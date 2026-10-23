import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/money_input_formatter.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../clientes/presentation/cliente_providers.dart';
import '../../financeiro/documentos/data/documento_repository.dart';
import '../../financeiro/documentos/domain/documento_gerado.dart';
import '../../financeiro/documentos/presentation/assinatura_page.dart';
import '../../financeiro/documentos/presentation/documento_providers.dart';
import '../domain/visita_resultado.dart';

class RetiradaResultadoPage extends ConsumerStatefulWidget {
  final RetiradaResultado resultado;
  final String orgId;
  final String clienteId;
  final String nomeCliente;
  final String cpfCnpjCliente;
  final String vendedorNome;

  const RetiradaResultadoPage({
    super.key,
    required this.resultado,
    required this.orgId,
    required this.clienteId,
    required this.nomeCliente,
    required this.cpfCnpjCliente,
    required this.vendedorNome,
  });

  @override
  ConsumerState<RetiradaResultadoPage> createState() =>
      _RetiradaResultadoPageState();
}

class _RetiradaResultadoPageState
    extends ConsumerState<RetiradaResultadoPage> {
  bool _isGerandoDocumento = false;
  bool _liberarSaida = false;

  DocumentoGerado? _documentoGerado;
  String? _telefoneResponsavel;
  String? _documentoErrorMessage;

  int get _totalEsperado =>
      widget.resultado.itens.fold<int>(
        0,
            (total, item) => total + item.saldoEsperado,
      );

  int get _totalDevolvido =>
      widget.resultado.itens.fold<int>(
        0,
            (total, item) => total + item.quantidadeDevolvida,
      );

  int get _totalNaoDevolvido =>
      widget.resultado.itens.fold<int>(
        0,
            (total, item) => total + item.quantidadeNaoDevolvida,
      );

  Future<void> _handleColetarAssinatura() async {
    if (_isGerandoDocumento) return;

    const tipo = DocumentoTipo.encerramento;

    final documentoRepository =
    ref.read(documentoRepositoryProvider);

    DocumentoPreparacao? preparacao;

    setState(() {
      _isGerandoDocumento = true;
      _documentoErrorMessage = null;
    });

    try {
      final clienteAtual = await ref
          .read(clienteRepositoryProvider)
          .fetchById(widget.clienteId);

      if (!mounted) return;

      if (clienteAtual == null) {
        throw StateError(
          'Cliente não encontrado para geração do documento.',
        );
      }

      final nomeExibicao =
      clienteAtual.nomeFantasia?.trim().isNotEmpty == true
          ? clienteAtual.nomeFantasia!.trim()
          : clienteAtual.nome;

      final enderecoCliente = [
        clienteAtual.logradouro.trim(),
        clienteAtual.numero.trim(),
        clienteAtual.complemento?.trim() ?? '',
      ].where((parte) => parte.isNotEmpty).join(', ');

      // Etapa 3:
      // Se já houve assinatura e a geração falhou, retoma o MESMO
      // número e a MESMA assinatura.
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

        final coletada =
        await Navigator.of(context).push<AssinaturaColetada>(
          MaterialPageRoute(
            builder: (_) => AssinaturaPage(
              tituloDocumento:
              'Termo de Retirada e Encerramento',
              nomeCliente: nomeExibicao,
              expositorNumero:
              widget.resultado.expositorNumero,
              expositorModeloNome:
              widget.resultado.expositorModeloNome,
              quantidadeSkus:
              widget.resultado.itens.length,
              quantidadeUnidades: _totalDevolvido,
              valorAcertoCentavos:
              widget.resultado.valorARepassarTotalCentavos,
              descricaoDocumento:
              'Visita ${widget.resultado.visitaNumero} • '
                  'Consignação ${widget.resultado.consignmentEncerradaNumero}',
              textoConfirmacao:
              'Confirmo a retirada do expositor, a conferência '
                  'final dos produtos, o destino informado e o valor '
                  'do acerto apresentado nesta operação.',
              nomeResponsavelInicial:
              clienteAtual.nomeResponsavel,
              telefoneResponsavelInicial:
              clienteAtual.telefoneResponsavel,
            ),
          ),
        );

        if (coletada == null || !mounted) return;

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

      final pdfBytes =
      await pdfService.gerarTermoRetirada(
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
        'Erro ao gerar Termo de Retirada: '
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
            : 'Falha ao gerar ${preparacao!.numero}. '
            'A assinatura foi preservada; tente novamente.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isGerandoDocumento = false;
        });
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
        'Erro ao abrir documento de retirada: '
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
        'Olá! Segue o documento de retirada do expositor '
        '${widget.resultado.expositorNumero} '
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

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor:
          isError
              ? Theme.of(context).colorScheme.error
              : null,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<bool> _confirmarSaida() async {
    if (_isGerandoDocumento) {
      _mostrarMensagem(
        'Aguarde a geração do documento terminar.',
      );
      return false;
    }

    if (_documentoGerado != null) {
      return true;
    }

    final sair = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'Sair sem assinar o documento?',
        ),
        content: const Text(
          'A retirada já foi registrada, mas o fluxo ainda '
              'não está finalizado porque falta a assinatura '
              'do Termo de Retirada. Você poderá retomar depois '
              'pela ficha do cliente.',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(false),
            child: const Text('Continuar aqui'),
          ),
          FilledButton.tonal(
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
    if (_documentoGerado == null ||
        _isGerandoDocumento) {
      return;
    }

    setState(() {
      _liberarSaida = true;
    });

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
    if (didPop || _liberarSaida) return;

    final podeSair = await _confirmarSaida();

    if (!podeSair || !mounted) return;

    setState(() {
      _liberarSaida = true;
    });

    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final documentoGerado =
        _documentoGerado != null;

    return PopScope(
      canPop: _liberarSaida,
      onPopInvokedWithResult: _interceptarVoltar,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Retirada ${widget.resultado.visitaNumero}',
          ),
        ),
        body: SingleChildScrollView(
          padding:
          const EdgeInsets.only(bottom: 28),
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
                      Icons.inventory_2_outlined,
                      color: Colors.green,
                      size: 40,
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                Text(
                  'Retirada registrada!',
                  textAlign: TextAlign.center,
                  style:
                  theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  'A consignação foi encerrada e a retirada '
                      'do expositor foi registrada.',
                  textAlign: TextAlign.center,
                  style:
                  theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
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
                              Icons.fact_check_outlined,
                              color: colors.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Resumo da retirada',
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
                          label: 'Consignação encerrada',
                          valor: widget.resultado
                              .consignmentEncerradaNumero,
                        ),

                        _LinhaResumo(
                          label: 'Expositor',
                          valor:
                          widget.resultado.expositorNumero,
                        ),

                        _LinhaResumo(
                          label: 'Modelo',
                          valor: widget.resultado
                              .expositorModeloNome,
                        ),

                        _LinhaResumo(
                          label: 'Motivo',
                          valor: motivoRetiradaLabel(
                            widget.resultado.motivo,
                          ),
                          manterValorEmUmaLinha: true,
                        ),

                        _LinhaResumo(
                          label: 'Destino',
                          valor: widget.resultado
                              .destinoExpositorLabel,
                          manterValorEmUmaLinha: true,
                        ),

                        const Divider(height: 24),

                        _LinhaResumo(
                          label: 'SKUs conferidos',
                          valor:
                          '${widget.resultado.itens.length}',
                        ),

                        _LinhaResumo(
                          label: 'Unidades esperadas',
                          valor: '$_totalEsperado',
                        ),

                        _LinhaResumo(
                          label: 'Unidades devolvidas',
                          valor: '$_totalDevolvido',
                        ),

                        if (_totalNaoDevolvido > 0)
                          _LinhaResumo(
                            label:
                            'Unidades não devolvidas',
                            valor:
                            '$_totalNaoDevolvido',
                            alerta: true,
                          ),

                        const Divider(height: 24),

                        _LinhaResumo(
                          label: 'Valor do acerto final',
                          valor: formatarCentavos(
                            widget.resultado
                                .valorARepassarTotalCentavos,
                          ),
                          destaque: true,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                Text(
                  documentoGerado
                      ? 'Documento assinado'
                      : 'Documento da retirada',
                  style:
                  theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  documentoGerado
                      ? 'O Termo de Retirada foi gerado e '
                      'está pronto para envio.'
                      : 'Confira o resumo e colete a assinatura '
                      'do responsável para finalizar a retirada.',
                  style:
                  theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),

                if (_documentoErrorMessage != null) ...[
                  const SizedBox(height: 10),

                  _MensagemStatus(
                    mensagem:
                    _documentoErrorMessage!,
                    erro: true,
                  ),
                ],

                const SizedBox(height: 14),

                if (!documentoGerado)
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
                          : 'Assinar e gerar documento',
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
                    builder: (context, constraints) {
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
                          Expanded(child: whatsapp),
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

                if (!documentoGerado) ...[
                  Row(
                    mainAxisAlignment:
                    MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.lock_outline,
                        size: 16,
                        color:
                        colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Assine e gere o documento '
                              'para liberar o botão Concluir.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(
                            color:
                            colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],

                OutlinedButton(
                  onPressed: !documentoGerado ||
                      _isGerandoDocumento
                      ? null
                      : _concluir,
                  child: const Text('Concluir'),
                ),

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

  const _MensagemStatus({
    required this.mensagem,
    this.erro = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final cor = erro
        ? theme.colorScheme.error
        : Colors.green;

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
            erro
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
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
        ],
      ),
    );
  }
}

class _LinhaResumo extends StatelessWidget {
  final String label;
  final String valor;
  final bool destaque;
  final bool alerta;
  final bool manterValorEmUmaLinha;

  const _LinhaResumo({
    required this.label,
    required this.valor,
    this.destaque = false,
    this.alerta = false,
    this.manterValorEmUmaLinha = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            flex: manterValorEmUmaLinha ? 2 : 3,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: manterValorEmUmaLinha ? 8 : 7,
            child: manterValorEmUmaLinha
                ? FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                valor,
                maxLines: 1,
                softWrap: false,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: alerta ? colors.error : null,
                  fontWeight: destaque || alerta
                      ? FontWeight.w800
                      : FontWeight.w600,
                  fontSize: destaque ? 16 : null,
                ),
              ),
            )
                : Text(
              valor,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: alerta ? colors.error : null,
                fontWeight: destaque || alerta
                    ? FontWeight.w800
                    : FontWeight.w600,
                fontSize: destaque ? 16 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
