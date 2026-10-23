import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/current_org_provider.dart';
import '../data/usuario_repository.dart';
import '../domain/app_user.dart';

final usuarioRepositoryProvider = Provider<UsuarioRepository>((ref) {
  return UsuarioRepository();
});

/// Todos os usuários da organização atual — usado por telas que
/// precisam listar/selecionar pessoas.
final usuariosListProvider = StreamProvider<List<AppUser>>((ref) {
  final orgId = ref.watch(currentOrgIdProvider);
  if (orgId == null) return const Stream.empty();
  return ref.watch(usuarioRepositoryProvider).watchTodos(orgId);
});

/// Só os vendedores — usado no seletor de "vendedor responsável" do
/// cadastro de cliente (quando quem cadastra é admin/financeiro, que
/// pode escolher qualquer vendedor, diferente do próprio vendedor,
/// que já vem auto-preenchido).
final vendedoresListProvider = Provider<AsyncValue<List<AppUser>>>((ref) {
  final usuarios = ref.watch(usuariosListProvider);
  return usuarios.whenData(
    (lista) => lista.where((u) => u.role == UserRole.vendedor).toList(),
  );
});
