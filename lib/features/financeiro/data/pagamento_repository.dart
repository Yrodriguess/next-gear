import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_collections.dart';
import '../domain/pagamento.dart';
import '../domain/recebivel.dart';

class PagamentoRepository {
  final FirebaseFirestore _firestore;

  PagamentoRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _pagamentos =>
      _firestore.collection('payments');

  CollectionReference<Map<String, dynamic>> get _recebiveis =>
      _firestore.collection(FirestoreCollections.contasAReceber);

  /// Registra um pagamento e aloca automaticamente contra os
  /// recebíveis em aberto do cliente, do mais antigo pro mais novo —
  /// ver seção 15.1 do Blueprint (paymentAllocations). Se sobrar
  /// valor depois de quitar tudo, vira saldo a favor (não usado ainda
  /// em lugar nenhum, mas fica registrado no próprio pagamento).
  ///
  /// Pix/boleto nascem confirmados (statusRepasse). Dinheiro nasce
  /// pendente de repasse — só vira "confirmado" depois que o
  /// vendedor fecha o caixa do dia e o financeiro valida.
  ///
  /// [jaConfirmado]: use quando o FINANCEIRO está registrando um
  /// recebimento que já caiu direto (ex: cliente pagou um boleto, ou
  /// pagou em dinheiro direto no escritório) — nesse caso não existe
  /// vendedor segurando o dinheiro, então nasce confirmado mesmo que
  /// a forma seja "dinheiro".
  Future<void> registrarEAlocar({
    required String orgId,
    required String clienteId,
    required int valorTotalCentavos,
    String? observacao,
    FormaPagamento formaPagamento = FormaPagamento.dinheiro,
    String? vendedorId,
    bool jaConfirmado = false,
  }) async {
    final emAbertoSnapshot = await _recebiveis
        .where('clienteId', isEqualTo: clienteId)
        .where('status', whereIn: ['aberto', 'parcial', 'vencido'])
        .orderBy('criadoEm')
        .get();

    final statusRepasse = jaConfirmado || formaPagamento != FormaPagamento.dinheiro
        ? StatusRepasse.confirmado
        : StatusRepasse.pendenteRepasse;

    await _firestore.runTransaction((transaction) async {
      final alocacoes = <String, int>{};
      int restante = valorTotalCentavos;

      for (final doc in emAbertoSnapshot.docs) {
        if (restante <= 0) break;

        final recebivelRef = _recebiveis.doc(doc.id);
        final snapshot = await transaction.get(recebivelRef);
        if (!snapshot.exists) continue;

        final recebivel = Recebivel.fromFirestore(doc.id, snapshot.data()!);
        final saldoDevido = recebivel.saldoEmAbertoCentavos;
        if (saldoDevido <= 0) continue;

        final aplicado = restante >= saldoDevido ? saldoDevido : restante;
        alocacoes[doc.id] = aplicado;
        restante -= aplicado;

        final novoValorPago = recebivel.valorPagoCentavos + aplicado;
        final novoStatus = novoValorPago >= recebivel.valorCentavos
            ? RecebivelStatus.pago
            : RecebivelStatus.parcial;

        transaction.update(recebivelRef, {
          'valorPagoCentavos': novoValorPago,
          'status': statusToString(novoStatus),
        });
      }

      final pagamentoRef = _pagamentos.doc();
      transaction.set(pagamentoRef, {
        'orgId': orgId,
        'clienteId': clienteId,
        'valorTotalCentavos': valorTotalCentavos,
        'observacao': observacao,
        'alocacoes': alocacoes,
        'formaPagamento': formaPagamentoToString(formaPagamento),
        'vendedorId': vendedorId,
        'statusRepasse': statusRepasseToString(statusRepasse),
        'acertoCaixaId': null,
        'criadoEm': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Pagamentos em dinheiro que esse vendedor recebeu e ainda não
  /// incluiu em nenhum fechamento de caixa — é a lista que alimenta a
  /// tela "Meu caixa".
  Stream<List<Pagamento>> watchPendentesRepasse(String vendedorId) {
    return _pagamentos
        .where('vendedorId', isEqualTo: vendedorId)
        .where('formaPagamento',
        isEqualTo: formaPagamentoToString(FormaPagamento.dinheiro))
        .where('statusRepasse',
        isEqualTo: statusRepasseToString(StatusRepasse.pendenteRepasse))
        .orderBy('criadoEm')
        .snapshots()
        .map((snap) =>
        snap.docs.map((d) => Pagamento.fromFirestore(d.id, d.data())).toList());
  }

  /// Todos os pagamentos da organização, mais recentes primeiro —
  /// alimenta o histórico geral. Filtros (forma, vendedor, período)
  /// são aplicados no cliente, o volume não justifica índice composto
  /// ainda.
  Stream<List<Pagamento>> watchTodos(String orgId, {int limite = 200}) {
    return _pagamentos
        .where('orgId', isEqualTo: orgId)
        .orderBy('criadoEm', descending: true)
        .limit(limite)
        .snapshots()
        .map((snap) =>
        snap.docs.map((d) => Pagamento.fromFirestore(d.id, d.data())).toList());
  }

  /// Marca um lote de pagamentos como pertencentes a um AcertoCaixa —
  /// chamado dentro da transação de fechamento (ver AcertoCaixaRepository).
  void marcarComoRepassados(
      Transaction transaction, {
        required List<String> pagamentoIds,
        required String acertoCaixaId,
      }) {
    for (final id in pagamentoIds) {
      transaction.update(_pagamentos.doc(id), {
        'statusRepasse': statusRepasseToString(StatusRepasse.repassado),
        'acertoCaixaId': acertoCaixaId,
      });
    }
  }

  /// Marca um lote de pagamentos como confirmados pelo financeiro —
  /// chamado dentro da transação de confirmação do acerto.
  void marcarComoConfirmados(
      Transaction transaction, {
        required List<String> pagamentoIds,
      }) {
    for (final id in pagamentoIds) {
      transaction.update(_pagamentos.doc(id), {
        'statusRepasse': statusRepasseToString(StatusRepasse.confirmado),
      });
    }
  }
}
