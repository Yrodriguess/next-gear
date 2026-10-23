import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_collections.dart';
import '../domain/consignment.dart';
import '../domain/consignment_item.dart';

class ConsignmentRepository {
  final FirebaseFirestore _firestore;

  ConsignmentRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(FirestoreCollections.consignments);

  /// A consignação ativa de um cliente — cuidado: se o cliente tiver
  /// mais de um expositor instalado, isso retorna UMA delas de forma
  /// arbitrária (o Firestore não garante qual). Pra saber a
  /// consignação de uma unidade específica, usa watchAtivaDoExpositor.
  /// Mantido por compatibilidade com quem só precisa do total do
  /// cliente como um todo.
  Stream<Consignment?> watchAtivaDoCliente(String clienteId) {
    return _collection
        .where('clienteId', isEqualTo: clienteId)
        .where('status', isEqualTo: 'ativa')
        .limit(1)
        .snapshots()
        .map((snap) => snap.docs.isEmpty
        ? null
        : Consignment.fromFirestore(snap.docs.first.id, snap.docs.first.data()));
  }

  /// TODAS as consignações ativas de um cliente — usar essa (não
  /// watchAtivaDoCliente) sempre que precisar decidir o que fazer
  /// dependendo de quantos expositores o cliente tem instalados.
  Stream<List<Consignment>> watchTodasAtivasDoCliente(String clienteId) {
    return _collection
        .where('clienteId', isEqualTo: clienteId)
        .where('status', isEqualTo: 'ativa')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Consignment.fromFirestore(d.id, d.data())).toList());
  }

  /// A consignação ativa de UM expositor específico — a consulta
  /// certa pra usar na ficha do expositor, porque não depende de
  /// quantos outros expositores o mesmo cliente também tenha.
  Stream<Consignment?> watchAtivaDoExpositor(String expositorId) {
    return _collection
        .where('expositorId', isEqualTo: expositorId)
        .where('status', isEqualTo: 'ativa')
        .limit(1)
        .snapshots()
        .map((snap) => snap.docs.isEmpty
        ? null
        : Consignment.fromFirestore(snap.docs.first.id, snap.docs.first.data()));
  }

  /// Todas as consignações ativas da organização — base do relatório
  /// de aging (seção 9.1 do Blueprint): quanto tempo cada uma está
  /// parada, calculado a partir de criadaEm.
  Stream<List<Consignment>> watchTodasAtivas(String orgId) {
    return _collection
        .where('orgId', isEqualTo: orgId)
        .where('status', isEqualTo: 'ativa')
        .snapshots()
        .map((snap) =>
        snap.docs.map((d) => Consignment.fromFirestore(d.id, d.data())).toList());
  }

  Stream<List<Consignment>> watchHistoricoDoCliente(String clienteId) {
    return _collection
        .where('clienteId', isEqualTo: clienteId)
        .orderBy('criadaEm', descending: true)
        .snapshots()
        .map((snap) =>
        snap.docs.map((d) => Consignment.fromFirestore(d.id, d.data())).toList());
  }

  Future<String> _gerarProximoNumero(String orgId) async {
    final counterRef = _firestore.collection('counters').doc('consignments_$orgId');

    final novoNumero = await _firestore.runTransaction<int>((transaction) async {
      final snapshot = await transaction.get(counterRef);
      final atual = (snapshot.data()?['seq'] as int?) ?? 0;
      final proximo = atual + 1;
      transaction.set(counterRef, {'seq': proximo});
      return proximo;
    });

    return 'CON-${novoNumero.toString().padLeft(5, '0')}';
  }

  /// Primeira consignação de um cliente (instalação) — não fecha nada,
  /// só abre. Ver seção 7.5 do Blueprint (tipo de evento "Instalação").
  Future<String> criarInicial({
    required String orgId,
    required String clienteId,
    required List<ConsignmentItem> itens,
    required String visitaId,
    String? expositorId,
  }) async {
    final numero = await _gerarProximoNumero(orgId);
    final docRef = _collection.doc();

    await docRef.set({
      'orgId': orgId,
      'numero': numero,
      'clienteId': clienteId,
      'expositorId': expositorId,
      'status': 'ativa',
      'itens': itens.map((i) => i.toMap()).toList(),
      'criadaEm': FieldValue.serverTimestamp(),
      'encerradaEm': null,
      'visitaQueAbriuId': visitaId,
      'visitaQueEncerrouId': null,
    });

    return numero;
  }

  /// O coração do módulo — ver seção 7.2 do Blueprint: encerra a
  /// consignação ativa e cria a nova numa única transação atômica.
  /// Nunca editar a consignação antiga; ela vira histórico permanente.
  /// expositorId é carregado adiante pra nova consignação — é o mesmo
  /// expositor físico, só mudou o ciclo de mercadoria.
  Future<String> encerrarEAbrirNova({
    required String orgId,
    required String clienteId,
    required String consignmentAtivaId,
    required List<ConsignmentItem> novosItens,
    required String visitaId,
    String? expositorId,
  }) async {
    final numero = await _gerarProximoNumero(orgId);
    final novaRef = _collection.doc();
    final antigaRef = _collection.doc(consignmentAtivaId);

    await _firestore.runTransaction((transaction) async {
      transaction.update(antigaRef, {
        'status': 'encerrada',
        'encerradaEm': FieldValue.serverTimestamp(),
        'visitaQueEncerrouId': visitaId,
      });

      transaction.set(novaRef, {
        'orgId': orgId,
        'numero': numero,
        'clienteId': clienteId,
        'expositorId': expositorId,
        'status': 'ativa',
        'itens': novosItens.map((i) => i.toMap()).toList(),
        'criadaEm': FieldValue.serverTimestamp(),
        'encerradaEm': null,
        'visitaQueAbriuId': visitaId,
        'visitaQueEncerrouId': null,
      });
    });

    return numero;
  }

  /// Encerra a consignação quando o expositor é retirado do cliente
  /// — corrige um gap real: antes, retirar um expositor não encerrava
  /// a consignação vinculada, deixando ela "ativa pra sempre" mesmo
  /// sem o expositor mais estar lá. Diferente de encerrarSemNova, não
  /// exige visitaId porque a retirada não passa necessariamente por
  /// uma visita.
  ///
  /// ⚠️ Limitação conhecida: hoje isso encerra sem conferência prévia
  /// — tudo que estava consignado é tratado como "devolvido", sem
  /// registrar quanto foi vendido antes da retirada. Um fluxo de
  /// conferência-na-retirada (Termo de Retirada e Encerramento) é
  /// trabalho futuro.
  Future<void> encerrarPorRetirada({
    required String consignmentAtivaId,
    String? observacao,
  }) {
    return _collection.doc(consignmentAtivaId).update({
      'status': 'encerrada',
      'encerradaEm': FieldValue.serverTimestamp(),
    });
  }

  /// Encerra sem abrir nova — usado quando o cliente fica inadimplente
  /// sem mercadoria restante, ou no encerramento formal do cliente
  /// (ver seção 7.2 do Blueprint).
  Future<void> encerrarSemNova({
    required String consignmentAtivaId,
    required String visitaId,
  }) {
    return _collection.doc(consignmentAtivaId).update({
      'status': 'encerrada',
      'encerradaEm': FieldValue.serverTimestamp(),
      'visitaQueEncerrouId': visitaId,
    });
  }
}
