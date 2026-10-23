/// Projeção rápida do saldo atual, derivada do log de `StockMovement`.
/// NUNCA é a fonte da verdade — se algo parecer errado aqui, o log de
/// movimentações é que manda. Ver seção 6.1 do Blueprint.
class EstoqueSaldo {
  final String orgId;
  final String localId;
  final String produtoId;
  final int quantidade;

  const EstoqueSaldo({
    required this.orgId,
    required this.localId,
    required this.produtoId,
    required this.quantidade,
  });

  /// Chave composta usada como ID do documento — evita precisar de
  /// consulta composta só pra achar um saldo específico.
  static String idPara(String localId, String produtoId) =>
      '${localId}__$produtoId';

  factory EstoqueSaldo.fromFirestore(Map<String, dynamic> data) {
    return EstoqueSaldo(
      orgId: data['orgId'] as String? ?? '',
      localId: data['localId'] as String? ?? '',
      produtoId: data['produtoId'] as String? ?? '',
      quantidade: data['quantidade'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'orgId': orgId,
      'localId': localId,
      'produtoId': produtoId,
      'quantidade': quantidade,
    };
  }
}
