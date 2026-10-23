/// Snapshot congelado no momento em que o item entra numa consignação
/// (ver seção 7.7 do Blueprint). Preço, custo e comissão aqui NUNCA
/// mudam depois — mesmo que o cadastro do produto ou a comissão do
/// cliente sejam alterados posteriormente.
class ConsignmentItem {
  final String produtoId;
  final String descricaoSnapshot;
  final int quantidade;

  /// Dinheiro sempre em centavos inteiros (seção 15.1).
  final int precoVendaCentavos;
  final int custoAquisicaoCentavos;
  final int comissaoBasisPoints;
  final int comissaoCentavos;
  final int valorLiquidoCentavos;

  const ConsignmentItem({
    required this.produtoId,
    required this.descricaoSnapshot,
    required this.quantidade,
    required this.precoVendaCentavos,
    required this.custoAquisicaoCentavos,
    required this.comissaoBasisPoints,
    required this.comissaoCentavos,
    required this.valorLiquidoCentavos,
  });

  /// Arredondamento comercial (half-up) — ver seção 15.1 do Blueprint.
  /// comissaoCentavos e valorLiquidoCentavos são sempre calculados
  /// a partir de precoVendaCentavos e comissaoBasisPoints, nunca
  /// digitados soltos.
  factory ConsignmentItem.calcular({
    required String produtoId,
    required String descricaoSnapshot,
    required int quantidade,
    required int precoVendaCentavos,
    required int custoAquisicaoCentavos,
    required int comissaoBasisPoints,
  }) {
    final comissaoCentavos =
    ((precoVendaCentavos * comissaoBasisPoints) / 10000).round();
    final valorLiquidoCentavos = precoVendaCentavos - comissaoCentavos;

    return ConsignmentItem(
      produtoId: produtoId,
      descricaoSnapshot: descricaoSnapshot,
      quantidade: quantidade,
      precoVendaCentavos: precoVendaCentavos,
      custoAquisicaoCentavos: custoAquisicaoCentavos,
      comissaoBasisPoints: comissaoBasisPoints,
      comissaoCentavos: comissaoCentavos,
      valorLiquidoCentavos: valorLiquidoCentavos,
    );
  }

  int get valorVendaTotalCentavos => precoVendaCentavos * quantidade;
  int get valorLiquidoTotalCentavos => valorLiquidoCentavos * quantidade;

  factory ConsignmentItem.fromMap(Map<String, dynamic> data) {
    return ConsignmentItem(
      produtoId: data['produtoId'] as String? ?? '',
      descricaoSnapshot: data['descricaoSnapshot'] as String? ?? '',
      quantidade: data['quantidade'] as int? ?? 0,
      precoVendaCentavos: data['precoVendaCentavos'] as int? ?? 0,
      custoAquisicaoCentavos: data['custoAquisicaoCentavos'] as int? ?? 0,
      comissaoBasisPoints: data['comissaoBasisPoints'] as int? ?? 0,
      comissaoCentavos: data['comissaoCentavos'] as int? ?? 0,
      valorLiquidoCentavos: data['valorLiquidoCentavos'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'produtoId': produtoId,
      'descricaoSnapshot': descricaoSnapshot,
      'quantidade': quantidade,
      'precoVendaCentavos': precoVendaCentavos,
      'custoAquisicaoCentavos': custoAquisicaoCentavos,
      'comissaoBasisPoints': comissaoBasisPoints,
      'comissaoCentavos': comissaoCentavos,
      'valorLiquidoCentavos': valorLiquidoCentavos,
    };
  }

  ConsignmentItem copyWith({int? quantidade}) {
    return ConsignmentItem.calcular(
      produtoId: produtoId,
      descricaoSnapshot: descricaoSnapshot,
      quantidade: quantidade ?? this.quantidade,
      precoVendaCentavos: precoVendaCentavos,
      custoAquisicaoCentavos: custoAquisicaoCentavos,
      comissaoBasisPoints: comissaoBasisPoints,
    );
  }
}