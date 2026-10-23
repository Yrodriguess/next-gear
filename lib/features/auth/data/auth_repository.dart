import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/constants/firestore_collections.dart';
import '../domain/app_user.dart';

/// Fala diretamente com Firebase Auth e Firestore.
/// Nenhuma tela deve chamar FirebaseAuth ou Firestore direto — sempre
/// passa por aqui, pra manter a lógica de autenticação num lugar só.
class AuthRepository {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  AuthRepository({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  /// Emite o usuário do Firebase Auth sempre que o estado de login muda
  /// (logou, deslogou, token expirou etc.).
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentFirebaseUser => _auth.currentUser;

  Future<void> signIn({required String email, required String password}) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signOut() => _auth.signOut();

  /// Busca o documento do usuário na coleção `usuarios` (com o papel/role,
  /// nome, orgId — ver seção 4 do Blueprint). É esse documento que diz
  /// o que a pessoa pode fazer no sistema, não o Firebase Auth sozinho.
  Future<AppUser?> fetchAppUser(String uid) async {
    final doc = await _firestore.collection(FirestoreCollections.usuarios).doc(uid).get();
    if (!doc.exists) return null;
    return AppUser.fromFirestore(uid, doc.data()!);
  }
}