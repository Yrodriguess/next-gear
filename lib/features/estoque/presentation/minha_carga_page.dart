import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/money_input_formatter.dart';
import '../../../core/widgets/barcode_scanner_page.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../produtos/presentation/produto_providers.dart';
import '../../produtos/presentation/sku_detail_page.dart';
import '../domain/stock_movement.dart';
import 'estoque_providers.dart';

const double _kBreakpointTabela = 820;
const double _kMaxWidthConteudo = 1200;

enum _OrdenacaoCarga {
  nomeAZ,
  maiorQuantidade,
  menorQuantidade,
}

/// O que o vendedor tem consigo agora (carga do dia).
///
/// A tela usa exatamente os mesmos saldos do estoque. Ela apenas filtra o local
/// do vendedor autenticado e apresenta os dados de forma otimizada para web e
/// mobile.
class MinhaCargaPage extends ConsumerStatefulWidget {
  const MinhaCargaPage({super.key});

  @override
  ConsumerState<MinhaCargaPage> createState() => _MinhaCargaPageState();
}

class _MinhaCargaPageState extends ConsumerState<MinhaCargaPage> {
  final _buscaController = TextEditingController();

  String _termoBusca = '';
  _OrdenacaoCarga _ordenacao = _OrdenacaoCarga.nomeAZ;

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  Future<void> _escanearCodigo() async {
    final codigo = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );

    if (codigo == null || !mounted) return;

    final codigoLimpo = codigo.trim();
    setState(() {
      _buscaController.text = codigoLimpo;
      _buscaController.selection = TextSelection.collapsed(
        offset: codigoLimpo.length,
      );
      _termoBusca = codigoLimpo;
    });
  }

  Future<void> _atualizar({
    required String orgId,
    required String localId,
  }) async {
    ref.invalidate(
      saldosDoLocalProvider((orgId: orgId, localId: localId)),
    );
    ref.invalidate(skusListProvider);
    ref.invalidate(produtosListProvider);

    // Dá tempo para os providers iniciarem uma nova leitura. O conteúdo não é
    // apagado durante a atualização, evitando piscar a tela no mobile.
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  void _limparBusca() {
    setState(() {
      _buscaController.clear();
      _termoBusca = '';
    });
  }

  void _abrirSku(_ItemCarga item) {
    final skuId = item.skuId;
    if (skuId == null || skuId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível identificar o SKU deste item.'),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SkuDetailPage(skuId: skuId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final usuarioAsync = ref.watch(appUserProvider);

    if (usuarioAsync.isLoading && usuarioAsync.value == null) {
      return const _EstadoCarregandoScaffold(titulo: 'Minha carga');
    }

    if (usuarioAsync.hasError) {
      return _EstadoErroScaffold(
        titulo: 'Minha carga',
        mensagem: 'Não foi possível carregar os dados do usuário.',
        onTentarNovamente: () => ref.invalidate(appUserProvider),
      );
    }

    final usuario = usuarioAsync.value;
    if (usuario == null) {
      return const _SessaoInvalidaScaffold();
    }

    final localId = LocalEstoque.vendedor(usuario.uid);
    final saldosProvider = saldosDoLocalProvider(
      (orgId: usuario.orgId, localId: localId),
    );
    final saldosAsync = ref.watch(saldosProvider);
    final skusAsync = ref.watch(skusListProvider);
    final produtosAsync = ref.watch(produtosListProvider);

    final primeiraCarga = saldosAsync.value == null ||
        skusAsync.value == null ||
        produtosAsync.value == null;
    final carregando = saldosAsync.isLoading ||
        skusAsync.isLoading ||
        produtosAsync.isLoading;

    if (carregando && primeiraCarga) {
      return const _EstadoCarregandoScaffold(titulo: 'Minha carga');
    }

    if (saldosAsync.hasError || skusAsync.hasError || produtosAsync.hasError) {
      return _EstadoErroScaffold(
        titulo: 'Minha carga',
        mensagem: 'Não foi possível carregar os produtos da sua carga.',
        onTentarNovamente: () {
          ref.invalidate(saldosProvider);
          ref.invalidate(skusListProvider);
          ref.invalidate(produtosListProvider);
        },
      );
    }

    final saldos = saldosAsync.value ?? const [];
    final skus = skusAsync.value ?? const [];
    final produtos = produtosAsync.value ?? const [];

    // Os mapas evitam procurar o mesmo SKU e produto em toda a lista para cada
    // saldo. Isso mantém a tela rápida mesmo quando a carga crescer.
    final skusPorId = {
      for (final sku in skus)
        if (sku.id != null) sku.id!: sku,
    };
    final produtosPorId = {
      for (final produto in produtos)
        if (produto.id != null) produto.id!: produto,
    };

    final itens = <_ItemCarga>[];
    for (final saldo in saldos) {
      if (saldo.quantidade <= 0) continue;

      // saldo.produtoId contém o ID do SKU, conforme o modelo atual de estoque.
      final sku = skusPorId[saldo.produtoId];
      final produto = sku == null ? null : produtosPorId[sku.produtoId];
      final variacao = sku?.variacao?.trim();
      final descricaoProduto = produto?.descricao.trim();
      final descricao = descricaoProduto == null || descricaoProduto.isEmpty
          ? 'Produto não identificado'
          : variacao != null && variacao.isNotEmpty
          ? '$descricaoProduto — $variacao'
          : descricaoProduto;

      itens.add(
        _ItemCarga(
          skuId: sku?.id,
          descricao: descricao,
          codigoInterno: sku?.codigoInterno ?? 'SKU não identificado',
          codigoBarras: sku?.codigoBarras,
          categoria: produto?.categoria ?? 'Sem categoria',
          fotoUrl: produto?.fotoUrl,
          quantidade: saldo.quantidade,
          precoVendaCentavos: sku?.precoVendaCentavos ?? 0,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Minha carga'),
        actions: [
          IconButton(
            tooltip: 'Escanear produto',
            onPressed: _escanearCodigo,
            icon: const Icon(Icons.qr_code_scanner_rounded),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: carregando
                ? null
                : () {
              _atualizar(orgId: usuario.orgId, localId: localId);
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildConteudo(
        context,
        itens: itens,
        atualizando: carregando,
        onAtualizar: () => _atualizar(
          orgId: usuario.orgId,
          localId: localId,
        ),
      ),
    );
  }

  Widget _buildConteudo(
      BuildContext context, {
        required List<_ItemCarga> itens,
        required bool atualizando,
        required Future<void> Function() onAtualizar,
      }) {
    final termo = _termoBusca.trim().toLowerCase();
    final filtrados = itens.where((item) {
      if (termo.isEmpty) return true;
      return item.descricao.toLowerCase().contains(termo) ||
          item.codigoInterno.toLowerCase().contains(termo) ||
          (item.codigoBarras?.toLowerCase().contains(termo) ?? false) ||
          item.categoria.toLowerCase().contains(termo);
    }).toList();

    switch (_ordenacao) {
      case _OrdenacaoCarga.nomeAZ:
        filtrados.sort(
              (a, b) => a.descricao.toLowerCase().compareTo(
            b.descricao.toLowerCase(),
          ),
        );
        break;
      case _OrdenacaoCarga.maiorQuantidade:
        filtrados.sort((a, b) => b.quantidade.compareTo(a.quantidade));
        break;
      case _OrdenacaoCarga.menorQuantidade:
        filtrados.sort((a, b) => a.quantidade.compareTo(b.quantidade));
        break;
    }

    final totalUnidades = itens.fold<int>(
      0,
          (total, item) => total + item.quantidade,
    );
    final valorPotencial = itens.fold<int>(
      0,
          (total, item) => total + item.valorPotencialCentavos,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final usarTabela = constraints.maxWidth >= _kBreakpointTabela;

        return RefreshIndicator(
          onRefresh: onAtualizar,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ResponsiveCenter(
              maxWidth: _kMaxWidthConteudo,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _CabecalhoCarga(
                      atualizando: atualizando,
                      onEscanear: _escanearCodigo,
                    ),
                    const SizedBox(height: 20),
                    _ResumoCarga(
                      quantidadeSkus: itens.length,
                      totalUnidades: totalUnidades,
                      valorPotencialCentavos: valorPotencial,
                    ),
                    const SizedBox(height: 16),
                    _BarraBuscaCarga(
                      controller: _buscaController,
                      ordenacao: _ordenacao,
                      quantidadeResultados: filtrados.length,
                      onChanged: (value) {
                        setState(() => _termoBusca = value);
                      },
                      onLimpar: _limparBusca,
                      onEscanear: _escanearCodigo,
                      onOrdenacaoChanged: (value) {
                        if (value == null) return;
                        setState(() => _ordenacao = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    if (itens.isEmpty)
                      _CargaVazia(onAtualizar: onAtualizar)
                    else if (filtrados.isEmpty)
                      _NenhumResultado(onLimpar: _limparBusca)
                    else if (usarTabela)
                        _TabelaCarga(
                          itens: filtrados,
                          onAbrir: _abrirSku,
                        )
                      else
                        _ListaCargaMobile(
                          itens: filtrados,
                          onAbrir: _abrirSku,
                        ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ItemCarga {
  final String? skuId;
  final String descricao;
  final String codigoInterno;
  final String? codigoBarras;
  final String categoria;
  final String? fotoUrl;
  final int quantidade;
  final int precoVendaCentavos;

  const _ItemCarga({
    required this.skuId,
    required this.descricao,
    required this.codigoInterno,
    required this.codigoBarras,
    required this.categoria,
    required this.fotoUrl,
    required this.quantidade,
    required this.precoVendaCentavos,
  });

  int get valorPotencialCentavos => quantidade * precoVendaCentavos;
}

class _CabecalhoCarga extends StatelessWidget {
  final bool atualizando;
  final VoidCallback onEscanear;

  const _CabecalhoCarga({
    required this.atualizando,
    required this.onEscanear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compacto = constraints.maxWidth < 600;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Produtos disponíveis com você',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Consulte rapidamente os itens disponíveis para instalações e reposições.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            if (!compacto) ...[
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: atualizando ? null : onEscanear,
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Escanear produto'),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ResumoCarga extends StatelessWidget {
  final int quantidadeSkus;
  final int totalUnidades;
  final int valorPotencialCentavos;

  const _ResumoCarga({
    required this.quantidadeSkus,
    required this.totalUnidades,
    required this.valorPotencialCentavos,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compacto = constraints.maxWidth < 580;
        final largura = compacto
            ? (constraints.maxWidth - 12) / 2
            : (constraints.maxWidth - 24) / 3;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: largura,
              child: _ResumoCard(
                icon: Icons.inventory_2_outlined,
                valor: '$quantidadeSkus',
                label: quantidadeSkus == 1 ? 'SKU' : 'SKUs',
              ),
            ),
            SizedBox(
              width: largura,
              child: _ResumoCard(
                icon: Icons.widgets_outlined,
                valor: '$totalUnidades',
                label: totalUnidades == 1 ? 'unidade' : 'unidades',
              ),
            ),
            SizedBox(
              width: compacto ? constraints.maxWidth : largura,
              child: _ResumoCard(
                icon: Icons.payments_outlined,
                valor: formatarCentavos(valorPotencialCentavos),
                label: 'venda potencial',
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ResumoCard extends StatelessWidget {
  final IconData icon;
  final String valor;
  final String label;

  const _ResumoCard({
    required this.icon,
    required this.valor,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: theme.colorScheme.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    valor,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(label, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarraBuscaCarga extends StatelessWidget {
  final TextEditingController controller;
  final _OrdenacaoCarga ordenacao;
  final int quantidadeResultados;
  final ValueChanged<String> onChanged;
  final VoidCallback onLimpar;
  final VoidCallback onEscanear;
  final ValueChanged<_OrdenacaoCarga?> onOrdenacaoChanged;

  const _BarraBuscaCarga({
    required this.controller,
    required this.ordenacao,
    required this.quantidadeResultados,
    required this.onChanged,
    required this.onLimpar,
    required this.onEscanear,
    required this.onOrdenacaoChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compacto = constraints.maxWidth < 700;
        final busca = TextField(
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Buscar produto, SKU ou código de barras',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: controller.text.isNotEmpty
                ? IconButton(
              tooltip: 'Limpar busca',
              onPressed: onLimpar,
              icon: const Icon(Icons.close),
            )
                : IconButton(
              tooltip: 'Escanear produto',
              onPressed: onEscanear,
              icon: const Icon(Icons.qr_code_scanner_rounded),
            ),
          ),
        );
        final ordenacaoField = DropdownButtonFormField<_OrdenacaoCarga>(
          initialValue: ordenacao,
          isExpanded: true,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.sort_rounded),
          ),
          items: const [
            DropdownMenuItem(
              value: _OrdenacaoCarga.nomeAZ,
              child: Text('Nome A–Z'),
            ),
            DropdownMenuItem(
              value: _OrdenacaoCarga.maiorQuantidade,
              child: Text('Maior quantidade'),
            ),
            DropdownMenuItem(
              value: _OrdenacaoCarga.menorQuantidade,
              child: Text('Menor quantidade'),
            ),
          ],
          onChanged: onOrdenacaoChanged,
        );

        if (compacto) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              busca,
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: ordenacaoField),
                  const SizedBox(width: 12),
                  Text(
                    '$quantidadeResultados resultado(s)',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: busca),
            const SizedBox(width: 12),
            SizedBox(width: 220, child: ordenacaoField),
            const SizedBox(width: 16),
            Text(
              '$quantidadeResultados resultado(s)',
              style: theme.textTheme.bodySmall,
            ),
          ],
        );
      },
    );
  }
}

class _TabelaCarga extends StatelessWidget {
  final List<_ItemCarga> itens;
  final ValueChanged<_ItemCarga> onAbrir;

  const _TabelaCarga({required this.itens, required this.onAbrir});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const _CabecalhoTabela(),
          for (var i = 0; i < itens.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _LinhaTabela(
              item: itens[i],
              onTap: () => onAbrir(itens[i]),
            ),
          ],
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
      fontWeight: FontWeight.w700,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(flex: 34, child: Text('Produto', style: style)),
          Expanded(flex: 16, child: Text('SKU', style: style)),
          Expanded(flex: 16, child: Text('Categoria', style: style)),
          Expanded(
            flex: 12,
            child: Text('Quantidade', textAlign: TextAlign.center, style: style),
          ),
          Expanded(
            flex: 11,
            child: Text('Preço', textAlign: TextAlign.end, style: style),
          ),
          Expanded(
            flex: 16,
            child: Text(
              'Venda potencial',
              textAlign: TextAlign.end,
              style: style,
            ),
          ),
          const SizedBox(width: 32),
        ],
      ),
    );
  }
}

class _LinhaTabela extends StatelessWidget {
  final _ItemCarga item;
  final VoidCallback onTap;

  const _LinhaTabela({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              flex: 34,
              child: Row(
                children: [
                  _ProdutoImagem(url: item.fotoUrl, tamanho: 52),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.descricao,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 16,
              child: Text(
                item.codigoInterno,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
            Expanded(
              flex: 16,
              child: Text(
                item.categoria,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
            Expanded(
              flex: 12,
              child: Center(child: _QuantidadeBadge(valor: item.quantidade)),
            ),
            Expanded(
              flex: 11,
              child: Text(
                formatarCentavos(item.precoVendaCentavos),
                textAlign: TextAlign.end,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Expanded(
              flex: 16,
              child: Text(
                formatarCentavos(item.valorPotencialCentavos),
                textAlign: TextAlign.end,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _ListaCargaMobile extends StatelessWidget {
  final List<_ItemCarga> itens;
  final ValueChanged<_ItemCarga> onAbrir;

  const _ListaCargaMobile({required this.itens, required this.onAbrir});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < itens.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _ItemCargaCard(
            item: itens[i],
            onTap: () => onAbrir(itens[i]),
          ),
        ],
      ],
    );
  }
}

class _ItemCargaCard extends StatelessWidget {
  final _ItemCarga item;
  final VoidCallback onTap;

  const _ItemCargaCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _ProdutoImagem(url: item.fotoUrl, tamanho: 68),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.descricao,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.codigoInterno} • ${item.categoria}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 7),
                    Text(
                      formatarCentavos(item.precoVendaCentavos),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _QuantidadeBadge(valor: item.quantidade),
                  const SizedBox(height: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
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

class _ProdutoImagem extends StatelessWidget {
  final String? url;
  final double tamanho;

  const _ProdutoImagem({required this.url, required this.tamanho});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final possuiImagem = url != null && url!.trim().isNotEmpty;

    Widget fallback() => ColoredBox(
      color: theme.colorScheme.primary.withValues(alpha: 0.08),
      child: Icon(
        Icons.inventory_2_outlined,
        color: theme.colorScheme.primary,
        size: tamanho * 0.42,
      ),
    );

    return Container(
      width: tamanho,
      height: tamanho,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerColor),
      ),
      child: possuiImagem
          ? Image.network(
        url!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: progress.expectedTotalBytes == null
                    ? null
                    : progress.cumulativeBytesLoaded /
                    progress.expectedTotalBytes!,
              ),
            ),
          );
        },
      )
          : fallback(),
    );
  }
}

class _QuantidadeBadge extends StatelessWidget {
  final int valor;

  const _QuantidadeBadge({required this.valor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cor = theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.08),
        border: Border.all(color: cor.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        '$valor un.',
        style: theme.textTheme.labelLarge?.copyWith(
          color: cor,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CargaVazia extends StatelessWidget {
  final Future<void> Function() onAtualizar;

  const _CargaVazia({required this.onAtualizar});

  @override
  Widget build(BuildContext context) {
    return _EstadoCard(
      icon: Icons.inventory_2_outlined,
      titulo: 'Sua carga está vazia',
      mensagem: 'Quando uma transferência for enviada para você, os produtos aparecerão aqui.',
      acao: OutlinedButton.icon(
        onPressed: () {
          onAtualizar();
        },
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Atualizar'),
      ),
    );
  }
}

class _NenhumResultado extends StatelessWidget {
  final VoidCallback onLimpar;

  const _NenhumResultado({required this.onLimpar});

  @override
  Widget build(BuildContext context) {
    return _EstadoCard(
      icon: Icons.search_off_rounded,
      titulo: 'Nenhum produto encontrado',
      mensagem: 'Confira o termo pesquisado ou limpe a busca para ver toda a carga.',
      acao: TextButton.icon(
        onPressed: onLimpar,
        icon: const Icon(Icons.close),
        label: const Text('Limpar busca'),
      ),
    );
  }
}

class _EstadoCard extends StatelessWidget {
  final IconData icon;
  final String titulo;
  final String mensagem;
  final Widget acao;

  const _EstadoCard({
    required this.icon,
    required this.titulo,
    required this.mensagem,
    required this.acao,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: Column(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: theme.colorScheme.primary, size: 30),
            ),
            const SizedBox(height: 16),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Text(
                mensagem,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 18),
            acao,
          ],
        ),
      ),
    );
  }
}

class _EstadoCarregandoScaffold extends StatelessWidget {
  final String titulo;

  const _EstadoCarregandoScaffold({required this.titulo});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _EstadoErroScaffold extends StatelessWidget {
  final String titulo;
  final String mensagem;
  final VoidCallback onTentarNovamente;

  const _EstadoErroScaffold({
    required this.titulo,
    required this.mensagem,
    required this.onTentarNovamente,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                mensagem,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onTentarNovamente,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessaoInvalidaScaffold extends StatelessWidget {
  const _SessaoInvalidaScaffold();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Minha carga')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_off_outlined,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Não foi possível identificar o usuário conectado.',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'Saia e entre novamente para acessar sua carga.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
