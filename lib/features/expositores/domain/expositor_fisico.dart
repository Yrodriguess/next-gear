/// Ver seção 4 do documento de melhorias do módulo de expositores.
/// 7 estados — inclui "Reservado" e "Perdido", que faltavam antes.
enum ExpositorStatus {
  disponivel,
  reservado,
  instalado,
  manutencao,
  recolhido,
  descartado,
  perdido,
}

ExpositorStatus _statusFromString(String? value) {
  if (value == null) return ExpositorStatus.disponivel;
  return ExpositorStatus.values.firstWhere(
        (v) => v.toString().split('.').last == value,
    orElse: () => ExpositorStatus.disponivel,
  );
}

String _statusToString(ExpositorStatus status) =>
    status.toString().split('.').last;

/// Estado de conservação físico do equipamento — separado do status
/// operacional (que é sobre onde/com quem ele está).
enum EstadoConservacao { novo, bom, regular, ruim }

EstadoConservacao _conservacaoFromString(String? value) {
  if (value == null) return EstadoConservacao.bom;
  return EstadoConservacao.values.firstWhere(
        (v) => v.toString().split('.').last == value,
    orElse: () => EstadoConservacao.bom,
  );
}

String _conservacaoToString(EstadoConservacao c) => c.toString().split('.').last;

/// Versão pública — usada pelo repositório ao gravar mudança de
/// estado de conservação (ex: durante a conferência pós-recolhimento).
String conservacaoParaString(EstadoConservacao c) => _conservacaoToString(c);

/// Identificadores padronizados de local do expositor — mesmo
/// espírito do LocalEstoque (seção 6.2 do Blueprint), mas mais simples
/// porque expositor não tem saldo, só "onde ele está agora".
class LocalExpositor {
  LocalExpositor._();

  static const String central = 'central';
  static const String manutencao = 'manutencao';

  static String cliente(String clienteId) => 'cliente_$clienteId';

  static String? extrairClienteId(String local) {
    if (!local.startsWith('cliente_')) return null;
    return local.substring('cliente_'.length);
  }
}

/// Destinos possíveis ao retirar um expositor de um cliente — ver
/// seção 7 do documento de melhorias. Transferência direta pra outro
/// cliente é um fluxo à parte (seção 8), ainda não implementado aqui.
enum DestinoRetirada { estoque, recolhido, manutencao, descarte, perdido }

class ExpositorFisico {
  final String? id;
  final String orgId;

  /// Código de inventário no formato EXP-MOD-000, ex: EXP-GRA-001.
  final String numero;
  final String modeloId;
  final String modeloNome;

  final String? clienteAtualId;
  final ExpositorStatus status;
  final String localAtual;

  /// Reserva feita no cadastro do cliente — antes da instalação de
  /// verdade. Enquanto reservado: clienteReservadoId preenchido,
  /// clienteAtualId continua null (o expositor ainda está fisicamente
  /// no estoque). Só depois de confirmarInstalacao() é que vira
  /// clienteAtualId de verdade. Ver plano de reserva de expositor.
  final String? clienteReservadoId;
  final DateTime? dataReserva;
  final String? reservadoPor;

  final String? observacoes;
  final EstadoConservacao estadoConservacao;
  final String? numeroSerieFabricante;

  final String? fotoUrl;
  final String? fotoStoragePath;

  final DateTime? dataInstalacao;

  // Auditoria — seção 14 do documento de melhorias.
  final DateTime? createdAt;
  final String? createdBy;
  final DateTime? updatedAt;
  final String? updatedBy;

  const ExpositorFisico({
    this.id,
    required this.orgId,
    required this.numero,
    required this.modeloId,
    required this.modeloNome,
    this.clienteAtualId,
    this.status = ExpositorStatus.disponivel,
    this.localAtual = LocalExpositor.central,
    this.clienteReservadoId,
    this.dataReserva,
    this.reservadoPor,
    this.observacoes,
    this.estadoConservacao = EstadoConservacao.novo,
    this.numeroSerieFabricante,
    this.fotoUrl,
    this.fotoStoragePath,
    this.dataInstalacao,
    this.createdAt,
    this.createdBy,
    this.updatedAt,
    this.updatedBy,
  });

  factory ExpositorFisico.fromFirestore(String id, Map<String, dynamic> data) {
    return ExpositorFisico(
      id: id,
      orgId: data['orgId'] as String? ?? '',
      numero: data['numero'] as String? ?? '',
      modeloId: data['modeloId'] as String? ?? '',
      modeloNome: data['modeloNome'] as String? ?? '',
      clienteAtualId: data['clienteAtualId'] as String?,
      status: _statusFromString(data['status'] as String?),
      localAtual: data['localAtual'] as String? ?? LocalExpositor.central,
      clienteReservadoId: data['clienteReservadoId'] as String?,
      dataReserva: data['dataReserva'] != null
          ? (data['dataReserva'] as dynamic).toDate()
          : null,
      reservadoPor: data['reservadoPor'] as String?,
      observacoes: data['observacoes'] as String?,
      estadoConservacao:
          _conservacaoFromString(data['estadoConservacao'] as String?),
      numeroSerieFabricante: data['numeroSerieFabricante'] as String?,
      fotoUrl: data['fotoUrl'] as String?,
      fotoStoragePath: data['fotoStoragePath'] as String?,
      dataInstalacao: data['dataInstalacao'] != null
          ? (data['dataInstalacao'] as dynamic).toDate()
          : null,
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as dynamic).toDate()
          : null,
      createdBy: data['createdBy'] as String?,
      updatedAt: data['updatedAt'] != null
          ? (data['updatedAt'] as dynamic).toDate()
          : null,
      updatedBy: data['updatedBy'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'orgId': orgId,
      'numero': numero,
      'modeloId': modeloId,
      'modeloNome': modeloNome,
      'clienteAtualId': clienteAtualId,
      'status': _statusToString(status),
      'localAtual': localAtual,
      'clienteReservadoId': clienteReservadoId,
      'dataReserva': dataReserva,
      'reservadoPor': reservadoPor,
      'observacoes': observacoes,
      'estadoConservacao': _conservacaoToString(estadoConservacao),
      'numeroSerieFabricante': numeroSerieFabricante,
      'fotoUrl': fotoUrl,
      'fotoStoragePath': fotoStoragePath,
      'dataInstalacao': dataInstalacao,
      'createdAt': createdAt,
      'createdBy': createdBy,
      'updatedAt': updatedAt,
      'updatedBy': updatedBy,
    };
  }
}
