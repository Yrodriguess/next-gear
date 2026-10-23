/// Ver seção 7.9 do Blueprint — documento gerado a partir de uma
/// visita (Termo de Instalação/Acerto/Retirada), com número legível,
/// hash do PDF e assinatura coletada.
///
/// `gerando` e `erro` existem para tornar a geração idempotente:
/// se PDF/Storage falhar depois da assinatura, o mesmo número e a
/// mesma assinatura podem ser reutilizados no retry.
enum DocumentoTipo { instalacao, acertoEReposicao, encerramento }

enum DocumentoStatus {
  gerando,
  ativo,
  erro,
  cancelado,
}

DocumentoTipo _tipoFromString(String? v) {
  return DocumentoTipo.values.firstWhere(
        (e) => e.name == v,
    orElse: () => DocumentoTipo.acertoEReposicao,
  );
}

String tipoToString(DocumentoTipo t) => t.name;

DocumentoStatus _statusFromString(String? v) {
  return switch (v) {
    'gerando' => DocumentoStatus.gerando,
    'erro' => DocumentoStatus.erro,
    'cancelado' => DocumentoStatus.cancelado,
  // Compatibilidade com documentos antigos, inclusive os que não
  // possuem o campo status.
    _ => DocumentoStatus.ativo,
  };
}

String statusToString(DocumentoStatus s) => s.name;

class Assinatura {
  final String nomeResponsavel;
  final String documentoResponsavel;
  final String telefoneResponsavel;
  final DateTime timestamp;

  const Assinatura({
    required this.nomeResponsavel,
    required this.documentoResponsavel,
    required this.telefoneResponsavel,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
    'nomeResponsavel': nomeResponsavel,
    'documentoResponsavel': documentoResponsavel,
    'telefoneResponsavel': telefoneResponsavel,
    'timestamp': timestamp,
  };

  factory Assinatura.fromMap(Map<String, dynamic> data) => Assinatura(
    nomeResponsavel: data['nomeResponsavel'] as String? ?? '',
    documentoResponsavel:
    data['documentoResponsavel'] as String? ?? '',
    telefoneResponsavel:
    data['telefoneResponsavel'] as String? ?? '',
    timestamp: data['timestamp'] != null
        ? (data['timestamp'] as dynamic).toDate()
        : DateTime.now(),
  );
}

class DocumentoGerado {
  final String? id;
  final String orgId;
  final String numero;
  final DocumentoTipo tipo;
  final String clienteId;
  final String visitaId;
  final String urlStorage;
  final String hash;
  final DocumentoStatus status;
  final Assinatura? assinatura;
  final String? erroGeracao;
  final DateTime? criadoEm;
  final DateTime? atualizadoEm;

  const DocumentoGerado({
    this.id,
    required this.orgId,
    required this.numero,
    required this.tipo,
    required this.clienteId,
    required this.visitaId,
    required this.urlStorage,
    required this.hash,
    this.status = DocumentoStatus.ativo,
    this.assinatura,
    this.erroGeracao,
    this.criadoEm,
    this.atualizadoEm,
  });

  factory DocumentoGerado.fromFirestore(
      String id,
      Map<String, dynamic> data,
      ) {
    return DocumentoGerado(
      id: id,
      orgId: data['orgId'] as String? ?? '',
      numero: data['numero'] as String? ?? '',
      tipo: _tipoFromString(data['tipo'] as String?),
      clienteId: data['clienteId'] as String? ?? '',
      visitaId: data['visitaId'] as String? ?? '',
      urlStorage: data['urlStorage'] as String? ?? '',
      hash: data['hash'] as String? ?? '',
      status: _statusFromString(data['status'] as String?),
      assinatura: data['assinatura'] is Map<String, dynamic>
          ? Assinatura.fromMap(
        data['assinatura'] as Map<String, dynamic>,
      )
          : null,
      erroGeracao: data['erroGeracao'] as String?,
      criadoEm: data['criadoEm'] != null
          ? (data['criadoEm'] as dynamic).toDate()
          : null,
      atualizadoEm: data['atualizadoEm'] != null
          ? (data['atualizadoEm'] as dynamic).toDate()
          : null,
    );
  }
}
