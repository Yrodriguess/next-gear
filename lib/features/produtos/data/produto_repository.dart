import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_collections.dart';
import '../domain/produto.dart';

/// Leitura de produtos. A criação agora sempre envolve o primeiro SKU
/// (e possivelmente uma foto) numa única operação — ver
/// produto_cadastro_service.dart.
class ProdutoRepository {
  final FirebaseFirestore _firestore;

  ProdutoRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(FirestoreCollections.produtos);

  Stream<List<Produto>> watchAll(String orgId) {
    return _collection
        .where('orgId', isEqualTo: orgId)
        .orderBy('descricao')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Produto.fromFirestore(d.id, d.data())).toList());
  }

  Stream<Produto?> watchById(String produtoId) {
    return _collection.doc(produtoId).snapshots().map(
        (doc) => doc.exists ? Produto.fromFirestore(doc.id, doc.data()!) : null);
  }
}
