/// Ver seção 7.1 do Blueprint. O "modelo" é só o template (Pequeno,
/// Grande) — não confundir com a unidade física individual.
class ExpositorModelo {
  final String? id;
  final String orgId;
  final String nome; // ex: "Pequeno", "Grande"
  final String? descricao;

  const ExpositorModelo({
    this.id,
    required this.orgId,
    required this.nome,
    this.descricao,
  });

  factory ExpositorModelo.fromFirestore(String id, Map<String, dynamic> data) {
    return ExpositorModelo(
      id: id,
      orgId: data['orgId'] as String? ?? '',
      nome: data['nome'] as String? ?? '',
      descricao: data['descricao'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'orgId': orgId,
      'nome': nome,
      'descricao': descricao,
    };
  }
}