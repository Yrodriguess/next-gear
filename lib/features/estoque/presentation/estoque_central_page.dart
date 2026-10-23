import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/current_org_provider.dart';
import '../../../core/widgets/barcode_scanner_page.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../produtos/domain/produto.dart';
import '../../produtos/domain/sku.dart';
import '../../produtos/presentation/produto_providers.dart';
import '../../produtos/presentation/sku_detail_page.dart';
import '../domain/stock_movement.dart';
import 'entrada_estoque_page.dart';
import 'estoque_providers.dart';
import 'minha_carga_page.dart';
import 'transferencia_estoque_page.dart';

enum _FiltroEstoque {
  todos,
  comSaldo,
  estoqueBaixo,
  semSaldo,
}

enum _OrdenacaoEstoque {
  nomeAZ,
  menorEstoque,
  maiorEstoque,
  codigo,
}

class EstoqueCentralPage extends ConsumerStatefulWidget {
  const EstoqueCentralPage({super.key});

  @override
  ConsumerState<EstoqueCentralPage> createState() =>
      _EstoqueCentralPageState();
}

class _EstoqueCentralPageState extends ConsumerState<EstoqueCentralPage> {
  final _buscaController = TextEditingController();

  String _busca = '';
  _FiltroEstoque _filtro = _FiltroEstoque.todos;
  _OrdenacaoEstoque _ordenacao = _OrdenacaoEstoque.nomeAZ;

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  Future<void> _abrirEntrada() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const EntradaEstoquePage()),
    );
  }

  Future<void> _abrirTransferencia() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TransferenciaEstoquePage()),
    );
  }

  Future<void> _abrirMinhaCarga() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MinhaCargaPage()),
    );
  }

  Future<void> _escanearCodigo() async {
    final codigo = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );

    if (codigo == null || !mounted) return;

    // Não removemos letras: o scanner também pode retornar um código
    // interno alfanumérico, além de EAN/GTIN numérico.
    final codigoLimpo = codigo.trim();

    setState(() {
      _buscaController.text = codigoLimpo;
      _buscaController.selection = TextSelection.collapsed(
        offset: codigoLimpo.length,
      );
      _busca = codigoLimpo.toLowerCase();
    });
  }

  void _limparBusca() {
    _buscaController.clear();
    setState(() => _busca = '');
  }

  void _recarregar() {
    final orgId = ref.read(currentOrgIdProvider);

    if (orgId != null) {
      ref.invalidate(
        saldosDoLocalProvider(
          (orgId: orgId, localId: LocalEstoque.central),
        ),
      );
    }

    ref.invalidate(skusListProvider);
    ref.invalidate(produtosListProvider);
  }

  @override
  Widget build(BuildContext context) {
    final orgId = ref.watch(currentOrgIdProvider);
    final compacto = MediaQuery.sizeOf(context).width < 760;

    final saldosAsync = orgId == null
        ? null
        : ref.watch(
      saldosDoLocalProvider(
        (orgId: orgId, localId: LocalEstoque.central),
      ),
    );

    final skusAsync = ref.watch(skusListProvider);
    final produtosAsync = ref.watch(produtosListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Estoque Central'),
        actions: [
          if (compacto) ...[
            IconButton(
              tooltip: 'Minha carga',
              onPressed: _abrirMinhaCarga,
              icon: const Icon(Icons.person_pin_circle_outlined),
            ),
            IconButton(
              tooltip: 'Movimentar carga',
              onPressed: _abrirTransferencia,
              icon: const Icon(Icons.swap_horiz_rounded),
            ),
          ],
          IconButton(
            tooltip: 'Atualizar estoque',
            onPressed: _recarregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: compacto
          ? FloatingActionButton.extended(
        heroTag: 'estoque_entrada_fab',
        onPressed: _abrirEntrada,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Entrada'),
      )
          : null,
      body: orgId == null || saldosAsync == null
          ? _ErroEstoque(
        mensagem: 'Não foi possível identificar sua organização.',
        onTentarNovamente: _recarregar,
      )
          : saldosAsync.when(
        loading: () => const _LoadingEstoque(),
        error: (error, stack) {
          debugPrint(
            'Erro ao carregar saldo do estoque central: $error\n$stack',
          );
          return _ErroEstoque(
            mensagem: 'Não foi possível carregar o estoque central.',
            onTentarNovamente: _recarregar,
          );
        },
        data: (saldos) {
          return skusAsync.when(
            loading: () => const _LoadingEstoque(),
            error: (error, stack) {
              debugPrint('Erro ao carregar SKUs: $error\n$stack');
              return _ErroEstoque(
                mensagem: 'Não foi possível carregar os produtos.',
                onTentarNovamente: _recarregar,
              );
            },
            data: (skus) {
              return produtosAsync.when(
                loading: () => const _LoadingEstoque(),
                error: (error, stack) {
                  debugPrint(
                    'Erro ao carregar produtos: $error\n$stack',
                  );
                  return _ErroEstoque(
                    mensagem: 'Não foi possível carregar os produtos.',
                    onTentarNovamente: _recarregar,
                  );
                },
                data: (produtos) => _buildEstoque(
                  saldos: saldos,
                  skus: skus,
                  produtos: produtos,
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEstoque({
    required List<dynamic> saldos,
    required List<Sku> skus,
    required List<Produto> produtos,
  }) {
    final skusPorId = <String, Sku>{
      for (final sku in skus)
        if (sku.id != null) sku.id!: sku,
    };

    final produtosPorId = <String, Produto>{
      for (final produto in produtos)
        if (produto.id != null) produto.id!: produto,
    };

    final itens = <_EstoqueCentralItem>[];

    for (final saldo in saldos) {
      // No domínio atual, saldo.produtoId armazena o ID do SKU.
      final String skuId = saldo.produtoId;
      final sku = skusPorId[skuId];

      if (sku == null) {
        itens.add(
          _EstoqueCentralItem(
            skuId: skuId,
            descricao: 'SKU não encontrado',
            variacao: null,
            codigoInterno: null,
            codigoBarras: null,
            fotoUrl: null,
            quantidade: saldo.quantidade,
            estoqueMinimo: 0,
            cadastroValido: false,
          ),
        );
        continue;
      }

      final produto = produtosPorId[sku.produtoId];

      itens.add(
        _EstoqueCentralItem(
          skuId: skuId,
          descricao: produto?.descricao ?? 'Produto não encontrado',
          variacao: sku.variacao,
          codigoInterno: sku.codigoInterno,
          codigoBarras: sku.codigoBarras,
          fotoUrl: produto?.fotoUrl,
          quantidade: saldo.quantidade,
          estoqueMinimo: sku.estoqueMinimo,
          cadastroValido: produto != null,
        ),
      );
    }

    final totalSkusComSaldo = itens.where((item) => item.possuiSaldo).length;
    final totalUnidades = itens.fold<int>(
      0,
          (total, item) =>
      total + (item.quantidade > 0 ? item.quantidade : 0),
    );
    final abaixoDoMinimo = itens.where((item) => item.estoqueBaixo).length;
    final semSaldo = itens.where((item) => item.semSaldo).length;

    final itensFiltrados = itens.where((item) {
      final correspondeBusca = _busca.isEmpty ||
          [
            item.descricao,
            item.variacao ?? '',
            item.codigoInterno ?? '',
            item.codigoBarras ?? '',
          ].join(' ').toLowerCase().contains(_busca);

      if (!correspondeBusca) return false;

      return switch (_filtro) {
        _FiltroEstoque.todos => true,
        _FiltroEstoque.comSaldo => item.possuiSaldo,
        _FiltroEstoque.estoqueBaixo => item.estoqueBaixo,
        _FiltroEstoque.semSaldo => item.semSaldo,
      };
    }).toList();

    switch (_ordenacao) {
      case _OrdenacaoEstoque.nomeAZ:
        itensFiltrados.sort(
              (a, b) =>
              a.descricao.toLowerCase().compareTo(b.descricao.toLowerCase()),
        );
        break;
      case _OrdenacaoEstoque.menorEstoque:
        itensFiltrados.sort(
              (a, b) => a.quantidade.compareTo(b.quantidade),
        );
        break;
      case _OrdenacaoEstoque.maiorEstoque:
        itensFiltrados.sort(
              (a, b) => b.quantidade.compareTo(a.quantidade),
        );
        break;
      case _OrdenacaoEstoque.codigo:
        itensFiltrados.sort(
              (a, b) => (a.codigoInterno ?? '')
              .toLowerCase()
              .compareTo((b.codigoInterno ?? '').toLowerCase()),
        );
        break;
    }

    return SafeArea(
      child: ResponsiveCenter(
        maxWidth: 1180,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compacto = constraints.maxWidth < 760;

            if (compacto) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 110),
                children: [
                  _CabecalhoEstoque(
                    onEntrada: _abrirEntrada,
                    onMovimentarCarga: _abrirTransferencia,
                    onMinhaCarga: _abrirMinhaCarga,
                  ),
                  const SizedBox(height: 18),
                  _ResumoEstoque(
                    totalSkus: totalSkusComSaldo,
                    totalUnidades: totalUnidades,
                    abaixoDoMinimo: abaixoDoMinimo,
                    semSaldo: semSaldo,
                  ),
                  const SizedBox(height: 18),
                  _FerramentasEstoque(
                    controller: _buscaController,
                    possuiBusca: _busca.isNotEmpty,
                    filtro: _filtro,
                    ordenacao: _ordenacao,
                    totalItens: itens.length,
                    totalFiltrados: itensFiltrados.length,
                    totalComSaldo: totalSkusComSaldo,
                    totalEstoqueBaixo: abaixoDoMinimo,
                    totalSemSaldo: semSaldo,
                    onBuscaChanged: (value) {
                      setState(() => _busca = value.trim().toLowerCase());
                    },
                    onLimparBusca: _limparBusca,
                    onScanner: _escanearCodigo,
                    onFiltroChanged: (filtro) =>
                        setState(() => _filtro = filtro),
                    onOrdenacaoChanged: (ordenacao) {
                      setState(() => _ordenacao = ordenacao);
                    },
                  ),
                  const SizedBox(height: 12),
                  if (itens.isEmpty)
                    _EstoqueVazio(onEntrada: _abrirEntrada)
                  else if (itensFiltrados.isEmpty)
                    _NenhumResultado(
                      busca: _buscaController.text,
                      onLimpar: () {
                        _limparBusca();
                        setState(() => _filtro = _FiltroEstoque.todos);
                      },
                    )
                  else
                    for (var index = 0;
                    index < itensFiltrados.length;
                    index++) ...[
                      _EstoqueItemCard(
                        item: itensFiltrados[index],
                        onTap: itensFiltrados[index].cadastroValido
                            ? () => _abrirItem(itensFiltrados[index])
                            : null,
                      ),
                      if (index < itensFiltrados.length - 1)
                        const SizedBox(height: 8),
                    ],
                ],
              );
            }

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  _CabecalhoEstoque(
                    onEntrada: _abrirEntrada,
                    onMovimentarCarga: _abrirTransferencia,
                    onMinhaCarga: _abrirMinhaCarga,
                  ),
                  const SizedBox(height: 18),
                  _ResumoEstoque(
                    totalSkus: totalSkusComSaldo,
                    totalUnidades: totalUnidades,
                    abaixoDoMinimo: abaixoDoMinimo,
                    semSaldo: semSaldo,
                  ),
                  const SizedBox(height: 18),
                  _FerramentasEstoque(
                    controller: _buscaController,
                    possuiBusca: _busca.isNotEmpty,
                    filtro: _filtro,
                    ordenacao: _ordenacao,
                    totalItens: itens.length,
                    totalFiltrados: itensFiltrados.length,
                    totalComSaldo: totalSkusComSaldo,
                    totalEstoqueBaixo: abaixoDoMinimo,
                    totalSemSaldo: semSaldo,
                    onBuscaChanged: (value) {
                      setState(() => _busca = value.trim().toLowerCase());
                    },
                    onLimparBusca: _limparBusca,
                    onScanner: _escanearCodigo,
                    onFiltroChanged: (filtro) =>
                        setState(() => _filtro = filtro),
                    onOrdenacaoChanged: (ordenacao) {
                      setState(() => _ordenacao = ordenacao);
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: itens.isEmpty
                        ? _EstoqueVazio(onEntrada: _abrirEntrada)
                        : itensFiltrados.isEmpty
                        ? _NenhumResultado(
                      busca: _buscaController.text,
                      onLimpar: () {
                        _limparBusca();
                        setState(
                              () => _filtro = _FiltroEstoque.todos,
                        );
                      },
                    )
                        : LayoutBuilder(
                      builder: (context, constraints) {
                        final usarTabela =
                            constraints.maxWidth >= 820;

                        if (usarTabela) {
                          return _TabelaEstoque(
                            itens: itensFiltrados,
                            onAbrirItem: _abrirItem,
                          );
                        }

                        return ListView.separated(
                          padding:
                          const EdgeInsets.only(bottom: 100),
                          itemCount: itensFiltrados.length,
                          separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = itensFiltrados[index];
                            return _EstoqueItemCard(
                              item: item,
                              onTap: item.cadastroValido
                                  ? () => _abrirItem(item)
                                  : null,
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _abrirItem(_EstoqueCentralItem item) {
    if (!item.cadastroValido) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SkuDetailPage(skuId: item.skuId),
      ),
    );
  }
}

class _EstoqueCentralItem {
  final String skuId;
  final String descricao;
  final String? variacao;
  final String? codigoInterno;
  final String? codigoBarras;
  final String? fotoUrl;
  final int quantidade;
  final int estoqueMinimo;
  final bool cadastroValido;

  const _EstoqueCentralItem({
    required this.skuId,
    required this.descricao,
    required this.variacao,
    required this.codigoInterno,
    required this.codigoBarras,
    required this.fotoUrl,
    required this.quantidade,
    required this.estoqueMinimo,
    required this.cadastroValido,
  });

  bool get possuiSaldo => quantidade > 0;
  bool get semSaldo => quantidade <= 0;
  bool get inconsistente => quantidade < 0 || !cadastroValido;

  bool get estoqueBaixo =>
      quantidade > 0 && estoqueMinimo > 0 && quantidade <= estoqueMinimo;
}

class _CabecalhoEstoque extends StatelessWidget {
  final VoidCallback onEntrada;
  final VoidCallback onMovimentarCarga;
  final VoidCallback onMinhaCarga;

  const _CabecalhoEstoque({
    required this.onEntrada,
    required this.onMovimentarCarga,
    required this.onMinhaCarga,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compacto = constraints.maxWidth < 760;

        if (compacto) {
          return Text(
            'Acompanhe saldos e movimentações do estoque.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          );
        }

        return Row(
          children: [
            Expanded(
              child: Text(
                'Acompanhe saldos, alertas e movimentações do estoque.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: onMinhaCarga,
              icon: const Icon(Icons.person_pin_circle_outlined),
              label: const Text('Minha carga'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: onMovimentarCarga,
              icon: const Icon(Icons.swap_horiz_rounded),
              label: const Text('Movimentar carga'),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: onEntrada,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Registrar entrada'),
            ),
          ],
        );
      },
    );
  }
}

class _ResumoEstoque extends StatelessWidget {
  final int totalSkus;
  final int totalUnidades;
  final int abaixoDoMinimo;
  final int semSaldo;

  const _ResumoEstoque({
    required this.totalSkus,
    required this.totalUnidades,
    required this.abaixoDoMinimo,
    required this.semSaldo,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final colunas = constraints.maxWidth >= 900 ? 4 : 2;
        const espacamento = 12.0;
        final largura =
            (constraints.maxWidth - (espacamento * (colunas - 1))) / colunas;

        final cards = <Widget>[
          _ResumoCard(
            icon: Icons.inventory_2_outlined,
            valor: '$totalSkus',
            label: totalSkus == 1 ? 'SKU com saldo' : 'SKUs com saldo',
          ),
          _ResumoCard(
            icon: Icons.widgets_outlined,
            valor: '$totalUnidades',
            label: totalUnidades == 1 ? 'Unidade' : 'Total de unidades',
          ),
          _ResumoCard(
            icon: Icons.warning_amber_rounded,
            valor: '$abaixoDoMinimo',
            label: 'Estoque baixo',
            tipo: abaixoDoMinimo > 0
                ? _TipoResumo.alerta
                : _TipoResumo.normal,
          ),
          _ResumoCard(
            icon: Icons.remove_shopping_cart_outlined,
            valor: '$semSaldo',
            label: 'Sem saldo',
            tipo: semSaldo > 0 ? _TipoResumo.erro : _TipoResumo.normal,
          ),
        ];

        return Wrap(
          spacing: espacamento,
          runSpacing: espacamento,
          children: [
            for (final card in cards)
              SizedBox(
                width: largura,
                child: card,
              ),
          ],
        );
      },
    );
  }
}

enum _TipoResumo { normal, alerta, erro }

class _ResumoCard extends StatelessWidget {
  final IconData icon;
  final String valor;
  final String label;
  final _TipoResumo tipo;

  const _ResumoCard({
    required this.icon,
    required this.valor,
    required this.label,
    this.tipo = _TipoResumo.normal,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = switch (tipo) {
      _TipoResumo.normal => colorScheme.primary,
      _TipoResumo.alerta => Colors.amber.shade600,
      _TipoResumo.erro => colorScheme.error,
    };

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    valor,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FerramentasEstoque extends StatelessWidget {
  final TextEditingController controller;
  final bool possuiBusca;
  final _FiltroEstoque filtro;
  final _OrdenacaoEstoque ordenacao;
  final int totalItens;
  final int totalFiltrados;
  final int totalComSaldo;
  final int totalEstoqueBaixo;
  final int totalSemSaldo;
  final ValueChanged<String> onBuscaChanged;
  final VoidCallback onLimparBusca;
  final VoidCallback onScanner;
  final ValueChanged<_FiltroEstoque> onFiltroChanged;
  final ValueChanged<_OrdenacaoEstoque> onOrdenacaoChanged;

  const _FerramentasEstoque({
    required this.controller,
    required this.possuiBusca,
    required this.filtro,
    required this.ordenacao,
    required this.totalItens,
    required this.totalFiltrados,
    required this.totalComSaldo,
    required this.totalEstoqueBaixo,
    required this.totalSemSaldo,
    required this.onBuscaChanged,
    required this.onLimparBusca,
    required this.onScanner,
    required this.onFiltroChanged,
    required this.onOrdenacaoChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.search,
                onChanged: onBuscaChanged,
                decoration: InputDecoration(
                  hintText: 'Buscar produto, SKU ou código de barras',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: possuiBusca
                      ? IconButton(
                    tooltip: 'Limpar busca',
                    onPressed: onLimparBusca,
                    icon: const Icon(Icons.close_rounded),
                  )
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 56,
              height: 56,
              child: IconButton.filledTonal(
                tooltip: 'Escanear código de barras',
                onPressed: onScanner,
                icon: const Icon(Icons.qr_code_scanner_rounded),
              ),
            ),
            const SizedBox(width: 8),
            _OrdenacaoButton(
              ordenacao: ordenacao,
              onChanged: onOrdenacaoChanged,
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final compacto = constraints.maxWidth < 700;
            final chips = <Widget>[
              _FiltroChip(
                label: 'Todos',
                quantidade: totalItens,
                selecionado: filtro == _FiltroEstoque.todos,
                onSelected: () => onFiltroChanged(_FiltroEstoque.todos),
              ),
              _FiltroChip(
                label: 'Com saldo',
                quantidade: totalComSaldo,
                selecionado: filtro == _FiltroEstoque.comSaldo,
                onSelected: () => onFiltroChanged(_FiltroEstoque.comSaldo),
              ),
              _FiltroChip(
                label: 'Estoque baixo',
                quantidade: totalEstoqueBaixo,
                selecionado: filtro == _FiltroEstoque.estoqueBaixo,
                onSelected: () => onFiltroChanged(_FiltroEstoque.estoqueBaixo),
              ),
              _FiltroChip(
                label: 'Sem saldo',
                quantidade: totalSemSaldo,
                selecionado: filtro == _FiltroEstoque.semSaldo,
                onSelected: () => onFiltroChanged(_FiltroEstoque.semSaldo),
              ),
            ];

            if (compacto) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < chips.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          chips[i],
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$totalFiltrados de $totalItens produto(s)',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              );
            }

            return Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: chips,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '$totalFiltrados de $totalItens produto(s)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _FiltroChip extends StatelessWidget {
  final String label;
  final int quantidade;
  final bool selecionado;
  final VoidCallback onSelected;

  const _FiltroChip({
    required this.label,
    required this.quantidade,
    required this.selecionado,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      selected: selecionado,
      onSelected: (_) => onSelected(),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          const SizedBox(width: 7),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: selecionado
                  ? Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.18)
                  : Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$quantidade',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrdenacaoButton extends StatelessWidget {
  final _OrdenacaoEstoque ordenacao;
  final ValueChanged<_OrdenacaoEstoque> onChanged;

  const _OrdenacaoButton({
    required this.ordenacao,
    required this.onChanged,
  });

  String get _label => switch (ordenacao) {
    _OrdenacaoEstoque.nomeAZ => 'Nome A–Z',
    _OrdenacaoEstoque.menorEstoque => 'Menor estoque',
    _OrdenacaoEstoque.maiorEstoque => 'Maior estoque',
    _OrdenacaoEstoque.codigo => 'Código SKU',
  };

  @override
  Widget build(BuildContext context) {
    final compacto = MediaQuery.sizeOf(context).width < 600;

    return PopupMenuButton<_OrdenacaoEstoque>(
      tooltip: 'Ordenar estoque',
      initialValue: ordenacao,
      onSelected: onChanged,
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _OrdenacaoEstoque.nomeAZ,
          child: Text('Nome A–Z'),
        ),
        PopupMenuItem(
          value: _OrdenacaoEstoque.menorEstoque,
          child: Text('Menor estoque'),
        ),
        PopupMenuItem(
          value: _OrdenacaoEstoque.maiorEstoque,
          child: Text('Maior estoque'),
        ),
        PopupMenuItem(
          value: _OrdenacaoEstoque.codigo,
          child: Text('Código SKU'),
        ),
      ],
      child: Container(
        height: 56,
        padding: EdgeInsets.symmetric(horizontal: compacto ? 14 : 16),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sort_rounded),
            if (!compacto) ...[
              const SizedBox(width: 9),
              Text(_label),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_drop_down_rounded),
            ],
          ],
        ),
      ),
    );
  }
}

class _TabelaEstoque extends StatelessWidget {
  final List<_EstoqueCentralItem> itens;
  final ValueChanged<_EstoqueCentralItem> onAbrirItem;

  const _TabelaEstoque({
    required this.itens,
    required this.onAbrirItem,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const _CabecalhoTabela(),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: itens.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = itens[index];
                return _LinhaTabelaEstoque(
                  item: item,
                  onTap: item.cadastroValido
                      ? () => onAbrirItem(item)
                      : null,
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Mostrando ${itens.length} produto(s)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CabecalhoTabela extends StatelessWidget {
  const _CabecalhoTabela();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );

    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      child: Row(
        children: [
          Expanded(flex: 5, child: Text('Produto', style: style)),
          Expanded(flex: 2, child: Text('SKU', style: style)),
          Expanded(flex: 2, child: Text('Estoque atual', style: style)),
          Expanded(flex: 2, child: Text('Mínimo', style: style)),
          Expanded(flex: 2, child: Text('Situação', style: style)),
          const SizedBox(width: 28),
        ],
      ),
    );
  }
}

class _LinhaTabelaEstoque extends StatelessWidget {
  final _EstoqueCentralItem item;
  final VoidCallback? onTap;

  const _LinhaTabelaEstoque({
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Row(
                children: [
                  _ProdutoImagem(url: item.fotoUrl, tamanho: 52),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.descricao,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (item.variacao?.trim().isNotEmpty == true) ...[
                          const SizedBox(height: 2),
                          Text(
                            item.variacao!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                item.codigoInterno ?? '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                '${item.quantidade} un.',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: item.semSaldo
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                item.estoqueMinimo > 0 ? '${item.estoqueMinimo} un.' : '—',
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _SituacaoChip(item: item),
              ),
            ),
            SizedBox(
              width: 28,
              child: item.cadastroValido
                  ? const Icon(Icons.chevron_right_rounded)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _EstoqueItemCard extends StatelessWidget {
  final _EstoqueCentralItem item;
  final VoidCallback? onTap;

  const _EstoqueItemCard({
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProdutoImagem(url: item.fotoUrl, tamanho: 64),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.descricao,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (item.variacao?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.variacao!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 5),
                    Text(
                      [
                        if (item.codigoInterno?.isNotEmpty == true)
                          item.codigoInterno!,
                        if (item.estoqueMinimo > 0)
                          'Mínimo ${item.estoqueMinimo} un.',
                      ].join(' • '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 9),
                    _SituacaoChip(item: item),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _QuantidadeEstoque(
                    quantidade: item.quantidade,
                    alerta: item.estoqueBaixo || item.semSaldo,
                  ),
                  if (item.cadastroValido) ...[
                    const SizedBox(height: 13),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProdutoImagem extends StatelessWidget {
  final String? url;
  final double tamanho;

  const _ProdutoImagem({
    required this.url,
    required this.tamanho,
  });

  @override
  Widget build(BuildContext context) {
    final urlValida = url?.trim().isNotEmpty == true;

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: tamanho,
        height: tamanho,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: urlValida
            ? Image.network(
          url!,
          width: tamanho,
          height: tamanho,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const _ImagemFallback(),
        )
            : const _ImagemFallback(),
      ),
    );
  }
}

class _ImagemFallback extends StatelessWidget {
  const _ImagemFallback();

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.inventory_2_outlined,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }
}

class _QuantidadeEstoque extends StatelessWidget {
  final int quantidade;
  final bool alerta;

  const _QuantidadeEstoque({
    required this.quantidade,
    required this.alerta,
  });

  @override
  Widget build(BuildContext context) {
    final color = alerta
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$quantidade un.',
        style: TextStyle(fontWeight: FontWeight.w800, color: color),
      ),
    );
  }
}

class _SituacaoChip extends StatelessWidget {
  final _EstoqueCentralItem item;

  const _SituacaoChip({required this.item});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    late final String label;
    late final IconData icon;
    late final Color color;

    if (item.inconsistente) {
      label = 'Inconsistência';
      icon = Icons.error_outline_rounded;
      color = colorScheme.error;
    } else if (item.semSaldo) {
      label = 'Sem saldo';
      icon = Icons.remove_circle_outline_rounded;
      color = colorScheme.error;
    } else if (item.estoqueBaixo) {
      label = 'Estoque baixo';
      icon = Icons.warning_amber_rounded;
      color = Colors.amber.shade700;
    } else {
      label = 'Normal';
      icon = Icons.check_circle_outline_rounded;
      color = colorScheme.primary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.34)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EstoqueVazio extends StatelessWidget {
  final VoidCallback onEntrada;

  const _EstoqueVazio({required this.onEntrada});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Estoque central vazio',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Registre uma entrada de mercadoria para começar a movimentar '
                  'o estoque.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onEntrada,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Registrar entrada'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NenhumResultado extends StatelessWidget {
  final String busca;
  final VoidCallback onLimpar;

  const _NenhumResultado({
    required this.busca,
    required this.onLimpar,
  });

  @override
  Widget build(BuildContext context) {
    final possuiBusca = busca.trim().isNotEmpty;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded, size: 56),
            const SizedBox(height: 12),
            Text(
              'Nenhum produto encontrado',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              possuiBusca
                  ? 'Nenhum item corresponde a “$busca” e aos filtros atuais.'
                  : 'Não há produtos que correspondam ao filtro selecionado.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onLimpar,
              icon: const Icon(Icons.filter_alt_off_outlined),
              label: const Text('Limpar busca e filtros'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingEstoque extends StatelessWidget {
  const _LoadingEstoque();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 14),
          Text(
            'Carregando estoque…',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _ErroEstoque extends StatelessWidget {
  final String mensagem;
  final VoidCallback onTentarNovamente;

  const _ErroEstoque({
    required this.mensagem,
    required this.onTentarNovamente,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(mensagem, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onTentarNovamente,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
