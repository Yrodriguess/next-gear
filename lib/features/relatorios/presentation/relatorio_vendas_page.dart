import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/firestore_collections.dart';
import '../../clientes/presentation/cliente_providers.dart';
import '../../estoque/domain/stock_movement.dart';
import '../../estoque/presentation/estoque_providers.dart';
import '../../produtos/presentation/produto_providers.dart';
import 'relatorios_ui.dart';

enum _PeriodoVendas {
  seteDias,
  trintaDias,
  esteMes,
  noventaDias,
  personalizado,
  tudo,
}

enum _OrdemVendas {
  recentes,
  antigas,
  maiorValor,
  maisUnidades,
  maiorComissao,
  maiorResultado,
}

enum _FiltroHistorico { todos, completos, incompletos, resultadoNegativo }

/// Relatório operacional e financeiro das vendas apuradas.
/// Os valores históricos vêm do movimento e nunca do cadastro atual do SKU.
class RelatorioVendasPage extends ConsumerStatefulWidget {
  const RelatorioVendasPage({super.key});

  @override
  ConsumerState<RelatorioVendasPage> createState() =>
      _RelatorioVendasPageState();
}

class _RelatorioVendasPageState extends ConsumerState<RelatorioVendasPage> {
  final _buscaController = TextEditingController();

  _PeriodoVendas _periodo = _PeriodoVendas.trintaDias;
  _OrdemVendas _ordem = _OrdemVendas.recentes;
  _FiltroHistorico _filtroHistorico = _FiltroHistorico.todos;
  DateTimeRange? _periodoPersonalizado;
  String? _clienteSelecionadoId;
  String? _skuSelecionadoId;
  int _limiteDetalhamento = 50;
  int _periodoFieldVersion = 0;

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  DateTime? get _inicioPeriodo {
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    return switch (_periodo) {
      _PeriodoVendas.seteDias => hoje.subtract(const Duration(days: 6)),
      _PeriodoVendas.trintaDias => hoje.subtract(const Duration(days: 29)),
      _PeriodoVendas.esteMes => DateTime(agora.year, agora.month, 1),
      _PeriodoVendas.noventaDias => hoje.subtract(const Duration(days: 89)),
      _PeriodoVendas.personalizado => _periodoPersonalizado?.start,
      _PeriodoVendas.tudo => null,
    };
  }

  DateTime? get _fimPeriodoExclusivo {
    final agora = DateTime.now();
    final amanha = DateTime(agora.year, agora.month, agora.day)
        .add(const Duration(days: 1));
    return switch (_periodo) {
      _PeriodoVendas.personalizado =>
          _periodoPersonalizado?.end.add(const Duration(days: 1)),
      _PeriodoVendas.tudo => null,
      _ => amanha,
    };
  }

  String get _periodoLabel {
    if (_periodo == _PeriodoVendas.personalizado &&
        _periodoPersonalizado != null) {
      return '${DateFormat('dd/MM/yyyy').format(_periodoPersonalizado!.start)} a '
          '${DateFormat('dd/MM/yyyy').format(_periodoPersonalizado!.end)}';
    }
    return _labelPeriodo(_periodo);
  }

  bool _noPeriodo(DateTime? data) {
    final inicio = _inicioPeriodo;
    final fim = _fimPeriodoExclusivo;
    if (inicio == null && fim == null) return true;
    if (data == null) return false;
    if (inicio != null && data.isBefore(inicio)) return false;
    if (fim != null && !data.isBefore(fim)) return false;
    return true;
  }

  Future<void> _alterarPeriodo(_PeriodoVendas periodo) async {
    if (periodo != _PeriodoVendas.personalizado) {
      setState(() {
        _periodo = periodo;
        _limiteDetalhamento = 50;
        _periodoFieldVersion++;
      });
      return;
    }

    final agora = DateTime.now();
    final inicial = _periodoPersonalizado ??
        DateTimeRange(
          start: DateTime(agora.year, agora.month, 1),
          end: DateTime(agora.year, agora.month, agora.day),
        );
    final selecionado = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(agora.year + 1, 12, 31),
      initialDateRange: inicial,
      helpText: 'Selecionar período das vendas',
      cancelText: 'Cancelar',
      confirmText: 'Aplicar',
      saveText: 'Aplicar',
      fieldStartLabelText: 'Data inicial',
      fieldEndLabelText: 'Data final',
    );
    if (!mounted) return;
    if (selecionado == null) {
      setState(() => _periodoFieldVersion++);
      return;
    }
    setState(() {
      _periodoPersonalizado = selecionado;
      _periodo = _PeriodoVendas.personalizado;
      _limiteDetalhamento = 50;
      _periodoFieldVersion++;
    });
  }

  void _recarregar() {
    ref.invalidate(vendasProvider(AppConfig.currentOrgId));
    ref.invalidate(clientesListProvider);
    ref.invalidate(produtosListProvider);
    ref.invalidate(skusListProvider);
  }

  void _limparFiltros() {
    setState(() {
      _buscaController.clear();
      _clienteSelecionadoId = null;
      _skuSelecionadoId = null;
      _filtroHistorico = _FiltroHistorico.todos;
      _ordem = _OrdemVendas.recentes;
      _limiteDetalhamento = 50;
    });
  }

  void _filtrarCliente(String id) {
    setState(() {
      _clienteSelecionadoId = id;
      _limiteDetalhamento = 50;
    });
  }

  void _filtrarSku(String id) {
    setState(() {
      _skuSelecionadoId = id;
      _limiteDetalhamento = 50;
    });
  }

  @override
  Widget build(BuildContext context) {
    final vendasAsync = ref.watch(vendasProvider(AppConfig.currentOrgId));
    final clientesAsync = ref.watch(clientesListProvider);
    final produtosAsync = ref.watch(produtosListProvider);
    final skusAsync = ref.watch(skusListProvider);

    if (vendasAsync.hasError ||
        clientesAsync.hasError ||
        produtosAsync.hasError ||
        skusAsync.hasError) {
      return RelatorioErrorState(onRetry: _recarregar);
    }
    if ((vendasAsync.isLoading && !vendasAsync.hasValue) ||
        (clientesAsync.isLoading && !clientesAsync.hasValue) ||
        (produtosAsync.isLoading && !produtosAsync.hasValue) ||
        (skusAsync.isLoading && !skusAsync.hasValue)) {
      return const RelatorioLoading();
    }

    final vendas = vendasAsync.value;
    final clientes = clientesAsync.value;
    final produtos = produtosAsync.value;
    final skus = skusAsync.value;
    if (vendas == null || clientes == null || produtos == null || skus == null) {
      return const RelatorioLoading();
    }

    final clientePorId = {
      for (final cliente in clientes)
        if (cliente.id != null) cliente.id!: cliente,
    };
    final produtoPorId = {
      for (final produto in produtos)
        if (produto.id != null) produto.id!: produto,
    };
    final skuPorId = {
      for (final sku in skus)
        if (sku.id != null) sku.id!: sku,
    };

    final linhasDoPeriodo = vendas.where((venda) => _noPeriodo(venda.timestamp)).map(
          (venda) {
        final clienteId = LocalEstoque.extrairClienteId(venda.origem);
        final cliente = clienteId == null ? null : clientePorId[clienteId];
        final sku = skuPorId[venda.produtoId];
        final produto = produtoPorId[sku?.produtoId ?? venda.produtoId];
        final nomeCliente = cliente?.nomeFantasia?.trim().isNotEmpty == true
            ? cliente!.nomeFantasia!.trim()
            : cliente?.nome ?? 'Cliente não localizado';
        final nomeProduto = produto == null
            ? sku?.codigoInterno ?? venda.produtoId
            : sku?.variacao?.trim().isNotEmpty == true
            ? '${produto.descricao} — ${sku!.variacao!.trim()}'
            : produto.descricao;

        return _VendaLinha(
          clienteId: clienteId,
          cliente: nomeCliente,
          cpfCnpj: cliente?.cpfCnpj ?? '',
          skuId: venda.produtoId,
          skuCodigo: sku?.codigoInterno ?? venda.produtoId,
          codigoBarras: sku?.codigoBarras ?? '',
          produto: nomeProduto,
          data: venda.timestamp,
          unidades: venda.quantidade,
          valorUnitarioCentavos: venda.valorVendaCentavosNoMomento,
          custoUnitarioCentavos: venda.custoUnitarioCentavosNoMomento,
          comissaoUnitarioCentavos: venda.comissaoCentavosNoMomento,
        );
      },
    ).toList();

    final query = _buscaController.text.trim().toLowerCase();
    final queryNumerica = query.replaceAll(RegExp(r'\D'), '');
    final linhas = linhasDoPeriodo.where((linha) {
      if (_clienteSelecionadoId != null &&
          linha.clienteId != _clienteSelecionadoId) {
        return false;
      }
      if (_skuSelecionadoId != null && linha.skuId != _skuSelecionadoId) {
        return false;
      }
      final atendeHistorico = switch (_filtroHistorico) {
        _FiltroHistorico.todos => true,
        _FiltroHistorico.completos => linha.historicoCompleto,
        _FiltroHistorico.incompletos => !linha.historicoCompleto,
        _FiltroHistorico.resultadoNegativo =>
        linha.resultadoCentavos != null && linha.resultadoCentavos! < 0,
      };
      if (!atendeHistorico) return false;
      if (query.isEmpty) return true;

      final documento = linha.cpfCnpj.replaceAll(RegExp(r'\D'), '');
      final barras = linha.codigoBarras.replaceAll(RegExp(r'\D'), '');
      return linha.cliente.toLowerCase().contains(query) ||
          linha.produto.toLowerCase().contains(query) ||
          linha.skuCodigo.toLowerCase().contains(query) ||
          linha.codigoBarras.toLowerCase().contains(query) ||
          (queryNumerica.isNotEmpty &&
              (documento.contains(queryNumerica) ||
                  barras.contains(queryNumerica)));
    }).toList();

    _ordenarLinhas(linhas, _ordem);

    final resumo = _ResumoVendas.calcular(linhas);
    final evolucao =
    _montarEvolucao(linhas, _periodo, _periodoPersonalizado);
    final rankings = _montarRankings(linhas);
    final linhasExibidas = linhas.take(_limiteDetalhamento).toList();
    final existemFiltrosAdicionais = query.isNotEmpty ||
        _clienteSelecionadoId != null ||
        _skuSelecionadoId != null ||
        _filtroHistorico != _FiltroHistorico.todos ||
        _ordem != _OrdemVendas.recentes;

    final clientesOrdenados = clientes
        .where((cliente) => cliente.id != null)
        .toList()
      ..sort((a, b) {
        final nomeA = a.nomeFantasia?.trim().isNotEmpty == true
            ? a.nomeFantasia!.trim()
            : a.nome;
        final nomeB = b.nomeFantasia?.trim().isNotEmpty == true
            ? b.nomeFantasia!.trim()
            : b.nome;
        return nomeA.toLowerCase().compareTo(nomeB.toLowerCase());
      });
    final skusOrdenados = skus.where((sku) => sku.id != null).toList()
      ..sort(
            (a, b) =>
            a.codigoInterno.toLowerCase().compareTo(b.codigoInterno.toLowerCase()),
      );

    return SingleChildScrollView(
      child: RelatorioPageBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RelatorioIntro(
              title: 'Vendas',
              subtitle:
              'Analise venda bruta, comissão retida, repasse e resultado por lojista e produto.',
              icon: Icons.trending_up,
              action: OutlinedButton.icon(
                onPressed: _recarregar,
                icon: const Icon(Icons.refresh),
                label: const Text('Atualizar'),
              ),
            ),
            const SizedBox(height: 20),
            _FiltrosVendas(
              buscaController: _buscaController,
              periodo: _periodo,
              periodoLabel: _periodoLabel,
              periodoFieldVersion: _periodoFieldVersion,
              ordem: _ordem,
              filtroHistorico: _filtroHistorico,
              clienteSelecionadoId: _clienteSelecionadoId,
              skuSelecionadoId: _skuSelecionadoId,
              clientes: clientesOrdenados
                  .map(
                    (cliente) => _OpcaoFiltro(
                  id: cliente.id!,
                  label: cliente.nomeFantasia?.trim().isNotEmpty == true
                      ? cliente.nomeFantasia!.trim()
                      : cliente.nome,
                ),
              )
                  .toList(),
              skus: skusOrdenados.map((sku) {
                final produto = produtoPorId[sku.produtoId];
                final descricao = produto?.descricao ?? 'Produto não localizado';
                final variacao = sku.variacao?.trim();
                return _OpcaoFiltro(
                  id: sku.id!,
                  label: variacao?.isNotEmpty == true
                      ? '${sku.codigoInterno} · $descricao — $variacao'
                      : '${sku.codigoInterno} · $descricao',
                );
              }).toList(),
              onBuscaChanged: (_) => setState(() => _limiteDetalhamento = 50),
              onPeriodoChanged: _alterarPeriodo,
              onClienteChanged: (value) => setState(() {
                _clienteSelecionadoId = value;
                _limiteDetalhamento = 50;
              }),
              onSkuChanged: (value) => setState(() {
                _skuSelecionadoId = value;
                _limiteDetalhamento = 50;
              }),
              onHistoricoChanged: (value) => setState(() {
                _filtroHistorico = value;
                _limiteDetalhamento = 50;
              }),
              onOrdemChanged: (value) => setState(() {
                _ordem = value;
                _limiteDetalhamento = 50;
              }),
              onClear: existemFiltrosAdicionais ? _limparFiltros : null,
              resultados: linhas.length,
            ),
            const SizedBox(height: 20),
            _TituloGrupo(
              title: 'Resultado financeiro',
              subtitle: '$_periodoLabel · considerando os filtros aplicados',
            ),
            const SizedBox(height: 12),
            RelatorioMetricsGrid(
              children: [
                RelatorioMetricCard(
                  label: 'Venda bruta',
                  value: formatarReais(resumo.faturamento),
                  hint: '${resumo.movimentos} movimentos filtrados',
                  icon: Icons.payments_outlined,
                  color: Colors.green,
                ),
                RelatorioMetricCard(
                  label: 'Comissão retida',
                  value: formatarReais(resumo.comissao),
                  hint: resumo.percentualComissao == null
                      ? 'Sem histórico financeiro completo'
                      : '${_percentual(resumo.percentualComissao!)}% da venda completa',
                  icon: Icons.handshake_outlined,
                  color: Colors.orange,
                ),
                RelatorioMetricCard(
                  label: 'Repasse à NEXT GEAR',
                  value: formatarReais(resumo.repasse),
                  hint: 'Venda menos comissão retida',
                  icon: Icons.account_balance_outlined,
                  color: Colors.lightBlue,
                ),
                RelatorioMetricCard(
                  label: 'Resultado bruto NEXT GEAR',
                  value: formatarReais(resumo.resultado),
                  hint: 'Repasse menos custo dos produtos',
                  icon: resumo.resultado < 0
                      ? Icons.trending_down
                      : Icons.trending_up,
                  color: resumo.resultado < 0 ? Colors.red : Colors.green,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _IndicadoresSecundarios(resumo: resumo),
            if (resumo.movimentosSemHistorico > 0) ...[
              const SizedBox(height: 16),
              _HistoricoAviso(resumo: resumo),
            ],
            const SizedBox(height: 20),
            RelatorioSectionCard(
              title: 'Evolução financeira',
              subtitle:
              'Venda bruta, comissão, repasse e resultado ao longo do período',
              child: _EvolucaoFinanceiraChart(
                dados: evolucao,
                periodo: _periodo,
              ),
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final colunas = constraints.maxWidth >= 1050
                    ? 3
                    : constraints.maxWidth >= 680
                    ? 2
                    : 1;
                final largura =
                    (constraints.maxWidth - (colunas - 1) * 16) / colunas;
                final cards = [
                  _RankingCard(
                    title: 'Top lojistas',
                    subtitle: 'Maiores vendas brutas',
                    color: Colors.green,
                    items: rankings.clientes,
                    onTap: _filtrarCliente,
                  ),
                  _RankingCard(
                    title: 'Top produtos',
                    subtitle: 'Maiores vendas por SKU',
                    color: Colors.lightBlue,
                    items: rankings.produtos,
                    onTap: _filtrarSku,
                  ),
                  _RankingCard(
                    title: 'Comissão por lojista',
                    subtitle: 'Maiores comissões retidas',
                    color: Colors.orange,
                    items: rankings.comissoes,
                    onTap: _filtrarCliente,
                  ),
                ];
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: cards
                      .map((card) => SizedBox(width: largura, child: card))
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 20),
            RelatorioSectionCard(
              title: 'Detalhamento das vendas',
              subtitle: linhas.isEmpty
                  ? 'Nenhum resultado encontrado'
                  : 'Mostrando ${linhasExibidas.length} de ${linhas.length} movimentos',
              child: linhas.isEmpty
                  ? RelatorioEmptyState(
                icon: Icons.search_off,
                title: linhasDoPeriodo.isEmpty
                    ? 'Nenhuma venda no período'
                    : 'Nenhuma venda encontrada',
                message: linhasDoPeriodo.isEmpty
                    ? 'As vendas aparecerão após a apuração das visitas.'
                    : 'Ajuste ou limpe os filtros para encontrar outros resultados.',
                action: linhasDoPeriodo.isEmpty
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
                  _VendasResultado(linhas: linhasExibidas),
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
              'Comissão, repasse, custo e resultado usam apenas movimentos com preço de venda, comissão e custo registrados. O resultado bruto não desconta despesas operacionais nem tributos.',
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

class _OpcaoFiltro {
  final String id;
  final String label;

  const _OpcaoFiltro({required this.id, required this.label});
}

class _FiltrosVendas extends StatelessWidget {
  final TextEditingController buscaController;
  final _PeriodoVendas periodo;
  final String periodoLabel;
  final int periodoFieldVersion;
  final _OrdemVendas ordem;
  final _FiltroHistorico filtroHistorico;
  final String? clienteSelecionadoId;
  final String? skuSelecionadoId;
  final List<_OpcaoFiltro> clientes;
  final List<_OpcaoFiltro> skus;
  final ValueChanged<String> onBuscaChanged;
  final ValueChanged<_PeriodoVendas> onPeriodoChanged;
  final ValueChanged<String?> onClienteChanged;
  final ValueChanged<String?> onSkuChanged;
  final ValueChanged<_FiltroHistorico> onHistoricoChanged;
  final ValueChanged<_OrdemVendas> onOrdemChanged;
  final VoidCallback? onClear;
  final int resultados;

  const _FiltrosVendas({
    required this.buscaController,
    required this.periodo,
    required this.periodoLabel,
    required this.periodoFieldVersion,
    required this.ordem,
    required this.filtroHistorico,
    required this.clienteSelecionadoId,
    required this.skuSelecionadoId,
    required this.clientes,
    required this.skus,
    required this.onBuscaChanged,
    required this.onPeriodoChanged,
    required this.onClienteChanged,
    required this.onSkuChanged,
    required this.onHistoricoChanged,
    required this.onOrdemChanged,
    required this.onClear,
    required this.resultados,
  });

  @override
  Widget build(BuildContext context) {
    return RelatorioSectionCard(
      title: 'Filtros',
      subtitle: '$resultados movimentos encontrados · $periodoLabel',
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
                  hint: 'Cliente, CPF/CNPJ, produto, SKU ou código de barras',
                  onChanged: onBuscaChanged,
                ),
              ),
              SizedBox(
                width: campo,
                child: DropdownButtonFormField<_PeriodoVendas>(
                  key: ValueKey(
                    'periodo_${periodo.name}_${periodoFieldVersion}_$periodoLabel',
                  ),
                  initialValue: periodo,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Período',
                    prefixIcon: Icon(Icons.date_range_outlined),
                  ),
                  items: _PeriodoVendas.values
                      .map(
                        (item) => DropdownMenuItem(
                      value: item,
                      child: Text(
                        item == _PeriodoVendas.personalizado &&
                            periodo == _PeriodoVendas.personalizado
                            ? periodoLabel
                            : _labelPeriodo(item),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) onPeriodoChanged(value);
                  },
                ),
              ),
              SizedBox(
                width: campo,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('cliente_${clienteSelecionadoId ?? 'todos'}'),
                  initialValue: clienteSelecionadoId ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Lojista',
                    prefixIcon: Icon(Icons.storefront_outlined),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Todos os lojistas'),
                    ),
                    ...clientes.map(
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
                  onChanged: (value) =>
                      onClienteChanged(value == null || value.isEmpty ? null : value),
                ),
              ),
              SizedBox(
                width: campo,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('sku_${skuSelecionadoId ?? 'todos'}'),
                  initialValue: skuSelecionadoId ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Produto/SKU',
                    prefixIcon: Icon(Icons.inventory_2_outlined),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Todos os produtos'),
                    ),
                    ...skus.map(
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
                  onChanged: (value) =>
                      onSkuChanged(value == null || value.isEmpty ? null : value),
                ),
              ),
              SizedBox(
                width: campo,
                child: DropdownButtonFormField<_FiltroHistorico>(
                  key: ValueKey('historico_${filtroHistorico.name}'),
                  initialValue: filtroHistorico,
                  decoration: const InputDecoration(
                    labelText: 'Situação dos dados',
                    prefixIcon: Icon(Icons.fact_check_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: _FiltroHistorico.todos,
                      child: Text('Todos os movimentos'),
                    ),
                    DropdownMenuItem(
                      value: _FiltroHistorico.completos,
                      child: Text('Histórico completo'),
                    ),
                    DropdownMenuItem(
                      value: _FiltroHistorico.incompletos,
                      child: Text('Histórico incompleto'),
                    ),
                    DropdownMenuItem(
                      value: _FiltroHistorico.resultadoNegativo,
                      child: Text('Resultado negativo'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) onHistoricoChanged(value);
                  },
                ),
              ),
              SizedBox(
                width: campo,
                child: DropdownButtonFormField<_OrdemVendas>(
                  key: ValueKey('ordem_${ordem.name}'),
                  initialValue: ordem,
                  decoration: const InputDecoration(
                    labelText: 'Ordenar por',
                    prefixIcon: Icon(Icons.sort),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: _OrdemVendas.recentes,
                      child: Text('Mais recentes'),
                    ),
                    DropdownMenuItem(
                      value: _OrdemVendas.antigas,
                      child: Text('Mais antigas'),
                    ),
                    DropdownMenuItem(
                      value: _OrdemVendas.maiorValor,
                      child: Text('Maior venda'),
                    ),
                    DropdownMenuItem(
                      value: _OrdemVendas.maisUnidades,
                      child: Text('Mais unidades'),
                    ),
                    DropdownMenuItem(
                      value: _OrdemVendas.maiorComissao,
                      child: Text('Maior comissão'),
                    ),
                    DropdownMenuItem(
                      value: _OrdemVendas.maiorResultado,
                      child: Text('Maior resultado'),
                    ),
                  ],
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

class _VendaLinha {
  final String? clienteId;
  final String cliente;
  final String cpfCnpj;
  final String skuId;
  final String skuCodigo;
  final String codigoBarras;
  final String produto;
  final DateTime? data;
  final int unidades;
  final int? valorUnitarioCentavos;
  final int? custoUnitarioCentavos;
  final int? comissaoUnitarioCentavos;

  const _VendaLinha({
    required this.clienteId,
    required this.cliente,
    required this.cpfCnpj,
    required this.skuId,
    required this.skuCodigo,
    required this.codigoBarras,
    required this.produto,
    required this.data,
    required this.unidades,
    required this.valorUnitarioCentavos,
    required this.custoUnitarioCentavos,
    required this.comissaoUnitarioCentavos,
  });

  bool get historicoCompleto =>
      valorUnitarioCentavos != null &&
          custoUnitarioCentavos != null &&
          comissaoUnitarioCentavos != null;

  int? get vendaCentavos => valorUnitarioCentavos == null
      ? null
      : unidades * valorUnitarioCentavos!;

  int? get custoCentavos => custoUnitarioCentavos == null
      ? null
      : unidades * custoUnitarioCentavos!;

  int? get comissaoCentavos => comissaoUnitarioCentavos == null
      ? null
      : unidades * comissaoUnitarioCentavos!;

  int? get repasseCentavos {
    final venda = vendaCentavos;
    final comissao = comissaoCentavos;
    if (venda == null || comissao == null) return null;
    return venda - comissao;
  }

  int? get resultadoCentavos {
    final repasse = repasseCentavos;
    final custo = custoCentavos;
    if (repasse == null || custo == null) return null;
    return repasse - custo;
  }

  double? get margemPercentual {
    final repasse = repasseCentavos;
    final resultado = resultadoCentavos;
    if (repasse == null || repasse == 0 || resultado == null) return null;
    return resultado / repasse * 100;
  }
}

class _ResumoVendas {
  final int movimentos;
  final int movimentosComHistorico;
  final int faturamento;
  final int faturamentoCompleto;
  final int comissao;
  final int repasse;
  final int custo;
  final int resultado;
  final int unidades;
  final int clientes;

  const _ResumoVendas({
    required this.movimentos,
    required this.movimentosComHistorico,
    required this.faturamento,
    required this.faturamentoCompleto,
    required this.comissao,
    required this.repasse,
    required this.custo,
    required this.resultado,
    required this.unidades,
    required this.clientes,
  });

  int get movimentosSemHistorico => movimentos - movimentosComHistorico;

  double? get percentualComissao => faturamentoCompleto == 0
      ? null
      : comissao / faturamentoCompleto * 100;

  double? get margem => repasse == 0 ? null : resultado / repasse * 100;

  double get cobertura =>
      movimentos == 0 ? 1 : movimentosComHistorico / movimentos;

  factory _ResumoVendas.calcular(List<_VendaLinha> linhas) {
    var faturamento = 0;
    var faturamentoCompleto = 0;
    var comissao = 0;
    var repasse = 0;
    var custo = 0;
    var resultado = 0;
    var unidades = 0;
    var completos = 0;
    final clientes = <String>{};

    for (final linha in linhas) {
      faturamento += linha.vendaCentavos ?? 0;
      unidades += linha.unidades;
      if (linha.clienteId != null) clientes.add(linha.clienteId!);
      if (!linha.historicoCompleto) continue;

      completos++;
      faturamentoCompleto += linha.vendaCentavos!;
      comissao += linha.comissaoCentavos!;
      repasse += linha.repasseCentavos!;
      custo += linha.custoCentavos!;
      resultado += linha.resultadoCentavos!;
    }

    return _ResumoVendas(
      movimentos: linhas.length,
      movimentosComHistorico: completos,
      faturamento: faturamento,
      faturamentoCompleto: faturamentoCompleto,
      comissao: comissao,
      repasse: repasse,
      custo: custo,
      resultado: resultado,
      unidades: unidades,
      clientes: clientes.length,
    );
  }
}

class _IndicadoresSecundarios extends StatelessWidget {
  final _ResumoVendas resumo;

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
                  label: 'Unidades vendidas',
                  value: '${resumo.unidades}',
                  hint: '${resumo.movimentos} movimentos',
                  icon: Icons.shopping_bag_outlined,
                  color: Colors.lightBlue,
                ),
              ),
              SizedBox(
                width: largura,
                child: _IndicadorCompacto(
                  label: 'Lojistas atendidos',
                  value: '${resumo.clientes}',
                  hint: 'Clientes únicos no filtro',
                  icon: Icons.storefront_outlined,
                  color: Colors.orange,
                ),
              ),
              SizedBox(
                width: largura,
                child: _IndicadorCompacto(
                  label: 'Margem sobre repasse',
                  value: resumo.margem == null
                      ? '—'
                      : '${_percentual(resumo.margem!)}%',
                  hint: 'Antes de despesas e tributos',
                  icon: Icons.percent,
                  color: resumo.margem != null && resumo.margem! < 0
                      ? Colors.red
                      : Colors.green,
                ),
              ),
              SizedBox(
                width: largura,
                child: _IndicadorCompacto(
                  label: 'Cobertura financeira',
                  value: resumo.movimentos == 0
                      ? '—'
                      : '${_percentual(resumo.cobertura * 100)}%',
                  hint:
                  '${resumo.movimentosComHistorico}/${resumo.movimentos} movimentos completos',
                  icon: Icons.fact_check_outlined,
                  color: resumo.movimentosSemHistorico == 0
                      ? Colors.green
                      : Colors.orange,
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

class _HistoricoAviso extends StatelessWidget {
  final _ResumoVendas resumo;

  const _HistoricoAviso({required this.resumo});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: .38)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Colors.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${resumo.movimentosSemHistorico} movimentos não possuem preço, comissão ou custo completos. Eles entram na venda bruta quando houver preço, mas não entram nos totais de comissão, repasse, custo e resultado.',
            ),
          ),
        ],
      ),
    );
  }
}

class _PontoEvolucao {
  final DateTime data;
  final int faturamento;
  final int comissao;
  final int repasse;
  final int resultado;

  const _PontoEvolucao({
    required this.data,
    required this.faturamento,
    required this.comissao,
    required this.repasse,
    required this.resultado,
  });
}

class _AcumuladorEvolucao {
  final DateTime data;
  int faturamento = 0;
  int comissao = 0;
  int repasse = 0;
  int resultado = 0;

  _AcumuladorEvolucao(this.data);
}

List<_PontoEvolucao> _montarEvolucao(
    List<_VendaLinha> linhas,
    _PeriodoVendas periodo,
    DateTimeRange? personalizado,
    ) {
  DateTime chave(DateTime data) {
    final diasPersonalizados = personalizado == null
        ? 0
        : personalizado.end.difference(personalizado.start).inDays + 1;
    if (periodo == _PeriodoVendas.tudo ||
        (periodo == _PeriodoVendas.personalizado &&
            diasPersonalizados > 180)) {
      return DateTime(data.year, data.month);
    }
    if (periodo == _PeriodoVendas.noventaDias ||
        (periodo == _PeriodoVendas.personalizado &&
            diasPersonalizados > 45)) {
      return _inicioSemana(data);
    }
    return DateTime(data.year, data.month, data.day);
  }

  final agrupados = <DateTime, _AcumuladorEvolucao>{};
  for (final linha in linhas) {
    final data = linha.data;
    if (data == null) continue;
    final grupo = agrupados.putIfAbsent(
      chave(data),
          () => _AcumuladorEvolucao(chave(data)),
    );
    grupo.faturamento += linha.vendaCentavos ?? 0;
    if (linha.historicoCompleto) {
      grupo.comissao += linha.comissaoCentavos!;
      grupo.repasse += linha.repasseCentavos!;
      grupo.resultado += linha.resultadoCentavos!;
    }
  }

  var pontos = agrupados.values
      .map(
        (grupo) => _PontoEvolucao(
      data: grupo.data,
      faturamento: grupo.faturamento,
      comissao: grupo.comissao,
      repasse: grupo.repasse,
      resultado: grupo.resultado,
    ),
  )
      .toList()
    ..sort((a, b) => a.data.compareTo(b.data));

  if (pontos.length > 36) pontos = pontos.sublist(pontos.length - 36);
  return pontos;
}

DateTime _inicioSemana(DateTime data) {
  final dia = DateTime(data.year, data.month, data.day);
  return dia.subtract(Duration(days: dia.weekday - DateTime.monday));
}

class _EvolucaoFinanceiraChart extends StatelessWidget {
  final List<_PontoEvolucao> dados;
  final _PeriodoVendas periodo;

  const _EvolucaoFinanceiraChart({
    required this.dados,
    required this.periodo,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (dados.isEmpty) {
      return const SizedBox(
        height: 220,
        child: Center(child: Text('Sem vendas para montar o gráfico.')),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Wrap(
          spacing: 14,
          runSpacing: 8,
          children: [
            _Legenda(label: 'Venda bruta', color: Colors.green),
            _Legenda(label: 'Comissão', color: Colors.orange),
            _Legenda(label: 'Repasse', color: Colors.lightBlue),
            _Legenda(label: 'Resultado', color: Colors.purpleAccent),
          ],
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 180,
          child: CustomPaint(
            painter: _EvolucaoPainter(
              dados: dados,
              gridColor: theme.colorScheme.outlineVariant,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _dataCurta(dados.first.data, periodo),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (dados.length > 2)
              Text(
                '${dados.length} períodos',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            Text(
              _dataCurta(dados.last.data, periodo),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Legenda extends StatelessWidget {
  final String label;
  final Color color;

  const _Legenda({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _EvolucaoPainter extends CustomPainter {
  final List<_PontoEvolucao> dados;
  final Color gridColor;

  const _EvolucaoPainter({required this.dados, required this.gridColor});

  @override
  void paint(Canvas canvas, Size size) {
    const margem = 5.0;
    final area = Rect.fromLTWH(
      margem,
      margem,
      math.max(1.0, size.width - margem * 2),
      math.max(1.0, size.height - margem * 2),
    );
    final valores = <int>[
      for (final item in dados) ...[
        item.faturamento,
        item.comissao,
        item.repasse,
        item.resultado,
      ],
    ];
    final minimo = math.min(0, valores.reduce(math.min));
    final maximo = math.max(1, valores.reduce(math.max));
    final amplitude = math.max(1, maximo - minimo);

    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: .55)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = area.top + area.height * i / 4;
      canvas.drawLine(Offset(area.left, y), Offset(area.right, y), gridPaint);
    }

    if (minimo < 0) {
      final zeroY = area.bottom - ((0 - minimo) / amplitude) * area.height;
      canvas.drawLine(
        Offset(area.left, zeroY),
        Offset(area.right, zeroY),
        Paint()
          ..color = gridColor
          ..strokeWidth = 1.4,
      );
    }

    void linha(List<int> serie, Color color) {
      final path = Path();
      for (var i = 0; i < serie.length; i++) {
        final x = serie.length == 1
            ? area.center.dx
            : area.left + area.width * i / (serie.length - 1);
        final y = area.bottom - ((serie[i] - minimo) / amplitude) * area.height;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      if (serie.length == 1) {
        final y =
            area.bottom - ((serie.first - minimo) / amplitude) * area.height;
        canvas.drawCircle(
          Offset(area.center.dx, y),
          3.5,
          Paint()..color = color,
        );
      }
    }

    linha(dados.map((item) => item.faturamento).toList(), Colors.green);
    linha(dados.map((item) => item.comissao).toList(), Colors.orange);
    linha(dados.map((item) => item.repasse).toList(), Colors.lightBlue);
    linha(dados.map((item) => item.resultado).toList(), Colors.purpleAccent);
  }

  @override
  bool shouldRepaint(covariant _EvolucaoPainter oldDelegate) {
    return oldDelegate.dados != dados || oldDelegate.gridColor != gridColor;
  }
}

class _RankingItem {
  final String id;
  final String label;
  final int valor;
  final int unidades;
  final double percentualDoTotal;

  const _RankingItem({
    required this.id,
    required this.label,
    required this.valor,
    required this.unidades,
    required this.percentualDoTotal,
  });
}

class _AcumuladorRanking {
  final String id;
  final String label;
  int valor = 0;
  int unidades = 0;

  _AcumuladorRanking({required this.id, required this.label});
}

class _Rankings {
  final List<_RankingItem> clientes;
  final List<_RankingItem> produtos;
  final List<_RankingItem> comissoes;

  const _Rankings({
    required this.clientes,
    required this.produtos,
    required this.comissoes,
  });
}

_Rankings _montarRankings(List<_VendaLinha> linhas) {
  final clientes = <String, _AcumuladorRanking>{};
  final produtos = <String, _AcumuladorRanking>{};
  final comissoes = <String, _AcumuladorRanking>{};

  for (final linha in linhas) {
    final clienteId = linha.clienteId;
    if (clienteId != null && linha.vendaCentavos != null) {
      final item = clientes.putIfAbsent(
        clienteId,
            () => _AcumuladorRanking(id: clienteId, label: linha.cliente),
      );
      item.valor += linha.vendaCentavos!;
      item.unidades += linha.unidades;
    }

    if (linha.vendaCentavos != null) {
      final item = produtos.putIfAbsent(
        linha.skuId,
            () => _AcumuladorRanking(
          id: linha.skuId,
          label: '${linha.skuCodigo} · ${linha.produto}',
        ),
      );
      item.valor += linha.vendaCentavos!;
      item.unidades += linha.unidades;
    }

    if (clienteId != null && linha.historicoCompleto) {
      final item = comissoes.putIfAbsent(
        clienteId,
            () => _AcumuladorRanking(id: clienteId, label: linha.cliente),
      );
      item.valor += linha.comissaoCentavos!;
      item.unidades += linha.unidades;
    }
  }

  List<_RankingItem> finalizar(Map<String, _AcumuladorRanking> mapa) {
    final total = mapa.values.fold<int>(0, (soma, item) => soma + item.valor);
    final itens = mapa.values
        .map(
          (item) => _RankingItem(
        id: item.id,
        label: item.label,
        valor: item.valor,
        unidades: item.unidades,
        percentualDoTotal: total == 0 ? 0 : item.valor / total * 100,
      ),
    )
        .toList()
      ..sort((a, b) => b.valor.compareTo(a.valor));
    return itens.take(5).toList();
  }

  return _Rankings(
    clientes: finalizar(clientes),
    produtos: finalizar(produtos),
    comissoes: finalizar(comissoes),
  );
}

class _RankingCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;
  final List<_RankingItem> items;
  final ValueChanged<String> onTap;

  const _RankingCard({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.items,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final maior = items.isEmpty
        ? 1
        : math.max(1, items.map((item) => item.valor).reduce(math.max));
    return RelatorioSectionCard(
      title: title,
      subtitle: subtitle,
      child: items.isEmpty
          ? const SizedBox(
        height: 120,
        child: Center(child: Text('Sem dados no período.')),
      )
          : Column(
        children: [
          for (var indice = 0; indice < items.length; indice++) ...[
            _RankingLinha(
              posicao: indice + 1,
              item: items[indice],
              maior: maior,
              percentual: items[indice].percentualDoTotal,
              color: color,
              onTap: () => onTap(items[indice].id),
            ),
            if (indice != items.length - 1)
              const SizedBox(height: 13),
          ],
        ],
      ),
    );
  }
}

class _RankingLinha extends StatelessWidget {
  final int posicao;
  final _RankingItem item;
  final int maior;
  final double percentual;
  final Color color;
  final VoidCallback onTap;

  const _RankingLinha({
    required this.posicao,
    required this.item,
    required this.maior,
    required this.percentual,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            CircleAvatar(
              radius: 15,
              backgroundColor: color.withValues(alpha: .12),
              child: Text(
                '$posicao',
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatarReais(item.valor),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_percentual(percentual)}% · ${item.unidades} un.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: item.valor.abs() / maior.abs(),
                      minHeight: 4,
                      color: color,
                      backgroundColor:
                      theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}

class _VendasResultado extends StatelessWidget {
  final List<_VendaLinha> linhas;

  const _VendasResultado({required this.linhas});

  String _valor(int? centavos) =>
      centavos == null ? '—' : formatarReais(centavos);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            children: [
              for (var indice = 0; indice < linhas.length; indice++) ...[
                _VendaMobileCard(linha: linhas[indice]),
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
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Data')),
                DataColumn(label: Text('Lojista')),
                DataColumn(label: Text('Produto/SKU')),
                DataColumn(label: Text('Qtd.'), numeric: true),
                DataColumn(label: Text('Venda unit.'), numeric: true),
                DataColumn(label: Text('Venda bruta'), numeric: true),
                DataColumn(label: Text('Comissão'), numeric: true),
                DataColumn(label: Text('Repasse NEXT'), numeric: true),
                DataColumn(label: Text('Custo'), numeric: true),
                DataColumn(label: Text('Resultado'), numeric: true),
                DataColumn(label: Text('Margem'), numeric: true),
              ],
              rows: linhas.map((linha) {
                final resultado = linha.resultadoCentavos;
                return DataRow(
                  color: resultado != null && resultado < 0
                      ? WidgetStatePropertyAll(
                    Colors.red.withValues(alpha: .035),
                  )
                      : null,
                  cells: [
                    DataCell(_StatusHistorico(linha: linha)),
                    DataCell(
                      Text(
                        linha.data == null
                            ? '—'
                            : DateFormat('dd/MM/yyyy HH:mm').format(linha.data!),
                      ),
                    ),
                    DataCell(
                      SizedBox(
                        width: 185,
                        child: Text(
                          linha.cliente,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(
                      SizedBox(
                        width: 240,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              linha.produto,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              linha.skuCodigo,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                    DataCell(Text('${linha.unidades}')),
                    DataCell(Text(_valor(linha.valorUnitarioCentavos))),
                    DataCell(
                      Text(
                        _valor(linha.vendaCentavos),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    DataCell(Text(_valor(linha.comissaoCentavos))),
                    DataCell(Text(_valor(linha.repasseCentavos))),
                    DataCell(Text(_valor(linha.custoCentavos))),
                    DataCell(
                      Text(
                        _valor(resultado),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: resultado != null && resultado < 0
                              ? Colors.red
                              : null,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        linha.margemPercentual == null
                            ? '—'
                            : '${_percentual(linha.margemPercentual!)}%',
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

class _VendaMobileCard extends StatelessWidget {
  final _VendaLinha linha;

  const _VendaMobileCard({required this.linha});

  String _valor(int? centavos) =>
      centavos == null ? '—' : formatarReais(centavos);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resultado = linha.resultadoCentavos;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: resultado != null && resultado < 0
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
                linha.produto,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _valor(linha.vendaCentavos),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                linha.cliente,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 8,
                runSpacing: 7,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _StatusHistorico(linha: linha),
                  Text('${linha.unidades} un.'),
                  Text(
                    linha.data == null
                        ? 'Data não informada'
                        : DateFormat('dd/MM/yyyy HH:mm').format(linha.data!),
                    style: theme.textTheme.bodySmall,
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
              'SKU ${linha.skuCodigo}'
                  '${linha.codigoBarras.trim().isEmpty ? '' : ' · EAN ${linha.codigoBarras}'}',
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
              _ValorCompacto(
                label: 'Venda unitária',
                value: _valor(linha.valorUnitarioCentavos),
              ),
              _ValorCompacto(
                label: 'Comissão retida',
                value: _valor(linha.comissaoCentavos),
                color: Colors.orange,
              ),
              _ValorCompacto(
                label: 'Repasse NEXT',
                value: _valor(linha.repasseCentavos),
                color: Colors.lightBlue,
              ),
              _ValorCompacto(
                label: 'Custo',
                value: _valor(linha.custoCentavos),
              ),
              _ValorCompacto(
                label: 'Resultado',
                value: _valor(resultado),
                color: resultado != null && resultado < 0
                    ? Colors.red
                    : Colors.green,
              ),
              _ValorCompacto(
                label: 'Margem',
                value: linha.margemPercentual == null
                    ? '—'
                    : '${_percentual(linha.margemPercentual!)}%',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusHistorico extends StatelessWidget {
  final _VendaLinha linha;

  const _StatusHistorico({required this.linha});

  @override
  Widget build(BuildContext context) {
    if (linha.resultadoCentavos != null && linha.resultadoCentavos! < 0) {
      return const RelatorioStatusPill(
        label: 'Resultado negativo',
        color: Colors.red,
        icon: Icons.trending_down,
      );
    }
    if (linha.historicoCompleto) {
      return const RelatorioStatusPill(
        label: 'Completo',
        color: Colors.green,
        icon: Icons.verified_outlined,
      );
    }
    return const RelatorioStatusPill(
      label: 'Incompleto',
      color: Colors.orange,
      icon: Icons.history_toggle_off,
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
      width: 130,
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

void _ordenarLinhas(List<_VendaLinha> linhas, _OrdemVendas ordem) {
  int valorOuMenosUm(int? valor) => valor ?? -1;
  switch (ordem) {
    case _OrdemVendas.recentes:
      linhas.sort(
            (a, b) =>
            (b.data ?? DateTime(0)).compareTo(a.data ?? DateTime(0)),
      );
      break;
    case _OrdemVendas.antigas:
      linhas.sort(
            (a, b) =>
            (a.data ?? DateTime(9999)).compareTo(b.data ?? DateTime(9999)),
      );
      break;
    case _OrdemVendas.maiorValor:
      linhas.sort(
            (a, b) => valorOuMenosUm(b.vendaCentavos)
            .compareTo(valorOuMenosUm(a.vendaCentavos)),
      );
      break;
    case _OrdemVendas.maisUnidades:
      linhas.sort((a, b) => b.unidades.compareTo(a.unidades));
      break;
    case _OrdemVendas.maiorComissao:
      linhas.sort(
            (a, b) => valorOuMenosUm(b.comissaoCentavos)
            .compareTo(valorOuMenosUm(a.comissaoCentavos)),
      );
      break;
    case _OrdemVendas.maiorResultado:
      linhas.sort(
            (a, b) => valorOuMenosUm(b.resultadoCentavos)
            .compareTo(valorOuMenosUm(a.resultadoCentavos)),
      );
      break;
  }
}

String _labelPeriodo(_PeriodoVendas periodo) => switch (periodo) {
  _PeriodoVendas.seteDias => 'Últimos 7 dias',
  _PeriodoVendas.trintaDias => 'Últimos 30 dias',
  _PeriodoVendas.esteMes => 'Este mês',
  _PeriodoVendas.noventaDias => 'Últimos 90 dias',
  _PeriodoVendas.personalizado => 'Período personalizado',
  _PeriodoVendas.tudo => 'Todo o histórico',
};

String _percentual(double valor) =>
    valor.toStringAsFixed(1).replaceAll('.', ',');

String _dataCurta(DateTime data, _PeriodoVendas periodo) {
  if (periodo == _PeriodoVendas.tudo) {
    return DateFormat('MM/yyyy').format(data);
  }
  return DateFormat('dd/MM').format(data);
}
