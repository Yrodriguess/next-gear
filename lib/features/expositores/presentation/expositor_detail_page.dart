import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/erro_carregamento.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../auth/presentation/auth_providers.dart'
    hide usuariosListProvider;
import '../../auth/presentation/usuario_providers.dart';
import '../../clientes/domain/cliente.dart';
import '../../clientes/presentation/cliente_detail_page.dart';
import '../../clientes/presentation/cliente_providers.dart';
import '../../consignacoes/domain/consignment.dart';
import '../../consignacoes/domain/consignment_item.dart';
import '../../consignacoes/presentation/consignment_providers.dart';
import '../../visitas/presentation/instalacao_page.dart';
import '../../visitas/presentation/retirada_conferencia_page.dart';
import '../domain/expositor_fisico.dart';
import '../domain/expositor_movimentacao.dart';
import 'expositor_providers.dart';
import 'expositor_status_ui.dart';

/// Mesmo ponto de corte usado no restante do módulo de Expositores.
const double _kDesktopBreakpoint = 800;

enum _AcaoStatusExpositor {
  manutencao,
  perdido,
  descarte,
}

final _formatoMoeda =
NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

/// Diálogo de busca de cliente — usado tanto na alocação quanto na
/// transferência. Não seleciona ninguém automaticamente: a pessoa
/// precisa tocar num resultado.
Future<Cliente?> _selecionarCliente(
    BuildContext context, {
      required String titulo,
      required List<Cliente> clientes,
    }) async {
  final buscaController = TextEditingController();
  try {
    return await showDialog<Cliente>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setStateDialog) {
          final termo = buscaController.text.trim().toLowerCase();
          final filtrados = termo.isEmpty
              ? clientes
              : clientes.where((c) {
            final nome = (c.nomeFantasia?.isNotEmpty == true
                ? c.nomeFantasia!
                : c.nome)
                .toLowerCase();
            return nome.contains(termo);
          }).toList();

          return AlertDialog(
            title: Text(titulo),
            content: SizedBox(
              width: 420,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    controller: buscaController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Buscar cliente',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) => setStateDialog(() {}),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtrados.isEmpty
                        ? const Center(child: Text('Nenhum cliente encontrado.'))
                        : ListView.builder(
                      itemCount: filtrados.length,
                      itemBuilder: (context, index) {
                        final c = filtrados[index];
                        final nome = c.nomeFantasia?.isNotEmpty == true
                            ? c.nomeFantasia!
                            : c.nome;
                        return ListTile(
                          title: Text(nome),
                          onTap: () => Navigator.of(dialogContext).pop(c),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancelar'),
              ),
            ],
          );
        },
      ),
    );
  } finally {
    buscaController.dispose();
  }
}

class ExpositorDetailPage extends ConsumerStatefulWidget {
  final String expositorId;
  const ExpositorDetailPage({super.key, required this.expositorId});

  @override
  ConsumerState<ExpositorDetailPage> createState() => _ExpositorDetailPageState();
}

class _ExpositorDetailPageState extends ConsumerState<ExpositorDetailPage> {
  bool _processando = false;

  void _copiar(String texto, String rotulo) {
    Clipboard.setData(ClipboardData(text: texto));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$rotulo copiado.')),
    );
  }

  // ── Reservar para cliente (status: disponível) ───────────────────
  Future<void> _abrirAlocacao(ExpositorFisico expositor) async {
    final todosClientes = ref.read(clientesListProvider).value ?? [];
    final clientes = todosClientes
        .where((cliente) => cliente.statusCadastro == StatusCadastro.aprovado)
        .toList();

    if (clientes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum cliente aprovado disponível.')),
      );
      return;
    }

    final cliente = await _selecionarCliente(context,
        titulo: 'Reservar para qual cliente?', clientes: clientes);
    if (cliente == null || cliente.id == null || !mounted) return;

    final usuario = ref.read(appUserProvider).value;
    if (usuario == null) return;

    setState(() => _processando = true);
    try {
      await ref.read(expositorFisicoRepositoryProvider).reservarParaCliente(
        expositorId: expositor.id!,
        clienteId: cliente.id!,
        usuarioId: usuario.uid,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Expositor reservado. Agora a instalação pode ser iniciada.',
            ),
          ),
        );
      }
    } catch (e, st) {
      debugPrint('Erro ao reservar expositor: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Não foi possível reservar. Tente novamente.')),
        );
      }
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  // ── Iniciar instalação real (status: reservado) ─────────────────
  Future<void> _abrirIniciarInstalacao(ExpositorFisico expositor) async {
    final clienteId = expositor.clienteReservadoId;

    if (clienteId == null || clienteId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Este expositor está reservado, mas não possui cliente vinculado.',
          ),
        ),
      );
      return;
    }

    setState(() => _processando = true);

    try {
      final cliente = await ref
          .read(clienteRepositoryProvider)
          .fetchById(clienteId);

      if (!mounted) return;

      if (cliente == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('O cliente da reserva não foi encontrado.'),
          ),
        );
        return;
      }

      if (cliente.statusCadastro != StatusCadastro.aprovado) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'O cliente precisa estar aprovado antes da instalação.',
            ),
          ),
        );
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => InstalacaoPage(
            cliente: cliente,
            expositorId: expositor.id!,
          ),
        ),
      );
    } catch (e, st) {
      debugPrint('Erro ao iniciar instalação: $e\n$st');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível iniciar a instalação. Tente novamente.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processando = false);
      }
    }
  }

  // ── Cancelar reserva (status: reservado) ─────────────────────────
  Future<void> _abrirCancelarReserva(ExpositorFisico expositor) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancelar reserva?'),
        content: Text(
            'O ${expositor.numero} volta a ficar disponível pra outro cliente. '
                'Isso não afeta o cadastro do cliente, só a reserva do expositor.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cancelar reserva'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;

    final usuario = ref.read(appUserProvider).value;
    if (usuario == null) return;

    setState(() => _processando = true);
    try {
      await ref.read(expositorFisicoRepositoryProvider).cancelarReserva(
        expositorId: expositor.id!,
        usuarioId: usuario.uid,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reserva cancelada.')),
        );
      }
    } catch (e, st) {
      debugPrint('Erro ao cancelar reserva: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Não foi possível cancelar a reserva. Tente novamente.')),
        );
      }
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  // ── Retirar do cliente (status: instalado) ──────────────────────
  Future<void> _abrirRetirada(ExpositorFisico expositor) async {
    // Se tem consignação ativa, o certo é passar pela conferência de
    // verdade (Termo de Retirada). O diálogo simples abaixo só cobre
    // o caso raro de inconsistência (instalado sem consignação).
    final consignmentAtiva = await ref
        .read(consignmentRepositoryProvider)
        .watchAtivaDoExpositor(expositor.id!)
        .first;

    if (consignmentAtiva != null && expositor.clienteAtualId != null) {
      final cliente = await ref
          .read(clienteRepositoryProvider)
          .fetchById(expositor.clienteAtualId!);
      if (cliente == null) return;
      if (!mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RetiradaConferenciaPage(
            cliente: cliente,
            consignmentAtiva: consignmentAtiva,
            expositor: expositor,
          ),
        ),
      );
      return;
    }

    await _abrirRetiradaSimples(expositor);
  }

  /// Fallback: retirada sem conferência, pra quando não existe
  /// consignação ativa vinculada (inconsistência de dados).
  Future<void> _abrirRetiradaSimples(ExpositorFisico expositor) async {
    DestinoRetirada destinoEscolhido = DestinoRetirada.estoque;
    final observacaoController = TextEditingController();
    String? erro;

    try {
      final confirmado = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setStateDialog) => AlertDialog(
            title: const Text('Retirar do cliente'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<DestinoRetirada>(
                  initialValue: destinoEscolhido,
                  decoration: const InputDecoration(labelText: 'Destino'),
                  items: const [
                    DropdownMenuItem(
                      value: DestinoRetirada.estoque,
                      child: Text('Voltar pro estoque (boas condições)'),
                    ),
                    DropdownMenuItem(
                      value: DestinoRetirada.recolhido,
                      child: Text('Recolhido — aguardando conferência'),
                    ),
                    DropdownMenuItem(
                      value: DestinoRetirada.manutencao,
                      child: Text('Enviar para manutenção'),
                    ),
                    DropdownMenuItem(
                      value: DestinoRetirada.descarte,
                      child: Text('Descartar'),
                    ),
                    DropdownMenuItem(
                      value: DestinoRetirada.perdido,
                      child: Text('Registrar como perdido'),
                    ),
                  ],
                  onChanged: (d) {
                    if (d != null) {
                      setStateDialog(() {
                        destinoEscolhido = d;
                        erro = null;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: observacaoController,
                  decoration: InputDecoration(
                    labelText: (destinoEscolhido == DestinoRetirada.descarte ||
                        destinoEscolhido == DestinoRetirada.perdido)
                        ? 'Observação (obrigatória nesse destino)'
                        : 'Observação (opcional)',
                  ),
                  maxLines: 2,
                  onChanged: (_) => setStateDialog(() => erro = null),
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
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  final precisaObservacao =
                      destinoEscolhido == DestinoRetirada.descarte ||
                          destinoEscolhido == DestinoRetirada.perdido;
                  if (precisaObservacao &&
                      observacaoController.text.trim().isEmpty) {
                    setStateDialog(() => erro =
                    'Informe o motivo — obrigatório em descarte/perda.');
                    return;
                  }
                  Navigator.of(dialogContext).pop(true);
                },
                child: const Text('Confirmar'),
              ),
            ],
          ),
        ),
      );

      if (confirmado != true) return;

      // Segunda confirmação só pra descarte — ação irreversível.
      if (destinoEscolhido == DestinoRetirada.descarte) {
        final confirmadoDeVerdade = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Descartar definitivamente?'),
            content: Text(
                'O expositor ${expositor.numero} será marcado como descartado. '
                    'Essa ação não pode ser desfeita.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                    backgroundColor:
                    Theme.of(context).colorScheme.errorContainer),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Descartar definitivamente'),
              ),
            ],
          ),
        );
        if (confirmadoDeVerdade != true) return;
      }

      if (!mounted) return;
      final usuario = ref.read(appUserProvider).value;
      if (usuario == null) return;

      setState(() => _processando = true);
      try {
        await ref.read(expositorFisicoRepositoryProvider).retirarDoCliente(
          expositorId: expositor.id!,
          destino: destinoEscolhido,
          usuarioId: usuario.uid,
          observacao: observacaoController.text.trim(),
        );

        // Corrige o gap: sem isso, a consignação vinculada a esse
        // expositor ficava "ativa pra sempre" mesmo depois de
        // retirado. Trata tudo que estava consignado como devolvido
        // — não há conferência aqui ainda (isso é trabalho futuro).
        final consignmentAtiva = await ref
            .read(consignmentRepositoryProvider)
            .watchAtivaDoExpositor(expositor.id!)
            .first;
        if (consignmentAtiva != null && consignmentAtiva.id != null) {
          await ref.read(consignmentRepositoryProvider).encerrarPorRetirada(
            consignmentAtivaId: consignmentAtiva.id!,
            observacao: 'Encerrada automaticamente na retirada do expositor.',
          );
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Expositor retirado do cliente.')),
          );
        }
      } catch (e, st) {
        debugPrint('Erro ao retirar expositor: $e\n$st');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Não foi possível retirar o expositor. Tente novamente.')),
          );
        }
      } finally {
        if (mounted) setState(() => _processando = false);
      }
    } finally {
      observacaoController.dispose();
    }
  }

  List<_AcaoStatusExpositor> _acoesStatusPermitidas(
      ExpositorFisico expositor,
      ) {
    return switch (expositor.status) {
      ExpositorStatus.disponivel => const [
        _AcaoStatusExpositor.manutencao,
        _AcaoStatusExpositor.perdido,
        _AcaoStatusExpositor.descarte,
      ],
      ExpositorStatus.recolhido => const [
        _AcaoStatusExpositor.manutencao,
        _AcaoStatusExpositor.perdido,
        _AcaoStatusExpositor.descarte,
      ],
      ExpositorStatus.manutencao => const [
        _AcaoStatusExpositor.perdido,
        _AcaoStatusExpositor.descarte,
      ],
      ExpositorStatus.reservado ||
      ExpositorStatus.instalado ||
      ExpositorStatus.descartado ||
      ExpositorStatus.perdido =>
      const [],
    };
  }

  String _acaoStatusLabel(_AcaoStatusExpositor acao) => switch (acao) {
    _AcaoStatusExpositor.manutencao => 'Enviar para manutenção',
    _AcaoStatusExpositor.perdido => 'Registrar como perdido',
    _AcaoStatusExpositor.descarte => 'Descartar expositor',
  };

  IconData _acaoStatusIcon(_AcaoStatusExpositor acao) => switch (acao) {
    _AcaoStatusExpositor.manutencao => Icons.build_outlined,
    _AcaoStatusExpositor.perdido => Icons.location_off_outlined,
    _AcaoStatusExpositor.descarte => Icons.delete_outline,
  };

  ExpositorStatus _acaoStatusDestino(_AcaoStatusExpositor acao) =>
      switch (acao) {
        _AcaoStatusExpositor.manutencao => ExpositorStatus.manutencao,
        _AcaoStatusExpositor.perdido => ExpositorStatus.perdido,
        _AcaoStatusExpositor.descarte => ExpositorStatus.descartado,
      };

  Future<void> _executarAcaoStatus(
      ExpositorFisico expositor,
      _AcaoStatusExpositor acao,
      ) async {
    final observacaoController = TextEditingController();
    String? erro;

    try {
      final confirmado = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setStateDialog) {
            final titulo = _acaoStatusLabel(acao);
            final mensagem = switch (acao) {
              _AcaoStatusExpositor.manutencao =>
              'O expositor será retirado do estoque disponível e ficará '
                  'marcado como em manutenção.',
              _AcaoStatusExpositor.perdido =>
              'O expositor será baixado da operação como perdido. '
                  'Use esta opção somente quando a localização não puder '
                  'ser confirmada.',
              _AcaoStatusExpositor.descarte =>
              'O expositor será baixado da operação como descartado. '
                  'Essa ação deve ser usada somente quando a unidade não '
                  'puder mais voltar à operação.',
            };

            return AlertDialog(
              icon: Icon(_acaoStatusIcon(acao)),
              title: Text(titulo),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(mensagem),
                    const SizedBox(height: 16),
                    TextField(
                      controller: observacaoController,
                      autofocus: true,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: acao == _AcaoStatusExpositor.manutencao
                            ? 'Motivo da manutenção'
                            : 'Motivo da baixa',
                        hintText: 'Obrigatório',
                        errorText: erro,
                        alignLabelWithHint: true,
                      ),
                      onChanged: (_) {
                        if (erro != null) {
                          setStateDialog(() => erro = null);
                        }
                      },
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
                  onPressed: () {
                    if (observacaoController.text.trim().isEmpty) {
                      setStateDialog(
                            () => erro = 'Informe o motivo desta alteração.',
                      );
                      return;
                    }

                    Navigator.of(dialogContext).pop(true);
                  },
                  child: Text(
                    acao == _AcaoStatusExpositor.manutencao
                        ? 'Enviar para manutenção'
                        : 'Confirmar',
                  ),
                ),
              ],
            );
          },
        ),
      );

      if (confirmado != true || !mounted) return;

      if (acao == _AcaoStatusExpositor.descarte) {
        final confirmouDescarte = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: Icon(
              Icons.warning_amber_rounded,
              color: Theme.of(context).colorScheme.error,
            ),
            title: const Text('Descartar definitivamente?'),
            content: Text(
              'O ${expositor.numero} será marcado como descartado. '
                  'Depois disso ele ficará somente para consulta no histórico.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Voltar'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Descartar definitivamente'),
              ),
            ],
          ),
        );

        if (confirmouDescarte != true || !mounted) return;
      }

      final usuario = ref.read(appUserProvider).value;
      if (usuario == null) return;

      setState(() => _processando = true);

      try {
        await ref
            .read(expositorFisicoRepositoryProvider)
            .alterarStatusAdministrativo(
          expositorId: expositor.id!,
          novoStatus: _acaoStatusDestino(acao),
          usuarioId: usuario.uid,
          observacao: observacaoController.text.trim(),
        );

        if (!mounted) return;

        ref.invalidate(expositorHistoricoProvider(expositor.id!));

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              switch (acao) {
                _AcaoStatusExpositor.manutencao =>
                'Expositor enviado para manutenção.',
                _AcaoStatusExpositor.perdido =>
                'Expositor registrado como perdido.',
                _AcaoStatusExpositor.descarte =>
                'Expositor registrado como descartado.',
              },
            ),
          ),
        );
      } catch (e, st) {
        debugPrint('Erro ao alterar status do expositor: $e\n$st');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Não foi possível alterar o status. Tente novamente.',
              ),
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _processando = false);
        }
      }
    } finally {
      observacaoController.dispose();
    }
  }

  Widget _menuAcoesStatus(
      ExpositorFisico expositor, {
        bool compacto = false,
      }) {
    final acoes = _acoesStatusPermitidas(expositor);

    if (acoes.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return PopupMenuButton<_AcaoStatusExpositor>(
      enabled: !_processando,
      tooltip: 'Mais ações',
      onSelected: (acao) => _executarAcaoStatus(expositor, acao),
      itemBuilder: (context) {
        return [
          for (final acao in acoes)
            PopupMenuItem<_AcaoStatusExpositor>(
              value: acao,
              child: Row(
                children: [
                  Icon(
                    _acaoStatusIcon(acao),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(_acaoStatusLabel(acao)),
                ],
              ),
            ),
        ];
      },
      child: Container(
        height: compacto ? 46 : 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          border: Border.all(
            color: theme.colorScheme.outline,
          ),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.more_horiz, size: 20),
            const SizedBox(width: 7),
            const Text('Mais ações'),
          ],
        ),
      ),
    );
  }

  // ── Transferir para outro cliente (status: instalado) ───────────
  Future<void> _abrirTransferencia(ExpositorFisico expositor) async {
    final consignmentAtiva = await ref
        .read(consignmentRepositoryProvider)
        .watchAtivaDoExpositor(expositor.id!)
        .first;

    if (!mounted) return;

    if (consignmentAtiva != null) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.lock_outline),
          title: const Text('Transferência bloqueada'),
          content: const Text(
            'Este expositor possui uma consignação ativa. '
                'Faça a retirada e a conferência final antes de transferir '
                'o expositor para outro cliente.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Entendi'),
            ),
          ],
        ),
      );
      return;
    }

    final clientes = ref.read(clientesListProvider).value ?? [];
    final outrosClientes =
    clientes.where((c) => c.id != expositor.clienteAtualId).toList();

    if (outrosClientes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Nenhum outro cliente disponível pra transferir.')),
      );
      return;
    }

    final novoCliente = await _selecionarCliente(context,
        titulo: 'Transferir para qual cliente?', clientes: outrosClientes);
    if (novoCliente == null || novoCliente.id == null || !mounted) return;

    final clienteAtual =
        clientes.where((c) => c.id == expositor.clienteAtualId).firstOrNull;
    final nomeAtual = clienteAtual != null
        ? (clienteAtual.nomeFantasia?.isNotEmpty == true
        ? clienteAtual.nomeFantasia!
        : clienteAtual.nome)
        : 'Cliente atual';
    final nomeNovo = novoCliente.nomeFantasia?.isNotEmpty == true
        ? novoCliente.nomeFantasia!
        : novoCliente.nome;

    final observacaoController = TextEditingController();
    bool confirmado = false;
    try {
      confirmado = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Confirmar transferência'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Expositor: ${expositor.numero}'),
              const SizedBox(height: 4),
              Text('De: $nomeAtual'),
              Text('Para: $nomeNovo'),
              const SizedBox(height: 12),
              TextField(
                controller: observacaoController,
                decoration: const InputDecoration(
                    labelText: 'Motivo / observação (opcional)'),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Confirmar transferência'),
            ),
          ],
        ),
      ) ??
          false;

      if (!confirmado || !mounted) return;

      final usuario = ref.read(appUserProvider).value;
      if (usuario == null) return;

      setState(() => _processando = true);
      try {
        await ref.read(expositorFisicoRepositoryProvider).transferirParaCliente(
          expositorId: expositor.id!,
          novoClienteId: novoCliente.id!,
          usuarioId: usuario.uid,
          observacao: observacaoController.text.trim(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Expositor transferido!')),
          );
        }
      } catch (e, st) {
        debugPrint('Erro ao transferir expositor: $e\n$st');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Não foi possível transferir o expositor. Tente novamente.')),
          );
        }
      } finally {
        if (mounted) setState(() => _processando = false);
      }
    } finally {
      observacaoController.dispose();
    }
  }

  // ── Finalizar manutenção (status: manutenção) ───────────────────
  Future<void> _abrirFinalizarManutencao(ExpositorFisico expositor) async {
    final observacaoController = TextEditingController();
    try {
      final confirmado = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Finalizar manutenção'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('O expositor volta pro estoque central como disponível.'),
              const SizedBox(height: 12),
              TextField(
                controller: observacaoController,
                decoration:
                const InputDecoration(labelText: 'Observação (opcional)'),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Finalizar'),
            ),
          ],
        ),
      );
      if (confirmado != true || !mounted) return;

      final usuario = ref.read(appUserProvider).value;
      if (usuario == null) return;

      setState(() => _processando = true);
      try {
        await ref.read(expositorFisicoRepositoryProvider).finalizarManutencao(
          expositorId: expositor.id!,
          usuarioId: usuario.uid,
          observacao: observacaoController.text.trim(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Manutenção finalizada!')),
          );
        }
      } catch (e, st) {
        debugPrint('Erro ao finalizar manutenção: $e\n$st');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                Text('Não foi possível finalizar. Tente novamente.')),
          );
        }
      } finally {
        if (mounted) setState(() => _processando = false);
      }
    } finally {
      observacaoController.dispose();
    }
  }

  // ── Conferir e disponibilizar (status: recolhido) ───────────────
  Future<void> _abrirConferencia(ExpositorFisico expositor) async {
    EstadoConservacao estadoEscolhido = expositor.estadoConservacao;
    final observacaoController = TextEditingController();
    try {
      final confirmado = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setStateDialog) => AlertDialog(
            title: const Text('Conferir e disponibilizar'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<EstadoConservacao>(
                  initialValue: estadoEscolhido,
                  decoration:
                  const InputDecoration(labelText: 'Estado de conservação'),
                  items: const [
                    DropdownMenuItem(
                        value: EstadoConservacao.novo, child: Text('Novo')),
                    DropdownMenuItem(
                        value: EstadoConservacao.bom, child: Text('Bom')),
                    DropdownMenuItem(
                        value: EstadoConservacao.regular,
                        child: Text('Regular')),
                    DropdownMenuItem(
                        value: EstadoConservacao.ruim, child: Text('Ruim')),
                  ],
                  onChanged: (v) {
                    if (v != null) setStateDialog(() => estadoEscolhido = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: observacaoController,
                  decoration:
                  const InputDecoration(labelText: 'Observação (opcional)'),
                  maxLines: 2,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Disponibilizar'),
              ),
            ],
          ),
        ),
      );
      if (confirmado != true || !mounted) return;

      final usuario = ref.read(appUserProvider).value;
      if (usuario == null) return;

      setState(() => _processando = true);
      try {
        await ref
            .read(expositorFisicoRepositoryProvider)
            .confirmarDisponibilidadeAposConferencia(
          expositorId: expositor.id!,
          usuarioId: usuario.uid,
          estadoConservacao: estadoEscolhido,
          observacao: observacaoController.text.trim(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Expositor disponibilizado!')),
          );
        }
      } catch (e, st) {
        debugPrint('Erro ao conferir expositor: $e\n$st');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Não foi possível confirmar a conferência. Tente novamente.')),
          );
        }
      } finally {
        if (mounted) setState(() => _processando = false);
      }
    } finally {
      observacaoController.dispose();
    }
  }

  /// Ação principal conforme o status — item 7 da lista de melhorias.
  (String, VoidCallback?)? _acaoPrincipal(ExpositorFisico expositor) {
    if (_processando) return null;
    return switch (expositor.status) {
      ExpositorStatus.disponivel => (
      'Reservar para cliente',
          () => _abrirAlocacao(expositor),
      ),
      ExpositorStatus.reservado => (
      'Iniciar instalação',
          () => _abrirIniciarInstalacao(expositor),
      ),
      ExpositorStatus.manutencao => (
      'Finalizar manutenção',
          () => _abrirFinalizarManutencao(expositor),
      ),
      ExpositorStatus.recolhido => (
      'Conferir e disponibilizar',
          () => _abrirConferencia(expositor),
      ),
      ExpositorStatus.instalado ||
      ExpositorStatus.descartado ||
      ExpositorStatus.perdido =>
      null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final expositorAsync = ref.watch(expositorFisicoByIdProvider(widget.expositorId));
    final isDesktop = MediaQuery.sizeOf(context).width >= _kDesktopBreakpoint;

    return expositorAsync.when(
      data: (expositor) {
        if (expositor == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Detalhes do Expositor')),
            body: const Center(child: Text('Expositor não encontrado.')),
          );
        }

        final acao = _acaoPrincipal(expositor);
        final acoesStatus = _acoesStatusPermitidas(expositor);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Detalhes do Expositor'),
            actions: isDesktop && (acao != null || acoesStatus.isNotEmpty)
                ? [
              if (acao != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilledButton.icon(
                    onPressed: acao.$2,
                    icon: _processando
                        ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                        : const Icon(Icons.arrow_forward),
                    label: Text(acao.$1),
                  ),
                ),
              if (acoesStatus.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: _menuAcoesStatus(expositor),
                ),
            ]
                : null,
          ),
          bottomNavigationBar:
          !isDesktop && (acao != null || acoesStatus.isNotEmpty)
              ? SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (acao != null)
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: FilledButton(
                          onPressed: acao.$2,
                          child: _processando
                              ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                              : Text(acao.$1),
                        ),
                      ),
                    ),
                  if (acao != null && acoesStatus.isNotEmpty)
                    const SizedBox(width: 10),
                  if (acoesStatus.isNotEmpty)
                    _menuAcoesStatus(
                      expositor,
                      compacto: true,
                    ),
                ],
              ),
            ),
          )
              : null,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ResponsiveCenter(
              maxWidth: isDesktop ? 1100 : 560,
              child: _buildConteudo(context, expositor, isDesktop),
            ),
          ),
        );
      },
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Detalhes do Expositor')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) {
        debugPrint('Erro ao carregar expositor: $e\n$st');
        return Scaffold(
          appBar: AppBar(title: const Text('Detalhes do Expositor')),
          body: ErroCarregamento(
            mensagem: 'Não foi possível carregar o expositor.',
            onTentarNovamente: () =>
                ref.invalidate(expositorFisicoByIdProvider(widget.expositorId)),
          ),
        );
      },
    );
  }

  Widget _buildConteudo(
      BuildContext context, ExpositorFisico expositor, bool isDesktop) {
    final colunaEsquerda = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CardIdentificacao(expositor: expositor, onCopiar: _copiar),
        const SizedBox(height: 16),
        _CardLocalizacao(expositor: expositor),
      ],
    );

    final colunaDireita = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (expositor.status == ExpositorStatus.reservado &&
            expositor.clienteReservadoId != null)
          _ClienteReservado(clienteId: expositor.clienteReservadoId!)
        else if (expositor.clienteAtualId != null)
          _DetalhesDoCliente(
            clienteId: expositor.clienteAtualId!,
            expositorId: expositor.id!,
          )
        else
          const _SectionCard(
            titulo: 'Cliente atual',
            child: Text(
              'Nenhum cliente vinculado no momento.',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        if (expositor.status == ExpositorStatus.reservado) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.bookmark_remove_outlined),
            label: const Text('Cancelar reserva'),
            onPressed: _processando
                ? null
                : () => _abrirCancelarReserva(expositor),
          ),
        ],
        if (expositor.status == ExpositorStatus.instalado) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.remove_circle_outline),
                label: const Text('Retirar do cliente'),
                onPressed:
                _processando ? null : () => _abrirRetirada(expositor),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Transferir para outro cliente'),
                onPressed:
                _processando ? null : () => _abrirTransferencia(expositor),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        _SectionCard(
          titulo: 'Histórico',
          child: _Historico(expositorId: expositor.id!),
        ),
      ],
    );

    final conteudo = isDesktop
        ? Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: colunaEsquerda),
        const SizedBox(width: 24),
        Expanded(flex: 3, child: colunaDireita),
      ],
    )
        : Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        colunaEsquerda,
        const SizedBox(height: 16),
        colunaDireita,
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CabecalhoOperacional(expositor: expositor),
        const SizedBox(height: 16),
        conteudo,
      ],
    );
  }
}

class _CabecalhoOperacional extends ConsumerWidget {
  final ExpositorFisico expositor;

  const _CabecalhoOperacional({
    required this.expositor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final clientes = ref.watch(clientesListProvider).value ??
        const <Cliente>[];

    final clienteId = expositor.status == ExpositorStatus.reservado
        ? expositor.clienteReservadoId
        : expositor.clienteAtualId;

    Cliente? cliente;
    if (clienteId != null) {
      for (final item in clientes) {
        if (item.id == clienteId) {
          cliente = item;
          break;
        }
      }
    }

    final consignment = expositor.status == ExpositorStatus.instalado
        ? ref.watch(
      consignmentAtivaDoExpositorProvider(expositor.id!),
    ).value
        : null;

    final quantidadeSkus = consignment?.itens.length ?? 0;
    final quantidadeUnidades = consignment?.itens.fold<int>(
      0,
          (total, item) => total + item.quantidade,
    ) ??
        0;

    final nomeCliente = cliente == null
        ? null
        : (cliente.nomeFantasia?.trim().isNotEmpty == true
        ? cliente.nomeFantasia!.trim()
        : cliente.nome);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compacto = constraints.maxWidth < 680;

            final identidade = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: compacto ? 24 : 28,
                  backgroundColor: colorScheme.primaryContainer,
                  foregroundColor: colorScheme.onPrimaryContainer,
                  child: const Icon(Icons.view_in_ar_outlined),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        expositor.numero,
                        style:
                        Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        expositor.modeloNome,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (nomeCliente != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          nomeCliente,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                          Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                StatusChip(status: expositor.status),
              ],
            );

            final resumo = Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (consignment != null)
                  _ResumoOperacional(
                    icon: Icons.category_outlined,
                    label: 'SKUs',
                    value: '$quantidadeSkus',
                  ),
                if (consignment != null)
                  _ResumoOperacional(
                    icon: Icons.inventory_2_outlined,
                    label: 'Unidades',
                    value: '$quantidadeUnidades',
                  ),
                if (consignment != null)
                  _ResumoOperacional(
                    icon: Icons.sell_outlined,
                    label: 'Venda total',
                    value: _formatoMoeda.format(
                      consignment.valorVendaTotalCentavos / 100,
                    ),
                  ),
              ],
            );

            if (compacto || consignment == null) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  identidade,
                  if (consignment != null) ...[
                    const SizedBox(height: 16),
                    resumo,
                  ],
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 3, child: identidade),
                const SizedBox(width: 24),
                Flexible(flex: 2, child: resumo),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ResumoOperacional extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ResumoOperacional({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(minWidth: 108),
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 9,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 18,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Card padrão usado em toda a tela — título + conteúdo.
class _SectionCard extends StatelessWidget {
  final String titulo;
  final Widget child;
  const _SectionCard({required this.titulo, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _CardIdentificacao extends StatelessWidget {
  final ExpositorFisico expositor;
  final void Function(String texto, String rotulo) onCopiar;
  const _CardIdentificacao({required this.expositor, required this.onCopiar});

  String _conservacaoLabel(EstadoConservacao c) => switch (c) {
    EstadoConservacao.novo => 'Novo',
    EstadoConservacao.bom => 'Bom',
    EstadoConservacao.regular => 'Regular',
    EstadoConservacao.ruim => 'Ruim',
  };

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      titulo: 'Identificação',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(expositor.numero,
                    style: Theme.of(context).textTheme.headlineSmall),
              ),
              IconButton(
                tooltip: 'Copiar patrimônio',
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () => onCopiar(expositor.numero, 'Patrimônio'),
              ),
              StatusChip(status: expositor.status),
            ],
          ),
          Text(expositor.modeloNome,
              style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          _InfoRow(
              label: 'Estado de conservação',
              value: _conservacaoLabel(expositor.estadoConservacao)),
          if (expositor.numeroSerieFabricante != null &&
              expositor.numeroSerieFabricante!.isNotEmpty)
            _InfoRow(
              label: 'Nº de série',
              value: expositor.numeroSerieFabricante!,
              trailing: IconButton(
                tooltip: 'Copiar nº de série',
                icon: const Icon(Icons.copy, size: 16),
                onPressed: () => onCopiar(
                    expositor.numeroSerieFabricante!, 'Número de série'),
              ),
            ),
          _InfoRow(
            label: 'Instalado desde',
            value: expositor.dataInstalacao != null
                ? DateFormat('dd/MM/yyyy').format(expositor.dataInstalacao!)
                : '—',
          ),
          if (expositor.observacoes != null &&
              expositor.observacoes!.isNotEmpty)
            _InfoRow(label: 'Observações', value: expositor.observacoes!),
        ],
      ),
    );
  }
}

class _CardLocalizacao extends StatelessWidget {
  final ExpositorFisico expositor;
  const _CardLocalizacao({required this.expositor});

  @override
  Widget build(BuildContext context) {
    final texto = switch (expositor.status) {
      ExpositorStatus.instalado => 'Com o cliente',
      ExpositorStatus.reservado => 'Estoque central (reservado)',
      ExpositorStatus.recolhido => 'Estoque central (recolhido)',
      ExpositorStatus.manutencao => 'Em manutenção',
      ExpositorStatus.descartado => 'Baixado / descartado',
      ExpositorStatus.perdido => 'Localização não confirmada (perdido)',
      ExpositorStatus.disponivel => 'Estoque central',
    };
    return _SectionCard(
      titulo: 'Localização',
      child: Text(texto),
    );
  }
}

/// Mostra pra quem o expositor está reservado, sem os detalhes de
/// consignação/mercadoria (ainda não existe consignação — a unidade
/// nem foi instalada de verdade).
class _ClienteReservado extends ConsumerWidget {
  final String clienteId;
  const _ClienteReservado({required this.clienteId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clienteAsync = ref.watch(clienteByIdProvider(clienteId));

    return _SectionCard(
      titulo: 'Reservado para',
      child: clienteAsync.when(
        data: (cliente) => cliente == null
            ? const Text('Cliente não encontrado.')
            : InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ClienteDetailPage(clienteId: cliente.id!),
              ),
            );
          },
          child: Row(
            children: [
              Expanded(
                child: Text(
                  cliente.nomeFantasia?.isNotEmpty == true
                      ? cliente.nomeFantasia!
                      : cliente.nome,
                ),
              ),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
        loading: () => const LinearProgressIndicator(),
        error: (e, st) {
          debugPrint('Erro ao carregar cliente da reserva: $e\n$st');
          return const Text('Não foi possível carregar o cliente.',
              style: TextStyle(color: Colors.grey));
        },
      ),
    );
  }
}

/// Busca o cliente e a consignação ativa DESSE expositor específico —
/// mostra onde o expositor está e o que tem consignado nele agora.
/// Usa consignmentAtivaDoExpositorProvider (não o por clienteId), pra
/// não misturar consignações quando o mesmo cliente tem mais de um
/// expositor instalado.
class _DetalhesDoCliente extends ConsumerWidget {
  final String clienteId;
  final String expositorId;
  const _DetalhesDoCliente(
      {required this.clienteId, required this.expositorId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clienteAsync = ref.watch(clienteByIdProvider(clienteId));
    final consignmentAsync =
    ref.watch(consignmentAtivaDoExpositorProvider(expositorId));

    return _SectionCard(
      titulo: 'Cliente atual',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          clienteAsync.when(
            data: (cliente) => cliente == null
                ? const Text('Cliente não encontrado.')
                : InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ClienteDetailPage(clienteId: cliente.id!),
                  ),
                );
              },
              child: Row(
                children: [
                  Expanded(
                    child: _InfoRow(
                      label: 'Nome',
                      value: cliente.nomeFantasia?.isNotEmpty == true
                          ? cliente.nomeFantasia!
                          : cliente.nome,
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
            ),
            loading: () => const LinearProgressIndicator(),
            error: (e, st) {
              debugPrint('Erro ao carregar cliente do expositor: $e\n$st');
              return const Text('Não foi possível carregar o cliente.',
                  style: TextStyle(color: Colors.grey));
            },
          ),
          const Divider(height: 24),
          Text('Mercadoria consignada agora',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          consignmentAsync.when(
            data: (consignment) {
              if (consignment == null || consignment.itens.isEmpty) {
                return const Text('Nenhuma mercadoria consignada no momento.',
                    style: TextStyle(color: Colors.grey));
              }
              return _MercadoriaConsignada(
                consignment: consignment,
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (e, st) {
              debugPrint('Erro ao carregar consignação do expositor: $e\n$st');
              return const Text('Não foi possível carregar a consignação.',
                  style: TextStyle(color: Colors.grey));
            },
          ),
        ],
      ),
    );
  }
}

class _MercadoriaConsignada extends StatefulWidget {
  final Consignment consignment;

  const _MercadoriaConsignada({
    required this.consignment,
  });

  @override
  State<_MercadoriaConsignada> createState() =>
      _MercadoriaConsignadaState();
}

class _MercadoriaConsignadaState extends State<_MercadoriaConsignada> {
  bool _mostrarTodos = false;

  int get _quantidadeSkus => widget.consignment.itens.length;

  int get _quantidadeUnidades => widget.consignment.itens.fold<int>(
    0,
        (total, item) => total + item.quantidade,
  );

  @override
  Widget build(BuildContext context) {
    final itens = widget.consignment.itens;
    final itensExibidos =
    _mostrarTodos ? itens : itens.take(8).toList();
    final temMais = itens.length > 8;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _ResumoOperacional(
              icon: Icons.category_outlined,
              label: 'SKUs',
              value: '$_quantidadeSkus',
            ),
            _ResumoOperacional(
              icon: Icons.inventory_2_outlined,
              label: 'Unidades',
              value: '$_quantidadeUnidades',
            ),
            _ResumoOperacional(
              icon: Icons.sell_outlined,
              label: 'Venda total',
              value: _formatoMoeda.format(
                widget.consignment.valorVendaTotalCentavos / 100,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 700;

            if (!isWide) {
              return Column(
                children: [
                  for (var index = 0;
                  index < itensExibidos.length;
                  index++) ...[
                    _MercadoriaMobileRow(
                      item: itensExibidos[index],
                    ),
                    if (index != itensExibidos.length - 1)
                      const Divider(height: 1),
                  ],
                ],
              );
            }

            return Column(
              children: [
                const _MercadoriaTableHeader(),
                const Divider(height: 1),
                for (var index = 0;
                index < itensExibidos.length;
                index++) ...[
                  _MercadoriaTableRow(
                    item: itensExibidos[index],
                  ),
                  if (index != itensExibidos.length - 1)
                    const Divider(height: 1),
                ],
              ],
            );
          },
        ),
        if (temMais) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.center,
            child: TextButton.icon(
              onPressed: () {
                setState(() {
                  _mostrarTodos = !_mostrarTodos;
                });
              },
              icon: Icon(
                _mostrarTodos
                    ? Icons.expand_less
                    : Icons.expand_more,
              ),
              label: Text(
                _mostrarTodos
                    ? 'Mostrar menos'
                    : 'Ver todos os $_quantidadeSkus produtos',
              ),
            ),
          ),
        ],
        const Divider(height: 24),
        _InfoRow(
          label: 'Valor de venda total',
          value: _formatoMoeda.format(
            widget.consignment.valorVendaTotalCentavos / 100,
          ),
        ),
        _InfoRow(
          label: 'Valor líquido NEXT GEAR',
          value: _formatoMoeda.format(
            widget.consignment.valorLiquidoTotalCentavos / 100,
          ),
        ),
      ],
    );
  }
}

class _MercadoriaMobileRow extends StatelessWidget {
  final ConsignmentItem item;

  const _MercadoriaMobileRow({
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            item.descricaoSnapshot,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 12,
            runSpacing: 5,
            children: [
              Text(
                '${item.quantidade} un.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                'Unit. ${_formatoMoeda.format(item.precoVendaCentavos / 100)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                'Total ${_formatoMoeda.format(item.valorVendaTotalCentavos / 100)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MercadoriaTableHeader extends StatelessWidget {
  const _MercadoriaTableHeader();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(flex: 5, child: Text('Produto', style: style)),
          SizedBox(
            width: 70,
            child: Text(
              'Qtd.',
              textAlign: TextAlign.center,
              style: style,
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              'Unitário',
              textAlign: TextAlign.right,
              style: style,
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              'Total',
              textAlign: TextAlign.right,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

class _MercadoriaTableRow extends StatelessWidget {
  final ConsignmentItem item;

  const _MercadoriaTableRow({
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              item.descricaoSnapshot,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              '${item.quantidade}',
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              _formatoMoeda.format(
                item.precoVendaCentavos / 100,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              _formatoMoeda.format(
                item.valorVendaTotalCentavos / 100,
              ),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Widget? trailing;
  const _InfoRow({required this.label, required this.value, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 160,
              child: Text(label, style: const TextStyle(color: Colors.grey))),
          Expanded(child: Text(value)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Linha do tempo do expositor — cadastro, instalação, retirada,
/// manutenção etc, do mais recente pro mais antigo.
class _Historico extends ConsumerWidget {
  final String expositorId;

  const _Historico({
    required this.expositorId,
  });

  String _tipoLabel(TipoMovimentacaoExpositor tipo) => switch (tipo) {
    TipoMovimentacaoExpositor.cadastro => 'Cadastrado',
    TipoMovimentacaoExpositor.instalacao => 'Instalado',
    TipoMovimentacaoExpositor.retirada => 'Retirado',
    TipoMovimentacaoExpositor.transferencia => 'Transferido',
    TipoMovimentacaoExpositor.manutencaoEntrada => 'Enviado à manutenção',
    TipoMovimentacaoExpositor.manutencaoSaida => 'Saiu da manutenção',
    TipoMovimentacaoExpositor.descarte => 'Descartado',
    TipoMovimentacaoExpositor.perda => 'Registrado como perdido',
    TipoMovimentacaoExpositor.conferencia => 'Conferido e disponibilizado',
    TipoMovimentacaoExpositor.reserva => 'Reservado',
    TipoMovimentacaoExpositor.cancelamentoReserva => 'Reserva cancelada',
  };

  IconData _tipoIcone(TipoMovimentacaoExpositor tipo) => switch (tipo) {
    TipoMovimentacaoExpositor.cadastro => Icons.add_circle_outline,
    TipoMovimentacaoExpositor.instalacao => Icons.store_outlined,
    TipoMovimentacaoExpositor.retirada => Icons.remove_circle_outline,
    TipoMovimentacaoExpositor.transferencia => Icons.swap_horiz,
    TipoMovimentacaoExpositor.manutencaoEntrada => Icons.build_outlined,
    TipoMovimentacaoExpositor.manutencaoSaida =>
    Icons.build_circle_outlined,
    TipoMovimentacaoExpositor.descarte => Icons.delete_outline,
    TipoMovimentacaoExpositor.perda => Icons.help_outline,
    TipoMovimentacaoExpositor.conferencia => Icons.fact_check_outlined,
    TipoMovimentacaoExpositor.reserva => Icons.bookmark_outline,
    TipoMovimentacaoExpositor.cancelamentoReserva =>
    Icons.bookmark_remove_outlined,
  };

  String _nomeCliente(
      String? id,
      Map<String, String> nomes,
      ) {
    if (id == null || id.isEmpty) return '—';
    return nomes[id] ?? 'Cliente não localizado';
  }

  String _localLabel(
      String? local,
      Map<String, String> clientes,
      ) {
    if (local == null || local.trim().isEmpty) return '—';

    if (local == LocalExpositor.central) {
      return 'Estoque central';
    }

    if (local == LocalExpositor.manutencao) {
      return 'Manutenção';
    }

    final clienteId = LocalExpositor.extrairClienteId(local);

    if (clienteId != null) {
      return clientes[clienteId] ?? 'Cliente não localizado';
    }

    return local;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historicoAsync =
    ref.watch(expositorHistoricoProvider(expositorId));
    final clientes = ref.watch(clientesListProvider).value ??
        const <Cliente>[];
    final usuarios = ref.watch(usuariosListProvider).value ?? const [];

    final clientePorId = <String, String>{
      for (final cliente in clientes)
        if (cliente.id != null)
          cliente.id!: cliente.nomeFantasia?.trim().isNotEmpty == true
              ? cliente.nomeFantasia!.trim()
              : cliente.nome,
    };

    final usuarioPorId = <String, String>{
      for (final usuario in usuarios) usuario.uid: usuario.nome,
    };

    return historicoAsync.when(
      data: (eventos) {
        if (eventos.isEmpty) {
          return const Text(
            'Nenhum evento registrado ainda.',
            style: TextStyle(color: Colors.grey),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < eventos.length; index++) ...[
              _HistoricoEvento(
                evento: eventos[index],
                titulo: _tipoLabel(eventos[index].tipo),
                icon: _tipoIcone(eventos[index].tipo),
                usuario: usuarioPorId[eventos[index].usuarioId] ??
                    'Usuário não localizado',
                clienteAnterior: _nomeCliente(
                  eventos[index].clienteAnteriorId,
                  clientePorId,
                ),
                clienteNovo: _nomeCliente(
                  eventos[index].clienteNovoId,
                  clientePorId,
                ),
                origem: _localLabel(
                  eventos[index].origem,
                  clientePorId,
                ),
                destino: _localLabel(
                  eventos[index].destino,
                  clientePorId,
                ),
              ),
              if (index != eventos.length - 1)
                const Divider(height: 20),
            ],
          ],
        );
      },
      loading: () => const LinearProgressIndicator(),
      error: (e, st) {
        debugPrint('Erro ao carregar histórico do expositor: $e\n$st');

        return const Text(
          'Não foi possível carregar o histórico.',
          style: TextStyle(color: Colors.grey),
        );
      },
    );
  }
}

class _HistoricoEvento extends StatelessWidget {
  final ExpositorMovimentacao evento;
  final String titulo;
  final IconData icon;
  final String usuario;
  final String clienteAnterior;
  final String clienteNovo;
  final String origem;
  final String destino;

  const _HistoricoEvento({
    required this.evento,
    required this.titulo,
    required this.icon,
    required this.usuario,
    required this.clienteAnterior,
    required this.clienteNovo,
    required this.origem,
    required this.destino,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final data = evento.timestamp == null
        ? 'Data não informada'
        : DateFormat('dd/MM/yyyy HH:mm').format(evento.timestamp!);

    final mudouCliente = evento.clienteAnteriorId != null ||
        evento.clienteNovoId != null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: .55),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 18,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$data · $usuario',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (mudouCliente) ...[
                const SizedBox(height: 5),
                Text(
                  '$clienteAnterior → $clienteNovo',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ] else if (origem != '—' || destino != '—') ...[
                const SizedBox(height: 5),
                Text(
                  '$origem → $destino',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (evento.observacao?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 5),
                Text(
                  evento.observacao!.trim(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
