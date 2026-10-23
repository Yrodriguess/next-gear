import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/acerto_caixa.dart';
import '../domain/pagamento.dart';
import 'pagamento_repository.dart';

class AcertoCaixaRepository {
  final FirebaseFirestore _firestore;
  final PagamentoRepository _pagamentoRepository;

  AcertoCaixaRepository({
    FirebaseFirestore? firestore,
    PagamentoRepository? pagamentoRepository,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _pagamentoRepository = pagamentoRepository ?? PagamentoRepository();

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('acertosCaixa');

  /// Fecha o caixa do dia — pega os pagamentos em dinheiro pendentes
  /// desse vendedor (já buscados via watchPendentesRepasse), monta o
  /// extrato detalhado por cliente e marca todos como "repassado" na
  /// mesma transação. Não movimenta o dinheiro de verdade — é a
  /// DECLARAÇÃO do vendedor; o financeiro confirma depois.
  Future<String> fecharCaixaDoDia({
    required String orgId,
    required String vendedorId,
    required List<Pagamento> pagamentosPendentes,
    required Map<String, String> nomeClientePorId,
    String? observacao,
  }) async {
    if (pagamentosPendentes.isEmpty) {
      throw ArgumentError('Não há nada pendente de repasse hoje.');
    }

    final itens = pagamentosPendentes
        .map((p) => AcertoCaixaItem(
              pagamentoId: p.id!,
              clienteId: p.clienteId,
              clienteNome: nomeClientePorId[p.clienteId] ?? 'Cliente',
              valorCentavos: p.valorTotalCentavos,
            ))
        .toList();

    final valorTotal =
        itens.fold<int>(0, (soma, item) => soma + item.valorCentavos);

    final acertoRef = _collection.doc();

    await _firestore.runTransaction((transaction) async {
      transaction.set(acertoRef, {
        'orgId': orgId,
        'vendedorId': vendedorId,
        'data': DateTime.now(),
        'itens': itens.map((i) => i.toMap()).toList(),
        'valorTotalCentavos': valorTotal,
        'status': statusAcertoCaixaToString(StatusAcertoCaixa.repassado),
        'observacao': observacao,
        'confirmadoPor': null,
        'confirmadoEm': null,
        'criadoEm': FieldValue.serverTimestamp(),
      });

      _pagamentoRepository.marcarComoRepassados(
        transaction,
        pagamentoIds: pagamentosPendentes.map((p) => p.id!).toList(),
        acertoCaixaId: acertoRef.id,
      );
    });

    return acertoRef.id;
  }

  /// O financeiro confirma que recebeu de verdade o valor declarado
  /// pelo vendedor — fecha o ciclo dos pagamentos incluídos nesse
  /// acerto.
  Future<void> confirmar({
    required String acertoCaixaId,
    required String usuarioId,
  }) async {
    final acertoRef = _collection.doc(acertoCaixaId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(acertoRef);
      if (!snapshot.exists) {
        throw Exception('Acerto de caixa não encontrado.');
      }
      final acerto = AcertoCaixa.fromFirestore(snapshot.id, snapshot.data()!);
      if (acerto.status == StatusAcertoCaixa.confirmado) {
        throw Exception('Esse acerto já foi confirmado.');
      }

      transaction.update(acertoRef, {
        'status': statusAcertoCaixaToString(StatusAcertoCaixa.confirmado),
        'confirmadoPor': usuarioId,
        'confirmadoEm': FieldValue.serverTimestamp(),
      });

      _pagamentoRepository.marcarComoConfirmados(
        transaction,
        pagamentoIds: acerto.itens.map((i) => i.pagamentoId).toList(),
      );
    });
  }

  /// Fila do financeiro — acertos declarados pelos vendedores,
  /// aguardando confirmação.
  Stream<List<AcertoCaixa>> watchPendentesConfirmacao(String orgId) {
    return _collection
        .where('orgId', isEqualTo: orgId)
        .where('status',
            isEqualTo: statusAcertoCaixaToString(StatusAcertoCaixa.repassado))
        .orderBy('criadoEm')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => AcertoCaixa.fromFirestore(d.id, d.data())).toList());
  }

  /// Histórico de acertos de um vendedor específico — pra ele
  /// acompanhar o que já fechou e o que já foi confirmado.
  Stream<List<AcertoCaixa>> watchMeusAcertos(String vendedorId) {
    return _collection
        .where('vendedorId', isEqualTo: vendedorId)
        .orderBy('criadoEm', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => AcertoCaixa.fromFirestore(d.id, d.data())).toList());
  }

  /// Todos os acertos da organização, mais recentes primeiro —
  /// alimenta relatório/histórico geral.
  Stream<List<AcertoCaixa>> watchTodos(String orgId) {
    return _collection
        .where('orgId', isEqualTo: orgId)
        .orderBy('criadoEm', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => AcertoCaixa.fromFirestore(d.id, d.data())).toList());
  }
}
