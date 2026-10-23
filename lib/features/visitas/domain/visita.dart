/// Ver seção 7.4 do Blueprint — visita como entidade com estados,
/// não um evento único. Permite pausar/retomar sem perder trabalho.
enum VisitaEstado {
  agendada,
  iniciada,
  emConferencia,
  conferenciaConcluida,
  emReposicao,
  aguardandoAssinatura,
  finalizada,
  sincronizada,
  cancelada,
}

VisitaEstado _estadoFromString(String? value) {
  if (value == null || value.trim().isEmpty) {
    return VisitaEstado.agendada;
  }

  return VisitaEstado.values.firstWhere(
        (estado) => estado.name == value,
    orElse: () => VisitaEstado.agendada,
  );
}

String _estadoToString(VisitaEstado estado) => estado.name;

/// Ver seção 7.5 do Blueprint — tipos de evento distintos, não uma
/// "visita" genérica para tudo.
enum VisitaTipo {
  instalacao,
  visita,
  coleta,
  transferencia,
  inventario,
}

VisitaTipo _tipoFromString(String? value) {
  if (value == null || value.trim().isEmpty) {
    return VisitaTipo.visita;
  }

  return VisitaTipo.values.firstWhere(
        (tipo) => tipo.name == value,
    orElse: () => VisitaTipo.visita,
  );
}

String _tipoToString(VisitaTipo tipo) => tipo.name;

/// Converte Timestamp do Firestore, DateTime ou texto ISO em DateTime.
/// Retorna null para manter compatibilidade com registros antigos ou inválidos.
DateTime? _dateTimeFromFirestore(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;

  if (value is String) {
    return DateTime.tryParse(value);
  }

  try {
    final convertido = value.toDate();
    return convertido is DateTime ? convertido : null;
  } catch (_) {
    return null;
  }
}

class Visita {
  final String? id;
  final String orgId;
  final String clienteId;
  final String vendedorId;
  final VisitaTipo tipo;
  final VisitaEstado estado;

  /// Código legível, por exemplo VIS-000001, gerado ao finalizar.
  final String? numero;

  /// Momento em que o documento da visita foi criado.
  final DateTime? criadaEm;

  /// Data prevista copiada do cliente quando a visita é iniciada.
  /// Mantê-la na visita permite medir atraso ou antecipação depois.
  final DateTime? dataPrevista;

  /// Horário real em que o vendedor confirmou o início da visita.
  final DateTime? iniciadaEm;

  /// Consignação atendida. Pode ser nula em uma instalação inicial.
  final String? consignmentId;

  /// Expositor escolhido para o atendimento.
  /// Pode ser definido depois em uma instalação inicial.
  final String? expositorId;

  /// Horário real de conclusão da visita.
  final DateTime? finalizadaEm;

  const Visita({
    this.id,
    required this.orgId,
    required this.clienteId,
    required this.vendedorId,
    this.tipo = VisitaTipo.visita,
    this.estado = VisitaEstado.agendada,
    this.numero,
    this.criadaEm,
    this.dataPrevista,
    this.iniciadaEm,
    this.consignmentId,
    this.expositorId,
    this.finalizadaEm,
  });

  /// Indica que a visita já começou e ainda pode ser retomada.
  bool get emAndamento {
    return estado == VisitaEstado.iniciada ||
        estado == VisitaEstado.emConferencia ||
        estado == VisitaEstado.conferenciaConcluida ||
        estado == VisitaEstado.emReposicao ||
        estado == VisitaEstado.aguardandoAssinatura;
  }

  bool get concluida {
    return estado == VisitaEstado.finalizada ||
        estado == VisitaEstado.sincronizada;
  }

  bool get cancelada => estado == VisitaEstado.cancelada;

  /// Compatibilidade para visitas antigas que ainda não possuem iniciadaEm.
  DateTime? get inicioEfetivo => iniciadaEm ?? criadaEm;

  factory Visita.fromFirestore(String id, Map<String, dynamic> data) {
    return Visita(
      id: id,
      orgId: data['orgId'] as String? ?? '',
      clienteId: data['clienteId'] as String? ?? '',
      vendedorId: data['vendedorId'] as String? ?? '',
      tipo: _tipoFromString(data['tipo'] as String?),
      estado: _estadoFromString(data['estado'] as String?),
      numero: data['numero'] as String?,
      criadaEm: _dateTimeFromFirestore(data['criadaEm']),
      dataPrevista: _dateTimeFromFirestore(data['dataPrevista']),
      iniciadaEm: _dateTimeFromFirestore(data['iniciadaEm']),
      consignmentId: data['consignmentId'] as String?,
      expositorId: data['expositorId'] as String?,
      finalizadaEm: _dateTimeFromFirestore(data['finalizadaEm']),
    );
  }

  /// Mapa usado somente na criação inicial do documento da visita.
  /// O número continua sendo gerado pelo fluxo de finalização.
  Map<String, dynamic> toFirestoreCriacao() {
    return {
      'orgId': orgId,
      'clienteId': clienteId,
      'vendedorId': vendedorId,
      'tipo': _tipoToString(tipo),
      'estado': _estadoToString(estado),
      'numero': null,
      'criadaEm': criadaEm,
      'dataPrevista': dataPrevista,
      'iniciadaEm': iniciadaEm,
      'consignmentId': consignmentId,
      'expositorId': expositorId,
      'finalizadaEm': null,
    };
  }
}

String estadoParaString(VisitaEstado estado) => _estadoToString(estado);

String tipoParaString(VisitaTipo tipo) => _tipoToString(tipo);
