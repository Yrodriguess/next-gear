import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/widgets/responsive_center.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../clientes/presentation/cliente_providers.dart';
import '../../financeiro/documentos/data/documento_repository.dart';
import '../../financeiro/documentos/domain/documento_gerado.dart';
import '../../financeiro/documentos/presentation/assinatura_page.dart';
import '../../financeiro/documentos/presentation/documento_providers.dart';
import '../../financeiro/domain/pagamento.dart';
import '../../financeiro/presentation/financeiro_providers.dart';
import '../domain/visita_resultado.dart';

enum _FormaPagamento {
  dinheiro,
  pix,
  cobrarDepois,
}

enum _StatusPagamentoVisita {
  pendente,
  recebido,
  cobrarDepois,
}

class VisitaResultadoPage extends ConsumerStatefulWidget {
  final VisitaResultado resultado;
  final String orgId;
  final String clienteId;
  final String nomeCliente;
  final String cpfCnpjCliente;
  final String vendedorNome;

  const VisitaResultadoPage({
    super.key,
    required this.resultado,
    required this.orgId,
    required this.clienteId,
    required this.nomeCliente,
    required this.cpfCnpjCliente,
    required this.vendedorNome,
  });

  @override
  ConsumerState<VisitaResultadoPage> createState() =>
      _VisitaResultadoPageState();
}

class _VisitaResultadoPageState
    extends ConsumerState<VisitaResultadoPage> {
  _FormaPagamento? _formaEscolhida;
  _StatusPagamentoVisita _statusPagamento =
      _StatusPagamentoVisita.pendente;

  bool _isSaving = false;
  bool _isGerandoDocumento = false;
  bool _liberarSaida = false;

  String? _errorMessage;
  String? _documentoErrorMessage;

  DocumentoGerado? _documentoGerado;
  String? _telefoneResponsavel;

  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
    decimalDigits: 2,
  );

  bool get _ehInstalacao =>
      widget.resultado.consignmentAntigaNumero == null;

  bool get _temAcertoFinanceiro =>
      !_ehInstalacao &&
          widget.resultado.valorAPagarNextGearCentavos > 0;

  bool get _acertoResolvido =>
      !_temAcertoFinanceiro ||
          _statusPagamento != _StatusPagamentoVisita.pendente;

  String _reais(int centavos) =>
      _moeda.format(centavos / 100);

  bool get _pagamentoRecebido =>
      _statusPagamento == _StatusPagamentoVisita.recebido;

  bool get _cobrancaEmAberto =>
      _statusPagamento == _StatusPagamentoVisita.cobrarDepois;

  int get _totalSkus =>
      widget.resultado.itensNovaPosicao.length;

  int get _totalUnidades =>
      widget.resultado.itensNovaPosicao.fold<int>(
        0,
            (total, item) => total + item.quantidade,
      );

  String _formaLabel(_FormaPagamento forma) {
    return switch (forma) {
      _FormaPagamento.dinheiro => 'Dinheiro',
      _FormaPagamento.pix => 'Pix',
      _FormaPagamento.cobrarDepois => 'Cobrar depois',
    };
  }

  Future<void> _handleConfirmarForma() async {
    if (_ehInstalacao || !_temAcertoFinanceiro) return;

    if (_isSaving ||
        _statusPagamento != _StatusPagamentoVisita.pendente) {
      return;
    }

    final forma = _formaEscolhida;

    if (forma == null) {
      setState(() {
        _errorMessage =
        'Escolha uma opção antes de continuar.';
      });
      return;
    }

    if (forma == _FormaPagamento.cobrarDepois) {
      setState(() {
        _statusPagamento =
            _StatusPagamentoVisita.cobrarDepois;
        _errorMessage = null;
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final usuario = ref.read(appUserProvider).value;
      final formaLabel = _formaLabel(forma);

      await ref
          .read(pagamentoRepositoryProvider)
          .registrarEAlocar(
        orgId: widget.orgId,
        clienteId: widget.clienteId,
        valorTotalCentavos:
        widget.resultado.valorAPagarNextGearCentavos,
        observacao:
        'Recebido em $formaLabel no momento da visita '
            '${widget.resultado.visitaNumero}',
        formaPagamento:
        forma == _FormaPagamento.dinheiro
            ? FormaPagamento.dinheiro
            : FormaPagamento.pix,
        vendedorId: usuario?.uid,
      );

      if (!mounted) return;

      setState(() {
        _statusPagamento =
            _StatusPagamentoVisita.recebido;
        _errorMessage = null;
      });
    } catch (error, stackTrace) {
      debugPrint(
        'Erro ao registrar pagamento: '
            '$error\n$stackTrace',
      );

      if (!mounted) return;

      setState(() {
        _errorMessage =
        'Não foi possível registrar o pagamento. '
            'Confira sua conexão e tente novamente.';
      });
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<bool> _confirmarResumoAntesDaAssinatura({
    required String nomeCliente,
  }) async {
    final theme = Theme.of(context);
    final expositorNumero =
    widget.resultado.expositorNumero?.trim();
    final expositorModelo =
    widget.resultado.expositorModeloNome?.trim();

    final confirmado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            _ehInstalacao
                ? 'Confirmar consignação'
                : 'Confirmar acerto e consignação',
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Confira com o responsável antes de coletar '
                      'a assinatura.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                _LinhaResumo(
                  label: 'Cliente',
                  valor: nomeCliente,
                ),
                _LinhaResumo(
                  label: 'Visita',
                  valor: widget.resultado.visitaNumero,
                ),
                _LinhaResumo(
                  label: 'Consignação',
                  valor:
                  widget.resultado.consignmentNovaNumero,
                ),
                if (expositorNumero != null &&
                    expositorNumero.isNotEmpty)
                  _LinhaResumo(
                    label: 'Expositor',
                    valor: expositorModelo != null &&
                        expositorModelo.isNotEmpty
                        ? '$expositorNumero • $expositorModelo'
                        : expositorNumero,
                    manterValorEmUmaLinha: true,
                  ),
                _LinhaResumo(
                  label: 'Produtos',
                  valor: '$_totalSkus',
                ),
                _LinhaResumo(
                  label: 'Unidades consignadas',
                  valor: '$_totalUnidades',
                ),
                _LinhaResumo(
                  label: 'Valor em consignação',
                  valor: _reais(
                    widget.resultado.novaExposicaoCentavos,
                  ),
                  destaque: true,
                ),
                if (!_ehInstalacao &&
                    widget.resultado.valorAPagarNextGearCentavos >
                        0) ...[
                  const Divider(height: 24),
                  _LinhaResumo(
                    label: 'Valor do acerto',
                    valor: _reais(
                      widget.resultado
                          .valorAPagarNextGearCentavos,
                    ),
                    destaque: true,
                  ),
                ],
                const SizedBox(height: 14),
                Text(
                  _ehInstalacao
                      ? 'Ao continuar, o responsável confirma '
                      'o recebimento dos produtos em consignação '
                      'e do expositor informado.'
                      : 'Ao continuar, o responsável confirma '
                      'a conferência do ciclo anterior e a nova '
                      'posição consignada.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(false),
              child: const Text('Voltar'),
            ),
            FilledButton.icon(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.draw_outlined),
              label: const Text('Continuar para assinatura'),
            ),
          ],
        );
      },
    );

    return confirmado ?? false;
  }

  Future<void> _handleColetarAssinatura() async {
    if (_isGerandoDocumento || !_acertoResolvido) {
      return;
    }

    final tipo = _ehInstalacao
        ? DocumentoTipo.instalacao
        : DocumentoTipo.acertoEReposicao;

    final tituloDocumento = _ehInstalacao
        ? 'Termo de Instalação e Consignação Inicial'
        : 'Termo de Reposição e Acerto';

    final documentoRepository =
    ref.read(documentoRepositoryProvider);

    DocumentoPreparacao? preparacao;

    setState(() {
      _isGerandoDocumento = true;
      _documentoErrorMessage = null;
    });

    try {
      // Busca os dados atuais do cliente para o termo sair com
      // endereço e responsável atualizados.
      final clienteAtual = await ref
          .read(clienteRepositoryProvider)
          .fetchById(widget.clienteId);

      if (!mounted) return;

      if (clienteAtual == null) {
        throw StateError(
          'Cliente não encontrado para geração do documento.',
        );
      }

      final enderecoCliente = [
        clienteAtual.logradouro.trim(),
        clienteAtual.numero.trim(),
        clienteAtual.complemento?.trim() ?? '',
      ].where((parte) => parte.isNotEmpty).join(', ');

      // Etapa 3: se uma tentativa anterior falhou depois da
      // assinatura, retoma o MESMO número e a MESMA assinatura.
      preparacao =
      await documentoRepository.buscarPreparacaoDaVisita(
        orgId: widget.orgId,
        visitaId: widget.resultado.visitaId,
        tipo: tipo,
      );

      late final AssinaturaColetada assinaturaColetada;

      if (preparacao != null) {
        assinaturaColetada = AssinaturaColetada(
          nomeResponsavel:
          preparacao.assinatura.nomeResponsavel,
          documentoResponsavel:
          preparacao.assinatura.documentoResponsavel,
          telefoneResponsavel:
          preparacao.assinatura.telefoneResponsavel,
          assinaturaPng: preparacao.assinaturaPng,
          assinadaEm: preparacao.assinatura.timestamp,
        );
      } else {
        if (mounted) {
          setState(() {
            _isGerandoDocumento = false;
          });
        }

        final podeAssinar =
        await _confirmarResumoAntesDaAssinatura(
          nomeCliente: clienteAtual.nomeFantasia?.trim().isNotEmpty == true
              ? clienteAtual.nomeFantasia!.trim()
              : clienteAtual.nome,
        );

        if (!podeAssinar || !mounted) return;

        final coletada =
        await Navigator.of(context).push<AssinaturaColetada>(
          MaterialPageRoute(
            builder: (_) => AssinaturaPage(
              tituloDocumento: tituloDocumento,
            ),
          ),
        );

        if (coletada == null || !mounted) {
          return;
        }

        setState(() {
          _isGerandoDocumento = true;
          _documentoErrorMessage = null;
        });

        assinaturaColetada = coletada;

        final assinatura = Assinatura(
          nomeResponsavel: coletada.nomeResponsavel,
          documentoResponsavel:
          coletada.documentoResponsavel,
          telefoneResponsavel:
          coletada.telefoneResponsavel,
          timestamp: coletada.assinadaEm,
        );

        preparacao =
        await documentoRepository.prepararDocumentoAssinado(
          orgId: widget.orgId,
          tipo: tipo,
          clienteId: widget.clienteId,
          nomeCliente: clienteAtual.nome,
          visitaId: widget.resultado.visitaId,
          assinatura: assinatura,
          assinaturaPng: coletada.assinaturaPng,
        );
      }

      final numero = preparacao.numero;
      final pdfService = ref.read(pdfServiceProvider);

      final pdfBytes = _ehInstalacao
          ? await pdfService.gerarTermoInstalacao(
        numeroDocumento: numero,
        nomeCliente: clienteAtual.nome,
        cpfCnpjCliente: clienteAtual.cpfCnpj,
        vendedorNome: widget.vendedorNome,
        resultado: widget.resultado,
        assinatura: assinaturaColetada,
        enderecoCliente: enderecoCliente,
        bairroCliente: clienteAtual.bairro,
        cidadeCliente: clienteAtual.cidade,
        ufCliente: clienteAtual.uf,
        cepCliente: clienteAtual.cep,
      )
          : await pdfService.gerarTermoReposicao(
        numeroDocumento: numero,
        nomeCliente: clienteAtual.nome,
        cpfCnpjCliente: clienteAtual.cpfCnpj,
        vendedorNome: widget.vendedorNome,
        resultado: widget.resultado,
        assinatura: assinaturaColetada,
        enderecoCliente: enderecoCliente,
        bairroCliente: clienteAtual.bairro,
        cidadeCliente: clienteAtual.cidade,
        ufCliente: clienteAtual.uf,
        cepCliente: clienteAtual.cep,
      );

      final documento =
      await documentoRepository.salvarDocumento(
        orgId: widget.orgId,
        numero: numero,
        tipo: tipo,
        clienteId: widget.clienteId,
        nomeCliente: clienteAtual.nome,
        visitaId: widget.resultado.visitaId,
        pdfBytes: pdfBytes,
        assinatura: preparacao.assinatura,
      );

      if (!mounted) return;

      setState(() {
        _documentoGerado = documento;
        _telefoneResponsavel =
            preparacao!.assinatura.telefoneResponsavel;
        _documentoErrorMessage = null;
      });
    } catch (error, stackTrace) {
      debugPrint(
        'Erro ao gerar documento: '
            '$error\n$stackTrace',
      );

      if (preparacao != null) {
        try {
          await documentoRepository.marcarErroGeracao(
            orgId: widget.orgId,
            visitaId: widget.resultado.visitaId,
            tipo: tipo,
            erro: error,
          );
        } catch (_) {
          // Não mascara o erro principal.
        }
      }

      if (!mounted) return;

      setState(() {
        _documentoErrorMessage =
        preparacao == null
            ? 'Não foi possível preparar o documento. '
            'Tente novamente.'
            : 'Falha ao gerar ${preparacao.numero}. '
            'A assinatura foi preservada; tente novamente.';
      });
    } finally {
      if (mounted) {
        setState(() => _isGerandoDocumento = false);
      }
    }
  }

  Future<void> _handleVisualizarDocumento() async {
    final documento = _documentoGerado;

    if (documento == null ||
        documento.urlStorage.trim().isEmpty) {
      _mostrarMensagem(
        'O documento ainda não está disponível.',
        isError: true,
      );
      return;
    }

    final url = Uri.tryParse(documento.urlStorage);

    if (url == null) {
      _mostrarMensagem(
        'O link do documento é inválido.',
        isError: true,
      );
      return;
    }

    try {
      final abriu = kIsWeb
          ? await launchUrl(
        url,
        webOnlyWindowName: '_blank',
      )
          : await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      );

      if (!abriu && mounted) {
        _mostrarMensagem(
          'Não foi possível abrir o documento.',
          isError: true,
        );
      }
    } catch (error, stackTrace) {
      debugPrint(
        'Erro ao abrir documento: '
            '$error\n$stackTrace',
      );

      if (mounted) {
        _mostrarMensagem(
          'Não foi possível abrir o documento.',
          isError: true,
        );
      }
    }
  }

  Future<void> _handleEnviarWhatsApp() async {
    final documento = _documentoGerado;
    final telefoneOriginal =
        _telefoneResponsavel?.trim() ?? '';

    if (documento == null) {
      _mostrarMensagem(
        'Gere o documento antes de enviar.',
        isError: true,
      );
      return;
    }

    final telefoneLimpo =
    telefoneOriginal.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );

    if (telefoneLimpo.isEmpty) {
      _mostrarMensagem(
        'O responsável não possui telefone para WhatsApp.',
        isError: true,
      );
      return;
    }

    late final String telefoneComPais;

    if (telefoneLimpo.startsWith('55') &&
        (telefoneLimpo.length == 12 ||
            telefoneLimpo.length == 13)) {
      telefoneComPais = telefoneLimpo;
    } else if (telefoneLimpo.length == 10 ||
        telefoneLimpo.length == 11) {
      telefoneComPais = '55$telefoneLimpo';
    } else {
      _mostrarMensagem(
        'O telefone do responsável parece inválido. '
            'Confira DDD e número.',
        isError: true,
      );
      return;
    }

    final mensagem =
        'Olá! Segue o documento assinado da visita '
        '${widget.resultado.visitaNumero} '
        '(${documento.numero}) — NEXT GEAR:\n'
        '${documento.urlStorage}';

    final url = Uri.parse(
      'https://wa.me/$telefoneComPais'
          '?text=${Uri.encodeComponent(mensagem)}',
    );

    try {
      final abriu = kIsWeb
          ? await launchUrl(
        url,
        webOnlyWindowName: '_blank',
      )
          : await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      );

      if (!abriu && mounted) {
        _mostrarMensagem(
          'Não foi possível abrir o WhatsApp.',
          isError: true,
        );
      }
    } catch (error, stackTrace) {
      debugPrint(
        'Erro ao abrir WhatsApp: '
            '$error\n$stackTrace',
      );

      if (mounted) {
        _mostrarMensagem(
          'Não foi possível abrir o WhatsApp.',
          isError: true,
        );
      }
    }
  }

  void _mostrarMensagem(
      String mensagem, {
        bool isError = false,
      }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor:
        isError
            ? Theme.of(context).colorScheme.error
            : null,
      ),
    );
  }

  Future<bool> _confirmarSaida() async {
    if (_isSaving || _isGerandoDocumento) {
      _mostrarMensagem(
        'Aguarde a operação em andamento terminar.',
      );
      return false;
    }

    if (_documentoGerado != null) {
      return true;
    }

    final sair = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'Sair sem assinar o documento?',
        ),
        content: const Text(
          'O registro da visita foi salvo, mas o fluxo ainda não está '
              'finalizado porque falta a assinatura do documento. '
              'Você poderá retomar depois pela ficha do cliente.',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(false),
            child: const Text('Continuar aqui'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(true),
            child: const Text('Sair e retomar depois'),
          ),
        ],
      ),
    );

    return sair ?? false;
  }

  Future<void> _concluir() async {
    final podeSair = await _confirmarSaida();

    if (!podeSair || !mounted) return;

    setState(() => _liberarSaida = true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      Navigator.of(context).popUntil(
            (route) => route.isFirst,
      );
    });
  }

  Future<void> _interceptarVoltar(
      bool didPop,
      Object? result,
      ) async {
    if (didPop || _liberarSaida) {
      return;
    }

    final podeSair = await _confirmarSaida();

    if (!podeSair || !mounted) {
      return;
    }

    setState(() => _liberarSaida = true);

    Navigator.of(context).pop(result);
  }

  void _reabrirEscolhaPagamento() {
    if (!_cobrancaEmAberto ||
        _isSaving ||
        _isGerandoDocumento) {
      return;
    }

    setState(() {
      _statusPagamento =
          _StatusPagamentoVisita.pendente;
      _formaEscolhida = null;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final expositorNumero =
    widget.resultado.expositorNumero?.trim();
    final expositorModelo =
    widget.resultado.expositorModeloNome?.trim();

    return PopScope(
      canPop: _liberarSaida,
      onPopInvokedWithResult: _interceptarVoltar,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Visita ${widget.resultado.visitaNumero}',
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: ResponsiveCenter(
            maxWidth: 620,
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),

                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.green
                          .withValues(alpha: .12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.green,
                      size: 46,
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                Text(
                  'Visita concluída!',
                  textAlign: TextAlign.center,
                  style:
                  theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  _ehInstalacao
                      ? 'Os produtos foram registrados em consignação.'
                      : 'A conferência e a nova consignação '
                      'foram registradas.',
                  textAlign: TextAlign.center,
                  style:
                  theme.textTheme.bodyMedium?.copyWith(
                    color:
                    colorScheme.onSurfaceVariant,
                  ),
                ),

                const SizedBox(height: 24),

                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.receipt_long_outlined,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Resumo da visita',
                                style: theme
                                    .textTheme.titleMedium
                                    ?.copyWith(
                                  fontWeight:
                                  FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        _LinhaResumo(
                          label: 'Visita',
                          valor:
                          widget.resultado.visitaNumero,
                        ),
                        _LinhaResumo(
                          label: 'Consignação',
                          valor: widget.resultado
                              .consignmentNovaNumero,
                        ),

                        if (expositorNumero != null &&
                            expositorNumero.isNotEmpty)
                          _LinhaResumo(
                            label: 'Expositor',
                            valor: expositorModelo != null &&
                                expositorModelo.isNotEmpty
                                ? '$expositorNumero • $expositorModelo'
                                : expositorNumero,
                            manterValorEmUmaLinha: true,
                          ),

                        _LinhaResumo(
                          label: 'Produtos',
                          valor: '$_totalSkus',
                        ),
                        _LinhaResumo(
                          label: 'Unidades',
                          valor: '$_totalUnidades',
                        ),

                        const Divider(height: 24),

                        _LinhaResumo(
                          label: 'Valor em consignação',
                          valor: _reais(
                            widget.resultado
                                .novaExposicaoCentavos,
                          ),
                          destaque: true,
                        ),
                      ],
                    ),
                  ),
                ),

                if (widget.resultado
                    .consignmentAntigaNumero !=
                    null) ...[
                  const SizedBox(height: 14),

                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding:
                      const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Acerto do ciclo encerrado',
                            style: theme
                                .textTheme.titleMedium
                                ?.copyWith(
                              fontWeight:
                              FontWeight.w800,
                            ),
                          ),

                          const SizedBox(height: 4),

                          Text(
                            widget.resultado
                                .consignmentAntigaNumero!,
                            style: theme
                                .textTheme.bodySmall
                                ?.copyWith(
                              color: colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),

                          const SizedBox(height: 12),

                          _LinhaResumo(
                            label: 'Venda apurada',
                            valor: _reais(
                              widget.resultado
                                  .totalVendidoCentavos,
                            ),
                          ),
                          _LinhaResumo(
                            label:
                            'Comissão do lojista',
                            valor: _reais(
                              widget.resultado
                                  .comissaoRetidaCentavos,
                            ),
                          ),

                          const Divider(height: 20),

                          _LinhaResumo(
                            label:
                            'Valor a pagar à NEXT GEAR',
                            valor: _reais(
                              widget.resultado
                                  .valorAPagarNextGearCentavos,
                            ),
                            destaque: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                if (!_acertoResolvido) ...[
                  const SizedBox(height: 18),

                  Text(
                    'Acerto financeiro',
                    style: theme
                        .textTheme.titleMedium
                        ?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    'Informe como o valor referente às vendas do ciclo anterior '
                        'foi recebido. Se ainda não recebeu, mantenha '
                        'o acerto em aberto para o financeiro.',
                    style: theme
                        .textTheme.bodySmall
                        ?.copyWith(
                      color:
                      colorScheme.onSurfaceVariant,
                    ),
                  ),

                  const SizedBox(height: 10),

                  Card(
                    margin: EdgeInsets.zero,
                    child:
                    RadioGroup<_FormaPagamento>(
                      groupValue: _formaEscolhida,
                      onChanged: (valor) {
                        if (_isSaving) return;

                        setState(() {
                          _formaEscolhida = valor;
                          _errorMessage = null;
                        });
                      },
                      child: const Column(
                        children: [
                          RadioListTile<
                              _FormaPagamento>(
                            title: Text(
                              'Recebi em dinheiro agora',
                            ),
                            value:
                            _FormaPagamento.dinheiro,
                          ),
                          RadioListTile<
                              _FormaPagamento>(
                            title: Text(
                              'Recebi via Pix agora',
                            ),
                            value: _FormaPagamento.pix,
                          ),
                          RadioListTile<
                              _FormaPagamento>(
                            title: Text(
                              'Ainda não recebi — '
                                  'cobrar depois',
                            ),
                            value: _FormaPagamento
                                .cobrarDepois,
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (_errorMessage != null) ...[
                    const SizedBox(height: 10),
                    _MensagemStatus(
                      mensagem: _errorMessage!,
                      erro: true,
                    ),
                  ],

                  const SizedBox(height: 12),

                  FilledButton(
                    onPressed: _isSaving
                        ? null
                        : _handleConfirmarForma,
                    child: _isSaving
                        ? const SizedBox(
                      height: 20,
                      width: 20,
                      child:
                      CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                        : const Text(
                      'Confirmar acerto',
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 18),

                  if (_pagamentoRecebido)
                    const _MensagemStatus(
                      mensagem:
                      'Acerto recebido e registrado.',
                    )
                  else if (_cobrancaEmAberto)
                    _MensagemStatus(
                      mensagem:
                      'Acerto mantido em aberto para o financeiro.',
                      informativa: true,
                      acaoLabel: 'Alterar',
                      onAcao:
                      _reabrirEscolhaPagamento,
                    ),

                  if (_pagamentoRecebido ||
                      _cobrancaEmAberto)
                    const SizedBox(height: 18),

                  Text(
                    _documentoGerado != null
                        ? 'Documento assinado'
                        : _ehInstalacao
                        ? 'Documento da instalação'
                        : 'Documento da visita',
                    style: theme
                        .textTheme.titleMedium
                        ?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    _documentoGerado != null
                        ? 'O documento foi gerado e '
                        'está pronto para envio.'
                        : 'Confira o resumo acima e '
                        'colete a assinatura do '
                        'responsável para finalizar '
                        'o termo.',
                    style: theme
                        .textTheme.bodySmall
                        ?.copyWith(
                      color:
                      colorScheme.onSurfaceVariant,
                    ),
                  ),

                  if (_documentoErrorMessage !=
                      null) ...[
                    const SizedBox(height: 10),
                    _MensagemStatus(
                      mensagem:
                      _documentoErrorMessage!,
                      erro: true,
                    ),
                  ],

                  const SizedBox(height: 14),

                  if (_documentoGerado == null)
                    FilledButton.icon(
                      icon: _isGerandoDocumento
                          ? const SizedBox(
                        width: 18,
                        height: 18,
                        child:
                        CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                          : Icon(
                        _documentoErrorMessage !=
                            null
                            ? Icons.refresh_rounded
                            : Icons.draw_outlined,
                      ),
                      label: Text(
                        _isGerandoDocumento
                            ? 'Gerando documento...'
                            : _documentoErrorMessage !=
                            null
                            ? 'Tentar gerar novamente'
                            : 'Assinar e gerar '
                            'documento',
                      ),
                      onPressed: _isGerandoDocumento
                          ? null
                          : _handleColetarAssinatura,
                    )
                  else ...[
                    _MensagemStatus(
                      mensagem:
                      '${_documentoGerado!.numero} '
                          'gerado com sucesso.',
                    ),

                    const SizedBox(height: 12),

                    LayoutBuilder(
                      builder:
                          (context, constraints) {
                        final compacto =
                            constraints.maxWidth < 440;

                        final whatsapp =
                        FilledButton.icon(
                          icon: const Icon(
                            Icons.chat_bubble_outline,
                          ),
                          label: const Text(
                            'Enviar pelo WhatsApp',
                          ),
                          onPressed:
                          _handleEnviarWhatsApp,
                        );

                        final visualizar =
                        OutlinedButton.icon(
                          icon: const Icon(
                            Icons.visibility_outlined,
                          ),
                          label: const Text(
                            'Visualizar documento',
                          ),
                          onPressed:
                          _handleVisualizarDocumento,
                        );

                        if (compacto) {
                          return Column(
                            crossAxisAlignment:
                            CrossAxisAlignment
                                .stretch,
                            children: [
                              whatsapp,
                              const SizedBox(height: 8),
                              visualizar,
                            ],
                          );
                        }

                        return Row(
                          children: [
                            Expanded(
                              child: whatsapp,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: visualizar,
                            ),
                          ],
                        );
                      },
                    ),
                  ],

                  const SizedBox(height: 22),

                  if (_documentoGerado == null) ...[
                    Text(
                      'Assine e gere o documento para liberar '
                          'o botão Concluir.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  OutlinedButton(
                    onPressed: _documentoGerado == null ||
                        _isSaving ||
                        _isGerandoDocumento
                        ? null
                        : _concluir,
                    child: const Text('Concluir'),
                  ),
                ],

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MensagemStatus extends StatelessWidget {
  final String mensagem;
  final bool erro;
  final bool informativa;
  final String? acaoLabel;
  final VoidCallback? onAcao;

  const _MensagemStatus({
    required this.mensagem,
    this.erro = false,
    this.informativa = false,
    this.acaoLabel,
    this.onAcao,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final cor = erro
        ? theme.colorScheme.error
        : informativa
        ? theme.colorScheme.primary
        : Colors.green;

    final icone = erro
        ? Icons.error_outline_rounded
        : informativa
        ? Icons.schedule_outlined
        : Icons.check_circle_outline_rounded;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: cor.withValues(alpha: .25),
        ),
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Icon(
            icone,
            color: cor,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              mensagem,
              style:
              theme.textTheme.bodySmall?.copyWith(
                color: erro ? cor : null,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (acaoLabel != null &&
              onAcao != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onAcao,
              child: Text(acaoLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class _LinhaResumo extends StatelessWidget {
  final String label;
  final String valor;
  final bool destaque;
  final bool manterValorEmUmaLinha;

  const _LinhaResumo({
    required this.label,
    required this.valor,
    this.destaque = false,
    this.manterValorEmUmaLinha = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 4,
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: 14),
          Flexible(
            flex: manterValorEmUmaLinha ? 2 : 1,
            child: manterValorEmUmaLinha
                ? FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                valor,
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.end,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: destaque
                      ? FontWeight.w800
                      : FontWeight.w500,
                  fontSize: destaque ? 16 : null,
                ),
              ),
            )
                : Text(
              valor,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: destaque
                    ? FontWeight.w800
                    : FontWeight.w500,
                fontSize: destaque ? 16 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
