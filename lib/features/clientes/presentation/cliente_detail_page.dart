import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/br_formatters.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_providers.dart'
    hide usuariosListProvider;
import '../../auth/presentation/usuario_providers.dart';
import '../../consignacoes/domain/consignment.dart';
import '../../consignacoes/presentation/consignment_providers.dart';
import '../../expositores/domain/expositor_fisico.dart';
import '../../expositores/presentation/expositor_detail_page.dart';
import '../../expositores/presentation/expositor_providers.dart';
import '../../financeiro/documentos/data/documento_repository.dart';
import '../../financeiro/documentos/domain/documento_gerado.dart';
import '../../financeiro/documentos/presentation/assinatura_page.dart';
import '../../financeiro/documentos/presentation/documento_providers.dart';
import '../../financeiro/presentation/contas_receber_page.dart';
import '../../produtos/presentation/produto_providers.dart';
import '../../visitas/domain/visita.dart';
import '../../visitas/domain/visita_resultado.dart';
import '../../visitas/presentation/visita_cliente_selector_page.dart';
import '../../visitas/presentation/visita_providers.dart';
import '../data/cliente_repository.dart';
import '../domain/cliente.dart';
import 'cliente_edicao_page.dart';
import 'cliente_form_page.dart';
import 'cliente_providers.dart';

final _formatoMoeda = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 2,
);

String _formatarCentavos(int centavos) {
  return _formatoMoeda.format(centavos / 100);
}

double? _parseValorMonetarioBr(String entrada) {
  var texto = entrada
      .trim()
      .replaceAll(RegExp(r'[^0-9,.\-]'), '');

  if (texto.isEmpty) return null;

  if (texto.contains(',') && texto.contains('.')) {
    texto = texto.replaceAll('.', '').replaceAll(',', '.');
  } else if (texto.contains(',')) {
    texto = texto.replaceAll(',', '.');
  } else if (RegExp(r'^\-?\d{1,3}(\.\d{3})+$').hasMatch(texto)) {
    texto = texto.replaceAll('.', '');
  }

  return double.tryParse(texto);
}

String _normalizarTelefoneWhatsAppBr(String entrada) {
  final digitos = entrada.replaceAll(RegExp(r'[^0-9]'), '');

  if (digitos.isEmpty) return '';

  if (digitos.startsWith('55') &&
      (digitos.length == 12 || digitos.length == 13)) {
    return digitos;
  }

  if (digitos.length == 10 || digitos.length == 11) {
    return '55$digitos';
  }

  return digitos.startsWith('55') ? digitos : '55$digitos';
}

class ClienteDetailPage extends ConsumerStatefulWidget {
  final String clienteId;

  const ClienteDetailPage({
    super.key,
    required this.clienteId,
  });

  @override
  ConsumerState<ClienteDetailPage> createState() =>
      _ClienteDetailPageState();
}

class _ClienteDetailPageState extends ConsumerState<ClienteDetailPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final _limiteController = TextEditingController();
  final _comissaoController = TextEditingController();

  bool _isSaving = false;
  bool _isOpeningVisit = false;
  bool _prefilled = false;
  String? _documentoPendenteProcessandoId;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _limiteController.dispose();
    _comissaoController.dispose();
    super.dispose();
  }

  void _prefillIfNeeded(Cliente cliente) {
    if (_prefilled) return;

    if (cliente.limiteCreditoCentavos > 0) {
      _limiteController.text = (cliente.limiteCreditoCentavos / 100)
          .toStringAsFixed(2)
          .replaceAll('.', ',');
    }

    _comissaoController.text =
        (cliente.comissaoBasisPoints / 100).toStringAsFixed(1);
    _prefilled = true;
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
          backgroundColor:
          isError ? colorScheme.error : colorScheme.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _atualizarPagina() {
    ref.invalidate(clienteByIdProvider(widget.clienteId));
    ref.invalidate(
      consignmentsTodasAtivasDoClienteProvider(widget.clienteId),
    );
    ref.invalidate(visitaHistoricoDoClienteProvider(widget.clienteId));
    ref.invalidate(documentosDoClienteProvider(widget.clienteId));
    ref.invalidate(expositoresFisicosListProvider);
  }

  Future<void> _handleAprovar(Cliente cliente) async {
    final usuario = ref.read(appUserProvider).value;
    if (usuario == null) {
      _mostrarMensagem('Usuário não autenticado.', isError: true);
      return;
    }

    final podeAnalisar = usuario.role == UserRole.admin ||
        usuario.role == UserRole.financeiro;
    if (!podeAnalisar) {
      _mostrarMensagem(
        'Somente Admin ou Financeiro pode aprovar clientes.',
        isError: true,
      );
      return;
    }

    final limiteReais = _parseValorMonetarioBr(_limiteController.text);
    final comissaoPercentual = double.tryParse(
      _comissaoController.text.trim().replaceAll(',', '.'),
    );

    if (limiteReais == null || limiteReais < 0) {
      setState(
            () => _errorMessage =
        'Limite de crédito inválido. Ex.: 1500,00 ou 1.500,00.',
      );
      return;
    }

    if (comissaoPercentual == null ||
        comissaoPercentual < 0 ||
        comissaoPercentual > 100) {
      setState(
            () => _errorMessage = 'A comissão precisa estar entre 0% e 100%.',
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await ref.read(clienteRepositoryProvider).aprovar(
        clienteId: cliente.id!,
        limiteCreditoCentavos: (limiteReais * 100).round(),
        comissaoBasisPoints: (comissaoPercentual * 100).round(),
        usuarioId: usuario.uid,
      );

      if (!mounted) return;

      _mostrarMensagem('Cliente aprovado com sucesso.');
      _tabController.animateTo(0);
      _atualizarPagina();
    } on ExpositorIndisponivelException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.toString());
    } catch (error, stackTrace) {
      debugPrint('Erro ao aprovar cliente: $error\n$stackTrace');

      if (!mounted) return;
      setState(
            () => _errorMessage =
        'Não foi possível aprovar o cliente. Tente novamente.',
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _ajustarLimiteCredito(Cliente cliente) async {
    final usuario = ref.read(appUserProvider).value;

    if (usuario == null) {
      _mostrarMensagem('Usuário não autenticado.', isError: true);
      return;
    }

    final podeAjustar = usuario.role == UserRole.admin ||
        usuario.role == UserRole.financeiro;

    if (!podeAjustar) {
      _mostrarMensagem(
        'Somente Admin ou Financeiro pode alterar o limite de crédito.',
        isError: true,
      );
      return;
    }

    if (cliente.statusCadastro != StatusCadastro.aprovado) {
      _mostrarMensagem(
        'O limite pode ser alterado após a aprovação do cliente.',
        isError: true,
      );
      return;
    }

    var valorDigitado =
    (cliente.limiteCreditoCentavos / 100)
        .toStringAsFixed(2)
        .replaceAll('.', ',');

    final valorInformado = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Editar limite de crédito'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: TextFormField(
            initialValue: valorDigitado,
            autofocus: true,
            keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Novo limite',
              prefixText: 'R\$ ',
              hintText: 'Ex.: 1.500,00',
              helperText:
              'Aceita 1500, 1.500, 1500,00 ou 1.500,00.',
            ),
            onChanged: (value) => valorDigitado = value,
            onFieldSubmitted: (value) =>
                Navigator.of(dialogContext).pop(value),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(valorDigitado),
            child: const Text('Salvar limite'),
          ),
        ],
      ),
    );

    if (valorInformado == null || !mounted) return;

    final novoLimiteReais =
    _parseValorMonetarioBr(valorInformado);

    if (novoLimiteReais == null || novoLimiteReais < 0) {
      _mostrarMensagem(
        'Informe um limite de crédito válido.',
        isError: true,
      );
      return;
    }

    final novoLimiteCentavos =
    (novoLimiteReais * 100).round();

    if (novoLimiteCentavos == cliente.limiteCreditoCentavos) {
      _mostrarMensagem('O limite informado já é o limite atual.');
      return;
    }

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmar novo limite?'),
        content: Text(
          'Limite atual: '
              '${_formatarCentavos(cliente.limiteCreditoCentavos)}\n'
              'Novo limite: ${_formatarCentavos(novoLimiteCentavos)}',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmou != true || !mounted) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await ref.read(clienteRepositoryProvider).ajustarLimiteCredito(
        clienteId: cliente.id!,
        novoLimiteCentavos: novoLimiteCentavos,
      );

      if (!mounted) return;

      ref.invalidate(clienteByIdProvider(widget.clienteId));
      ref.invalidate(clientesListProvider);

      _mostrarMensagem(
        'Limite de crédito atualizado para '
            '${_formatarCentavos(novoLimiteCentavos)}.',
      );
    } catch (error, stackTrace) {
      debugPrint(
        'Erro ao ajustar limite de crédito: $error\n$stackTrace',
      );

      if (!mounted) return;

      _mostrarMensagem(
        'Não foi possível atualizar o limite de crédito.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _handleReprovar(Cliente cliente) async {
    final usuario = ref.read(appUserProvider).value;
    if (usuario == null) {
      _mostrarMensagem('Usuário não autenticado.', isError: true);
      return;
    }

    final podeAnalisar = usuario.role == UserRole.admin ||
        usuario.role == UserRole.financeiro;
    if (!podeAnalisar) {
      _mostrarMensagem(
        'Somente Admin ou Financeiro pode reprovar clientes.',
        isError: true,
      );
      return;
    }

    var motivoDigitado = '';

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Reprovar cliente?'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (cliente.expositorFisicoSelecionadoId != null) ...[
                  const _DialogWarning(
                    mensagem:
                    'O expositor reservado será liberado e voltará a '
                        'ficar disponível.',
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  initialValue: motivoDigitado,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Motivo da reprovação',
                    hintText: 'Opcional',
                    alignLabelWithHint: true,
                  ),
                  onChanged: (value) => motivoDigitado = value,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Reprovar'),
            ),
          ],
        );
      },
    );

    if (confirmado != true || !mounted) {
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await ref.read(clienteRepositoryProvider).reprovar(
        clienteId: cliente.id!,
        usuarioId: usuario.uid,
        motivo: motivoDigitado.trim().isEmpty
            ? null
            : motivoDigitado.trim(),
      );

      if (!mounted) return;

      _mostrarMensagem('Cliente reprovado.');
      _atualizarPagina();
    } catch (error, stackTrace) {
      debugPrint('Erro ao reprovar cliente: $error\n$stackTrace');

      if (!mounted) return;
      setState(
            () => _errorMessage =
        'Não foi possível reprovar. Confira a reserva e tente novamente.',
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _abrirWhatsAppCliente(Cliente cliente) async {
    final telefone =
    cliente.telefoneResponsavel.replaceAll(RegExp(r'[^0-9]'), '');

    if (telefone.isEmpty) {
      _mostrarMensagem(
        'Este cliente não possui telefone cadastrado.',
        isError: true,
      );
      return;
    }

    final telefoneComPais = _normalizarTelefoneWhatsAppBr(telefone);
    final mensagem = Uri.encodeComponent(
      'Olá, ${cliente.nomeResponsavel}! Tudo bem?',
    );
    final uri = Uri.parse('https://wa.me/$telefoneComPais?text=$mensagem');

    final abriu = await launchUrl(
      uri,
      mode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
      webOnlyWindowName: kIsWeb ? '_blank' : null,
    );

    if (!abriu) {
      _mostrarMensagem('Não foi possível abrir o WhatsApp.', isError: true);
    }
  }

  Future<void> _abrirDocumento(DocumentoGerado documento) async {
    final uri = Uri.tryParse(documento.urlStorage);

    if (uri == null || !uri.hasScheme) {
      _mostrarMensagem('O endereço deste documento é inválido.', isError: true);
      return;
    }

    final abriu = await launchUrl(
      uri,
      mode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
      webOnlyWindowName: kIsWeb ? '_blank' : null,
    );

    if (!abriu) {
      _mostrarMensagem('Não foi possível abrir o documento.', isError: true);
    }
  }

  Future<void> _compartilharDocumento(
      Cliente cliente,
      DocumentoGerado documento,
      ) async {
    final telefone =
    cliente.telefoneResponsavel.replaceAll(RegExp(r'[^0-9]'), '');
    final telefoneComPais =
    telefone.isEmpty ? '' : _normalizarTelefoneWhatsAppBr(telefone);

    final mensagem = Uri.encodeComponent(
      'Olá! Segue o documento assinado ${documento.numero} — NEXT GEAR:\n'
          '${documento.urlStorage}',
    );

    final uri = telefoneComPais.isEmpty
        ? Uri.parse('https://wa.me/?text=$mensagem')
        : Uri.parse('https://wa.me/$telefoneComPais?text=$mensagem');

    final abriu = await launchUrl(
      uri,
      mode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
      webOnlyWindowName: kIsWeb ? '_blank' : null,
    );

    if (!abriu) {
      _mostrarMensagem(
        'Não foi possível compartilhar o documento.',
        isError: true,
      );
    }
  }

  Future<void> _assinarDocumentoPendente(
      Cliente cliente,
      Visita visita,
      ) async {
    final visitaId = visita.id?.trim();

    if (visitaId == null || visitaId.isEmpty) {
      _mostrarMensagem(
        'Esta visita não possui identificador válido.',
        isError: true,
      );
      return;
    }

    if (_documentoPendenteProcessandoId != null) {
      return;
    }

    final tipoDocumento = switch (visita.tipo) {
      VisitaTipo.instalacao => DocumentoTipo.instalacao,
      VisitaTipo.visita => DocumentoTipo.acertoEReposicao,
      VisitaTipo.coleta => DocumentoTipo.encerramento,
      _ => null,
    };

    if (tipoDocumento == null) {
      _mostrarMensagem(
        'Este tipo de visita não gera documento para assinatura.',
        isError: true,
      );
      return;
    }

    setState(() {
      _documentoPendenteProcessandoId = visitaId;
    });

    DocumentoPreparacao? preparacao;

    try {
      final visitaRepository = ref.read(visitaRepositoryProvider);
      final documentoRepository =
      ref.read(documentoRepositoryProvider);

      var snapshot =
      await visitaRepository.carregarSnapshotDocumento(visitaId);

      // Compatibilidade com instalações concluídas antes da criação do
      // snapshot de documento. Só reconstruímos quando é seguro usar a
      // consignação ativa daquele expositor.
      if (snapshot == null && visita.tipo == VisitaTipo.instalacao) {
        snapshot = await _reconstruirSnapshotInstalacaoAntiga(
          cliente: cliente,
          visita: visita,
        );

        if (snapshot != null) {
          await visitaRepository.salvarSnapshotDocumentoPendente(
            visitaId: visitaId,
            snapshot: snapshot,
          );
        }
      }

      if (snapshot == null) {
        _mostrarMensagem(
          visita.tipo == VisitaTipo.instalacao
              ? 'Esta instalação antiga não possui dados suficientes para '
              'reconstruir o documento com segurança.'
              : 'Esta visita foi concluída antes do salvamento do snapshot '
              'do documento. Não é seguro reconstruir os valores.',
          isError: true,
        );
        return;
      }

      final vendedorNome =
      await _resolverNomeVendedor(visita.vendedorId);

      final tituloDocumento = switch (tipoDocumento) {
        DocumentoTipo.instalacao =>
        'Instalação e Consignação Inicial',
        DocumentoTipo.acertoEReposicao =>
        'Reposição e Acerto',
        DocumentoTipo.encerramento =>
        'Retirada e Encerramento',
      };

      VisitaResultado? resultado;
      RetiradaResultado? retiradaResultado;

      if (tipoDocumento == DocumentoTipo.encerramento) {
        retiradaResultado = _retiradaResultadoDoSnapshot(
          visita,
          snapshot,
        );
      } else {
        resultado = _visitaResultadoDoSnapshot(
          visita,
          snapshot,
        );
      }

      final quantidadeSkus = resultado?.itensNovaPosicao.length ??
          retiradaResultado?.itens.length;

      final quantidadeUnidades = resultado != null
          ? resultado.itensNovaPosicao.fold<int>(
        0,
            (total, item) => total + item.quantidade,
      )
          : retiradaResultado?.itens.fold<int>(
        0,
            (total, item) => total + item.saldoEsperado,
      );

      final quantidadeVendida = resultado == null
          ? null
          : resultado.itensCicloEncerrado.fold<int>(
        0,
            (total, item) => total + item.quantidadeVendida,
      );

      final valorAcerto =
          resultado?.valorAPagarNextGearCentavos ??
              retiradaResultado?.valorARepassarTotalCentavos;

      final expositorNumero =
          resultado?.expositorNumero ??
              retiradaResultado?.expositorNumero;
      final expositorModelo =
          resultado?.expositorModeloNome ??
              retiradaResultado?.expositorModeloNome;

      // Se uma tentativa anterior falhou depois da assinatura,
      // recupera o MESMO número e a MESMA assinatura.
      preparacao =
      await documentoRepository.buscarPreparacaoDaVisita(
        orgId: visita.orgId,
        visitaId: visitaId,
        tipo: tipoDocumento,
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
        final coletada =
        await Navigator.of(context).push<AssinaturaColetada>(
          MaterialPageRoute(
            builder: (_) => AssinaturaPage(
              tituloDocumento: tituloDocumento,
              nomeCliente: _nomeExibicaoCliente(cliente),
              expositorNumero: expositorNumero,
              expositorModeloNome: expositorModelo,
              quantidadeSkus: quantidadeSkus,
              quantidadeUnidades: quantidadeUnidades,
              quantidadeVendida: quantidadeVendida,
              valorAcertoCentavos: valorAcerto,
              valorReposicaoExpositorCentavos:
              tipoDocumento == DocumentoTipo.instalacao
                  ? _valorReposicaoExpositorCentavos(
                expositorModelo,
              )
                  : null,
              descricaoDocumento:
              'Visita ${visita.numero ?? visitaId}',
              textoConfirmacao:
              _textoConfirmacaoDocumento(tipoDocumento),
              nomeResponsavelInicial:
              cliente.nomeResponsavel,
              telefoneResponsavelInicial:
              cliente.telefoneResponsavel,
            ),
          ),
        );

        if (coletada == null || !mounted) {
          return;
        }

        assinaturaColetada = coletada;

        final assinatura = Assinatura(
          nomeResponsavel: coletada.nomeResponsavel,
          documentoResponsavel:
          coletada.documentoResponsavel,
          telefoneResponsavel:
          coletada.telefoneResponsavel,
          timestamp: coletada.assinadaEm,
        );

        // Reserva número + persiste assinatura antes de gerar o PDF.
        preparacao =
        await documentoRepository.prepararDocumentoAssinado(
          orgId: visita.orgId,
          tipo: tipoDocumento,
          clienteId: cliente.id!,
          nomeCliente: cliente.nome,
          visitaId: visitaId,
          assinatura: assinatura,
          assinaturaPng: coletada.assinaturaPng,
        );
      }

      final numero = preparacao.numero;
      final pdfService = ref.read(pdfServiceProvider);

      final endereco = [
        cliente.logradouro.trim(),
        cliente.numero.trim(),
        cliente.complemento?.trim() ?? '',
      ].where((parte) => parte.isNotEmpty).join(', ');

      final pdfBytes = switch (tipoDocumento) {
        DocumentoTipo.instalacao =>
        await pdfService.gerarTermoInstalacao(
          numeroDocumento: numero,
          nomeCliente: cliente.nome,
          cpfCnpjCliente: cliente.cpfCnpj,
          vendedorNome: vendedorNome,
          resultado: resultado!,
          assinatura: assinaturaColetada,
          enderecoCliente: endereco,
          bairroCliente: cliente.bairro,
          cidadeCliente: cliente.cidade,
          ufCliente: cliente.uf,
          cepCliente: cliente.cep,
        ),
        DocumentoTipo.acertoEReposicao =>
        await pdfService.gerarTermoReposicao(
          numeroDocumento: numero,
          nomeCliente: cliente.nome,
          cpfCnpjCliente: cliente.cpfCnpj,
          vendedorNome: vendedorNome,
          resultado: resultado!,
          assinatura: assinaturaColetada,
          enderecoCliente: endereco,
          bairroCliente: cliente.bairro,
          cidadeCliente: cliente.cidade,
          ufCliente: cliente.uf,
          cepCliente: cliente.cep,
        ),
        DocumentoTipo.encerramento =>
        await pdfService.gerarTermoRetirada(
          numeroDocumento: numero,
          nomeCliente: cliente.nome,
          cpfCnpjCliente: cliente.cpfCnpj,
          vendedorNome: vendedorNome,
          resultado: retiradaResultado!,
          assinatura: assinaturaColetada,
          enderecoCliente: endereco,
          bairroCliente: cliente.bairro,
          cidadeCliente: cliente.cidade,
          ufCliente: cliente.uf,
          cepCliente: cliente.cep,
        ),
      };

      await documentoRepository.salvarDocumento(
        orgId: visita.orgId,
        numero: numero,
        tipo: tipoDocumento,
        clienteId: cliente.id!,
        nomeCliente: cliente.nome,
        visitaId: visitaId,
        pdfBytes: pdfBytes,
        assinatura: preparacao.assinatura,
      );

      if (!mounted) return;

      ref.invalidate(documentosDoClienteProvider(cliente.id!));
      ref.invalidate(visitaHistoricoDoClienteProvider(cliente.id!));

      _mostrarMensagem(
        '$numero assinado e gerado com sucesso.',
      );
    } catch (error, stackTrace) {
      debugPrint(
        'Erro ao concluir documento pendente: $error\n$stackTrace',
      );

      if (preparacao != null) {
        try {
          await ref.read(documentoRepositoryProvider).marcarErroGeracao(
            orgId: visita.orgId,
            visitaId: visitaId,
            tipo: tipoDocumento,
            erro: error,
          );
        } catch (_) {
          // Não mascara o erro principal.
        }
      }

      if (mounted) {
        _mostrarMensagem(
          preparacao == null
              ? 'Não foi possível preparar o documento. Tente novamente.'
              : 'Não foi possível concluir ${preparacao.numero}. '
              'A assinatura foi preservada; tente novamente.',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _documentoPendenteProcessandoId = null;
        });
      }
    }
  }

  Future<Map<String, dynamic>?> _reconstruirSnapshotInstalacaoAntiga({
    required Cliente cliente,
    required Visita visita,
  }) async {
    final clienteId = cliente.id;
    if (clienteId == null || clienteId.isEmpty) return null;

    // Se já houve outra visita concluída depois nesse mesmo expositor,
    // a posição atual pode ter mudado. Nesse cenário não reconstruímos
    // um documento antigo usando dados atuais.
    final historico =
    await ref.read(visitaHistoricoDoClienteProvider(clienteId).future);
    final dataOriginal = visita.finalizadaEm ?? visita.criadaEm;

    for (final outra in historico) {
      if (outra.id == visita.id) continue;
      if (outra.expositorId != visita.expositorId) continue;
      if (!_visitaConcluida(outra)) continue;

      final dataOutra = outra.finalizadaEm ?? outra.criadaEm;

      if (dataOriginal == null || dataOutra == null) {
        return null;
      }

      if (dataOutra.isAfter(dataOriginal)) {
        return null;
      }
    }

    final consignacoes = await ref
        .read(consignmentRepositoryProvider)
        .watchTodasAtivasDoCliente(clienteId)
        .first;

    Consignment? consignacao;

    for (final item in consignacoes) {
      if (visita.expositorId != null &&
          item.expositorId == visita.expositorId) {
        consignacao = item;
        break;
      }
    }

    if (consignacao == null && consignacoes.length == 1) {
      consignacao = consignacoes.first;
    }

    if (consignacao == null) {
      return null;
    }

    final skus = await ref.read(skusListProvider.future);
    final codigoPorSku = <String, String>{
      for (final sku in skus)
        if (sku.id != null) sku.id!: sku.codigoInterno,
    };

    final expositores = await ref.read(expositoresFisicosListProvider.future);
    ExpositorFisico? expositor;

    for (final item in expositores) {
      if (item.id == consignacao.expositorId) {
        expositor = item;
        break;
      }
    }

    return {
      'versao': 1,
      'tipoDocumento': 'instalacao',
      'clienteId': clienteId,
      'clienteNome': cliente.nome,
      'clienteNomeFantasia': cliente.nomeFantasia,
      'clienteCpfCnpj': cliente.cpfCnpj,
      'vendedorId': visita.vendedorId,
      'consignmentNovaNumero': consignacao.numero,
      'novaExposicaoCentavos': consignacao.valorLiquidoTotalCentavos,
      'expositorNumero': expositor?.numero,
      'expositorModeloNome': expositor?.modeloNome,
      'itensCicloEncerrado': const <Map<String, dynamic>>[],
      'itensNovaPosicao': consignacao.itens
          .map(
            (item) => <String, dynamic>{
          'skuId': item.produtoId,
          'codigoInterno':
          codigoPorSku[item.produtoId] ?? item.produtoId,
          'descricao': item.descricaoSnapshot,
          'quantidade': item.quantidade,
          'precoVendaCentavosUnit': item.precoVendaCentavos,
          'comissaoCentavosUnit': item.comissaoCentavos,
          'saldoAnteriorQuantidade': null,
          'quantidadeConferida': null,
          'quantidadeReposta': null,
        },
      )
          .toList(),
    };
  }

  Future<String> _resolverNomeVendedor(String vendedorId) async {
    try {
      final usuarios = await ref.read(usuariosListProvider.future);

      for (final usuario in usuarios) {
        if (usuario.uid == vendedorId) {
          return usuario.nome;
        }
      }
    } catch (_) {
      // Usa o fallback abaixo.
    }

    final atual = ref.read(appUserProvider).value;
    if (atual != null && atual.uid == vendedorId) {
      return atual.nome;
    }

    return 'Vendedor NEXT GEAR';
  }

  Future<void> _abrirNovaVisita(Cliente cliente) async {
    if (_isOpeningVisit) return;

    final clienteId = cliente.id?.trim();

    if (clienteId == null || clienteId.isEmpty) {
      _mostrarMensagem(
        'Cliente sem identificador válido.',
        isError: true,
      );
      return;
    }

    setState(() => _isOpeningVisit = true);

    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VisitaClienteSelectorPage(
            clienteIdInicial: clienteId,
          ),
        ),
      );

      if (!mounted) return;

      // Ao voltar da Agenda, recarrega a ficha para refletir
      // instalação, visita, consignação e documentos atualizados.
      _atualizarPagina();
      ref.invalidate(clientesListProvider);
      ref.invalidate(visitasEmAndamentoProvider);
      ref.invalidate(visitasRealizadasProvider);
    } catch (error, stackTrace) {
      debugPrint(
        'Erro ao abrir fluxo de visitas: $error\n$stackTrace',
      );

      _mostrarMensagem(
        'Não foi possível abrir o fluxo de visitas.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isOpeningVisit = false);
      }
    }
  }

  Future<void> _prepararNovaInstalacao(Cliente cliente) async {
    if (_isOpeningVisit) return;

    final usuario = ref.read(appUserProvider).value;
    if (usuario == null) {
      _mostrarMensagem('Usuário não autenticado.', isError: true);
      return;
    }

    final clienteId = cliente.id?.trim();
    if (clienteId == null || clienteId.isEmpty) {
      _mostrarMensagem(
        'Cliente sem identificador válido.',
        isError: true,
      );
      return;
    }

    if (cliente.statusCadastro != StatusCadastro.aprovado ||
        cliente.statusOperacional != StatusOperacional.encerrado) {
      _mostrarMensagem(
        'Este cliente não está disponível para uma nova instalação.',
        isError: true,
      );
      return;
    }

    if (cliente.statusFinanceiro == StatusFinanceiro.bloqueado) {
      _mostrarMensagem(
        'Regularize a situação financeira antes de reservar '
            'um novo expositor.',
        isError: true,
      );
      return;
    }

    setState(() => _isOpeningVisit = true);

    try {
      final todosExpositores =
      await ref.read(expositoresFisicosListProvider.future);

      final disponiveis = todosExpositores
          .where(
            (expositor) =>
        expositor.orgId == cliente.orgId &&
            expositor.status == ExpositorStatus.disponivel &&
            expositor.id != null &&
            expositor.id!.isNotEmpty,
      )
          .toList()
        ..sort((a, b) => a.numero.compareTo(b.numero));

      if (!mounted) return;

      if (disponiveis.isEmpty) {
        _mostrarMensagem(
          'Não há expositor disponível para uma nova instalação.',
          isError: true,
        );
        return;
      }

      final selecionado = await showDialog<ExpositorFisico>(
        context: context,
        builder: (dialogContext) {
          final alturaDisponivel =
              MediaQuery.sizeOf(dialogContext).height * 0.55;
          final alturaConteudo =
          alturaDisponivel > 440 ? 440.0 : alturaDisponivel;

          return AlertDialog(
            title: const Text('Nova instalação'),
            content: SizedBox(
              width: 520,
              height: alturaConteudo,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Selecione o expositor que será reservado para '
                        '${_nomeExibicaoCliente(cliente)}.',
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: disponiveis.length,
                      separatorBuilder: (_, __) =>
                      const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final expositor = disponiveis[index];

                        return ListTile(
                          contentPadding:
                          const EdgeInsets.symmetric(horizontal: 4),
                          leading: const CircleAvatar(
                            child: Icon(Icons.view_in_ar_outlined),
                          ),
                          title: Text(
                            expositor.numero,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(expositor.modeloNome),
                          trailing:
                          const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.of(dialogContext)
                              .pop(expositor),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(),
                child: const Text('Cancelar'),
              ),
            ],
          );
        },
      );

      if (selecionado == null || !mounted) return;

      final confirmou = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Reservar expositor?'),
          content: Text(
            'O expositor ${selecionado.numero} '
                '(${selecionado.modeloNome}) será reservado para '
                '${_nomeExibicaoCliente(cliente)}.\n\n'
                'Depois disso o cliente ficará como '
                '"Aguardando instalação".',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(true),
              child: const Text('Reservar'),
            ),
          ],
        ),
      );

      if (confirmou != true || !mounted) return;

      await ref.read(clienteRepositoryProvider).prepararNovaInstalacao(
        clienteId: clienteId,
        expositorFisicoId: selecionado.id!,
        usuarioId: usuario.uid,
      );

      if (!mounted) return;

      _atualizarPagina();
      ref.invalidate(clientesListProvider);
      ref.invalidate(expositoresFisicosListProvider);

      _mostrarMensagem(
        '${selecionado.numero} reservado. '
            'O cliente agora está aguardando instalação.',
      );
    } on ExpositorIndisponivelException catch (error) {
      if (!mounted) return;
      _mostrarMensagem(error.toString(), isError: true);
      _atualizarPagina();
    } catch (error, stackTrace) {
      debugPrint(
        'Erro ao preparar nova instalação: $error\n$stackTrace',
      );

      if (!mounted) return;

      final mensagem = error.toString().replaceFirst('Exception: ', '');
      _mostrarMensagem(
        mensagem.isEmpty
            ? 'Não foi possível preparar a nova instalação.'
            : mensagem,
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isOpeningVisit = false);
      }
    }
  }




  @override
  Widget build(BuildContext context) {
    final clienteAsync = ref.watch(clienteByIdProvider(widget.clienteId));
    final usuariosAsync = ref.watch(usuariosListProvider);
    final appUser = ref.watch(appUserProvider).value;

    final tecladoAberto = MediaQuery.viewInsetsOf(context).bottom > 0;
    final telaCompacta = MediaQuery.sizeOf(context).width < 760;
    final compactarComTeclado = tecladoAberto && telaCompacta;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalhes do cliente'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _atualizarPagina,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: clienteAsync.when(
        data: (cliente) {
          if (cliente == null) {
            return _PageMessage(
              icon: Icons.person_off_outlined,
              titulo: 'Cliente não encontrado',
              mensagem:
              'O cadastro pode ter sido removido ou você pode não ter acesso.',
              botao: 'Voltar',
              onPressed: () => Navigator.of(context).maybePop(),
            );
          }

          _prefillIfNeeded(cliente);

          final vendedorNome = usuariosAsync.maybeWhen(
            data: (usuarios) {
              if (cliente.vendedorResponsavelId == null) return '—';

              for (final usuario in usuarios) {
                if (usuario.uid == cliente.vendedorResponsavelId) {
                  return usuario.nome;
                }
              }

              return '—';
            },
            orElse: () => 'Carregando...',
          );

          return SafeArea(
            bottom: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: Column(
                  children: [
                    if (!compactarComTeclado) ...[
                      _ClienteHeader(
                        cliente: cliente,
                        isOpeningVisit: _isOpeningVisit,
                        onWhatsApp: () => _abrirWhatsAppCliente(cliente),
                        papelUsuario: appUser?.role,
                        usuarioId: appUser?.uid,
                        onPrimaryAction: () {
                          if (cliente.statusCadastro == StatusCadastro.rascunho ||
                              cliente.statusCadastro ==
                                  StatusCadastro.reprovado) {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    ClienteFormPage(clienteExistente: cliente),
                              ),
                            );
                            return;
                          }

                          if (cliente.statusCadastro ==
                              StatusCadastro.emAnalise) {
                            _tabController.animateTo(3);
                            return;
                          }

                          if (cliente.statusOperacional ==
                              StatusOperacional.encerrado) {
                            _prepararNovaInstalacao(cliente);
                            return;
                          }

                          _abrirNovaVisita(cliente);
                        },
                      ),
                      _ClienteAlertas(
                        cliente: cliente,
                        onAnalisarCadastro: () =>
                            _tabController.animateTo(3),
                        onAbrirFinanceiro: () =>
                            _tabController.animateTo(2),
                      ),
                    ],
                    Material(
                      color: Theme.of(context).colorScheme.surface,
                      child: TabBar(
                        controller: _tabController,
                        isScrollable: true,
                        tabs: const [
                          Tab(
                            icon: Icon(Icons.dashboard_outlined),
                            text: 'Resumo',
                          ),
                          Tab(
                            icon: Icon(Icons.history),
                            text: 'Visitas e documentos',
                          ),
                          Tab(
                            icon: Icon(Icons.account_balance_wallet_outlined),
                            text: 'Financeiro',
                          ),
                          Tab(
                            icon: Icon(Icons.badge_outlined),
                            text: 'Cadastro',
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _ResumoTab(
                            cliente: cliente,
                            onVerHistorico: () =>
                                _tabController.animateTo(1),
                            onAbrirDocumento: _abrirDocumento,
                            onAssinarDocumento: (visita) =>
                                _assinarDocumentoPendente(cliente, visita),
                            documentoPendenteProcessandoId:
                            _documentoPendenteProcessandoId,
                          ),
                          _VisitasDocumentosTab(
                            cliente: cliente,
                            onAbrirDocumento: _abrirDocumento,
                            onCompartilharDocumento: (documento) =>
                                _compartilharDocumento(cliente, documento),
                            onAssinarDocumento: (visita) =>
                                _assinarDocumentoPendente(cliente, visita),
                            documentoPendenteProcessandoId:
                            _documentoPendenteProcessandoId,
                          ),
                          _FinanceiroTab(
                            cliente: cliente,
                            podeAjustarLimite:
                            appUser?.role == UserRole.admin ||
                                appUser?.role == UserRole.financeiro,
                            isSaving: _isSaving,
                            onAjustarLimite: () =>
                                _ajustarLimiteCredito(cliente),
                            onAbrirContas: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ContasReceberPage(cliente: cliente),
                                ),
                              );
                            },
                          ),
                          _CadastroTab(
                            cliente: cliente,
                            vendedorNome: vendedorNome,
                            limiteController: _limiteController,
                            comissaoController: _comissaoController,
                            isSaving: _isSaving,
                            errorMessage: _errorMessage,
                            papelUsuario: appUser?.role,
                            usuarioId: appUser?.uid,
                            onAprovar: () => _handleAprovar(cliente),
                            onReprovar: () => _handleReprovar(cliente),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) {
          debugPrint('Erro ao carregar cliente: $error\n$stackTrace');

          return _PageMessage(
            icon: Icons.cloud_off_outlined,
            titulo: 'Não foi possível carregar o cliente',
            mensagem: 'Verifique sua conexão e tente novamente.',
            botao: 'Tentar novamente',
            onPressed: _atualizarPagina,
          );
        },
      ),
    );
  }
}

class _ClienteHeader extends StatelessWidget {
  final Cliente cliente;
  final bool isOpeningVisit;
  final VoidCallback onWhatsApp;
  final VoidCallback onPrimaryAction;
  final UserRole? papelUsuario;
  final String? usuarioId;

  const _ClienteHeader({
    required this.cliente,
    required this.isOpeningVisit,
    required this.onWhatsApp,
    required this.onPrimaryAction,
    required this.papelUsuario,
    required this.usuarioId,
  });

  String get _nomeExibicao {
    final fantasia = cliente.nomeFantasia?.trim();
    return fantasia != null && fantasia.isNotEmpty ? fantasia : cliente.nome;
  }

  String get _iniciais {
    final partes = _nomeExibicao
        .trim()
        .split(RegExp(r'\s+'))
        .where((parte) => parte.isNotEmpty)
        .toList();

    if (partes.isEmpty) return '?';
    if (partes.length == 1) return partes.first[0].toUpperCase();

    return '${partes.first[0]}${partes.last[0]}'.toUpperCase();
  }

  /// Rascunho/reprovado: só quem pode continuar é o admin ou o
  /// PRÓPRIO vendedor responsável — bate com a regra do Firestore
  /// (allow update só libera pra esses dois casos).
  bool get _podeContinuarCadastro {
    if (cliente.statusCadastro != StatusCadastro.rascunho &&
        cliente.statusCadastro != StatusCadastro.reprovado) {
      return false;
    }
    if (papelUsuario == UserRole.admin) return true;
    if (papelUsuario == UserRole.vendedor) {
      return cliente.vendedorResponsavelId == usuarioId;
    }
    return false;
  }

  bool get _podeAnalisarCadastro {
    return cliente.statusCadastro == StatusCadastro.emAnalise &&
        (papelUsuario == UserRole.admin || papelUsuario == UserRole.financeiro);
  }

  bool get _podeAbrirVisita {
    if (_podeContinuarCadastro || _podeAnalisarCadastro) return true;

    if (cliente.statusCadastro != StatusCadastro.aprovado) return false;

    if (cliente.statusOperacional == StatusOperacional.encerrado) {
      return cliente.statusFinanceiro != StatusFinanceiro.bloqueado;
    }

    return cliente.statusOperacional == StatusOperacional.ativo ||
        cliente.statusOperacional ==
            StatusOperacional.aguardandoInstalacao;
  }

  String get _acaoPrincipalLabel {
    if (cliente.statusCadastro == StatusCadastro.rascunho) {
      return 'Continuar cadastro';
    }
    if (cliente.statusCadastro == StatusCadastro.reprovado) {
      return 'Corrigir e reenviar';
    }
    if (cliente.statusCadastro == StatusCadastro.emAnalise) {
      return _podeAnalisarCadastro ? 'Analisar cadastro' : 'Aguardando análise';
    }

    if (cliente.statusFinanceiro == StatusFinanceiro.bloqueado &&
        cliente.statusOperacional == StatusOperacional.ativo) {
      return 'Conferir sem repor';
    }

    if (cliente.statusOperacional ==
        StatusOperacional.aguardandoInstalacao) {
      return 'Iniciar instalação';
    }

    if (cliente.statusOperacional == StatusOperacional.encerrado) {
      return 'Nova instalação';
    }

    return 'Nova visita';
  }

  IconData get _acaoPrincipalIcon {
    if (cliente.statusCadastro == StatusCadastro.rascunho ||
        cliente.statusCadastro == StatusCadastro.reprovado) {
      return Icons.edit_note_outlined;
    }
    if (cliente.statusCadastro == StatusCadastro.emAnalise) {
      return Icons.fact_check_outlined;
    }

    if (cliente.statusOperacional ==
        StatusOperacional.aguardandoInstalacao ||
        cliente.statusOperacional == StatusOperacional.encerrado) {
      return Icons.storefront_outlined;
    }

    return Icons.route_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 760;

        final identidade = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: isCompact ? 24 : 29,
              backgroundColor: colorScheme.primaryContainer,
              foregroundColor: colorScheme.onPrimaryContainer,
              child: Text(
                _iniciais,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _nomeExibicao,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    formatarCpfCnpj(cliente.cpfCnpj),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      _StatusChip(_cadastroInfo(cliente.statusCadastro)),
                      _StatusChip(_operacionalInfo(cliente.statusOperacional)),
                      _StatusChip(_financeiroInfo(cliente.statusFinanceiro)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );

        final acoes = Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.end,
          children: [
            OutlinedButton.icon(
              onPressed: onWhatsApp,
              icon: const Icon(Icons.chat_outlined),
              label: const Text('WhatsApp'),
            ),
            FilledButton.icon(
              onPressed:
              !_podeAbrirVisita || isOpeningVisit ? null : onPrimaryAction,
              icon: isOpeningVisit
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : Icon(_acaoPrincipalIcon),
              label: Text(
                isOpeningVisit ? 'Preparando...' : _acaoPrincipalLabel,
              ),
            ),
          ],
        );

        return Padding(
          padding: EdgeInsets.fromLTRB(
            isCompact ? 16 : 24,
            isCompact ? 16 : 22,
            isCompact ? 16 : 24,
            16,
          ),
          child: isCompact
              ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              identidade,
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: acoes,
              ),
            ],
          )
              : Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: identidade),
              const SizedBox(width: 24),
              acoes,
            ],
          ),
        );
      },
    );
  }
}

class _ClienteAlertas extends StatelessWidget {
  final Cliente cliente;
  final VoidCallback onAnalisarCadastro;
  final VoidCallback onAbrirFinanceiro;

  const _ClienteAlertas({
    required this.cliente,
    required this.onAnalisarCadastro,
    required this.onAbrirFinanceiro,
  });

  @override
  Widget build(BuildContext context) {
    String? mensagem;
    String? botao;
    VoidCallback? onPressed;
    IconData icon = Icons.info_outline;
    Color color = Colors.orange;

    if (cliente.statusCadastro == StatusCadastro.emAnalise) {
      mensagem =
      'Cadastro aguardando análise. Defina limite, comissão e valide '
          'o expositor reservado.';
      botao = 'Analisar';
      onPressed = onAnalisarCadastro;
      icon = Icons.fact_check_outlined;
    } else if (cliente.statusFinanceiro == StatusFinanceiro.bloqueado) {
      mensagem =
      'Cliente bloqueado financeiramente. Conferência e retirada '
          'continuam permitidas, mas novas reposições devem permanecer bloqueadas.';
      botao = 'Ver financeiro';
      onPressed = onAbrirFinanceiro;
      icon = Icons.lock_outline;
      color = Theme.of(context).colorScheme.error;
    } else if (cliente.statusOperacional == StatusOperacional.suspenso) {
      mensagem =
      'Operação suspensa. Verifique a situação antes de iniciar outra visita.';
      botao = 'Ver cadastro';
      onPressed = onAnalisarCadastro;
      icon = Icons.pause_circle_outline;
    } else if (cliente.statusOperacional == StatusOperacional.encerrado) {
      mensagem =
      'Parceria encerrada. O histórico foi preservado. Se o cliente voltar, '
          'use "Nova instalação" para reservar um novo expositor.';
      icon = Icons.history_toggle_off_outlined;
      color = Colors.blueGrey;
    }

    if (mensagem == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                mensagem,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            if (botao != null)
              TextButton(
                onPressed: onPressed,
                child: Text(botao),
              ),
          ],
        ),
      ),
    );
  }
}

class _ResumoTab extends ConsumerWidget {
  final Cliente cliente;
  final VoidCallback onVerHistorico;
  final ValueChanged<DocumentoGerado> onAbrirDocumento;
  final ValueChanged<Visita> onAssinarDocumento;
  final String? documentoPendenteProcessandoId;

  const _ResumoTab({
    required this.cliente,
    required this.onVerHistorico,
    required this.onAbrirDocumento,
    required this.onAssinarDocumento,
    required this.documentoPendenteProcessandoId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MetricasExposicao(cliente: cliente),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 900;

              final principal = Column(
                children: [
                  _ExpositoresInstalados(cliente: cliente),
                  const SizedBox(height: 16),
                  _VisitasRecentes(
                    cliente: cliente,
                    onVerHistorico: onVerHistorico,
                    onAbrirDocumento: onAbrirDocumento,
                    onAssinarDocumento: onAssinarDocumento,
                    documentoPendenteProcessandoId:
                    documentoPendenteProcessandoId,
                  ),
                ],
              );

              final lateral = Column(
                children: [
                  _ContatoOperacao(cliente: cliente),
                  const SizedBox(height: 16),
                  _EnderecoCard(cliente: cliente),
                ],
              );

              if (!isWide) {
                return Column(
                  children: [
                    principal,
                    const SizedBox(height: 16),
                    lateral,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: principal),
                  const SizedBox(width: 16),
                  Expanded(child: lateral),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MetricasExposicao extends ConsumerWidget {
  final Cliente cliente;

  const _MetricasExposicao({required this.cliente});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consignacoesAsync = ref.watch(
      consignmentsTodasAtivasDoClienteProvider(cliente.id!),
    );

    return consignacoesAsync.when(
      data: (consignacoes) {
        final exposicao = consignacoes.fold<int>(
          0,
              (soma, consignacao) =>
          soma + consignacao.valorLiquidoTotalCentavos,
        );
        final disponivel = cliente.limiteCreditoCentavos - exposicao;

        return LayoutBuilder(
          builder: (context, constraints) {
            final colunas = constraints.maxWidth >= 760
                ? 3
                : constraints.maxWidth >= 430
                ? 2
                : 1;
            final largura = (constraints.maxWidth - ((colunas - 1) * 12)) /
                colunas;

            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: largura,
                  child: _MetricCard(
                    label: 'Limite',
                    value: _formatarCentavos(cliente.limiteCreditoCentavos),
                    supportingText: 'Crédito aprovado',
                    icon: Icons.credit_score_outlined,
                  ),
                ),
                SizedBox(
                  width: largura,
                  child: _MetricCard(
                    label: 'Exposição atual',
                    value: _formatarCentavos(exposicao),
                    supportingText:
                    '${consignacoes.length} consignação(ões) ativa(s)',
                    icon: Icons.inventory_2_outlined,
                    valueColor:
                    disponivel < 0 ? Theme.of(context).colorScheme.error : null,
                  ),
                ),
                SizedBox(
                  width: largura,
                  child: _MetricCard(
                    label: 'Disponível',
                    value: _formatarCentavos(disponivel),
                    supportingText: disponivel < 0
                        ? 'Exposição acima do limite'
                        : 'Saldo para novas consignações',
                    icon: Icons.account_balance_wallet_outlined,
                    valueColor: disponivel < 0
                        ? Theme.of(context).colorScheme.error
                        : Colors.green,
                  ),
                ),
              ],
            );
          },
        );
      },
      loading: () => const _LoadingCard(height: 116),
      error: (error, stackTrace) {
        debugPrint('Erro ao carregar exposição: $error\n$stackTrace');
        return const _InlineError(
          mensagem: 'Não foi possível carregar a exposição financeira.',
        );
      },
    );
  }
}

class _ExpositoresInstalados extends ConsumerWidget {
  final Cliente cliente;

  const _ExpositoresInstalados({required this.cliente});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expositoresAsync = ref.watch(expositoresFisicosListProvider);
    final consignacoes = ref
        .watch(
      consignmentsTodasAtivasDoClienteProvider(cliente.id!),
    )
        .value ??
        const <Consignment>[];

    return _SectionCard(
      title: 'Expositores instalados',
      subtitle: 'Unidades físicas atualmente vinculadas ao cliente.',
      child: expositoresAsync.when(
        data: (expositores) {
          final instalados = expositores
              .where((expositor) => expositor.clienteAtualId == cliente.id)
              .toList()
            ..sort((a, b) => a.numero.compareTo(b.numero));

          if (instalados.isEmpty) {
            return const _EmptySection(
              icon: Icons.storefront_outlined,
              mensagem: 'Nenhum expositor instalado no momento.',
            );
          }

          return Column(
            children: [
              for (var index = 0; index < instalados.length; index++) ...[
                if (index > 0) const Divider(height: 1),
                _ExpositorRow(
                  expositor: instalados[index],
                  consignacao: _consignacaoDoExpositor(
                    instalados[index],
                    consignacoes,
                  ),
                ),
              ],
            ],
          );
        },
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: LinearProgressIndicator(),
        ),
        error: (error, stackTrace) {
          debugPrint('Erro ao carregar expositores: $error\n$stackTrace');
          return const _InlineError(
            mensagem: 'Não foi possível carregar os expositores.',
          );
        },
      ),
    );
  }
}

class _ExpositorRow extends StatelessWidget {
  final ExpositorFisico expositor;
  final Consignment? consignacao;

  const _ExpositorRow({
    required this.expositor,
    required this.consignacao,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      leading: CircleAvatar(
        backgroundColor: colorScheme.secondaryContainer,
        foregroundColor: colorScheme.onSecondaryContainer,
        child: const Icon(Icons.view_in_ar_outlined),
      ),
      title: Text(
        expositor.numero,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        consignacao == null
            ? expositor.modeloNome
            : '${expositor.modeloNome} • '
            '${consignacao!.itens.length} produto(s) • '
            '${_formatarCentavos(consignacao!.valorLiquidoTotalCentavos)}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        if (expositor.id == null) return;

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ExpositorDetailPage(expositorId: expositor.id!),
          ),
        );
      },
    );
  }
}

class _VisitasRecentes extends ConsumerWidget {
  final Cliente cliente;
  final VoidCallback onVerHistorico;
  final ValueChanged<DocumentoGerado> onAbrirDocumento;
  final ValueChanged<Visita> onAssinarDocumento;
  final String? documentoPendenteProcessandoId;

  const _VisitasRecentes({
    required this.cliente,
    required this.onVerHistorico,
    required this.onAbrirDocumento,
    required this.onAssinarDocumento,
    required this.documentoPendenteProcessandoId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visitasAsync =
    ref.watch(visitaHistoricoDoClienteProvider(cliente.id!));
    final documentosAsync = ref.watch(documentosDoClienteProvider(cliente.id!));

    return _SectionCard(
      title: 'Visitas recentes',
      subtitle: 'Operações realizadas e situação dos documentos.',
      trailing: TextButton(
        onPressed: onVerHistorico,
        child: const Text('Ver histórico'),
      ),
      child: visitasAsync.when(
        data: (visitas) {
          return documentosAsync.when(
            data: (documentos) {
              if (visitas.isEmpty) {
                return const _EmptySection(
                  icon: Icons.event_busy_outlined,
                  mensagem: 'Nenhuma visita registrada ainda.',
                );
              }

              final recentes = visitas.take(3).toList();

              return Column(
                children: [
                  for (var index = 0; index < recentes.length; index++) ...[
                    if (index > 0) const Divider(height: 1),
                    _VisitaResumoRow(
                      visita: recentes[index],
                      documentos: _documentosDaVisita(
                        recentes[index],
                        documentos,
                      ),
                      onAbrirDocumento: onAbrirDocumento,
                      onAssinarDocumento: onAssinarDocumento,
                      processandoDocumento:
                      documentoPendenteProcessandoId ==
                          recentes[index].id,
                    ),
                  ],
                ],
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: LinearProgressIndicator(),
            ),
            error: (error, stackTrace) {
              debugPrint(
                'Erro ao carregar documentos recentes: '
                    '$error\n$stackTrace',
              );
              return const _InlineError(
                mensagem: 'Não foi possível carregar os documentos.',
              );
            },
          );
        },
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: LinearProgressIndicator(),
        ),
        error: (error, stackTrace) {
          debugPrint('Erro ao carregar visitas: $error\n$stackTrace');
          return const _InlineError(
            mensagem: 'Não foi possível carregar as visitas.',
          );
        },
      ),
    );
  }
}

class _VisitaResumoRow extends StatelessWidget {
  final Visita visita;
  final List<DocumentoGerado> documentos;
  final ValueChanged<DocumentoGerado> onAbrirDocumento;
  final ValueChanged<Visita> onAssinarDocumento;
  final bool processandoDocumento;

  const _VisitaResumoRow({
    required this.visita,
    required this.documentos,
    required this.onAbrirDocumento,
    required this.onAssinarDocumento,
    required this.processandoDocumento,
  });

  @override
  Widget build(BuildContext context) {
    final documento = _documentoVigente(documentos);
    final retomandoDocumento = documento != null &&
        (documento.status == DocumentoStatus.erro ||
            documento.status == DocumentoStatus.gerando);
    final data = visita.finalizadaEm ?? visita.criadaEm;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: colorScheme.surfaceContainerHighest,
            child: Icon(
              _iconeVisita(visita.tipo),
              size: 20,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_visitaTipoLabel(visita.tipo)} • '
                      '${visita.numero ?? 'Sem número'}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  data == null
                      ? _visitaEstadoLabel(visita.estado)
                      : DateFormat('dd/MM/yyyy HH:mm').format(data),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 7),
                _DocumentoStatusLabel(
                  visita: visita,
                  documento: documento,
                  quantidadeVersoes: documentos.length,
                ),
                if (_visitaTemDocumentoPendente(visita, documentos)) ...[
                  const SizedBox(height: 9),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: processandoDocumento
                          ? null
                          : () => onAssinarDocumento(visita),
                      icon: processandoDocumento
                          ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                          : Icon(
                        retomandoDocumento
                            ? Icons.refresh_rounded
                            : Icons.draw_outlined,
                        size: 18,
                      ),
                      label: Text(
                        processandoDocumento
                            ? 'Preparando...'
                            : retomandoDocumento
                            ? 'Tentar novamente'
                            : 'Assinar documento',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (documento != null &&
              documento.status == DocumentoStatus.ativo &&
              documento.urlStorage.isNotEmpty)
            IconButton(
              tooltip: 'Visualizar ${documento.numero}',
              onPressed: () => onAbrirDocumento(documento),
              icon: const Icon(Icons.visibility_outlined),
            ),
        ],
      ),
    );
  }
}

class _ContatoOperacao extends ConsumerWidget {
  final Cliente cliente;

  const _ContatoOperacao({required this.cliente});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usuariosAsync = ref.watch(usuariosListProvider);
    final visitasAsync =
    ref.watch(visitaHistoricoDoClienteProvider(cliente.id!));

    final vendedor = usuariosAsync.maybeWhen(
      data: (usuarios) {
        for (final usuario in usuarios) {
          if (usuario.uid == cliente.vendedorResponsavelId) {
            return usuario.nome;
          }
        }
        return '—';
      },
      orElse: () => 'Carregando...',
    );

    final ultimaVisita = visitasAsync.maybeWhen(
      data: (visitas) {
        for (final visita in visitas) {
          if (_visitaConcluida(visita)) {
            final data = visita.finalizadaEm ?? visita.criadaEm;
            return data == null
                ? visita.numero ?? '—'
                : DateFormat('dd/MM/yyyy').format(data);
          }
        }
        return 'Nenhuma';
      },
      orElse: () => 'Carregando...',
    );

    return _SectionCard(
      title: 'Contato e operação',
      subtitle: 'Dados usados durante o atendimento.',
      child: Column(
        children: [
          _DetailRow(label: 'Responsável', value: cliente.nomeResponsavel),
          _DetailRow(
            label: 'Telefone',
            value: formatarTelefone(cliente.telefoneResponsavel),
          ),
          _DetailRow(
            label: 'Prazo de acerto',
            value: '${cliente.prazoAcertoDias} dias',
          ),
          _DetailRow(label: 'Vendedor', value: vendedor),
          _DetailRow(label: 'Última visita', value: ultimaVisita),
        ],
      ),
    );
  }
}

class _EnderecoCard extends StatelessWidget {
  final Cliente cliente;

  const _EnderecoCard({required this.cliente});

  @override
  Widget build(BuildContext context) {
    final complemento = cliente.complemento?.trim();
    final cep = cliente.cep.length == 8
        ? '${cliente.cep.substring(0, 5)}-${cliente.cep.substring(5)}'
        : cliente.cep;

    return _SectionCard(
      title: 'Endereço',
      subtitle: 'Local de instalação e das visitas.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            [
              cliente.enderecoResumo,
              if (complemento != null && complemento.isNotEmpty) complemento,
              if (cep.isNotEmpty) 'CEP $cep',
            ].join('\n'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

enum _FiltroHistorico {
  todas,
  instalacao,
  reposicao,
  retirada,
  pendente,
}

class _VisitasDocumentosTab extends ConsumerStatefulWidget {
  final Cliente cliente;
  final ValueChanged<DocumentoGerado> onAbrirDocumento;
  final ValueChanged<DocumentoGerado> onCompartilharDocumento;
  final ValueChanged<Visita> onAssinarDocumento;
  final String? documentoPendenteProcessandoId;

  const _VisitasDocumentosTab({
    required this.cliente,
    required this.onAbrirDocumento,
    required this.onCompartilharDocumento,
    required this.onAssinarDocumento,
    required this.documentoPendenteProcessandoId,
  });

  @override
  ConsumerState<_VisitasDocumentosTab> createState() =>
      _VisitasDocumentosTabState();
}

class _VisitasDocumentosTabState
    extends ConsumerState<_VisitasDocumentosTab> {
  _FiltroHistorico _filtro = _FiltroHistorico.todas;

  bool _passaFiltro(
      Visita visita,
      List<DocumentoGerado> documentos,
      ) {
    return switch (_filtro) {
      _FiltroHistorico.todas => true,
      _FiltroHistorico.instalacao => visita.tipo == VisitaTipo.instalacao,
      _FiltroHistorico.reposicao => visita.tipo == VisitaTipo.visita,
      _FiltroHistorico.retirada => visita.tipo == VisitaTipo.coleta,
      _FiltroHistorico.pendente =>
          _visitaTemDocumentoPendente(visita, documentos),
    };
  }

  @override
  Widget build(BuildContext context) {
    final visitasAsync = ref.watch(
      visitaHistoricoDoClienteProvider(widget.cliente.id!),
    );
    final documentosAsync = ref.watch(
      documentosDoClienteProvider(widget.cliente.id!),
    );

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              _FiltroChip(
                label: 'Todas',
                selected: _filtro == _FiltroHistorico.todas,
                onSelected: () =>
                    setState(() => _filtro = _FiltroHistorico.todas),
              ),
              _FiltroChip(
                label: 'Instalação',
                selected: _filtro == _FiltroHistorico.instalacao,
                onSelected: () =>
                    setState(() => _filtro = _FiltroHistorico.instalacao),
              ),
              _FiltroChip(
                label: 'Reposição',
                selected: _filtro == _FiltroHistorico.reposicao,
                onSelected: () =>
                    setState(() => _filtro = _FiltroHistorico.reposicao),
              ),
              _FiltroChip(
                label: 'Retirada',
                selected: _filtro == _FiltroHistorico.retirada,
                onSelected: () =>
                    setState(() => _filtro = _FiltroHistorico.retirada),
              ),
              _FiltroChip(
                label: 'Documento pendente',
                selected: _filtro == _FiltroHistorico.pendente,
                onSelected: () =>
                    setState(() => _filtro = _FiltroHistorico.pendente),
              ),
            ],
          ),
        ),
        Expanded(
          child: visitasAsync.when(
            data: (visitas) {
              return documentosAsync.when(
                data: (documentos) {
                  final filtradas = visitas.where((visita) {
                    return _passaFiltro(
                      visita,
                      _documentosDaVisita(visita, documentos),
                    );
                  }).toList();

                  if (filtradas.isEmpty) {
                    return const _PageMessage(
                      icon: Icons.history_toggle_off_outlined,
                      titulo: 'Nenhuma visita encontrada',
                      mensagem:
                      'Não existem visitas correspondentes a este filtro.',
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    itemCount: filtradas.length,
                    separatorBuilder: (_, __) =>
                    const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final visita = filtradas[index];

                      return _VisitaDocumentoCard(
                        visita: visita,
                        documentos:
                        _documentosDaVisita(visita, documentos),
                        onAbrirDocumento: widget.onAbrirDocumento,
                        onCompartilharDocumento:
                        widget.onCompartilharDocumento,
                        onAssinarDocumento:
                        widget.onAssinarDocumento,
                        processandoDocumento:
                        widget.documentoPendenteProcessandoId ==
                            visita.id,
                      );
                    },
                  );
                },
                loading: () =>
                const Center(child: CircularProgressIndicator()),
                error: (error, stackTrace) {
                  debugPrint(
                    'Erro ao carregar documentos: $error\n$stackTrace',
                  );
                  return const _PageMessage(
                    icon: Icons.description_outlined,
                    titulo: 'Erro ao carregar documentos',
                    mensagem: 'Tente atualizar a página.',
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) {
              debugPrint('Erro ao carregar histórico: $error\n$stackTrace');
              return const _PageMessage(
                icon: Icons.event_busy_outlined,
                titulo: 'Erro ao carregar visitas',
                mensagem: 'Tente atualizar a página.',
              );
            },
          ),
        ),
      ],
    );
  }
}

class _VisitaDocumentoCard extends StatelessWidget {
  final Visita visita;
  final List<DocumentoGerado> documentos;
  final ValueChanged<DocumentoGerado> onAbrirDocumento;
  final ValueChanged<DocumentoGerado> onCompartilharDocumento;
  final ValueChanged<Visita> onAssinarDocumento;
  final bool processandoDocumento;

  const _VisitaDocumentoCard({
    required this.visita,
    required this.documentos,
    required this.onAbrirDocumento,
    required this.onCompartilharDocumento,
    required this.onAssinarDocumento,
    required this.processandoDocumento,
  });

  @override
  Widget build(BuildContext context) {
    final documento = _documentoVigente(documentos);
    final retomandoDocumento = documento != null &&
        (documento.status == DocumentoStatus.erro ||
            documento.status == DocumentoStatus.gerando);
    final data = visita.finalizadaEm ?? visita.criadaEm;
    final assinatura = documento?.assinatura;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 760;

          final operacao = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: colorScheme.primaryContainer,
                foregroundColor: colorScheme.onPrimaryContainer,
                child: Icon(_iconeVisita(visita.tipo)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _visitaTipoLabel(visita.tipo),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      visita.numero ?? 'Visita sem número',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final detalhes = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CompactLabelValue(
                label: 'Data',
                value: data == null
                    ? 'Não informada'
                    : DateFormat('dd/MM/yyyy HH:mm').format(data),
              ),
              const SizedBox(height: 8),
              _CompactLabelValue(
                label: 'Situação',
                value: _visitaEstadoLabel(visita.estado),
              ),
            ],
          );

          final documentoInfo = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DocumentoStatusLabel(
                visita: visita,
                documento: documento,
                quantidadeVersoes: documentos.length,
              ),
              if (assinatura != null) ...[
                const SizedBox(height: 7),
                Text(
                  'Assinado por ${assinatura.nomeResponsavel}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  DateFormat('dd/MM/yyyy HH:mm').format(assinatura.timestamp),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          );

          final documentoAtivo = documento != null &&
              documento.status == DocumentoStatus.ativo &&
              documento.urlStorage.isNotEmpty;
          final documentoPendente =
          _visitaTemDocumentoPendente(visita, documentos);
          final temAcoes = documentoAtivo || documentoPendente;

          final acoes = documentoAtivo
              ? Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => onAbrirDocumento(documento),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Ver PDF'),
              ),
              IconButton(
                tooltip: 'Compartilhar documento',
                onPressed: () =>
                    onCompartilharDocumento(documento),
                icon: const Icon(Icons.share_outlined),
              ),
            ],
          )
              : documentoPendente
              ? (isWide
              ? FilledButton.tonalIcon(
            onPressed: processandoDocumento
                ? null
                : () => onAssinarDocumento(visita),
            icon: processandoDocumento
                ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
              ),
            )
                : Icon(
              retomandoDocumento
                  ? Icons.refresh_rounded
                  : Icons.draw_outlined,
            ),
            label: Text(
              processandoDocumento
                  ? 'Preparando...'
                  : retomandoDocumento
                  ? 'Tentar novamente'
                  : 'Assinar documento',
            ),
          )
              : SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: processandoDocumento
                  ? null
                  : () => onAssinarDocumento(visita),
              icon: processandoDocumento
                  ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              )
                  : Icon(
                retomandoDocumento
                    ? Icons.refresh_rounded
                    : Icons.draw_outlined,
              ),
              label: Text(
                processandoDocumento
                    ? 'Preparando...'
                    : retomandoDocumento
                    ? 'Tentar novamente'
                    : 'Assinar documento',
              ),
            ),
          ))
              : const SizedBox.shrink();

          if (!isWide) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  operacao,
                  const Divider(height: 28),
                  detalhes,
                  const SizedBox(height: 14),
                  documentoInfo,
                  if (temAcoes) ...[
                    const SizedBox(height: 14),
                    acoes,
                  ],
                ],
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 3, child: operacao),
                const SizedBox(width: 20),
                Expanded(flex: 2, child: detalhes),
                const SizedBox(width: 20),
                Expanded(flex: 3, child: documentoInfo),
                const SizedBox(width: 16),
                acoes,
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FinanceiroTab extends ConsumerWidget {
  final Cliente cliente;
  final bool podeAjustarLimite;
  final bool isSaving;
  final VoidCallback onAjustarLimite;
  final VoidCallback onAbrirContas;

  const _FinanceiroTab({
    required this.cliente,
    required this.podeAjustarLimite,
    required this.isSaving,
    required this.onAjustarLimite,
    required this.onAbrirContas,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (cliente.statusFinanceiro == StatusFinanceiro.bloqueado) ...[
            _WarningCard(
              icon: Icons.lock_outline,
              title: 'Cliente bloqueado financeiramente',
              message:
              'Novas reposições devem permanecer bloqueadas até a '
                  'regularização. Conferência e retirada continuam disponíveis.',
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
          ],
          _MetricasExposicao(cliente: cliente),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final conditions = _SectionCard(
                title: 'Condições comerciais',
                subtitle: 'Definidas durante a aprovação do cliente.',
                child: Column(
                  children: [
                    LayoutBuilder(
                      builder: (context, limiteConstraints) {
                        final limiteInfo = _DetailRow(
                          label: 'Limite de crédito',
                          value: _formatarCentavos(
                            cliente.limiteCreditoCentavos,
                          ),
                        );

                        if (!podeAjustarLimite) {
                          return limiteInfo;
                        }

                        final botao = OutlinedButton.icon(
                          onPressed:
                          isSaving ? null : onAjustarLimite,
                          icon: const Icon(
                            Icons.edit_outlined,
                            size: 17,
                          ),
                          label: const Text('Editar limite'),
                        );

                        if (limiteConstraints.maxWidth < 520) {
                          return Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.stretch,
                            children: [
                              limiteInfo,
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: botao,
                              ),
                              const SizedBox(height: 4),
                            ],
                          );
                        }

                        return Row(
                          crossAxisAlignment:
                          CrossAxisAlignment.center,
                          children: [
                            Expanded(child: limiteInfo),
                            const SizedBox(width: 12),
                            botao,
                          ],
                        );
                      },
                    ),
                    _DetailRow(
                      label: 'Comissão',
                      value:
                      '${(cliente.comissaoBasisPoints / 100).toStringAsFixed(1)}%',
                    ),
                    _DetailRow(
                      label: 'Prazo de acerto',
                      value: '${cliente.prazoAcertoDias} dias',
                    ),
                    _DetailRow(
                      label: 'Situação financeira',
                      value: _financeiroInfo(cliente.statusFinanceiro).$1,
                    ),
                  ],
                ),
              );

              final accounts = _SectionCard(
                title: 'Contas a receber',
                subtitle:
                'Cobranças geradas pelos acertos realizados nas visitas.',
                child: FilledButton.tonalIcon(
                  onPressed: onAbrirContas,
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Ver contas a receber'),
                ),
              );

              if (constraints.maxWidth < 800) {
                return Column(
                  children: [
                    conditions,
                    const SizedBox(height: 16),
                    accounts,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: conditions),
                  const SizedBox(width: 16),
                  Expanded(child: accounts),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CadastroTab extends StatelessWidget {
  final Cliente cliente;
  final String vendedorNome;
  final TextEditingController limiteController;
  final TextEditingController comissaoController;
  final bool isSaving;
  final String? errorMessage;
  final UserRole? papelUsuario;
  final String? usuarioId;
  final VoidCallback onAprovar;
  final VoidCallback onReprovar;

  const _CadastroTab({
    required this.cliente,
    required this.vendedorNome,
    required this.limiteController,
    required this.comissaoController,
    required this.isSaving,
    required this.errorMessage,
    required this.papelUsuario,
    required this.usuarioId,
    required this.onAprovar,
    required this.onReprovar,
  });

  @override
  Widget build(BuildContext context) {
    final podeAnalisar = papelUsuario == UserRole.admin ||
        papelUsuario == UserRole.financeiro;

    final vendedorResponsavel =
        papelUsuario == UserRole.vendedor &&
            usuarioId != null &&
            cliente.vendedorResponsavelId == usuarioId;

    final podeEditarCadastro =
        papelUsuario == UserRole.admin || vendedorResponsavel;

    final podeAjustarComissao =
        papelUsuario == UserRole.admin ||
            papelUsuario == UserRole.financeiro;

    final podeAjustarVisitas =
        papelUsuario == UserRole.admin || vendedorResponsavel;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (cliente.statusCadastro == StatusCadastro.emAnalise) ...[
            if (podeAnalisar)
              _AprovacaoCard(
                cliente: cliente,
                limiteController: limiteController,
                comissaoController: comissaoController,
                isSaving: isSaving,
                errorMessage: errorMessage,
                onAprovar: onAprovar,
                onReprovar: onReprovar,
              )
            else
              const _SectionCard(
                title: 'Análise e aprovação',
                subtitle:
                'Cadastro aguardando validação administrativa/financeira.',
                child: Text(
                  'Somente usuários Admin ou Financeiro podem definir '
                      'o limite, validar a comissão, aprovar ou reprovar este cliente.',
                ),
              ),
            const SizedBox(height: 16),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final dados = _SectionCard(
                title: 'Dados do estabelecimento',
                subtitle: 'Identificação e contato do cliente.',
                trailing: podeEditarCadastro
                    ? OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            ClienteEdicaoPage(cliente: cliente),
                      ),
                    );
                  },
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Editar'),
                )
                    : null,
                child: Column(
                  children: [
                    _DetailRow(label: 'Nome/Razão social', value: cliente.nome),
                    if (cliente.nomeFantasia?.trim().isNotEmpty == true)
                      _DetailRow(
                        label: 'Nome fantasia',
                        value: cliente.nomeFantasia!,
                      ),
                    _DetailRow(
                      label: 'CPF/CNPJ',
                      value: formatarCpfCnpj(cliente.cpfCnpj),
                    ),
                    _DetailRow(
                      label: 'Responsável',
                      value: cliente.nomeResponsavel,
                    ),
                    _DetailRow(
                      label: 'Telefone',
                      value: formatarTelefone(cliente.telefoneResponsavel),
                    ),
                    if (cliente.emailResponsavel?.trim().isNotEmpty == true)
                      _DetailRow(
                        label: 'E-mail',
                        value: cliente.emailResponsavel!,
                      ),
                  ],
                ),
              );

              final operacao = _SectionCard(
                title: 'Controle interno',
                subtitle: 'Responsabilidade e situação operacional.',
                child: Column(
                  children: [
                    _DetailRow(label: 'Vendedor responsável', value: vendedorNome),
                    _DetailRow(
                      label: 'Prazo de acerto',
                      value: '${cliente.prazoAcertoDias} dias',
                    ),
                    _DetailRow(
                      label: 'Cadastro',
                      value: _cadastroInfo(cliente.statusCadastro).$1,
                    ),
                    _DetailRow(
                      label: 'Operacional',
                      value: _operacionalInfo(cliente.statusOperacional).$1,
                    ),
                    _DetailRow(
                      label: 'Financeiro',
                      value: _financeiroInfo(cliente.statusFinanceiro).$1,
                    ),
                  ],
                ),
              );

              final endereco = _EnderecoDetalhado(cliente: cliente);
              final comissao = _ComissaoVisitaCard(
                cliente: cliente,
                podeAjustarComissao: podeAjustarComissao,
                podeAjustarVisitas: podeAjustarVisitas,
              );

              if (constraints.maxWidth < 900) {
                return Column(
                  children: [
                    dados,
                    const SizedBox(height: 16),
                    endereco,
                    const SizedBox(height: 16),
                    operacao,
                    const SizedBox(height: 16),
                    comissao,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        dados,
                        const SizedBox(height: 16),
                        endereco,
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      children: [
                        operacao,
                        const SizedBox(height: 16),
                        comissao,
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ComissaoVisitaCard extends ConsumerStatefulWidget {
  final Cliente cliente;
  final bool podeAjustarComissao;
  final bool podeAjustarVisitas;

  const _ComissaoVisitaCard({
    required this.cliente,
    required this.podeAjustarComissao,
    required this.podeAjustarVisitas,
  });

  @override
  ConsumerState<_ComissaoVisitaCard> createState() => _ComissaoVisitaCardState();
}

class _ComissaoVisitaCardState extends ConsumerState<_ComissaoVisitaCard> {
  bool _isSaving = false;

  bool get _atrasada {
    final data = widget.cliente.proximaVisitaEm;
    if (data == null) return false;

    final hoje = DateTime.now();
    final hojeData = DateTime(hoje.year, hoje.month, hoje.day);
    final visitaData = DateTime(data.year, data.month, data.day);

    return visitaData.isBefore(hojeData);
  }

  Future<void> _ajustarComissao() async {
    if (!widget.podeAjustarComissao) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Somente Admin ou Financeiro pode ajustar a comissão.',
            ),
          ),
        );
      }
      return;
    }

    var valorDigitado =
    (widget.cliente.comissaoBasisPoints / 100).toStringAsFixed(1);

    final valorInformado = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ajustar comissão'),
        content: TextFormField(
          initialValue: valorDigitado,
          keyboardType:
          const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Comissão (%)',
            hintText: 'Ex.: 30,0',
          ),
          autofocus: true,
          onChanged: (value) => valorDigitado = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(valorDigitado),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    if (valorInformado == null || !mounted) return;

    final novoValor =
    double.tryParse(valorInformado.trim().replaceAll(',', '.'));

    if (novoValor == null || novoValor < 0 || novoValor > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe uma comissão válida entre 0% e 100%.'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref.read(clienteRepositoryProvider).ajustarComissao(
        clienteId: widget.cliente.id!,
        novaComissaoBasisPoints: (novoValor * 100).round(),
      );
      ref.invalidate(clienteByIdProvider(widget.cliente.id!));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Comissão atualizada!')),
        );
      }
    } catch (e, stack) {
      debugPrint('Erro ao ajustar comissão: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível ajustar a comissão.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _editarProximaVisita() async {
    if (!widget.podeAjustarVisitas) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Você não possui permissão para alterar a próxima visita.',
            ),
          ),
        );
      }
      return;
    }

    final data = await showDatePicker(
      context: context,
      initialDate: widget.cliente.proximaVisitaEm ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (data == null || !mounted) return;

    setState(() => _isSaving = true);
    try {
      await ref.read(clienteRepositoryProvider).definirProximaVisita(
        clienteId: widget.cliente.id!,
        data: data,
      );
      ref.invalidate(clienteByIdProvider(widget.cliente.id!));
      ref.invalidate(clientesListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Próxima visita atualizada!')),
        );
      }
    } catch (e, stack) {
      debugPrint('Erro ao definir próxima visita: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível atualizar a próxima visita.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _ajustarFrequencia() async {
    if (!widget.podeAjustarVisitas) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Você não possui permissão para alterar a frequência de visitas.',
            ),
          ),
        );
      }
      return;
    }

    var valorDigitado = '${widget.cliente.frequenciaVisitaDiasPadrao}';

    final valorInformado = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Frequência de visita'),
        content: TextFormField(
          initialValue: valorDigitado,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Sugerir nova visita a cada quantos dias?',
          ),
          autofocus: true,
          onChanged: (value) => valorDigitado = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(valorDigitado),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    if (valorInformado == null || !mounted) return;

    final novoValor = int.tryParse(valorInformado.trim());

    if (novoValor == null || novoValor <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe uma frequência válida em dias.'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref.read(clienteRepositoryProvider).ajustarFrequenciaVisita(
        clienteId: widget.cliente.id!,
        dias: novoValor,
      );
      ref.invalidate(clienteByIdProvider(widget.cliente.id!));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Frequência de visitas atualizada!')),
        );
      }
    } catch (e, stack) {
      debugPrint('Erro ao ajustar frequência: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível atualizar a frequência de visitas.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _formatarData(DateTime data) {
    return '${data.day.toString().padLeft(2, '0')}/'
        '${data.month.toString().padLeft(2, '0')}/${data.year}';
  }

  Widget _botaoAjuste({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: 108,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cliente = widget.cliente;
    final proximaVisita = cliente.proximaVisitaEm;
    final dataFormatada =
    proximaVisita == null ? 'Não definida' : _formatarData(proximaVisita);

    return _SectionCard(
      title: 'Comissão e visitas',
      subtitle:
      'Ajustáveis a qualquer momento, mesmo com o cliente já aprovado.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _DetailRow(
                  label: 'Comissão atual',
                  value:
                  '${(cliente.comissaoBasisPoints / 100).toStringAsFixed(1)}%',
                ),
              ),
              if (widget.podeAjustarComissao) ...[
                const SizedBox(width: 12),
                _botaoAjuste(
                  label: 'Ajustar',
                  icon: Icons.percent,
                  onPressed: _isSaving ? null : _ajustarComissao,
                ),
              ],
            ],
          ),
          const Divider(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DetailRow(
                      label: 'Próxima visita',
                      value: dataFormatada,
                    ),
                    if (_atrasada) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                              color: Colors.red.withValues(alpha: 0.4)),
                        ),
                        child: const Text(
                          'Atrasada',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.podeAjustarVisitas) ...[
                const SizedBox(width: 12),
                _botaoAjuste(
                  label: 'Definir',
                  icon: Icons.event_outlined,
                  onPressed: _isSaving ? null : _editarProximaVisita,
                ),
              ],
            ],
          ),
          const Divider(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _DetailRow(
                  label: 'Sugerir a cada',
                  value: '${cliente.frequenciaVisitaDiasPadrao} dias',
                ),
              ),
              if (widget.podeAjustarVisitas) ...[
                const SizedBox(width: 12),
                _botaoAjuste(
                  label: 'Ajustar',
                  icon: Icons.tune,
                  onPressed: _isSaving ? null : _ajustarFrequencia,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _AprovacaoCard extends StatelessWidget {
  final Cliente cliente;
  final TextEditingController limiteController;
  final TextEditingController comissaoController;
  final bool isSaving;
  final String? errorMessage;
  final VoidCallback onAprovar;
  final VoidCallback onReprovar;

  const _AprovacaoCard({
    required this.cliente,
    required this.limiteController,
    required this.comissaoController,
    required this.isSaving,
    required this.errorMessage,
    required this.onAprovar,
    required this.onReprovar,
  });

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Análise e aprovação',
      subtitle:
      'Defina o limite, valide a comissão e confira o expositor reservado.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (cliente.expositorFisicoSelecionadoId != null) ...[
            _ExpositorReservado(
              expositorId: cliente.expositorFisicoSelecionadoId!,
            ),
            const Divider(height: 28),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final limiteField = TextFormField(
                controller: limiteController,
                enabled: !isSaving,
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Limite de crédito',
                  prefixText: 'R\$ ',
                ),
              );

              final comissaoField = TextFormField(
                controller: comissaoController,
                enabled: !isSaving,
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Comissão validada',
                  suffixText: '%',
                ),
              );

              if (constraints.maxWidth < 560) {
                return Column(
                  children: [
                    limiteField,
                    const SizedBox(height: 12),
                    comissaoField,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: limiteField),
                  const SizedBox(width: 12),
                  Expanded(child: comissaoField),
                ],
              );
            },
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final reprovar = OutlinedButton(
                onPressed: isSaving ? null : onReprovar,
                child: const Text('Reprovar'),
              );

              final aprovar = FilledButton.icon(
                onPressed: isSaving ? null : onAprovar,
                icon: isSaving
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.check_circle_outline),
                label: Text(isSaving ? 'Salvando...' : 'Aprovar cliente'),
              );

              if (constraints.maxWidth < 460) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    aprovar,
                    const SizedBox(height: 10),
                    reprovar,
                  ],
                );
              }

              return Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  reprovar,
                  const SizedBox(width: 10),
                  aprovar,
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _EnderecoDetalhado extends StatelessWidget {
  final Cliente cliente;

  const _EnderecoDetalhado({required this.cliente});

  @override
  Widget build(BuildContext context) {
    final cep = cliente.cep.length == 8
        ? '${cliente.cep.substring(0, 5)}-${cliente.cep.substring(5)}'
        : cliente.cep.isEmpty
        ? '—'
        : cliente.cep;

    return _SectionCard(
      title: 'Endereço',
      subtitle: 'Local usado para instalação e visitas.',
      child: Column(
        children: [
          _DetailRow(label: 'Endereço', value: cliente.enderecoResumo),
          if (cliente.complemento?.trim().isNotEmpty == true)
            _DetailRow(
              label: 'Complemento',
              value: cliente.complemento!,
            ),
          _DetailRow(label: 'CEP', value: cep),
        ],
      ),
    );
  }
}

class _ExpositorReservado extends ConsumerWidget {
  final String expositorId;

  const _ExpositorReservado({required this.expositorId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expositorAsync = ref.watch(expositorFisicoByIdProvider(expositorId));

    return expositorAsync.when(
      data: (expositor) {
        if (expositor == null) {
          return const _InlineError(
            mensagem: 'O expositor reservado não foi encontrado.',
          );
        }

        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.inventory_2_outlined),
          title: Text(
            expositor.numero,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text('${expositor.modeloNome} • Reservado'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ExpositorDetailPage(expositorId: expositorId),
              ),
            );
          },
        );
      },
      loading: () => const LinearProgressIndicator(),
      error: (error, stackTrace) {
        debugPrint('Erro ao carregar expositor: $error\n$stackTrace');
        return const _InlineError(
          mensagem: 'Não foi possível carregar o expositor reservado.',
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  const _SectionCard({
    required this.title,
    this.subtitle,
    this.trailing,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          style:
                          Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 10),
                  trailing!,
                ],
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String supportingText;
  final IconData icon;
  final Color? valueColor;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.supportingText,
    required this.icon,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Icon(icon, size: 19, color: colorScheme.primary),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: valueColor,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              supportingText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 360;

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(value),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 145,
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(value)),
            ],
          );
        },
      ),
    );
  }
}

class _CompactLabelValue extends StatelessWidget {
  final String label;
  final String value;

  const _CompactLabelValue({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(value),
      ],
    );
  }
}

class _DocumentoStatusLabel extends StatelessWidget {
  final Visita visita;
  final DocumentoGerado? documento;
  final int quantidadeVersoes;

  const _DocumentoStatusLabel({
    required this.visita,
    required this.documento,
    required this.quantidadeVersoes,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    late final String label;
    late final IconData icon;
    late final Color color;

    if (visita.estado == VisitaEstado.cancelada) {
      label = 'Visita cancelada';
      icon = Icons.cancel_outlined;
      color = colorScheme.onSurfaceVariant;
    } else if (documento == null &&
        _visitaTemDocumentoPendente(visita, const <DocumentoGerado>[])) {
      label = 'Documento pendente';
      icon = Icons.pending_actions_outlined;
      color = Colors.orange;
    } else if (documento == null) {
      label = _visitaConcluida(visita)
          ? 'Sem documento'
          : _visitaEstadoLabel(visita.estado);
      icon = _visitaConcluida(visita)
          ? Icons.description_outlined
          : Icons.schedule_outlined;
      color = colorScheme.onSurfaceVariant;
    } else if (documento!.status == DocumentoStatus.cancelado) {
      label = '${documento!.numero} • Cancelado';
      icon = Icons.description_outlined;
      color = colorScheme.onSurfaceVariant;
    } else if (documento!.status == DocumentoStatus.erro) {
      label = '${documento!.numero} • Falha na geração';
      icon = Icons.error_outline;
      color = colorScheme.error;
    } else if (documento!.status == DocumentoStatus.gerando) {
      label = '${documento!.numero} • Geração pendente';
      icon = Icons.hourglass_top_rounded;
      color = Colors.orange;
    } else {
      label = '${documento!.numero} • Assinado';
      icon = Icons.verified_outlined;
      color = Colors.green;
    }

    return Wrap(
      spacing: 8,
      runSpacing: 5,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(100),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        if (quantidadeVersoes > 1)
          Text(
            '$quantidadeVersoes versões',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final (String, Color, IconData) info;

  const _StatusChip(this.info);

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = info;

    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      backgroundColor: color.withValues(alpha: 0.10),
      side: BorderSide(color: color.withValues(alpha: 0.28)),
      labelStyle: TextStyle(
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _FiltroChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _FiltroChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
      ),
    );
  }
}

class _WarningCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Color color;

  const _WarningCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(message),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogWarning extends StatelessWidget {
  final String mensagem;

  const _DialogWarning({required this.mensagem});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.warning_amber_rounded, color: Colors.orange),
        const SizedBox(width: 9),
        Expanded(child: Text(mensagem)),
      ],
    );
  }
}



class _LoadingCard extends StatelessWidget {
  final double height;

  const _LoadingCard({required this.height});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        child: const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  final String mensagem;

  const _InlineError({required this.mensagem});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colorScheme.error),
          const SizedBox(width: 9),
          Expanded(child: Text(mensagem)),
        ],
      ),
    );
  }
}

class _EmptySection extends StatelessWidget {
  final IconData icon;
  final String mensagem;

  const _EmptySection({
    required this.icon,
    required this.mensagem,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          Icon(icon, size: 36, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(
            mensagem,
            textAlign: TextAlign.center,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _PageMessage extends StatelessWidget {
  final IconData icon;
  final String titulo;
  final String mensagem;
  final String? botao;
  final VoidCallback? onPressed;

  const _PageMessage({
    required this.icon,
    required this.titulo,
    required this.mensagem,
    this.botao,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            children: [
              Icon(icon, size: 60, color: colorScheme.primary),
              const SizedBox(height: 18),
              Text(
                titulo,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                mensagem,
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              if (botao != null && onPressed != null) ...[
                const SizedBox(height: 18),
                FilledButton.tonal(
                  onPressed: onPressed,
                  child: Text(botao!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

bool _visitaConcluida(Visita visita) {
  return visita.estado == VisitaEstado.aguardandoAssinatura ||
      visita.estado == VisitaEstado.finalizada ||
      visita.estado == VisitaEstado.sincronizada;
}

bool _visitaTemDocumentoPendente(
    Visita visita,
    List<DocumentoGerado> documentos,
    ) {
  final geraDocumento = visita.tipo == VisitaTipo.instalacao ||
      visita.tipo == VisitaTipo.visita ||
      visita.tipo == VisitaTipo.coleta;

  if (!geraDocumento ||
      visita.estado == VisitaEstado.cancelada ||
      !_visitaConcluida(visita)) {
    return false;
  }

  return !documentos.any(
        (documento) => documento.status == DocumentoStatus.ativo,
  );
}

String _nomeExibicaoCliente(Cliente cliente) {
  final fantasia = cliente.nomeFantasia?.trim();
  return fantasia?.isNotEmpty == true ? fantasia! : cliente.nome;
}

String _textoConfirmacaoDocumento(DocumentoTipo tipo) => switch (tipo) {
  DocumentoTipo.instalacao =>
  'Li e confirmo o recebimento dos produtos e do expositor em '
      'consignação, bem como as quantidades, valores e condições '
      'apresentadas nesta instalação.',
  DocumentoTipo.acertoEReposicao =>
  'Li e confirmo a conferência, o acerto realizado e a nova posição '
      'consignada apresentada nesta operação.',
  DocumentoTipo.encerramento =>
  'Li e confirmo a conferência final, os valores apresentados e a '
      'retirada do expositor com o encerramento da consignação.',
};

int? _valorReposicaoExpositorCentavos(String? modelo) {
  final texto = modelo?.trim().toLowerCase() ?? '';

  if (texto.contains('grande')) return 100000;
  if (texto.contains('pequeno')) return 70000;

  return null;
}

int _snapshotInt(dynamic value) {
  return value is num ? value.toInt() : int.tryParse('$value') ?? 0;
}

int? _snapshotNullableInt(dynamic value) {
  if (value == null) return null;
  return value is num ? value.toInt() : int.tryParse('$value');
}

String _snapshotString(dynamic value) {
  return value?.toString().trim() ?? '';
}

String? _snapshotNullableString(dynamic value) {
  final texto = value?.toString().trim();
  return texto == null || texto.isEmpty ? null : texto;
}

List<Map<String, dynamic>> _snapshotMapList(dynamic value) {
  if (value is! List) return const [];

  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

ItemDocumento _itemDocumentoDoSnapshot(Map<String, dynamic> data) {
  return ItemDocumento(
    skuId: _snapshotString(data['skuId']),
    codigoInterno: _snapshotString(data['codigoInterno']),
    descricao: _snapshotString(data['descricao']),
    quantidade: _snapshotInt(data['quantidade']),
    precoVendaCentavosUnit:
    _snapshotInt(data['precoVendaCentavosUnit']),
    comissaoCentavosUnit:
    _snapshotInt(data['comissaoCentavosUnit']),
    saldoAnteriorQuantidade:
    _snapshotNullableInt(data['saldoAnteriorQuantidade']),
    quantidadeConferida:
    _snapshotNullableInt(data['quantidadeConferida']),
    quantidadeReposta:
    _snapshotNullableInt(data['quantidadeReposta']),
  );
}

VisitaResultado _visitaResultadoDoSnapshot(
    Visita visita,
    Map<String, dynamic> snapshot,
    ) {
  final consignmentNovaNumero =
  _snapshotString(snapshot['consignmentNovaNumero']);

  if (consignmentNovaNumero.isEmpty) {
    throw StateError(
      'O snapshot desta visita não possui a nova consignação.',
    );
  }

  return VisitaResultado(
    visitaId: visita.id ?? '',
    visitaNumero: visita.numero ?? visita.id ?? 'VISITA',
    consignmentAntigaNumero:
    _snapshotNullableString(snapshot['consignmentAntigaNumero']),
    consignmentNovaNumero: consignmentNovaNumero,
    totalVendidoCentavos:
    _snapshotInt(snapshot['totalVendidoCentavos']),
    comissaoRetidaCentavos:
    _snapshotInt(snapshot['comissaoRetidaCentavos']),
    valorAPagarNextGearCentavos:
    _snapshotInt(snapshot['valorAPagarNextGearCentavos']),
    novaExposicaoCentavos:
    _snapshotInt(snapshot['novaExposicaoCentavos']),
    expositorNumero:
    _snapshotNullableString(snapshot['expositorNumero']),
    expositorModeloNome:
    _snapshotNullableString(snapshot['expositorModeloNome']),
    itensCicloEncerrado:
    _snapshotMapList(snapshot['itensCicloEncerrado'])
        .map(_itemDocumentoDoSnapshot)
        .toList(),
    itensNovaPosicao:
    _snapshotMapList(snapshot['itensNovaPosicao'])
        .map(_itemDocumentoDoSnapshot)
        .toList(),
  );
}

RetiradaResultado _retiradaResultadoDoSnapshot(
    Visita visita,
    Map<String, dynamic> snapshot,
    ) {
  final motivoRaw = _snapshotString(snapshot['motivo']);

  final motivo = MotivoRetirada.values.firstWhere(
        (item) => item.name == motivoRaw,
    orElse: () => MotivoRetirada.outro,
  );

  final itens = _snapshotMapList(snapshot['itens'])
      .map(
        (data) => ItemDocumentoRetirada(
      codigoInterno: _snapshotString(data['codigoInterno']),
      descricao: _snapshotString(data['descricao']),
      saldoEsperado: _snapshotInt(data['saldoEsperado']),
      quantidadeDevolvida:
      _snapshotInt(data['quantidadeDevolvida']),
      repasseCentavosUnit:
      _snapshotInt(data['repasseCentavosUnit']),
      classificacaoLabel:
      _snapshotNullableString(data['classificacaoLabel']),
      geraCobranca: data['geraCobranca'] == true,
    ),
  )
      .toList();

  return RetiradaResultado(
    visitaId: visita.id ?? '',
    visitaNumero: visita.numero ?? visita.id ?? 'VISITA',
    consignmentEncerradaNumero:
    _snapshotString(snapshot['consignmentEncerradaNumero']),
    expositorNumero: _snapshotString(snapshot['expositorNumero']),
    expositorModeloNome:
    _snapshotString(snapshot['expositorModeloNome']),
    motivo: motivo,
    destinoExpositorLabel:
    _snapshotString(snapshot['destinoExpositorLabel']),
    itens: itens,
    valorARepassarTotalCentavos:
    _snapshotInt(snapshot['valorARepassarTotalCentavos']),
  );
}

Consignment? _consignacaoDoExpositor(
    ExpositorFisico expositor,
    List<Consignment> consignacoes,
    ) {
  for (final consignacao in consignacoes) {
    if (consignacao.expositorId == expositor.id) return consignacao;
  }
  return null;
}

List<DocumentoGerado> _documentosDaVisita(
    Visita visita,
    List<DocumentoGerado> documentos,
    ) {
  final relacionados = documentos.where((documento) {
    // Compatibilidade temporária:
    // documentos antigos receberam VIS-000000 no campo visitaId.
    // Depois da correção, o vínculo principal passa a ser o ID do Firestore.
    return documento.visitaId == visita.id ||
        (visita.numero != null && documento.visitaId == visita.numero);
  }).toList();

  relacionados.sort((a, b) {
    if (a.status != b.status) {
      return a.status == DocumentoStatus.ativo ? -1 : 1;
    }

    final dataA = a.criadoEm ?? a.assinatura?.timestamp;
    final dataB = b.criadoEm ?? b.assinatura?.timestamp;

    if (dataA == null && dataB == null) return 0;
    if (dataA == null) return 1;
    if (dataB == null) return -1;
    return dataB.compareTo(dataA);
  });

  return relacionados;
}

DocumentoGerado? _documentoVigente(List<DocumentoGerado> documentos) {
  if (documentos.isEmpty) return null;

  for (final documento in documentos) {
    if (documento.status == DocumentoStatus.ativo) return documento;
  }

  return documentos.first;
}

String _visitaTipoLabel(VisitaTipo tipo) => switch (tipo) {
  VisitaTipo.instalacao => 'Instalação',
  VisitaTipo.visita => 'Conferência e reposição',
  VisitaTipo.coleta => 'Retirada',
  VisitaTipo.transferencia => 'Transferência',
  VisitaTipo.inventario => 'Inventário',
};

IconData _iconeVisita(VisitaTipo tipo) => switch (tipo) {
  VisitaTipo.instalacao => Icons.add_business_outlined,
  VisitaTipo.visita => Icons.sync_outlined,
  VisitaTipo.coleta => Icons.move_to_inbox_outlined,
  VisitaTipo.transferencia => Icons.swap_horiz_outlined,
  VisitaTipo.inventario => Icons.inventory_outlined,
};

String _visitaEstadoLabel(VisitaEstado estado) => switch (estado) {
  VisitaEstado.agendada => 'Agendada',
  VisitaEstado.iniciada => 'Iniciada',
  VisitaEstado.emConferencia => 'Em conferência',
  VisitaEstado.conferenciaConcluida => 'Conferência concluída',
  VisitaEstado.emReposicao => 'Em reposição',
  VisitaEstado.aguardandoAssinatura => 'Aguardando assinatura',
  VisitaEstado.finalizada => 'Finalizada',
  VisitaEstado.sincronizada => 'Sincronizada',
  VisitaEstado.cancelada => 'Cancelada',
};

(String, Color, IconData) _cadastroInfo(StatusCadastro status) =>
    switch (status) {
      StatusCadastro.rascunho =>
      ('Rascunho', Colors.grey, Icons.edit_note),
      StatusCadastro.emAnalise =>
      ('Em análise', Colors.orange, Icons.hourglass_top),
      StatusCadastro.aprovado =>
      ('Aprovado', Colors.green, Icons.verified_outlined),
      StatusCadastro.reprovado =>
      ('Reprovado', Colors.red, Icons.cancel_outlined),
    };

(String, Color, IconData) _operacionalInfo(StatusOperacional status) =>
    switch (status) {
      StatusOperacional.pendente =>
      ('Pendente', Colors.grey, Icons.pending_outlined),
      StatusOperacional.aguardandoInstalacao => (
      'Aguardando instalação',
      Colors.orange,
      Icons.storefront_outlined,
      ),
      StatusOperacional.ativo =>
      ('Ativo', Colors.green, Icons.check_circle_outline),
      StatusOperacional.suspenso =>
      ('Suspenso', Colors.orange, Icons.pause_circle_outline),
      StatusOperacional.encerrado =>
      ('Encerrado', Colors.grey, Icons.stop_circle_outlined),
    };

(String, Color, IconData) _financeiroInfo(StatusFinanceiro status) =>
    switch (status) {
      StatusFinanceiro.normal =>
      ('Financeiro normal', Colors.green, Icons.payments_outlined),
      StatusFinanceiro.alerta =>
      ('Alerta financeiro', Colors.orange, Icons.warning_amber_outlined),
      StatusFinanceiro.bloqueado =>
      ('Financeiro bloqueado', Colors.red, Icons.lock_outline),
    };
