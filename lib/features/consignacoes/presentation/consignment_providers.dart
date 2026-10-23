import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/consignment_repository.dart';
import '../domain/consignment.dart';

final consignmentRepositoryProvider = Provider<ConsignmentRepository>((ref) {
  return ConsignmentRepository();
});

/// A consignação ativa de um cliente específico — cuidado: ambíguo se
/// o cliente tiver mais de um expositor (ver comentário no
/// repositório). Mantido pra quem precisa só do total do cliente.
final consignmentAtivaProvider =
StreamProvider.family<Consignment?, String>((ref, clienteId) {
  return ref
      .watch(consignmentRepositoryProvider)
      .watchAtivaDoCliente(clienteId);
});

/// TODAS as consignações ativas de um cliente — usar essa (não a de
/// cima) sempre que precisar saber se o cliente tem mais de um
/// expositor instalado ao mesmo tempo.
final consignmentsTodasAtivasDoClienteProvider =
StreamProvider.family<List<Consignment>, String>((ref, clienteId) {
  return ref
      .watch(consignmentRepositoryProvider)
      .watchTodasAtivasDoCliente(clienteId);
});

/// A consignação ativa de UM expositor específico — usar esse na
/// ficha do expositor, não o de cima, justamente pra não misturar
/// consignações quando o cliente tem mais de uma unidade.
final consignmentAtivaDoExpositorProvider =
StreamProvider.family<Consignment?, String>((ref, expositorId) {
  return ref
      .watch(consignmentRepositoryProvider)
      .watchAtivaDoExpositor(expositorId);
});

final consignmentHistoricoProvider =
StreamProvider.family<List<Consignment>, String>((ref, clienteId) {
  return ref
      .watch(consignmentRepositoryProvider)
      .watchHistoricoDoCliente(clienteId);
});

/// Todas as consignações ativas da organização — base do relatório
/// de aging (seção 9.1 do Blueprint).
final consignmentsAtivasProvider =
StreamProvider.family<List<Consignment>, String>((ref, orgId) {
  return ref.watch(consignmentRepositoryProvider).watchTodasAtivas(orgId);
});
