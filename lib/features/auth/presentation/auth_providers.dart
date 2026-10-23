import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_collections.dart';
import '../data/auth_repository.dart';
import '../data/usuario_repository.dart';
import '../domain/app_user.dart';

/// Instância única do repositório, compartilhada pelo app inteiro.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

/// Emite o usuário do Firebase Auth toda vez que o login muda.
/// null significa "deslogado".
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

/// Busca o AppUser (com role, nome, orgId) sempre que o Firebase User mudar.
/// É esse provider que as telas devem observar pra saber o papel de quem
/// está logado — nunca confiar só no Firebase Auth puro.
final appUserProvider = FutureProvider<AppUser?>((ref) async {
  final firebaseUser = ref.watch(authStateProvider).value;
  if (firebaseUser == null) return null;
  return ref.watch(authRepositoryProvider).fetchAppUser(firebaseUser.uid);
});

final usuarioRepositoryProvider = Provider<UsuarioRepository>((ref) {
  return UsuarioRepository();
});

final usuariosListProvider =
StreamProvider.family<List<AppUser>, String>((ref, orgId) {
  return ref.watch(usuarioRepositoryProvider).watchTodos(orgId);
});