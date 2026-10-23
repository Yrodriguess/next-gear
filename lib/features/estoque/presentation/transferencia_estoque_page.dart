import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/barcode_scanner_page.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../auth/presentation/auth_providers.dart'
    hide usuariosListProvider;
import '../../auth/presentation/usuario_providers.dart';
import '../../produtos/domain/sku.dart';
import '../../produtos/presentation/produto_providers.dart';
import '../domain/stock_movement.dart';
import 'estoque_providers.dart';

const double _kBreakpointDesktop = 920;
const double _kMaxWidthConteudo = 1200;

enum _ModoMovimentacao { carregar, retirar }

/// Movimenta produtos entre o estoque central e a carga de um vendedor.
///
/// - carregar: estoque central → carga do vendedor;
/// - retirar: carga do vendedor → estoque central.
///
/// A direção do movimento fica registrada por origem e destino. A retirada não
/// apaga a transferência anterior: ela cria uma nova movimentação inversa.
class TransferenciaEstoquePage extends ConsumerStatefulWidget {
  const TransferenciaEstoquePage({super.key});

  @override
  ConsumerState<TransferenciaEstoquePage> createState() =>
      _TransferenciaEstoquePageState();
}

class _TransferenciaEstoquePageState
    extends ConsumerState<TransferenciaEstoquePage> {
  final _buscaController = TextEditingController();
  final Map<String, int> _quantidades = {};

  _ModoMovimentacao _modo = _ModoMovimentacao.carregar;
  String? _vendedorSelecionadoId;
  String _termoBusca = '';
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  int get _totalProdutos =>
      _quantidades.values.where((quantidade) => quantidade > 0).length;

  int get _totalUnidades => _quantidades.values.fold<int>(
    0,
        (total, quantidade) => total + quantidade,
  );

  void _limparSelecao() {
    setState(() {
      _quantidades.clear();
      _errorMessage = null;
    });
  }

  Future<bool> _confirmarLimpeza() async {
    if (_totalUnidades == 0) return true;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Limpar itens selecionados?'),
        content: const Text(
          'Ao alterar o tipo de movimentação ou o vendedor, os itens já '
              'selecionados serão removidos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Continuar nesta seleção'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Limpar e continuar'),
          ),
        ],
      ),
    );

    return confirmar ?? false;
  }

  Future<void> _alterarModo(_ModoMovimentacao novoModo) async {
    if (_modo == novoModo || _isSaving) return;
    if (!await _confirmarLimpeza() || !mounted) return;

    setState(() {
      _modo = novoModo;
      _quantidades.clear();
      _errorMessage = null;
    });
  }

  Future<void> _alterarVendedor(String? vendedorId) async {
    if (vendedorId == null ||
        vendedorId == _vendedorSelecionadoId ||
        _isSaving) {
      return;
    }
    if (!await _confirmarLimpeza() || !mounted) return;

    setState(() {
      _vendedorSelecionadoId = vendedorId;
      _quantidades.clear();
      _errorMessage = null;
    });
  }

  void _alterarQuantidade(_ItemMovimentacao item, int quantidade) {
    if (_isSaving) return;
    final quantidadeFinal = quantidade.clamp(0, item.disponivel).toInt();

    setState(() {
      if (quantidadeFinal == 0) {
        _quantidades.remove(item.skuId);
      } else {
        _quantidades[item.skuId] = quantidadeFinal;
      }
      _errorMessage = null;
    });
  }

  Future<void> _editarQuantidade(_ItemMovimentacao item) async {
    final controller = TextEditingController(
      text: '${_quantidades[item.skuId] ?? 0}',
    );

    try {
      final quantidade = await showDialog<int>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Informar quantidade'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.descricao,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text('Disponível na origem: ${item.disponivel} unidades'),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Quantidade'),
                  onSubmitted: (value) {
                    Navigator.of(dialogContext).pop(int.tryParse(value));
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                int.tryParse(controller.text),
              ),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      );

      if (quantidade == null || !mounted) return;
      if (quantidade > item.disponivel) {
        setState(() {
          _errorMessage =
          'A quantidade de ${item.descricao} não pode ultrapassar '
              '${item.disponivel} unidades.';
        });
        return;
      }
      _alterarQuantidade(item, quantidade);
    } finally {
      controller.dispose();
    }
  }

  Future<void> _escanearCodigo() async {
    final codigo = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );

    if (codigo == null || !mounted) return;
    final codigoFinal = codigo.trim();
    setState(() {
      _buscaController.text = codigoFinal;
      _buscaController.selection = TextSelection.collapsed(
        offset: codigoFinal.length,
      );
      _termoBusca = codigoFinal;
    });
  }

  Future<bool> _mostrarRevisao({
    required String vendedorNome,
    required List<_ItemMovimentacao> selecionados,
  }) async {
    final retirando = _modo == _ModoMovimentacao.retirar;
    final origem = retirando ? 'Carga de $vendedorNome' : 'Estoque central';
    final destino = retirando ? 'Estoque central' : 'Carga de $vendedorNome';

    final confirmar = await showDialog<bool>(
      context: context,
      barrierDismissible: !_isSaving,
      builder: (dialogContext) => AlertDialog(
        // O AlertDialog calcula dimensões intrínsecas no Flutter Web.
        // Um ListView shrinkWrap/Flexible dentro do content não suporta
        // esse cálculo e fazia a revisão abrir apenas a barreira escura.
        // Deixamos o próprio diálogo cuidar da rolagem e renderizamos os
        // poucos itens selecionados como filhos normais da Column.
        scrollable: true,
        title: Text(retirando ? 'Revisar retirada' : 'Revisar carregamento'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FluxoDialog(origem: origem, destino: destino),
              const SizedBox(height: 16),
              Text(
                '$_totalProdutos produto(s) • $_totalUnidades unidade(s)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 10),
              for (var index = 0; index < selecionados.length; index++) ...[
                if (index > 0) const Divider(height: 1),
                Builder(
                  builder: (context) {
                    final item = selecionados[index];
                    final quantidade = _quantidades[item.skuId] ?? 0;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: _ProdutoImagem(
                        url: item.fotoUrl,
                        tamanho: 44,
                      ),
                      title: Text(
                        item.descricao,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(item.codigoInterno),
                      trailing: Text(
                        '$quantidade un.',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Esta confirmação registrará uma nova movimentação de estoque.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Voltar e ajustar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.check_circle_outline),
            label: Text(
              retirando ? 'Confirmar retirada' : 'Confirmar transferência',
            ),
          ),
        ],
      ),
    );

    return confirmar ?? false;
  }

  Future<void> _confirmarETransferir({
    required String orgId,
    required String usuarioId,
    required String vendedorId,
    required String vendedorNome,
    required List<_ItemMovimentacao> itens,
  }) async {
    if (_isSaving) return;

    final selecionados = itens
        .where((item) => (_quantidades[item.skuId] ?? 0) > 0)
        .toList();

    if (selecionados.isEmpty) {
      setState(() => _errorMessage = 'Selecione pelo menos um produto.');
      return;
    }

    for (final item in selecionados) {
      final quantidade = _quantidades[item.skuId] ?? 0;
      if (quantidade > item.disponivel) {
        setState(() {
          _errorMessage =
          '${item.descricao} possui somente ${item.disponivel} unidade(s) '
              'disponíveis na origem.';
        });
        return;
      }
    }

    final confirmou = await _mostrarRevisao(
      vendedorNome: vendedorNome,
      selecionados: selecionados,
    );
    if (!confirmou || !mounted) return;

    final localVendedor = LocalEstoque.vendedor(vendedorId);
    final origem = _modo == _ModoMovimentacao.carregar
        ? LocalEstoque.central
        : localVendedor;
    final destino = _modo == _ModoMovimentacao.carregar
        ? localVendedor
        : LocalEstoque.central;
    final concluidos = <String>[];
    final totalUnidadesMovimentadas = _totalUnidades;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      for (final item in selecionados) {
        final quantidade = _quantidades[item.skuId] ?? 0;
        await ref.read(estoqueRepositoryProvider).registrarMovimento(
          orgId: orgId,
          // No domínio atual, produtoId armazena o ID do SKU.
          produtoId: item.skuId,
          quantidade: quantidade,
          origem: origem,
          destino: destino,
          motivo: MovimentoMotivo.transferencia,
          usuarioId: usuarioId,
          custoUnitarioCentavosNoMomento: item.custoUnitarioCentavos,
        );
        concluidos.add(item.skuId);
      }

      if (!mounted) return;
      final verbo = _modo == _ModoMovimentacao.carregar
          ? 'enviadas para a carga de $vendedorNome'
          : 'devolvidas ao estoque central';

      setState(() => _quantidades.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$totalUnidadesMovimentadas unidade(s) $verbo com sucesso.',
          ),
        ),
      );
    } catch (error, stack) {
      debugPrint('Erro ao movimentar carga: $error\n$stack');
      if (!mounted) return;

      // Como o repositório atual registra um SKU por chamada, uma falha pode
      // acontecer depois de alguns itens já terem sido movimentados. Removemos
      // da seleção somente os concluídos e informamos claramente a situação.
      setState(() {
        for (final skuId in concluidos) {
          _quantidades.remove(skuId);
        }
        _errorMessage = concluidos.isEmpty
            ? 'Não foi possível concluir a movimentação. Confira os saldos e '
            'tente novamente.'
            : '${concluidos.length} item(ns) foram movimentados, mas a operação '
            'não terminou. Os itens restantes continuam selecionados.';
      });
    } finally {
      ref.invalidate(
        saldosDoLocalProvider(
          (orgId: orgId, localId: LocalEstoque.central),
        ),
      );
      ref.invalidate(
        saldosDoLocalProvider((orgId: orgId, localId: localVendedor)),
      );
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final usuarioAsync = ref.watch(appUserProvider);
    final usuariosAsync = ref.watch(usuariosListProvider);

    if ((usuarioAsync.isLoading && usuarioAsync.value == null) ||
        (usuariosAsync.isLoading && usuariosAsync.value == null)) {
      return const _EstadoCarregandoScaffold();
    }

    if (usuarioAsync.hasError || usuariosAsync.hasError) {
      return _EstadoErroScaffold(
        mensagem: 'Não foi possível carregar os usuários.',
        onTentarNovamente: () {
          ref.invalidate(appUserProvider);
          ref.invalidate(usuariosListProvider);
        },
      );
    }

    final usuario = usuarioAsync.value;
    if (usuario == null || usuario.orgId.isEmpty) {
      return const _SessaoInvalidaScaffold();
    }

    final vendedores = <_VendedorOpcao>[
      for (final item in usuariosAsync.value ?? const [])
        _VendedorOpcao(id: item.uid, nome: item.nome),
    ];
    if (!vendedores.any((item) => item.id == usuario.uid)) {
      vendedores.add(_VendedorOpcao(id: usuario.uid, nome: usuario.nome));
    }
    vendedores.sort(
          (a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()),
    );

    final vendedorId = _vendedorSelecionadoId ?? usuario.uid;
    final vendedor = vendedores.firstWhere(
          (item) => item.id == vendedorId,
      orElse: () => _VendedorOpcao(id: usuario.uid, nome: usuario.nome),
    );
    final localVendedor = LocalEstoque.vendedor(vendedor.id);
    final localOrigem = _modo == _ModoMovimentacao.carregar
        ? LocalEstoque.central
        : localVendedor;
    final saldosProvider = saldosDoLocalProvider(
      (orgId: usuario.orgId, localId: localOrigem),
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
      return const _EstadoCarregandoScaffold();
    }

    if (saldosAsync.hasError || skusAsync.hasError || produtosAsync.hasError) {
      return _EstadoErroScaffold(
        mensagem: 'Não foi possível carregar os saldos disponíveis.',
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
    final skusPorId = {
      for (final sku in skus)
        if (sku.id != null) sku.id!: sku,
    };
    final produtosPorId = {
      for (final produto in produtos)
        if (produto.id != null) produto.id!: produto,
    };

    final itens = <_ItemMovimentacao>[];
    for (final saldo in saldos) {
      if (saldo.quantidade <= 0) continue;
      final sku = skusPorId[saldo.produtoId];
      if (sku == null || sku.id == null || sku.status != SkuStatus.active) {
        continue;
      }
      final produto = produtosPorId[sku.produtoId];
      final nomeProduto = produto?.descricao.trim();
      final variacao = sku.variacao?.trim();
      final descricao = nomeProduto == null || nomeProduto.isEmpty
          ? 'Produto não identificado'
          : variacao != null && variacao.isNotEmpty
          ? '$nomeProduto — $variacao'
          : nomeProduto;

      itens.add(
        _ItemMovimentacao(
          skuId: sku.id!,
          codigoInterno: sku.codigoInterno,
          codigoBarras: sku.codigoBarras,
          descricao: descricao,
          categoria: produto?.categoria ?? 'Sem categoria',
          fotoUrl: produto?.fotoUrl,
          disponivel: saldo.quantidade,
          custoUnitarioCentavos: sku.custoInicialCentavos,
        ),
      );
    }
    itens.sort(
          (a, b) => a.descricao.toLowerCase().compareTo(b.descricao.toLowerCase()),
    );

    return LayoutBuilder(
      builder: (context, pageConstraints) {
        // Usa a largura realmente entregue pelo AppShell, já descontando o
        // menu lateral no web.
        final exibirBarraMobile =
            pageConstraints.maxWidth < _kBreakpointDesktop;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Movimentar carga'),
            actions: [
              IconButton(
                tooltip: 'Escanear produto',
                onPressed: _isSaving ? null : _escanearCodigo,
                icon: const Icon(Icons.qr_code_scanner_rounded),
              ),
              IconButton(
                tooltip: 'Atualizar',
                onPressed: carregando
                    ? null
                    : () {
                  ref.invalidate(saldosProvider);
                  ref.invalidate(skusListProvider);
                  ref.invalidate(produtosListProvider);
                },
                icon: const Icon(Icons.refresh_rounded),
              ),
              const SizedBox(width: 8),
            ],
          ),
          bottomNavigationBar: exibirBarraMobile
              ? _BarraAcaoMobile(
            modo: _modo,
            totalUnidades: _totalUnidades,
            salvando: _isSaving,
            onPressed: () {
              _confirmarETransferir(
                orgId: usuario.orgId,
                usuarioId: usuario.uid,
                vendedorId: vendedor.id,
                vendedorNome: vendedor.nome,
                itens: itens,
              );
            },
          )
              : null,
          body: _buildConteudo(
            context,
            vendedores: vendedores,
            vendedor: vendedor,
            itens: itens,
            orgId: usuario.orgId,
            usuarioId: usuario.uid,
          ),
        );
      },
    );
  }

  Widget _buildConteudo(
      BuildContext context, {
        required List<_VendedorOpcao> vendedores,
        required _VendedorOpcao vendedor,
        required List<_ItemMovimentacao> itens,
        required String orgId,
        required String usuarioId,
      }) {
    final termo = _termoBusca.trim().toLowerCase();
    final filtrados = itens.where((item) {
      if (termo.isEmpty) return true;
      return item.descricao.toLowerCase().contains(termo) ||
          item.codigoInterno.toLowerCase().contains(termo) ||
          item.categoria.toLowerCase().contains(termo) ||
          (item.codigoBarras?.toLowerCase().contains(termo) ?? false);
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= _kBreakpointDesktop;
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 28),
          child: ResponsiveCenter(
            maxWidth: _kMaxWidthConteudo,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Controle os produtos enviados e devolvidos pelos vendedores',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Selecione a operação, confira a origem e revise tudo antes de movimentar o estoque.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  _SeletorModo(
                    modo: _modo,
                    bloqueado: _isSaving,
                    onChanged: _alterarModo,
                  ),
                  const SizedBox(height: 16),
                  _FluxoMovimentacao(
                    modo: _modo,
                    vendedorNome: vendedor.nome,
                  ),
                  const SizedBox(height: 16),
                  _SeletorVendedor(
                    vendedores: vendedores,
                    selecionadoId: vendedor.id,
                    bloqueado: _isSaving,
                    onChanged: _alterarVendedor,
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    _BannerErro(mensagem: _errorMessage!),
                  ],
                  const SizedBox(height: 16),
                  if (desktop)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _PainelProdutos(
                            modo: _modo,
                            itens: filtrados,
                            totalSemFiltro: itens.length,
                            buscaController: _buscaController,
                            termoBusca: _termoBusca,
                            quantidades: _quantidades,
                            bloqueado: _isSaving,
                            onBuscaChanged: (value) {
                              setState(() => _termoBusca = value);
                            },
                            onLimparBusca: () {
                              setState(() {
                                _buscaController.clear();
                                _termoBusca = '';
                              });
                            },
                            onEscanear: _escanearCodigo,
                            onQuantidadeChanged: _alterarQuantidade,
                            onEditarQuantidade: _editarQuantidade,
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 320,
                          child: _ResumoMovimentacao(
                            modo: _modo,
                            vendedorNome: vendedor.nome,
                            itens: itens,
                            quantidades: _quantidades,
                            salvando: _isSaving,
                            onLimpar: _limparSelecao,
                            onRevisar: () {
                              _confirmarETransferir(
                                orgId: orgId,
                                usuarioId: usuarioId,
                                vendedorId: vendedor.id,
                                vendedorNome: vendedor.nome,
                                itens: itens,
                              );
                            },
                          ),
                        ),
                      ],
                    )
                  else
                    _PainelProdutos(
                      modo: _modo,
                      itens: filtrados,
                      totalSemFiltro: itens.length,
                      buscaController: _buscaController,
                      termoBusca: _termoBusca,
                      quantidades: _quantidades,
                      bloqueado: _isSaving,
                      onBuscaChanged: (value) {
                        setState(() => _termoBusca = value);
                      },
                      onLimparBusca: () {
                        setState(() {
                          _buscaController.clear();
                          _termoBusca = '';
                        });
                      },
                      onEscanear: _escanearCodigo,
                      onQuantidadeChanged: _alterarQuantidade,
                      onEditarQuantidade: _editarQuantidade,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _VendedorOpcao {
  final String id;
  final String nome;

  const _VendedorOpcao({required this.id, required this.nome});
}

class _ItemMovimentacao {
  final String skuId;
  final String codigoInterno;
  final String? codigoBarras;
  final String descricao;
  final String categoria;
  final String? fotoUrl;
  final int disponivel;
  final int custoUnitarioCentavos;

  const _ItemMovimentacao({
    required this.skuId,
    required this.codigoInterno,
    required this.codigoBarras,
    required this.descricao,
    required this.categoria,
    required this.fotoUrl,
    required this.disponivel,
    required this.custoUnitarioCentavos,
  });
}

class _SeletorModo extends StatelessWidget {
  final _ModoMovimentacao modo;
  final bool bloqueado;
  final ValueChanged<_ModoMovimentacao> onChanged;

  const _SeletorModo({
    required this.modo,
    required this.bloqueado,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compacto = constraints.maxWidth < 600;
        final carregar = _OpcaoModo(
          selecionado: modo == _ModoMovimentacao.carregar,
          icon: Icons.local_shipping_outlined,
          titulo: compacto ? 'Carregar' : 'Carregar vendedor',
          subtitulo: 'Central → vendedor',
          onTap: bloqueado
              ? null
              : () => onChanged(_ModoMovimentacao.carregar),
        );
        final retirar = _OpcaoModo(
          selecionado: modo == _ModoMovimentacao.retirar,
          icon: Icons.assignment_return_outlined,
          titulo: compacto ? 'Retirar' : 'Retirar da carga',
          subtitulo: 'Vendedor → central',
          onTap: bloqueado
              ? null
              : () => onChanged(_ModoMovimentacao.retirar),
        );

        return compacto
            ? Row(
          children: [
            Expanded(child: carregar),
            const SizedBox(width: 10),
            Expanded(child: retirar),
          ],
        )
            : Row(
          children: [
            Expanded(child: carregar),
            const SizedBox(width: 12),
            Expanded(child: retirar),
          ],
        );
      },
    );
  }
}

class _OpcaoModo extends StatelessWidget {
  final bool selecionado;
  final IconData icon;
  final String titulo;
  final String subtitulo;
  final VoidCallback? onTap;

  const _OpcaoModo({
    required this.selecionado,
    required this.icon,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cor = selecionado
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(
              color: selecionado ? cor : theme.dividerColor,
              width: selecionado ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, color: cor, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: selecionado ? cor : null,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FluxoMovimentacao extends StatelessWidget {
  final _ModoMovimentacao modo;
  final String vendedorNome;

  const _FluxoMovimentacao({
    required this.modo,
    required this.vendedorNome,
  });

  @override
  Widget build(BuildContext context) {
    final carregando = modo == _ModoMovimentacao.carregar;
    final origem = carregando ? 'Estoque central' : 'Carga de $vendedorNome';
    final destino = carregando ? 'Carga de $vendedorNome' : 'Estoque central';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _PontoFluxo(
                icon: carregando
                    ? Icons.warehouse_outlined
                    : Icons.person_outline,
                label: 'Origem',
                valor: origem,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Icon(
                Icons.arrow_forward_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            Expanded(
              child: _PontoFluxo(
                icon: carregando
                    ? Icons.person_outline
                    : Icons.warehouse_outlined,
                label: 'Destino',
                valor: destino,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PontoFluxo extends StatelessWidget {
  final IconData icon;
  final String label;
  final String valor;

  const _PontoFluxo({
    required this.icon,
    required this.label,
    required this.valor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: theme.colorScheme.primary, size: 21),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelSmall),
              Text(
                valor,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SeletorVendedor extends StatelessWidget {
  final List<_VendedorOpcao> vendedores;
  final String selecionadoId;
  final bool bloqueado;
  final ValueChanged<String?> onChanged;

  const _SeletorVendedor({
    required this.vendedores,
    required this.selecionadoId,
    required this.bloqueado,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: DropdownButtonFormField<String>(
        key: ValueKey(selecionadoId),
        initialValue: selecionadoId,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Vendedor',
          prefixIcon: Icon(Icons.person_outline),
        ),
        items: vendedores
            .map(
              (vendedor) => DropdownMenuItem(
            value: vendedor.id,
            child: Text(
              vendedor.nome,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
            .toList(),
        onChanged: bloqueado ? null : onChanged,
      ),
    );
  }
}

class _PainelProdutos extends StatelessWidget {
  final _ModoMovimentacao modo;
  final List<_ItemMovimentacao> itens;
  final int totalSemFiltro;
  final TextEditingController buscaController;
  final String termoBusca;
  final Map<String, int> quantidades;
  final bool bloqueado;
  final ValueChanged<String> onBuscaChanged;
  final VoidCallback onLimparBusca;
  final VoidCallback onEscanear;
  final void Function(_ItemMovimentacao, int) onQuantidadeChanged;
  final ValueChanged<_ItemMovimentacao> onEditarQuantidade;

  const _PainelProdutos({
    required this.modo,
    required this.itens,
    required this.totalSemFiltro,
    required this.buscaController,
    required this.termoBusca,
    required this.quantidades,
    required this.bloqueado,
    required this.onBuscaChanged,
    required this.onLimparBusca,
    required this.onEscanear,
    required this.onQuantidadeChanged,
    required this.onEditarQuantidade,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: buscaController,
              enabled: !bloqueado,
              onChanged: onBuscaChanged,
              decoration: InputDecoration(
                hintText: 'Buscar produto, SKU ou código de barras',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: termoBusca.isNotEmpty
                    ? IconButton(
                  tooltip: 'Limpar busca',
                  onPressed: onLimparBusca,
                  icon: const Icon(Icons.close),
                )
                    : IconButton(
                  tooltip: 'Escanear produto',
                  onPressed: onEscanear,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                ),
              ),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final tabela = constraints.maxWidth >= 680;
                if (totalSemFiltro == 0) {
                  return _ListaVazia(modo: modo);
                }
                if (itens.isEmpty) {
                  return _NenhumResultado(onLimpar: onLimparBusca);
                }
                if (!tabela) {
                  return Column(
                    children: [
                      for (var i = 0; i < itens.length; i++) ...[
                        if (i > 0) const SizedBox(height: 10),
                        _ProdutoMovimentacaoCard(
                          item: itens[i],
                          quantidade: quantidades[itens[i].skuId] ?? 0,
                          bloqueado: bloqueado,
                          onChanged: (quantidade) =>
                              onQuantidadeChanged(itens[i], quantidade),
                          onEditar: () => onEditarQuantidade(itens[i]),
                        ),
                      ],
                    ],
                  );
                }

                return Column(
                  children: [
                    const _CabecalhoProdutos(),
                    const Divider(height: 1),
                    for (var i = 0; i < itens.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _ProdutoMovimentacaoLinha(
                        item: itens[i],
                        quantidade: quantidades[itens[i].skuId] ?? 0,
                        bloqueado: bloqueado,
                        onChanged: (quantidade) =>
                            onQuantidadeChanged(itens[i], quantidade),
                        onEditar: () => onEditarQuantidade(itens[i]),
                      ),
                    ],
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Mostrando ${itens.length} de $totalSemFiltro produto(s)',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CabecalhoProdutos extends StatelessWidget {
  const _CabecalhoProdutos();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w700,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(flex: 5, child: Text('Produto', style: style)),
          Expanded(flex: 2, child: Text('SKU', style: style)),
          Expanded(
            flex: 2,
            child: Text(
              'Disponível na origem',
              textAlign: TextAlign.center,
              style: style,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Quantidade',
              textAlign: TextAlign.center,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProdutoMovimentacaoLinha extends StatelessWidget {
  final _ItemMovimentacao item;
  final int quantidade;
  final bool bloqueado;
  final ValueChanged<int> onChanged;
  final VoidCallback onEditar;

  const _ProdutoMovimentacaoLinha({
    required this.item,
    required this.quantidade,
    required this.bloqueado,
    required this.onChanged,
    required this.onEditar,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
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
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.categoria,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              item.codigoInterno,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${item.disponivel} un.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Center(
              child: _SeletorQuantidade(
                valor: quantidade,
                maximo: item.disponivel,
                bloqueado: bloqueado,
                onChanged: onChanged,
                onEditar: onEditar,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProdutoMovimentacaoCard extends StatelessWidget {
  final _ItemMovimentacao item;
  final int quantidade;
  final bool bloqueado;
  final ValueChanged<int> onChanged;
  final VoidCallback onEditar;

  const _ProdutoMovimentacaoCard({
    required this.item,
    required this.quantidade,
    required this.bloqueado,
    required this.onChanged,
    required this.onEditar,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                    const SizedBox(height: 5),
                    Text(
                      'Disponível na origem: ${item.disponivel} un.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: _SeletorQuantidade(
              valor: quantidade,
              maximo: item.disponivel,
              bloqueado: bloqueado,
              onChanged: onChanged,
              onEditar: onEditar,
            ),
          ),
        ],
      ),
    );
  }
}

class _SeletorQuantidade extends StatelessWidget {
  final int valor;
  final int maximo;
  final bool bloqueado;
  final ValueChanged<int> onChanged;
  final VoidCallback onEditar;

  const _SeletorQuantidade({
    required this.valor,
    required this.maximo,
    required this.bloqueado,
    required this.onChanged,
    required this.onEditar,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Diminuir',
            visualDensity: VisualDensity.compact,
            onPressed: bloqueado || valor == 0
                ? null
                : () => onChanged(valor - 1),
            icon: const Icon(Icons.remove, size: 18),
          ),
          InkWell(
            onTap: bloqueado ? null : onEditar,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 34),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  '$valor',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: valor > 0 ? theme.colorScheme.primary : null,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Aumentar',
            visualDensity: VisualDensity.compact,
            onPressed: bloqueado || valor >= maximo
                ? null
                : () => onChanged(valor + 1),
            icon: const Icon(Icons.add, size: 18),
          ),
        ],
      ),
    );
  }
}

class _ResumoMovimentacao extends StatelessWidget {
  final _ModoMovimentacao modo;
  final String vendedorNome;
  final List<_ItemMovimentacao> itens;
  final Map<String, int> quantidades;
  final bool salvando;
  final VoidCallback onLimpar;
  final VoidCallback onRevisar;

  const _ResumoMovimentacao({
    required this.modo,
    required this.vendedorNome,
    required this.itens,
    required this.quantidades,
    required this.salvando,
    required this.onLimpar,
    required this.onRevisar,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selecionados = itens
        .where((item) => (quantidades[item.skuId] ?? 0) > 0)
        .toList();
    final totalUnidades = selecionados.fold<int>(
      0,
          (total, item) => total + (quantidades[item.skuId] ?? 0),
    );
    final retirando = modo == _ModoMovimentacao.retirar;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    retirando ? 'Resumo da retirada' : 'Resumo da carga',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (selecionados.isNotEmpty)
                  IconButton(
                    tooltip: 'Limpar seleção',
                    onPressed: salvando ? null : onLimpar,
                    icon: const Icon(Icons.delete_sweep_outlined),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ResumoNumero(
                    valor: '${selecionados.length}',
                    label: 'produtos',
                    icon: Icons.inventory_2_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ResumoNumero(
                    valor: '$totalUnidades',
                    label: 'unidades',
                    icon: Icons.widgets_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text('Destino', style: theme.textTheme.labelSmall),
            const SizedBox(height: 4),
            Text(
              retirando ? 'Estoque central' : 'Carga de $vendedorNome',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Divider(height: 24),
            if (selecionados.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Selecione as quantidades dos produtos para montar a movimentação.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              )
            else
              for (final item in selecionados) ...[
                _ResumoItem(
                  item: item,
                  quantidade: quantidades[item.skuId] ?? 0,
                ),
                const SizedBox(height: 10),
              ],
            const SizedBox(height: 6),
            FilledButton.icon(
              onPressed: salvando || selecionados.isEmpty ? null : onRevisar,
              icon: salvando
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Icon(Icons.fact_check_outlined),
              label: Text(
                salvando
                    ? 'Movimentando...'
                    : retirando
                    ? 'Revisar retirada'
                    : 'Revisar transferência',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResumoNumero extends StatelessWidget {
  final String valor;
  final String label;
  final IconData icon;

  const _ResumoNumero({
    required this.valor,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  valor,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(label, style: theme.textTheme.labelSmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResumoItem extends StatelessWidget {
  final _ItemMovimentacao item;
  final int quantidade;

  const _ResumoItem({required this.item, required this.quantidade});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        _ProdutoImagem(url: item.fotoUrl, tamanho: 38),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.descricao,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(item.codigoInterno, style: theme.textTheme.labelSmall),
            ],
          ),
        ),
        Text(
          '$quantidade un.',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _FluxoDialog extends StatelessWidget {
  final String origem;
  final String destino;

  const _FluxoDialog({required this.origem, required this.destino});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              origem,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(
              Icons.arrow_forward_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          Expanded(
            child: Text(
              destino,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _BarraAcaoMobile extends StatelessWidget {
  final _ModoMovimentacao modo;
  final int totalUnidades;
  final bool salvando;
  final VoidCallback onPressed;

  const _BarraAcaoMobile({
    required this.modo,
    required this.totalUnidades,
    required this.salvando,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: theme.dividerColor)),
          ),
          // heightFactor impede a barra de ocupar toda a altura da página.
          child: Align(
            alignment: Alignment.center,
            heightFactor: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: salvando || totalUnidades == 0 ? null : onPressed,
                  icon: salvando
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Icon(Icons.fact_check_outlined),
                  label: Text(
                    salvando
                        ? 'Movimentando...'
                        : 'Revisar • $totalUnidades unidade(s)',
                  ),
                ),
              ),
            ),
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
          return const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
      )
          : fallback(),
    );
  }
}

class _BannerErro extends StatelessWidget {
  final String mensagem;

  const _BannerErro({required this.mensagem});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cor = theme.colorScheme.error;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.1),
        border: Border.all(color: cor.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: cor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              mensagem,
              style: theme.textTheme.bodyMedium?.copyWith(color: cor),
            ),
          ),
        ],
      ),
    );
  }
}

class _ListaVazia extends StatelessWidget {
  final _ModoMovimentacao modo;

  const _ListaVazia({required this.modo});

  @override
  Widget build(BuildContext context) {
    final retirando = modo == _ModoMovimentacao.retirar;
    return _EstadoLista(
      icon: Icons.inventory_2_outlined,
      titulo: retirando
          ? 'Este vendedor não possui produtos na carga'
          : 'O estoque central não possui produtos disponíveis',
      mensagem: retirando
          ? 'Selecione outro vendedor ou confira se a carga já foi devolvida.'
          : 'Registre uma entrada no estoque central antes de carregar o vendedor.',
    );
  }
}

class _NenhumResultado extends StatelessWidget {
  final VoidCallback onLimpar;

  const _NenhumResultado({required this.onLimpar});

  @override
  Widget build(BuildContext context) {
    return _EstadoLista(
      icon: Icons.search_off_rounded,
      titulo: 'Nenhum produto encontrado',
      mensagem: 'Confira o termo pesquisado ou limpe a busca.',
      acao: TextButton.icon(
        onPressed: onLimpar,
        icon: const Icon(Icons.close),
        label: const Text('Limpar busca'),
      ),
    );
  }
}

class _EstadoLista extends StatelessWidget {
  final IconData icon;
  final String titulo;
  final String mensagem;
  final Widget? acao;

  const _EstadoLista({
    required this.icon,
    required this.titulo,
    required this.mensagem,
    this.acao,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 42),
      child: Column(
        children: [
          Icon(icon, size: 42, color: theme.colorScheme.primary),
          const SizedBox(height: 14),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            mensagem,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          if (acao != null) ...[
            const SizedBox(height: 12),
            acao!,
          ],
        ],
      ),
    );
  }
}

class _EstadoCarregandoScaffold extends StatelessWidget {
  const _EstadoCarregandoScaffold();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Movimentar carga')),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _EstadoErroScaffold extends StatelessWidget {
  final String mensagem;
  final VoidCallback onTentarNovamente;

  const _EstadoErroScaffold({
    required this.mensagem,
    required this.onTentarNovamente,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Movimentar carga')),
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
              const SizedBox(height: 14),
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
      appBar: AppBar(title: const Text('Movimentar carga')),
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
              const SizedBox(height: 14),
              Text(
                'Não foi possível identificar sua organização.',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 5),
              Text(
                'Saia e entre novamente ou fale com um administrador.',
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
