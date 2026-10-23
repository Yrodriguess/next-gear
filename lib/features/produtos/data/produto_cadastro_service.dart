import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_collections.dart';
import '../domain/produto.dart';
import '../domain/sku.dart';
import 'produto_imagem_service.dart';
import 'sku_repository.dart';

/// Erro específico de GTIN/EAN duplicado.
/// Permite à tela mostrar uma mensagem exata em vez do erro genérico
/// de "não foi possível salvar".
class GtinDuplicadoException implements Exception {
  final String codigoBarras;

  const GtinDuplicadoException(this.codigoBarras);

  @override
  String toString() =>
      'Já existe um SKU cadastrado com o GTIN/EAN '
          '$codigoBarras nesta organização.';
}

/// Orquestra o cadastro de um Produto + seu primeiro SKU como uma
/// operação única do ponto de vista do usuário.
///
/// Upload de imagem é uma chamada externa ao Storage e não pode entrar
/// numa transação do Firestore, então a ordem é:
///
/// 1. Reserva os IDs de Produto e SKU.
/// 2. Sobe a foto, se houver.
/// 3. Gera automaticamente o código de barras interno NEXT GEAR.
/// 4. Roda uma transação que:
///    - confere se o GTIN/EAN do fornecedor já existe;
///    - grava Produto;
///    - grava SKU;
///    - grava o primeiro registro de preço;
///    - reserva o GTIN/EAN do fornecedor.
/// 5. Se a transação falhar, remove a imagem já enviada ao Storage.
///
/// O código de barras interno é gerado automaticamente pelo sistema e
/// não depende de o produto possuir GTIN/EAN do fabricante.
///
/// REGRA NEXT GEAR:
/// O estoque dos produtos é controlado exclusivamente por quantidade.
/// Não utilizamos lote nem número de série.
class ProdutoCadastroService {
  final FirebaseFirestore _firestore;
  final SkuRepository _skuRepository;
  final ProdutoImagemService _imagemService;

  ProdutoCadastroService({
    FirebaseFirestore? firestore,
    SkuRepository? skuRepository,
    ProdutoImagemService? imagemService,
  })  : _firestore =
      firestore ?? FirebaseFirestore.instance,
        _skuRepository =
            skuRepository ?? SkuRepository(),
        _imagemService =
            imagemService ?? ProdutoImagemService();

  Future<String> criar({
    required Produto produto,
    required Sku primeiroSku,
    Uint8List? fotoBytes,
  }) async {
    // Reserva os IDs antes de escrever para:
    // - usar o ID do produto no caminho da foto;
    // - referenciar corretamente o SKU;
    // - manter toda a criação vinculada aos mesmos IDs.
    final produtoRef = _firestore
        .collection(FirestoreCollections.produtos)
        .doc();

    final skuRef = _firestore
        .collection(FirestoreCollections.skus)
        .doc();

    String? fotoUrl;
    String? fotoStoragePath;

    // =========================================================
    // FOTO
    // =========================================================

    if (fotoBytes != null) {
      final upload = await _imagemService.upload(
        orgId: produto.orgId,
        produtoId: produtoRef.id,
        bytes: fotoBytes,
      );

      fotoUrl = upload.url;
      fotoStoragePath = upload.storagePath;
    }

    // =========================================================
    // CÓDIGO INTERNO NEXT GEAR
    // =========================================================

    // Gera automaticamente o código de barras interno.
    //
    // Exemplo:
    // 2000000000015
    //
    // O usuário não digita esse código.
    final codigoBarrasInterno =
    await _skuRepository.gerarProximoCodigoBarrasInterno(
      produto.orgId,
    );

    // =========================================================
    // GTIN / EAN DO FABRICANTE
    // =========================================================

    final codigoBarras =
    primeiroSku.codigoBarras?.trim();

    // Documento auxiliar usado para impedir que o mesmo GTIN/EAN
    // seja cadastrado duas vezes dentro da mesma organização.
    final barcodeRef =
    (codigoBarras != null && codigoBarras.isNotEmpty)
        ? _firestore
        .collection(
      FirestoreCollections.skuBarcodes,
    )
        .doc(
      '${produto.orgId}_$codigoBarras',
    )
        : null;

    try {
      await _firestore.runTransaction(
            (transaction) async {
          // =====================================================
          // VERIFICA GTIN/EAN DUPLICADO
          // =====================================================

          // Toda leitura da transação precisa acontecer antes
          // das escritas.
          if (barcodeRef != null) {
            final existente =
            await transaction.get(barcodeRef);

            if (existente.exists) {
              throw GtinDuplicadoException(
                codigoBarras!,
              );
            }
          }

          // =====================================================
          // PRODUTO
          // =====================================================

          transaction.set(
            produtoRef,
            produto
                .copyWith(
              fotoUrl: fotoUrl,
              fotoStoragePath:
              fotoStoragePath,
            )
                .toFirestore(),
          );

          // =====================================================
          // PRIMEIRO SKU
          // =====================================================

          // No cadastro inicial:
          //
          // custoInicial = custo informado pelo usuário
          // custoMedio = custo inicial
          // custoUltimaCompra = custo inicial
          //
          // O controle de estoque da NEXT GEAR é exclusivamente
          // por quantidade.
          //
          // Não utilizamos:
          // - lote;
          // - número de série.
          //
          // Depois, novas entradas de compra passam a recalcular
          // automaticamente:
          //
          // - custoMedioCentavos;
          // - custoUltimaCompraCentavos.
          final skuInicial =
          primeiroSku.copyWith(
            produtoId: produtoRef.id,

            codigoBarrasInterno:
            codigoBarrasInterno,

            trackingMode:
            TrackingMode.quantity,

            custoMedioCentavos:
            primeiroSku
                .custoInicialCentavos,

            custoUltimaCompraCentavos:
            primeiroSku
                .custoInicialCentavos,
          );

          transaction.set(
            skuRef,
            skuInicial.toFirestore(),
          );

          // =====================================================
          // PRIMEIRO PREÇO
          // =====================================================

          // Primeiro registro da tabela de preço com vigência.
          //
          // O histórico completo de alterações de preço continua
          // separado em skuPrecos.
          final precoRef = _firestore
              .collection(
            FirestoreCollections.skuPrecos,
          )
              .doc();

          transaction.set(
            precoRef,
            {
              'orgId': produto.orgId,
              'skuId': skuRef.id,
              'precoVendaCentavos':
              primeiroSku
                  .precoVendaCentavos,
              'vigenteDesde':
              FieldValue.serverTimestamp(),
            },
          );

          // =====================================================
          // RESERVA DO GTIN / EAN
          // =====================================================

          if (barcodeRef != null) {
            transaction.set(
              barcodeRef,
              {
                'orgId': produto.orgId,
                'skuId': skuRef.id,
                'codigoBarras':
                codigoBarras,
              },
            );
          }
        },
      );
    } catch (e) {
      // =========================================================
      // LIMPEZA DE FOTO EM CASO DE ERRO
      // =========================================================

      // Se a criação no Firestore falhar, remove a foto já enviada
      // para não deixar arquivo órfão no Storage.
      if (fotoStoragePath != null) {
        await _imagemService.remover(
          fotoStoragePath,
        );
      }

      rethrow;
    }

    return produtoRef.id;
  }
}