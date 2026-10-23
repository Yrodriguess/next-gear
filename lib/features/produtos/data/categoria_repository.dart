import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_collections.dart';
import '../domain/categoria.dart';

class CategoriaRepository {
  final FirebaseFirestore _firestore;

  CategoriaRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(FirestoreCollections.categoriasProduto);

  Stream<List<Categoria>> watchAll(String orgId) {
    return _collection
        .where('orgId', isEqualTo: orgId)
        .orderBy('nome')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Categoria.fromFirestore(d.id, d.data())).toList());
  }

  /// Trim + primeira letra maiúscula por palavra, pra "cabo", "Cabo" e
  /// "CABO" sempre virarem a mesma categoria ("Cabo").
  String normalizar(String nome) {
    final limpo = nome.trim();
    if (limpo.isEmpty) return limpo;
    return limpo
        .split(RegExp(r'\s+'))
        .map((p) =>
            p.isEmpty ? p : p[0].toUpperCase() + p.substring(1).toLowerCase())
        .join(' ');
  }

  /// Cria a categoria se ainda não existir uma com o mesmo nome
  /// normalizado nesta organização; devolve o nome final a ser salvo
  /// no produto.
  Future<String> criarSeNaoExistir(String orgId, String nome) async {
    final nomeNormalizado = normalizar(nome);
    if (nomeNormalizado.isEmpty) return nomeNormalizado;

    final existente = await _collection
        .where('orgId', isEqualTo: orgId)
        .where('nome', isEqualTo: nomeNormalizado)
        .limit(1)
        .get();

    if (existente.docs.isEmpty) {
      await _collection
          .add(Categoria(orgId: orgId, nome: nomeNormalizado).toFirestore());
    }

    return nomeNormalizado;
  }
}
