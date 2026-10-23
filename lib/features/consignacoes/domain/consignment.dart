import 'consignment_item.dart';

enum ConsignmentStatus { ativa, encerrada }

ConsignmentStatus _statusFromString(String? v) {
  if (v == 'encerrada') return ConsignmentStatus.encerrada;
  return ConsignmentStatus.ativa;
}

String _statusToString(ConsignmentStatus s) =>
    s == ConsignmentStatus.encerrada ? 'encerrada' : 'ativa';

/// O ciclo de consignação — ver seção 7.2 e 7.3 do Blueprint.
/// Nunca é editada depois de criada (exceto para encerrar). Uma
/// consignação encerrada é histórico permanente, nunca apagado.
class Consignment {
  final String? id;
  final String orgId;
  final String numero; // ex: CON-00001
  final String clienteId;

  /// A qual expositor físico esta consignação pertence — essencial
  /// quando um cliente tem mais de um expositor instalado, senão não
  /// dá pra saber qual consignação é de qual unidade. Opcional só por
  /// compatibilidade com registros antigos criados antes dessa
  /// correção; toda consignação nova deveria vir com isso preenchido.
  final String? expositorId;

  final ConsignmentStatus status;
  final List<ConsignmentItem> itens;
  final DateTime? criadaEm;
  final DateTime? encerradaEm;
  final String? visitaQueAbriuId;
  final String? visitaQueEncerrouId;

  const Consignment({
    this.id,
    required this.orgId,
    required this.numero,
    required this.clienteId,
    this.expositorId,
    this.status = ConsignmentStatus.ativa,
    this.itens = const [],
    this.criadaEm,
    this.encerradaEm,
    this.visitaQueAbriuId,
    this.visitaQueEncerrouId,
  });

  /// Valor líquido NEXT GEAR total da consignação — ver seção 5.3.
  /// É este valor que conta para o limite/exposição do cliente.
  int get valorLiquidoTotalCentavos =>
      itens.fold(0, (soma, item) => soma + item.valorLiquidoTotalCentavos);

  int get valorVendaTotalCentavos =>
      itens.fold(0, (soma, item) => soma + item.valorVendaTotalCentavos);

  factory Consignment.fromFirestore(String id, Map<String, dynamic> data) {
    return Consignment(
      id: id,
      orgId: data['orgId'] as String? ?? '',
      numero: data['numero'] as String? ?? '',
      clienteId: data['clienteId'] as String? ?? '',
      expositorId: data['expositorId'] as String?,
      status: _statusFromString(data['status'] as String?),
      itens: (data['itens'] as List<dynamic>? ?? [])
          .map((e) => ConsignmentItem.fromMap(e as Map<String, dynamic>))
          .toList(),
      criadaEm: data['criadaEm'] != null
          ? (data['criadaEm'] as dynamic).toDate()
          : null,
      encerradaEm: data['encerradaEm'] != null
          ? (data['encerradaEm'] as dynamic).toDate()
          : null,
      visitaQueAbriuId: data['visitaQueAbriuId'] as String?,
      visitaQueEncerrouId: data['visitaQueEncerrouId'] as String?,
    );
  }

  Map<String, dynamic> toFirestoreCriacao() {
    return {
      'orgId': orgId,
      'numero': numero,
      'clienteId': clienteId,
      'expositorId': expositorId,
      'status': _statusToString(status),
      'itens': itens.map((i) => i.toMap()).toList(),
      'criadaEm': criadaEm,
      'encerradaEm': null,
      'visitaQueAbriuId': visitaQueAbriuId,
      'visitaQueEncerrouId': null,
    };
  }
}
