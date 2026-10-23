/// Categoria de produto (ex: "Cabos", "Fones") — cadastrável pelo
/// próprio usuário, mas selecionável em vez de texto livre, evitando
/// "Cabo" / "cabo" / "CABOS" coexistindo no catálogo.
class Categoria {
  final String? id;
  final String orgId;
  final String nome;

  const Categoria({
    this.id,
    required this.orgId,
    required this.nome,
  });

  factory Categoria.fromFirestore(String id, Map<String, dynamic> data) {
    return Categoria(
      id: id,
      orgId: data['orgId'] as String? ?? '',
      nome: data['nome'] as String? ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {'orgId': orgId, 'nome': nome};
  }
}
