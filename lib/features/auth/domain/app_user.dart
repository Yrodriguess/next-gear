import 'package:cloud_firestore/cloud_firestore.dart';

enum UserRole { admin, financeiro, vendedor, estoque, cliente }

UserRole userRoleFromString(String value) {
  return UserRole.values.firstWhere(
        (r) => r.name == value,
    orElse: () => UserRole.vendedor,
  );
}

class AppUser {
  final String uid;
  final String email;
  final String nome;
  final UserRole role;
  final String orgId;

  /// Define se o usuário pode acessar o sistema.
  final bool ativo;

  /// Data em que o usuário foi criado.
  final DateTime? createdAt;

  const AppUser({
    required this.uid,
    required this.email,
    required this.nome,
    required this.role,
    required this.orgId,
    this.ativo = true,
    this.createdAt,
  });

  factory AppUser.fromFirestore(
      String uid,
      Map<String, dynamic> data,
      ) {
    final createdAt = data['createdAt'];

    return AppUser(
      uid: uid,
      email: data['email'] as String? ?? '',
      nome: data['nome'] as String? ?? '',
      role: userRoleFromString(
        data['role'] as String? ?? 'vendedor',
      ),
      orgId: data['orgId'] as String? ?? '',

      // Usuários antigos que ainda não possuem o campo
      // continuam ativos normalmente.
      ativo: data['ativo'] as bool? ?? true,

      createdAt: createdAt is Timestamp
          ? createdAt.toDate()
          : null,
    );
  }
}