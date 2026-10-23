import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/barcode_scanner_page.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../produtos/domain/produto.dart';
import '../../produtos/domain/sku.dart';
import '../../produtos/presentation/produto_providers.dart';
import '../domain/stock_movement.dart';
import 'estoque_providers.dart';

class EntradaEstoquePage extends ConsumerStatefulWidget {
  const EntradaEstoquePage({super.key});

  @override
  ConsumerState<EntradaEstoquePage> createState() =>
      _EntradaEstoquePageState();
}

class _EntradaEstoquePageState extends ConsumerState<EntradaEstoquePage> {
  final _buscaController = TextEditingController();
  final _itens = <String, _ItemEntradaSelecionado>{};

  bool _bonificacao = false;
  bool _isSaving = false;
  String? _errorMessage;

  int get _totalProdutos => _itens.length;

  int get _totalUnidades => _itens.values.fold<int>(
    0,
        (total, item) => total + item.quantidade,
  );

  int get _custoTotalCentavos {
    if (_bonificacao) return 0;

    return _itens.values.fold<int>(0, (total, item) {
      final custoUnitario = _parseCentavos(item.custoController.text) ?? 0;
      return total + (custoUnitario * item.quantidade);
    });
  }

  @override
  void dispose() {
    _buscaController.dispose();
    for (final item in _itens.values) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _cancelar() async {
    if (_isSaving) return;

    if (_itens.isEmpty) {
      if (mounted) Navigator.of(context).maybePop();
      return;
    }

    final descartar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Descartar entrada?'),
        content: const Text(
          'Os produtos e custos informados nesta entrada serão perdidos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Continuar preenchendo'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );

    if (descartar == true && mounted) {
      Navigator.of(context).maybePop();
    }
  }

  void _adicionarSku(Sku sku, Map<String, Produto> produtosPorId) {
    final skuId = sku.id;

    if (skuId == null || skuId.isEmpty) {
      setState(() => _errorMessage = 'Este SKU ainda não possui um ID válido.');
      return;
    }

    setState(() {
      final existente = _itens[skuId];

      if (existente != null) {
        existente.quantidade++;
      } else {
        _itens[skuId] = _ItemEntradaSelecionado(
          sku: sku,
          produto: produtosPorId[sku.produtoId],
        );
      }

      _buscaController.clear();
      _errorMessage = null;
    });
  }

  void _alterarQuantidade(_ItemEntradaSelecionado item, int delta) {
    if (_isSaving) return;

    setState(() {
      final novaQuantidade = item.quantidade + delta;
      item.quantidade = novaQuantidade < 1 ? 1 : novaQuantidade;
      _errorMessage = null;
    });
  }

  Future<void> _editarQuantidade(_ItemEntradaSelecionado item) async {
    final controller = TextEditingController(text: '${item.quantidade}');

    try {
      final novaQuantidade = await showDialog<int>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Alterar quantidade'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Quantidade recebida',
              suffixText: 'un.',
            ),
            onSubmitted: (value) {
              final quantidade = int.tryParse(value);
              if (quantidade != null && quantidade > 0) {
                Navigator.of(dialogContext).pop(quantidade);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final quantidade = int.tryParse(controller.text);
                if (quantidade != null && quantidade > 0) {
                  Navigator.of(dialogContext).pop(quantidade);
                }
              },
              child: const Text('Aplicar'),
            ),
          ],
        ),
      );

      if (novaQuantidade != null && mounted) {
        setState(() {
          item.quantidade = novaQuantidade;
          _errorMessage = null;
        });
      }
    } finally {
      controller.dispose();
    }
  }

  void _removerItem(_ItemEntradaSelecionado item) {
    if (_isSaving) return;

    setState(() {
      final removido = _itens.remove(item.sku.id);
      removido?.dispose();
      _errorMessage = null;
    });
  }

  Future<void> _abrirSeletor(
      List<Sku> skus,
      Map<String, Produto> produtosPorId,
      ) async {
    if (_isSaving) return;

    final tamanhoTela = MediaQuery.sizeOf(context);
    final largura = tamanhoTela.width;
    final consultaInicial = _buscaController.text.trim();
    Sku? selecionado;

    if (largura >= 700) {
      selecionado = await showDialog<Sku>(
        context: context,
        builder: (dialogContext) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: largura - 48 > 680 ? 680 : largura - 48,
            height: tamanhoTela.height * .82 > 620
                ? 620
                : tamanhoTela.height * .82,
            child: _SeletorSku(
              skus: skus,
              produtosPorId: produtosPorId,
              consultaInicial: consultaInicial,
              quantidadesSelecionadas: {
                for (final item in _itens.values)
                  item.sku.id!: item.quantidade,
              },
              onSelecionar: (sku) => Navigator.of(dialogContext).pop(sku),
              onCancelar: () => Navigator.of(dialogContext).pop(),
            ),
          ),
        ),
      );
    } else {
      selecionado = await showModalBottomSheet<Sku>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (bottomSheetContext) => FractionallySizedBox(
          heightFactor: 0.90,
          child: _SeletorSku(
            skus: skus,
            produtosPorId: produtosPorId,
            consultaInicial: consultaInicial,
            quantidadesSelecionadas: {
              for (final item in _itens.values)
                item.sku.id!: item.quantidade,
            },
            onSelecionar: (sku) =>
                Navigator.of(bottomSheetContext).pop(sku),
            onCancelar: () => Navigator.of(bottomSheetContext).pop(),
          ),
        ),
      );
    }

    if (selecionado != null && mounted) {
      _adicionarSku(selecionado, produtosPorId);
    }
  }

  Future<void> _escanearCodigo(
      List<Sku> skus,
      Map<String, Produto> produtosPorId,
      ) async {
    if (_isSaving) return;

    final codigo = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );

    if (codigo == null || !mounted) return;

    final codigoLimpo = codigo.trim();
    final codigoNormalizado = codigoLimpo.toLowerCase();
    Sku? encontrado;

    for (final sku in skus) {
      if (sku.id == null) continue;

      final correspondeBarras =
          sku.codigoBarras?.trim().toLowerCase() == codigoNormalizado;
      final correspondeInterno =
          sku.codigoInterno.trim().toLowerCase() == codigoNormalizado;

      if (correspondeBarras || correspondeInterno) {
        encontrado = sku;
        break;
      }
    }

    if (encontrado != null) {
      _adicionarSku(encontrado, produtosPorId);
      return;
    }

    setState(() {
      _buscaController.text = codigoLimpo;
      _buscaController.selection = TextSelection.collapsed(
        offset: codigoLimpo.length,
      );
      _errorMessage = 'Nenhum SKU encontrado para o código $codigoLimpo.';
    });
  }

  String? _validarEntrada() {
    if (_itens.isEmpty) {
      return 'Adicione pelo menos um produto à entrada.';
    }

    for (final item in _itens.values) {
      if (item.quantidade <= 0) {
        return 'Informe uma quantidade válida para ${item.descricao}.';
      }

      if (!_bonificacao) {
        final custo = _parseCentavos(item.custoController.text);
        if (custo == null || custo <= 0) {
          return 'Informe o custo unitário de ${item.descricao}.';
        }
      }
    }

    final usuario = ref.read(appUserProvider).value;
    if (usuario == null) {
      return 'Não foi possível identificar o usuário logado.';
    }
    if (usuario.orgId.isEmpty) {
      return 'Sua conta não tem organização definida. Fale com um administrador.';
    }

    return null;
  }

  Future<bool> _mostrarRevisao() async {
    final itens = _itens.values.toList(growable: false);
    final tamanhoTela = MediaQuery.sizeOf(context);
    final larguraDialog =
    tamanhoTela.width < 720 ? tamanhoTela.width - 32 : 680.0;
    final alturaDialog =
    tamanhoTela.height < 720 ? tamanhoTela.height - 48 : 640.0;

    final confirmou = await showDialog<bool>(
      context: context,
      barrierDismissible: !_isSaving,
      builder: (dialogContext) => _DialogRevisaoEntrada(
        largura: larguraDialog,
        altura: alturaDialog,
        itens: itens,
        totalProdutos: _totalProdutos,
        totalUnidades: _totalUnidades,
        custoTotalCentavos: _custoTotalCentavos,
        bonificacao: _bonificacao,
        onVoltar: () => Navigator.of(dialogContext).pop(false),
        onConfirmar: () => Navigator.of(dialogContext).pop(true),
      ),
    );

    return confirmou ?? false;
  }

  Future<void> _revisarERegistrar() async {
    if (_isSaving) return;

    final erro = _validarEntrada();
    if (erro != null) {
      setState(() => _errorMessage = erro);
      return;
    }

    setState(() => _errorMessage = null);

    final confirmou = await _mostrarRevisao();
    if (!confirmou || !mounted) return;

    final usuario = ref.read(appUserProvider).value!;
    final itensParaRegistrar = _itens.values.toList(growable: false);
    final concluidos = <String>[];
    Object? falha;

    setState(() => _isSaving = true);

    for (final item in itensParaRegistrar) {
      final skuId = item.sku.id!;
      final custoUnitario =
      _bonificacao ? 0 : _parseCentavos(item.custoController.text)!;

      try {
        await ref.read(estoqueRepositoryProvider).registrarMovimento(
          orgId: usuario.orgId,
          // O campo produtoId ainda guarda o ID do SKU no domínio atual.
          produtoId: skuId,
          quantidade: item.quantidade,
          origem: LocalEstoque.fornecedor,
          destino: LocalEstoque.central,
          motivo: MovimentoMotivo.entrada,
          usuarioId: usuario.uid,
          custoUnitarioCentavosNoMomento: custoUnitario,
        );
        concluidos.add(skuId);
      } catch (error, stack) {
        debugPrint('Erro ao registrar entrada do SKU $skuId: $error\n$stack');
        falha = error;
        break;
      }
    }

    if (!mounted) return;

    setState(() {
      for (final skuId in concluidos) {
        final removido = _itens.remove(skuId);
        removido?.dispose();
      }

      _isSaving = false;

      if (falha != null) {
        _errorMessage = concluidos.isEmpty
            ? 'Não foi possível registrar a entrada. Tente novamente.'
            : '${concluidos.length} produto(s) foram registrados. Os demais '
            'continuam na tela para você tentar novamente.';
      } else {
        _errorMessage = null;
        _bonificacao = false;
        _buscaController.clear();
      }
    });

    if (falha == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${itensParaRegistrar.length} produto(s) e '
                '${itensParaRegistrar.fold<int>(0, (t, i) => t + i.quantidade)} '
                'unidade(s) adicionados ao estoque central.',
          ),
        ),
      );
    }
  }

  void _recarregarProdutos() {
    ref.invalidate(skusListProvider);
    ref.invalidate(produtosListProvider);
  }

  @override
  Widget build(BuildContext context) {
    final usuario = ref.watch(appUserProvider).value;
    final skusAsync = ref.watch(skusListProvider);
    final produtosAsync = ref.watch(produtosListProvider);
    final compacto = MediaQuery.sizeOf(context).width < 760;

    if (usuario == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Voltar',
          onPressed: _isSaving ? null : _cancelar,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Entrada de Estoque'),
        actions: [
          if (!compacto) ...[
            TextButton.icon(
              onPressed: _isSaving ? null : _cancelar,
              icon: const Icon(Icons.close_rounded),
              label: const Text('Cancelar'),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: FilledButton.icon(
                onPressed: _isSaving ? null : _revisarERegistrar,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Revisar entrada'),
              ),
            ),
            const SizedBox(width: 12),
          ],
        ],
      ),
      bottomNavigationBar: compacto
          ? _BarraInferiorEntrada(
        custoTotalCentavos: _custoTotalCentavos,
        totalUnidades: _totalUnidades,
        bonificacao: _bonificacao,
        salvando: _isSaving,
        habilitado: _itens.isNotEmpty,
        onRevisar: _revisarERegistrar,
      )
          : null,
      body: skusAsync.when(
        loading: () => const _LoadingEntrada(),
        error: (error, stack) {
          debugPrint('Erro ao carregar SKUs: $error\n$stack');
          return _ErroEntrada(onTentarNovamente: _recarregarProdutos);
        },
        data: (skus) => produtosAsync.when(
          loading: () => const _LoadingEntrada(),
          error: (error, stack) {
            debugPrint('Erro ao carregar produtos: $error\n$stack');
            return _ErroEntrada(onTentarNovamente: _recarregarProdutos);
          },
          data: (produtos) {
            final produtosPorId = <String, Produto>{
              for (final produto in produtos)
                if (produto.id != null) produto.id!: produto,
            };

            return _buildConteudo(
              skus: skus,
              produtosPorId: produtosPorId,
              usuarioNome: usuario.nome,
            );
          },
        ),
      ),
    );
  }

  Widget _buildConteudo({
    required List<Sku> skus,
    required Map<String, Produto> produtosPorId,
    required String usuarioNome,
  }) {
    return SafeArea(
      child: ResponsiveCenter(
        maxWidth: 1180,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Text(
              'Registre os produtos recebidos do fornecedor.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            _DadosEntrada(
              usuarioNome: usuarioNome,
              data: _formatarData(DateTime.now()),
            ),
            const SizedBox(height: 14),
            _BuscaProdutoEntrada(
              controller: _buscaController,
              onScanner: () => _escanearCodigo(skus, produtosPorId),
              onAdicionar: () => _abrirSeletor(skus, produtosPorId),
              enabled: !_isSaving,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              _AvisoErro(
                mensagem: _errorMessage!,
                onFechar: () => setState(() => _errorMessage = null),
              ),
            ],
            const SizedBox(height: 14),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final desktop = constraints.maxWidth >= 900;

                  if (desktop) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _PainelProdutosEntrada(
                            itens: _itens.values.toList(growable: false),
                            bonificacao: _bonificacao,
                            onDiminuir: (item) =>
                                _alterarQuantidade(item, -1),
                            onAumentar: (item) =>
                                _alterarQuantidade(item, 1),
                            onEditarQuantidade: _editarQuantidade,
                            onRemover: _removerItem,
                            onCustoChanged: () => setState(() {
                              _errorMessage = null;
                            }),
                            onAdicionar: () =>
                                _abrirSeletor(skus, produtosPorId),
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 326,
                          child: _ResumoEntrada(
                            totalProdutos: _totalProdutos,
                            totalUnidades: _totalUnidades,
                            custoTotalCentavos: _custoTotalCentavos,
                            bonificacao: _bonificacao,
                            salvando: _isSaving,
                            mostrarBotao: true,
                            onBonificacaoChanged: (value) => setState(() {
                              _bonificacao = value;
                              _errorMessage = null;
                            }),
                            onRevisar: _revisarERegistrar,
                          ),
                        ),
                      ],
                    );
                  }

                  final itens = _itens.values.toList(growable: false);

                  return ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Produtos da entrada',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          Text(
                            '${itens.length} produto(s)',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (itens.isEmpty)
                        _EntradaVazia(
                          onAdicionar: () =>
                              _abrirSeletor(skus, produtosPorId),
                        )
                      else
                        for (var index = 0; index < itens.length; index++) ...[
                          if (index > 0) const SizedBox(height: 8),
                          _ItemEntradaCard(
                            item: itens[index],
                            bonificacao: _bonificacao,
                            onDiminuir: () =>
                                _alterarQuantidade(itens[index], -1),
                            onAumentar: () =>
                                _alterarQuantidade(itens[index], 1),
                            onEditarQuantidade: () =>
                                _editarQuantidade(itens[index]),
                            onRemover: () => _removerItem(itens[index]),
                            onCustoChanged: () => setState(() {
                              _errorMessage = null;
                            }),
                          ),
                        ],
                      const SizedBox(height: 14),
                      _ResumoEntrada(
                        totalProdutos: _totalProdutos,
                        totalUnidades: _totalUnidades,
                        custoTotalCentavos: _custoTotalCentavos,
                        bonificacao: _bonificacao,
                        salvando: _isSaving,
                        mostrarBotao: false,
                        onBonificacaoChanged: (value) => setState(() {
                          _bonificacao = value;
                          _errorMessage = null;
                        }),
                        onRevisar: _revisarERegistrar,
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemEntradaSelecionado {
  final Sku sku;
  final Produto? produto;
  final TextEditingController custoController;
  int quantidade;

  _ItemEntradaSelecionado({
    required this.sku,
    required this.produto,
    this.quantidade = 1,
  }) : custoController = TextEditingController();

  String get descricao {
    final nome = produto?.descricao ?? 'Produto não encontrado';
    final variacao = sku.variacao?.trim();
    return variacao?.isNotEmpty == true ? '$nome — $variacao' : nome;
  }

  String? get fotoUrl => produto?.fotoUrl;

  void dispose() => custoController.dispose();
}

class _DadosEntrada extends StatelessWidget {
  final String usuarioNome;
  final String data;

  const _DadosEntrada({required this.usuarioNome, required this.data});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compacto = constraints.maxWidth < 620;
            final itens = [
              const _DadoFluxo(
                icon: Icons.local_shipping_outlined,
                label: 'Origem',
                valor: 'Fornecedor',
              ),
              const _DadoFluxo(
                icon: Icons.warehouse_outlined,
                label: 'Destino',
                valor: 'Estoque central',
              ),
              _DadoFluxo(
                icon: Icons.person_outline_rounded,
                label: 'Responsável',
                valor: usuarioNome,
              ),
              _DadoFluxo(
                icon: Icons.calendar_today_outlined,
                label: 'Data',
                valor: data,
              ),
            ];

            if (compacto) {
              return Wrap(
                spacing: 12,
                runSpacing: 14,
                children: [
                  for (final item in itens)
                    SizedBox(
                      width: (constraints.maxWidth - 12) / 2,
                      child: item,
                    ),
                ],
              );
            }

            return Row(
              children: [
                for (var index = 0; index < itens.length; index++) ...[
                  if (index > 0) const SizedBox(width: 18),
                  Expanded(child: itens[index]),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DadoFluxo extends StatelessWidget {
  final IconData icon;
  final String label;
  final String valor;

  const _DadoFluxo({
    required this.icon,
    required this.label,
    required this.valor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 1),
              Text(
                valor,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BuscaProdutoEntrada extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onScanner;
  final VoidCallback onAdicionar;
  final bool enabled;

  const _BuscaProdutoEntrada({
    required this.controller,
    required this.onScanner,
    required this.onAdicionar,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compacto = constraints.maxWidth < 650;
        final pesquisa = Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => onAdicionar(),
                decoration: const InputDecoration(
                  hintText: 'Buscar produto, SKU ou código de barras',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 56,
              height: 56,
              child: IconButton.filledTonal(
                tooltip: 'Escanear código',
                onPressed: enabled ? onScanner : null,
                icon: const Icon(Icons.qr_code_scanner_rounded),
              ),
            ),
          ],
        );

        final botao = FilledButton.icon(
          onPressed: enabled ? onAdicionar : null,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Adicionar produto'),
        );

        if (compacto) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              pesquisa,
              const SizedBox(height: 8),
              SizedBox(height: 48, child: botao),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: pesquisa),
            const SizedBox(width: 10),
            SizedBox(height: 56, child: botao),
          ],
        );
      },
    );
  }
}

class _PainelProdutosEntrada extends StatelessWidget {
  final List<_ItemEntradaSelecionado> itens;
  final bool bonificacao;
  final ValueChanged<_ItemEntradaSelecionado> onDiminuir;
  final ValueChanged<_ItemEntradaSelecionado> onAumentar;
  final ValueChanged<_ItemEntradaSelecionado> onEditarQuantidade;
  final ValueChanged<_ItemEntradaSelecionado> onRemover;
  final VoidCallback onCustoChanged;
  final VoidCallback onAdicionar;

  const _PainelProdutosEntrada({
    required this.itens,
    required this.bonificacao,
    required this.onDiminuir,
    required this.onAumentar,
    required this.onEditarQuantidade,
    required this.onRemover,
    required this.onCustoChanged,
    required this.onAdicionar,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Produtos da entrada',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${itens.length} produto(s)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          const _CabecalhoTabelaEntrada(),
          const Divider(height: 1),
          Expanded(
            child: itens.isEmpty
                ? _EntradaVazia(onAdicionar: onAdicionar)
                : ListView.separated(
              itemCount: itens.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = itens[index];
                return _LinhaEntradaDesktop(
                  item: item,
                  bonificacao: bonificacao,
                  onDiminuir: () => onDiminuir(item),
                  onAumentar: () => onAumentar(item),
                  onEditarQuantidade: () => onEditarQuantidade(item),
                  onRemover: () => onRemover(item),
                  onCustoChanged: onCustoChanged,
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Text(
              '${itens.length} produto(s) adicionado(s)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _CabecalhoTabelaEntrada extends StatelessWidget {
  const _CabecalhoTabelaEntrada();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );

    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          Expanded(flex: 5, child: Text('Produto', style: style)),
          SizedBox(width: 130, child: Text('Quantidade', style: style)),
          SizedBox(width: 132, child: Text('Custo unit.', style: style)),
          SizedBox(width: 104, child: Text('Total', style: style)),
          const SizedBox(width: 42),
        ],
      ),
    );
  }
}

class _LinhaEntradaDesktop extends StatelessWidget {
  final _ItemEntradaSelecionado item;
  final bool bonificacao;
  final VoidCallback onDiminuir;
  final VoidCallback onAumentar;
  final VoidCallback onEditarQuantidade;
  final VoidCallback onRemover;
  final VoidCallback onCustoChanged;

  const _LinhaEntradaDesktop({
    required this.item,
    required this.bonificacao,
    required this.onDiminuir,
    required this.onAumentar,
    required this.onEditarQuantidade,
    required this.onRemover,
    required this.onCustoChanged,
  });

  @override
  Widget build(BuildContext context) {
    final custo = bonificacao
        ? 0
        : (_parseCentavos(item.custoController.text) ?? 0);
    final total = custo * item.quantidade;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Row(
              children: [
                _ProdutoImagem(url: item.fotoUrl, tamanho: 52),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.descricao,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.sku.codigoInterno,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 130,
            child: _ControleQuantidade(
              quantidade: item.quantidade,
              onDiminuir: onDiminuir,
              onAumentar: onAumentar,
              onEditar: onEditarQuantidade,
            ),
          ),
          SizedBox(
            width: 132,
            child: _CampoCusto(
              controller: item.custoController,
              enabled: !bonificacao,
              onChanged: onCustoChanged,
            ),
          ),
          SizedBox(
            width: 104,
            child: Text(
              bonificacao ? 'Bonificação' : _formatarCentavos(total),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: bonificacao
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
            ),
          ),
          SizedBox(
            width: 42,
            child: IconButton(
              tooltip: 'Remover produto',
              onPressed: onRemover,
              color: Theme.of(context).colorScheme.error,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemEntradaCard extends StatelessWidget {
  final _ItemEntradaSelecionado item;
  final bool bonificacao;
  final VoidCallback onDiminuir;
  final VoidCallback onAumentar;
  final VoidCallback onEditarQuantidade;
  final VoidCallback onRemover;
  final VoidCallback onCustoChanged;

  const _ItemEntradaCard({
    required this.item,
    required this.bonificacao,
    required this.onDiminuir,
    required this.onAumentar,
    required this.onEditarQuantidade,
    required this.onRemover,
    required this.onCustoChanged,
  });

  @override
  Widget build(BuildContext context) {
    final custo = bonificacao
        ? 0
        : (_parseCentavos(item.custoController.text) ?? 0);
    final total = custo * item.quantidade;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProdutoImagem(url: item.fotoUrl, tamanho: 60),
                const SizedBox(width: 12),
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
                      const SizedBox(height: 3),
                      Text(
                        item.sku.codigoInterno,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Remover produto',
                  onPressed: onRemover,
                  color: Theme.of(context).colorScheme.error,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final muitoCompacto = constraints.maxWidth < 350;
                final quantidade = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quantidade',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 5),
                    _ControleQuantidade(
                      quantidade: item.quantidade,
                      onDiminuir: onDiminuir,
                      onAumentar: onAumentar,
                      onEditar: onEditarQuantidade,
                    ),
                  ],
                );
                final custo = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Custo unitário',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 5),
                    _CampoCusto(
                      controller: item.custoController,
                      enabled: !bonificacao,
                      onChanged: onCustoChanged,
                    ),
                  ],
                );

                if (muitoCompacto) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      quantidade,
                      const SizedBox(height: 10),
                      custo,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: quantidade),
                    const SizedBox(width: 12),
                    Expanded(child: custo),
                  ],
                );
              },
            ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    bonificacao ? 'Entrada bonificada' : 'Total do produto',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Text(
                  bonificacao ? 'R\$ 0,00' : _formatarCentavos(total),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: bonificacao
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CampoCusto extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onChanged;

  const _CampoCusto({
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
      ],
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(
        prefixText: 'R\$ ',
        hintText: '0,00',
        isDense: true,
        helperText: enabled ? null : 'Bonificação',
      ),
    );
  }
}

class _ControleQuantidade extends StatelessWidget {
  final int quantidade;
  final VoidCallback onDiminuir;
  final VoidCallback onAumentar;
  final VoidCallback onEditar;

  const _ControleQuantidade({
    required this.quantidade,
    required this.onDiminuir,
    required this.onAumentar,
    required this.onEditar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            tooltip: 'Diminuir',
            onPressed: quantidade > 1 ? onDiminuir : null,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove_rounded, size: 19),
          ),
          InkWell(
            onTap: onEditar,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
              child: Text(
                '$quantidade',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Aumentar',
            onPressed: onAumentar,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_rounded, size: 19),
          ),
        ],
      ),
    );
  }
}

class _ResumoEntrada extends StatelessWidget {
  final int totalProdutos;
  final int totalUnidades;
  final int custoTotalCentavos;
  final bool bonificacao;
  final bool salvando;
  final bool mostrarBotao;
  final ValueChanged<bool> onBonificacaoChanged;
  final VoidCallback onRevisar;

  const _ResumoEntrada({
    required this.totalProdutos,
    required this.totalUnidades,
    required this.custoTotalCentavos,
    required this.bonificacao,
    required this.salvando,
    required this.mostrarBotao,
    required this.onBonificacaoChanged,
    required this.onRevisar,
  });

  @override
  Widget build(BuildContext context) {
    final conteudo = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.receipt_long_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Resumo da entrada',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _ResumoNumeros(
            totalProdutos: totalProdutos,
            totalUnidades: totalUnidades,
            custoTotalCentavos: custoTotalCentavos,
            bonificacao: bonificacao,
          ),
          const Divider(height: 28),
          Row(
            children: [
              Icon(
                Icons.warehouse_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Destino', style: TextStyle(fontSize: 12)),
                    Text(
                      'Estoque central',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Bonificação'),
            subtitle: const Text('Entrada gratuita com custo igual a zero'),
            value: bonificacao,
            onChanged: salvando ? null : onBonificacaoChanged,
          ),
        ],
      ),
    );

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: mostrarBotao
          ? Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              primary: false,
              child: conteudo,
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Confira os dados antes de registrar o estoque.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: salvando || totalProdutos == 0
                        ? null
                        : onRevisar,
                    icon: salvando
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                        : const Icon(Icons.fact_check_outlined),
                    label: Text(
                      salvando ? 'Registrando…' : 'Revisar entrada',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      )
          : conteudo,
    );
  }
}

class _ResumoNumeros extends StatelessWidget {
  final int totalProdutos;
  final int totalUnidades;
  final int custoTotalCentavos;
  final bool bonificacao;

  const _ResumoNumeros({
    required this.totalProdutos,
    required this.totalUnidades,
    required this.custoTotalCentavos,
    required this.bonificacao,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compacto = constraints.maxWidth < 260;
        final itens = [
          _ResumoValor(
            icon: Icons.inventory_2_outlined,
            valor: '$totalProdutos',
            label: totalProdutos == 1 ? 'produto' : 'produtos',
          ),
          _ResumoValor(
            icon: Icons.widgets_outlined,
            valor: '$totalUnidades',
            label: totalUnidades == 1 ? 'unidade' : 'unidades',
          ),
          _ResumoValor(
            icon: Icons.payments_outlined,
            valor: bonificacao
                ? 'Bonificação'
                : _formatarCentavos(custoTotalCentavos),
            label: 'custo total',
          ),
        ];

        if (compacto) {
          return Column(
            children: [
              for (var index = 0; index < itens.length; index++) ...[
                if (index > 0) const SizedBox(height: 10),
                SizedBox(width: double.infinity, child: itens[index]),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (var index = 0; index < itens.length; index++) ...[
              if (index > 0) const SizedBox(width: 8),
              Expanded(child: itens[index]),
            ],
          ],
        );
      },
    );
  }
}

class _ResumoValor extends StatelessWidget {
  final IconData icon;
  final String valor;
  final String label;

  const _ResumoValor({
    required this.icon,
    required this.valor,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: .5),
        ),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 5),
          Text(
            valor,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _BarraInferiorEntrada extends StatelessWidget {
  final int custoTotalCentavos;
  final int totalUnidades;
  final bool bonificacao;
  final bool salvando;
  final bool habilitado;
  final VoidCallback onRevisar;

  const _BarraInferiorEntrada({
    required this.custoTotalCentavos,
    required this.totalUnidades,
    required this.bonificacao,
    required this.salvando,
    required this.habilitado,
    required this.onRevisar,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 10,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$totalUnidades unidade(s)',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      bonificacao
                          ? 'Bonificação'
                          : _formatarCentavos(custoTotalCentavos),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: salvando || !habilitado ? null : onRevisar,
                icon: salvando
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.fact_check_outlined),
                label: Text(salvando ? 'Registrando…' : 'Revisar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeletorSku extends StatefulWidget {
  final List<Sku> skus;
  final Map<String, Produto> produtosPorId;
  final String consultaInicial;
  final Map<String, int> quantidadesSelecionadas;
  final ValueChanged<Sku> onSelecionar;
  final VoidCallback onCancelar;

  const _SeletorSku({
    required this.skus,
    required this.produtosPorId,
    required this.consultaInicial,
    required this.quantidadesSelecionadas,
    required this.onSelecionar,
    required this.onCancelar,
  });

  @override
  State<_SeletorSku> createState() => _SeletorSkuState();
}

class _SeletorSkuState extends State<_SeletorSku> {
  late final TextEditingController _controller;
  late String _busca;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.consultaInicial);
    _busca = widget.consultaInicial.trim().toLowerCase();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = widget.skus.where((sku) {
      if (sku.id == null) return false;
      if (_busca.isEmpty) return true;

      final produto = widget.produtosPorId[sku.produtoId];
      final texto = [
        produto?.descricao ?? '',
        produto?.categoria ?? '',
        sku.variacao ?? '',
        sku.codigoInterno,
        sku.codigoBarras ?? '',
      ].join(' ').toLowerCase();

      return texto.contains(_busca);
    }).toList()
      ..sort((a, b) {
        final nomeA = widget.produtosPorId[a.produtoId]?.descricao ?? '';
        final nomeB = widget.produtosPorId[b.produtoId]?.descricao ?? '';
        return nomeA.toLowerCase().compareTo(nomeB.toLowerCase());
      });

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Adicionar produto',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Fechar',
                  onPressed: widget.onCancelar,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: (value) {
                setState(() => _busca = value.trim().toLowerCase());
              },
              decoration: InputDecoration(
                hintText: 'Produto, SKU ou código de barras',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _busca.isNotEmpty
                    ? IconButton(
                  tooltip: 'Limpar',
                  onPressed: () {
                    _controller.clear();
                    setState(() => _busca = '');
                  },
                  icon: const Icon(Icons.close_rounded),
                )
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              '${filtrados.length} resultado(s)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 6),
          const Divider(height: 1),
          Expanded(
            child: filtrados.isEmpty
                ? const Center(child: Text('Nenhum produto encontrado.'))
                : ListView.separated(
              itemCount: filtrados.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final sku = filtrados[index];
                final produto = widget.produtosPorId[sku.produtoId];
                final selecionadas =
                    widget.quantidadesSelecionadas[sku.id] ?? 0;
                final variacao = sku.variacao?.trim();

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 6,
                  ),
                  leading: _ProdutoImagem(
                    url: produto?.fotoUrl,
                    tamanho: 50,
                  ),
                  title: Text(
                    produto?.descricao ?? 'Produto não encontrado',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    [
                      sku.codigoInterno,
                      if (variacao?.isNotEmpty == true) variacao!,
                    ].join(' • '),
                  ),
                  trailing: selecionadas > 0
                      ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$selecionadas na entrada',
                      style: TextStyle(
                        color:
                        Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  )
                      : const Icon(Icons.add_circle_outline_rounded),
                  onTap: () => widget.onSelecionar(sku),
                );
              },
            ),
          ),
        ],
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
    final possuiFoto = url?.trim().isNotEmpty == true;

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: tamanho,
        height: tamanho,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: possuiFoto
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

class _DialogRevisaoEntrada extends StatelessWidget {
  final double largura;
  final double altura;
  final List<_ItemEntradaSelecionado> itens;
  final int totalProdutos;
  final int totalUnidades;
  final int custoTotalCentavos;
  final bool bonificacao;
  final VoidCallback onVoltar;
  final VoidCallback onConfirmar;

  const _DialogRevisaoEntrada({
    required this.largura,
    required this.altura,
    required this.itens,
    required this.totalProdutos,
    required this.totalUnidades,
    required this.custoTotalCentavos,
    required this.bonificacao,
    required this.onVoltar,
    required this.onConfirmar,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: largura,
        height: altura,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Revisar entrada',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    onPressed: onVoltar,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                primary: false,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _FluxoRevisao(),
                    const SizedBox(height: 16),
                    _ResumoNumeros(
                      totalProdutos: totalProdutos,
                      totalUnidades: totalUnidades,
                      custoTotalCentavos: custoTotalCentavos,
                      bonificacao: bonificacao,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Produtos da entrada',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (var index = 0; index < itens.length; index++) ...[
                      if (index > 0) const Divider(height: 1),
                      _ItemRevisao(
                        item: itens[index],
                        bonificacao: bonificacao,
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      'Ao confirmar, o saldo será adicionado ao estoque central.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: onVoltar,
                    child: const Text('Voltar e ajustar'),
                  ),
                  FilledButton.icon(
                    onPressed: onConfirmar,
                    icon: const Icon(Icons.check_circle_outline_rounded),
                    label: const Text('Confirmar entrada'),
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

class _FluxoRevisao extends StatelessWidget {
  const _FluxoRevisao();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Expanded(
            child: _DadoFluxo(
              icon: Icons.local_shipping_outlined,
              label: 'Origem',
              valor: 'Fornecedor',
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Icon(Icons.arrow_forward_rounded),
          ),
          Expanded(
            child: _DadoFluxo(
              icon: Icons.warehouse_outlined,
              label: 'Destino',
              valor: 'Estoque central',
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemRevisao extends StatelessWidget {
  final _ItemEntradaSelecionado item;
  final bool bonificacao;

  const _ItemRevisao({required this.item, required this.bonificacao});

  @override
  Widget build(BuildContext context) {
    final custo = bonificacao
        ? 0
        : (_parseCentavos(item.custoController.text) ?? 0);
    final total = custo * item.quantidade;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          _ProdutoImagem(url: item.fotoUrl, tamanho: 44),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.descricao,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.quantidade} un. × '
                      '${bonificacao ? 'R\$ 0,00' : _formatarCentavos(custo)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _formatarCentavos(total),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _EntradaVazia extends StatelessWidget {
  final VoidCallback onAdicionar;

  const _EntradaVazia({required this.onAdicionar});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add_box_outlined,
              size: 52,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Nenhum produto adicionado',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Busque ou escaneie os produtos recebidos do fornecedor.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onAdicionar,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Adicionar produto'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvisoErro extends StatelessWidget {
  final String mensagem;
  final VoidCallback onFechar;

  const _AvisoErro({required this.mensagem, required this.onFechar});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        border: Border.all(color: color.withValues(alpha: .35)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: color),
          const SizedBox(width: 9),
          Expanded(child: Text(mensagem)),
          IconButton(
            tooltip: 'Fechar aviso',
            onPressed: onFechar,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _LoadingEntrada extends StatelessWidget {
  const _LoadingEntrada();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _ErroEntrada extends StatelessWidget {
  final VoidCallback onTentarNovamente;

  const _ErroEntrada({required this.onTentarNovamente});

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
            const Text(
              'Não foi possível carregar os produtos.',
              textAlign: TextAlign.center,
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
    );
  }
}

int? _parseCentavos(String valor) {
  var normalizado = valor.trim().replaceAll(RegExp(r'[^0-9,.]'), '');
  if (normalizado.isEmpty) return null;

  if (normalizado.contains(',')) {
    normalizado = normalizado.replaceAll('.', '').replaceAll(',', '.');
  } else if (RegExp(r'\.').allMatches(normalizado).length > 1) {
    final partes = normalizado.split('.');
    final decimal = partes.removeLast();
    normalizado = '${partes.join()}.$decimal';
  }

  final numero = double.tryParse(normalizado);
  if (numero == null) return null;
  return (numero * 100).round();
}

String _formatarCentavos(int centavos) {
  final negativo = centavos < 0;
  final absoluto = centavos.abs();
  final reais = (absoluto ~/ 100).toString();
  final centavosTexto = (absoluto % 100).toString().padLeft(2, '0');
  final reaisFormatados = reais.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => '.',
  );

  return '${negativo ? '-' : ''}R\$ $reaisFormatados,$centavosTexto';
}

String _formatarData(DateTime data) {
  final dia = data.day.toString().padLeft(2, '0');
  final mes = data.month.toString().padLeft(2, '0');
  return '$dia/$mes/${data.year}';
}
