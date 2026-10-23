import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_collections.dart';
import '../domain/recebivel.dart';

class RecebivelRepository {
  final FirebaseFirestore _firestore;

  RecebivelRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(FirestoreCollections.contasAReceber);

  Stream<List<Recebivel>> watchDoCliente(String clienteId) {
    return _collection
        .where('clienteId', isEqualTo: clienteId)
        .orderBy('criadoEm', descending: true)
        .snapshots()
        .map((snap) =>
        snap.docs.map((d) => Recebivel.fromFirestore(d.id, d.data())).toList());
  }

  /// Todos os recebíveis em aberto ou parcial de um cliente — usado
  /// pra calcular a "exposição" real (mercadoria + a receber, seção
  /// 5.3 do Blueprint) e pra saber se ele está inadimplente.
  Stream<List<Recebivel>> watchEmAbertoDoCliente(String clienteId) {
    return _collection
        .where('clienteId', isEqualTo: clienteId)
        .where('status', whereIn: ['aberto', 'parcial', 'vencido'])
        .snapshots()
        .map((snap) =>
        snap.docs.map((d) => Recebivel.fromFirestore(d.id, d.data())).toList());
  }

  /// Todos os recebíveis em aberto/parcial/vencido da organização
  /// inteira, juntos — alimenta a tela "Contas a receber" geral do
  /// menu Financeiro (não mais só por cliente).
  Stream<List<Recebivel>> watchTodosAbertos(String orgId) {
    return _collection
        .where('orgId', isEqualTo: orgId)
        .where('status', whereIn: ['aberto', 'parcial', 'vencido'])
        .orderBy('dataVencimento')
        .snapshots()
        .map((snap) =>
        snap.docs.map((d) => Recebivel.fromFirestore(d.id, d.data())).toList());
  }

  /// Todos os recebíveis da organização, sem filtro de status — pra
  /// relatório/exportação e pro histórico completo.
  Stream<List<Recebivel>> watchTodos(String orgId) {
    return _collection
        .where('orgId', isEqualTo: orgId)
        .orderBy('criadoEm', descending: true)
        .snapshots()
        .map((snap) =>
        snap.docs.map((d) => Recebivel.fromFirestore(d.id, d.data())).toList());
  }

  Future<String> _gerarProximoNumero(String orgId) async {
    final counterRef = _firestore.collection('counters').doc('recebiveis_$orgId');
    final novoNumero = await _firestore.runTransaction<int>((transaction) async {
      final snapshot = await transaction.get(counterRef);
      final atual = (snapshot.data()?['seq'] as int?) ?? 0;
      final proximo = atual + 1;
      transaction.set(counterRef, {'seq': proximo});
      return proximo;
    });
    return 'COB-${novoNumero.toString().padLeft(6, '0')}';
  }

  /// Cria a cobrança a partir do valor apurado numa visita — ver
  /// seção 8.2 e 15.1 do Blueprint. Só é chamado quando há venda
  /// apurada (valorCentavos > 0).
  Future<String> criarAPartirDaVisita({
    required String orgId,
    required String clienteId,
    required String visitaId,
    required int valorCentavos,
    required int prazoAcertoDias,
  }) async {
    final numero = await _gerarProximoNumero(orgId);
    final vencimento = DateTime.now().add(Duration(days: prazoAcertoDias));

    await _collection.add({
      'orgId': orgId,
      'numero': numero,
      'clienteId': clienteId,
      'visitaId': visitaId,
      'valorCentavos': valorCentavos,
      'valorPagoCentavos': 0,
      'status': statusToString(RecebivelStatus.aberto),
      'dataVencimento': vencimento,
      'criadoEm': FieldValue.serverTimestamp(),
    });

    return numero;
  }
}
