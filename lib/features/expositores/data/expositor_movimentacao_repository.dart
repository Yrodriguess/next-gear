import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_collections.dart';
import '../domain/expositor_movimentacao.dart';

class ExpositorMovimentacaoRepository {
  final FirebaseFirestore _firestore;

  ExpositorMovimentacaoRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(FirestoreCollections.expositorMovimentacoes);

  Stream<List<ExpositorMovimentacao>> watchDoExpositor(
      String orgId, String expositorId) {
    return _collection
        .where('orgId', isEqualTo: orgId)
        .where('expositorId', isEqualTo: expositorId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => ExpositorMovimentacao.fromFirestore(d.id, d.data()))
            .toList());
  }

  /// As movimentações mais recentes de TODOS os expositores da
  /// organização — usado no relatório consolidado (não filtra por um
  /// expositor específico, diferente de watchDoExpositor).
  Stream<List<ExpositorMovimentacao>> watchRecentes(
    String orgId, {
    int limit = 50,
  }) {
    return _collection
        .where('orgId', isEqualTo: orgId)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => ExpositorMovimentacao.fromFirestore(d.id, d.data()))
            .toList());
  }
}
