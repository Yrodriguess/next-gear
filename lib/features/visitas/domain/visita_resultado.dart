import '../../produtos/domain/sku.dart';

/// Um item que o vendedor está trazendo pra repor/instalar — o SKU
/// escolhido na tela (é ele que se movimenta em estoque, seção 6.3 do
/// Blueprint) + quantidade. A descrição já vem pronta de quem criou o
/// ItemReposicao, porque combina o nome do Produto com a variação do
/// SKU ("Cabo USB-C Turbo — Preto 1m") — o SKU sozinho não carrega o
/// nome do produto. Preço/custo/comissão são sempre os vigentes agora,
/// capturados no momento em que a consignação é criada (seção 7.7).
class ItemReposicao {
  final Sku sku;
  final String descricaoSnapshot;
  final int quantidade;

  const ItemReposicao({
    required this.sku,
    required this.descricaoSnapshot,
    required this.quantidade,
  });
}

/// Um item pronto pra aparecer numa tabela de documento — já traz tudo
/// calculado com os valores CONGELADOS do ciclo em questão (nunca
/// consulta o preço atual do cadastro), o PDF só formata.
class ItemDocumento {
  final String skuId;
  final String codigoInterno;
  final String descricao;

  /// Quantidade "final" desse item nessa tabela — instalada (1ª vez),
  /// nova posição (reposição) ou saldo anterior (acerto, ver abaixo).
  final int quantidade;

  final int precoVendaCentavosUnit;

  /// Ganho do cliente por unidade vendida (a comissão dele) — o resto
  /// do preço de venda é o que volta pra NEXT GEAR.
  final int comissaoCentavosUnit;

  // Só preenchidos nos itens do "ciclo encerrado" (acerto) — ver
  // VisitaResultado.itensCicloEncerrado.
  final int? saldoAnteriorQuantidade;

  /// A quantidade que o VENDEDOR de fato informou na conferência —
  /// nunca reconstruída por subtração depois. É esse número, e só
  /// ele, que representa o que realmente aconteceu na visita.
  final int? quantidadeConferida;

  final int? quantidadeReposta;

  const ItemDocumento({
    required this.skuId,
    required this.codigoInterno,
    required this.descricao,
    required this.quantidade,
    required this.precoVendaCentavosUnit,
    required this.comissaoCentavosUnit,
    this.saldoAnteriorQuantidade,
    this.quantidadeConferida,
    this.quantidadeReposta,
  });

  /// "Repasse unit." — quanto volta pra NEXT GEAR por unidade vendida.
  int get repasseCentavosUnit => precoVendaCentavosUnit - comissaoCentavosUnit;

  int get vendaPotencialCentavos => precoVendaCentavosUnit * quantidade;
  int get repassePotencialCentavos => repasseCentavosUnit * quantidade;
  int get ganhoPotencialCentavos => comissaoCentavosUnit * quantidade;

  /// Vendido = saldo anterior − quantidade conferida (nunca o
  /// contrário — a conferência é o dado real, a venda é derivada dela).
  int get quantidadeVendida =>
      (saldoAnteriorQuantidade ?? 0) - (quantidadeConferida ?? 0);

  int get repasseDevidoCentavos => quantidadeVendida * repasseCentavosUnit;
  int get ganhoRealizadoCentavos => quantidadeVendida * comissaoCentavosUnit;
}

/// O que aconteceu com a unidade que não voltou — define a
/// consequência: gera cobrança + movimenta estoque pro destino
/// definitivo certo (vendido/avaria/extravio), ou fica como pendência
/// operacional sem mexer em nada (ficou no cliente / outro).
enum ClassificacaoNaoDevolvida {
  vendido,
  avariado,
  extraviado,
  naoLocalizado,
  ficouNoCliente,
  outro,
}

String classificacaoNaoDevolvidaLabel(ClassificacaoNaoDevolvida c) => switch (c) {
  ClassificacaoNaoDevolvida.vendido => 'Vendido',
  ClassificacaoNaoDevolvida.avariado => 'Avariado',
  ClassificacaoNaoDevolvida.extraviado => 'Extraviado',
  ClassificacaoNaoDevolvida.naoLocalizado => 'Não localizado',
  ClassificacaoNaoDevolvida.ficouNoCliente => 'Ficou no cliente',
  ClassificacaoNaoDevolvida.outro => 'Outro',
};

/// Vendido/avariado/extraviado/não localizado: o cliente ainda deve o
/// repasse dessa unidade, mesmo que não tenha sido uma venda de
/// verdade — é mercadoria que saiu da posição consignada sem voltar.
/// "Ficou no cliente"/"Outro": fica como pendência, sem cobrança
/// automática nem movimentação de estoque — alguém decide depois.
bool classificacaoGeraCobranca(ClassificacaoNaoDevolvida c) =>
    c != ClassificacaoNaoDevolvida.ficouNoCliente &&
        c != ClassificacaoNaoDevolvida.outro;

/// Um produto conferido na hora da retirada — o vendedor informa
/// quanto voltou fisicamente. NUNCA classificamos automaticamente a
/// diferença como "venda" — quem decide é o próprio vendedor, item a
/// item, através de `classificacao`.
class ItemRetirada {
  final String produtoId;
  final String codigoInterno;
  final String descricaoSnapshot;
  final int quantidadeEsperada;
  final int quantidadeDevolvida;

  /// Só obrigatório quando quantidadeNaoDevolvida > 0.
  final ClassificacaoNaoDevolvida? classificacao;

  const ItemRetirada({
    required this.produtoId,
    required this.codigoInterno,
    required this.descricaoSnapshot,
    required this.quantidadeEsperada,
    required this.quantidadeDevolvida,
    this.classificacao,
  });

  int get quantidadeNaoDevolvida => quantidadeEsperada - quantidadeDevolvida;
}

/// Um item pronto pra tabela do Termo de Retirada — já com os valores
/// congelados da consignação que está sendo encerrada.
class ItemDocumentoRetirada {
  final String codigoInterno;
  final String descricao;
  final int saldoEsperado;
  final int quantidadeDevolvida;
  final int repasseCentavosUnit;
  final String? classificacaoLabel;
  final bool geraCobranca;

  const ItemDocumentoRetirada({
    required this.codigoInterno,
    required this.descricao,
    required this.saldoEsperado,
    required this.quantidadeDevolvida,
    required this.repasseCentavosUnit,
    this.classificacaoLabel,
    this.geraCobranca = false,
  });

  int get quantidadeNaoDevolvida => saldoEsperado - quantidadeDevolvida;
  int get valorARepassarCentavos =>
      geraCobranca ? quantidadeNaoDevolvida * repasseCentavosUnit : 0;
}

/// Motivo declarado da retirada — pro cabeçalho do Termo de Retirada.
enum MotivoRetirada { solicitacaoCliente, decisaoNextGear, encerramentoParceria, outro }

String motivoRetiradaLabel(MotivoRetirada m) => switch (m) {
  MotivoRetirada.solicitacaoCliente => 'Solicitação do cliente',
  MotivoRetirada.decisaoNextGear => 'Decisão da NEXT GEAR',
  MotivoRetirada.encerramentoParceria => 'Encerramento da parceria',
  MotivoRetirada.outro => 'Outro',
};

/// Resumo do que aconteceu ao retirar um expositor de um cliente —
/// equivalente ao VisitaResultado, mas pra retirada (que não abre
/// consignação nova).
class RetiradaResultado {
  /// ID real do documento da visita no Firestore.
  final String visitaId;
  final String visitaNumero;
  final String consignmentEncerradaNumero;
  final String expositorNumero;
  final String expositorModeloNome;
  final MotivoRetirada motivo;
  final String destinoExpositorLabel;
  final List<ItemDocumentoRetirada> itens;
  final int valorARepassarTotalCentavos;

  const RetiradaResultado({
    required this.visitaId,
    required this.visitaNumero,
    required this.consignmentEncerradaNumero,
    required this.expositorNumero,
    required this.expositorModeloNome,
    required this.motivo,
    required this.destinoExpositorLabel,
    required this.itens,
    required this.valorARepassarTotalCentavos,
  });
}

/// Resumo do que aconteceu ao finalizar uma visita — usado pra
/// mostrar a tela de resultado e gerar o documento (seção 7.9 do
/// Blueprint).
class VisitaResultado {
  /// ID real do documento da visita no Firestore.
  final String visitaId;
  final String visitaNumero;
  final String? consignmentAntigaNumero;
  final String consignmentNovaNumero;
  final int totalVendidoCentavos;
  final int comissaoRetidaCentavos;
  final int valorAPagarNextGearCentavos;
  final int novaExposicaoCentavos;

  /// Pro cabeçalho dos termos (Instalação/Reposição) — qual unidade
  /// física está em jogo.
  final String? expositorNumero;
  final String? expositorModeloNome;

  /// Itens do ciclo que ENCERROU — só existe em reposição, nunca em
  /// instalação. Cada item aqui carrega saldoAnteriorQuantidade e
  /// quantidadeConferida, usados na tabela "Acerto do ciclo encerrado".
  /// Produto vendido totalmente e não reposto continua aparecendo
  /// aqui, mesmo que não apareça mais em itensNovaPosicao.
  final List<ItemDocumento> itensCicloEncerrado;

  /// Itens da posição NOVA — o mix inicial (instalação) ou o que
  /// ficou consignado depois da reposição. Produto com saldo final
  /// zero não aparece aqui.
  final List<ItemDocumento> itensNovaPosicao;

  const VisitaResultado({
    required this.visitaId,
    required this.visitaNumero,
    this.consignmentAntigaNumero,
    required this.consignmentNovaNumero,
    this.totalVendidoCentavos = 0,
    this.comissaoRetidaCentavos = 0,
    this.valorAPagarNextGearCentavos = 0,
    required this.novaExposicaoCentavos,
    this.expositorNumero,
    this.expositorModeloNome,
    this.itensCicloEncerrado = const [],
    this.itensNovaPosicao = const [],
  });
}