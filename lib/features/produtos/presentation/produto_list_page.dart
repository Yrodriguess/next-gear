import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/responsive_center.dart';
import '../../../core/widgets/barcode_scanner_page.dart';
import '../domain/produto.dart';
import '../domain/sku.dart';
import 'produto_form_page.dart';
import 'produto_providers.dart';
import 'sku_detail_page.dart';

enum _FiltroProduto { todos, ativos, inativos }

enum _OrdenacaoProduto { nomeAZ, nomeZA }

class ProdutoListPage extends ConsumerStatefulWidget {
  const ProdutoListPage({super.key});

  @override
  ConsumerState<ProdutoListPage> createState() => _ProdutoListPageState();
}

class _ProdutoListPageState extends ConsumerState<ProdutoListPage> {
  final _buscaController = TextEditingController();
  final _buscaFocusNode = FocusNode();

  String _busca = '';
  String? _produtoEmNavegacaoId;
  _FiltroProduto _filtro = _FiltroProduto.todos;
  _OrdenacaoProduto _ordenacao = _OrdenacaoProduto.nomeAZ;

  @override
  void dispose() {
    _buscaController.dispose();
    _buscaFocusNode.dispose();
    super.dispose();
  }

  List<_ProdutoComSkus> _montarCatalogo(
      List<Produto> produtos,
      List<Sku> skus,
      ) {
    final skusPorProduto = <String, List<Sku>>{};

    for (final sku in skus) {
      skusPorProduto.putIfAbsent(sku.produtoId, () => <Sku>[]).add(sku);
    }

    return produtos
        .map(
          (produto) => _ProdutoComSkus(
        produto: produto,
        skus: produto.id == null
            ? const <Sku>[]
            : List<Sku>.unmodifiable(
          skusPorProduto[produto.id!] ?? const <Sku>[],
        ),
      ),
    )
        .toList();
  }

  List<_ProdutoComSkus> _aplicarFiltros(
      List<_ProdutoComSkus> catalogo,
      ) {
    Iterable<_ProdutoComSkus> filtrados = catalogo;

    filtrados = switch (_filtro) {
      _FiltroProduto.todos => filtrados,
      _FiltroProduto.ativos => filtrados.where(
            (item) => item.skus.any((sku) => sku.status == SkuStatus.active),
      ),
      _FiltroProduto.inativos => filtrados.where(
            (item) => item.skus.isNotEmpty &&
            item.skus.every((sku) => sku.status != SkuStatus.active),
      ),
    };

    if (_busca.isNotEmpty) {
      final termo = _normalizar(_busca);
      final termoNumerico = _somenteNumeros(_busca);

      filtrados = filtrados.where((item) {
        final produto = item.produto;

        final correspondeAoProduto = [
          produto.descricao,
          produto.categoria,
          produto.modelo ?? '',
          produto.fabricante ?? '',
        ].any(
              (valor) => _normalizar(valor).contains(termo),
        );

        if (correspondeAoProduto) return true;

        return item.skus.any((sku) {
          final correspondeAoTexto = [
            sku.codigoInterno,
            sku.variacao ?? '',
            sku.codigoBarras ?? '',
          ].any(
                (valor) => _normalizar(valor).contains(termo),
          );

          final codigoBarras =
          _somenteNumeros(sku.codigoBarras ?? '');

          final correspondeAoCodigo =
              termoNumerico.isNotEmpty &&
                  codigoBarras.contains(termoNumerico);

          return correspondeAoTexto || correspondeAoCodigo;
        });
      });
    }

    final resultado = filtrados.toList();

    resultado.sort((a, b) {
      final descricaoA = _normalizar(a.produto.descricao);
      final descricaoB = _normalizar(b.produto.descricao);

      return switch (_ordenacao) {
        _OrdenacaoProduto.nomeAZ =>
            descricaoA.compareTo(descricaoB),
        _OrdenacaoProduto.nomeZA =>
            descricaoB.compareTo(descricaoA),
      };
    });

    return resultado;
  }

  Future<void> _recarregar() async {
    ref.invalidate(produtosListProvider);
    ref.invalidate(skusListProvider);

    await Future.wait<Object?>([
      ref.read(produtosListProvider.future),
      ref.read(skusListProvider.future),
    ]);
  }

  Future<void> _abrirNovoProduto() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ProdutoFormPage(),
      ),
    );

    if (!mounted) return;

    ref.invalidate(produtosListProvider);
    ref.invalidate(skusListProvider);
  }

  Future<Sku?> _escolherSku(
      _ProdutoComSkus item, {
        required String titulo,
        required String descricao,
      }) async {
    if (item.skus.isEmpty) return null;
    if (item.skus.length == 1) return item.skus.first;

    final largura = MediaQuery.sizeOf(context).width;

    if (largura >= 720) {
      return showDialog<Sku>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(titulo),
          contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
          content: SizedBox(
            width: 480,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: _SkuPickerList(
                produto: item.produto,
                skus: item.skus,
                descricao: descricao,
                onSelected: (sku) =>
                    Navigator.of(dialogContext).pop(sku),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      );
    }

    return showModalBottomSheet<Sku>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (bottomSheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
            MediaQuery.sizeOf(bottomSheetContext).height * 0.72,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  titulo,
                  style: Theme.of(bottomSheetContext)
                      .textTheme
                      .titleLarge
                      ?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: _SkuPickerList(
                    produto: item.produto,
                    skus: item.skus,
                    descricao: descricao,
                    onSelected: (sku) =>
                        Navigator.of(bottomSheetContext).pop(sku),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editarProduto(_ProdutoComSkus item) async {
    final produtoId = item.produto.id;

    if (produtoId == null || produtoId.isEmpty) {
      _mostrarMensagem(
        'Não foi possível editar este produto.',
        isError: true,
      );
      return;
    }

    if (item.skus.isEmpty) {
      _mostrarMensagem(
        'Este produto não possui SKU. Cadastre uma variação antes de editar.',
        isError: true,
      );
      return;
    }

    final sku = await _escolherSku(
      item,
      titulo: 'Editar produto',
      descricao:
      'Escolha qual SKU será carregado junto com os dados do produto.',
    );

    if (sku == null || !mounted) return;

    final skuId = sku.id;

    if (skuId == null || skuId.isEmpty) {
      _mostrarMensagem(
        'Não foi possível editar este SKU.',
        isError: true,
      );
      return;
    }

    setState(() => _produtoEmNavegacaoId = produtoId);

    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProdutoFormPage(
            produtoId: produtoId,
            skuId: skuId,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _produtoEmNavegacaoId = null);

        ref.invalidate(produtosListProvider);
        ref.invalidate(skusListProvider);
      }
    }
  }

  Future<void> _verSkus(_ProdutoComSkus item) async {
    final produtoId = item.produto.id;

    if (produtoId == null || produtoId.isEmpty) {
      _mostrarMensagem(
        'Não foi possível abrir este produto.',
        isError: true,
      );
      return;
    }

    if (item.skus.isEmpty) {
      _mostrarMensagem(
        'Este produto ainda não possui nenhum SKU cadastrado.',
      );
      return;
    }

    final sku = await _escolherSku(
      item,
      titulo: 'Detalhes',
      descricao: 'Escolha a variação que deseja consultar.',
    );

    if (sku == null || !mounted) return;

    final skuId = sku.id;

    if (skuId == null || skuId.isEmpty) {
      _mostrarMensagem(
        'Não foi possível abrir este SKU.',
        isError: true,
      );
      return;
    }

    setState(() => _produtoEmNavegacaoId = produtoId);

    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SkuDetailPage(
            skuId: skuId,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _produtoEmNavegacaoId = null);

        ref.invalidate(produtosListProvider);
        ref.invalidate(skusListProvider);
      }
    }
  }

  Future<void> _escanearCodigoDeBarras(List<Sku> skus) async {
    final codigo = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerPage(),
      ),
    );

    if (!mounted || codigo == null || codigo.trim().isEmpty) return;

    final codigoNormalizado = _normalizarGtin(codigo);

    Sku? skuEncontrado;
    for (final sku in skus) {
      final codigoSku = sku.codigoBarras?.trim();
      if (codigoSku == null || codigoSku.isEmpty) continue;

      if (_normalizarGtin(codigoSku) == codigoNormalizado) {
        skuEncontrado = sku;
        break;
      }
    }

    if (skuEncontrado == null) {
      _mostrarMensagem(
        'Nenhum produto encontrado para o código $codigoNormalizado.',
        isError: true,
      );
      return;
    }

    final skuId = skuEncontrado.id;
    if (skuId == null || skuId.isEmpty) {
      _mostrarMensagem(
        'O produto foi localizado, mas o SKU não possui um identificador válido.',
        isError: true,
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SkuDetailPage(skuId: skuId),
      ),
    );

    if (!mounted) return;
    ref.invalidate(produtosListProvider);
    ref.invalidate(skusListProvider);
  }

  void _mostrarMensagem(
      String mensagem, {
        bool isError = false,
      }) {
    if (!mounted) return;

    final colorScheme = Theme.of(context).colorScheme;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensagem),
          behavior: SnackBarBehavior.floating,
          backgroundColor:
          isError ? colorScheme.error : null,
        ),
      );
  }

  void _limparBusca() {
    _buscaController.clear();

    setState(() => _busca = '');

    _buscaFocusNode.requestFocus();
  }

  void _limparFiltros() {
    _buscaController.clear();

    setState(() {
      _busca = '';
      _filtro = _FiltroProduto.todos;
      _ordenacao = _OrdenacaoProduto.nomeAZ;
    });
  }

  @override
  Widget build(BuildContext context) {
    final produtosAsync =
    ref.watch(produtosListProvider);

    final skusAsync =
    ref.watch(skusListProvider);

    final largura =
        MediaQuery.sizeOf(context).width;

    final mostrarAcaoNoCabecalho =
        largura >= 700;

    final temProdutos =
        produtosAsync.value?.isNotEmpty == true;

    return Scaffold(
      floatingActionButton:
      !mostrarAcaoNoCabecalho && temProdutos
          ? FloatingActionButton.extended(
        heroTag: 'produtos_novo_fab',
        onPressed: _abrirNovoProduto,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Novo produto'),
      )
          : null,
      body: produtosAsync.when(
        data: (produtos) {
          if (produtos.isEmpty) {
            return _EmptyProdutosState(
              onCreate: _abrirNovoProduto,
            );
          }

          return skusAsync.when(
            data: (skus) => _buildCatalogo(
              context,
              produtos: produtos,
              skus: skus,
              mostrarAcaoNoCabecalho:
              mostrarAcaoNoCabecalho,
            ),
            loading: () =>
            const _ProdutosLoadingState(),
            error: (error, stack) {
              debugPrint(
                'Erro ao carregar SKUs da lista: '
                    '$error\n$stack',
              );

              return _ProdutosErrorState(
                onRetry: _recarregar,
              );
            },
          );
        },
        loading: () =>
        const _ProdutosLoadingState(),
        error: (error, stack) {
          debugPrint(
            'Erro ao carregar produtos: '
                '$error\n$stack',
          );

          return _ProdutosErrorState(
            onRetry: _recarregar,
          );
        },
      ),
    );
  }

  Widget _buildCatalogo(
      BuildContext context, {
        required List<Produto> produtos,
        required List<Sku> skus,
        required bool mostrarAcaoNoCabecalho,
      }) {
    final catalogo =
    _montarCatalogo(produtos, skus);

    final filtrados =
    _aplicarFiltros(catalogo);

    final contagens =
    _ContagensProdutos.from(catalogo);

    return SafeArea(
      child: ResponsiveCenter(
        maxWidth: 1180,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            16,
            16,
            16,
            0,
          ),
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.stretch,
            children: [
              _ProdutosSummary(
                totalProdutos: catalogo.length,
                totalExibido: filtrados.length,
                onCreate:
                mostrarAcaoNoCabecalho
                    ? _abrirNovoProduto
                    : null,
              ),
              const SizedBox(height: 20),
              _SearchAndSortBar(
                controller: _buscaController,
                focusNode: _buscaFocusNode,
                busca: _busca,
                ordenacao: _ordenacao,
                onBuscaChanged: (valor) {
                  setState(
                        () => _busca = valor.trim(),
                  );
                },
                onClearSearch: _limparBusca,
                onScanBarcode: () => _escanearCodigoDeBarras(skus),
                onOrdenacaoChanged: (ordenacao) {
                  setState(
                        () => _ordenacao = ordenacao,
                  );
                },
              ),
              const SizedBox(height: 12),
              _FiltrosProdutos(
                filtro: _filtro,
                contagens: contagens,
                totalExibido: filtrados.length,
                onChanged: (filtro) =>
                    setState(() => _filtro = filtro),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _recarregar,
                  child: filtrados.isEmpty
                      ? _FilteredEmptyState(
                    onClearFilters:
                    _limparFiltros,
                  )
                      : LayoutBuilder(
                    builder: (
                        context,
                        constraints,
                        ) {
                      if (constraints.maxWidth >=
                          940) {
                        return _DesktopProdutosTable(
                          itens: filtrados,
                          produtoEmNavegacaoId:
                          _produtoEmNavegacaoId,
                          onEditar:
                          _editarProduto,
                          onVerSkus:
                          _verSkus,
                        );
                      }

                      return _MobileProdutosList(
                        itens: filtrados,
                        produtoEmNavegacaoId:
                        _produtoEmNavegacaoId,
                        bottomPadding:
                        mostrarAcaoNoCabecalho
                            ? 24
                            : 96,
                        onEditar:
                        _editarProduto,
                        onVerSkus:
                        _verSkus,
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProdutosSummary extends StatelessWidget {
  final int totalProdutos;
  final int totalExibido;
  final VoidCallback? onCreate;

  const _ProdutosSummary({
    required this.totalProdutos,
    required this.totalExibido,
    this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final colorScheme =
        theme.colorScheme;

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(
              alpha: 0.14,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.inventory_2_outlined,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Text(
                '$totalProdutos '
                    '${totalProdutos == 1 ? 'produto cadastrado' : 'produtos cadastrados'}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                totalExibido == totalProdutos
                    ? 'Gerencie produtos, fotos e suas variações de SKU.'
                    : '$totalExibido '
                    '${totalExibido == 1 ? 'resultado encontrado' : 'resultados encontrados'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color:
                  colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (onCreate != null) ...[
          const SizedBox(width: 16),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Novo produto'),
          ),
        ],
      ],
    );
  }
}

class _SearchAndSortBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String busca;
  final _OrdenacaoProduto ordenacao;
  final ValueChanged<String> onBuscaChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onScanBarcode;
  final ValueChanged<_OrdenacaoProduto> onOrdenacaoChanged;

  const _SearchAndSortBar({
    required this.controller,
    required this.focusNode,
    required this.busca,
    required this.ordenacao,
    required this.onBuscaChanged,
    required this.onClearSearch,
    required this.onScanBarcode,
    required this.onOrdenacaoChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final buscaField = TextField(
          controller: controller,
          focusNode: focusNode,
          textInputAction: TextInputAction.search,
          onChanged: onBuscaChanged,
          decoration: InputDecoration(
            hintText: 'Buscar produto, modelo, SKU ou código de barras',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: busca.isNotEmpty
                ? IconButton(
              tooltip: 'Limpar busca',
              onPressed: onClearSearch,
              icon: const Icon(Icons.close_rounded),
            )
                : null,
          ),
        );

        final scannerButton = SizedBox(
          height: 48,
          child: FilledButton.tonalIcon(
            onPressed: onScanBarcode,
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: Text(constraints.maxWidth < 620 ? 'Escanear' : 'Ler código'),
          ),
        );

        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              buscaField,
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: scannerButton),
                  const SizedBox(width: 10),
                  _OrdenacaoButton(
                    ordenacao: ordenacao,
                    onChanged: onOrdenacaoChanged,
                  ),
                ],
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: buscaField),
            const SizedBox(width: 10),
            scannerButton,
            const SizedBox(width: 10),
            _OrdenacaoButton(
              ordenacao: ordenacao,
              onChanged: onOrdenacaoChanged,
            ),
          ],
        );
      },
    );
  }
}

class _OrdenacaoButton extends StatelessWidget {
  final _OrdenacaoProduto ordenacao;
  final ValueChanged<_OrdenacaoProduto>
  onChanged;

  const _OrdenacaoButton({
    required this.ordenacao,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final label = switch (ordenacao) {
      _OrdenacaoProduto.nomeAZ =>
      'Nome A–Z',
      _OrdenacaoProduto.nomeZA =>
      'Nome Z–A',
    };

    return PopupMenuButton<_OrdenacaoProduto>(
      initialValue: ordenacao,
      tooltip: 'Ordenar produtos',
      onSelected: onChanged,
      itemBuilder: (context) => const [
        PopupMenuItem(
          value:
          _OrdenacaoProduto.nomeAZ,
          child: Text('Nome A–Z'),
        ),
        PopupMenuItem(
          value:
          _OrdenacaoProduto.nomeZA,
          child: Text('Nome Z–A'),
        ),
      ],
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
        ),
        decoration: BoxDecoration(
          color:
          Theme.of(context).cardColor,
          border: Border.all(
            color: Theme.of(context)
                .colorScheme
                .outlineVariant,
          ),
          borderRadius:
          BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize:
          MainAxisSize.min,
          children: [
            const Icon(
              Icons.swap_vert_rounded,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(label),
            const SizedBox(width: 6),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _FiltrosProdutos extends StatelessWidget {
  final _FiltroProduto filtro;
  final _ContagensProdutos contagens;
  final int totalExibido;
  final ValueChanged<_FiltroProduto> onChanged;

  const _FiltrosProdutos({
    required this.filtro,
    required this.contagens,
    required this.totalExibido,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FiltroChip(
                  label: 'Todos',
                  quantidade: contagens.todos,
                  selecionado: filtro == _FiltroProduto.todos,
                  onTap: () => onChanged(_FiltroProduto.todos),
                ),
                const SizedBox(width: 8),
                _FiltroChip(
                  label: 'Ativos',
                  quantidade: contagens.ativos,
                  selecionado: filtro == _FiltroProduto.ativos,
                  onTap: () => onChanged(_FiltroProduto.ativos),
                ),
                const SizedBox(width: 8),
                _FiltroChip(
                  label: 'Inativos',
                  quantidade: contagens.inativos,
                  selecionado: filtro == _FiltroProduto.inativos,
                  onTap: () => onChanged(_FiltroProduto.inativos),
                ),
              ],
            ),
          ),
        ),
        if (MediaQuery.sizeOf(context).width >= 800) ...[
          const SizedBox(width: 16),
          Text(
            '$totalExibido ${totalExibido == 1 ? 'resultado' : 'resultados'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _FiltroChip extends StatelessWidget {
  final String label;
  final int quantidade;
  final bool selecionado;
  final VoidCallback onTap;

  const _FiltroChip({
    required this.label,
    required this.quantidade,
    required this.selecionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme =
        Theme.of(context).colorScheme;

    return ChoiceChip(
      selected: selecionado,
      onSelected: (_) => onTap(),
      side: BorderSide(
        color: selecionado
            ? colorScheme.primary.withValues(
          alpha: 0.72,
        )
            : colorScheme.outlineVariant,
      ),
      label: Row(
        mainAxisSize:
        MainAxisSize.min,
        children: [
          Text(label),
          const SizedBox(width: 8),
          Container(
            constraints:
            const BoxConstraints(
              minWidth: 24,
            ),
            padding:
            const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: selecionado
                  ? colorScheme.primary
                  .withValues(
                alpha: 0.18,
              )
                  : colorScheme
                  .surfaceContainerHighest,
              borderRadius:
              BorderRadius.circular(20),
            ),
            child: Text(
              '$quantidade',
              textAlign:
              TextAlign.center,
              style: TextStyle(
                color: selecionado
                    ? colorScheme.primary
                    : colorScheme
                    .onSurfaceVariant,
                fontSize: 11,
                fontWeight:
                FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopProdutosTable extends StatelessWidget {
  final List<_ProdutoComSkus> itens;
  final String? produtoEmNavegacaoId;
  final ValueChanged<_ProdutoComSkus>
  onEditar;
  final ValueChanged<_ProdutoComSkus>
  onVerSkus;

  const _DesktopProdutosTable({
    required this.itens,
    required this.produtoEmNavegacaoId,
    required this.onEditar,
    required this.onVerSkus,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final borderColor =
        theme.colorScheme.outlineVariant;

    return CustomScrollView(
      physics:
      const AlwaysScrollableScrollPhysics(),
      slivers: [
        const SliverToBoxAdapter(
          child: _DesktopTableHeader(),
        ),
        SliverList(
          delegate:
          SliverChildBuilderDelegate(
                (context, index) {
              final item =
              itens[index];

              final isLast =
                  index == itens.length - 1;

              return Container(
                clipBehavior:
                Clip.antiAlias,
                decoration:
                BoxDecoration(
                  color:
                  theme.cardColor,
                  border: Border(
                    left: BorderSide(
                      color:
                      borderColor,
                    ),
                    right: BorderSide(
                      color:
                      borderColor,
                    ),
                    bottom: BorderSide(
                      color:
                      borderColor,
                    ),
                  ),
                  borderRadius: isLast
                      ? const BorderRadius
                      .vertical(
                    bottom:
                    Radius.circular(
                      14,
                    ),
                  )
                      : null,
                ),
                child:
                _DesktopProdutoRow(
                  item: item,
                  carregando:
                  produtoEmNavegacaoId ==
                      item.produto.id,
                  onEditar: () =>
                      onEditar(item),
                  onVerSkus: () =>
                      onVerSkus(item),
                ),
              );
            },
            childCount: itens.length,
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding:
            const EdgeInsets.fromLTRB(
              4,
              12,
              4,
              24,
            ),
            child: Text(
              'Mostrando ${itens.length} '
                  '${itens.length == 1 ? 'produto' : 'produtos'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color:
                theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DesktopTableHeader extends StatelessWidget {
  const _DesktopTableHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final style =
    theme.textTheme.labelMedium?.copyWith(
      color:
      theme.colorScheme.onSurfaceVariant,
      fontWeight:
      FontWeight.w700,
    );

    return Container(
      height: 52,
      padding:
      const EdgeInsets.symmetric(
        horizontal: 16,
      ),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius:
        const BorderRadius.vertical(
          top: Radius.circular(14),
        ),
        border: Border.all(
          color:
          theme.colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              'Produto',
              style: style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Categoria',
              style: style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Modelo',
              style: style,
            ),
          ),
          SizedBox(
            width: 78,
            child: Text(
              'SKUs',
              style: style,
            ),
          ),
          SizedBox(
            width: 92,
            child: Text(
              'Status',
              style: style,
            ),
          ),
          SizedBox(
            width: 196,
            child: Text(
              'Ações',
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopProdutoRow extends StatefulWidget {
  final _ProdutoComSkus item;
  final bool carregando;
  final VoidCallback onEditar;
  final VoidCallback onVerSkus;

  const _DesktopProdutoRow({
    required this.item,
    required this.carregando,
    required this.onEditar,
    required this.onVerSkus,
  });

  @override
  State<_DesktopProdutoRow> createState() =>
      _DesktopProdutoRowState();
}

class _DesktopProdutoRowState
    extends State<_DesktopProdutoRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme =
    Theme.of(context);

    final colorScheme =
        theme.colorScheme;

    final item =
        widget.item;

    final produto =
        item.produto;

    return Semantics(
      button: true,
      label:
      'Ver detalhes do produto ${produto.descricao}',
      child: MouseRegion(
        cursor:
        SystemMouseCursors.click,
        onEnter: (_) =>
            setState(() => _hovered = true),
        onExit: (_) =>
            setState(() => _hovered = false),
        child: Material(
          color: _hovered
              ? colorScheme.primary.withValues(
            alpha: 0.04,
          )
              : Colors.transparent,
          child: InkWell(
            onTap: widget.carregando
                ? null
                : widget.onVerSkus,
            child: Padding(
              padding:
              const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Row(
                      children: [
                        _ProdutoPhoto(
                          fotoUrl:
                          produto.fotoUrl,
                          descricao:
                          produto.descricao,
                          size: 60,
                        ),
                        const SizedBox(
                          width: 12,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            children: [
                              Text(
                                produto.descricao,
                                maxLines: 2,
                                overflow:
                                TextOverflow.ellipsis,
                                style: theme
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                  fontWeight:
                                  FontWeight.w700,
                                ),
                              ),
                              const SizedBox(
                                height: 4,
                              ),
                              Text(
                                _codigoResumo(item),
                                maxLines: 1,
                                overflow:
                                TextOverflow.ellipsis,
                                style: theme
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                  color:
                                  colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(
                          width: 12,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      produto.categoria,
                      maxLines: 2,
                      overflow:
                      TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      _textoOuTraco(
                        produto.modelo,
                      ),
                      maxLines: 2,
                      overflow:
                      TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: 78,
                    child: _SkuCountBadge(
                      quantidade:
                      item.skus.length,
                    ),
                  ),
                  SizedBox(
                    width: 92,
                    child: _SkuStatusBadge(
                      skus: item.skus,
                    ),
                  ),
                  SizedBox(
                    width: 196,
                    child: widget.carregando
                        ? const Align(
                      alignment:
                      Alignment.centerLeft,
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child:
                        CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      ),
                    )
                        : Row(
                      children: [
                        OutlinedButton(
                          onPressed:
                          widget.onEditar,
                          child:
                          const Text(
                            'Editar',
                          ),
                        ),
                        const SizedBox(
                          width: 8,
                        ),
                        Expanded(
                          child:
                          OutlinedButton(
                            onPressed:
                            item.skus.isEmpty
                                ? null
                                : widget
                                .onVerSkus,
                            child:
                            const Text(
                              'Detalhes',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileProdutosList extends StatelessWidget {
  final List<_ProdutoComSkus> itens;
  final String? produtoEmNavegacaoId;
  final double bottomPadding;
  final ValueChanged<_ProdutoComSkus>
  onEditar;
  final ValueChanged<_ProdutoComSkus>
  onVerSkus;

  const _MobileProdutosList({
    required this.itens,
    required this.produtoEmNavegacaoId,
    required this.bottomPadding,
    required this.onEditar,
    required this.onVerSkus,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics:
      const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(
        bottom: bottomPadding,
      ),
      itemCount:
      itens.length,
      separatorBuilder: (_, __) =>
      const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item =
        itens[index];

        return _MobileProdutoCard(
          item: item,
          carregando:
          produtoEmNavegacaoId ==
              item.produto.id,
          onEditar: () =>
              onEditar(item),
          onVerSkus: () =>
              onVerSkus(item),
        );
      },
    );
  }
}

class _MobileProdutoCard extends StatelessWidget {
  final _ProdutoComSkus item;
  final bool carregando;
  final VoidCallback onEditar;
  final VoidCallback onVerSkus;

  const _MobileProdutoCard({
    required this.item,
    required this.carregando,
    required this.onEditar,
    required this.onVerSkus,
  });

  @override
  Widget build(BuildContext context) {
    final theme =
    Theme.of(context);

    final colorScheme =
        theme.colorScheme;

    final produto =
        item.produto;

    return Card(
      margin:
      EdgeInsets.zero,
      color:
      theme.cardColor,
      clipBehavior:
      Clip.antiAlias,
      shape:
      RoundedRectangleBorder(
        borderRadius:
        BorderRadius.circular(14),
        side: BorderSide(
          color:
          colorScheme.outlineVariant,
        ),
      ),
      child: InkWell(
        onTap:
        carregando ? null : onVerSkus,
        child: Padding(
          padding:
          const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  _ProdutoPhoto(
                    fotoUrl:
                    produto.fotoUrl,
                    descricao:
                    produto.descricao,
                    size: 76,
                  ),
                  const SizedBox(
                    width: 12,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Text(
                          produto.descricao,
                          maxLines: 2,
                          overflow:
                          TextOverflow.ellipsis,
                          style: theme
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                            fontWeight:
                            FontWeight.w800,
                          ),
                        ),
                        const SizedBox(
                          height: 5,
                        ),
                        Text(
                          [
                            produto.categoria,
                            if (produto.modelo
                                ?.trim()
                                .isNotEmpty ==
                                true)
                              produto.modelo!
                                  .trim(),
                          ].join(' · '),
                          maxLines: 2,
                          overflow:
                          TextOverflow.ellipsis,
                          style: theme
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                            color:
                            colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(
                          height: 9,
                        ),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _SkuCountBadge(
                              quantidade:
                              item.skus.length,
                            ),
                            _SkuStatusBadge(
                              skus:
                              item.skus,
                            ),
                            if (!_temFoto(produto))
                              const _SemFotoBadge(),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(
                height: 14,
              ),
              if (carregando)
                const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child:
                    CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child:
                      OutlinedButton.icon(
                        onPressed:
                        onEditar,
                        icon:
                        const Icon(
                          Icons.edit_outlined,
                          size: 18,
                        ),
                        label:
                        const Text(
                          'Editar',
                        ),
                      ),
                    ),
                    const SizedBox(
                      width: 10,
                    ),
                    Expanded(
                      child:
                      FilledButton.tonalIcon(
                        onPressed:
                        item.skus.isEmpty
                            ? null
                            : onVerSkus,
                        icon:
                        const Icon(
                          Icons.view_list_outlined,
                          size: 18,
                        ),
                        label:
                        const Text(
                          'Detalhes',
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProdutoPhoto extends StatelessWidget {
  final String? fotoUrl;
  final String descricao;
  final double size;

  const _ProdutoPhoto({
    required this.fotoUrl,
    required this.descricao,
    required this.size,
  });

  bool get _hasPhoto =>
      fotoUrl?.trim().isNotEmpty == true;

  @override
  Widget build(BuildContext context) {
    final theme =
    Theme.of(context);

    final colorScheme =
        theme.colorScheme;

    final placeholder =
    Center(
      child: Icon(
        Icons.inventory_2_outlined,
        size: size * 0.4,
        color:
        colorScheme.onSurfaceVariant,
      ),
    );

    return Semantics(
      image:
      _hasPhoto,
      label: _hasPhoto
          ? 'Foto de $descricao'
          : '$descricao sem foto',
      child: Material(
        color:
        colorScheme
            .surfaceContainerHighest,
        borderRadius:
        BorderRadius.circular(12),
        clipBehavior:
        Clip.antiAlias,
        child: InkWell(
          onTap: _hasPhoto
              ? () => _ampliarFoto(context)
              : null,
          child: SizedBox(
            width: size,
            height: size,
            child: _hasPhoto
                ? Image.network(
              fotoUrl!.trim(),
              fit: BoxFit.contain,
              frameBuilder: (
                  context,
                  child,
                  frame,
                  syncLoaded,
                  ) {
                if (syncLoaded ||
                    frame != null) {
                  return child;
                }

                return Center(
                  child:
                  SizedBox(
                    width:
                    size * 0.28,
                    height:
                    size * 0.28,
                    child:
                    const CircularProgressIndicator(
                      strokeWidth:
                      2,
                    ),
                  ),
                );
              },
              errorBuilder:
                  (_, __, ___) =>
              placeholder,
            )
                : placeholder,
          ),
        ),
      ),
    );
  }

  Future<void> _ampliarFoto(
      BuildContext context,
      ) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) =>
          Dialog(
            child:
            ConstrainedBox(
              constraints:
              const BoxConstraints(
                maxWidth: 560,
                maxHeight: 620,
              ),
              child: Padding(
                padding:
                const EdgeInsets.all(
                  16,
                ),
                child: Column(
                  mainAxisSize:
                  MainAxisSize.min,
                  crossAxisAlignment:
                  CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            descricao,
                            maxLines: 2,
                            overflow:
                            TextOverflow.ellipsis,
                            style: Theme.of(
                              dialogContext,
                            ).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          tooltip:
                          'Fechar',
                          onPressed: () =>
                              Navigator.of(
                                dialogContext,
                              ).pop(),
                          icon:
                          const Icon(
                            Icons.close_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(
                      height: 12,
                    ),
                    Flexible(
                      child:
                      InteractiveViewer(
                        minScale: 0.8,
                        maxScale: 4,
                        child:
                        Image.network(
                          fotoUrl!.trim(),
                          fit:
                          BoxFit.contain,
                          errorBuilder:
                              (_, __, ___) =>
                          const Center(
                            child: Text(
                              'Não foi possível carregar a foto.',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }
}

class _SkuPickerList extends StatelessWidget {
  final Produto produto;
  final List<Sku> skus;
  final String descricao;
  final ValueChanged<Sku> onSelected;

  const _SkuPickerList({
    required this.produto,
    required this.skus,
    required this.descricao,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme =
    Theme.of(context);

    return Column(
      mainAxisSize:
      MainAxisSize.min,
      crossAxisAlignment:
      CrossAxisAlignment.stretch,
      children: [
        Text(
          produto.descricao,
          maxLines: 2,
          overflow:
          TextOverflow.ellipsis,
          style:
          theme.textTheme.titleSmall?.copyWith(
            fontWeight:
            FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          descricao,
          style:
          theme.textTheme.bodySmall?.copyWith(
            color:
            theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount:
            skus.length,
            separatorBuilder:
                (_, __) =>
            const Divider(height: 1),
            itemBuilder: (
                context,
                index,
                ) {
              final sku =
              skus[index];

              final variacao =
              sku.variacao?.trim();

              return ListTile(
                contentPadding:
                EdgeInsets.zero,
                leading:
                CircleAvatar(
                  child:
                  Text('${index + 1}'),
                ),
                title: Text(
                  variacao?.isNotEmpty ==
                      true
                      ? variacao!
                      : sku.codigoInterno,
                ),
                subtitle: Text(
                  [
                    sku.codigoInterno,
                    if (sku.codigoBarras
                        ?.trim()
                        .isNotEmpty ==
                        true)
                      'EAN ${sku.codigoBarras!.trim()}',
                  ].join(' · '),
                ),
                trailing:
                const Icon(
                  Icons.chevron_right_rounded,
                ),
                onTap: () =>
                    onSelected(sku),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SkuCountBadge extends StatelessWidget {
  final int quantidade;

  const _SkuCountBadge({
    required this.quantidade,
  });

  @override
  Widget build(BuildContext context) {
    final theme =
    Theme.of(context);

    final colorScheme =
        theme.colorScheme;

    final semSku =
        quantidade == 0;

    final color =
    semSku
        ? Colors.orange
        : colorScheme
        .onSurfaceVariant;

    final label =
    quantidade == 0
        ? 'Sem SKU'
        : '$quantidade '
        '${quantidade == 1 ? 'SKU' : 'SKUs'}';

    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration:
      BoxDecoration(
        color:
        color.withValues(
          alpha: 0.11,
        ),
        borderRadius:
        BorderRadius.circular(7),
        border:
        Border.all(
          color:
          color.withValues(
            alpha: 0.32,
          ),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow:
        TextOverflow.ellipsis,
        textAlign:
        TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight:
          FontWeight.w700,
        ),
      ),
    );
  }
}

class _SkuStatusBadge extends StatelessWidget {
  final List<Sku> skus;

  const _SkuStatusBadge({
    required this.skus,
  });

  @override
  Widget build(BuildContext context) {
    final ativos = skus
        .where(
          (sku) =>
      sku.status ==
          SkuStatus.active,
    )
        .length;

    late final String label;
    late final Color color;

    if (skus.isEmpty) {
      label = 'Pendente';
      color = Colors.orange;
    } else if (ativos ==
        skus.length) {
      label = 'Ativo';
      color = Colors.green;
    } else if (ativos == 0) {
      label = 'Inativo';
      color = Colors.grey;
    } else {
      label = 'Parcial';
      color = Colors.orange;
    }

    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration:
      BoxDecoration(
        color:
        color.withValues(
          alpha: 0.12,
        ),
        borderRadius:
        BorderRadius.circular(7),
        border:
        Border.all(
          color:
          color.withValues(
            alpha: 0.38,
          ),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow:
        TextOverflow.ellipsis,
        textAlign:
        TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight:
          FontWeight.w700,
        ),
      ),
    );
  }
}

class _SemFotoBadge extends StatelessWidget {
  const _SemFotoBadge();

  @override
  Widget build(BuildContext context) {
    final color =
        Theme.of(context)
            .colorScheme
            .onSurfaceVariant;

    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration:
      BoxDecoration(
        color:
        color.withValues(
          alpha: 0.1,
        ),
        borderRadius:
        BorderRadius.circular(7),
        border:
        Border.all(
          color:
          color.withValues(
            alpha: 0.3,
          ),
        ),
      ),
      child: Text(
        'Sem foto',
        style:
        TextStyle(
          color: color,
          fontSize: 11,
          fontWeight:
          FontWeight.w700,
        ),
      ),
    );
  }
}

class _FilteredEmptyState extends StatelessWidget {
  final VoidCallback onClearFilters;

  const _FilteredEmptyState({
    required this.onClearFilters,
  });

  @override
  Widget build(BuildContext context) {
    final theme =
    Theme.of(context);

    return ListView(
      physics:
      const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: 360,
          child: Center(
            child:
            ConstrainedBox(
              constraints:
              const BoxConstraints(
                maxWidth: 390,
              ),
              child: Column(
                mainAxisSize:
                MainAxisSize.min,
                children: [
                  const _StateIcon(
                    icon:
                    Icons.search_off_rounded,
                  ),
                  const SizedBox(
                    height: 16,
                  ),
                  Text(
                    'Nenhum produto encontrado',
                    textAlign:
                    TextAlign.center,
                    style: theme
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                      fontWeight:
                      FontWeight.w800,
                    ),
                  ),
                  const SizedBox(
                    height: 6,
                  ),
                  Text(
                    'Tente outra descrição, modelo, SKU, '
                        'código de barras ou remova os filtros.',
                    textAlign:
                    TextAlign.center,
                    style: theme
                        .textTheme
                        .bodyMedium
                        ?.copyWith(
                      color:
                      theme
                          .colorScheme
                          .onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(
                    height: 18,
                  ),
                  OutlinedButton.icon(
                    onPressed:
                    onClearFilters,
                    icon:
                    const Icon(
                      Icons.filter_alt_off_outlined,
                    ),
                    label:
                    const Text(
                      'Limpar filtros',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyProdutosState extends StatelessWidget {
  final VoidCallback onCreate;

  const _EmptyProdutosState({
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    final theme =
    Theme.of(context);

    return SafeArea(
      child: Center(
        child: Padding(
          padding:
          const EdgeInsets.all(
            24,
          ),
          child:
          ConstrainedBox(
            constraints:
            const BoxConstraints(
              maxWidth: 430,
            ),
            child: Column(
              mainAxisSize:
              MainAxisSize.min,
              children: [
                const _StateIcon(
                  icon:
                  Icons.add_box_outlined,
                ),
                const SizedBox(
                  height: 18,
                ),
                Text(
                  'Cadastre seu primeiro produto',
                  textAlign:
                  TextAlign.center,
                  style: theme
                      .textTheme
                      .titleLarge
                      ?.copyWith(
                    fontWeight:
                    FontWeight.w800,
                  ),
                ),
                const SizedBox(
                  height: 8,
                ),
                Text(
                  'O cadastro cria o produto e seu primeiro SKU, '
                      'com foto, preço e código de barras.',
                  textAlign:
                  TextAlign.center,
                  style: theme
                      .textTheme
                      .bodyMedium
                      ?.copyWith(
                    color:
                    theme
                        .colorScheme
                        .onSurfaceVariant,
                  ),
                ),
                const SizedBox(
                  height: 22,
                ),
                FilledButton.icon(
                  onPressed:
                  onCreate,
                  icon:
                  const Icon(
                    Icons.add_rounded,
                  ),
                  label:
                  const Text(
                    'Novo produto',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProdutosLoadingState extends StatelessWidget {
  const _ProdutosLoadingState();

  @override
  Widget build(BuildContext context) {
    final theme =
    Theme.of(context);

    final colorScheme =
        theme.colorScheme;

    return SafeArea(
      child: ResponsiveCenter(
        maxWidth: 1180,
        child: ListView(
          padding:
          const EdgeInsets.all(16),
          children: [
            Container(
              height: 58,
              decoration:
              BoxDecoration(
                color:
                theme.cardColor,
                borderRadius:
                BorderRadius.circular(
                  14,
                ),
              ),
            ),
            const SizedBox(
              height: 16,
            ),
            Container(
              height: 50,
              decoration:
              BoxDecoration(
                color:
                theme.cardColor,
                borderRadius:
                BorderRadius.circular(
                  12,
                ),
              ),
            ),
            const SizedBox(
              height: 16,
            ),
            for (var index = 0;
            index < 5;
            index++) ...[
              Container(
                height: 88,
                decoration:
                BoxDecoration(
                  color:
                  theme.cardColor,
                  borderRadius:
                  BorderRadius.circular(
                    12,
                  ),
                  border:
                  Border.all(
                    color:
                    colorScheme
                        .outlineVariant,
                  ),
                ),
              ),
              const SizedBox(
                height: 10,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProdutosErrorState extends StatelessWidget {
  final Future<void> Function() onRetry;

  const _ProdutosErrorState({
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme =
    Theme.of(context);

    return SafeArea(
      child: Center(
        child: Padding(
          padding:
          const EdgeInsets.all(
            24,
          ),
          child:
          ConstrainedBox(
            constraints:
            const BoxConstraints(
              maxWidth: 420,
            ),
            child: Column(
              mainAxisSize:
              MainAxisSize.min,
              children: [
                const _StateIcon(
                  icon:
                  Icons.cloud_off_rounded,
                  color:
                  Colors.orange,
                ),
                const SizedBox(
                  height: 18,
                ),
                Text(
                  'Não foi possível carregar os produtos',
                  textAlign:
                  TextAlign.center,
                  style: theme
                      .textTheme
                      .titleMedium
                      ?.copyWith(
                    fontWeight:
                    FontWeight.w800,
                  ),
                ),
                const SizedBox(
                  height: 8,
                ),
                Text(
                  'Verifique sua conexão e tente novamente.',
                  textAlign:
                  TextAlign.center,
                  style: theme
                      .textTheme
                      .bodyMedium
                      ?.copyWith(
                    color:
                    theme
                        .colorScheme
                        .onSurfaceVariant,
                  ),
                ),
                const SizedBox(
                  height: 20,
                ),
                FilledButton.tonalIcon(
                  onPressed:
                  onRetry,
                  icon:
                  const Icon(
                    Icons.refresh_rounded,
                  ),
                  label:
                  const Text(
                    'Tentar novamente',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StateIcon extends StatelessWidget {
  final IconData icon;
  final Color? color;

  const _StateIcon({
    required this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        color ??
            Theme.of(context)
                .colorScheme
                .primary;

    return Container(
      width: 72,
      height: 72,
      decoration:
      BoxDecoration(
        color:
        effectiveColor.withValues(
          alpha: 0.12,
        ),
        shape:
        BoxShape.circle,
      ),
      child: Icon(
        icon,
        size: 34,
        color:
        effectiveColor,
      ),
    );
  }
}

class _ProdutoComSkus {
  final Produto produto;
  final List<Sku> skus;

  const _ProdutoComSkus({
    required this.produto,
    required this.skus,
  });
}

class _ContagensProdutos {
  final int todos;
  final int ativos;
  final int inativos;

  const _ContagensProdutos({
    required this.todos,
    required this.ativos,
    required this.inativos,
  });

  factory _ContagensProdutos.from(List<_ProdutoComSkus> catalogo) {
    return _ContagensProdutos(
      todos: catalogo.length,
      ativos: catalogo
          .where((item) =>
          item.skus.any((sku) => sku.status == SkuStatus.active))
          .length,
      inativos: catalogo
          .where((item) =>
      item.skus.isNotEmpty &&
          item.skus.every((sku) => sku.status != SkuStatus.active))
          .length,
    );
  }
}

bool _temFoto(
    Produto produto,
    ) {
  return produto.fotoUrl
      ?.trim()
      .isNotEmpty ==
      true;
}

String _textoOuTraco(
    String? valor,
    ) {
  final texto =
  valor?.trim();

  return texto?.isNotEmpty ==
      true
      ? texto!
      : '—';
}

String _codigoResumo(
    _ProdutoComSkus item,
    ) {
  if (item.skus.isEmpty) {
    return 'Nenhum SKU cadastrado';
  }

  final primeiroSku = item.skus.first;
  final codigoInterno = primeiroSku.codigoInterno;
  final ean = primeiroSku.codigoBarras?.trim();

  if (item.skus.length == 1) {
    if (ean != null && ean.isNotEmpty) {
      return 'SKU $codigoInterno · EAN $ean';
    }
    return 'SKU $codigoInterno';
  }

  return 'SKU $codigoInterno +${item.skus.length - 1} variações';
}

String _normalizarGtin(String valor) {
  final codigo = _somenteNumeros(valor);
  if (codigo.length == 12) return '0$codigo';
  return codigo;
}

String _normalizar(
    String valor,
    ) {
  return valor
      .trim()
      .toLowerCase();
}

String _somenteNumeros(
    String valor,
    ) {
  return valor.replaceAll(
    RegExp(r'[^0-9]'),
    '',
  );
}
