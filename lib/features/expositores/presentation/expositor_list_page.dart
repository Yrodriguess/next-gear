import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/current_org_provider.dart';
import '../../../core/widgets/erro_carregamento.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../clientes/domain/cliente.dart';
import '../../clientes/presentation/cliente_providers.dart';
import '../../consignacoes/domain/consignment.dart';
import '../../consignacoes/presentation/consignment_providers.dart';
import '../domain/expositor_fisico.dart';
import '../domain/expositor_modelo.dart';
import 'expositor_providers.dart';
import 'expositor_status_ui.dart';
import 'expositor_detail_page.dart';

/// Mesmo ponto de corte usado no AppShell — acima disso mostramos
/// botões com texto no cabeçalho; abaixo, ícones compactos + FAB.
const double _kDesktopBreakpoint = 840;

/// Status sempre mostrados no resumo, mesmo com contagem zero — os
/// outros (reservado, recolhido, descartado, perdido) só aparecem se
/// tiver pelo menos 1 unidade, pra não poluir o resumo.
const List<ExpositorStatus> _statusPrincipais = [
  ExpositorStatus.disponivel,
  ExpositorStatus.instalado,
  ExpositorStatus.manutencao,
];

enum _OrdenacaoExpositores {
  patrimonio,
  maisRecentes,
  status,
  modelo,
  cliente,
}

class ExpositorListPage extends ConsumerStatefulWidget {
  const ExpositorListPage({super.key});

  @override
  ConsumerState<ExpositorListPage> createState() => _ExpositorListPageState();
}

class _ExpositorListPageState extends ConsumerState<ExpositorListPage> {
  final _buscaController = TextEditingController();
  String _busca = '';
  ExpositorStatus? _statusFiltro;
  String? _modeloFiltro;
  _OrdenacaoExpositores _ordenacao = _OrdenacaoExpositores.patrimonio;
  bool _criandoExpositor = false;
  bool _criandoLote = false;

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  bool get _temFiltroAtivo =>
      _busca.isNotEmpty || _statusFiltro != null || _modeloFiltro != null;

  void _limparFiltros() {
    setState(() {
      _busca = '';
      _buscaController.clear();
      _statusFiltro = null;
      _modeloFiltro = null;
    });
  }

  Future<void> _abrirNovoModelo(BuildContext context, WidgetRef ref) async {
    final orgId = ref.read(currentOrgIdProvider);
    if (orgId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sessão inválida. Faça login novamente.')),
      );
      return;
    }

    final controller = TextEditingController();
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          bool salvando = false;
          String? erro;
          return StatefulBuilder(
            builder: (context, setStateDialog) => AlertDialog(
              title: const Text('Novo modelo de expositor'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: controller,
                    enabled: !salvando,
                    autofocus: true,
                    decoration: const InputDecoration(
                        labelText: 'Nome (ex: Grande, Pequeno)'),
                  ),
                  if (erro != null) ...[
                    const SizedBox(height: 8),
                    Text(erro!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12)),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: salvando
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: salvando
                      ? null
                      : () async {
                    final nome = controller.text.trim();
                    if (nome.isEmpty) {
                      setStateDialog(() => erro = 'Informe um nome.');
                      return;
                    }
                    setStateDialog(() {
                      salvando = true;
                      erro = null;
                    });
                    try {
                      await ref
                          .read(expositorModeloRepositoryProvider)
                          .create(ExpositorModelo(orgId: orgId, nome: nome));
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                    } catch (e, st) {
                      debugPrint('Erro ao criar modelo de expositor: $e\n$st');
                      setStateDialog(() {
                        salvando = false;
                        erro = 'Não foi possível criar o modelo. Tente novamente.';
                      });
                    }
                  },
                  child: salvando
                      ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Text('Criar'),
                ),
              ],
            ),
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _abrirNovoExpositor(
      BuildContext context,
      WidgetRef ref,
      List<ExpositorModelo> modelos,
      ) async {
    final orgId = ref.read(currentOrgIdProvider);

    if (orgId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sessão inválida. Faça login novamente.'),
        ),
      );
      return;
    }

    if (modelos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cadastre um modelo antes (ex: Grande, Pequeno).',
          ),
        ),
      );
      return;
    }

    ExpositorModelo modeloEscolhido = modelos.first;
    final serieController = TextEditingController();
    final observacaoController = TextEditingController();

    try {
      final confirmado = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Novo expositor'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<ExpositorModelo>(
                  initialValue: modeloEscolhido,
                  decoration: const InputDecoration(
                    labelText: 'Modelo',
                  ),
                  items: modelos
                      .map(
                        (modelo) => DropdownMenuItem(
                      value: modelo,
                      child: Text(modelo.nome),
                    ),
                  )
                      .toList(),
                  onChanged: (modelo) {
                    if (modelo != null) {
                      modeloEscolhido = modelo;
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: serieController,
                  decoration: const InputDecoration(
                    labelText: 'Nº de série do fabricante',
                    helperText: 'Opcional',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: observacaoController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Observação',
                    helperText: 'Opcional',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                const _DialogInfo(
                  texto:
                  'O patrimônio NEXT GEAR será gerado automaticamente.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.add),
              label: const Text('Cadastrar expositor'),
            ),
          ],
        ),
      );

      if (confirmado != true || !mounted) return;

      final usuario = ref.read(appUserProvider).value;
      if (usuario == null) return;

      setState(() => _criandoExpositor = true);

      try {
        final numero = await ref
            .read(expositorFisicoRepositoryProvider)
            .create(
          orgId: orgId,
          modeloId: modeloEscolhido.id!,
          modeloNome: modeloEscolhido.nome,
          usuarioId: usuario.uid,
          numeroSerieFabricante:
          serieController.text.trim().isEmpty
              ? null
              : serieController.text.trim(),
          observacoes:
          observacaoController.text.trim().isEmpty
              ? null
              : observacaoController.text.trim(),
        );

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Expositor $numero criado!'),
            ),
          );
        }
      } catch (e, st) {
        debugPrint('Erro ao criar expositor: $e\n$st');

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Não foi possível criar o expositor. Tente novamente.',
              ),
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _criandoExpositor = false);
        }
      }
    } finally {
      serieController.dispose();
      observacaoController.dispose();
    }
  }

  Future<void> _abrirCadastroLote(
      BuildContext context,
      WidgetRef ref,
      List<ExpositorModelo> modelos,
      ) async {
    final orgId = ref.read(currentOrgIdProvider);
    if (orgId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sessão inválida. Faça login novamente.')),
      );
      return;
    }
    if (modelos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Cadastre um modelo antes (ex: Grande, Pequeno).')),
      );
      return;
    }

    final repository = ref.read(expositorFisicoRepositoryProvider);
    ExpositorModelo modeloEscolhido = modelos.first;
    final quantidadeController = TextEditingController();
    int proximaSequencia =
    await repository.obterProximaSequencia(orgId, modeloEscolhido.nome);

    if (!context.mounted) return;

    String? erroValidacao;

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setStateDialog) {
          final quantidade = int.tryParse(quantidadeController.text);
          final abreviacao = modeloEscolhido.nome
              .toUpperCase()
              .replaceAll(RegExp(r'[^A-Z]'), '')
              .padRight(3, 'X')
              .substring(0, 3);
          final previewInicio =
              'EXP-$abreviacao-${proximaSequencia.toString().padLeft(3, '0')}';
          final previewFim = (quantidade != null && quantidade > 0)
              ? 'EXP-$abreviacao-${(proximaSequencia + quantidade - 1).toString().padLeft(3, '0')}'
              : previewInicio;

          return AlertDialog(
            title: const Text('Cadastro em lote'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<ExpositorModelo>(
                  initialValue: modeloEscolhido,
                  decoration: const InputDecoration(labelText: 'Modelo'),
                  items: modelos
                      .map((m) => DropdownMenuItem(value: m, child: Text(m.nome)))
                      .toList(),
                  onChanged: (m) async {
                    if (m == null) return;
                    final novaSequencia =
                    await repository.obterProximaSequencia(orgId, m.nome);
                    setStateDialog(() {
                      modeloEscolhido = m;
                      proximaSequencia = novaSequencia;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: quantidadeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Quantidade',
                    helperText: 'Entre 1 e 200',
                  ),
                  onChanged: (_) => setStateDialog(() => erroValidacao = null),
                ),
                const SizedBox(height: 12),
                Text(
                  (quantidade != null && quantidade > 0)
                      ? 'Serão criados de $previewInicio até $previewFim.'
                      : 'Informe uma quantidade.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (erroValidacao != null) ...[
                  const SizedBox(height: 8),
                  Text(erroValidacao!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  if (quantidade == null || quantidade <= 0 || quantidade > 200) {
                    setStateDialog(() =>
                    erroValidacao = 'Informe uma quantidade entre 1 e 200.');
                    return;
                  }
                  Navigator.of(dialogContext).pop(true);
                },
                child: const Text('Cadastrar'),
              ),
            ],
          );
        },
      ),
    );

    final quantidade = int.tryParse(quantidadeController.text) ?? 0;
    quantidadeController.dispose();
    if (confirmado != true) return;

    final usuario = ref.read(appUserProvider).value;
    if (usuario == null) return;

    setState(() => _criandoLote = true);

    try {
      final numeros = await repository.createLote(
        orgId: orgId,
        modeloId: modeloEscolhido.id!,
        modeloNome: modeloEscolhido.nome,
        quantidade: quantidade,
        usuarioId: usuario.uid,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '${numeros.length} expositores criados: ${numeros.first} até ${numeros.last}')),
        );
      }
    } catch (e, st) {
      debugPrint('Erro ao cadastrar lote de expositores: $e\n$st');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível cadastrar o lote. Tente novamente.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _criandoLote = false);
      }
    }
  }

  String _nomeCliente(Cliente cliente) {
    final fantasia = cliente.nomeFantasia?.trim();
    return fantasia?.isNotEmpty == true ? fantasia! : cliente.nome;
  }

  String _conservacaoLabel(EstadoConservacao estado) => switch (estado) {
    EstadoConservacao.novo => 'Novo',
    EstadoConservacao.bom => 'Bom',
    EstadoConservacao.regular => 'Regular',
    EstadoConservacao.ruim => 'Ruim',
  };

  Cliente? _clienteVinculado(
      ExpositorFisico expositor,
      Map<String, Cliente> clientesPorId,
      ) {
    final clienteId = expositor.status == ExpositorStatus.reservado
        ? expositor.clienteReservadoId
        : expositor.clienteAtualId;

    return clienteId == null ? null : clientesPorId[clienteId];
  }

  String _localTexto(
      ExpositorFisico expositor,
      Map<String, Cliente> clientesPorId, {
        required bool clientesIndisponiveis,
      }) {
    final cliente = _clienteVinculado(expositor, clientesPorId);

    if (expositor.status == ExpositorStatus.reservado) {
      if (cliente != null) {
        return 'Reservado para ${_nomeCliente(cliente)}';
      }
      return clientesIndisponiveis
          ? 'Reserva • cliente indisponível'
          : 'Reservado • cliente não encontrado';
    }

    if (expositor.clienteAtualId != null) {
      if (cliente != null) return _nomeCliente(cliente);
      return clientesIndisponiveis
          ? 'Cliente indisponível'
          : 'Cliente não encontrado';
    }

    return switch (expositor.status) {
      ExpositorStatus.manutencao => 'Em manutenção',
      ExpositorStatus.recolhido => 'Aguardando conferência',
      ExpositorStatus.descartado => 'Descartado',
      ExpositorStatus.perdido => 'Registrado como perdido',
      _ => 'Estoque central',
    };
  }

  List<ExpositorFisico> _aplicarFiltros(
      List<ExpositorFisico> expositores,
      List<Cliente> clientes,
      ) {
    var filtrados = List<ExpositorFisico>.from(expositores);

    final clientesPorId = <String, Cliente>{
      for (final cliente in clientes)
        if (cliente.id != null) cliente.id!: cliente,
    };

    if (_statusFiltro != null) {
      filtrados = filtrados
          .where((expositor) => expositor.status == _statusFiltro)
          .toList();
    }

    if (_modeloFiltro != null) {
      filtrados = filtrados
          .where((expositor) => expositor.modeloId == _modeloFiltro)
          .toList();
    }

    if (_busca.isNotEmpty) {
      final termo = _busca.toLowerCase();

      filtrados = filtrados.where((expositor) {
        if (expositor.numero.toLowerCase().contains(termo)) {
          return true;
        }

        if ((expositor.numeroSerieFabricante ?? '')
            .toLowerCase()
            .contains(termo)) {
          return true;
        }

        if (expositor.modeloNome.toLowerCase().contains(termo)) {
          return true;
        }

        if (statusLabel(expositor.status).toLowerCase().contains(termo)) {
          return true;
        }

        if ((expositor.observacoes ?? '').toLowerCase().contains(termo)) {
          return true;
        }

        final cliente =
        _clienteVinculado(expositor, clientesPorId);

        if (cliente == null) return false;

        final camposCliente = [
          cliente.nome,
          cliente.nomeFantasia ?? '',
          cliente.cpfCnpj,
        ].join(' ').toLowerCase();

        return camposCliente.contains(termo);
      }).toList();
    }

    int compararNullableDateDesc(DateTime? a, DateTime? b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return b.compareTo(a);
    }

    filtrados.sort((a, b) {
      return switch (_ordenacao) {
        _OrdenacaoExpositores.patrimonio =>
            a.numero.compareTo(b.numero),
        _OrdenacaoExpositores.maisRecentes =>
            compararNullableDateDesc(a.createdAt, b.createdAt),
        _OrdenacaoExpositores.status =>
            statusLabel(a.status).compareTo(statusLabel(b.status)),
        _OrdenacaoExpositores.modelo =>
            a.modeloNome.compareTo(b.modeloNome),
        _OrdenacaoExpositores.cliente => () {
          final clienteA = _clienteVinculado(a, clientesPorId);
          final clienteB = _clienteVinculado(b, clientesPorId);

          final nomeA =
          clienteA == null ? '' : _nomeCliente(clienteA);
          final nomeB =
          clienteB == null ? '' : _nomeCliente(clienteB);

          final comparacao = nomeA.compareTo(nomeB);
          return comparacao != 0
              ? comparacao
              : a.numero.compareTo(b.numero);
        }(),
      };
    });

    return filtrados;
  }

  @override
  Widget build(BuildContext context) {
    final expositoresAsync = ref.watch(expositoresFisicosListProvider);
    final clientesAsync = ref.watch(clientesListProvider);
    final modelosAsync = ref.watch(expositorModelosListProvider);
    final orgId = ref.watch(currentOrgIdProvider);
    final consignacoesAsync = orgId == null
        ? const AsyncValue<List<Consignment>>.data(<Consignment>[])
        : ref.watch(consignmentsAtivasProvider(orgId));
    final isDesktop = MediaQuery.sizeOf(context).width >= _kDesktopBreakpoint;
    final modelos = modelosAsync.value ?? const <ExpositorModelo>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expositores'),
        actions: isDesktop
            ? [
          TextButton.icon(
            icon: const Icon(Icons.category_outlined),
            label: const Text('Novo modelo'),
            onPressed: () => _abrirNovoModelo(context, ref),
          ),
          TextButton.icon(
            icon: _criandoLote
                ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Icon(Icons.dynamic_feed_outlined),
            label: Text(
              _criandoLote ? 'Cadastrando...' : 'Cadastrar lote',
            ),
            onPressed: _criandoLote
                ? null
                : () => _abrirCadastroLote(context, ref, modelos),
          ),
          FilledButton.icon(
            icon: _criandoExpositor
                ? const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Icon(Icons.add),
            label: const Text('Novo expositor'),
            onPressed: _criandoExpositor
                ? null
                : () => _abrirNovoExpositor(context, ref, modelos),
          ),
          const SizedBox(width: 12),
        ]
            : [
          IconButton(
            icon: const Icon(Icons.category_outlined),
            tooltip: 'Novo modelo',
            onPressed: () => _abrirNovoModelo(context, ref),
          ),
          IconButton(
            icon: _criandoLote
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Icon(Icons.dynamic_feed_outlined),
            tooltip: 'Cadastro em lote',
            onPressed: _criandoLote
                ? null
                : () => _abrirCadastroLote(context, ref, modelos),
          ),
        ],
      ),
      floatingActionButton: isDesktop
          ? null
          : FloatingActionButton.extended(
        heroTag: 'expositores_novo_fab',
        icon: _criandoExpositor
            ? const SizedBox(
          height: 16,
          width: 16,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: Colors.white),
        )
            : const Icon(Icons.add),
        label: const Text('Novo expositor'),
        onPressed: _criandoExpositor
            ? null
            : () => _abrirNovoExpositor(context, ref, modelos),
      ),
      body: expositoresAsync.when(
        data: (expositores) => _buildBody(
          context,
          expositores,
          clientesAsync,
          modelos,
          isDesktop,
          consignacoesAsync,
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) {
          debugPrint('Erro ao carregar expositores: $error\n$stack');
          return ErroCarregamento(
            mensagem: 'Não foi possível carregar os expositores.',
            onTentarNovamente: () =>
                ref.invalidate(expositoresFisicosListProvider),
          );
        },
      ),
    );
  }

  Widget _buildBody(
      BuildContext context,
      List<ExpositorFisico> expositores,
      AsyncValue<List<Cliente>> clientesAsync,
      List<ExpositorModelo> modelos,
      bool isDesktop,
      AsyncValue<List<Consignment>> consignacoesAsync,
      ) {
    if (expositores.isEmpty) {
      return _EstadoVazio(
        onCriarModelo: () => _abrirNovoModelo(context, ref),
        onCriarExpositor: modelos.isEmpty
            ? null
            : () => _abrirNovoExpositor(context, ref, modelos),
      );
    }

    final clientes = clientesAsync.value ?? const <Cliente>[];
    final clientesIndisponiveis = clientesAsync.hasError;

    final clientesPorId = <String, Cliente>{
      for (final cliente in clientes)
        if (cliente.id != null) cliente.id!: cliente,
    };

    final consignacoes = consignacoesAsync.value ?? const <Consignment>[];
    final consignacaoPorExpositor = <String, Consignment>{
      for (final consignacao in consignacoes)
        if (consignacao.expositorId != null)
          consignacao.expositorId!: consignacao,
    };

    final filtrados = _aplicarFiltros(expositores, clientes);

    final porStatus = <ExpositorStatus, int>{};
    for (final expositor in expositores) {
      porStatus[expositor.status] =
          (porStatus[expositor.status] ?? 0) + 1;
    }

    final statusParaMostrar = {
      ..._statusPrincipais,
      ...porStatus.keys.where(
            (status) => (porStatus[status] ?? 0) > 0,
      ),
    }.toList();

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(expositoresFisicosListProvider);
        ref.invalidate(clientesListProvider);

        final orgId = ref.read(currentOrgIdProvider);
        if (orgId != null) {
          ref.invalidate(consignmentsAtivasProvider(orgId));
        }
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        child: ResponsiveCenter(
          maxWidth: isDesktop ? 1180 : 640,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),

                if (clientesIndisponiveis)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _AvisoInline(
                      mensagem:
                      'Não foi possível carregar os clientes agora. '
                          'Alguns vínculos podem aparecer indisponíveis.',
                    ),
                  ),

                LayoutBuilder(
                  builder: (context, constraints) {
                    final largura = constraints.maxWidth;
                    final colunas = largura >= 980
                        ? 4
                        : largura >= 620
                        ? 3
                        : 2;
                    const gap = 10.0;
                    final larguraCard =
                        (largura - ((colunas - 1) * gap)) / colunas;

                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        SizedBox(
                          width: larguraCard,
                          child: _ResumoCard(
                            label: 'Total',
                            valor: expositores.length,
                            selecionado: _statusFiltro == null,
                            onTap: () =>
                                setState(() => _statusFiltro = null),
                          ),
                        ),
                        for (final status in statusParaMostrar)
                          SizedBox(
                            width: larguraCard,
                            child: _ResumoCard(
                              label: statusLabel(status),
                              valor: porStatus[status] ?? 0,
                              cor: statusColor(status),
                              selecionado: _statusFiltro == status,
                              onTap: () => setState(
                                    () => _statusFiltro = status,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 18),

                TextField(
                  controller: _buscaController,
                  textInputAction: TextInputAction.search,
                  onChanged: (valor) {
                    setState(() {
                      _busca = valor.trim();
                    });
                  },
                  decoration: InputDecoration(
                    labelText:
                    'Buscar patrimônio, série, modelo, cliente, CPF/CNPJ...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _busca.isNotEmpty
                        ? IconButton(
                      tooltip: 'Limpar busca',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _buscaController.clear();
                        setState(() => _busca = '');
                      },
                    )
                        : null,
                  ),
                ),

                const SizedBox(height: 12),

                LayoutBuilder(
                  builder: (context, constraints) {
                    final compacto = constraints.maxWidth < 620;

                    final modelo = _ModeloDropdown(
                      modelos: modelos,
                      valor: _modeloFiltro,
                      onChanged: (valor) {
                        setState(() => _modeloFiltro = valor);
                      },
                    );

                    final ordem = _OrdenacaoDropdown(
                      valor: _ordenacao,
                      onChanged: (valor) {
                        setState(() => _ordenacao = valor);
                      },
                    );

                    if (compacto) {
                      return Column(
                        children: [
                          modelo,
                          const SizedBox(height: 10),
                          ordem,
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: modelo),
                        const SizedBox(width: 12),
                        Expanded(child: ordem),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${filtrados.length} de ${expositores.length} expositores',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (_temFiltroAtivo)
                      TextButton.icon(
                        onPressed: _limparFiltros,
                        icon: const Icon(
                          Icons.filter_alt_off_outlined,
                          size: 18,
                        ),
                        label: const Text('Limpar filtros'),
                      ),
                  ],
                ),

                const SizedBox(height: 10),

                if (filtrados.isEmpty)
                  _SemResultado(
                    onLimparFiltros: _limparFiltros,
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final usarTabela =
                          constraints.maxWidth >= 900;

                      if (usarTabela) {
                        return _ExpositoresTabela(
                          expositores: filtrados,
                          clientesPorId: clientesPorId,
                          consignacaoPorExpositor:
                          consignacaoPorExpositor,
                          clientesIndisponiveis:
                          clientesIndisponiveis,
                          localTexto: (
                              expositor,
                              ) =>
                              _localTexto(
                                expositor,
                                clientesPorId,
                                clientesIndisponiveis:
                                clientesIndisponiveis,
                              ),
                          conservacaoLabel:
                          _conservacaoLabel,
                        );
                      }

                      return Column(
                        children: [
                          for (var index = 0;
                          index < filtrados.length;
                          index++) ...[
                            _ExpositorMobileCard(
                              expositor: filtrados[index],
                              localTexto: _localTexto(
                                filtrados[index],
                                clientesPorId,
                                clientesIndisponiveis:
                                clientesIndisponiveis,
                              ),
                              conservacao: _conservacaoLabel(
                                filtrados[index].estadoConservacao,
                              ),
                              consignacao:
                              consignacaoPorExpositor[
                              filtrados[index].id],
                            ),
                            if (index != filtrados.length - 1)
                              const SizedBox(height: 10),
                          ],
                        ],
                      );
                    },
                  ),

                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ),
    );
  }

}

class _OrdenacaoDropdown extends StatelessWidget {
  final _OrdenacaoExpositores valor;
  final ValueChanged<_OrdenacaoExpositores> onChanged;

  const _OrdenacaoDropdown({
    required this.valor,
    required this.onChanged,
  });

  String _label(_OrdenacaoExpositores ordem) => switch (ordem) {
    _OrdenacaoExpositores.patrimonio => 'Patrimônio A–Z',
    _OrdenacaoExpositores.maisRecentes => 'Mais recentes',
    _OrdenacaoExpositores.status => 'Status',
    _OrdenacaoExpositores.modelo => 'Modelo',
    _OrdenacaoExpositores.cliente => 'Cliente',
  };

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<_OrdenacaoExpositores>(
      initialValue: valor,
      decoration: const InputDecoration(
        labelText: 'Ordenar por',
        prefixIcon: Icon(Icons.sort),
      ),
      items: _OrdenacaoExpositores.values
          .map(
            (ordem) => DropdownMenuItem(
          value: ordem,
          child: Text(_label(ordem)),
        ),
      )
          .toList(),
      onChanged: (ordem) {
        if (ordem != null) onChanged(ordem);
      },
    );
  }
}

class _ExpositoresTabela extends StatelessWidget {
  final List<ExpositorFisico> expositores;
  final Map<String, Cliente> clientesPorId;
  final Map<String, Consignment> consignacaoPorExpositor;
  final bool clientesIndisponiveis;
  final String Function(ExpositorFisico expositor) localTexto;
  final String Function(EstadoConservacao estado) conservacaoLabel;

  const _ExpositoresTabela({
    required this.expositores,
    required this.clientesPorId,
    required this.consignacaoPorExpositor,
    required this.clientesIndisponiveis,
    required this.localTexto,
    required this.conservacaoLabel,
  });

  void _abrir(
      BuildContext context,
      ExpositorFisico expositor,
      ) {
    if (expositor.id == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExpositorDetailPage(
          expositorId: expositor.id!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 11,
            ),
            color: colorScheme.surfaceContainerLow,
            child: const Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _TabelaCabecalho('Patrimônio'),
                ),
                Expanded(
                  flex: 2,
                  child: _TabelaCabecalho('Modelo'),
                ),
                Expanded(
                  flex: 3,
                  child: _TabelaCabecalho('Cliente / Local'),
                ),
                Expanded(
                  flex: 2,
                  child: _TabelaCabecalho('Mercadoria'),
                ),
                SizedBox(
                  width: 120,
                  child: _TabelaCabecalho('Status'),
                ),
                SizedBox(width: 38),
              ],
            ),
          ),
          for (var index = 0;
          index < expositores.length;
          index++) ...[
            _ExpositorTabelaLinha(
              expositor: expositores[index],
              localTexto: localTexto(expositores[index]),
              conservacao:
              conservacaoLabel(expositores[index].estadoConservacao),
              consignacao:
              consignacaoPorExpositor[expositores[index].id],
              onTap: () => _abrir(
                context,
                expositores[index],
              ),
            ),
            if (index != expositores.length - 1)
              const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _TabelaCabecalho extends StatelessWidget {
  final String texto;

  const _TabelaCabecalho(this.texto);

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w800,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _ExpositorTabelaLinha extends StatelessWidget {
  final ExpositorFisico expositor;
  final String localTexto;
  final String conservacao;
  final Consignment? consignacao;
  final VoidCallback onTap;

  const _ExpositorTabelaLinha({
    required this.expositor,
    required this.localTexto,
    required this.conservacao,
    required this.consignacao,
    required this.onTap,
  });

  int get _unidades => consignacao?.itens.fold<int>(
    0,
        (total, item) => total + item.quantidade,
  ) ??
      0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 13,
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    expositor.numero,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (expositor.numeroSerieFabricante?.trim().isNotEmpty ==
                      true)
                    Text(
                      'Série ${expositor.numeroSerieFabricante}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(expositor.modeloNome),
                  Text(
                    conservacao,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                localTexto,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: consignacao == null
                  ? Text(
                '—',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                ),
              )
                  : Text(
                '${consignacao!.itens.length} SKUs • $_unidades un.',
              ),
            ),
            SizedBox(
              width: 120,
              child: Align(
                alignment: Alignment.centerLeft,
                child: StatusChip(
                  status: expositor.status,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpositorMobileCard extends StatelessWidget {
  final ExpositorFisico expositor;
  final String localTexto;
  final String conservacao;
  final Consignment? consignacao;

  const _ExpositorMobileCard({
    required this.expositor,
    required this.localTexto,
    required this.conservacao,
    required this.consignacao,
  });

  int get _unidades => consignacao?.itens.fold<int>(
    0,
        (total, item) => total + item.quantidade,
  ) ??
      0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: colorScheme.outlineVariant,
        ),
      ),
      child: InkWell(
        onTap: expositor.id == null
            ? null
            : () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ExpositorDetailPage(
                expositorId: expositor.id!,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(15),
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
                          expositor.numero,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          expositor.modeloNome,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusChip(status: expositor.status),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.place_outlined,
                    size: 17,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      localTexto,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  _MiniInfo(
                    icon: Icons.health_and_safety_outlined,
                    texto: conservacao,
                  ),
                  if (consignacao != null)
                    _MiniInfo(
                      icon: Icons.category_outlined,
                      texto: '${consignacao!.itens.length} SKUs',
                    ),
                  if (consignacao != null)
                    _MiniInfo(
                      icon: Icons.inventory_2_outlined,
                      texto: '$_unidades un.',
                    ),
                  if (expositor.numeroSerieFabricante?.trim().isNotEmpty ==
                      true)
                    _MiniInfo(
                      icon: Icons.tag_outlined,
                      texto: 'Série ${expositor.numeroSerieFabricante}',
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

class _MiniInfo extends StatelessWidget {
  final IconData icon;
  final String texto;

  const _MiniInfo({
    required this.icon,
    required this.texto,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 15,
          color: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 5),
        Text(
          texto,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _AvisoInline extends StatelessWidget {
  final String mensagem;

  const _AvisoInline({
    required this.mensagem,
  });

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: error.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: error.withValues(alpha: .24),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: error,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              mensagem,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogInfo extends StatelessWidget {
  final String texto;

  const _DialogInfo({
    required this.texto,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: .3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              texto,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeloDropdown extends StatelessWidget {
  final List<ExpositorModelo> modelos;
  final String? valor;
  final ValueChanged<String?> onChanged;

  const _ModeloDropdown({
    required this.modelos,
    required this.valor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      initialValue: valor,
      decoration: const InputDecoration(labelText: 'Modelo'),
      items: [
        const DropdownMenuItem(value: null, child: Text('Todos os modelos')),
        ...modelos.map(
              (m) => DropdownMenuItem(value: m.id, child: Text(m.nome)),
        ),
      ],
      onChanged: onChanged,
    );
  }
}


/// Card de resumo clicável — clicar já aplica o filtro de status
/// correspondente.
class _ResumoCard extends StatelessWidget {
  final String label;
  final int valor;
  final Color? cor;
  final bool selecionado;
  final VoidCallback onTap;

  const _ResumoCard({
    required this.label,
    required this.valor,
    this.cor,
    required this.selecionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final corBase = cor ?? Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selecionado ? corBase : corBase.withValues(alpha: 0.3),
            width: selecionado ? 2 : 1,
          ),
          color: selecionado ? corBase.withValues(alpha: 0.12) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$valor',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold, color: corBase)),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _EstadoVazio extends StatelessWidget {
  final VoidCallback onCriarModelo;
  final VoidCallback? onCriarExpositor;

  const _EstadoVazio({required this.onCriarModelo, this.onCriarExpositor});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dashboard_customize_outlined,
                size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            const Text('Nenhum expositor cadastrado ainda.',
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              onCriarExpositor == null
                  ? 'Primeiro cadastre um modelo (ex: Grande, Pequeno).'
                  : 'Cadastre o primeiro expositor pra começar.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: onCriarModelo,
                  icon: const Icon(Icons.category_outlined),
                  label: const Text('Criar modelo'),
                ),
                if (onCriarExpositor != null)
                  FilledButton.icon(
                    onPressed: onCriarExpositor,
                    icon: const Icon(Icons.add),
                    label: const Text('Cadastrar primeiro expositor'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SemResultado extends StatelessWidget {
  final VoidCallback onLimparFiltros;
  const _SemResultado({required this.onLimparFiltros});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 48),
            const SizedBox(height: 12),
            const Text('Nenhum expositor encontrado com esse filtro.'),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onLimparFiltros,
              child: const Text('Limpar filtros'),
            ),
          ],
        ),
      ),
    );
  }
}
