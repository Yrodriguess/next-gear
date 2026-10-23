import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/current_org_provider.dart';
import '../data/cliente_repository.dart';
import '../domain/cliente.dart';

final clienteRepositoryProvider = Provider<ClienteRepository>((ref) {
  return ClienteRepository();
});

/// Lista de clientes da organização atual, em tempo real.
final clientesListProvider = StreamProvider<List<Cliente>>((ref) {
  final orgId = ref.watch(currentOrgIdProvider);
  if (orgId == null) return const Stream.empty();
  return ref.watch(clienteRepositoryProvider).watchAll(orgId);
});

/// Um cliente específico, em tempo real — útil pra tela de detalhe.
final clienteByIdProvider =
StreamProvider.family<Cliente?, String>((ref, clienteId) {
  return ref.watch(clienteRepositoryProvider).watchById(clienteId);
});
