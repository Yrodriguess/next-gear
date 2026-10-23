import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../../core/constants/firestore_collections.dart';
import '../domain/app_user.dart';

class UsuarioRepository {
  final FirebaseFirestore _firestore;

  UsuarioRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(FirestoreCollections.usuarios);

  Stream<List<AppUser>> watchTodos(String orgId) {
    return _collection
        .where('orgId', isEqualTo: orgId)
        .snapshots()
        .map((snap) =>
        snap.docs.map((d) => AppUser.fromFirestore(d.id, d.data())).toList());
  }

  /// Cria um usuário novo (Firebase Auth + Firestore) sem afetar a
  /// sessão de quem está logado agora — usa um app Firebase
  /// secundário temporário só pra esse cadastro.
  Future<void> criarUsuario({
    required String orgId,
    required String nome,
    required String email,
    required String senha,
    required UserRole role,
  }) async {
    final appTemporario = await Firebase.initializeApp(
      name: 'temp_criar_usuario_${DateTime.now().millisecondsSinceEpoch}',
      options: Firebase.app().options,
    );

    try {
      final authTemporario = FirebaseAuth.instanceFor(app: appTemporario);

      final emailNormalizado = email.trim().toLowerCase();

      final credential = await authTemporario.createUserWithEmailAndPassword(
        email: emailNormalizado,
        password: senha,
      );

      final uid = credential.user!.uid;

      await _collection.doc(uid).set({
        'orgId': orgId,
        'nome': nome.trim(),
        'email': emailNormalizado,
        'role': role.name,
        'ativo': true,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await authTemporario.signOut();
    } finally {
      await appTemporario.delete();
    }
  }

  /// Atualiza os dados administrativos do usuário.
  Future<void> atualizarUsuario({
    required String usuarioId,
    required String nome,
    required UserRole role,
  }) {
    return _collection.doc(usuarioId).update({
      'nome': nome.trim(),
      'role': role.name,
    });
  }

  /// Mantido para alterações onde somente o perfil precisa mudar.
  Future<void> atualizarRole(
      String usuarioId,
      UserRole role,
      ) {
    return _collection.doc(usuarioId).update({
      'role': role.name,
    });
  }

  /// Ativa ou bloqueia o acesso do usuário no sistema.
  ///
  /// Essa alteração controla o acesso pelo Firestore/app.
  /// Ela não desabilita a conta diretamente no Firebase Auth.
  Future<void> atualizarStatus(
      String usuarioId,
      bool ativo,
      ) {
    return _collection.doc(usuarioId).update({
      'ativo': ativo,
    });
  }
}