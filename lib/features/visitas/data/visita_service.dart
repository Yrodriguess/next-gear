import '../../clientes/data/cliente_repository.dart';
import '../../clientes/domain/cliente.dart';
import '../../consignacoes/data/consignment_repository.dart';
import '../../consignacoes/domain/consignment.dart';
import '../../consignacoes/domain/consignment_item.dart';
import '../../estoque/data/estoque_repository.dart';
import '../../estoque/domain/stock_movement.dart';
import '../../expositores/data/expositor_fisico_repository.dart';
import '../../expositores/domain/expositor_fisico.dart';
import '../../financeiro/data/recebivel_repository.dart';
import '../domain/conferencia_item.dart';
import '../domain/visita.dart';
import '../domain/visita_exceptions.dart';
import '../domain/visita_resultado.dart';
import 'visita_repository.dart';

/// Orquestra tudo que uma visita precisa fazer, juntando os módulos
/// de Cliente, Consignação, Estoque, Expositor, Financeiro e Visita.
/// Ver seções 7.2 a 8.2 do Blueprint — este é o "coração do sistema".
///
/// NOTA: numa versão de produção mais madura, isso deveria rodar
/// inteiro numa Cloud Function, numa única transação de verdade
/// (ver seção 15.2 do Blueprint — rascunho → validação → commit).
class VisitaService {
  final ClienteRepository _clienteRepository;
  final ConsignmentRepository _consignmentRepository;
  final EstoqueRepository _estoqueRepository;
  final VisitaRepository _visitaRepository;
  final ExpositorFisicoRepository _expositorRepository;
  final RecebivelRepository _recebivelRepository;

  VisitaService({
    ClienteRepository? clienteRepository,
    ConsignmentRepository? consignmentRepository,
    EstoqueRepository? estoqueRepository,
    VisitaRepository? visitaRepository,
    ExpositorFisicoRepository? expositorRepository,
    RecebivelRepository? recebivelRepository,
  })  : _clienteRepository = clienteRepository ?? ClienteRepository(),
        _consignmentRepository = consignmentRepository ?? ConsignmentRepository(),
        _estoqueRepository = estoqueRepository ?? EstoqueRepository(),
        _visitaRepository = visitaRepository ?? VisitaRepository(),
        _expositorRepository = expositorRepository ?? ExpositorFisicoRepository(),
        _recebivelRepository = recebivelRepository ?? RecebivelRepository();

  /// Valida TODO o estoque necessário antes de mover qualquer unidade —
  /// ver seção 15.2 do Blueprint ("rascunho → validação → commit").
  /// necessidades: mapa de "origemId|skuId" -> quantidade total
  /// que vai ser retirada dali durante a operação inteira.
  Future<void> _validarEstoqueDisponivel(
      Map<String, int> necessidades) async {
    for (final entry in necessidades.entries) {
      final partes = entry.key.split('|');
      final origem = partes[0];
      final skuId = partes[1];
      final necessario = entry.value;

      final disponivel = await _estoqueRepository.obterSaldo(origem, skuId);
      if (disponivel < necessario) {
        throw EstoqueInsuficienteException(
          local: origem,
          disponivel: disponivel,
          solicitado: necessario,
        );
      }
    }
  }

  /// Reutiliza a visita iniciada na Agenda. O fallback de criação mantém as
  /// telas antigas funcionando enquanto elas ainda não enviam [visitaId].
  Future<String> _obterOuCriarVisitaId({
    required String orgId,
    required String clienteId,
    required String vendedorId,
    required VisitaTipo tipo,
    String? visitaId,
    DateTime? dataPrevista,
    String? consignmentId,
    String? expositorId,
  }) async {
    final idInformado = visitaId?.trim();

    if (idInformado == null || idInformado.isEmpty) {
      final visitaExistente =
      await _visitaRepository.buscarEmAndamentoDoCliente(
        orgId: orgId,
        clienteId: clienteId,
      );

      if (visitaExistente != null) {
        if (visitaExistente.vendedorId != vendedorId) {
          throw StateError(
            'A visita deste cliente foi iniciada por outro vendedor.',
          );
        }

        if (visitaExistente.tipo != tipo) {
          throw StateError(
            'Existe uma visita em andamento para este cliente, '
                'mas ela corresponde a outra operação.',
          );
        }

        final idExistente = visitaExistente.id;

        if (idExistente == null || idExistente.isEmpty) {
          throw StateError(
            'A visita em andamento possui identificador inválido.',
          );
        }

        return idExistente;
      }

      return _visitaRepository.iniciar(
        orgId: orgId,
        clienteId: clienteId,
        vendedorId: vendedorId,
        tipo: tipo,
        dataPrevista: dataPrevista,
        consignmentId: consignmentId,
        expositorId: expositorId,
      );
    }

    final visita = await _visitaRepository.buscarById(idInformado);

    if (visita == null) {
      throw StateError('A visita iniciada não foi encontrada.');
    }

    if (visita.orgId != orgId) {
      throw StateError('A visita pertence a outra organização.');
    }

    if (visita.clienteId != clienteId) {
      throw StateError('A visita não pertence ao cliente selecionado.');
    }

    if (visita.vendedorId != vendedorId) {
      throw StateError('A visita foi iniciada por outro vendedor.');
    }

    if (visita.tipo != tipo) {
      throw StateError('A visita não corresponde a esta operação.');
    }

    if (!visita.emAndamento) {
      throw StateError('Esta visita não está mais em andamento.');
    }

    if (consignmentId != null &&
        visita.consignmentId != null &&
        visita.consignmentId != consignmentId) {
      throw StateError('A visita pertence a outra consignação.');
    }

    if (expositorId != null &&
        visita.expositorId != null &&
        visita.expositorId != expositorId) {
      throw StateError('A visita pertence a outro expositor.');
    }

    final precisaVincularConsignacao =
        consignmentId != null && visita.consignmentId == null;
    final precisaVincularExpositor =
        expositorId != null && visita.expositorId == null;

    if (precisaVincularConsignacao || precisaVincularExpositor) {
      await _visitaRepository.atualizarVinculos(
        visitaId: idInformado,
        consignmentId:
        precisaVincularConsignacao ? consignmentId : null,
        expositorId: precisaVincularExpositor ? expositorId : null,
      );
    }

    return idInformado;
  }

  Map<String, dynamic> _itemDocumentoParaSnapshot(
      ItemDocumento item,
      ) {
    return {
      'skuId': item.skuId,
      'codigoInterno': item.codigoInterno,
      'descricao': item.descricao,
      'quantidade': item.quantidade,
      'precoVendaCentavosUnit': item.precoVendaCentavosUnit,
      'comissaoCentavosUnit': item.comissaoCentavosUnit,
      'saldoAnteriorQuantidade': item.saldoAnteriorQuantidade,
      'quantidadeConferida': item.quantidadeConferida,
      'quantidadeReposta': item.quantidadeReposta,
    };
  }

  Map<String, dynamic> _itemRetiradaParaSnapshot(
      ItemDocumentoRetirada item,
      ) {
    return {
      'codigoInterno': item.codigoInterno,
      'descricao': item.descricao,
      'saldoEsperado': item.saldoEsperado,
      'quantidadeDevolvida': item.quantidadeDevolvida,
      'repasseCentavosUnit': item.repasseCentavosUnit,
      'classificacaoLabel': item.classificacaoLabel,
      'geraCobranca': item.geraCobranca,
    };
  }

  Map<String, dynamic> _dadosBaseDocumento({
    required String tipoDocumento,
    required Cliente cliente,
    required String vendedorId,
  }) {
    return {
      'versao': 1,
      'tipoDocumento': tipoDocumento,
      'clienteId': cliente.id,
      'clienteNome': cliente.nome,
      'clienteNomeFantasia': cliente.nomeFantasia,
      'clienteCpfCnpj': cliente.cpfCnpj,
      'vendedorId': vendedorId,
    };
  }

  Future<VisitaResultado> executarInstalacao({
    required String orgId,
    required Cliente cliente,
    required String vendedorId,
    required List<ItemReposicao> itensInstalados,
    required String expositorId,
    String? expositorNumero,
    String? expositorModeloNome,
    String? visitaId,
    DateTime? dataPrevista,
  }) async {
    if (itensInstalados.isEmpty) {
      throw StateError(
        'A instalação precisa ter pelo menos um produto.',
      );
    }

    for (final item in itensInstalados) {
      final skuId = item.sku.id;

      if (skuId == null || skuId.isEmpty) {
        throw StateError(
          'Existe produto sem identificador de estoque.',
        );
      }
    }

    final clienteId = cliente.id?.trim();

    if (clienteId == null || clienteId.isEmpty) {
      throw StateError('Cliente sem identificador válido.');
    }

    // Recarrega o cliente no momento da confirmação. Assim limite de
    // crédito e comissão alterados enquanto a tela estava aberta não
    // são validados com dados antigos.
    final clienteAtual = await _clienteRepository.fetchById(clienteId);

    if (clienteAtual == null) {
      throw StateError('Cliente não encontrado.');
    }

    if (clienteAtual.orgId != orgId) {
      throw StateError('O cliente não pertence a esta organização.');
    }

    final itensConsignment = itensInstalados
        .map(
          (item) => ConsignmentItem.calcular(
        produtoId: item.sku.id!,
        descricaoSnapshot: item.descricaoSnapshot,
        quantidade: item.quantidade,
        precoVendaCentavos: item.sku.precoVendaCentavos,
        custoAquisicaoCentavos: item.sku.custoInicialCentavos,
        comissaoBasisPoints: clienteAtual.comissaoBasisPoints,
      ),
    )
        .toList();

    final novaExposicao = itensConsignment.fold<int>(
      0,
          (soma, item) => soma + item.valorLiquidoTotalCentavos,
    );

    // Considera TODAS as consignações ativas do cliente. Isso é
    // importante quando o mesmo cliente possui mais de um expositor.
    final consignacoesAtivas = await _consignmentRepository
        .watchTodasAtivasDoCliente(clienteAtual.id!)
        .first;

    final exposicaoAtual = consignacoesAtivas.fold<int>(
      0,
          (soma, consignacao) =>
      soma + consignacao.valorLiquidoTotalCentavos,
    );

    final exposicaoAposInstalacao =
        exposicaoAtual + novaExposicao;

    if (exposicaoAposInstalacao >
        clienteAtual.limiteCreditoCentavos) {
      throw LimiteExcedidoException(
        exposicaoAposInstalacao -
            clienteAtual.limiteCreditoCentavos,
      );
    }

    // Valida TODO o estoque antes de criar/mover qualquer coisa.
    final origemVendedor = LocalEstoque.vendedor(vendedorId);
    final necessidades = <String, int>{};

    for (final item in itensInstalados) {
      final skuId = item.sku.id;

      if (skuId == null || skuId.isEmpty) {
        throw StateError(
          'Existe produto sem identificador de estoque.',
        );
      }

      final chave = '$origemVendedor|$skuId';
      necessidades[chave] =
          (necessidades[chave] ?? 0) + item.quantidade;
    }

    await _validarEstoqueDisponivel(necessidades);

    final idVisita = await _obterOuCriarVisitaId(
      orgId: orgId,
      clienteId: clienteAtual.id!,
      vendedorId: vendedorId,
      tipo: VisitaTipo.instalacao,
      visitaId: visitaId,
      dataPrevista: dataPrevista,
      expositorId: expositorId,
    );

    try {
      for (final item in itensInstalados) {
        await _estoqueRepository.registrarMovimento(
          orgId: orgId,
          produtoId: item.sku.id!,
          quantidade: item.quantidade,
          origem: origemVendedor,
          destino: LocalEstoque.cliente(clienteAtual.id!),
          motivo: MovimentoMotivo.instalacao,
          usuarioId: vendedorId,
          custoUnitarioCentavosNoMomento: item.sku.custoInicialCentavos,
        );
      }

      await _expositorRepository.confirmarInstalacao(
        expositorId: expositorId,
        clienteId: clienteAtual.id!,
        usuarioId: vendedorId,
      );

      final consignmentNumero = await _consignmentRepository.criarInicial(
        orgId: orgId,
        clienteId: clienteAtual.id!,
        expositorId: expositorId,
        itens: itensConsignment,
        visitaId: idVisita,
      );

      // Instalação não tem "ciclo anterior" — é a primeira vez.
      final itensNovaPosicao = itensConsignment
          .map((item) => ItemDocumento(
        skuId: item.produtoId,
        codigoInterno: itensInstalados
            .firstWhere((i) => i.sku.id == item.produtoId)
            .sku
            .codigoInterno,
        descricao: item.descricaoSnapshot,
        quantidade: item.quantidade,
        precoVendaCentavosUnit: item.precoVendaCentavos,
        comissaoCentavosUnit: item.comissaoCentavos,
      ))
          .toList();

      final documentoSnapshot = <String, dynamic>{
        ..._dadosBaseDocumento(
          tipoDocumento: 'instalacao',
          cliente: clienteAtual,
          vendedorId: vendedorId,
        ),
        'consignmentNovaNumero': consignmentNumero,
        'novaExposicaoCentavos': novaExposicao,
        'expositorNumero': expositorNumero,
        'expositorModeloNome': expositorModeloNome,
        'itensCicloEncerrado': const <Map<String, dynamic>>[],
        'itensNovaPosicao':
        itensNovaPosicao.map(_itemDocumentoParaSnapshot).toList(),
      };

      final visitaNumero = await _visitaRepository.finalizar(
        orgId,
        idVisita,
        documentoSnapshot: documentoSnapshot,
      );

      // Sugere a próxima visita — nunca trava nada, é só um lembrete
      // que pode ser sobrescrito a qualquer momento na ficha do cliente.
      await _clienteRepository.sugerirProximaVisitaAposFinalizar(
        clienteId: clienteAtual.id!,
        frequenciaVisitaDiasPadrao: clienteAtual.frequenciaVisitaDiasPadrao,
      );

      return VisitaResultado(
        visitaId: idVisita,
        visitaNumero: visitaNumero,
        consignmentNovaNumero: consignmentNumero,
        novaExposicaoCentavos: novaExposicao,
        expositorNumero: expositorNumero,
        expositorModeloNome: expositorModeloNome,
        itensNovaPosicao: itensNovaPosicao,
      );
    } catch (e) {
      await _visitaRepository.cancelar(idVisita);
      rethrow;
    }
  }

  Future<VisitaResultado> executarVisita({
    required String orgId,
    required Cliente cliente,
    required String vendedorId,
    required Consignment consignmentAtiva,
    required List<ConferenciaItem> conferencia,
    required List<ItemReposicao> itensReposicao,
    String? visitaId,
    DateTime? dataPrevista,
  }) async {
    final inadimplente = cliente.statusFinanceiro == StatusFinanceiro.bloqueado;
    if (inadimplente && itensReposicao.isNotEmpty) {
      throw ReposicaoBloqueadaException();
    }

    // Monta as necessidades de TODAS as movimentações que essa visita
    // vai fazer, e valida tudo de uma vez, antes de criar a visita ou
    // mover qualquer unidade — evita o cenário de "consumiu estoque
    // mas não finalizou" (seção 15.2 do Blueprint).
    final necessidades = <String, int>{};
    final origemCliente = LocalEstoque.cliente(cliente.id!);
    final origemVendedor = LocalEstoque.vendedor(vendedorId);

    for (final item in conferencia) {
      if (!item.temDiferenca || item.diferenca <= 0) continue;
      if (item.classificacaoDiferenca == null) continue;
      final destino = switch (item.classificacaoDiferenca) {
        ClassificacaoDiferenca.vendido => LocalEstoque.vendido,
        ClassificacaoDiferenca.avaria => LocalEstoque.avaria,
        ClassificacaoDiferenca.extravio => LocalEstoque.extravio,
        ClassificacaoDiferenca.devolvido => origemVendedor,
        _ => null,
      };
      if (destino == null) continue;
      final chave = '$origemCliente|${item.produtoId}';
      necessidades[chave] = (necessidades[chave] ?? 0) + item.diferenca;
    }

    for (final item in itensReposicao) {
      final chave = '$origemVendedor|${item.sku.id}';
      necessidades[chave] = (necessidades[chave] ?? 0) + item.quantidade;
    }

    await _validarEstoqueDisponivel(necessidades);

    final idVisita = await _obterOuCriarVisitaId(
      orgId: orgId,
      clienteId: cliente.id!,
      vendedorId: vendedorId,
      tipo: VisitaTipo.visita,
      visitaId: visitaId,
      dataPrevista: dataPrevista,
      consignmentId: consignmentAtiva.id,
      expositorId: consignmentAtiva.expositorId,
    );

    try {
      final novosItensPorProduto = <String, ConsignmentItem>{};

      for (final item in conferencia) {
        if (item.quantidadeEncontrada <= 0) continue;
        final itemAntigo = consignmentAtiva.itens
            .firstWhere((i) => i.produtoId == item.produtoId);
        novosItensPorProduto[item.produtoId] = ConsignmentItem.calcular(
          produtoId: item.produtoId,
          descricaoSnapshot: item.descricaoSnapshot,
          quantidade: item.quantidadeEncontrada,
          precoVendaCentavos: itemAntigo.precoVendaCentavos,
          custoAquisicaoCentavos: itemAntigo.custoAquisicaoCentavos,
          comissaoBasisPoints: cliente.comissaoBasisPoints,
        );
      }

      for (final item in itensReposicao) {
        final existente = novosItensPorProduto[item.sku.id];
        final quantidadeTotal = (existente?.quantidade ?? 0) + item.quantidade;
        novosItensPorProduto[item.sku.id!] = ConsignmentItem.calcular(
          produtoId: item.sku.id!,
          descricaoSnapshot: item.descricaoSnapshot,
          quantidade: quantidadeTotal,
          precoVendaCentavos: item.sku.precoVendaCentavos,
          custoAquisicaoCentavos: item.sku.custoInicialCentavos,
          comissaoBasisPoints: cliente.comissaoBasisPoints,
        );
      }

      final novosItens = novosItensPorProduto.values.toList();

      final novaExposicao = novosItens.fold<int>(
          0, (soma, item) => soma + item.valorLiquidoTotalCentavos);
      if (novaExposicao > cliente.limiteCreditoCentavos) {
        throw LimiteExcedidoException(novaExposicao - cliente.limiteCreditoCentavos);
      }

      int totalVendidoCentavos = 0;
      int comissaoRetidaCentavos = 0;

      for (final item in conferencia) {
        if (!item.temDiferenca) continue;
        final itemAntigo =
        consignmentAtiva.itens.firstWhere((i) => i.produtoId == item.produtoId);

        final destino = switch (item.classificacaoDiferenca) {
          ClassificacaoDiferenca.vendido => LocalEstoque.vendido,
          ClassificacaoDiferenca.avaria => LocalEstoque.avaria,
          ClassificacaoDiferenca.extravio => LocalEstoque.extravio,
          ClassificacaoDiferenca.devolvido => LocalEstoque.vendedor(vendedorId),
          _ => null,
        };

        if (destino != null && item.diferenca > 0) {
          await _estoqueRepository.registrarMovimento(
            orgId: orgId,
            produtoId: item.produtoId,
            quantidade: item.diferenca,
            origem: LocalEstoque.cliente(cliente.id!),
            destino: destino,
            motivo: item.classificacaoDiferenca == ClassificacaoDiferenca.vendido
                ? MovimentoMotivo.vendaApurada
                : item.classificacaoDiferenca == ClassificacaoDiferenca.avaria
                ? MovimentoMotivo.avaria
                : item.classificacaoDiferenca == ClassificacaoDiferenca.extravio
                ? MovimentoMotivo.extravio
                : MovimentoMotivo.devolucao,
            usuarioId: vendedorId,
            custoUnitarioCentavosNoMomento: itemAntigo.custoAquisicaoCentavos,
            valorVendaCentavosNoMomento:
            item.classificacaoDiferenca == ClassificacaoDiferenca.vendido
                ? itemAntigo.precoVendaCentavos
                : null,
            comissaoCentavosNoMomento:
            item.classificacaoDiferenca == ClassificacaoDiferenca.vendido
                ? itemAntigo.comissaoCentavos
                : null,
          );
        }

        if (item.classificacaoDiferenca == ClassificacaoDiferenca.vendido) {
          totalVendidoCentavos += itemAntigo.precoVendaCentavos * item.quantidadeVendida;
          comissaoRetidaCentavos += itemAntigo.comissaoCentavos * item.quantidadeVendida;
        }
      }

      for (final item in itensReposicao) {
        await _estoqueRepository.registrarMovimento(
          orgId: orgId,
          produtoId: item.sku.id!,
          quantidade: item.quantidade,
          origem: LocalEstoque.vendedor(vendedorId),
          destino: LocalEstoque.cliente(cliente.id!),
          motivo: MovimentoMotivo.reposicao,
          usuarioId: vendedorId,
          custoUnitarioCentavosNoMomento: item.sku.custoInicialCentavos,
        );
      }

      final consignmentNovaNumero = await _consignmentRepository.encerrarEAbrirNova(
        orgId: orgId,
        clienteId: cliente.id!,
        expositorId: consignmentAtiva.expositorId,
        consignmentAtivaId: consignmentAtiva.id!,
        novosItens: novosItens,
        visitaId: idVisita,
      );

      final valorAPagarNextGearCentavos = totalVendidoCentavos - comissaoRetidaCentavos;

      if (valorAPagarNextGearCentavos > 0) {
        await _recebivelRepository.criarAPartirDaVisita(
          orgId: orgId,
          clienteId: cliente.id!,
          visitaId: idVisita,
          valorCentavos: valorAPagarNextGearCentavos,
          prazoAcertoDias: cliente.prazoAcertoDias,
        );
      }

      // Busca o expositor só pra exibir número/modelo no documento —
      // não influencia nenhum cálculo.
      final expositor = consignmentAtiva.expositorId != null
          ? await _expositorRepository
          .watchById(orgId, consignmentAtiva.expositorId!)
          .first
          : null;

      // ── Duas listas separadas pro documento (ver plano de docs) ──
      final repostaPorProduto = <String, int>{
        for (final item in itensReposicao) item.sku.id!: item.quantidade,
      };
      final codigoInternoPorProduto = <String, String>{
        for (final item in itensReposicao) item.sku.id!: item.sku.codigoInterno,
      };

      // "Ciclo encerrado" — TODO produto que estava na consignação
      // antiga, mesmo que tenha sumido totalmente (vendido e não
      // reposto). quantidadeConferida vem direto do que o vendedor
      // realmente informou na conferência — nunca reconstruída.
      final itensCicloEncerrado = consignmentAtiva.itens.map((itemAntigo) {
        final conferenciaItem = conferencia
            .where((c) => c.produtoId == itemAntigo.produtoId)
            .firstOrNull;
        return ItemDocumento(
          skuId: itemAntigo.produtoId,
          codigoInterno:
          codigoInternoPorProduto[itemAntigo.produtoId] ?? itemAntigo.produtoId,
          descricao: itemAntigo.descricaoSnapshot,
          quantidade: itemAntigo.quantidade,
          precoVendaCentavosUnit: itemAntigo.precoVendaCentavos,
          comissaoCentavosUnit: itemAntigo.comissaoCentavos,
          saldoAnteriorQuantidade: itemAntigo.quantidade,
          quantidadeConferida:
          conferenciaItem?.quantidadeEncontrada ?? itemAntigo.quantidade,
        );
      }).toList();

      // "Nova posição" — só o que sobrou/foi reposto com saldo final
      // maior que zero. Produto novo (sem histórico anterior) entra
      // aqui naturalmente, já que só depende de novosItensPorProduto.
      final itensNovaPosicao = novosItens
          .where((item) => item.quantidade > 0)
          .map((item) => ItemDocumento(
        skuId: item.produtoId,
        codigoInterno:
        codigoInternoPorProduto[item.produtoId] ?? item.produtoId,
        descricao: item.descricaoSnapshot,
        quantidade: item.quantidade,
        precoVendaCentavosUnit: item.precoVendaCentavos,
        comissaoCentavosUnit: item.comissaoCentavos,
        quantidadeReposta: repostaPorProduto[item.produtoId] ?? 0,
      ))
          .toList();

      final documentoSnapshot = <String, dynamic>{
        ..._dadosBaseDocumento(
          tipoDocumento: 'reposicao',
          cliente: cliente,
          vendedorId: vendedorId,
        ),
        'consignmentAntigaNumero': consignmentAtiva.numero,
        'consignmentNovaNumero': consignmentNovaNumero,
        'totalVendidoCentavos': totalVendidoCentavos,
        'comissaoRetidaCentavos': comissaoRetidaCentavos,
        'valorAPagarNextGearCentavos': valorAPagarNextGearCentavos,
        'novaExposicaoCentavos': novaExposicao,
        'expositorNumero': expositor?.numero,
        'expositorModeloNome': expositor?.modeloNome,
        'itensCicloEncerrado':
        itensCicloEncerrado.map(_itemDocumentoParaSnapshot).toList(),
        'itensNovaPosicao':
        itensNovaPosicao.map(_itemDocumentoParaSnapshot).toList(),
      };

      final visitaNumero = await _visitaRepository.finalizar(
        orgId,
        idVisita,
        documentoSnapshot: documentoSnapshot,
      );

      // Sugere a próxima visita — nunca trava nada, é só um lembrete
      // que pode ser sobrescrito a qualquer momento na ficha do cliente.
      await _clienteRepository.sugerirProximaVisitaAposFinalizar(
        clienteId: cliente.id!,
        frequenciaVisitaDiasPadrao: cliente.frequenciaVisitaDiasPadrao,
      );

      return VisitaResultado(
        visitaId: idVisita,
        visitaNumero: visitaNumero,
        consignmentAntigaNumero: consignmentAtiva.numero,
        consignmentNovaNumero: consignmentNovaNumero,
        totalVendidoCentavos: totalVendidoCentavos,
        comissaoRetidaCentavos: comissaoRetidaCentavos,
        valorAPagarNextGearCentavos: valorAPagarNextGearCentavos,
        novaExposicaoCentavos: novaExposicao,
        expositorNumero: expositor?.numero,
        expositorModeloNome: expositor?.modeloNome,
        itensCicloEncerrado: itensCicloEncerrado,
        itensNovaPosicao: itensNovaPosicao,
      );
    } catch (e) {
      await _visitaRepository.cancelar(idVisita);
      rethrow;
    }
  }

  /// Retirada de expositor com conferência de verdade — vira uma
  /// visita do tipo "coleta" (o campo já existia, nunca tinha sido
  /// usado). Move o que voltou fisicamente pro estoque do vendedor,
  /// registra financeiramente o que NÃO voltou (sem chamar isso de
  /// "venda" em lugar nenhum), encerra a consignação e retira o
  /// expositor — tudo dentro do mesmo fluxo auditado.
  Future<RetiradaResultado> executarRetirada({
    required String orgId,
    required Cliente cliente,
    required String vendedorId,
    required Consignment consignmentAtiva,
    required List<ItemRetirada> conferenciaRetirada,
    required String expositorId,
    required String expositorNumero,
    required String expositorModeloNome,
    required DestinoRetirada destinoExpositor,
    required String destinoExpositorLabel,
    required MotivoRetirada motivo,
    String? observacao,
    EstadoConservacao? estadoConservacaoExpositor,
    String? visitaId,
    DateTime? dataPrevista,
  }) async {
    // Valida antes de criar ou recuperar a visita. Uma classificação ausente
    // não deve cancelar uma visita que já estava aberta na Agenda.
    for (final item in conferenciaRetirada) {
      if (item.quantidadeNaoDevolvida > 0 && item.classificacao == null) {
        throw ArgumentError(
          'Classifique o que aconteceu com '
              '"${item.descricaoSnapshot}" antes de confirmar.',
        );
      }
    }

    final idVisita = await _obterOuCriarVisitaId(
      orgId: orgId,
      clienteId: cliente.id!,
      vendedorId: vendedorId,
      tipo: VisitaTipo.coleta,
      visitaId: visitaId,
      dataPrevista: dataPrevista,
      consignmentId: consignmentAtiva.id,
      expositorId: expositorId,
    );

    try {
      for (final item in conferenciaRetirada) {
        final itemAntigo = consignmentAtiva.itens
            .firstWhere((i) => i.produtoId == item.produtoId);

        // A parte que voltou fisicamente sempre segue pro estoque do
        // vendedor, independente da classificação do resto.
        if (item.quantidadeDevolvida > 0) {
          await _estoqueRepository.registrarMovimento(
            orgId: orgId,
            produtoId: item.produtoId,
            quantidade: item.quantidadeDevolvida,
            origem: LocalEstoque.cliente(cliente.id!),
            destino: LocalEstoque.vendedor(vendedorId),
            motivo: MovimentoMotivo.devolucao,
            usuarioId: vendedorId,
            custoUnitarioCentavosNoMomento: itemAntigo.custoAquisicaoCentavos,
          );
        }

        // A parte que NÃO voltou só movimenta estoque se a
        // classificação tiver um destino definitivo (vendido/avariado/
        // extraviado/não localizado). "Ficou no cliente" e "Outro"
        // ficam como pendência — não mexem no estoque.
        if (item.quantidadeNaoDevolvida > 0) {
          final destinoEstoque = switch (item.classificacao!) {
            ClassificacaoNaoDevolvida.vendido => LocalEstoque.vendido,
            ClassificacaoNaoDevolvida.avariado => LocalEstoque.avaria,
            ClassificacaoNaoDevolvida.extraviado => LocalEstoque.extravio,
            ClassificacaoNaoDevolvida.naoLocalizado => LocalEstoque.extravio,
            _ => null,
          };
          if (destinoEstoque != null) {
            final motivoEstoque = switch (item.classificacao!) {
              ClassificacaoNaoDevolvida.vendido => MovimentoMotivo.vendaApurada,
              ClassificacaoNaoDevolvida.avariado => MovimentoMotivo.avaria,
              _ => MovimentoMotivo.extravio,
            };
            await _estoqueRepository.registrarMovimento(
              orgId: orgId,
              produtoId: item.produtoId,
              quantidade: item.quantidadeNaoDevolvida,
              origem: LocalEstoque.cliente(cliente.id!),
              destino: destinoEstoque,
              motivo: motivoEstoque,
              usuarioId: vendedorId,
              custoUnitarioCentavosNoMomento: itemAntigo.custoAquisicaoCentavos,
              valorVendaCentavosNoMomento:
              item.classificacao == ClassificacaoNaoDevolvida.vendido
                  ? itemAntigo.precoVendaCentavos
                  : null,
              comissaoCentavosNoMomento:
              item.classificacao == ClassificacaoNaoDevolvida.vendido
                  ? itemAntigo.comissaoCentavos
                  : null,
            );
          }
        }
      }

      // Encerra a consignação sem abrir nova — a retirada não deixa
      // nada consignado nesse expositor.
      await _consignmentRepository.encerrarSemNova(
        consignmentAtivaId: consignmentAtiva.id!,
        visitaId: idVisita,
      );

      // Retira o expositor de verdade — já cuida de status, local e
      // histórico do expositor (ver ExpositorFisicoRepository).
      await _expositorRepository.retirarDoCliente(
        expositorId: expositorId,
        destino: destinoExpositor,
        usuarioId: vendedorId,
        observacao: observacao ?? '',
        estadoConservacao: estadoConservacaoExpositor,
      );

      // Se esta era a última consignação ativa do cliente, encerra a
      // operação do cliente também. Se ainda houver outro expositor/
      // consignação ativa, ele permanece Ativo normalmente.
      final consignacoesRestantes = await _consignmentRepository
          .watchTodasAtivasDoCliente(cliente.id!)
          .first;

      if (consignacoesRestantes.isEmpty) {
        await _clienteRepository.encerrarOperacaoAposUltimaRetirada(
          clienteId: cliente.id!,
          usuarioId: vendedorId,
        );
      }

      final itensDocumento = conferenciaRetirada.map((item) {
        final itemAntigo = consignmentAtiva.itens
            .firstWhere((i) => i.produtoId == item.produtoId);
        return ItemDocumentoRetirada(
          codigoInterno: item.codigoInterno,
          descricao: item.descricaoSnapshot,
          saldoEsperado: item.quantidadeEsperada,
          quantidadeDevolvida: item.quantidadeDevolvida,
          repasseCentavosUnit:
          itemAntigo.precoVendaCentavos - itemAntigo.comissaoCentavos,
          classificacaoLabel: item.classificacao != null
              ? classificacaoNaoDevolvidaLabel(item.classificacao!)
              : null,
          geraCobranca: item.classificacao != null
              ? classificacaoGeraCobranca(item.classificacao!)
              : false,
        );
      }).toList();

      final valorARepassarTotal = itensDocumento.fold<int>(
          0, (soma, item) => soma + item.valorARepassarCentavos);

      // Só cria cobrança se sobrou algo não devolvido pra acertar.
      if (valorARepassarTotal > 0) {
        await _recebivelRepository.criarAPartirDaVisita(
          orgId: orgId,
          clienteId: cliente.id!,
          visitaId: idVisita,
          valorCentavos: valorARepassarTotal,
          prazoAcertoDias: cliente.prazoAcertoDias,
        );
      }

      final documentoSnapshot = <String, dynamic>{
        ..._dadosBaseDocumento(
          tipoDocumento: 'retirada',
          cliente: cliente,
          vendedorId: vendedorId,
        ),
        'consignmentEncerradaNumero': consignmentAtiva.numero,
        'expositorNumero': expositorNumero,
        'expositorModeloNome': expositorModeloNome,
        'motivo': motivo.name,
        'motivoLabel': motivoRetiradaLabel(motivo),
        'destinoExpositorLabel': destinoExpositorLabel,
        'valorARepassarTotalCentavos': valorARepassarTotal,
        'itens': itensDocumento.map(_itemRetiradaParaSnapshot).toList(),
      };

      final visitaNumero = await _visitaRepository.finalizar(
        orgId,
        idVisita,
        documentoSnapshot: documentoSnapshot,
      );

      return RetiradaResultado(
        visitaId: idVisita,
        visitaNumero: visitaNumero,
        consignmentEncerradaNumero: consignmentAtiva.numero,
        expositorNumero: expositorNumero,
        expositorModeloNome: expositorModeloNome,
        motivo: motivo,
        destinoExpositorLabel: destinoExpositorLabel,
        itens: itensDocumento,
        valorARepassarTotalCentavos: valorARepassarTotal,
      );
    } catch (e) {
      await _visitaRepository.cancelar(idVisita);
      rethrow;
    }
  }
}
