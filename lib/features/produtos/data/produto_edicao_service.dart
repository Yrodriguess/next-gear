import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_collections.dart';
import '../domain/produto.dart';
import '../domain/sku.dart';
import 'produto_cadastro_service.dart' show GtinDuplicadoException;
import 'produto_imagem_service.dart';
import 'sku_repository.dart';

/// O que fazer com a foto ao salvar uma edição.
enum AcaoFoto { manter, trocar, remover }

/// Coordena a edição de um Produto + seu SKU como uma operação só —
/// mesma lógica de atomicidade do ProdutoCadastroService, agora pra
/// update: troca de GTIN libera a reserva antiga e cria a nova dentro
/// da mesma transação, e mudança de preço nunca sobrescreve o valor
/// anterior — sempre cria uma nova vigência (seção 7.7 do Blueprint).
class ProdutoEdicaoService {
  final FirebaseFirestore _firestore;
  final ProdutoImagemService _imagemService;

  ProdutoEdicaoService({
    FirebaseFirestore? firestore,
    SkuRepository? skuRepository,
    ProdutoImagemService? imagemService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _imagemService = imagemService ?? ProdutoImagemService();

  Future<void> atualizar({
    required Produto produto,
    required Sku sku,
    required AcaoFoto acaoFoto,
    Uint8List? fotoBytesNovos,
    required String? codigoBarrasAntigo,
    required int precoVendaAntigoCentavos,
  }) async {
    final produtoId = produto.id!;
    final skuId = sku.id!;

    String? fotoUrl = produto.fotoUrl;
    String? fotoStoragePath = produto.fotoStoragePath;

    if (acaoFoto == AcaoFoto.remover) {
      if (produto.fotoStoragePath != null) {
        await _imagemService.remover(
          produto.fotoStoragePath!,
        );
      }

      fotoUrl = null;
      fotoStoragePath = null;
    } else if (acaoFoto == AcaoFoto.trocar &&
        fotoBytesNovos != null) {
      // Não precisa apagar o arquivo antigo antes de subir o novo:
      // o caminho no Storage é determinístico por produto
      // (organizations/{orgId}/products/{produtoId}/foto.jpg),
      // então o upload novo sobrescreve o mesmo objeto.
      final upload = await _imagemService.upload(
        orgId: produto.orgId,
        produtoId: produtoId,
        bytes: fotoBytesNovos,
      );

      fotoUrl = upload.url;
      fotoStoragePath = upload.storagePath;
    }

    // AcaoFoto.manter:
    // fotoUrl/fotoStoragePath permanecem como já vieram.

    // Constrói o objeto final manualmente porque precisamos permitir
    // fotoUrl/fotoStoragePath como null quando a foto for removida.
    final produtoFinal = Produto(
      id: produto.id,
      orgId: produto.orgId,
      descricao: produto.descricao,
      categoria: produto.categoria,
      modelo: produto.modelo,
      fabricante: produto.fabricante,
      fotoUrl: fotoUrl,
      fotoStoragePath: fotoStoragePath,
    );

    final codigoBarrasNovo = sku.codigoBarras;
    final gtinMudou =
        codigoBarrasNovo != codigoBarrasAntigo;

    DocumentReference<Map<String, dynamic>>? barcodeRefNovo;

    if (gtinMudou &&
        codigoBarrasNovo != null &&
        codigoBarrasNovo.isNotEmpty) {
      barcodeRefNovo = _firestore
          .collection(
        FirestoreCollections.skuBarcodes,
      )
          .doc(
        '${produto.orgId}_$codigoBarrasNovo',
      );
    }

    await _firestore.runTransaction(
          (transaction) async {
        // Leitura sempre antes de qualquer escrita,
        // exigência do Firestore para transações.
        if (barcodeRefNovo != null) {
          final existente =
          await transaction.get(barcodeRefNovo);

          if (existente.exists) {
            throw GtinDuplicadoException(
              codigoBarrasNovo!,
            );
          }
        }

        final produtoRef = _firestore
            .collection(
          FirestoreCollections.produtos,
        )
            .doc(produtoId);

        transaction.update(
          produtoRef,
          produtoFinal.toFirestore(),
        );

        final skuRef = _firestore
            .collection(
          FirestoreCollections.skus,
        )
            .doc(skuId);

        transaction.update(
          skuRef,
          sku.toFirestore(),
        );

        if (gtinMudou) {
          if (codigoBarrasAntigo != null &&
              codigoBarrasAntigo.isNotEmpty) {
            final barcodeRefAntigo = _firestore
                .collection(
              FirestoreCollections.skuBarcodes,
            )
                .doc(
              '${produto.orgId}_$codigoBarrasAntigo',
            );

            transaction.delete(
              barcodeRefAntigo,
            );
          }

          if (barcodeRefNovo != null) {
            transaction.set(
              barcodeRefNovo,
              {
                'orgId': produto.orgId,
                'skuId': skuId,
                'codigoBarras': codigoBarrasNovo,
              },
            );
          }
        }

        if (sku.precoVendaCentavos !=
            precoVendaAntigoCentavos) {
          final precoRef = _firestore
              .collection(
            FirestoreCollections.skuPrecos,
          )
              .doc();

          transaction.set(
            precoRef,
            {
              'orgId': produto.orgId,
              'skuId': skuId,
              'precoVendaCentavos':
              sku.precoVendaCentavos,
              'vigenteDesde':
              FieldValue.serverTimestamp(),
            },
          );
        }
      },
    );
  }
}