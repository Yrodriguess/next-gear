import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_collections.dart';
import '../../clientes/presentation/cliente_providers.dart';
import '../../consignacoes/presentation/consignment_providers.dart';
import '../../estoque/domain/stock_movement.dart';
import '../../estoque/presentation/estoque_providers.dart';
import 'relatorios_ui.dart';

enum _NivelGiro { todos, alto, medio, baixo }
enum _OrdemGiro { maiorGiro, menorGiro, maiorCapital, cliente }

class RelatorioGiroPage extends ConsumerStatefulWidget {
  const RelatorioGiroPage({super.key});

  @override
  ConsumerState<RelatorioGiroPage> createState() => _RelatorioGiroPageState();
}

class _RelatorioGiroPageState extends ConsumerState<RelatorioGiroPage> {
  final _buscaController = TextEditingController();
  _NivelGiro _nivel = _NivelGiro.todos;
  _OrdemGiro _ordem = _OrdemGiro.maiorGiro;

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  double _indice(int consignadoCentavos, int vendidoCentavos) {
    if (consignadoCentavos == 0) return vendidoCentavos > 0 ? 999 : 0;
    return vendidoCentavos / consignadoCentavos;
  }

  _NivelGiro _classificar(double indice, int consignado) {
    if (consignado == 0 && indice == 0) return _NivelGiro.baixo;
    if (indice >= .5) return _NivelGiro.alto;
    if (indice >= .15) return _NivelGiro.medio;
    return _NivelGiro.baixo;
  }

  String _nivelLabel(_NivelGiro nivel) => switch (nivel) {
        _NivelGiro.todos => 'Todos',
        _NivelGiro.alto => 'Alto giro',
        _NivelGiro.medio => 'Giro médio',
        _NivelGiro.baixo => 'Baixo giro',
      };

  Color _nivelCor(_NivelGiro nivel) => switch (nivel) {
        _NivelGiro.alto => Colors.green,
        _NivelGiro.medio => Colors.orange,
        _NivelGiro.baixo => Colors.red,
        _NivelGiro.todos => Colors.blueGrey,
      };

  void _recarregar() {
    ref.invalidate(consignmentsAtivasProvider(AppConfig.currentOrgId));
    ref.invalidate(vendasProvider(AppConfig.currentOrgId));
    ref.invalidate(clientesListProvider);
  }

  @override
  Widget build(BuildContext context) {
    final consignacoesAsync =
        ref.watch(consignmentsAtivasProvider(AppConfig.currentOrgId));
    final vendasAsync = ref.watch(vendasProvider(AppConfig.currentOrgId));
    final clientesAsync = ref.watch(clientesListProvider);

    if (consignacoesAsync.hasError || vendasAsync.hasError || clientesAsync.hasError) {
      return RelatorioErrorState(onRetry: _recarregar);
    }
    if ((consignacoesAsync.isLoading && !consignacoesAsync.hasValue) ||
        (vendasAsync.isLoading && !vendasAsync.hasValue) ||
        (clientesAsync.isLoading && !clientesAsync.hasValue)) {
      return const RelatorioLoading();
    }

    final consignacoes = consignacoesAsync.value;
    final vendas = vendasAsync.value;
    final clientes = clientesAsync.value;
    if (consignacoes == null || vendas == null || clientes == null) {
      return const RelatorioLoading();
    }

    final vendidoPorCliente = <String, int>{};
    for (final venda in vendas) {
      final clienteId = LocalEstoque.extrairClienteId(venda.origem);
      if (clienteId == null) continue;
      final valor =
          venda.quantidade * (venda.valorVendaCentavosNoMomento ?? 0);
      vendidoPorCliente[clienteId] =
          (vendidoPorCliente[clienteId] ?? 0) + valor;
    }
    final consignadoPorCliente = <String, int>{};
    for (final consignacao in consignacoes) {
      consignadoPorCliente[consignacao.clienteId] =
          (consignadoPorCliente[consignacao.clienteId] ?? 0) +
              consignacao.valorVendaTotalCentavos;
    }

    final query = _buscaController.text.trim().toLowerCase();
    final todasLinhas = clientes.where((cliente) {
      return consignadoPorCliente.containsKey(cliente.id) ||
          vendidoPorCliente.containsKey(cliente.id);
    }).map((cliente) {
      final consignado = consignadoPorCliente[cliente.id] ?? 0;
      final vendido = vendidoPorCliente[cliente.id] ?? 0;
      final indice = _indice(consignado, vendido);
      return _GiroLinha(
        cliente: cliente.nomeFantasia?.isNotEmpty == true
            ? cliente.nomeFantasia!
            : cliente.nome,
        consignadoCentavos: consignado,
        vendidoCentavos: vendido,
        indice: indice,
        nivel: _classificar(indice, consignado),
      );
    }).toList();
    final linhas = todasLinhas.where((linha) {
      final nivelOk = _nivel == _NivelGiro.todos || linha.nivel == _nivel;
      final buscaOk = query.isEmpty || linha.cliente.toLowerCase().contains(query);
      return nivelOk && buscaOk;
    }).toList();

    switch (_ordem) {
      case _OrdemGiro.maiorGiro:
        linhas.sort((a, b) => b.indice.compareTo(a.indice));
        break;
      case _OrdemGiro.menorGiro:
        linhas.sort((a, b) => a.indice.compareTo(b.indice));
        break;
      case _OrdemGiro.maiorCapital:
        linhas.sort((a, b) => b.consignadoCentavos.compareTo(a.consignadoCentavos));
        break;
      case _OrdemGiro.cliente:
        linhas.sort((a, b) => a.cliente.toLowerCase().compareTo(b.cliente.toLowerCase()));
        break;
    }

    int quantidade(_NivelGiro nivel) =>
        todasLinhas.where((linha) => linha.nivel == nivel).length;
    final capital = todasLinhas.fold<int>(
      0,
      (total, linha) => total + linha.consignadoCentavos,
    );
    final vendido = todasLinhas.fold<int>(
      0,
      (total, linha) => total + linha.vendidoCentavos,
    );

    return SingleChildScrollView(
      child: RelatorioPageBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RelatorioIntro(
              title: 'Giro de estoque',
              subtitle:
                  'Compara o vendido acumulado com o valor atualmente consignado por cliente.',
              icon: Icons.sync_alt,
              action: OutlinedButton.icon(
                onPressed: _recarregar,
                icon: const Icon(Icons.refresh),
                label: const Text('Atualizar'),
              ),
            ),
            const SizedBox(height: 20),
            RelatorioMetricsGrid(
              children: [
                RelatorioMetricCard(
                  label: 'Alto giro',
                  value: '${quantidade(_NivelGiro.alto)}',
                  hint: 'Índice igual ou acima de 50%',
                  icon: Icons.trending_up,
                  color: Colors.green,
                ),
                RelatorioMetricCard(
                  label: 'Giro médio',
                  value: '${quantidade(_NivelGiro.medio)}',
                  hint: 'Índice entre 15% e 49%',
                  icon: Icons.trending_flat,
                  color: Colors.orange,
                ),
                RelatorioMetricCard(
                  label: 'Baixo giro',
                  value: '${quantidade(_NivelGiro.baixo)}',
                  hint: 'Índice abaixo de 15%',
                  icon: Icons.trending_down,
                  color: Colors.red,
                ),
                RelatorioMetricCard(
                  label: 'Capital analisado',
                  value: formatarReais(capital),
                  hint: 'Vendido acumulado: ${formatarReais(vendido)}',
                  icon: Icons.inventory_2_outlined,
                  color: Colors.lightBlue,
                ),
              ],
            ),
            const SizedBox(height: 16),
            RelatorioSectionCard(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final busca = RelatorioSearchField(
                    controller: _buscaController,
                    hint: 'Buscar cliente',
                    onChanged: (_) => setState(() {}),
                  );
                  final nivel = DropdownButtonFormField<_NivelGiro>(
                    initialValue: _nivel,
                    decoration: const InputDecoration(
                      labelText: 'Classificação',
                      prefixIcon: Icon(Icons.filter_alt_outlined),
                    ),
                    items: _NivelGiro.values
                        .map((item) => DropdownMenuItem(
                              value: item,
                              child: Text(_nivelLabel(item)),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _nivel = value);
                    },
                  );
                  final ordem = DropdownButtonFormField<_OrdemGiro>(
                    initialValue: _ordem,
                    decoration: const InputDecoration(
                      labelText: 'Ordenar por',
                      prefixIcon: Icon(Icons.sort),
                    ),
                    items: const [
                      DropdownMenuItem(value: _OrdemGiro.maiorGiro, child: Text('Maior giro')),
                      DropdownMenuItem(value: _OrdemGiro.menorGiro, child: Text('Menor giro')),
                      DropdownMenuItem(value: _OrdemGiro.maiorCapital, child: Text('Maior capital')),
                      DropdownMenuItem(value: _OrdemGiro.cliente, child: Text('Cliente A–Z')),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _ordem = value);
                    },
                  );
                  if (constraints.maxWidth < 800) {
                    return Column(children: [
                      busca,
                      const SizedBox(height: 12),
                      nivel,
                      const SizedBox(height: 12),
                      ordem,
                    ]);
                  }
                  return Row(children: [
                    Expanded(flex: 2, child: busca),
                    const SizedBox(width: 12),
                    Expanded(child: nivel),
                    const SizedBox(width: 12),
                    Expanded(child: ordem),
                  ]);
                },
              ),
            ),
            const SizedBox(height: 16),
            RelatorioSectionCard(
              title: 'Desempenho por cliente',
              subtitle: '${linhas.length} resultados encontrados',
              child: linhas.isEmpty
                  ? RelatorioEmptyState(
                      icon: Icons.sync_disabled,
                      title: todasLinhas.isEmpty
                          ? 'Ainda não há dados de giro'
                          : 'Nenhum cliente encontrado',
                      message: todasLinhas.isEmpty
                          ? 'O relatório será formado quando houver consignação ou venda.'
                          : 'Ajuste a busca ou a classificação selecionada.',
                      action: todasLinhas.isEmpty
                          ? null
                          : TextButton(
                              onPressed: () => setState(() {
                                _buscaController.clear();
                                _nivel = _NivelGiro.todos;
                              }),
                              child: const Text('Limpar filtros'),
                            ),
                    )
                  : _GiroResultado(
                      linhas: linhas,
                      nivelLabel: _nivelLabel,
                      nivelCor: _nivelCor,
                    ),
            ),
            const SizedBox(height: 12),
            Text(
              'Índice de giro = valor vendido acumulado ÷ valor consignado atual. Use-o como sinal operacional, sempre considerando o tempo em campo.',
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

class _GiroLinha {
  final String cliente;
  final int consignadoCentavos;
  final int vendidoCentavos;
  final double indice;
  final _NivelGiro nivel;

  const _GiroLinha({
    required this.cliente,
    required this.consignadoCentavos,
    required this.vendidoCentavos,
    required this.indice,
    required this.nivel,
  });
}

class _GiroResultado extends StatelessWidget {
  final List<_GiroLinha> linhas;
  final String Function(_NivelGiro) nivelLabel;
  final Color Function(_NivelGiro) nivelCor;

  const _GiroResultado({
    required this.linhas,
    required this.nivelLabel,
    required this.nivelCor,
  });

  String _percentual(_GiroLinha linha) {
    if (linha.indice == 999) return 'Sem saldo atual';
    return '${(linha.indice * 100).toStringAsFixed(0)}%';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 780) {
          return Column(
            children: linhas.map((linha) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Expanded(child: Text(linha.cliente, style: const TextStyle(fontWeight: FontWeight.w700))),
                        RelatorioStatusPill(label: nivelLabel(linha.nivel), color: nivelCor(linha.nivel)),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(child: _MiniValue(label: 'Consignado', value: formatarReais(linha.consignadoCentavos))),
                        Expanded(child: _MiniValue(label: 'Vendido', value: formatarReais(linha.vendidoCentavos))),
                        Expanded(child: _MiniValue(label: 'Índice', value: _percentual(linha))),
                      ]),
                    ],
                  ),
                ),
              );
            }).toList(),
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Cliente')),
                DataColumn(label: Text('Consignado'), numeric: true),
                DataColumn(label: Text('Vendido'), numeric: true),
                DataColumn(label: Text('Índice'), numeric: true),
                DataColumn(label: Text('Classificação')),
              ],
              rows: linhas.map((linha) => DataRow(cells: [
                    DataCell(SizedBox(width: 240, child: Text(linha.cliente, maxLines: 1, overflow: TextOverflow.ellipsis))),
                    DataCell(Text(formatarReais(linha.consignadoCentavos))),
                    DataCell(Text(formatarReais(linha.vendidoCentavos))),
                    DataCell(Text(_percentual(linha), style: const TextStyle(fontWeight: FontWeight.w700))),
                    DataCell(RelatorioStatusPill(label: nivelLabel(linha.nivel), color: nivelCor(linha.nivel))),
                  ])).toList(),
            ),
          ),
        );
      },
    );
  }
}

class _MiniValue extends StatelessWidget {
  final String label;
  final String value;

  const _MiniValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 3),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }
}
