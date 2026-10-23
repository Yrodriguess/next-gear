/// Ver seção 6.3 e 15.1 do Blueprint.
enum TrackingMode { quantity, lot, serial }

enum SkuStatus { active, blockedForSale, discontinued }

T _enumFromString<T>(List<T> values, String? value, T fallback) {
  if (value == null) return fallback;

  return values.firstWhere(
        (v) => v.toString().split('.').last == value,
    orElse: () => fallback,
  );
}

String _enumToString(Object enumValue) =>
    enumValue.toString().split('.').last;

/// A variação que de fato se movimenta em estoque (ver seção 6.3 do
/// Blueprint) — ex: "Cabo USB-C Turbo — Preto 1m".
///
/// Um Produto pode possuir vários SKUs, por exemplo:
/// - cores;
/// - tamanhos;
/// - modelos.
///
/// O SKU é a unidade real movimentada no estoque.
class Sku {
  final String? id;
  final String orgId;
  final String produtoId;

  /// Código de barras interno gerado automaticamente pela NEXT GEAR.
  ///
  /// Exemplo:
  /// 2000000000015
  ///
  /// É utilizado para identificação, etiquetas, estoque, scanner,
  /// conferências e movimentações internas.
  ///
  /// Apesar de possuir formato compatível com EAN-13 para leitura
  /// por scanner, não deve ser tratado como GTIN comercial oficial.
  final String codigoBarrasInterno;

  /// Compatibilidade temporária com telas e serviços antigos.
  ///
  /// Novos códigos devem usar [codigoBarrasInterno].
  @Deprecated('Use codigoBarrasInterno')
  String get codigoInterno => codigoBarrasInterno;

  /// GTIN/EAN original do fabricante/fornecedor, quando existir.
  ///
  /// Exemplo:
  /// 7891234567890
  final String? codigoBarras;

  /// Identificação da variação do produto.
  ///
  /// Exemplo:
  /// "Preto 1m"
  final String? variacao;

  /// Custo informado no primeiro cadastro do SKU.
  ///
  /// Serve como valor de partida antes de existir histórico de
  /// entradas/compras.
  final int custoInicialCentavos;

  /// Custo médio ponderado atual do SKU.
  ///
  /// Deve ser atualizado automaticamente quando ocorrer uma nova
  /// entrada de compra no estoque.
  ///
  /// Transferências entre estoque central, vendedor e cliente não
  /// recalculam este valor.
  final int custoMedioCentavos;

  /// Custo unitário da compra mais recente.
  ///
  /// Também é atualizado somente quando houver uma nova entrada de
  /// compra.
  final int custoUltimaCompraCentavos;

  /// Preço vigente "de hoje".
  ///
  /// O histórico completo de vigência vive em skuPrecos; este campo
  /// representa apenas o preço atual.
  final int precoVendaCentavos;

  final int estoqueMinimo;
  final TrackingMode trackingMode;
  final SkuStatus status;

  const Sku({
    this.id,
    required this.orgId,
    required this.produtoId,
    String? codigoBarrasInterno,
    @Deprecated('Use codigoBarrasInterno') String? codigoInterno,
    this.codigoBarras,
    this.variacao,
    required this.custoInicialCentavos,
    this.custoMedioCentavos = 0,
    this.custoUltimaCompraCentavos = 0,
    required this.precoVendaCentavos,
    this.estoqueMinimo = 0,
    this.trackingMode = TrackingMode.quantity,
    this.status = SkuStatus.active,
  }) : codigoBarrasInterno =
      codigoBarrasInterno ?? codigoInterno ?? '';

  factory Sku.fromFirestore(
      String id,
      Map<String, dynamic> data,
      ) {
    final custoInicial =
        data['custoInicialCentavos'] as int? ?? 0;

    return Sku(
      id: id,
      orgId: data['orgId'] as String? ?? '',
      produtoId: data['produtoId'] as String? ?? '',

      // Campo novo.
      // Se o registro for antigo, ainda lê codigoInterno.
      codigoBarrasInterno:
      data['codigoBarrasInterno'] as String? ??
          data['codigoInterno'] as String? ??
          '',

      codigoBarras: data['codigoBarras'] as String?,
      variacao: data['variacao'] as String?,

      custoInicialCentavos: custoInicial,

      // Compatibilidade com registros antigos.
      custoMedioCentavos:
      data['custoMedioCentavos'] as int? ??
          custoInicial,

      custoUltimaCompraCentavos:
      data['custoUltimaCompraCentavos'] as int? ??
          custoInicial,

      precoVendaCentavos:
      data['precoVendaCentavos'] as int? ?? 0,

      estoqueMinimo:
      data['estoqueMinimo'] as int? ?? 0,

      trackingMode: _enumFromString(
        TrackingMode.values,
        data['trackingMode'] as String?,
        TrackingMode.quantity,
      ),

      status: _enumFromString(
        SkuStatus.values,
        data['status'] as String?,
        SkuStatus.active,
      ),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'orgId': orgId,
      'produtoId': produtoId,
      'codigoBarrasInterno': codigoBarrasInterno,
      'codigoBarras': codigoBarras,
      'variacao': variacao,
      'custoInicialCentavos': custoInicialCentavos,
      'custoMedioCentavos': custoMedioCentavos,
      'custoUltimaCompraCentavos':
      custoUltimaCompraCentavos,
      'precoVendaCentavos': precoVendaCentavos,
      'estoqueMinimo': estoqueMinimo,
      'trackingMode': _enumToString(trackingMode),
      'status': _enumToString(status),
    };
  }

  Sku copyWith({
    String? produtoId,
    String? codigoBarrasInterno,
    @Deprecated('Use codigoBarrasInterno')
    String? codigoInterno,
    String? codigoBarras,
    String? variacao,
    int? custoInicialCentavos,
    int? custoMedioCentavos,
    int? custoUltimaCompraCentavos,
    int? precoVendaCentavos,
    int? estoqueMinimo,
    TrackingMode? trackingMode,
    SkuStatus? status,
  }) {
    return Sku(
      id: id,
      orgId: orgId,
      produtoId: produtoId ?? this.produtoId,

      codigoBarrasInterno:
      codigoBarrasInterno ??
          codigoInterno ??
          this.codigoBarrasInterno,

      codigoBarras:
      codigoBarras ?? this.codigoBarras,

      variacao:
      variacao ?? this.variacao,

      custoInicialCentavos:
      custoInicialCentavos ??
          this.custoInicialCentavos,

      custoMedioCentavos:
      custoMedioCentavos ??
          this.custoMedioCentavos,

      custoUltimaCompraCentavos:
      custoUltimaCompraCentavos ??
          this.custoUltimaCompraCentavos,

      precoVendaCentavos:
      precoVendaCentavos ??
          this.precoVendaCentavos,

      estoqueMinimo:
      estoqueMinimo ??
          this.estoqueMinimo,

      trackingMode:
      trackingMode ?? this.trackingMode,

      status:
      status ?? this.status,
    );
  }
}
