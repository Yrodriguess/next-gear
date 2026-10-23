import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_collections.dart';
import '../domain/expositor_modelo.dart';

class ExpositorModeloRepository {
  final FirebaseFirestore _firestore;

  ExpositorModeloRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(FirestoreCollections.expositorModelos);

  Stream<List<ExpositorModelo>> watchAll(String orgId) {
    return _collection
        .where('orgId', isEqualTo: orgId)
        .orderBy('nome')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => ExpositorModelo.fromFirestore(d.id, d.data()))
            .toList());
  }

  Future<void> create(ExpositorModelo modelo) async {
    await _collection.add(modelo.toFirestore());
  }
}
