/// Ver seção 10 do documento de melhorias — cada mudança relevante
/// vira uma linha aqui, nunca substituindo a anterior.
enum TipoMovimentacaoExpositor {
  cadastro,
  instalacao,
  retirada,
  transferencia,
  manutencaoEntrada,
  manutencaoSaida,
  descarte,
  perda,
  conferencia,
  reserva,
  cancelamentoReserva,
}

TipoMovimentacaoExpositor _tipoFromString(String? v) {
  if (v == null) return TipoMovimentacaoExpositor.cadastro;
  return TipoMovimentacaoExpositor.values.firstWhere(
    (e) => e.toString().split('.').last == v,
    orElse: () => TipoMovimentacaoExpositor.cadastro,
  );
}

String tipoMovimentacaoParaString(TipoMovimentacaoExpositor t) =>
    t.toString().split('.').last;

/// Um evento na linha do tempo de um expositor físico. Imutável —
/// nunca é editado ou apagado depois de criado (mesmo invariante de
/// estoqueMovimentacoes, seção 16 do Blueprint).
class ExpositorMovimentacao {
  final String? id;
  final String orgId;
  final String expositorId;
  final TipoMovimentacaoExpositor tipo;
  final String usuarioId;

  final String? clienteAnteriorId;
  final String? clienteNovoId;
  final String? statusAnterior;
  final String statusNovo;
  final String? origem;
  final String? destino;
  final String? observacao;

  final DateTime? timestamp;

  const ExpositorMovimentacao({
    this.id,
    required this.orgId,
    required this.expositorId,
    required this.tipo,
    required this.usuarioId,
    this.clienteAnteriorId,
    this.clienteNovoId,
    this.statusAnterior,
    required this.statusNovo,
    this.origem,
    this.destino,
    this.observacao,
    this.timestamp,
  });

  factory ExpositorMovimentacao.fromFirestore(
      String id, Map<String, dynamic> data) {
    return ExpositorMovimentacao(
      id: id,
      orgId: data['orgId'] as String? ?? '',
      expositorId: data['expositorId'] as String? ?? '',
      tipo: _tipoFromString(data['tipo'] as String?),
      usuarioId: data['usuarioId'] as String? ?? '',
      clienteAnteriorId: data['clienteAnteriorId'] as String?,
      clienteNovoId: data['clienteNovoId'] as String?,
      statusAnterior: data['statusAnterior'] as String?,
      statusNovo: data['statusNovo'] as String? ?? '',
      origem: data['origem'] as String?,
      destino: data['destino'] as String?,
      observacao: data['observacao'] as String?,
      timestamp: data['timestamp'] != null
          ? (data['timestamp'] as dynamic).toDate()
          : null,
    );
  }
}
