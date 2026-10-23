import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_collections.dart';
import '../domain/sku.dart';

class SkuRepository {
  final FirebaseFirestore _firestore;

  SkuRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(FirestoreCollections.skus);

  Stream<List<Sku>> watchByProduto(String produtoId) {
    return _collection
        .where('produtoId', isEqualTo: produtoId)
        .orderBy('codigoBarrasInterno')
        .snapshots()
        .map(
          (snap) => snap.docs
          .map((d) => Sku.fromFirestore(d.id, d.data()))
          .toList(),
    );
  }

  /// Leitura única (não-stream) dos SKUs de um produto — usada em
  /// ações pontuais, como decidir pra onde navegar ao tocar num
  /// produto na lista (direto pro único SKU, ou escolher a variação).
  Future<List<Sku>> fetchByProduto(String produtoId) async {
    final snap = await _collection
        .where('produtoId', isEqualTo: produtoId)
        .orderBy('codigoBarrasInterno')
        .get();

    return snap.docs
        .map((d) => Sku.fromFirestore(d.id, d.data()))
        .toList();
  }

  Stream<Sku?> watchById(String skuId) {
    return _collection.doc(skuId).snapshots().map(
          (doc) => doc.exists
          ? Sku.fromFirestore(doc.id, doc.data()!)
          : null,
    );
  }

  Future<void> update(String skuId, Sku sku) {
    return _collection.doc(skuId).update(sku.toFirestore());
  }

  /// Todos os SKUs da organização — usado nas telas de estoque, que
  /// selecionam/exibem o SKU (a unidade que de fato se movimenta),
  /// não o Produto genérico.
  Stream<List<Sku>> watchAll(String orgId) {
    return _collection
        .where('orgId', isEqualTo: orgId)
        .orderBy('codigoBarrasInterno')
        .snapshots()
        .map(
          (snap) => snap.docs
          .map((d) => Sku.fromFirestore(d.id, d.data()))
          .toList(),
    );
  }

  /// Gera o próximo código de barras interno da NEXT GEAR.
  ///
  /// Estrutura:
  /// 20 + sequencial de 10 dígitos + dígito verificador
  ///
  /// Exemplos:
  /// 2000000000015
  /// 2000000000022
  /// 2000000000039
  ///
  /// O contador é incrementado dentro de uma transação do Firestore
  /// para impedir que dois cadastros simultâneos recebam o mesmo
  /// número sequencial.
  Future<String> gerarProximoCodigoBarrasInterno(
      String orgId,
      ) async {
    final counterRef = _firestore
        .collection(FirestoreCollections.counters)
        .doc('skus_$orgId');

    final novoNumero =
    await _firestore.runTransaction<int>(
          (transaction) async {
        final snapshot =
        await transaction.get(counterRef);

        final atual =
            (snapshot.data()?['seq'] as int?) ?? 0;

        final proximo = atual + 1;

        if (proximo > 9999999999) {
          throw StateError(
            'Limite de códigos de barras internos atingido.',
          );
        }

        transaction.set(
          counterRef,
          {
            'seq': proximo,
          },
          SetOptions(merge: true),
        );

        return proximo;
      },
    );

    final sequencial =
    novoNumero.toString().padLeft(10, '0');

    // Base com 12 dígitos:
    // 20 + 0000000001 = 200000000001
    final base = '20$sequencial';

    final digitoVerificador =
    _calcularDigitoVerificadorEan13(base);

    return '$base$digitoVerificador';
  }

  /// Compatibilidade temporária com chamadas antigas.
  ///
  /// Novos códigos devem chamar
  /// [gerarProximoCodigoBarrasInterno].
  @Deprecated('Use gerarProximoCodigoBarrasInterno')
  Future<String> gerarProximoCodigo(String orgId) {
    return gerarProximoCodigoBarrasInterno(orgId);
  }

  /// Calcula o dígito verificador pelo algoritmo Módulo 10
  /// utilizado no formato EAN-13.
  ///
  /// [base] deve possuir exatamente 12 dígitos.
  int _calcularDigitoVerificadorEan13(String base) {
    if (base.length != 12 ||
        !RegExp(r'^\d{12}$').hasMatch(base)) {
      throw ArgumentError(
        'A base do código interno deve possuir exatamente 12 dígitos.',
      );
    }

    var soma = 0;

    for (var i = 0; i < base.length; i++) {
      final digito = int.parse(base[i]);

      soma += i.isEven
          ? digito
          : digito * 3;
    }

    return (10 - (soma % 10)) % 10;
  }

  /// Impede duplicidade de GTIN/EAN do fabricante/fornecedor dentro
  /// da mesma organização.
  ///
  /// Na edição, passe [excluirSkuId] com o próprio SKU sendo editado,
  /// senão ele se acusa como duplicado quando o código não mudou.
  Future<bool> existeCodigoBarras(
      String orgId,
      String codigoBarras, {
        String? excluirSkuId,
      }) async {
    final resultado = await _collection
        .where('orgId', isEqualTo: orgId)
        .where('codigoBarras', isEqualTo: codigoBarras)
        .get();

    return resultado.docs.any(
          (d) => d.id != excluirSkuId,
    );
  }
}
