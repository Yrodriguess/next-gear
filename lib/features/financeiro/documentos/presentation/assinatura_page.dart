import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:signature/signature.dart';

import '../../../../core/utils/money_input_formatter.dart';
import '../../../../core/widgets/responsive_center.dart';

/// Resultado da coleta de assinatura.
class AssinaturaColetada {
  final String nomeResponsavel;
  final String documentoResponsavel;
  final String telefoneResponsavel;
  final Uint8List assinaturaPng;

  /// Momento exato em que o responsável confirmou a assinatura.
  final DateTime assinadaEm;

  const AssinaturaColetada({
    required this.nomeResponsavel,
    required this.documentoResponsavel,
    required this.telefoneResponsavel,
    required this.assinaturaPng,
    required this.assinadaEm,
  });
}

class AssinaturaPage extends StatefulWidget {
  final String tituloDocumento;

  /// Dados opcionais para mostrar o contexto da operação.
  final String? numeroDocumento;
  final String? nomeCliente;
  final String? expositorNumero;
  final String? expositorModeloNome;

  /// Quantidade de SKUs/modelos diferentes no expositor.
  final int? quantidadeSkus;

  /// Quantidade total de unidades físicas no expositor.
  final int? quantidadeUnidades;

  /// Compatibilidade com chamadas antigas.
  /// Quando quantidadeSkus não for informado, este valor será tratado
  /// como quantidade de SKUs.
  @Deprecated('Use quantidadeSkus e quantidadeUnidades.')
  final int? quantidadeProdutos;

  final int? quantidadeVendida;
  final int? valorAcertoCentavos;

  /// Na instalação, por exemplo:
  /// Grande = 100000
  /// Pequeno = 70000
  final int? valorReposicaoExpositorCentavos;

  /// Texto mostrado abaixo do título do documento.
  final String? descricaoDocumento;

  /// Texto que o responsável confirma antes de assinar.
  final String? textoConfirmacao;

  /// Dados opcionais para pré-preencher o responsável.
  final String? nomeResponsavelInicial;
  final String? documentoResponsavelInicial;
  final String? telefoneResponsavelInicial;

  const AssinaturaPage({
    super.key,
    required this.tituloDocumento,
    this.numeroDocumento,
    this.nomeCliente,
    this.expositorNumero,
    this.expositorModeloNome,
    this.quantidadeSkus,
    this.quantidadeUnidades,
    this.quantidadeProdutos,
    this.quantidadeVendida,
    this.valorAcertoCentavos,
    this.valorReposicaoExpositorCentavos,
    this.descricaoDocumento,
    this.textoConfirmacao,
    this.nomeResponsavelInicial,
    this.documentoResponsavelInicial,
    this.telefoneResponsavelInicial,
  });

  @override
  State<AssinaturaPage> createState() => _AssinaturaPageState();
}

class _AssinaturaPageState extends State<AssinaturaPage> {
  final _nomeController = TextEditingController();
  final _documentoController = TextEditingController();
  final _telefoneController = TextEditingController();

  late final SignatureController _signatureController;

  bool _confirmouDados = false;
  bool _isSaving = false;
  bool _liberarSaida = false;
  bool _dialogSaidaAberto = false;

  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    _nomeController.text =
        widget.nomeResponsavelInicial?.trim() ?? '';

    _documentoController.text =
        _formatarDocumento(
          _somenteDigitos(
            widget.documentoResponsavelInicial ?? '',
          ),
        );

    _telefoneController.text =
        _formatarTelefone(
          _somenteDigitos(
            widget.telefoneResponsavelInicial ?? '',
          ),
        );

    _signatureController = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
    );

    _nomeController.addListener(_onAlteracao);
    _documentoController.addListener(_onAlteracao);
    _telefoneController.addListener(_onAlteracao);
    _signatureController.addListener(_onAlteracao);
  }

  @override
  void dispose() {
    _nomeController.removeListener(_onAlteracao);
    _documentoController.removeListener(_onAlteracao);
    _telefoneController.removeListener(_onAlteracao);
    _signatureController.removeListener(_onAlteracao);

    _nomeController.dispose();
    _documentoController.dispose();
    _telefoneController.dispose();
    _signatureController.dispose();

    super.dispose();
  }

  void _onAlteracao() {
    if (!mounted) return;

    setState(() {
      _errorMessage = null;
    });
  }

  bool get _temAlteracoes {
    return _nomeController.text.trim().isNotEmpty ||
        _documentoController.text.trim().isNotEmpty ||
        _telefoneController.text.trim().isNotEmpty ||
        !_signatureController.isEmpty ||
        _confirmouDados;
  }

  bool get _temContextoOperacao {
    return _temTexto(widget.nomeCliente) ||
        _temTexto(widget.numeroDocumento) ||
        _temTexto(widget.expositorNumero) ||
        widget.quantidadeSkus != null ||
        widget.quantidadeUnidades != null ||
        widget.quantidadeProdutos != null ||
        widget.quantidadeVendida != null ||
        widget.valorAcertoCentavos != null ||
        widget.valorReposicaoExpositorCentavos != null;
  }

  Future<void> _tentarSair() async {
    if (_liberarSaida) {
      return;
    }

    if (_isSaving) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Aguarde a confirmação da assinatura.',
          ),
        ),
      );
      return;
    }

    if (!_temAlteracoes) {
      setState(() {
        _liberarSaida = true;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).maybePop();
        }
      });

      return;
    }

    if (_dialogSaidaAberto) {
      return;
    }

    _dialogSaidaAberto = true;

    final sair = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          icon: const Icon(
            Icons.warning_amber_rounded,
          ),
          title: const Text(
            'Sair da assinatura?',
          ),
          content: const Text(
            'Os dados preenchidos e a assinatura desenhada '
                'serão perdidos.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text(
                'Continuar assinando',
              ),
            ),
            FilledButton.tonal(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text(
                'Sair',
              ),
            ),
          ],
        );
      },
    );

    _dialogSaidaAberto = false;

    if (sair != true || !mounted) {
      return;
    }

    setState(() {
      _liberarSaida = true;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).maybePop();
      }
    });
  }

  Future<void> _handleConfirmar() async {
    if (_isSaving) {
      return;
    }

    final nome = _normalizarNome(
      _nomeController.text,
    );

    final documento = _somenteDigitos(
      _documentoController.text,
    );

    final telefone = _somenteDigitos(
      _telefoneController.text,
    );

    if (nome.isEmpty) {
      _mostrarErro(
        'Informe o nome completo do responsável.',
      );
      return;
    }

    if (nome.split(' ').where((e) => e.isNotEmpty).length < 2) {
      _mostrarErro(
        'Informe o nome completo do responsável.',
      );
      return;
    }

    if (documento.length != 11 &&
        documento.length != 14) {
      _mostrarErro(
        'Informe um CPF ou CNPJ válido.',
      );
      return;
    }

    if (telefone.length != 10 &&
        telefone.length != 11) {
      _mostrarErro(
        'Informe um telefone com DDD.',
      );
      return;
    }

    if (!_confirmouDados) {
      _mostrarErro(
        'Confirme que conferiu os dados da operação.',
      );
      return;
    }

    if (_signatureController.isEmpty) {
      _mostrarErro(
        'Colete a assinatura antes de continuar.',
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      /// Data REAL da confirmação.
      final assinadaEm = DateTime.now();

      final png =
      await _signatureController.toPngBytes();

      if (png == null) {
        if (mounted) {
          _mostrarErro(
            'Não foi possível capturar a assinatura.',
          );
        }
        return;
      }

      final resultado = AssinaturaColetada(
        nomeResponsavel: nome,
        documentoResponsavel: documento,
        telefoneResponsavel: telefone,
        assinaturaPng: png,
        assinadaEm: assinadaEm,
      );

      if (!mounted) return;

      final continuar = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          final theme =
          Theme.of(dialogContext);

          return AlertDialog(
            icon: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: Colors.green.withValues(
                  alpha: .12,
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: Colors.green,
                size: 34,
              ),
            ),
            title: const Text(
              'Assinatura registrada',
              textAlign: TextAlign.center,
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'A assinatura foi confirmada com sucesso.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme
                        .surfaceContainerLow,
                    borderRadius:
                    BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Data e hora da assinatura',
                        style: TextStyle(
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatarDataHora(
                          assinadaEm,
                        ),
                        style: const TextStyle(
                          fontWeight:
                          FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(
                      dialogContext,
                    ).pop(true);
                  },
                  child: const Text(
                    'Continuar',
                  ),
                ),
              ),
            ],
          );
        },
      );

      if (continuar != true || !mounted) {
        return;
      }

      setState(() {
        _liberarSaida = true;
      });

      Navigator.of(context).pop(
        resultado,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _mostrarErro(String mensagem) {
    setState(() {
      _errorMessage = mensagem;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: _liberarSaida,
      onPopInvokedWithResult: (
          didPop,
          result,
          ) {
        if (!didPop) {
          _tentarSair();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Assinatura',
          ),
        ),
        body: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            padding:
            const EdgeInsets.fromLTRB(
              16,
              16,
              16,
              28,
            ),
            child: ResponsiveCenter(
              maxWidth: 640,
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.stretch,
                children: [
                  _DocumentoHeader(
                    titulo:
                    widget.tituloDocumento,
                    numeroDocumento:
                    widget.numeroDocumento,
                    descricao:
                    widget.descricaoDocumento,
                  ),

                  if (_temContextoOperacao) ...[
                    const SizedBox(height: 14),
                    _OperacaoCard(
                      nomeCliente:
                      widget.nomeCliente,
                      expositorNumero:
                      widget.expositorNumero,
                      expositorModelo:
                      widget
                          .expositorModeloNome,
                      quantidadeSkus:
                      widget.quantidadeSkus ??
                          widget.quantidadeProdutos,
                      quantidadeUnidades:
                      widget.quantidadeUnidades,
                      quantidadeVendida:
                      widget.quantidadeVendida,
                      valorAcertoCentavos:
                      widget
                          .valorAcertoCentavos,
                      valorReposicaoExpositorCentavos:
                      widget
                          .valorReposicaoExpositorCentavos,
                    ),
                  ],

                  const SizedBox(height: 22),

                  const _SectionTitle(
                    title:
                    'RESPONSÁVEL PELO ESTABELECIMENTO',
                  ),

                  const SizedBox(height: 12),

                  TextFormField(
                    controller:
                    _nomeController,
                    enabled: !_isSaving,
                    textCapitalization:
                    TextCapitalization.words,
                    textInputAction:
                    TextInputAction.next,
                    decoration:
                    const InputDecoration(
                      labelText:
                      'Nome completo',
                      prefixIcon: Icon(
                        Icons.person_outline,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  TextFormField(
                    controller:
                    _documentoController,
                    enabled: !_isSaving,
                    keyboardType:
                    TextInputType.number,
                    textInputAction:
                    TextInputAction.next,
                    inputFormatters: [
                      FilteringTextInputFormatter
                          .digitsOnly,
                      LengthLimitingTextInputFormatter(
                        14,
                      ),
                      _DocumentoInputFormatter(),
                    ],
                    decoration:
                    const InputDecoration(
                      labelText: 'CPF/CNPJ',
                      prefixIcon: Icon(
                        Icons.badge_outlined,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  TextFormField(
                    controller:
                    _telefoneController,
                    enabled: !_isSaving,
                    keyboardType:
                    TextInputType.phone,
                    textInputAction:
                    TextInputAction.done,
                    inputFormatters: [
                      FilteringTextInputFormatter
                          .digitsOnly,
                      LengthLimitingTextInputFormatter(
                        11,
                      ),
                      _TelefoneInputFormatter(),
                    ],
                    decoration:
                    const InputDecoration(
                      labelText:
                      'WhatsApp',
                      prefixIcon: Icon(
                        Icons.phone_outlined,
                      ),
                      helperText:
                      'Usado para identificação e envio do documento.',
                    ),
                  ),

                  const SizedBox(height: 14),

                  const _InfoBox(
                    message:
                    'Os dados do responsável serão vinculados ao documento desta operação.',
                  ),

                  const SizedBox(height: 24),

                  const _SectionTitle(
                    title: 'CONFIRMAÇÃO',
                  ),

                  const SizedBox(height: 10),

                  CheckboxListTile(
                    value: _confirmouDados,
                    enabled: !_isSaving,
                    contentPadding:
                    EdgeInsets.zero,
                    controlAffinity:
                    ListTileControlAffinity
                        .leading,
                    title: Text(
                      widget.textoConfirmacao ??
                          'Li e confirmo que conferi os produtos, '
                              'quantidades, valores e informações '
                              'apresentados nesta operação.',
                      style: theme
                          .textTheme.bodyMedium,
                    ),
                    onChanged: (value) {
                      setState(() {
                        _confirmouDados =
                            value ?? false;
                        _errorMessage = null;
                      });
                    },
                  ),

                  const SizedBox(height: 20),

                  const _SectionTitle(
                    title:
                    'ASSINATURA DO RESPONSÁVEL',
                  ),

                  const SizedBox(height: 10),

                  Container(
                    height: 235,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                      BorderRadius.circular(
                        14,
                      ),
                      border: Border.all(
                        color: theme
                            .colorScheme
                            .outlineVariant,
                      ),
                    ),
                    clipBehavior:
                    Clip.antiAlias,
                    child: Stack(
                      children: [
                        Signature(
                          controller:
                          _signatureController,
                          backgroundColor:
                          Colors.white,
                        ),

                        if (_signatureController
                            .isEmpty)
                          const IgnorePointer(
                            child: Center(
                              child: Column(
                                mainAxisSize:
                                MainAxisSize
                                    .min,
                                children: [
                                  Icon(
                                    Icons
                                        .draw_outlined,
                                    size: 34,
                                    color:
                                    Colors.grey,
                                  ),
                                  SizedBox(
                                    height: 8,
                                  ),
                                  Text(
                                    'Assine dentro da área',
                                    style:
                                    TextStyle(
                                      color:
                                      Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  Align(
                    alignment:
                    Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _isSaving ||
                          _signatureController
                              .isEmpty
                          ? null
                          : () {
                        setState(() {
                          _signatureController
                              .clear();

                          _errorMessage =
                          null;
                        });
                      },
                      icon: const Icon(
                        Icons.delete_outline,
                      ),
                      label: const Text(
                        'Limpar assinatura',
                      ),
                    ),
                  ),

                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    _ErrorBox(
                      message:
                      _errorMessage!,
                    ),
                  ],

                  /// Espaço para não ficar escondido
                  /// atrás da barra inferior.
                  const SizedBox(height: 90),
                ],
              ),
            ),
          ),
        ),

        bottomNavigationBar: _BottomBar(
          loading: _isSaving,
          onConfirmar:
          _handleConfirmar,
        ),
      ),
    );
  }
}

class _DocumentoHeader extends StatelessWidget {
  final String titulo;
  final String? numeroDocumento;
  final String? descricao;

  const _DocumentoHeader({
    required this.titulo,
    required this.numeroDocumento,
    required this.descricao,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: colors.primaryContainer
            .withValues(alpha: .32),
        borderRadius:
        BorderRadius.circular(16),
        border: Border.all(
          color: colors.primary
              .withValues(alpha: .16),
        ),
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: colors.primary
                  .withValues(alpha: .10),
              borderRadius:
              BorderRadius.circular(13),
            ),
            child: Icon(
              Icons.description_outlined,
              color: colors.primary,
              size: 27,
            ),
          ),

          const SizedBox(width: 13),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  titulo.toUpperCase(),
                  style: theme
                      .textTheme.titleMedium
                      ?.copyWith(
                    fontWeight:
                    FontWeight.w900,
                  ),
                ),

                if (_temTexto(
                  numeroDocumento,
                )) ...[
                  const SizedBox(height: 2),
                  Text(
                    numeroDocumento!,
                    style: theme
                        .textTheme.titleSmall
                        ?.copyWith(
                      color: colors
                          .onSurfaceVariant,
                      fontWeight:
                      FontWeight.w700,
                    ),
                  ),
                ],

                if (_temTexto(descricao)) ...[
                  const SizedBox(height: 7),
                  Text(
                    descricao!,
                    style: theme
                        .textTheme.bodySmall
                        ?.copyWith(
                      color: colors
                          .onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OperacaoCard extends StatelessWidget {
  final String? nomeCliente;
  final String? expositorNumero;
  final String? expositorModelo;

  final int? quantidadeSkus;
  final int? quantidadeUnidades;
  final int? quantidadeVendida;
  final int? valorAcertoCentavos;
  final int? valorReposicaoExpositorCentavos;

  const _OperacaoCard({
    required this.nomeCliente,
    required this.expositorNumero,
    required this.expositorModelo,
    required this.quantidadeSkus,
    required this.quantidadeUnidades,
    required this.quantidadeVendida,
    required this.valorAcertoCentavos,
    required this.valorReposicaoExpositorCentavos,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      child: Padding(
        padding:
        const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.stretch,
          children: [
            if (_temTexto(nomeCliente)) ...[
              Row(
                children: [
                  const Icon(
                    Icons.storefront_outlined,
                    size: 22,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      nomeCliente!,
                      style: theme
                          .textTheme.titleMedium
                          ?.copyWith(
                        fontWeight:
                        FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              const Divider(height: 1),
              const SizedBox(height: 13),
            ],

            if (_temTexto(expositorNumero))
              _OperacaoLinha(
                icon:
                Icons.inventory_2_outlined,
                label: 'Expositor',
                value: [
                  expositorNumero,
                  if (_temTexto(
                    expositorModelo,
                  ))
                    expositorModelo,
                ].whereType<String>().join(
                  ' • ',
                ),
              ),

            if (quantidadeSkus != null)
              _OperacaoLinha(
                icon: Icons.category_outlined,
                label:
                'SKUs no expositor',
                value:
                '$quantidadeSkus',
              ),

            if (quantidadeUnidades != null)
              _OperacaoLinha(
                icon: Icons.inventory_2_outlined,
                label:
                'Unidades no expositor',
                value:
                '$quantidadeUnidades un.',
              ),

            if (quantidadeVendida != null)
              _OperacaoLinha(
                icon:
                Icons.shopping_bag_outlined,
                label:
                'Produtos vendidos',
                value:
                '$quantidadeVendida un.',
              ),

            if (valorAcertoCentavos != null)
              _OperacaoLinha(
                icon:
                Icons.payments_outlined,
                label: 'Valor do acerto',
                value: formatarCentavos(
                  valorAcertoCentavos!,
                ),
                destaque: true,
              ),

            if (valorReposicaoExpositorCentavos !=
                null)
              _OperacaoLinha(
                icon:
                Icons.price_change_outlined,
                label:
                'Reposição do expositor',
                value: formatarCentavos(
                  valorReposicaoExpositorCentavos!,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OperacaoLinha extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool destaque;

  const _OperacaoLinha({
    required this.icon,
    required this.label,
    required this.value,
    this.destaque = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding:
      const EdgeInsets.symmetric(
        vertical: 6,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 19,
            color:
            theme.colorScheme.primary,
          ),

          const SizedBox(width: 9),

          Expanded(
            child: Text(
              label,
              style: theme
                  .textTheme.bodyMedium
                  ?.copyWith(
                color: theme.colorScheme
                    .onSurfaceVariant,
              ),
            ),
          ),

          const SizedBox(width: 12),

          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme
                  .textTheme.bodyMedium
                  ?.copyWith(
                fontWeight:
                destaque
                    ? FontWeight.w900
                    : FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context)
          .textTheme
          .labelLarge
          ?.copyWith(
        fontWeight: FontWeight.w900,
        letterSpacing: .25,
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final String message;

  const _InfoBox({
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme
            .colorScheme.primaryContainer
            .withValues(alpha: .25),
        borderRadius:
        BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            color:
            theme.colorScheme.primary,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: theme
                  .textTheme.bodySmall
                  ?.copyWith(
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;

  const _ErrorBox({
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final colors =
        Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius:
        BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            color: colors.error,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color:
                colors.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final bool loading;
  final VoidCallback onConfirmar;

  const _BottomBar({
    required this.loading,
    required this.onConfirmar,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color:
      theme.scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: Container(
          padding:
          const EdgeInsets.fromLTRB(
            16,
            10,
            16,
            12,
          ),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: theme.dividerColor,
              ),
            ),
          ),
          child: Align(
            alignment: Alignment.center,
            heightFactor: 1,
            child: ConstrainedBox(
              constraints:
              const BoxConstraints(
                maxWidth: 640,
              ),
              child: SizedBox(
                height: 50,
                width: double.infinity,
                child:
                FilledButton.icon(
                  onPressed:
                  loading
                      ? null
                      : onConfirmar,
                  icon: loading
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child:
                    CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                      : const Icon(
                    Icons
                        .draw_outlined,
                  ),
                  label: Text(
                    loading
                        ? 'Registrando assinatura...'
                        : 'Confirmar assinatura',
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

class _DocumentoInputFormatter
    extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    final digits =
    _somenteDigitos(newValue.text);

    final formatted =
    _formatarDocumento(digits);

    return TextEditingValue(
      text: formatted,
      selection:
      TextSelection.collapsed(
        offset: formatted.length,
      ),
    );
  }
}

class _TelefoneInputFormatter
    extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    final digits =
    _somenteDigitos(newValue.text);

    final formatted =
    _formatarTelefone(digits);

    return TextEditingValue(
      text: formatted,
      selection:
      TextSelection.collapsed(
        offset: formatted.length,
      ),
    );
  }
}

bool _temTexto(String? texto) {
  return texto != null &&
      texto.trim().isNotEmpty;
}

String _somenteDigitos(String valor) {
  return valor.replaceAll(
    RegExp(r'\D'),
    '',
  );
}

String _normalizarNome(String nome) {
  return nome
      .trim()
      .replaceAll(
    RegExp(r'\s+'),
    ' ',
  );
}

String _formatarDocumento(String valor) {
  final digits =
  _somenteDigitos(valor);

  if (digits.isEmpty) {
    return '';
  }

  if (digits.length <= 11) {
    final d = digits.substring(
      0,
      digits.length > 11
          ? 11
          : digits.length,
    );

    var result = '';

    for (var i = 0;
    i < d.length;
    i++) {
      if (i == 3 || i == 6) {
        result += '.';
      }

      if (i == 9) {
        result += '-';
      }

      result += d[i];
    }

    return result;
  }

  final d = digits.substring(
    0,
    digits.length > 14
        ? 14
        : digits.length,
  );

  var result = '';

  for (var i = 0;
  i < d.length;
  i++) {
    if (i == 2 || i == 5) {
      result += '.';
    }

    if (i == 8) {
      result += '/';
    }

    if (i == 12) {
      result += '-';
    }

    result += d[i];
  }

  return result;
}

String _formatarTelefone(String valor) {
  final digits =
  _somenteDigitos(valor);

  if (digits.isEmpty) {
    return '';
  }

  final d = digits.substring(
    0,
    digits.length > 11
        ? 11
        : digits.length,
  );

  if (d.length <= 2) {
    return '($d';
  }

  final ddd =
  d.substring(0, 2);

  final restante =
  d.substring(2);

  if (restante.length <= 4) {
    return '($ddd) $restante';
  }

  if (d.length <= 10) {
    return '($ddd) '
        '${restante.substring(0, 4)}-'
        '${restante.substring(4)}';
  }

  return '($ddd) '
      '${restante.substring(0, 5)}-'
      '${restante.substring(5)}';
}

String _formatarDataHora(DateTime data) {
  final local = data.toLocal();

  String dois(int valor) =>
      valor.toString().padLeft(2, '0');

  return '${dois(local.day)}/'
      '${dois(local.month)}/'
      '${local.year} às '
      '${dois(local.hour)}:'
      '${dois(local.minute)}';
}
