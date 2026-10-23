/// Ver seção 6.4 do Blueprint — motivos padronizados, não texto livre.
enum MovimentoMotivo {
  entrada,
  instalacao,
  reposicao,
  recolhimento,
  transferencia,
  devolucao,
  inventario,
  avaria,
  extravio,
  vendaApurada,
  erroDeLancamento,
}

MovimentoMotivo motivoFromString(String? v) {
  if (v == null) return MovimentoMotivo.inventario;
  return MovimentoMotivo.values.firstWhere(
        (e) => e.toString().split('.').last == v,
    orElse: () => MovimentoMotivo.inventario,
  );
}

String motivoToString(MovimentoMotivo m) => m.toString().split('.').last;

/// Identificadores padronizados de local de estoque — ver seção 6.2
/// do Blueprint (três camadas: central, carga do vendedor, cliente).
/// Nunca escrever esses valores "na mão" em outro lugar do código.
///
/// Além dos locais físicos reais, existem "destinos externos" — venda
/// apurada, avaria, extravio, fornecedor — que representam saída
/// definitiva de mercadoria. Eles NÃO têm saldo de estoque próprio.
class LocalEstoque {
  LocalEstoque._();

  static const String central = 'central';
  static const String fornecedor = 'fornecedor';
  static const String vendido = 'vendido';
  static const String avaria = 'avaria';
  static const String extravio = 'extravio';

  static String vendedor(String usuarioId) => 'vendedor_$usuarioId';
  static String cliente(String clienteId) => 'cliente_$clienteId';

  static const Set<String> _externos = {fornecedor, vendido, avaria, extravio};

  /// Locais externos não têm saldo rastreado — só marcam entrada/saída
  /// definitiva de mercadoria do sistema físico.
  static bool ehLocalReal(String local) => !_externos.contains(local);

  /// Extrai o clienteId de um local no formato "cliente_XYZ" — usado
  /// pelos relatórios pra resolver o nome do cliente a partir da
  /// movimentação. Retorna null se o local não for desse formato.
  static String? extrairClienteId(String local) {
    if (!local.startsWith('cliente_')) return null;
    return local.substring('cliente_'.length);
  }
}

/// Ver seção 6.1 do Blueprint: `stockMovements` é a única fonte da
/// verdade do estoque. Nunca é editado ou apagado — uma correção
/// sempre gera um novo lançamento de estorno, nunca some o antigo.
class StockMovement {
  final String? id;
  final String orgId;
  final String produtoId;
  final int quantidade;
  final String origem;
  final String destino;
  final MovimentoMotivo motivo;
  final String usuarioId;
  final int? custoUnitarioCentavosNoMomento;

  /// Preço de venda vigente no momento da movimentação — só
  /// preenchido em movimentações do tipo `vendaApurada`. É o que
  /// permite o relatório de vendas calcular R$ sem depender do preço
  /// atual do produto (que pode já ter mudado) — mesma lógica de
  /// snapshot da seção 7.7 do Blueprint.
  final int? valorVendaCentavosNoMomento;

  /// Comissão unitária que o lojista reteve nesta venda. O valor vem do
  /// item da consignação encerrada, portanto não muda se a comissão do
  /// cliente for alterada depois. Movimentos antigos podem ter valor nulo.
  final int? comissaoCentavosNoMomento;

  final String? observacao;
  final DateTime? timestamp;

  const StockMovement({
    this.id,
    required this.orgId,
    required this.produtoId,
    required this.quantidade,
    required this.origem,
    required this.destino,
    required this.motivo,
    required this.usuarioId,
    this.custoUnitarioCentavosNoMomento,
    this.valorVendaCentavosNoMomento,
    this.comissaoCentavosNoMomento,
    this.observacao,
    this.timestamp,
  });

  factory StockMovement.fromFirestore(String id, Map<String, dynamic> data) {
    return StockMovement(
      id: id,
      orgId: data['orgId'] as String? ?? '',
      produtoId: data['produtoId'] as String? ?? '',
      quantidade: data['quantidade'] as int? ?? 0,
      origem: data['origem'] as String? ?? '',
      destino: data['destino'] as String? ?? '',
      motivo: motivoFromString(data['motivo'] as String?),
      usuarioId: data['usuarioId'] as String? ?? '',
      custoUnitarioCentavosNoMomento:
      data['custoUnitarioCentavosNoMomento'] as int?,
      valorVendaCentavosNoMomento: data['valorVendaCentavosNoMomento'] as int?,
      comissaoCentavosNoMomento: data['comissaoCentavosNoMomento'] as int?,
      observacao: data['observacao'] as String?,
      timestamp: data['timestamp'] != null
          ? (data['timestamp'] as dynamic).toDate()
          : null,
    );
  }

  int get valorVendaTotalCentavos =>
      quantidade * (valorVendaCentavosNoMomento ?? 0);

  int? get comissaoTotalCentavos => comissaoCentavosNoMomento == null
      ? null
      : quantidade * comissaoCentavosNoMomento!;

  int? get repasseNextGearCentavos {
    final comissao = comissaoTotalCentavos;
    if (valorVendaCentavosNoMomento == null || comissao == null) return null;
    return valorVendaTotalCentavos - comissao;
  }

  int? get resultadoBrutoNextGearCentavos {
    final repasse = repasseNextGearCentavos;
    final custoUnitario = custoUnitarioCentavosNoMomento;
    if (repasse == null || custoUnitario == null) return null;
    return repasse - (quantidade * custoUnitario);
  }
}
