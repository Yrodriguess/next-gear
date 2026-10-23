/// Ver seção 8.1 e 8.2 do Blueprint.
enum RecebivelStatus { aberto, parcial, pago, vencido, cancelado }

RecebivelStatus _statusFromString(String? v) {
  if (v == null) return RecebivelStatus.aberto;
  return RecebivelStatus.values.firstWhere(
        (e) => e.toString().split('.').last == v,
    orElse: () => RecebivelStatus.aberto,
  );
}

String statusToString(RecebivelStatus s) => s.toString().split('.').last;

/// Uma conta a receber, gerada automaticamente ao finalizar uma visita
/// com venda apurada. Nunca editada diretamente — o saldo é sempre
/// derivado dos pagamentos aplicados a ela (ver seção 8.1: ledger,
/// não "saldo" sobrescrito).
class Recebivel {
  final String? id;
  final String orgId;
  final String numero; // ex: COB-000001
  final String clienteId;
  final String visitaId;
  final int valorCentavos;
  final int valorPagoCentavos;
  final RecebivelStatus status;
  final DateTime? dataVencimento;
  final DateTime? criadoEm;

  const Recebivel({
    this.id,
    required this.orgId,
    required this.numero,
    required this.clienteId,
    required this.visitaId,
    required this.valorCentavos,
    this.valorPagoCentavos = 0,
    this.status = RecebivelStatus.aberto,
    this.dataVencimento,
    this.criadoEm,
  });

  int get saldoEmAbertoCentavos => valorCentavos - valorPagoCentavos;

  factory Recebivel.fromFirestore(String id, Map<String, dynamic> data) {
    return Recebivel(
      id: id,
      orgId: data['orgId'] as String? ?? '',
      numero: data['numero'] as String? ?? '',
      clienteId: data['clienteId'] as String? ?? '',
      visitaId: data['visitaId'] as String? ?? '',
      valorCentavos: data['valorCentavos'] as int? ?? 0,
      valorPagoCentavos: data['valorPagoCentavos'] as int? ?? 0,
      status: _statusFromString(data['status'] as String?),
      dataVencimento: data['dataVencimento'] != null
          ? (data['dataVencimento'] as dynamic).toDate()
          : null,
      criadoEm: data['criadoEm'] != null
          ? (data['criadoEm'] as dynamic).toDate()
          : null,
    );
  }
}