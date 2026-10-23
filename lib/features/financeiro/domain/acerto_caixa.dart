/// Ciclo de vida de um fechamento de caixa: repassado (vendedor
/// Ciclo de vida de um fechamento de caixa: repassado (vendedor
/// fechou o dia e declarou o total) → confirmado (financeiro validou
/// que recebeu de verdade).
enum StatusAcertoCaixa { repassado, confirmado }

String statusAcertoCaixaToString(StatusAcertoCaixa s) =>
    s.toString().split('.').last;

StatusAcertoCaixa statusAcertoCaixaFromString(String? v) {
  return StatusAcertoCaixa.values.firstWhere(
    (e) => e.toString().split('.').last == v,
    orElse: () => StatusAcertoCaixa.repassado,
  );
}

/// Um item do extrato do dia — snapshot de um pagamento em dinheiro
/// incluído nesse fechamento, já com o nome do cliente pra não
/// precisar de join na hora de exibir.
class AcertoCaixaItem {
  final String pagamentoId;
  final String clienteId;
  final String clienteNome;
  final int valorCentavos;

  const AcertoCaixaItem({
    required this.pagamentoId,
    required this.clienteId,
    required this.clienteNome,
    required this.valorCentavos,
  });

  Map<String, dynamic> toMap() => {
        'pagamentoId': pagamentoId,
        'clienteId': clienteId,
        'clienteNome': clienteNome,
        'valorCentavos': valorCentavos,
      };

  factory AcertoCaixaItem.fromMap(Map<String, dynamic> m) => AcertoCaixaItem(
        pagamentoId: m['pagamentoId'] as String? ?? '',
        clienteId: m['clienteId'] as String? ?? '',
        clienteNome: m['clienteNome'] as String? ?? '',
        valorCentavos: m['valorCentavos'] as int? ?? 0,
      );
}

/// O fechamento de caixa em dinheiro de um vendedor num dia — extrato
/// detalhado cliente a cliente + total, que o financeiro confirma
/// depois de receber de verdade. Nunca editado depois de criado —
/// é histórico.
class AcertoCaixa {
  final String? id;
  final String orgId;
  final String vendedorId;
  final DateTime data;
  final List<AcertoCaixaItem> itens;
  final int valorTotalCentavos;
  final StatusAcertoCaixa status;
  final String? observacao;
  final String? confirmadoPor;
  final DateTime? confirmadoEm;
  final DateTime? criadoEm;

  const AcertoCaixa({
    this.id,
    required this.orgId,
    required this.vendedorId,
    required this.data,
    required this.itens,
    required this.valorTotalCentavos,
    this.status = StatusAcertoCaixa.repassado,
    this.observacao,
    this.confirmadoPor,
    this.confirmadoEm,
    this.criadoEm,
  });

  factory AcertoCaixa.fromFirestore(String id, Map<String, dynamic> data) {
    return AcertoCaixa(
      id: id,
      orgId: data['orgId'] as String? ?? '',
      vendedorId: data['vendedorId'] as String? ?? '',
      data: data['data'] != null
          ? (data['data'] as dynamic).toDate()
          : DateTime.now(),
      itens: (data['itens'] as List<dynamic>? ?? [])
          .map((e) => AcertoCaixaItem.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      valorTotalCentavos: data['valorTotalCentavos'] as int? ?? 0,
      status: statusAcertoCaixaFromString(data['status'] as String?),
      observacao: data['observacao'] as String?,
      confirmadoPor: data['confirmadoPor'] as String?,
      confirmadoEm: data['confirmadoEm'] != null
          ? (data['confirmadoEm'] as dynamic).toDate()
          : null,
      criadoEm: data['criadoEm'] != null
          ? (data['criadoEm'] as dynamic).toDate()
          : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'orgId': orgId,
      'vendedorId': vendedorId,
      'data': data,
      'itens': itens.map((i) => i.toMap()).toList(),
      'valorTotalCentavos': valorTotalCentavos,
      'status': statusAcertoCaixaToString(status),
      'observacao': observacao,
      'confirmadoPor': confirmadoPor,
      'confirmadoEm': confirmadoEm,
    };
  }
}
