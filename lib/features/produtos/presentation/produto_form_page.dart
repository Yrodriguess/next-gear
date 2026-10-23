import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/current_org_provider.dart';
import '../../../core/utils/gtin_validator.dart';
import '../../../core/utils/money_input_formatter.dart';
import '../../../core/widgets/barcode_scanner_page.dart';
import '../../../core/widgets/produto_photo_picker.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../estoque/domain/stock_movement.dart';
import '../../estoque/presentation/estoque_providers.dart';
import '../data/produto_cadastro_service.dart';
import '../data/produto_edicao_service.dart';
import '../domain/produto.dart';
import '../domain/sku.dart';
import 'produto_providers.dart';

/// Breakpoints locais da tela. Eles consideram a largura disponível para o
/// conteúdo, não a largura total do dispositivo (no web pode existir menu
/// lateral ocupando parte da janela).
const double _kBreakpointCamposCompactos = 620;
const double _kBreakpointLayoutDesktop = 920;
const double _kLarguraPainelLateral = 320;

const int _maxDescricao = 150;
const int _maxVariacao = 80;
const int _maxModelo = 80;
const int _maxFabricante = 120;

class ProdutoFormPage extends ConsumerStatefulWidget {
  /// Quando produtoId e skuId vêm preenchidos, a tela abre em modo
  /// edição — carrega os dados existentes e atualiza em vez de criar.
  /// Os dois têm que vir juntos: não existe edição parcial só de
  /// Produto ou só de SKU nesta tela.
  final String? produtoId;
  final String? skuId;

  const ProdutoFormPage({
    super.key,
    this.produtoId,
    this.skuId,
  }) : assert(
  (produtoId == null) == (skuId == null),
  'produtoId e skuId precisam vir os dois nulos (criação) ou os '
      'dois preenchidos (edição) — nunca só um dos dois.',
  );

  @override
  ConsumerState<ProdutoFormPage> createState() =>
      _ProdutoFormPageState();
}

class _ProdutoFormPageState
    extends ConsumerState<ProdutoFormPage> {
  final _formKey = GlobalKey<FormState>();

  bool get _isEdicao =>
      widget.produtoId != null &&
          widget.skuId != null;

  // =========================================================
  // PRODUTO
  // =========================================================

  final _descricaoController =
  TextEditingController();

  final _modeloController =
  TextEditingController();

  final _fabricanteController =
  TextEditingController();

  String? _categoriaSelecionada;

  Uint8List? _fotoBytes;

  String? _fotoUrlExistente;

  bool _removerFotoExistente = false;

  // =========================================================
  // PRIMEIRO SKU / SKU EM EDIÇÃO
  // =========================================================

  final _variacaoController =
  TextEditingController();

  final _codigoBarrasController =
  TextEditingController();

  final _codigoInternoController =
  TextEditingController();

  final _custoController =
  TextEditingController(
    text: formatarCentavos(0),
  );

  final _precoController =
  TextEditingController(
    text: formatarCentavos(0),
  );

  final _estoqueMinimoController =
  TextEditingController(
    text: '0',
  );

  // =========================================================
  // CAMPOS PRESERVADOS NA EDIÇÃO
  // =========================================================

  SkuStatus _statusOriginal =
      SkuStatus.active;

  String? _codigoBarrasOriginal;

  int _precoVendaOriginalCentavos = 0;

  int _custoInicialOriginalCentavos = 0;

  int _custoMedioOriginalCentavos = 0;

  int _custoUltimaCompraOriginalCentavos = 0;

  bool _prefilled = false;

  bool _isSaving = false;

  bool _dirty = false;

  String? _errorMessage;

  // =========================================================
  // DISPOSE
  // =========================================================

  @override
  void dispose() {
    _descricaoController.dispose();
    _modeloController.dispose();
    _fabricanteController.dispose();

    _variacaoController.dispose();
    _codigoBarrasController.dispose();
    _codigoInternoController.dispose();

    _custoController.dispose();
    _precoController.dispose();

    _estoqueMinimoController.dispose();

    super.dispose();
  }

  // =========================================================
  // ALTERAÇÕES
  // =========================================================

  void _marcarAlterado() {
    // O rebuild também mantém o resumo lateral sincronizado
    // com o formulário.
    setState(() {
      _dirty = true;
      _errorMessage = null;
    });
  }

  // =========================================================
  // PREENCHIMENTO NA EDIÇÃO
  // =========================================================

  void _prefillSeNecessario(
      Produto produto,
      Sku sku,
      ) {
    if (_prefilled) return;

    _descricaoController.text =
        produto.descricao;

    _modeloController.text =
        produto.modelo ?? '';

    _fabricanteController.text =
        produto.fabricante ?? '';

    _categoriaSelecionada =
        produto.categoria;

    _fotoUrlExistente =
        produto.fotoUrl;

    _variacaoController.text =
        sku.variacao ?? '';

    _codigoBarrasController.text =
        sku.codigoBarras ?? '';

    _codigoInternoController.text =
        sku.codigoInterno;

    _custoController.text =
        formatarCentavos(
          sku.custoInicialCentavos,
        );

    _precoController.text =
        formatarCentavos(
          sku.precoVendaCentavos,
        );

    _estoqueMinimoController.text =
    '${sku.estoqueMinimo}';

    _statusOriginal =
        sku.status;

    _codigoBarrasOriginal =
        sku.codigoBarras;

    _precoVendaOriginalCentavos =
        sku.precoVendaCentavos;

    _custoInicialOriginalCentavos =
        sku.custoInicialCentavos;

    _custoMedioOriginalCentavos =
        sku.custoMedioCentavos;

    _custoUltimaCompraOriginalCentavos =
        sku.custoUltimaCompraCentavos;

    _prefilled = true;
  }

  // =========================================================
  // FOTO
  // =========================================================

  AcaoFoto _acaoFoto() {
    if (_removerFotoExistente) {
      return AcaoFoto.remover;
    }

    if (_fotoBytes != null) {
      return AcaoFoto.trocar;
    }

    return AcaoFoto.manter;
  }

  // =========================================================
  // SAÍDA / DESCARTE
  // =========================================================

  Future<bool> _confirmarDescarte() async {
    if (!_dirty) return true;

    final confirmar =
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) =>
          AlertDialog(
            title: const Text(
              'Descartar alterações?',
            ),
            content: const Text(
              'Você tem alterações não salvas. '
                  'Se sair agora, elas serão perdidas.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(
                    dialogContext,
                  ).pop(false);
                },
                child: const Text(
                  'Continuar editando',
                ),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(
                    dialogContext,
                  ).pop(true);
                },
                child: const Text(
                  'Descartar',
                ),
              ),
            ],
          ),
    );

    return confirmar ?? false;
  }

  Future<void> _solicitarSaida() async {
    if (_isSaving) return;

    final podeSair =
    await _confirmarDescarte();

    if (!podeSair || !mounted) {
      return;
    }

    // O PopScope precisa ser reconstruído permitindo
    // a saída antes do pop.
    setState(() {
      _dirty = false;
    });

    WidgetsBinding.instance
        .addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  // =========================================================
  // CATEGORIA
  // =========================================================

  Future<void> _novaCategoria(
      String orgId,
      ) async {
    final controller =
    TextEditingController();

    try {
      final nome =
      await showDialog<String>(
        context: context,
        builder: (dialogContext) =>
            StatefulBuilder(
              builder: (
                  context,
                  setDialogState,
                  ) {
                final podeAdicionar =
                    controller.text
                        .trim()
                        .isNotEmpty;

                return AlertDialog(
                  title: const Text(
                    'Nova categoria',
                  ),
                  content: ConstrainedBox(
                    constraints:
                    const BoxConstraints(
                      maxWidth: 420,
                    ),
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      textCapitalization:
                      TextCapitalization.words,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(
                          60,
                        ),
                      ],
                      decoration:
                      const InputDecoration(
                        labelText:
                        'Nome da categoria',
                      ),
                      onChanged: (_) {
                        setDialogState(() {});
                      },
                      onSubmitted: (v) {
                        if (v.trim().isNotEmpty) {
                          Navigator.of(
                            dialogContext,
                          ).pop(v);
                        }
                      },
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(
                          dialogContext,
                        ).pop();
                      },
                      child: const Text(
                        'Cancelar',
                      ),
                    ),
                    FilledButton(
                      onPressed: podeAdicionar
                          ? () {
                        Navigator.of(
                          dialogContext,
                        ).pop(
                          controller.text,
                        );
                      }
                          : null,
                      child: const Text(
                        'Adicionar',
                      ),
                    ),
                  ],
                );
              },
            ),
      );

      if (nome == null ||
          nome.trim().isEmpty) {
        return;
      }

      try {
        final nomeFinal = await ref
            .read(
          categoriaRepositoryProvider,
        )
            .criarSeNaoExistir(
          orgId,
          nome,
        );

        if (mounted) {
          setState(() {
            _categoriaSelecionada =
                nomeFinal;

            _dirty = true;

            _errorMessage = null;
          });
        }
      } catch (e) {
        debugPrint(
          'Erro ao criar categoria: $e',
        );

        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(
            const SnackBar(
              content: Text(
                'Não foi possível criar a categoria.',
              ),
            ),
          );
        }
      }
    } finally {
      controller.dispose();
    }
  }

  // =========================================================
  // SCANNER
  // =========================================================

  Future<void> _escanearCodigoBarras() async {
    final codigo =
    await Navigator.of(context)
        .push<String>(
      MaterialPageRoute(
        builder: (_) =>
        const BarcodeScannerPage(),
      ),
    );

    if (codigo != null && mounted) {
      setState(() {
        _codigoBarrasController.text =
            codigo.replaceAll(
              RegExp(r'[^0-9]'),
              '',
            );

        _dirty = true;
        _errorMessage = null;
      });
    }
  }

  // =========================================================
  // VALIDAÇÕES
  // =========================================================

  String? _validarDescricao(
      String? value,
      ) {
    final descricao =
        value?.trim() ?? '';

    if (descricao.isEmpty) {
      return 'Informe a descrição';
    }

    if (descricao.length < 2) {
      return 'Descrição muito curta';
    }

    return null;
  }

  String? _validarCodigoBarras(
      String? value,
      ) {
    final codigo =
        value?.trim() ?? '';

    if (codigo.isEmpty) {
      return null;
    }

    if (!gtinValido(codigo)) {
      return 'GTIN/EAN inválido — confira o código '
          '(8, 12, 13 ou 14 dígitos)';
    }

    return null;
  }

  String? _validarCodigoInterno(
      String? value,
      ) {
    final codigo =
        value?.trim() ?? '';

    if (codigo.isEmpty) {
      return 'Informe o código interno';
    }

    if (codigo.length != 13) {
      return 'O código deve ter 13 dígitos';
    }

    return null;
  }

  String? _validarPreco(
      String? value,
      ) {
    final centavos =
    centavosFromFormatted(
      value ?? '',
    );

    if (centavos <= 0) {
      return 'Informe um preço maior que zero';
    }

    return null;
  }

  String? _validarEstoqueMinimo(
      String? value,
      ) {
    final quantidade =
    int.tryParse(
      value ?? '',
    );

    if (quantidade == null ||
        quantidade < 0) {
      return 'Informe um número inteiro válido';
    }

    return null;
  }

  // =========================================================
  // SALVAR
  // =========================================================

  Future<void> _handleSave() async {
    if (_isSaving) return;

    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!
        .validate()) {
      return;
    }

    final orgId =
    ref.read(
      currentOrgIdProvider,
    );

    if (orgId == null) {
      setState(() {
        _errorMessage =
        'Sessão inválida. Faça login novamente.';
      });

      return;
    }

    final categoria =
        _categoriaSelecionada;

    if (categoria == null ||
        categoria.isEmpty) {
      setState(() {
        _errorMessage =
        'Selecione ou cadastre uma categoria.';
      });

      return;
    }

    final precoCentavos =
    centavosFromFormatted(
      _precoController.text,
    );

    final codigoBarras =
    _codigoBarrasController.text
        .trim();

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      // =====================================================
      // GTIN / EAN DUPLICADO
      // =====================================================

      if (codigoBarras.isNotEmpty) {
        final jaExiste =
        await ref
            .read(
          skuRepositoryProvider,
        )
            .existeCodigoBarras(
          orgId,
          codigoBarras,
          excluirSkuId: _isEdicao
              ? widget.skuId
              : null,
        );

        if (!mounted) return;

        if (jaExiste) {
          setState(() {
            _errorMessage =
            'Já existe um produto cadastrado '
                'com esse GTIN/EAN.';

            _isSaving = false;
          });

          return;
        }
      }

      // =====================================================
      // PRODUTO
      // =====================================================

      final produto = Produto(
        id: _isEdicao
            ? widget.produtoId
            : null,
        orgId: orgId,
        descricao:
        _descricaoController.text
            .trim(),
        categoria: categoria,

        modelo:
        _modeloController.text
            .trim()
            .isEmpty
            ? null
            : _modeloController.text
            .trim(),

        fabricante:
        _fabricanteController.text
            .trim()
            .isEmpty
            ? null
            : _fabricanteController
            .text
            .trim(),

        fotoUrl: _isEdicao
            ? _fotoUrlExistente
            : null,
      );

      // Custo inicial não é editável na tela
      // em modo edição.
      final custoCentavos =
      _isEdicao
          ? _custoInicialOriginalCentavos
          : centavosFromFormatted(
        _custoController.text,
      );

      // =====================================================
      // SKU
      // =====================================================

      final sku = Sku(
        id: _isEdicao
            ? widget.skuId
            : null,

        orgId: orgId,

        produtoId: _isEdicao
            ? widget.produtoId!
            : '',

        codigoInterno: _isEdicao
            ? _codigoInternoController.text.trim()
            : '',

        codigoBarras:
        codigoBarras.isEmpty
            ? null
            : codigoBarras,

        variacao:
        _variacaoController.text
            .trim()
            .isEmpty
            ? null
            : _variacaoController
            .text
            .trim(),

        custoInicialCentavos:
        custoCentavos,

        custoMedioCentavos:
        _isEdicao
            ? _custoMedioOriginalCentavos
            : custoCentavos,

        custoUltimaCompraCentavos:
        _isEdicao
            ? _custoUltimaCompraOriginalCentavos
            : custoCentavos,

        precoVendaCentavos:
        precoCentavos,

        estoqueMinimo:
        int.tryParse(
          _estoqueMinimoController
              .text,
        ) ??
            0,

        // REGRA DEFINITIVA NEXT GEAR:
        // estoque controlado exclusivamente
        // por quantidade.
        trackingMode:
        TrackingMode.quantity,

        status: _isEdicao
            ? _statusOriginal
            : SkuStatus.active,
      );

      // =====================================================
      // EDIÇÃO / CADASTRO
      // =====================================================

      if (_isEdicao) {
        await ref
            .read(
          produtoEdicaoServiceProvider,
        )
            .atualizar(
          produto: produto,
          sku: sku,
          acaoFoto: _acaoFoto(),
          fotoBytesNovos:
          _fotoBytes,
          codigoBarrasAntigo:
          _codigoBarrasOriginal,
          precoVendaAntigoCentavos:
          _precoVendaOriginalCentavos,
        );
      } else {
        await ref
            .read(
          produtoCadastroServiceProvider,
        )
            .criar(
          produto: produto,
          primeiroSku: sku,
          fotoBytes:
          _fotoBytes,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text(
              _isEdicao
                  ? 'Produto atualizado!'
                  : 'Produto cadastrado!',
            ),
          ),
        );

        setState(() {
          _dirty = false;
        });

        WidgetsBinding.instance
            .addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context)
                .pop(true);
          }
        });
      }
    } on GtinDuplicadoException catch (e) {
      debugPrint(
        'Cadastro rejeitado: $e',
      );

      if (mounted) {
        setState(() {
          _errorMessage =
          'Esse GTIN/EAN já está cadastrado '
              'nesta organização.';
        });
      }
    } catch (e, stack) {
      debugPrint(
        'Erro ao salvar produto: '
            '$e\n$stack',
      );

      if (mounted) {
        setState(() {
          _errorMessage = _isEdicao
              ? 'Não foi possível salvar as alterações. '
              'Tente novamente.'
              : 'Não foi possível cadastrar o produto. '
              'Tente novamente.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    if (_isEdicao) {
      final produtoAsync =
      ref.watch(
        produtoByIdProvider(
          widget.produtoId!,
        ),
      );

      final skuAsync =
      ref.watch(
        skuByIdProvider(
          widget.skuId!,
        ),
      );

      return produtoAsync.when(
        data: (produto) =>
            skuAsync.when(
              data: (sku) {
                if (produto == null ||
                    sku == null) {
                  return Scaffold(
                    appBar: AppBar(
                      title:
                      const Text(
                        'Editar Produto',
                      ),
                    ),
                    body: Center(
                      child: Column(
                        mainAxisSize:
                        MainAxisSize.min,
                        children: [
                          const Text(
                            'Produto não encontrado.',
                          ),
                          const SizedBox(
                            height: 12,
                          ),
                          OutlinedButton(
                            onPressed: () {
                              Navigator.of(
                                context,
                              ).pop();
                            },
                            child: const Text(
                              'Voltar',
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                _prefillSeNecessario(
                  produto,
                  sku,
                );

                return _buildFormScaffold(
                  context,
                );
              },
              loading: () =>
                  Scaffold(
                    appBar: AppBar(
                      title:
                      const Text(
                        'Editar Produto',
                      ),
                    ),
                    body: const Center(
                      child:
                      CircularProgressIndicator(),
                    ),
                  ),
              error: (e, st) {
                debugPrint(
                  'Erro ao carregar SKU '
                      'para edição: $e\n$st',
                );

                return Scaffold(
                  appBar: AppBar(
                    title:
                    const Text(
                      'Editar Produto',
                    ),
                  ),
                  body: const Center(
                    child: Text(
                      'Não foi possível carregar o SKU.',
                    ),
                  ),
                );
              },
            ),
        loading: () =>
            Scaffold(
              appBar: AppBar(
                title:
                const Text(
                  'Editar Prduto',
                ),
              ),
              body: const Center(
                child:
                CircularProgressIndicator(),
              ),
            ),
        error: (e, st) {
          debugPrint(
            'Erro ao carregar produto '
                'para edição: $e\n$st',
          );

          return Scaffold(
            appBar: AppBar(
              title:
              const Text(
                'Editar Produto',
              ),
            ),
            body: const Center(
              child: Text(
                'Não foi possível carregar o produto.',
              ),
            ),
          );
        },
      );
    }

    return _buildFormScaffold(
      context,
    );
  }

  // =========================================================
  // SCAFFOLD DO FORMULÁRIO
  // =========================================================

  Widget _buildFormScaffold(
      BuildContext context,
      ) {
    final orgId =
    ref.watch(
      currentOrgIdProvider,
    );

    final appUserAsync =
    ref.watch(
      appUserProvider,
    );

    if (orgId == null &&
        appUserAsync.isLoading) {
      return const Scaffold(
        body: Center(
          child:
          CircularProgressIndicator(),
        ),
      );
    }

    if (orgId == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            _isEdicao
                ? 'Editar Produto'
                : 'Novo Produto',
          ),
        ),
        body: Center(
          child: Padding(
            padding:
            const EdgeInsets.all(
              24,
            ),
            child: Column(
              mainAxisSize:
              MainAxisSize.min,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 48,
                  color: Theme.of(context)
                      .colorScheme
                      .error,
                ),
                const SizedBox(
                  height: 16,
                ),
                const Text(
                  'Não foi possível identificar '
                      'sua organização.',
                  textAlign:
                  TextAlign.center,
                ),
                const SizedBox(
                  height: 8,
                ),
                const Text(
                  'Saia e entre novamente '
                      'no sistema.',
                  textAlign:
                  TextAlign.center,
                ),
                const SizedBox(
                  height: 20,
                ),
                FilledButton.icon(
                  onPressed: () {
                    ref
                        .read(
                      authRepositoryProvider,
                    )
                        .signOut();
                  },
                  icon: const Icon(
                    Icons.logout,
                  ),
                  label: const Text(
                    'Sair',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop:
      !_dirty &&
          !_isSaving,
      onPopInvoked:
          (didPop) async {
        if (didPop) return;

        await _solicitarSaida();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading:
          false,
          leading: IconButton(
            tooltip: 'Voltar',
            onPressed: _isSaving
                ? null
                : () {
              _solicitarSaida();
            },
            icon: const Icon(
              Icons.arrow_back,
            ),
          ),
          title: Text(
            _isEdicao
                ? 'Editar produto'
                : 'Novo produto',
          ),
        ),
        bottomNavigationBar:
        _BarraAcoesFormulario(
          salvando: _isSaving,
          modoEdicao: _isEdicao,
          onCancelar: () {
            _solicitarSaida();
          },
          onSalvar: () {
            _handleSave();
          },
        ),
        body: GestureDetector(
          behavior:
          HitTestBehavior.translucent,
          onTap: () {
            FocusScope.of(context)
                .unfocus();
          },
          child:
          SingleChildScrollView(
            padding:
            const EdgeInsets.only(
              bottom: 24,
            ),
            child: ResponsiveCenter(
              maxWidth: 1120,
              child: Padding(
                padding:
                const EdgeInsets
                    .fromLTRB(
                  16,
                  20,
                  16,
                  8,
                ),
                child: Form(
                  key: _formKey,
                  autovalidateMode:
                  AutovalidateMode
                      .onUserInteraction,
                  child: LayoutBuilder(
                    builder: (
                        context,
                        constraints,
                        ) {
                      final desktop =
                          constraints
                              .maxWidth >=
                              _kBreakpointLayoutDesktop;

                      final larguraFormulario =
                      desktop
                          ? constraints
                          .maxWidth -
                          _kLarguraPainelLateral -
                          20
                          : constraints
                          .maxWidth;

                      final compacto =
                          larguraFormulario <
                              _kBreakpointCamposCompactos;

                      final formulario =
                      _buildFormularioPrincipal(
                        context,
                        orgId: orgId,
                        compacto:
                        compacto,
                      );

                      final lateral =
                      Column(
                        crossAxisAlignment:
                        CrossAxisAlignment
                            .stretch,
                        children: [
                          _buildFotoCard(
                            context,
                          ),
                          const SizedBox(
                            height: 16,
                          ),
                          _buildResumoCard(
                            context,
                          ),
                        ],
                      );

                      return Column(
                        crossAxisAlignment:
                        CrossAxisAlignment
                            .stretch,
                        children: [
                          _CabecalhoFormulario(
                            modoEdicao:
                            _isEdicao,
                          ),
                          const SizedBox(
                            height: 20,
                          ),
                          if (desktop)
                            Row(
                              crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                              children: [
                                Expanded(
                                  child:
                                  formulario,
                                ),
                                const SizedBox(
                                  width: 20,
                                ),
                                SizedBox(
                                  width:
                                  _kLarguraPainelLateral,
                                  child:
                                  lateral,
                                ),
                              ],
                            )
                          else ...[
                            _buildFotoCard(
                              context,
                            ),
                            const SizedBox(
                              height: 16,
                            ),
                            formulario,
                            const SizedBox(
                              height: 16,
                            ),
                            _buildResumoCard(
                              context,
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================
  // FORMULÁRIO PRINCIPAL
  // =========================================================

  Widget _buildFormularioPrincipal(
      BuildContext context, {
        required String orgId,
        required bool compacto,
      }) {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.stretch,
      children: [
        if (_errorMessage != null) ...[
          _BannerErro(
            mensagem:
            _errorMessage!,
          ),
          const SizedBox(
            height: 16,
          ),
        ],

        _buildInformacoesProdutoCard(
          context,
          orgId,
          compacto,
        ),

        const SizedBox(
          height: 16,
        ),

        _buildSkuCard(
          context,
        ),

        const SizedBox(
          height: 16,
        ),

        _buildValoresCard(
          context,
          compacto,
        ),

        const SizedBox(
          height: 16,
        ),

        _buildControleEstoqueCard(
          context,
          compacto,
        ),
      ],
    );
  }

  // =========================================================
  // INFORMAÇÕES DO PRODUTO
  // =========================================================

  Widget _buildInformacoesProdutoCard(
      BuildContext context,
      String orgId,
      bool compacto,
      ) {
    return _CardSecao(
      icon:
      Icons.inventory_2_outlined,
      titulo:
      'Informações do produto',
      subtitulo: _isEdicao
          ? 'Estes dados são compartilhados por todas as variações.'
          : 'Dados principais usados para identificar o produto.',
      child: Column(
        children: [
          TextFormField(
            controller:
            _descricaoController,
            enabled:
            !_isSaving,
            textCapitalization:
            TextCapitalization
                .sentences,
            textInputAction:
            TextInputAction.next,
            inputFormatters: [
              LengthLimitingTextInputFormatter(
                _maxDescricao,
              ),
            ],
            onFieldSubmitted: (_) {
              FocusScope.of(context)
                  .nextFocus();
            },
            decoration:
            const InputDecoration(
              labelText:
              'Descrição *',
              hintText:
              'Ex.: Cabo USB-C Turbo',
            ),
            validator:
            _validarDescricao,
            onChanged: (_) {
              _marcarAlterado();
            },
          ),

          const SizedBox(
            height: 16,
          ),

          _buildCategoriaField(
            context,
            orgId,
            compacto,
          ),

          const SizedBox(
            height: 16,
          ),

          _CamposPar(
            compacto:
            compacto,

            primeiro:
            TextFormField(
              controller:
              _modeloController,
              enabled:
              !_isSaving,
              textCapitalization:
              TextCapitalization
                  .words,
              textInputAction:
              TextInputAction
                  .next,
              inputFormatters: [
                LengthLimitingTextInputFormatter(
                  _maxModelo,
                ),
              ],
              onFieldSubmitted:
                  (_) {
                FocusScope.of(
                  context,
                ).nextFocus();
              },
              decoration:
              const InputDecoration(
                labelText:
                'Modelo',
                hintText:
                'Ex.: Y20',
              ),
              onChanged: (_) {
                _marcarAlterado();
              },
            ),

            segundo:
            TextFormField(
              controller:
              _fabricanteController,
              enabled:
              !_isSaving,
              textCapitalization:
              TextCapitalization
                  .words,
              textInputAction:
              TextInputAction
                  .next,
              inputFormatters: [
                LengthLimitingTextInputFormatter(
                  _maxFabricante,
                ),
              ],
              onFieldSubmitted:
                  (_) {
                FocusScope.of(
                  context,
                ).nextFocus();
              },
              decoration:
              const InputDecoration(
                labelText:
                'Fabricante',
                hintText:
                'Ex.: H\'Maston',
              ),
              onChanged: (_) {
                _marcarAlterado();
              },
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // CATEGORIA
  // =========================================================

  Widget _buildCategoriaField(
      BuildContext context,
      String orgId,
      bool compacto,
      ) {
    final categoriasAsync =
    ref.watch(
      categoriasListProvider,
    );

    return categoriasAsync.when(
      data: (categorias) {
        final nomes = categorias
            .map(
              (categoria) =>
          categoria.nome,
        )
            .toSet()
            .toList();

        final selecionada =
            _categoriaSelecionada;

        if (selecionada != null &&
            !nomes.contains(
              selecionada,
            )) {
          nomes.add(
            selecionada,
          );
        }

        nomes.sort();

        return Row(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            Expanded(
              child:
              DropdownButtonFormField<
                  String>(
                key: ValueKey(
                  selecionada,
                ),
                initialValue:
                selecionada,
                isExpanded: true,
                decoration:
                const InputDecoration(
                  labelText:
                  'Categoria *',
                ),
                items: nomes
                    .map(
                      (nome) =>
                      DropdownMenuItem(
                        value: nome,
                        child: Text(
                          nome,
                          overflow:
                          TextOverflow
                              .ellipsis,
                        ),
                      ),
                )
                    .toList(),
                onChanged:
                _isSaving
                    ? null
                    : (value) {
                  setState(
                        () {
                      _categoriaSelecionada =
                          value;

                      _dirty =
                      true;

                      _errorMessage =
                      null;
                    },
                  );
                },
                validator:
                    (value) =>
                value ==
                    null ||
                    value
                        .isEmpty
                    ? 'Selecione uma categoria'
                    : null,
              ),
            ),

            const SizedBox(
              width: 8,
            ),

            if (compacto)
              IconButton.filledTonal(
                tooltip:
                'Nova categoria',
                onPressed:
                _isSaving
                    ? null
                    : () {
                  _novaCategoria(
                    orgId,
                  );
                },
                icon: const Icon(
                  Icons.add,
                ),
              )
            else
              OutlinedButton.icon(
                onPressed:
                _isSaving
                    ? null
                    : () {
                  _novaCategoria(
                    orgId,
                  );
                },
                icon: const Icon(
                  Icons.add,
                ),
                label: const Text(
                  'Nova categoria',
                ),
              ),
          ],
        );
      },
      loading: () =>
      const _CampoCarregando(
        label:
        'Carregando categorias...',
      ),
      error: (
          error,
          stack,
          ) =>
          _CampoComErro(
            mensagem:
            'Não foi possível carregar as categorias.',
            onTentarNovamente: () {
              ref.invalidate(
                categoriasListProvider,
              );
            },
          ),
    );
  }

  // =========================================================
  // SKU
  // =========================================================

  Widget _buildSkuCard(
      BuildContext context,
      ) {
    return _CardSecao(
      icon:
      Icons.qr_code_2_rounded,
      titulo: _isEdicao
          ? 'Identificação do SKU'
          : 'Primeiro SKU',
      subtitulo: _isEdicao
          ? 'Dados específicos desta variação do produto.'
          : 'O SKU é a unidade que será movimentada no estoque.',
      child: Column(
        children: [
          if (_isEdicao) ...[
            Row(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller:
                    _codigoInternoController,
                    enabled:
                    !_isSaving,
                    keyboardType:
                    TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter
                          .digitsOnly,
                      LengthLimitingTextInputFormatter(
                        13,
                      ),
                    ],
                    decoration:
                    const InputDecoration(
                      labelText:
                      'Código interno',
                      prefixIcon:
                      Icon(Icons.tag),
                    ),
                    validator:
                    _validarCodigoInterno,
                    onChanged: (_) {
                      _marcarAlterado();
                    },
                  ),
                ),

                const SizedBox(
                  width: 12,
                ),

                Expanded(
                  child:
                  _InformacaoCompacta(
                    label:
                    'Status',
                    valor:
                    _statusLabel(
                      _statusOriginal,
                    ),
                    icon: Icons
                        .check_circle_outline,
                    destaque:
                    true,
                  ),
                ),
              ],
            ),

            const SizedBox(
              height: 16,
            ),
          ],

          TextFormField(
            controller:
            _variacaoController,
            enabled:
            !_isSaving,
            textCapitalization:
            TextCapitalization
                .words,
            textInputAction:
            TextInputAction.next,
            inputFormatters: [
              LengthLimitingTextInputFormatter(
                _maxVariacao,
              ),
            ],
            onFieldSubmitted: (_) {
              FocusScope.of(context)
                  .nextFocus();
            },
            decoration:
            const InputDecoration(
              labelText:
              'Variação (opcional)',
              hintText:
              'Ex.: Preto 1m',
              helperText:
              'Use cor, tamanho ou outra característica.',
            ),
            onChanged: (_) {
              _marcarAlterado();
            },
          ),

          const SizedBox(
            height: 16,
          ),

          TextFormField(
            controller:
            _codigoBarrasController,
            enabled:
            !_isSaving,
            keyboardType:
            TextInputType.number,
            textInputAction:
            TextInputAction.next,
            onFieldSubmitted: (_) {
              FocusScope.of(context)
                  .nextFocus();
            },
            inputFormatters: [
              FilteringTextInputFormatter
                  .digitsOnly,
              LengthLimitingTextInputFormatter(
                14,
              ),
            ],
            decoration:
            InputDecoration(
              labelText:
              'GTIN/EAN do fabricante (opcional)',
              hintText:
              'Digite ou escaneie o código',
              helperText:
              'Sem GTIN, um código interno será gerado ao salvar.',
              suffixIcon:
              IconButton(
                tooltip:
                'Escanear código de barras',
                onPressed:
                _isSaving
                    ? null
                    : _escanearCodigoBarras,
                icon: const Icon(
                  Icons
                      .qr_code_scanner_rounded,
                ),
              ),
            ),
            validator:
            _validarCodigoBarras,
            onChanged: (_) {
              _marcarAlterado();
            },
          ),
        ],
      ),
    );
  }

  // =========================================================
  // CUSTOS E PREÇO
  // =========================================================

  Widget _buildValoresCard(
      BuildContext context,
      bool compacto,
      ) {
    final custoReferenciaCentavos =
    _isEdicao
        ? _custoMedioOriginalCentavos
        : centavosFromFormatted(
      _custoController.text,
    );

    final precoCentavos =
    centavosFromFormatted(
      _precoController.text,
    );

    final campoPreco = TextFormField(
      controller:
      _precoController,
      enabled:
      !_isSaving,
      keyboardType:
      TextInputType.number,
      textInputAction:
      TextInputAction.next,
      onFieldSubmitted:
          (_) {
        FocusScope.of(
          context,
        ).nextFocus();
      },
      inputFormatters: [
        MoneyInputFormatter(),
      ],
      decoration:
      InputDecoration(
        labelText:
        _isEdicao
            ? 'Preço de venda *'
            : 'Preço inicial de venda *',
      ),
      validator:
      _validarPreco,
      onChanged: (_) {
        _marcarAlterado();
      },
    );

    return _CardSecao(
      icon:
      Icons.payments_outlined,
      titulo:
      'Custos e preço',
      subtitulo: _isEdicao
          ? 'Os custos de compra são atualizados automaticamente pelas entradas de estoque.'
          : 'Informe o custo inicial e o preço de venda.',
      child: Column(
        children: [
          if (_isEdicao) ...[
            _CamposPar(
              compacto:
              compacto,
              primeiro:
              _CampoSomenteLeitura(
                label:
                'Custo inicial de aquisição',
                valor:
                formatarCentavos(
                  _custoInicialOriginalCentavos,
                ),
              ),
              segundo:
              _CampoSomenteLeitura(
                label:
                'Custo da última compra',
                valor:
                formatarCentavos(
                  _custoUltimaCompraOriginalCentavos,
                ),
              ),
            ),

            const SizedBox(
              height: 16,
            ),

            _CamposPar(
              compacto:
              compacto,
              primeiro:
              _CampoSomenteLeitura(
                label:
                'Custo médio atual',
                valor:
                formatarCentavos(
                  _custoMedioOriginalCentavos,
                ),
              ),
              segundo:
              campoPreco,
            ),

            const SizedBox(
              height: 8,
            ),

            const _TextoInformativo(
              icon:
              Icons.history,
              texto:
              'O custo inicial é preservado. Última compra e custo médio '
                  'são calculados pelas entradas. Alterações no preço de '
                  'venda ficam registradas no histórico.',
            ),
          ] else
            _CamposPar(
              compacto:
              compacto,
              primeiro:
              TextFormField(
                controller:
                _custoController,
                enabled:
                !_isSaving,
                keyboardType:
                TextInputType.number,
                textInputAction:
                TextInputAction.next,
                onFieldSubmitted:
                    (_) {
                  FocusScope.of(
                    context,
                  ).nextFocus();
                },
                inputFormatters: [
                  MoneyInputFormatter(),
                ],
                decoration:
                const InputDecoration(
                  labelText:
                  'Custo inicial de aquisição',
                ),
                onChanged:
                    (_) {
                  _marcarAlterado();
                },
              ),
              segundo:
              campoPreco,
            ),

          if (precoCentavos >
              0) ...[
            const SizedBox(
              height: 16,
            ),
            _ResumoMargem(
              custoCentavos:
              custoReferenciaCentavos,
              precoCentavos:
              precoCentavos,
            ),
          ],
        ],
      ),
    );
  }

  // =========================================================
  // CONTROLE DE ESTOQUE
  // =========================================================

  Widget _buildControleEstoqueCard(
      BuildContext context,
      bool compacto,
      ) {
    final Widget campoSaldo;

    if (_isEdicao) {
      final saldoAsync = ref.watch(
        saldoProvider((
        localId: LocalEstoque.central,
        produtoId: widget.skuId!,
        )),
      );

      campoSaldo = saldoAsync.when(
        data: (saldo) =>
            _CampoSomenteLeitura(
              label:
              'Saldo atual no estoque central',
              valor:
              '$saldo un.',
            ),
        loading: () =>
        const _CampoSomenteLeitura(
          label:
          'Saldo atual no estoque central',
          valor:
          'Carregando...',
        ),
        error: (_, __) =>
        const _CampoSomenteLeitura(
          label:
          'Saldo atual no estoque central',
          valor:
          '—',
        ),
      );
    } else {
      campoSaldo =
      const _CampoSomenteLeitura(
        label:
        'Saldo atual no estoque central',
        valor:
        '0 un.',
      );
    }

    return _CardSecao(
      icon:
      Icons.warehouse_outlined,
      titulo:
      'Controle de estoque',
      subtitulo:
      'Acompanhe o saldo atual e defina o ponto de reposição.',
      child: _CamposPar(
        compacto:
        compacto,
        primeiro:
        campoSaldo,
        segundo:
        TextFormField(
          controller:
          _estoqueMinimoController,
          enabled:
          !_isSaving,
          keyboardType:
          TextInputType.number,
          textInputAction:
          TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter
                .digitsOnly,
          ],
          decoration:
          const InputDecoration(
            labelText:
            'Estoque mínimo no estoque central',
            helperText:
            'Usado para avisar quando for necessário repor.',
          ),
          validator:
          _validarEstoqueMinimo,
          onChanged: (_) {
            _marcarAlterado();
          },
        ),
      ),
    );
  }

  // =========================================================
  // FOTO
  // =========================================================

  Widget _buildFotoCard(
      BuildContext context,
      ) {
    return _CardSecao(
      icon:
      Icons.add_a_photo_outlined,
      titulo:
      'Foto do produto',
      subtitulo:
      'Ajuda na identificação durante estoque e visitas.',
      child: Column(
        children: [
          Center(
            child:
            ProdutoPhotoPicker(
              bytesSelecionados:
              _fotoBytes,

              urlExistente:
              _removerFotoExistente
                  ? null
                  : _fotoUrlExistente,

              onChanged: (bytes) {
                setState(() {
                  _fotoBytes =
                      bytes;

                  if (bytes !=
                      null) {
                    _removerFotoExistente =
                    false;
                  } else if (_fotoUrlExistente !=
                      null) {
                    _removerFotoExistente =
                    true;
                  }

                  _dirty =
                  true;

                  _errorMessage =
                  null;
                });
              },
            ),
          ),

          const SizedBox(
            height: 12,
          ),

          Text(
            'Use uma foto nítida, de preferência com fundo neutro.',
            textAlign:
            TextAlign.center,
            style:
            Theme.of(context)
                .textTheme
                .bodySmall,
          ),
        ],
      ),
    );
  }

  // =========================================================
  // RESUMO
  // =========================================================

  Widget _buildResumoCard(
      BuildContext context,
      ) {
    final descricao =
    _descricaoController.text
        .trim();

    final variacao =
    _variacaoController.text
        .trim();

    final identificacao = [
      if (descricao.isNotEmpty)
        descricao,
      if (variacao.isNotEmpty)
        variacao,
    ].join(' — ');

    final codigoInterno =
    _codigoInternoController.text
        .trim();

    return _CardSecao(
      icon:
      Icons.fact_check_outlined,
      titulo:
      'Resumo do cadastro',
      subtitulo:
      'Confira os dados principais antes de salvar.',
      child: Column(
        children: [
          _ResumoLinha(
            label:
            'Produto',
            valor:
            identificacao.isEmpty
                ? 'Não informado'
                : identificacao,
          ),

          const Divider(
            height: 24,
          ),

          _ResumoLinha(
            label:
            'Categoria',
            valor:
            _categoriaSelecionada ??
                'Não selecionada',
          ),

          const Divider(
            height: 24,
          ),

          _ResumoLinha(
            label:
            'SKU',
            valor:
            _isEdicao
                ? (codigoInterno.isEmpty
                ? '—'
                : codigoInterno)
                : 'Gerado ao salvar',
          ),

          const Divider(
            height: 24,
          ),

          _ResumoLinha(
            label:
            'Preço de venda',
            valor:
            _precoController.text,
          ),

          const Divider(
            height: 24,
          ),

          _ResumoLinha(
            label:
            'Status',
            valor:
            _isEdicao
                ? _statusLabel(
              _statusOriginal,
            )
                : 'Ativo ao salvar',
            destaque:
            true,
          ),
        ],
      ),
    );
  }

  String _statusLabel(
      SkuStatus status,
      ) =>
      switch (status) {
        SkuStatus.active =>
        'Ativo',
        SkuStatus.blockedForSale =>
        'Bloqueado para venda',
        SkuStatus.discontinued =>
        'Descontinuado',
      };
}

// ===========================================================
// CABEÇALHO
// ===========================================================

class _CabecalhoFormulario
    extends StatelessWidget {
  final bool modoEdicao;

  const _CabecalhoFormulario({
    required this.modoEdicao,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    final textTheme =
        Theme.of(context)
            .textTheme;

    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Text(
          modoEdicao
              ? 'Atualize o produto e o SKU'
              : 'Cadastre o produto e seu primeiro SKU',
          style:
          textTheme.headlineSmall
              ?.copyWith(
            fontWeight:
            FontWeight.w700,
          ),
        ),

        const SizedBox(
          height: 6,
        ),

        Text(
          modoEdicao
              ? 'Revise os dados compartilhados do produto '
              'e as informações desta variação.'
              : 'Preencha as informações abaixo. '
              'Os campos com * são obrigatórios.',
          style:
          textTheme.bodyMedium,
        ),
      ],
    );
  }
}

// ===========================================================
// CARD DE SEÇÃO
// ===========================================================

class _CardSecao
    extends StatelessWidget {
  final IconData icon;
  final String titulo;
  final String? subtitulo;
  final Widget child;

  const _CardSecao({
    required this.icon,
    required this.titulo,
    this.subtitulo,
    required this.child,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    final theme =
    Theme.of(context);

    return Card(
      margin:
      EdgeInsets.zero,
      clipBehavior:
      Clip.antiAlias,
      child: Padding(
        padding:
        const EdgeInsets.all(
          20,
        ),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment
              .stretch,
          children: [
            Row(
              crossAxisAlignment:
              CrossAxisAlignment
                  .start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration:
                  BoxDecoration(
                    color: theme
                        .colorScheme
                        .primary
                        .withValues(
                      alpha:
                      0.12,
                    ),
                    borderRadius:
                    BorderRadius
                        .circular(
                      10,
                    ),
                  ),
                  child: Icon(
                    icon,
                    color: theme
                        .colorScheme
                        .primary,
                    size: 21,
                  ),
                ),

                const SizedBox(
                  width: 12,
                ),

                Expanded(
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                    children: [
                      Text(
                        titulo,
                        style: theme
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                          fontWeight:
                          FontWeight
                              .w700,
                        ),
                      ),

                      if (subtitulo !=
                          null) ...[
                        const SizedBox(
                          height: 3,
                        ),
                        Text(
                          subtitulo!,
                          style: theme
                              .textTheme
                              .bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(
              height: 20,
            ),

            child,
          ],
        ),
      ),
    );
  }
}

// ===========================================================
// CAMPO SOMENTE LEITURA
// ===========================================================

class _CampoSomenteLeitura
    extends StatelessWidget {
  final String label;
  final String valor;

  const _CampoSomenteLeitura({
    required this.label,
    required this.valor,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return InputDecorator(
      decoration:
      InputDecoration(
        labelText: label,
      ),
      child: Text(
        valor,
      ),
    );
  }
}

// ===========================================================
// INFORMAÇÃO COMPACTA
// ===========================================================

class _InformacaoCompacta
    extends StatelessWidget {
  final String label;
  final String valor;
  final IconData icon;
  final bool destaque;

  const _InformacaoCompacta({
    required this.label,
    required this.valor,
    required this.icon,
    this.destaque = false,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    final theme =
    Theme.of(context);

    final cor = destaque
        ? theme
        .colorScheme
        .primary
        : theme
        .colorScheme
        .onSurfaceVariant;

    return Container(
      padding:
      const EdgeInsets.all(
        12,
      ),
      decoration:
      BoxDecoration(
        border:
        Border.all(
          color:
          theme.dividerColor,
        ),
        borderRadius:
        BorderRadius.circular(
          10,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 19,
            color: cor,
          ),

          const SizedBox(
            width: 10,
          ),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment
                  .start,
              children: [
                Text(
                  label,
                  style: theme
                      .textTheme
                      .labelSmall,
                ),

                const SizedBox(
                  height: 2,
                ),

                Text(
                  valor,
                  maxLines: 1,
                  overflow:
                  TextOverflow
                      .ellipsis,
                  style: theme
                      .textTheme
                      .bodyMedium
                      ?.copyWith(
                    color:
                    destaque
                        ? cor
                        : null,
                    fontWeight:
                    FontWeight
                        .w600,
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

// ===========================================================
// LINHA DO RESUMO
// ===========================================================

class _ResumoLinha
    extends StatelessWidget {
  final String label;
  final String valor;
  final bool destaque;

  const _ResumoLinha({
    required this.label,
    required this.valor,
    this.destaque = false,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    final theme =
    Theme.of(context);

    return Row(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: theme
                .textTheme
                .bodySmall,
          ),
        ),

        const SizedBox(
          width: 12,
        ),

        Flexible(
          child: Text(
            valor,
            textAlign:
            TextAlign.end,
            maxLines: 2,
            overflow:
            TextOverflow.ellipsis,
            style: theme
                .textTheme
                .bodyMedium
                ?.copyWith(
              color:
              destaque
                  ? theme
                  .colorScheme
                  .primary
                  : null,
              fontWeight:
              FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// ===========================================================
// RESUMO DE MARGEM
// ===========================================================

class _ResumoMargem
    extends StatelessWidget {
  final int custoCentavos;
  final int precoCentavos;

  const _ResumoMargem({
    required this.custoCentavos,
    required this.precoCentavos,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    final theme =
    Theme.of(context);

    final diferenca =
        precoCentavos -
            custoCentavos;

    final margem =
    precoCentavos == 0
        ? 0.0
        : (diferenca /
        precoCentavos) *
        100;

    final positiva =
        diferenca >= 0;

    final cor =
    positiva
        ? theme
        .colorScheme
        .primary
        : theme
        .colorScheme
        .error;

    return Container(
      padding:
      const EdgeInsets
          .symmetric(
        horizontal: 14,
        vertical: 12,
      ),
      decoration:
      BoxDecoration(
        color:
        cor.withValues(
          alpha: 0.08,
        ),
        border:
        Border.all(
          color:
          cor.withValues(
            alpha: 0.24,
          ),
        ),
        borderRadius:
        BorderRadius.circular(
          10,
        ),
      ),
      child: Row(
        children: [
          Icon(
            positiva
                ? Icons.trending_up
                : Icons
                .warning_amber_rounded,
            color: cor,
            size: 20,
          ),

          const SizedBox(
            width: 10,
          ),

          Expanded(
            child: Text(
              'Margem bruta estimada',
              style: theme
                  .textTheme
                  .bodySmall,
            ),
          ),

          Text(
            '${formatarCentavos(diferenca)} • '
                '${margem.toStringAsFixed(1)}%',
            style: theme
                .textTheme
                .bodyMedium
                ?.copyWith(
              color: cor,
              fontWeight:
              FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================
// TEXTO INFORMATIVO
// ===========================================================

class _TextoInformativo
    extends StatelessWidget {
  final IconData icon;
  final String texto;
  final Color? cor;

  const _TextoInformativo({
    required this.icon,
    required this.texto,
    this.cor,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    final theme =
    Theme.of(context);

    final corFinal =
        cor ??
            theme
                .colorScheme
                .onSurfaceVariant;

    return Row(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 17,
          color: corFinal,
        ),

        const SizedBox(
          width: 8,
        ),

        Expanded(
          child: Text(
            texto,
            style: theme
                .textTheme
                .bodySmall
                ?.copyWith(
              color: corFinal,
            ),
          ),
        ),
      ],
    );
  }
}

// ===========================================================
// BANNER DE ERRO
// ===========================================================

class _BannerErro
    extends StatelessWidget {
  final String mensagem;

  const _BannerErro({
    required this.mensagem,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    final theme =
    Theme.of(context);

    final cor =
        theme.colorScheme.error;

    return Container(
      padding:
      const EdgeInsets.all(
        14,
      ),
      decoration:
      BoxDecoration(
        color:
        cor.withValues(
          alpha: 0.1,
        ),
        borderRadius:
        BorderRadius.circular(
          12,
        ),
        border:
        Border.all(
          color:
          cor.withValues(
            alpha: 0.3,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment
            .start,
        children: [
          Icon(
            Icons.error_outline,
            color: cor,
          ),

          const SizedBox(
            width: 10,
          ),

          Expanded(
            child: Text(
              mensagem,
              style: theme
                  .textTheme
                  .bodyMedium
                  ?.copyWith(
                color: cor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================
// CAMPO CARREGANDO
// ===========================================================

class _CampoCarregando
    extends StatelessWidget {
  final String label;

  const _CampoCarregando({
    required this.label,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return InputDecorator(
      decoration:
      const InputDecoration(
        enabled: false,
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child:
            CircularProgressIndicator(
              strokeWidth: 2,
            ),
          ),

          const SizedBox(
            width: 10,
          ),

          Text(
            label,
          ),
        ],
      ),
    );
  }
}

// ===========================================================
// CAMPO COM ERRO
// ===========================================================

class _CampoComErro
    extends StatelessWidget {
  final String mensagem;

  final VoidCallback
  onTentarNovamente;

  const _CampoComErro({
    required this.mensagem,
    required this.onTentarNovamente,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    final cor =
        Theme.of(context)
            .colorScheme
            .error;

    return Container(
      padding:
      const EdgeInsets
          .symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      decoration:
      BoxDecoration(
        border:
        Border.all(
          color:
          cor.withValues(
            alpha: 0.4,
          ),
        ),
        borderRadius:
        BorderRadius.circular(
          10,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: cor,
            size: 20,
          ),

          const SizedBox(
            width: 8,
          ),

          Expanded(
            child: Text(
              mensagem,
            ),
          ),

          TextButton(
            onPressed:
            onTentarNovamente,
            child: const Text(
              'Tentar novamente',
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================
// BARRA DE AÇÕES
// ===========================================================

class _BarraAcoesFormulario
    extends StatelessWidget {
  final bool salvando;
  final bool modoEdicao;

  final VoidCallback
  onCancelar;

  final VoidCallback
  onSalvar;

  const _BarraAcoesFormulario({
    required this.salvando,
    required this.modoEdicao,
    required this.onCancelar,
    required this.onSalvar,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    final theme =
    Theme.of(context);

    return Material(
      color:
      theme.scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: Container(
          decoration:
          BoxDecoration(
            border: Border(
              top: BorderSide(
                color:
                theme.dividerColor,
              ),
            ),
          ),
          child: Align(
            alignment:
            Alignment.center,
            heightFactor: 1,
            child:
            ConstrainedBox(
              constraints:
              const BoxConstraints(
                maxWidth: 1120,
              ),
              child:
              SizedBox(
                width:
                double.infinity,
                child: Padding(
                  padding:
                  const EdgeInsets
                      .symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child:
                  LayoutBuilder(
                    builder: (
                        context,
                        constraints,
                        ) {
                      final compacto =
                          constraints
                              .maxWidth <
                              520;

                      return Row(
                        children: [
                          if (!compacto)
                            const Spacer(),

                          OutlinedButton
                              .icon(
                            onPressed:
                            salvando
                                ? null
                                : onCancelar,
                            icon:
                            const Icon(
                              Icons.close,
                            ),
                            label:
                            const Text(
                              'Cancelar',
                            ),
                          ),

                          const SizedBox(
                            width: 12,
                          ),

                          if (compacto)
                            Expanded(
                              child:
                              FilledButton
                                  .icon(
                                onPressed:
                                salvando
                                    ? null
                                    : onSalvar,
                                icon:
                                salvando
                                    ? const SizedBox(
                                  width:
                                  18,
                                  height:
                                  18,
                                  child:
                                  CircularProgressIndicator(
                                    strokeWidth:
                                    2,
                                  ),
                                )
                                    : const Icon(
                                  Icons.save_outlined,
                                ),
                                label:
                                Text(
                                  salvando
                                      ? 'Salvando...'
                                      : modoEdicao
                                      ? 'Salvar'
                                      : 'Salvar produto',
                                ),
                              ),
                            )
                          else
                            SizedBox(
                              width:
                              190,
                              child:
                              FilledButton
                                  .icon(
                                onPressed:
                                salvando
                                    ? null
                                    : onSalvar,
                                icon:
                                salvando
                                    ? const SizedBox(
                                  width:
                                  18,
                                  height:
                                  18,
                                  child:
                                  CircularProgressIndicator(
                                    strokeWidth:
                                    2,
                                  ),
                                )
                                    : const Icon(
                                  Icons.save_outlined,
                                ),
                                label:
                                Text(
                                  salvando
                                      ? 'Salvando...'
                                      : modoEdicao
                                      ? 'Salvar alterações'
                                      : 'Salvar produto',
                                ),
                              ),
                            ),
                        ],
                      );
                    },
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

// ===========================================================
// DOIS CAMPOS RESPONSIVOS
// ===========================================================

/// Dois campos lado a lado no desktop;
/// empilhados no celular.
class _CamposPar
    extends StatelessWidget {
  final bool compacto;
  final Widget primeiro;
  final Widget segundo;

  const _CamposPar({
    required this.compacto,
    required this.primeiro,
    required this.segundo,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    if (compacto) {
      return Column(
        crossAxisAlignment:
        CrossAxisAlignment
            .stretch,
        children: [
          primeiro,
          const SizedBox(
            height: 12,
          ),
          segundo,
        ],
      );
    }

    return Row(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        Expanded(
          child: primeiro,
        ),
        const SizedBox(
          width: 12,
        ),
        Expanded(
          child: segundo,
        ),
      ],
    );
  }
}