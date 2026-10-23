import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/acerto_caixa_repository.dart';
import '../data/pagamento_repository.dart';
import '../data/recebivel_repository.dart';
import '../domain/acerto_caixa.dart';
import '../domain/pagamento.dart';
import '../domain/recebivel.dart';

final recebivelRepositoryProvider = Provider<RecebivelRepository>((ref) {
  return RecebivelRepository();
});

final pagamentoRepositoryProvider = Provider<PagamentoRepository>((ref) {
  return PagamentoRepository();
});

final acertoCaixaRepositoryProvider = Provider<AcertoCaixaRepository>((ref) {
  return AcertoCaixaRepository(
    pagamentoRepository: ref.watch(pagamentoRepositoryProvider),
  );
});

// ── Recebíveis (Contas a Receber) ─────────────────────────────────

final recebiveisDoClienteProvider =
StreamProvider.family<List<Recebivel>, String>((ref, clienteId) {
  return ref.watch(recebivelRepositoryProvider).watchDoCliente(clienteId);
});

final recebiveisEmAbertoProvider =
StreamProvider.family<List<Recebivel>, String>((ref, clienteId) {
  return ref.watch(recebivelRepositoryProvider).watchEmAbertoDoCliente(clienteId);
});

/// Todos os recebíveis em aberto da organização, juntos — painel e
/// tela "Contas a receber" geral do menu Financeiro.
final recebiveisTodosAbertosProvider =
StreamProvider.family<List<Recebivel>, String>((ref, orgId) {
  return ref.watch(recebivelRepositoryProvider).watchTodosAbertos(orgId);
});

/// Todos os recebíveis da organização, sem filtro — histórico/relatório.
final recebiveisTodosProvider =
StreamProvider.family<List<Recebivel>, String>((ref, orgId) {
  return ref.watch(recebivelRepositoryProvider).watchTodos(orgId);
});

// ── Pagamentos ─────────────────────────────────────────────────────

/// Pagamentos em dinheiro pendentes de repasse de um vendedor — tela
/// "Meu caixa".
final pagamentosPendentesRepasseProvider =
StreamProvider.family<List<Pagamento>, String>((ref, vendedorId) {
  return ref.watch(pagamentoRepositoryProvider).watchPendentesRepasse(vendedorId);
});

/// Todos os pagamentos da organização, mais recentes primeiro —
/// histórico geral do menu Financeiro.
final pagamentosTodosProvider =
StreamProvider.family<List<Pagamento>, String>((ref, orgId) {
  return ref.watch(pagamentoRepositoryProvider).watchTodos(orgId);
});

// ── Acertos de caixa ───────────────────────────────────────────────

/// Fila do financeiro — acertos declarados pelos vendedores,
/// aguardando confirmação.
final acertosPendentesConfirmacaoProvider =
StreamProvider.family<List<AcertoCaixa>, String>((ref, orgId) {
  return ref.watch(acertoCaixaRepositoryProvider).watchPendentesConfirmacao(orgId);
});

/// Histórico de acertos de um vendedor específico.
final meusAcertosCaixaProvider =
StreamProvider.family<List<AcertoCaixa>, String>((ref, vendedorId) {
  return ref.watch(acertoCaixaRepositoryProvider).watchMeusAcertos(vendedorId);
});

/// Todos os acertos da organização — histórico/relatório geral.
final acertosCaixaTodosProvider =
StreamProvider.family<List<AcertoCaixa>, String>((ref, orgId) {
  return ref.watch(acertoCaixaRepositoryProvider).watchTodos(orgId);
});
