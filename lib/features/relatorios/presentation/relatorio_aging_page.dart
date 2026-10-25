import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/firestore_collections.dart';
import '../../auth/presentation/usuario_providers.dart';
import '../../clientes/presentation/cliente_detail_page.dart';
import '../../clientes/presentation/cliente_providers.dart';
import '../../consignacoes/presentation/consignment_providers.dart';
import '../../estoque/domain/estoque_saldo.dart';
import '../../estoque/domain/stock_movement.dart';
import '../../estoque/presentation/estoque_providers.dart';
import '../../expositores/presentation/expositor_providers.dart';
import '../../produtos/domain/sku.dart';
import '../../produtos/presentation/produto_providers.dart';
import 'relatorios_ui.dart';

enum _FaixaAging {
  todas,
  ate30,
  de31a60,
  de61a90,
  acima90,
  semData,
  dataInconsistente,
}

enum _SituacaoVisita {
  todas,
  atrasada,
  hoje,
  estaSemana,
  futura,
  semAgendamento,
}

enum _FaixaValor { todos, acimaMil, acimaTresMil, acimaCincoMil }

enum _OrdemAging {
  prioridade,
  maisAntigos,
  maiorCusto,
  maiorVenda,
  cliente,
}

/// Posição financeira das consignações ativas nos clientes.
///
/// O aging representa o tempo desde a abertura da consignação ativa atual.
/// Para medir a idade real de cada unidade será necessário preservar
/// `entrouEmCampoEm` no item em uma evolução futura do domínio.
class RelatorioAgingPage extends ConsumerStatefulWidget {
  const RelatorioAgingPage({super.key});

  @override
  ConsumerState<RelatorioAgingPage> createState() =>
      _RelatorioAgingPageState();
}

class _RelatorioAgingPageState extends ConsumerState<RelatorioAgingPage> {
  final _buscaController = TextEditingController();

  _FaixaAging _faixa = _FaixaAging.todas;
  _SituacaoVisita _situacaoVisita = _SituacaoVisita.todas;
  _FaixaValor _faixaValor = _FaixaValor.todos;
  _OrdemAging _ordem = _OrdemAging.prioridade;
  String? _clienteSelecionadoId;
  String? _vendedorSelecionadoId;
  int _limiteDetalhamento = 50;

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  _IdadeConsignacao _calcularIdade(DateTime? criadaEm) {
    if (criadaEm == null) {
      return const _IdadeConsignacao(
        dias: null,
        faixa: _FaixaAging.semData,
      );
    }

    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final abertura = DateTime(criadaEm.year, criadaEm.month, criadaEm.day);
    if (abertura.isAfter(hoje)) {
      return const _IdadeConsignacao(
        dias: null,
        faixa: _FaixaAging.dataInconsistente,
      );
    }

    final dias = hoje.difference(abertura).inDays;
    final faixa = dias <= 30
        ? _FaixaAging.ate30
        : dias <= 60
        ? _FaixaAging.de31a60
        : dias <= 90
        ? _FaixaAging.de61a90
        : _FaixaAging.acima90;
    return _IdadeConsignacao(dias: dias, faixa: faixa);
  }

  _SituacaoVisita _calcularSituacaoVisita(DateTime? proximaVisitaEm) {
    if (proximaVisitaEm == null) return _SituacaoVisita.semAgendamento;

    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final prevista = DateTime(
      proximaVisitaEm.year,
      proximaVisitaEm.month,
      proximaVisitaEm.day,
    );
    if (prevista.isBefore(hoje)) return _SituacaoVisita.atrasada;
    if (prevista.isAtSameMomentAs(hoje)) return _SituacaoVisita.hoje;

    final domingo = hoje.add(Duration(days: DateTime.sunday - hoje.weekday));
    if (!prevista.isAfter(domingo)) return _SituacaoVisita.estaSemana;
    return _SituacaoVisita.futura;
  }

  bool _atendeFaixaValor(int custoCentavos) => switch (_faixaValor) {
    _FaixaValor.todos => true,
    _FaixaValor.acimaMil => custoCentavos >= 100000,
    _FaixaValor.acimaTresMil => custoCentavos >= 300000,
    _FaixaValor.acimaCincoMil => custoCentavos >= 500000,
  };

  void _recarregar() {
    ref.invalidate(consignmentsAtivasProvider(AppConfig.currentOrgId));
    ref.invalidate(saldosDaOrganizacaoProvider(AppConfig.currentOrgId));
    ref.invalidate(skusListProvider);
    ref.invalidate(clientesListProvider);
    ref.invalidate(expositoresFisicosListProvider);
    ref.invalidate(usuariosListProvider);
  }

  void _limparFiltros() {
    setState(() {
      _buscaController.clear();
      _faixa = _FaixaAging.todas;
      _situacaoVisita = _SituacaoVisita.todas;
      _faixaValor = _FaixaValor.todos;
      _ordem = _OrdemAging.prioridade;
      _clienteSelecionadoId = null;
      _vendedorSelecionadoId = null;
      _limiteDetalhamento = 50;
    });
  }

  void _abrirCliente(String? clienteId) {
    if (clienteId == null || clienteId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClienteDetailPage(clienteId: clienteId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orgId = AppConfig.currentOrgId;
    final consignacoesAsync = ref.watch(consignmentsAtivasProvider(orgId));
    final saldosAsync = ref.watch(saldosDaOrganizacaoProvider(orgId));
    final skusAsync = ref.watch(skusListProvider);
    final clientesAsync = ref.watch(clientesListProvider);
    final expositoresAsync = ref.watch(expositoresFisicosListProvider);
    final usuariosAsync = ref.watch(usuariosListProvider);

    if (consignacoesAsync.hasError ||
        saldosAsync.hasError ||
        skusAsync.hasError ||
        clientesAsync.hasError ||
        expositoresAsync.hasError ||
        usuariosAsync.hasError) {
      return RelatorioErrorState(onRetry: _recarregar);
    }
    if ((consignacoesAsync.isLoading && !consignacoesAsync.hasValue) ||
        (saldosAsync.isLoading && !saldosAsync.hasValue) ||
        (skusAsync.isLoading && !skusAsync.hasValue) ||
        (clientesAsync.isLoading && !clientesAsync.hasValue) ||
        (expositoresAsync.isLoading && !expositoresAsync.hasValue) ||
        (usuariosAsync.isLoading && !usuariosAsync.hasValue)) {
      return const RelatorioLoading();
    }

    final consignacoes = consignacoesAsync.value;
    final saldos = saldosAsync.value;
    final skus = skusAsync.value;
    final clientes = clientesAsync.value;
    final expositores = expositoresAsync.value;
    final usuarios = usuariosAsync.value;
    if (consignacoes == null ||
        saldos == null ||
        skus == null ||
        clientes == null ||
        expositores == null ||
        usuarios == null) {
      return const RelatorioLoading();
    }

    final clientePorId = {
      for (final cliente in clientes)
        if (cliente.id != null) cliente.id!: cliente,
    };
    final expositorPorId = {
      for (final expositor in expositores)
        if (expositor.id != null) expositor.id!: expositor,
    };
    final usuarioPorId = {for (final usuario in usuarios) usuario.uid: usuario};
    final skuPorId = {
      for (final sku in skus)
        if (sku.id != null) sku.id!: sku,
    };

    final estoqueCentral = _ResumoEstoque.calcular(
      saldos.where((saldo) => saldo.localId == LocalEstoque.central),
      skuPorId,
    );
    final estoqueVendedores = _ResumoEstoque.calcular(
      saldos.where(
            (saldo) => saldo.localId.startsWith(LocalEstoque.vendedor('')),
      ),
      skuPorId,
    );

    final todasLinhas = consignacoes.map((consignacao) {
      final cliente = clientePorId[consignacao.clienteId];
      final expositor = expositorPorId[consignacao.expositorId];
      final vendedorId = cliente?.vendedorResponsavelId;
      final vendedor = vendedorId == null ? null : usuarioPorId[vendedorId];
      final nomeCliente = cliente?.nomeFantasia?.trim().isNotEmpty == true
          ? cliente!.nomeFantasia!.trim()
          : cliente?.nome ?? 'Cliente não localizado';
      final idade = _calcularIdade(consignacao.criadaEm);
      final situacaoVisita =
      _calcularSituacaoVisita(cliente?.proximaVisitaEm);

      var unidades = 0;
      var custo = 0;
      var vendaBruta = 0;
      var comissao = 0;
      var repasse = 0;
      for (final item in consignacao.itens) {
        unidades += item.quantidade;
        custo += item.quantidade * item.custoAquisicaoCentavos;
        vendaBruta += item.quantidade * item.precoVendaCentavos;
        comissao += item.quantidade * item.comissaoCentavos;
        repasse += item.valorLiquidoTotalCentavos;
      }

      return _AgingLinha(
        consignacaoId: consignacao.id,
        clienteId: consignacao.clienteId,
        cliente: nomeCliente,
        cpfCnpj: cliente?.cpfCnpj ?? '',
        vendedorId: vendedorId,
        vendedor: vendedor?.nome ?? 'Sem vendedor responsável',
        expositor: expositor == null
            ? consignacao.expositorId ?? 'Expositor não localizado'
            : '${expositor.numero} · ${expositor.modeloNome}',
        abertaEm: consignacao.criadaEm,
        proximaVisitaEm: cliente?.proximaVisitaEm,
        dias: idade.dias,
        faixa: idade.faixa,
        situacaoVisita: situacaoVisita,
        unidades: unidades,
        custoCentavos: custo,
        vendaBrutaCentavos: vendaBruta,
        comissaoCentavos: comissao,
        repasseCentavos: repasse,
      );
    }).toList();

    final query = _buscaController.text.trim().toLowerCase();
    final queryNumerica = query.replaceAll(RegExp(r'\D'), '');
    final linhasBaseFaixa = todasLinhas.where((linha) {
      if (_clienteSelecionadoId != null &&
          linha.clienteId != _clienteSelecionadoId) {
        return false;
      }
      if (_vendedorSelecionadoId != null &&
          linha.vendedorId != _vendedorSelecionadoId) {
        return false;
      }
      if (_situacaoVisita != _SituacaoVisita.todas &&
          linha.situacaoVisita != _situacaoVisita) {
        return false;
      }
      if (!_atendeFaixaValor(linha.custoCentavos)) return false;
      if (query.isEmpty) return true;

      final documento = linha.cpfCnpj.replaceAll(RegExp(r'\D'), '');
      return linha.cliente.toLowerCase().contains(query) ||
          linha.expositor.toLowerCase().contains(query) ||
          linha.vendedor.toLowerCase().contains(query) ||
          (linha.consignacaoId ?? '').toLowerCase().contains(query) ||
          (queryNumerica.isNotEmpty && documento.contains(queryNumerica));
    }).toList();

    final linhas = linhasBaseFaixa.where((linha) {
      return _faixa == _FaixaAging.todas || linha.faixa == _faixa;
    }).toList();
    _ordenarLinhas(linhas, _ordem);

    final resumo = _ResumoCampo.calcular(linhas);
    final resumoGeral = _ResumoCampo.calcular(todasLinhas);
    final capitalTotalCentavos = estoqueCentral.custoCentavos +
        estoqueVendedores.custoCentavos +
        resumoGeral.custoCentavos;
    final unidadesTotais = estoqueCentral.unidades +
        estoqueVendedores.unidades +
        resumoGeral.unidades;
    final unidadesSemSku =
        estoqueCentral.unidadesSemSku + estoqueVendedores.unidadesSemSku;
    final linhasExibidas = linhas.take(_limiteDetalhamento).toList();
    final filtrosAtivos = query.isNotEmpty ||
        _faixa != _FaixaAging.todas ||
        _situacaoVisita != _SituacaoVisita.todas ||
        _faixaValor != _FaixaValor.todos ||
        _ordem != _OrdemAging.prioridade ||
        _clienteSelecionadoId != null ||
        _vendedorSelecionadoId != null;

    final clientesOrdenados = clientes
        .where((cliente) => cliente.id != null)
        .map(
          (cliente) => _OpcaoFiltro(
        id: cliente.id!,
        label: cliente.nomeFantasia?.trim().isNotEmpty == true
            ? cliente.nomeFantasia!.trim()
            : cliente.nome,
      ),
    )
        .toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    final vendedoresOrdenados = usuarios
        .map((usuario) => _OpcaoFiltro(id: usuario.uid, label: usuario.nome))
        .toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

    return SingleChildScrollView(
      child: RelatorioPageBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RelatorioIntro(
              title: 'Capital em campo',
              subtitle:
              'Acompanhe custo, potencial financeiro, tempo da posição atual e agenda das consignações.',
              icon: Icons.hourglass_bottom,
              action: OutlinedButton.icon(
                onPressed: _recarregar,
                icon: const Icon(Icons.refresh),
                label: const Text('Atualizar'),
              ),
            ),
            const SizedBox(height: 20),
            const _TituloGrupo(
              title: 'Distribuição do capital',
              subtitle: 'Onde estão os produtos da empresa neste momento',
            ),
            const SizedBox(height: 12),
            RelatorioMetricsGrid(
              children: [
                RelatorioMetricCard(
                  label: 'Estoque central',
                  value: formatarReais(estoqueCentral.custoCentavos),
                  hint: '${estoqueCentral.unidades} unidades · custo cadastrado',
                  icon: Icons.warehouse_outlined,
                  color: Colors.lightBlue,
                ),
                RelatorioMetricCard(
                  label: 'Carga dos vendedores',
                  value: formatarReais(estoqueVendedores.custoCentavos),
                  hint:
                  '${estoqueVendedores.unidades} unidades · ${estoqueVendedores.locais} cargas',
                  icon: Icons.local_shipping_outlined,
                  color: Colors.orange,
                ),
                RelatorioMetricCard(
                  label: 'Produtos consignados',
                  value: formatarReais(resumoGeral.custoCentavos),
                  hint:
                  '${resumoGeral.unidades} unidades · ${resumoGeral.clientes} clientes',
                  icon: Icons.storefront_outlined,
                  color: Colors.green,
                ),
                RelatorioMetricCard(
                  label: 'Capital total em produtos',
                  value: formatarReais(capitalTotalCentavos),
                  hint: '$unidadesTotais unidades nos três locais',
                  icon: Icons.account_balance_wallet_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              unidadesSemSku > 0
                  ? '$unidadesSemSku unidades do central ou das cargas estão sem SKU localizado e não entraram no valor. Central e cargas usam o custo inicial cadastrado; o consignado usa o custo histórico da consignação.'
                  : 'Central e cargas usam o custo inicial cadastrado no SKU. O consignado usa o custo histórico congelado na consignação.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            _FiltrosAging(
              buscaController: _buscaController,
              clientes: clientesOrdenados,
              vendedores: vendedoresOrdenados,
              clienteSelecionadoId: _clienteSelecionadoId,
              vendedorSelecionadoId: _vendedorSelecionadoId,
              situacaoVisita: _situacaoVisita,
              faixaValor: _faixaValor,
              ordem: _ordem,
              resultados: linhas.length,
              onBuscaChanged: (_) => setState(() => _limiteDetalhamento = 50),
              onClienteChanged: (value) => setState(() {
                _clienteSelecionadoId = value;
                _limiteDetalhamento = 50;
              }),
              onVendedorChanged: (value) => setState(() {
                _vendedorSelecionadoId = value;
                _limiteDetalhamento = 50;
              }),
              onSituacaoChanged: (value) => setState(() {
                _situacaoVisita = value;
                _limiteDetalhamento = 50;
              }),
              onFaixaValorChanged: (value) => setState(() {
                _faixaValor = value;
                _limiteDetalhamento = 50;
              }),
              onOrdemChanged: (value) => setState(() {
                _ordem = value;
                _limiteDetalhamento = 50;
              }),
              onClear: filtrosAtivos ? _limparFiltros : null,
            ),
            const SizedBox(height: 20),
            _TituloGrupo(
              title: 'Potencial financeiro das consignações',
              subtitle: filtrosAtivos
                  ? 'Valores considerando os filtros aplicados'
                  : '${todasLinhas.length} consignações ativas',
            ),
            const SizedBox(height: 12),
            RelatorioMetricsGrid(
              children: [
                RelatorioMetricCard(
                  label: 'Capital a custo na rua',
                  value: formatarReais(resumo.custoCentavos),
                  hint: '${resumo.unidades} unidades consignadas',
                  icon: Icons.account_balance_wallet_outlined,
                  color: Colors.lightBlue,
                ),
                RelatorioMetricCard(
                  label: 'Venda bruta potencial',
                  value: formatarReais(resumo.vendaBrutaCentavos),
                  hint: 'Se toda a posição for vendida',
                  icon: Icons.payments_outlined,
                  color: Colors.green,
                ),
                RelatorioMetricCard(
                  label: 'Comissão potencial',
                  value: formatarReais(resumo.comissaoCentavos),
                  hint: 'Valor que os lojistas poderão reter',
                  icon: Icons.handshake_outlined,
                  color: Colors.orange,
                ),
                RelatorioMetricCard(
                  label: 'Repasse potencial NEXT',
                  value: formatarReais(resumo.repasseCentavos),
                  hint: 'Venda bruta menos comissão',
                  icon: Icons.account_balance_outlined,
                  color: Colors.lightBlue,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _IndicadoresSecundarios(resumo: resumo),
            const SizedBox(height: 20),
            _DistribuicaoFaixas(
              linhas: linhasBaseFaixa,
              faixaSelecionada: _faixa,
              onSelected: (faixa) => setState(() {
                _faixa = _faixa == faixa ? _FaixaAging.todas : faixa;
                _limiteDetalhamento = 50;
              }),
            ),
            const SizedBox(height: 20),
            _PrioridadesCard(linhas: todasLinhas, resumo: resumoGeral),
            const SizedBox(height: 20),
            RelatorioSectionCard(
              title: _faixa == _FaixaAging.todas
                  ? 'Consignações ativas'
                  : _faixaLabel(_faixa),
              subtitle: linhas.isEmpty
                  ? 'Nenhum resultado encontrado'
                  : 'Mostrando ${linhasExibidas.length} de ${linhas.length} consignações',
              child: linhas.isEmpty
                  ? RelatorioEmptyState(
                icon: Icons.inventory_2_outlined,
                title: consignacoes.isEmpty
                    ? 'Nenhuma consignação ativa'
                    : 'Nenhuma consignação encontrada',
                message: consignacoes.isEmpty
                    ? 'Quando houver mercadoria nos clientes, a análise aparecerá aqui.'
                    : 'Altere ou limpe os filtros para ampliar os resultados.',
                action: consignacoes.isEmpty
                    ? null
                    : TextButton.icon(
                  onPressed: _limparFiltros,
                  icon: const Icon(Icons.filter_alt_off_outlined),
                  label: const Text('Limpar filtros'),
                ),
              )
                  : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AgingResultado(
                    linhas: linhasExibidas,
                    onAbrirCliente: _abrirCliente,
                  ),
                  if (linhasExibidas.length < linhas.length) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.center,
                      child: OutlinedButton.icon(
                        onPressed: () => setState(
                              () => _limiteDetalhamento += 50,
                        ),
                        icon: const Icon(Icons.expand_more),
                        label: Text(
                          'Mostrar mais ${math.min(50, linhas.length - linhasExibidas.length)}',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'O tempo em campo considera a abertura da consignação ativa atual. Os valores são potenciais e refletem os itens que permanecem no cliente; não representam vendas já realizadas.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IdadeConsignacao {
  final int? dias;
  final _FaixaAging faixa;

  const _IdadeConsignacao({required this.dias, required this.faixa});
}

class _AgingLinha {
  final String? consignacaoId;
  final String? clienteId;
  final String cliente;
  final String cpfCnpj;
  final String? vendedorId;
  final String vendedor;
  final String expositor;
  final DateTime? abertaEm;
  final DateTime? proximaVisitaEm;
  final int? dias;
  final _FaixaAging faixa;
  final _SituacaoVisita situacaoVisita;
  final int unidades;
  final int custoCentavos;
  final int vendaBrutaCentavos;
  final int comissaoCentavos;
  final int repasseCentavos;

  const _AgingLinha({
    required this.consignacaoId,
    required this.clienteId,
    required this.cliente,
    required this.cpfCnpj,
    required this.vendedorId,
    required this.vendedor,
    required this.expositor,
    required this.abertaEm,
    required this.proximaVisitaEm,
    required this.dias,
    required this.faixa,
    required this.situacaoVisita,
    required this.unidades,
    required this.custoCentavos,
    required this.vendaBrutaCentavos,
    required this.comissaoCentavos,
    required this.repasseCentavos,
  });

  int get resultadoPotencialCentavos => repasseCentavos - custoCentavos;

  double? get margemPotencial {
    if (repasseCentavos == 0) return null;
    return resultadoPotencialCentavos / repasseCentavos * 100;
  }
}

class _ResumoEstoque {
  final int unidades;
  final int custoCentavos;
  final int locais;
  final int unidadesSemSku;

  const _ResumoEstoque({
    required this.unidades,
    required this.custoCentavos,
    required this.locais,
    required this.unidadesSemSku,
  });

  factory _ResumoEstoque.calcular(
      Iterable<EstoqueSaldo> saldos,
      Map<String, Sku> skuPorId,
      ) {
    var unidades = 0;
    var custo = 0;
    var unidadesSemSku = 0;
    final locais = <String>{};

    for (final saldo in saldos) {
      if (saldo.quantidade <= 0) continue;
      unidades += saldo.quantidade;
      locais.add(saldo.localId);

      final sku = skuPorId[saldo.produtoId];
      if (sku == null) {
        unidadesSemSku += saldo.quantidade;
        continue;
      }
      custo += saldo.quantidade * sku.custoInicialCentavos;
    }

    return _ResumoEstoque(
      unidades: unidades,
      custoCentavos: custo,
      locais: locais.length,
      unidadesSemSku: unidadesSemSku,
    );
  }
}

class _ResumoCampo {
  final int consignacoes;
  final int clientes;
  final int unidades;
  final int custoCentavos;
  final int vendaBrutaCentavos;
  final int comissaoCentavos;
  final int repasseCentavos;
  final int resultadoCentavos;
  final double? idadeMediaPonderada;
  final int custoCriticoCentavos;

  const _ResumoCampo({
    required this.consignacoes,
    required this.clientes,
    required this.unidades,
    required this.custoCentavos,
    required this.vendaBrutaCentavos,
    required this.comissaoCentavos,
    required this.repasseCentavos,
    required this.resultadoCentavos,
    required this.idadeMediaPonderada,
    required this.custoCriticoCentavos,
  });

  double? get margemPotencial => repasseCentavos == 0
      ? null
      : resultadoCentavos / repasseCentavos * 100;

  factory _ResumoCampo.calcular(List<_AgingLinha> linhas) {
    var unidades = 0;
    var custo = 0;
    var venda = 0;
    var comissao = 0;
    var repasse = 0;
    var resultado = 0;
    var custoCritico = 0;
    var pesoIdade = 0.0;
    var pesoTotal = 0;
    final clientes = <String>{};

    for (final linha in linhas) {
      unidades += linha.unidades;
      custo += linha.custoCentavos;
      venda += linha.vendaBrutaCentavos;
      comissao += linha.comissaoCentavos;
      repasse += linha.repasseCentavos;
      resultado += linha.resultadoPotencialCentavos;
      if (linha.faixa == _FaixaAging.acima90) {
        custoCritico += linha.custoCentavos;
      }
      if (linha.clienteId != null) clientes.add(linha.clienteId!);
      if (linha.dias != null && linha.custoCentavos > 0) {
        pesoIdade += linha.dias! * linha.custoCentavos;
        pesoTotal += linha.custoCentavos;
      }
    }

    return _ResumoCampo(
      consignacoes: linhas.length,
      clientes: clientes.length,
      unidades: unidades,
      custoCentavos: custo,
      vendaBrutaCentavos: venda,
      comissaoCentavos: comissao,
      repasseCentavos: repasse,
      resultadoCentavos: resultado,
      idadeMediaPonderada: pesoTotal == 0 ? null : pesoIdade / pesoTotal,
      custoCriticoCentavos: custoCritico,
    );
  }
}

class _OpcaoFiltro {
  final String id;
  final String label;

  const _OpcaoFiltro({required this.id, required this.label});
}

class _FiltrosAging extends StatelessWidget {
  final TextEditingController buscaController;
  final List<_OpcaoFiltro> clientes;
  final List<_OpcaoFiltro> vendedores;
  final String? clienteSelecionadoId;
  final String? vendedorSelecionadoId;
  final _SituacaoVisita situacaoVisita;
  final _FaixaValor faixaValor;
  final _OrdemAging ordem;
  final int resultados;
  final ValueChanged<String> onBuscaChanged;
  final ValueChanged<String?> onClienteChanged;
  final ValueChanged<String?> onVendedorChanged;
  final ValueChanged<_SituacaoVisita> onSituacaoChanged;
  final ValueChanged<_FaixaValor> onFaixaValorChanged;
  final ValueChanged<_OrdemAging> onOrdemChanged;
  final VoidCallback? onClear;

  const _FiltrosAging({
    required this.buscaController,
    required this.clientes,
    required this.vendedores,
    required this.clienteSelecionadoId,
    required this.vendedorSelecionadoId,
    required this.situacaoVisita,
    required this.faixaValor,
    required this.ordem,
    required this.resultados,
    required this.onBuscaChanged,
    required this.onClienteChanged,
    required this.onVendedorChanged,
    required this.onSituacaoChanged,
    required this.onFaixaValorChanged,
    required this.onOrdemChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return RelatorioSectionCard(
      title: 'Filtros',
      subtitle: '$resultados consignações encontradas',
      trailing: onClear == null
          ? null
          : TextButton.icon(
        onPressed: onClear,
        icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
        label: const Text('Limpar'),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final largura = constraints.maxWidth;
          final campo = largura >= 1060
              ? (largura - 24) / 3
              : largura >= 680
              ? (largura - 12) / 2
              : largura;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: campo,
                child: RelatorioSearchField(
                  controller: buscaController,
                  hint: 'Cliente, CPF/CNPJ, expositor ou vendedor',
                  onChanged: onBuscaChanged,
                ),
              ),
              SizedBox(
                width: campo,
                child: _DropdownId(
                  key: ValueKey('cliente_${clienteSelecionadoId ?? 'todos'}'),
                  label: 'Cliente',
                  icon: Icons.storefront_outlined,
                  allLabel: 'Todos os clientes',
                  value: clienteSelecionadoId,
                  options: clientes,
                  onChanged: onClienteChanged,
                ),
              ),
              SizedBox(
                width: campo,
                child: _DropdownId(
                  key: ValueKey(
                    'vendedor_${vendedorSelecionadoId ?? 'todos'}',
                  ),
                  label: 'Vendedor responsável',
                  icon: Icons.badge_outlined,
                  allLabel: 'Todos os vendedores',
                  value: vendedorSelecionadoId,
                  options: vendedores,
                  onChanged: onVendedorChanged,
                ),
              ),
              SizedBox(
                width: campo,
                child: DropdownButtonFormField<_SituacaoVisita>(
                  key: ValueKey('visita_${situacaoVisita.name}'),
                  initialValue: situacaoVisita,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Próxima visita',
                    prefixIcon: Icon(Icons.event_outlined),
                  ),
                  items: _SituacaoVisita.values
                      .map(
                        (item) => DropdownMenuItem(
                      value: item,
                      child: Text(_visitaLabel(item)),
                    ),
                  )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) onSituacaoChanged(value);
                  },
                ),
              ),
              SizedBox(
                width: campo,
                child: DropdownButtonFormField<_FaixaValor>(
                  key: ValueKey('valor_${faixaValor.name}'),
                  initialValue: faixaValor,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Capital a custo',
                    prefixIcon: Icon(Icons.attach_money),
                  ),
                  items: _FaixaValor.values
                      .map(
                        (item) => DropdownMenuItem(
                      value: item,
                      child: Text(_faixaValorLabel(item)),
                    ),
                  )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) onFaixaValorChanged(value);
                  },
                ),
              ),
              SizedBox(
                width: campo,
                child: DropdownButtonFormField<_OrdemAging>(
                  key: ValueKey('ordem_${ordem.name}'),
                  initialValue: ordem,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Ordenar por',
                    prefixIcon: Icon(Icons.sort),
                  ),
                  items: _OrdemAging.values
                      .map(
                        (item) => DropdownMenuItem(
                      value: item,
                      child: Text(_ordemLabel(item)),
                    ),
                  )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) onOrdemChanged(value);
                  },
                ),
              ),
              if (largura < 680 && onClear != null)
                SizedBox(
                  width: largura,
                  child: OutlinedButton.icon(
                    onPressed: onClear,
                    icon: const Icon(Icons.filter_alt_off_outlined),
                    label: const Text('Limpar filtros'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DropdownId extends StatelessWidget {
  final String label;
  final IconData icon;
  final String allLabel;
  final String? value;
  final List<_OpcaoFiltro> options;
  final ValueChanged<String?> onChanged;

  const _DropdownId({
    super.key,
    required this.label,
    required this.icon,
    required this.allLabel,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value ?? '',
      isExpanded: true,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      items: [
        DropdownMenuItem(value: '', child: Text(allLabel)),
        ...options.map(
              (item) => DropdownMenuItem(
            value: item.id,
            child: Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
      onChanged: (selected) =>
          onChanged(selected == null || selected.isEmpty ? null : selected),
    );
  }
}

class _TituloGrupo extends StatelessWidget {
  final String title;
  final String subtitle;

  const _TituloGrupo({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _IndicadoresSecundarios extends StatelessWidget {
  final _ResumoCampo resumo;

  const _IndicadoresSecundarios({required this.resumo});

  @override
  Widget build(BuildContext context) {
    return RelatorioSectionCard(
      title: 'Indicadores complementares',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final colunas = constraints.maxWidth >= 900
              ? 4
              : constraints.maxWidth >= 520
              ? 2
              : 1;
          final largura =
              (constraints.maxWidth - (colunas - 1) * 12) / colunas;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: largura,
                child: _IndicadorCompacto(
                  label: 'Resultado potencial',
                  value: formatarReais(resumo.resultadoCentavos),
                  hint: resumo.margemPotencial == null
                      ? 'Sem repasse potencial'
                      : '${_percentual(resumo.margemPotencial!)}% sobre o repasse',
                  icon: resumo.resultadoCentavos < 0
                      ? Icons.trending_down
                      : Icons.trending_up,
                  color: resumo.resultadoCentavos < 0
                      ? Colors.red
                      : Colors.green,
                ),
              ),
              SizedBox(
                width: largura,
                child: _IndicadorCompacto(
                  label: 'Clientes em campo',
                  value: '${resumo.clientes}',
                  hint: '${resumo.consignacoes} consignações ativas',
                  icon: Icons.storefront_outlined,
                  color: Colors.lightBlue,
                ),
              ),
              SizedBox(
                width: largura,
                child: _IndicadorCompacto(
                  label: 'Capital acima de 90 dias',
                  value: formatarReais(resumo.custoCriticoCentavos),
                  hint: 'Calculado pelo custo de aquisição',
                  icon: Icons.warning_amber_rounded,
                  color: resumo.custoCriticoCentavos > 0
                      ? Colors.red
                      : Colors.green,
                ),
              ),
              SizedBox(
                width: largura,
                child: _IndicadorCompacto(
                  label: 'Idade média ponderada',
                  value: resumo.idadeMediaPonderada == null
                      ? '—'
                      : '${resumo.idadeMediaPonderada!.round()} dias',
                  hint: 'Ponderada pelo capital a custo',
                  icon: Icons.schedule_outlined,
                  color: Colors.orange,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _IndicadorCompacto extends StatelessWidget {
  final String label;
  final String value;
  final String hint;
  final IconData icon;
  final Color color;

  const _IndicadorCompacto({
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .20)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FaixaResumo {
  final _FaixaAging faixa;
  final int quantidade;
  final int custoCentavos;
  final double percentual;

  const _FaixaResumo({
    required this.faixa,
    required this.quantidade,
    required this.custoCentavos,
    required this.percentual,
  });
}

class _DistribuicaoFaixas extends StatelessWidget {
  final List<_AgingLinha> linhas;
  final _FaixaAging faixaSelecionada;
  final ValueChanged<_FaixaAging> onSelected;

  const _DistribuicaoFaixas({
    required this.linhas,
    required this.faixaSelecionada,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final totalCusto = linhas.fold<int>(
      0,
          (soma, linha) => soma + linha.custoCentavos,
    );
    final faixas = _FaixaAging.values.skip(1).map((faixa) {
      final itens = linhas.where((linha) => linha.faixa == faixa).toList();
      final custo = itens.fold<int>(
        0,
            (soma, linha) => soma + linha.custoCentavos,
      );
      return _FaixaResumo(
        faixa: faixa,
        quantidade: itens.length,
        custoCentavos: custo,
        percentual: totalCusto == 0 ? 0 : custo / totalCusto * 100,
      );
    }).toList();
    final faixasValidas = faixas
        .where(
          (item) => item.faixa != _FaixaAging.semData &&
          item.faixa != _FaixaAging.dataInconsistente,
    )
        .toList();
    final totalValido = faixasValidas.fold<int>(
      0,
          (soma, item) => soma + item.custoCentavos,
    );

    return RelatorioSectionCard(
      title: 'Distribuição por tempo da posição atual',
      subtitle: 'Selecione uma faixa para filtrar o detalhamento',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (totalValido > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: SizedBox(
                height: 12,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Row(
                      children: faixasValidas.map((item) {
                        return SizedBox(
                          width: constraints.maxWidth *
                              item.custoCentavos /
                              totalValido,
                          child: ColoredBox(color: _faixaCor(item.faixa)),
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
            ),
          if (totalValido > 0) const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final colunas = constraints.maxWidth >= 1000
                  ? 3
                  : constraints.maxWidth >= 580
                  ? 2
                  : 1;
              final largura =
                  (constraints.maxWidth - (colunas - 1) * 10) / colunas;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: faixas
                    .map(
                      (item) => SizedBox(
                    width: largura,
                    child: _FaixaTile(
                      resumo: item,
                      selected: faixaSelecionada == item.faixa,
                      onTap: () => onSelected(item.faixa),
                    ),
                  ),
                )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FaixaTile extends StatelessWidget {
  final _FaixaResumo resumo;
  final bool selected;
  final VoidCallback onTap;

  const _FaixaTile({
    required this.resumo,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cor = _faixaCor(resumo.faixa);
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? cor.withValues(alpha: .16)
          : cor.withValues(alpha: .06),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? cor : cor.withValues(alpha: .22),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 38,
                decoration: BoxDecoration(
                  color: cor,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _faixaLabel(resumo.faixa),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${resumo.quantidade} consignações · ${_percentual(resumo.percentual)}%',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatarReais(resumo.custoCentavos),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrioridadesCard extends StatelessWidget {
  final List<_AgingLinha> linhas;
  final _ResumoCampo resumo;

  const _PrioridadesCard({required this.linhas, required this.resumo});

  @override
  Widget build(BuildContext context) {
    final atrasadas = linhas
        .where((linha) => linha.situacaoVisita == _SituacaoVisita.atrasada)
        .toList();
    final hoje = linhas
        .where((linha) => linha.situacaoVisita == _SituacaoVisita.hoje)
        .toList();
    final semAgendamento = linhas
        .where(
          (linha) => linha.situacaoVisita == _SituacaoVisita.semAgendamento,
    )
        .toList();
    final criticas = linhas
        .where((linha) => linha.faixa == _FaixaAging.acima90)
        .toList();
    final datasInvalidas = linhas
        .where(
          (linha) => linha.faixa == _FaixaAging.semData ||
          linha.faixa == _FaixaAging.dataInconsistente,
    )
        .toList();
    final temAlerta = atrasadas.isNotEmpty ||
        hoje.isNotEmpty ||
        semAgendamento.isNotEmpty ||
        criticas.isNotEmpty ||
        datasInvalidas.isNotEmpty;

    return RelatorioSectionCard(
      title: 'Prioridades operacionais',
      subtitle: 'Situações que precisam de acompanhamento',
      child: !temAlerta
          ? const _AlertaLinha(
        icon: Icons.verified_outlined,
        title: 'Nenhuma prioridade crítica',
        message: 'As consignações possuem agenda e datas consistentes.',
        color: Colors.green,
      )
          : Column(
        children: [
          if (atrasadas.isNotEmpty)
            _AlertaLinha(
              icon: Icons.event_busy_outlined,
              title: '${atrasadas.length} visitas atrasadas',
              message:
              '${formatarReais(_somarCusto(atrasadas))} a custo aguardando acompanhamento.',
              color: Colors.red,
            ),
          if (atrasadas.isNotEmpty &&
              (hoje.isNotEmpty ||
                  semAgendamento.isNotEmpty ||
                  criticas.isNotEmpty ||
                  datasInvalidas.isNotEmpty))
            const Divider(height: 24),
          if (hoje.isNotEmpty)
            _AlertaLinha(
              icon: Icons.today_outlined,
              title: '${hoje.length} visitas previstas para hoje',
              message:
              '${formatarReais(_somarCusto(hoje))} a custo nesses clientes.',
              color: Colors.lightBlue,
            ),
          if (hoje.isNotEmpty &&
              (semAgendamento.isNotEmpty ||
                  criticas.isNotEmpty ||
                  datasInvalidas.isNotEmpty))
            const Divider(height: 24),
          if (criticas.isNotEmpty)
            _AlertaLinha(
              icon: Icons.hourglass_disabled_outlined,
              title: '${criticas.length} posições acima de 90 dias',
              message:
              '${formatarReais(resumo.custoCriticoCentavos)} em capital a custo.',
              color: Colors.red,
            ),
          if (criticas.isNotEmpty &&
              (semAgendamento.isNotEmpty || datasInvalidas.isNotEmpty))
            const Divider(height: 24),
          if (semAgendamento.isNotEmpty)
            _AlertaLinha(
              icon: Icons.event_note_outlined,
              title: '${semAgendamento.length} clientes sem próxima visita',
              message:
              '${formatarReais(_somarCusto(semAgendamento))} a custo sem acompanhamento agendado.',
              color: Colors.orange,
            ),
          if (semAgendamento.isNotEmpty && datasInvalidas.isNotEmpty)
            const Divider(height: 24),
          if (datasInvalidas.isNotEmpty)
            _AlertaLinha(
              icon: Icons.error_outline,
              title: '${datasInvalidas.length} datas de abertura inconsistentes',
              message:
              'Existem consignações sem data ou com abertura futura.',
              color: Colors.orange,
            ),
        ],
      ),
    );
  }
}

class _AlertaLinha extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Color color;

  const _AlertaLinha({
    required this.icon,
    required this.title,
    required this.message,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(message, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _AgingResultado extends StatelessWidget {
  final List<_AgingLinha> linhas;
  final ValueChanged<String?> onAbrirCliente;

  const _AgingResultado({
    required this.linhas,
    required this.onAbrirCliente,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 800) {
          return Column(
            children: [
              for (var indice = 0; indice < linhas.length; indice++) ...[
                _AgingMobileCard(
                  linha: linhas[indice],
                  onAbrirCliente: () =>
                      onAbrirCliente(linhas[indice].clienteId),
                ),
                if (indice != linhas.length - 1) const SizedBox(height: 10),
              ],
            ],
          );
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Cliente')),
                DataColumn(label: Text('Expositor')),
                DataColumn(label: Text('Abertura')),
                DataColumn(label: Text('Aging')),
                DataColumn(label: Text('Próxima visita')),
                DataColumn(label: Text('Unid.'), numeric: true),
                DataColumn(label: Text('Custo em campo'), numeric: true),
                DataColumn(label: Text('Venda potencial'), numeric: true),
                DataColumn(label: Text('Comissão'), numeric: true),
                DataColumn(label: Text('Repasse NEXT'), numeric: true),
                DataColumn(label: Text('Resultado'), numeric: true),
              ],
              rows: linhas.map((linha) {
                return DataRow(
                  cells: [
                    DataCell(
                      SizedBox(
                        width: 190,
                        child: TextButton(
                          onPressed: linha.clienteId == null
                              ? null
                              : () => onAbrirCliente(linha.clienteId),
                          style: TextButton.styleFrom(
                            alignment: Alignment.centerLeft,
                            padding: EdgeInsets.zero,
                          ),
                          child: Text(
                            linha.cliente,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      SizedBox(
                        width: 150,
                        child: Text(
                          linha.expositor,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(Text(_dataOuTraco(linha.abertaEm))),
                    DataCell(
                      RelatorioStatusPill(
                        label: _agingStatusLabel(linha),
                        color: _faixaCor(linha.faixa),
                      ),
                    ),
                    DataCell(
                      _VisitaStatus(
                        situacao: linha.situacaoVisita,
                        data: linha.proximaVisitaEm,
                      ),
                    ),
                    DataCell(Text('${linha.unidades}')),
                    DataCell(
                      Text(
                        formatarReais(linha.custoCentavos),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    DataCell(Text(formatarReais(linha.vendaBrutaCentavos))),
                    DataCell(Text(formatarReais(linha.comissaoCentavos))),
                    DataCell(Text(formatarReais(linha.repasseCentavos))),
                    DataCell(
                      Text(
                        formatarReais(linha.resultadoPotencialCentavos),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: linha.resultadoPotencialCentavos < 0
                              ? Colors.red
                              : null,
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}

class _AgingMobileCard extends StatelessWidget {
  final _AgingLinha linha;
  final VoidCallback onAbrirCliente;

  const _AgingMobileCard({
    required this.linha,
    required this.onAbrirCliente,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: linha.faixa == _FaixaAging.acima90
              ? Colors.red.withValues(alpha: .45)
              : theme.dividerColor,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        title: Row(
          children: [
            Expanded(
              child: Text(
                linha.cliente,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              formatarReais(linha.custoCentavos),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                linha.expositor,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 8,
                runSpacing: 7,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  RelatorioStatusPill(
                    label: _agingStatusLabel(linha),
                    color: _faixaCor(linha.faixa),
                  ),
                  _VisitaStatus(
                    situacao: linha.situacaoVisita,
                    data: linha.proximaVisitaEm,
                  ),
                ],
              ),
            ],
          ),
        ),
        children: [
          const Divider(height: 18),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Posição aberta em ${_dataOuTraco(linha.abertaEm)} · ${linha.vendedor}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _ValorCompacto(label: 'Unidades', value: '${linha.unidades}'),
              _ValorCompacto(
                label: 'Custo em campo',
                value: formatarReais(linha.custoCentavos),
                color: Colors.lightBlue,
              ),
              _ValorCompacto(
                label: 'Venda potencial',
                value: formatarReais(linha.vendaBrutaCentavos),
                color: Colors.green,
              ),
              _ValorCompacto(
                label: 'Comissão potencial',
                value: formatarReais(linha.comissaoCentavos),
                color: Colors.orange,
              ),
              _ValorCompacto(
                label: 'Repasse NEXT',
                value: formatarReais(linha.repasseCentavos),
                color: Colors.lightBlue,
              ),
              _ValorCompacto(
                label: 'Resultado potencial',
                value: formatarReais(linha.resultadoPotencialCentavos),
                color: linha.resultadoPotencialCentavos < 0
                    ? Colors.red
                    : Colors.green,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: linha.clienteId == null ? null : onAbrirCliente,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Ver cliente'),
            ),
          ),
        ],
      ),
    );
  }
}

class _VisitaStatus extends StatelessWidget {
  final _SituacaoVisita situacao;
  final DateTime? data;

  const _VisitaStatus({required this.situacao, required this.data});

  @override
  Widget build(BuildContext context) {
    return RelatorioStatusPill(
      label: _visitaStatusLabel(situacao, data),
      color: _visitaCor(situacao),
      icon: _visitaIcon(situacao),
    );
  }
}

class _ValorCompacto extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _ValorCompacto({
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 135,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }
}

void _ordenarLinhas(List<_AgingLinha> linhas, _OrdemAging ordem) {
  int diasOuMenosUm(_AgingLinha linha) => linha.dias ?? -1;
  switch (ordem) {
    case _OrdemAging.prioridade:
      linhas.sort((a, b) {
        final visita = _pesoVisita(a.situacaoVisita)
            .compareTo(_pesoVisita(b.situacaoVisita));
        if (visita != 0) return visita;
        final faixa = _pesoFaixa(a.faixa).compareTo(_pesoFaixa(b.faixa));
        if (faixa != 0) return faixa;
        return diasOuMenosUm(b).compareTo(diasOuMenosUm(a));
      });
      break;
    case _OrdemAging.maisAntigos:
      linhas.sort((a, b) => diasOuMenosUm(b).compareTo(diasOuMenosUm(a)));
      break;
    case _OrdemAging.maiorCusto:
      linhas.sort((a, b) => b.custoCentavos.compareTo(a.custoCentavos));
      break;
    case _OrdemAging.maiorVenda:
      linhas.sort(
            (a, b) => b.vendaBrutaCentavos.compareTo(a.vendaBrutaCentavos),
      );
      break;
    case _OrdemAging.cliente:
      linhas.sort(
            (a, b) =>
            a.cliente.toLowerCase().compareTo(b.cliente.toLowerCase()),
      );
      break;
  }
}

int _pesoVisita(_SituacaoVisita situacao) => switch (situacao) {
  _SituacaoVisita.atrasada => 0,
  _SituacaoVisita.hoje => 1,
  _SituacaoVisita.semAgendamento => 2,
  _SituacaoVisita.estaSemana => 3,
  _SituacaoVisita.futura => 4,
  _SituacaoVisita.todas => 5,
};

int _pesoFaixa(_FaixaAging faixa) => switch (faixa) {
  _FaixaAging.acima90 => 0,
  _FaixaAging.de61a90 => 1,
  _FaixaAging.de31a60 => 2,
  _FaixaAging.ate30 => 3,
  _FaixaAging.semData => 4,
  _FaixaAging.dataInconsistente => 5,
  _FaixaAging.todas => 6,
};

String _faixaLabel(_FaixaAging faixa) => switch (faixa) {
  _FaixaAging.todas => 'Todas as faixas',
  _FaixaAging.ate30 => '0–30 dias',
  _FaixaAging.de31a60 => '31–60 dias',
  _FaixaAging.de61a90 => '61–90 dias',
  _FaixaAging.acima90 => 'Acima de 90 dias',
  _FaixaAging.semData => 'Sem data de abertura',
  _FaixaAging.dataInconsistente => 'Data inconsistente',
};

Color _faixaCor(_FaixaAging faixa) => switch (faixa) {
  _FaixaAging.ate30 => Colors.green,
  _FaixaAging.de31a60 => Colors.lightGreen,
  _FaixaAging.de61a90 => Colors.orange,
  _FaixaAging.acima90 => Colors.red,
  _FaixaAging.semData => Colors.blueGrey,
  _FaixaAging.dataInconsistente => Colors.purple,
  _FaixaAging.todas => Colors.blueGrey,
};

String _visitaLabel(_SituacaoVisita situacao) => switch (situacao) {
  _SituacaoVisita.todas => 'Todas as situações',
  _SituacaoVisita.atrasada => 'Visitas atrasadas',
  _SituacaoVisita.hoje => 'Previstas para hoje',
  _SituacaoVisita.estaSemana => 'Previstas esta semana',
  _SituacaoVisita.futura => 'Próximas visitas',
  _SituacaoVisita.semAgendamento => 'Sem agendamento',
};

String _faixaValorLabel(_FaixaValor faixa) => switch (faixa) {
  _FaixaValor.todos => 'Qualquer valor',
  _FaixaValor.acimaMil => 'A partir de R\$ 1.000',
  _FaixaValor.acimaTresMil => 'A partir de R\$ 3.000',
  _FaixaValor.acimaCincoMil => 'A partir de R\$ 5.000',
};

String _ordemLabel(_OrdemAging ordem) => switch (ordem) {
  _OrdemAging.prioridade => 'Maior prioridade',
  _OrdemAging.maisAntigos => 'Mais antigos',
  _OrdemAging.maiorCusto => 'Maior custo em campo',
  _OrdemAging.maiorVenda => 'Maior venda potencial',
  _OrdemAging.cliente => 'Cliente A–Z',
};

Color _visitaCor(_SituacaoVisita situacao) => switch (situacao) {
  _SituacaoVisita.atrasada => Colors.red,
  _SituacaoVisita.hoje => Colors.green,
  _SituacaoVisita.estaSemana => Colors.lightBlue,
  _SituacaoVisita.futura => Colors.blueGrey,
  _SituacaoVisita.semAgendamento => Colors.orange,
  _SituacaoVisita.todas => Colors.blueGrey,
};

IconData _visitaIcon(_SituacaoVisita situacao) => switch (situacao) {
  _SituacaoVisita.atrasada => Icons.event_busy_outlined,
  _SituacaoVisita.hoje => Icons.today_outlined,
  _SituacaoVisita.estaSemana => Icons.date_range_outlined,
  _SituacaoVisita.futura => Icons.event_outlined,
  _SituacaoVisita.semAgendamento => Icons.event_note_outlined,
  _SituacaoVisita.todas => Icons.event_outlined,
};

String _visitaStatusLabel(_SituacaoVisita situacao, DateTime? data) {
  if (situacao == _SituacaoVisita.semAgendamento || data == null) {
    return 'Sem agendamento';
  }
  if (situacao == _SituacaoVisita.atrasada) {
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final prevista = DateTime(data.year, data.month, data.day);
    final dias = hoje.difference(prevista).inDays;
    return 'Atrasada há $dias ${dias == 1 ? 'dia' : 'dias'}';
  }
  if (situacao == _SituacaoVisita.hoje) return 'Hoje';
  return DateFormat('dd/MM/yyyy').format(data);
}

String _agingStatusLabel(_AgingLinha linha) {
  if (linha.faixa == _FaixaAging.semData) return 'Sem data';
  if (linha.faixa == _FaixaAging.dataInconsistente) return 'Data futura';
  return '${linha.dias} dias';
}

String _dataOuTraco(DateTime? data) =>
    data == null ? '—' : DateFormat('dd/MM/yyyy').format(data);

String _percentual(double valor) =>
    valor.toStringAsFixed(1).replaceAll('.', ',');

int _somarCusto(List<_AgingLinha> linhas) => linhas.fold<int>(
  0,
      (soma, linha) => soma + linha.custoCentavos,
);
