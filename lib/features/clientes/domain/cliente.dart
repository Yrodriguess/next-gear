/// Ver seção 5.1 do Blueprint — três dimensões de status, nunca um
/// campo único misturando tudo.
enum StatusCadastro { rascunho, emAnalise, aprovado, reprovado }

/// "pendente" cobre rascunho e em análise — antes disso não existia,
/// e um rascunho recém-criado nascia direto como "aguardandoInstalacao",
/// o que não fazia sentido (rascunho nem foi enviado ainda) e podia
/// até interferir na checagem de CPF/CNPJ duplicado.
enum StatusOperacional { pendente, aguardandoInstalacao, ativo, suspenso, encerrado }

enum StatusFinanceiro { normal, alerta, bloqueado }

enum TipoDocumento { pessoaFisica, pessoaJuridica }

/// Período em que normalmente é mais fácil encontrar o responsável
/// no estabelecimento.
enum PeriodoPreferencialVisita { qualquerHorario, manha, tarde, noite }

/// Antecedência combinada com o cliente para avisar sobre a visita.
enum AntecedenciaAvisoVisita { naoAvisar, mesmoDia, umDiaAntes }

T _enumFromString<T>(List<T> values, String? value, T fallback) {
  if (value == null) return fallback;
  return values.firstWhere(
        (v) => v.toString().split('.').last == value,
    orElse: () => fallback,
  );
}

String _enumToString(Object enumValue) => enumValue.toString().split('.').last;

class Cliente {
  final String? id;
  final String orgId;

  final TipoDocumento tipoDocumento;
  final String cpfCnpj;
  final String nome; // nome completo (PF) ou razão social (PJ)
  final String? nomeFantasia; // só PJ

  // Endereço estruturado — decisão barata agora, cara de migrar
  // depois (o sistema já vai ter rotas, mapas e vendedores por
  // região, então texto livre não escala).
  final String cep;
  final String logradouro;
  final String numero;
  final String? complemento;
  final String bairro;
  final String cidade;
  final String uf;

  /// Link compartilhado do estabelecimento no Google Maps. Ele pertence ao
  /// cliente, não ao vendedor, para continuar válido quando a rota mudar de
  /// responsável.
  final String localizacaoMapsUrl;

  /// Foto usada pelo vendedor para reconhecer a fachada do comércio.
  final String? fotoFachadaUrl;

  final String nomeResponsavel;
  final String telefoneResponsavel;
  final String? emailResponsavel;

  final String? vendedorResponsavelId;
  final int prazoAcertoDias;

  /// Recados permanentes sobre o atendimento, por exemplo: "responsável só
  /// está à tarde" ou "ligar antes para separar o dinheiro".
  final String? observacoesOperacionais;

  final PeriodoPreferencialVisita periodoPreferencialVisita;
  final AntecedenciaAvisoVisita antecedenciaAvisoVisita;

  /// Mantido só por compatibilidade com clientes cadastrados antes da
  /// escolha de unidade física existir. Não usar em cadastros novos —
  /// use expositorFisicoSelecionadoId.
  final String? expositorModeloPretendidoId;

  /// A unidade física exata escolhida no cadastro (ex: EXP-GRA-023),
  /// não só o modelo. No rascunho isso é só uma intenção (não bloqueia
  /// nada); ao enviar para análise, essa unidade é reservada de
  /// verdade — ver ClienteRepository.enviarParaAnaliseComExpositor.
  final String? expositorFisicoSelecionadoId;

  /// Comissão que o VENDEDOR propôs no cadastro — ainda não validada
  /// por ninguém. Nunca usar esse campo em cálculo de venda.
  final int comissaoPropostaBasisPoints;

  /// Comissão de fato aprovada pelo financeiro/admin — é esse campo
  /// que entra nos cálculos de consignação (seção 5.3). Fica em 0 até
  /// a aprovação acontecer.
  final int comissaoBasisPoints;

  /// Limite de crédito em centavos — nunca double/float (seção 15.1).
  final int limiteCreditoCentavos;

  final StatusCadastro statusCadastro;
  final StatusOperacional statusOperacional;
  final StatusFinanceiro statusFinanceiro;

  /// Data definida/sugerida da próxima visita — editável a qualquer
  /// momento. Quando uma visita é finalizada, o sistema sugere
  /// "hoje + frequenciaVisitaDiasPadrao" automaticamente, mas isso
  /// nunca trava: dá pra sobrescrever na mão sempre.
  final DateTime? proximaVisitaEm;

  /// De quanto em quanto tempo (em dias) esse cliente costuma
  /// precisar de visita — usado como base pra sugestão automática.
  /// Ajustável por cliente porque cada loja vende num ritmo diferente.
  final int frequenciaVisitaDiasPadrao;

  const Cliente({
    this.id,
    required this.orgId,
    required this.tipoDocumento,
    required this.cpfCnpj,
    required this.nome,
    this.nomeFantasia,
    required this.cep,
    required this.logradouro,
    required this.numero,
    this.complemento,
    required this.bairro,
    required this.cidade,
    required this.uf,
    this.localizacaoMapsUrl = '',
    this.fotoFachadaUrl,
    required this.nomeResponsavel,
    required this.telefoneResponsavel,
    this.emailResponsavel,
    this.vendedorResponsavelId,
    required this.prazoAcertoDias,
    this.observacoesOperacionais,
    this.periodoPreferencialVisita =
        PeriodoPreferencialVisita.qualquerHorario,
    this.antecedenciaAvisoVisita = AntecedenciaAvisoVisita.naoAvisar,
    this.expositorModeloPretendidoId,
    this.expositorFisicoSelecionadoId,
    this.comissaoPropostaBasisPoints = 0,
    required this.comissaoBasisPoints,
    required this.limiteCreditoCentavos,
    this.statusCadastro = StatusCadastro.rascunho,
    this.statusOperacional = StatusOperacional.pendente,
    this.statusFinanceiro = StatusFinanceiro.normal,
    this.proximaVisitaEm,
    this.frequenciaVisitaDiasPadrao = 30,
  });

  /// Endereço pronto pra exibir numa linha — "Rua Exemplo, 123 -
  /// Bairro, Cidade/UF". Os campos estruturados continuam sendo a
  /// fonte de verdade; isso é só conveniência de exibição.
  String get enderecoResumo {
    final partes = <String>[
      if (logradouro.isNotEmpty)
        numero.isNotEmpty ? '$logradouro, $numero' : logradouro,
      if (bairro.isNotEmpty) bairro,
      if (cidade.isNotEmpty && uf.isNotEmpty)
        '$cidade/$uf'
      else if (cidade.isNotEmpty)
        cidade,
    ];
    return partes.join(' - ');
  }

  factory Cliente.fromFirestore(String id, Map<String, dynamic> data) {
    return Cliente(
      id: id,
      orgId: data['orgId'] as String? ?? '',
      tipoDocumento: _enumFromString(
          TipoDocumento.values, data['tipoDocumento'] as String?, TipoDocumento.pessoaJuridica),
      cpfCnpj: data['cpfCnpj'] as String? ?? '',
      nome: data['nome'] as String? ?? '',
      nomeFantasia: data['nomeFantasia'] as String?,
      cep: data['cep'] as String? ?? '',
      logradouro: data['logradouro'] as String? ?? '',
      numero: data['numero'] as String? ?? '',
      complemento: data['complemento'] as String?,
      bairro: data['bairro'] as String? ?? '',
      cidade: data['cidade'] as String? ?? '',
      uf: data['uf'] as String? ?? '',
      localizacaoMapsUrl: data['localizacaoMapsUrl'] as String? ?? '',
      fotoFachadaUrl: data['fotoFachadaUrl'] as String?,
      nomeResponsavel: data['nomeResponsavel'] as String? ?? '',
      telefoneResponsavel: data['telefoneResponsavel'] as String? ?? '',
      emailResponsavel: data['emailResponsavel'] as String?,
      vendedorResponsavelId: data['vendedorResponsavelId'] as String?,
      prazoAcertoDias: data['prazoAcertoDias'] as int? ?? 7,
      observacoesOperacionais:
      data['observacoesOperacionais'] as String?,
      periodoPreferencialVisita: _enumFromString(
        PeriodoPreferencialVisita.values,
        data['periodoPreferencialVisita'] as String?,
        PeriodoPreferencialVisita.qualquerHorario,
      ),
      antecedenciaAvisoVisita: _enumFromString(
        AntecedenciaAvisoVisita.values,
        data['antecedenciaAvisoVisita'] as String?,
        AntecedenciaAvisoVisita.naoAvisar,
      ),
      expositorModeloPretendidoId: data['expositorModeloPretendidoId'] as String?,
      expositorFisicoSelecionadoId: data['expositorFisicoSelecionadoId'] as String?,
      comissaoPropostaBasisPoints: data['comissaoPropostaBasisPoints'] as int? ?? 0,
      comissaoBasisPoints: data['comissaoBasisPoints'] as int? ?? 0,
      limiteCreditoCentavos: data['limiteCreditoCentavos'] as int? ?? 0,
      statusCadastro: _enumFromString(
          StatusCadastro.values, data['statusCadastro'] as String?, StatusCadastro.rascunho),
      statusOperacional: _enumFromString(StatusOperacional.values,
          data['statusOperacional'] as String?, StatusOperacional.pendente),
      statusFinanceiro: _enumFromString(
          StatusFinanceiro.values, data['statusFinanceiro'] as String?, StatusFinanceiro.normal),
      proximaVisitaEm: data['proximaVisitaEm'] != null
          ? (data['proximaVisitaEm'] as dynamic).toDate()
          : null,
      frequenciaVisitaDiasPadrao:
      data['frequenciaVisitaDiasPadrao'] as int? ?? 30,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'orgId': orgId,
      'tipoDocumento': _enumToString(tipoDocumento),
      'cpfCnpj': cpfCnpj,
      'nome': nome,
      'nomeFantasia': nomeFantasia,
      'cep': cep,
      'logradouro': logradouro,
      'numero': numero,
      'complemento': complemento,
      'bairro': bairro,
      'cidade': cidade,
      'uf': uf,
      'localizacaoMapsUrl': localizacaoMapsUrl,
      'fotoFachadaUrl': fotoFachadaUrl,
      'nomeResponsavel': nomeResponsavel,
      'telefoneResponsavel': telefoneResponsavel,
      'emailResponsavel': emailResponsavel,
      'vendedorResponsavelId': vendedorResponsavelId,
      'prazoAcertoDias': prazoAcertoDias,
      'observacoesOperacionais': observacoesOperacionais,
      'periodoPreferencialVisita':
      _enumToString(periodoPreferencialVisita),
      'antecedenciaAvisoVisita':
      _enumToString(antecedenciaAvisoVisita),
      'expositorModeloPretendidoId': expositorModeloPretendidoId,
      'expositorFisicoSelecionadoId': expositorFisicoSelecionadoId,
      'comissaoPropostaBasisPoints': comissaoPropostaBasisPoints,
      'comissaoBasisPoints': comissaoBasisPoints,
      'limiteCreditoCentavos': limiteCreditoCentavos,
      'statusCadastro': _enumToString(statusCadastro),
      'statusOperacional': _enumToString(statusOperacional),
      'statusFinanceiro': _enumToString(statusFinanceiro),
      'proximaVisitaEm': proximaVisitaEm,
      'frequenciaVisitaDiasPadrao': frequenciaVisitaDiasPadrao,
    };
  }

  Cliente copyWith({
    TipoDocumento? tipoDocumento,
    String? cpfCnpj,
    String? nome,
    String? nomeFantasia,
    String? cep,
    String? logradouro,
    String? numero,
    String? complemento,
    String? bairro,
    String? cidade,
    String? uf,
    String? localizacaoMapsUrl,
    String? fotoFachadaUrl,
    String? nomeResponsavel,
    String? telefoneResponsavel,
    String? emailResponsavel,
    String? vendedorResponsavelId,
    int? prazoAcertoDias,
    String? observacoesOperacionais,
    PeriodoPreferencialVisita? periodoPreferencialVisita,
    AntecedenciaAvisoVisita? antecedenciaAvisoVisita,
    String? expositorModeloPretendidoId,
    String? expositorFisicoSelecionadoId,
    int? comissaoPropostaBasisPoints,
    int? comissaoBasisPoints,
    int? limiteCreditoCentavos,
    StatusCadastro? statusCadastro,
    StatusOperacional? statusOperacional,
    StatusFinanceiro? statusFinanceiro,
    DateTime? proximaVisitaEm,
    int? frequenciaVisitaDiasPadrao,
  }) {
    return Cliente(
      id: id,
      orgId: orgId,
      tipoDocumento: tipoDocumento ?? this.tipoDocumento,
      cpfCnpj: cpfCnpj ?? this.cpfCnpj,
      nome: nome ?? this.nome,
      nomeFantasia: nomeFantasia ?? this.nomeFantasia,
      cep: cep ?? this.cep,
      logradouro: logradouro ?? this.logradouro,
      numero: numero ?? this.numero,
      complemento: complemento ?? this.complemento,
      bairro: bairro ?? this.bairro,
      cidade: cidade ?? this.cidade,
      uf: uf ?? this.uf,
      localizacaoMapsUrl: localizacaoMapsUrl ?? this.localizacaoMapsUrl,
      fotoFachadaUrl: fotoFachadaUrl ?? this.fotoFachadaUrl,
      nomeResponsavel: nomeResponsavel ?? this.nomeResponsavel,
      telefoneResponsavel: telefoneResponsavel ?? this.telefoneResponsavel,
      emailResponsavel: emailResponsavel ?? this.emailResponsavel,
      vendedorResponsavelId: vendedorResponsavelId ?? this.vendedorResponsavelId,
      prazoAcertoDias: prazoAcertoDias ?? this.prazoAcertoDias,
      observacoesOperacionais:
      observacoesOperacionais ?? this.observacoesOperacionais,
      periodoPreferencialVisita:
      periodoPreferencialVisita ?? this.periodoPreferencialVisita,
      antecedenciaAvisoVisita:
      antecedenciaAvisoVisita ?? this.antecedenciaAvisoVisita,
      expositorModeloPretendidoId:
      expositorModeloPretendidoId ?? this.expositorModeloPretendidoId,
      expositorFisicoSelecionadoId:
      expositorFisicoSelecionadoId ?? this.expositorFisicoSelecionadoId,
      comissaoPropostaBasisPoints:
      comissaoPropostaBasisPoints ?? this.comissaoPropostaBasisPoints,
      comissaoBasisPoints: comissaoBasisPoints ?? this.comissaoBasisPoints,
      limiteCreditoCentavos: limiteCreditoCentavos ?? this.limiteCreditoCentavos,
      statusCadastro: statusCadastro ?? this.statusCadastro,
      statusOperacional: statusOperacional ?? this.statusOperacional,
      statusFinanceiro: statusFinanceiro ?? this.statusFinanceiro,
      proximaVisitaEm: proximaVisitaEm ?? this.proximaVisitaEm,
      frequenciaVisitaDiasPadrao:
      frequenciaVisitaDiasPadrao ?? this.frequenciaVisitaDiasPadrao,
    );
  }
}
