/// Como o dinheiro chegou. Pix e boleto caem direto pra empresa/banco
/// — não tem "vendedor segurando o dinheiro", então já nascem
/// confirmados. Só "dinheiro" passa pelo ciclo de repasse.
enum FormaPagamento { dinheiro, pix, boleto }

String formaPagamentoToString(FormaPagamento f) => f.toString().split('.').last;

FormaPagamento formaPagamentoFromString(String? v) {
  return FormaPagamento.values.firstWhere(
    (e) => e.toString().split('.').last == v,
    orElse: () => FormaPagamento.dinheiro,
  );
}

String formaPagamentoLabel(FormaPagamento f) => switch (f) {
      FormaPagamento.dinheiro => 'Dinheiro',
      FormaPagamento.pix => 'Pix',
      FormaPagamento.boleto => 'Boleto',
    };

/// Situação do repasse desse pagamento específico até a empresa.
/// Pix/boleto nascem "confirmado" — não precisam de repasse físico.
/// Dinheiro nasce "pendenteRepasse", vira "repassado" quando entra
/// num AcertoCaixa, e "confirmado" quando o financeiro valida.
enum StatusRepasse { confirmado, pendenteRepasse, repassado }

String statusRepasseToString(StatusRepasse s) => s.toString().split('.').last;

StatusRepasse statusRepasseFromString(String? v) {
  return StatusRepasse.values.firstWhere(
    (e) => e.toString().split('.').last == v,
    orElse: () => StatusRepasse.confirmado,
  );
}

/// Ver seção 15.1 do Blueprint — paymentAllocations. Um pagamento não
/// só muda o status de UM recebível: ele é distribuído (alocado) entre
/// um ou mais recebíveis, e pode sobrar saldo a favor do cliente.
class Pagamento {
  final String? id;
  final String orgId;
  final String clienteId;
  final int valorTotalCentavos;
  final String? observacao;
  final DateTime? criadoEm;

  /// Para cada recebível que esse pagamento cobriu, quanto foi
  /// aplicado nele — ex: {"recebivelId1": 40000, "recebivelId2": 15000}.
  final Map<String, int> alocacoes;

  final FormaPagamento formaPagamento;

  /// Quem recebeu — só relevante/preenchido pra pagamentos em dinheiro
  /// coletados durante uma visita.
  final String? vendedorId;

  final StatusRepasse statusRepasse;

  /// Preenchido quando esse pagamento entra num AcertoCaixa (fechamento
  /// do dia do vendedor).
  final String? acertoCaixaId;

  const Pagamento({
    this.id,
    required this.orgId,
    required this.clienteId,
    required this.valorTotalCentavos,
    this.observacao,
    this.criadoEm,
    this.alocacoes = const {},
    this.formaPagamento = FormaPagamento.dinheiro,
    this.vendedorId,
    this.statusRepasse = StatusRepasse.confirmado,
    this.acertoCaixaId,
  });

  int get valorAlocadoCentavos =>
      alocacoes.values.fold(0, (soma, v) => soma + v);

  int get saldoAFavorCentavos => valorTotalCentavos - valorAlocadoCentavos;

  factory Pagamento.fromFirestore(String id, Map<String, dynamic> data) {
    return Pagamento(
      id: id,
      orgId: data['orgId'] as String? ?? '',
      clienteId: data['clienteId'] as String? ?? '',
      valorTotalCentavos: data['valorTotalCentavos'] as int? ?? 0,
      observacao: data['observacao'] as String?,
      criadoEm: data['criadoEm'] != null
          ? (data['criadoEm'] as dynamic).toDate()
          : null,
      alocacoes: Map<String, int>.from(data['alocacoes'] as Map? ?? {}),
      formaPagamento: formaPagamentoFromString(data['formaPagamento'] as String?),
      vendedorId: data['vendedorId'] as String?,
      statusRepasse: statusRepasseFromString(data['statusRepasse'] as String?),
      acertoCaixaId: data['acertoCaixaId'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'orgId': orgId,
      'clienteId': clienteId,
      'valorTotalCentavos': valorTotalCentavos,
      'observacao': observacao,
      'alocacoes': alocacoes,
      'formaPagamento': formaPagamentoToString(formaPagamento),
      'vendedorId': vendedorId,
      'statusRepasse': statusRepasseToString(statusRepasse),
      'acertoCaixaId': acertoCaixaId,
    };
  }
}
