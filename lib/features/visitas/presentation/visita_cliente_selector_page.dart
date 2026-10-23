import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../clientes/domain/cliente.dart';
import '../../clientes/presentation/cliente_providers.dart';
import '../../consignacoes/domain/consignment.dart';
import '../../consignacoes/presentation/consignment_providers.dart';
import '../../expositores/domain/expositor_fisico.dart';
import '../../expositores/presentation/expositor_providers.dart';
import '../data/visita_repository.dart';
import '../domain/visita.dart';
import 'instalacao_page.dart';
import 'visita_execucao_page.dart';
import 'visita_providers.dart';

enum _AgendaFiltro {
  todas,
  atrasadas,
  hoje,
  estaSemana,
  proximas,
  semData,
}

enum _SituacaoAgenda {
  emAndamento,
  atrasada,
  hoje,
  estaSemana,
  futura,
  semData,
}

enum _AcaoConfirmacaoInicio {
  alterarData,
  iniciar,
}

final _consignacoesAtivasAgendaProvider =
StreamProvider.family<List<Consignment>, String>((ref, clienteId) {
  return ref
      .watch(consignmentRepositoryProvider)
      .watchTodasAtivasDoCliente(clienteId);
});

class VisitaClienteSelectorPage extends ConsumerStatefulWidget {
  const VisitaClienteSelectorPage({super.key, this.clienteIdInicial});

  /// Quando informado, a tela abre mostrando apenas este cliente
  /// (quando elegível na agenda, em andamento e realizadas). O usuário pode remover o foco.
  final String? clienteIdInicial;

  @override
  ConsumerState<VisitaClienteSelectorPage> createState() =>
      _VisitaClienteSelectorPageState();
}

class _VisitaClienteSelectorPageState
    extends ConsumerState<VisitaClienteSelectorPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _pesquisaController = TextEditingController();

  late final TabController _tabController;

  String _pesquisa = '';
  String? _clienteCarregandoId;
  String? _visitaCancelandoId;
  String? _clienteFocoId;
  _AgendaFiltro _filtro = _AgendaFiltro.todas;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    final inicial = widget.clienteIdInicial?.trim();
    _clienteFocoId = (inicial == null || inicial.isEmpty) ? null : inicial;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pesquisaController.dispose();
    super.dispose();
  }

  DateTime _somenteData(DateTime data) {
    return DateTime(data.year, data.month, data.day);
  }

  DateTime get _hoje => _somenteData(DateTime.now());

  DateTime get _inicioSemana {
    return _hoje.subtract(Duration(days: _hoje.weekday - DateTime.monday));
  }

  DateTime get _fimSemana {
    return _inicioSemana.add(const Duration(days: 6));
  }

  bool _mesmoDia(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatarData(DateTime? data) {
    if (data == null) return 'Sem data';
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    return '$dia/$mes/${data.year}';
  }

  String _formatarDataHora(DateTime? data) {
    if (data == null) return 'Horário não registrado';
    final hora = data.hour.toString().padLeft(2, '0');
    final minuto = data.minute.toString().padLeft(2, '0');
    return '${_formatarData(data)} às $hora:$minuto';
  }

  String _nomeCliente(Cliente cliente) {
    final nomeFantasia = cliente.nomeFantasia?.trim();

    if (nomeFantasia != null && nomeFantasia.isNotEmpty) {
      return nomeFantasia;
    }

    return cliente.nome.trim();
  }

  /// Comparação direta com o enum. A versão anterior usava
  /// toString().contains('aprovado'), que também aceitava "reprovado".
  bool _clienteAprovado(Cliente cliente) {
    return cliente.statusCadastro == StatusCadastro.aprovado;
  }

  bool _clientePodeEntrarNaAgenda(
      Cliente cliente, {
        required bool temConsignacaoAtiva,
      }) {
    if (!_clienteAprovado(cliente)) return false;

    switch (cliente.statusOperacional) {
      case StatusOperacional.aguardandoInstalacao:
        final expositorId =
        cliente.expositorFisicoSelecionadoId?.trim();
        return expositorId != null && expositorId.isNotEmpty;

      case StatusOperacional.ativo:
      // Cliente ativo só aparece se ainda existir pelo menos uma
      // consignação ativa. Isso evita que um cliente recém-retirado
      // continue aparecendo como se pudesse iniciar nova visita.
        return temConsignacaoAtiva;

      case StatusOperacional.pendente:
      case StatusOperacional.suspenso:
      case StatusOperacional.encerrado:
        return false;
    }
  }

  bool _correspondeFoco(String? clienteId) {
    return _clienteFocoId == null || clienteId == _clienteFocoId;
  }

  void _limparFoco() {
    setState(() => _clienteFocoId = null);
  }

  bool _correspondePesquisa(Cliente cliente) {
    final termo = _normalizar(_pesquisa);
    if (termo.isEmpty) return true;

    final termoNumerico = _pesquisa.replaceAll(RegExp(r'\D'), '');
    final documentoNumerico = cliente.cpfCnpj.replaceAll(RegExp(r'\D'), '');

    return _normalizar(_nomeCliente(cliente)).contains(termo) ||
        _normalizar(cliente.nome).contains(termo) ||
        _normalizar(cliente.cpfCnpj).contains(termo) ||
        _normalizar(cliente.enderecoResumo).contains(termo) ||
        (termoNumerico.isNotEmpty &&
            documentoNumerico.contains(termoNumerico));
  }

  String _formatarCpfCnpj(String valor) {
    final numeros = valor.replaceAll(RegExp(r'\D'), '');

    if (numeros.length == 11) {
      return '${numeros.substring(0, 3)}.'
          '${numeros.substring(3, 6)}.'
          '${numeros.substring(6, 9)}-'
          '${numeros.substring(9, 11)}';
    }

    if (numeros.length == 14) {
      return '${numeros.substring(0, 2)}.'
          '${numeros.substring(2, 5)}.'
          '${numeros.substring(5, 8)}/'
          '${numeros.substring(8, 12)}-'
          '${numeros.substring(12, 14)}';
    }

    return valor;
  }

  String _iniciais(String nome) {
    final partes = nome
        .trim()
        .split(RegExp(r'\s+'))
        .where((parte) => parte.isNotEmpty)
        .toList();

    if (partes.isEmpty) return '?';
    if (partes.length == 1) {
      return partes.first.substring(0, 1).toUpperCase();
    }

    return '${partes.first.substring(0, 1)}'
        '${partes.last.substring(0, 1)}'
        .toUpperCase();
  }

  _SituacaoAgenda _situacaoDoCliente(
      Cliente cliente,
      Visita? visitaEmAndamento,
      ) {
    if (visitaEmAndamento != null) {
      return _SituacaoAgenda.emAndamento;
    }

    final data = cliente.proximaVisitaEm;
    if (data == null) return _SituacaoAgenda.semData;

    final prevista = _somenteData(data);
    if (prevista.isBefore(_hoje)) return _SituacaoAgenda.atrasada;
    if (_mesmoDia(prevista, _hoje)) return _SituacaoAgenda.hoje;

    if (!prevista.isBefore(_inicioSemana) && !prevista.isAfter(_fimSemana)) {
      return _SituacaoAgenda.estaSemana;
    }

    return _SituacaoAgenda.futura;
  }

  String _textoSituacao(
      Cliente cliente,
      Visita? visitaEmAndamento,
      ) {
    final situacao = _situacaoDoCliente(cliente, visitaEmAndamento);
    final prevista = cliente.proximaVisitaEm;

    switch (situacao) {
      case _SituacaoAgenda.emAndamento:
        return 'Visita em andamento';
      case _SituacaoAgenda.atrasada:
        final dias = _hoje.difference(_somenteData(prevista!)).inDays;
        return dias == 1 ? 'Atrasada há 1 dia' : 'Atrasada há $dias dias';
      case _SituacaoAgenda.hoje:
        return 'Prevista para hoje';
      case _SituacaoAgenda.estaSemana:
        final amanha = _hoje.add(const Duration(days: 1));
        if (_mesmoDia(prevista!, amanha)) return 'Prevista para amanhã';
        return 'Esta semana · ${_formatarData(prevista)}';
      case _SituacaoAgenda.futura:
        return 'Próxima visita · ${_formatarData(prevista)}';
      case _SituacaoAgenda.semData:
        return 'Sem agendamento';
    }
  }

  bool _correspondeFiltro(Cliente cliente, Visita? visitaEmAndamento) {
    final situacao = _situacaoDoCliente(cliente, visitaEmAndamento);

    return switch (_filtro) {
      _AgendaFiltro.todas => true,
      _AgendaFiltro.atrasadas => situacao == _SituacaoAgenda.atrasada,
      _AgendaFiltro.hoje => situacao == _SituacaoAgenda.hoje,
      _AgendaFiltro.estaSemana => situacao == _SituacaoAgenda.hoje ||
          situacao == _SituacaoAgenda.estaSemana,
      _AgendaFiltro.proximas => situacao == _SituacaoAgenda.futura,
      _AgendaFiltro.semData => situacao == _SituacaoAgenda.semData,
    };
  }

  int _prioridade(Cliente cliente, Visita? visitaEmAndamento) {
    return switch (_situacaoDoCliente(cliente, visitaEmAndamento)) {
      _SituacaoAgenda.emAndamento => 0,
      _SituacaoAgenda.atrasada => 1,
      _SituacaoAgenda.hoje => 2,
      _SituacaoAgenda.estaSemana => 3,
      _SituacaoAgenda.futura => 4,
      _SituacaoAgenda.semData => 5,
    };
  }

  void _ordenarAgenda(
      List<Cliente> clientes,
      Map<String, Visita> visitasPorCliente,
      ) {
    clientes.sort((a, b) {
      final prioridadeA = _prioridade(a, visitasPorCliente[a.id]);
      final prioridadeB = _prioridade(b, visitasPorCliente[b.id]);

      if (prioridadeA != prioridadeB) {
        return prioridadeA.compareTo(prioridadeB);
      }

      final dataA = a.proximaVisitaEm;
      final dataB = b.proximaVisitaEm;
      if (dataA != null && dataB != null) {
        final comparacaoData = dataA.compareTo(dataB);
        if (comparacaoData != 0) return comparacaoData;
      }

      return _normalizar(_nomeCliente(a))
          .compareTo(_normalizar(_nomeCliente(b)));
    });
  }

  Future<DateTime?> _alterarDataPrevista(
      Cliente cliente,
      DateTime? dataAtual,
      ) async {
    final agora = DateTime.now();
    final data = await showDatePicker(
      context: context,
      initialDate: dataAtual ?? agora,
      firstDate: agora.subtract(const Duration(days: 365)),
      lastDate: agora.add(const Duration(days: 730)),
      helpText: 'DATA PREVISTA DA VISITA',
      cancelText: 'CANCELAR',
      confirmText: 'SALVAR',
    );

    if (data == null || !mounted) return null;

    try {
      await ref.read(clienteRepositoryProvider).definirProximaVisita(
        clienteId: cliente.id!,
        data: data,
      );
      ref.invalidate(clientesListProvider);
      _mostrarMensagem('Data prevista atualizada.');
      return data;
    } catch (error, stackTrace) {
      debugPrint('Erro ao alterar data prevista: $error\n$stackTrace');
      _mostrarMensagem(
        'Não foi possível atualizar a data prevista.',
        isError: true,
      );
      return null;
    }
  }

  Future<_AcaoConfirmacaoInicio?> _confirmarInicio({
    required Cliente cliente,
    required DateTime? dataPrevista,
    required VisitaTipo tipo,
    String? expositorLabel,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final prevista = dataPrevista == null ? null : _somenteData(dataPrevista);
    final somenteConferencia =
        cliente.statusFinanceiro == StatusFinanceiro.bloqueado &&
            tipo == VisitaTipo.visita;

    String alerta;
    IconData alertaIcon;
    Color alertaColor;

    if (prevista == null) {
      alerta = 'Este cliente não possui visita agendada.';
      alertaIcon = Icons.event_busy_outlined;
      alertaColor = colorScheme.onSurfaceVariant;
    } else if (prevista.isAfter(_hoje)) {
      alerta =
      'A visita está prevista para ${_formatarData(prevista)}. Ao iniciar agora, ela será registrada como antecipada.';
      alertaIcon = Icons.update_outlined;
      alertaColor = Colors.blueAccent;
    } else if (prevista.isBefore(_hoje)) {
      final dias = _hoje.difference(prevista).inDays;
      alerta = dias == 1
          ? 'A visita está atrasada há 1 dia.'
          : 'A visita está atrasada há $dias dias.';
      alertaIcon = Icons.warning_amber_rounded;
      alertaColor = colorScheme.error;
    } else {
      alerta = 'A visita está prevista para hoje.';
      alertaIcon = Icons.event_available_outlined;
      alertaColor = colorScheme.primary;
    }

    return showDialog<_AcaoConfirmacaoInicio>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          icon: Icon(Icons.route_outlined, color: colorScheme.primary),
          title: Text(
            somenteConferencia
                ? 'Iniciar conferência?'
                : 'Iniciar visita?',
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 470),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _nomeCliente(cliente),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatarCpfCnpj(cliente.cpfCnpj),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                _DialogInfoRow(
                  icon: Icons.event_outlined,
                  label: 'Data prevista',
                  value: dataPrevista == null
                      ? 'Não definida'
                      : _formatarData(dataPrevista),
                ),
                const SizedBox(height: 10),
                _DialogInfoRow(
                  icon: tipo == VisitaTipo.instalacao
                      ? Icons.add_business_outlined
                      : Icons.inventory_2_outlined,
                  label: 'Operação',
                  value: tipo == VisitaTipo.instalacao
                      ? 'Instalação inicial'
                      : somenteConferencia
                      ? 'Conferência sem reposição'
                      : 'Conferência e reposição',
                ),
                if (expositorLabel != null) ...[
                  const SizedBox(height: 10),
                  _DialogInfoRow(
                    icon: Icons.view_in_ar_outlined,
                    label: 'Expositor',
                    value: expositorLabel,
                  ),
                ],
                if (somenteConferencia) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.error.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.error.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.block_outlined,
                          color: colorScheme.error,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Cliente bloqueado financeiramente. '
                                'A visita permitirá conferência e acerto, '
                                'mas nenhuma reposição de produtos.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: alertaColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: alertaColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(alertaIcon, color: alertaColor, size: 20),
                      const SizedBox(width: 10),
                      Expanded(child: Text(alerta)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Confirme somente quando estiver no estabelecimento.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
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
            TextButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(
                _AcaoConfirmacaoInicio.alterarData,
              ),
              icon: const Icon(Icons.edit_calendar_outlined),
              label: Text(
                dataPrevista == null ? 'Definir data' : 'Alterar data',
              ),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(
                _AcaoConfirmacaoInicio.iniciar,
              ),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(
                somenteConferencia
                    ? 'Iniciar conferência'
                    : 'Iniciar visita',
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _selecionarCliente(
      Cliente cliente,
      Visita? visitaEmAndamento,
      ) async {
    final clienteId = cliente.id;

    if (clienteId == null || clienteId.isEmpty) {
      _mostrarMensagem(
        'Este cliente não possui um identificador válido.',
        isError: true,
      );
      return;
    }

    if (_clienteCarregandoId != null) return;

    if (!_clienteAprovado(cliente) ||
        cliente.statusOperacional == StatusOperacional.pendente ||
        cliente.statusOperacional == StatusOperacional.suspenso ||
        cliente.statusOperacional == StatusOperacional.encerrado) {
      _mostrarMensagem(
        cliente.statusOperacional == StatusOperacional.encerrado
            ? 'A parceria deste cliente está encerrada. '
            'Ele permanece disponível apenas no histórico.'
            : 'Este cliente não está disponível para iniciar uma visita.',
        isError: true,
      );
      _atualizarTudo();
      return;
    }

    if (visitaEmAndamento != null) {
      await _retomarVisita(cliente, visitaEmAndamento);
      return;
    }

    final usuario = ref.read(appUserProvider).value;
    if (usuario == null) {
      _mostrarMensagem(
        'Sua sessão não está disponível. Entre novamente.',
        isError: true,
      );
      return;
    }

    final visitaDoVendedor =
        ref.read(visitaEmAndamentoDoVendedorProvider).value;
    if (visitaDoVendedor != null && visitaDoVendedor.clienteId != clienteId) {
      _mostrarMensagem(
        'Você já possui uma visita em andamento. Retome ou cancele esse atendimento antes de iniciar outro.',
        isError: true,
      );
      return;
    }

    setState(() => _clienteCarregandoId = clienteId);

    try {
      final consignacoes = await ref
          .read(consignmentRepositoryProvider)
          .watchTodasAtivasDoCliente(clienteId)
          .first;

      if (!mounted) return;

      Consignment? consignacaoEscolhida;
      if (consignacoes.length == 1) {
        consignacaoEscolhida = consignacoes.first;
      } else if (consignacoes.length > 1) {
        consignacaoEscolhida = await _escolherExpositor(
          context,
          consignacoes,
        );
        if (consignacaoEscolhida == null || !mounted) return;
      }

      late final VisitaTipo tipo;

      if (consignacoes.isNotEmpty) {
        tipo = VisitaTipo.visita;
      } else if (cliente.statusOperacional ==
          StatusOperacional.aguardandoInstalacao) {
        tipo = VisitaTipo.instalacao;
      } else {
        _mostrarMensagem(
          'Este cliente não possui consignação ativa. '
              'Ele não pode iniciar uma nova instalação por esta tela.',
          isError: true,
        );
        _atualizarTudo();
        return;
      }

      if (tipo == VisitaTipo.instalacao &&
          cliente.statusFinanceiro == StatusFinanceiro.bloqueado) {
        _mostrarMensagem(
          'Cliente bloqueado financeiramente. '
              'Não é possível iniciar uma nova instalação enquanto o bloqueio estiver ativo.',
          isError: true,
        );
        return;
      }

      final expositorId = tipo == VisitaTipo.instalacao
          ? cliente.expositorFisicoSelecionadoId
          : consignacaoEscolhida?.expositorId;

      if (tipo == VisitaTipo.instalacao &&
          (expositorId == null || expositorId.isEmpty)) {
        _mostrarMensagem(
          'Reserve um expositor no cadastro do cliente antes de iniciar a instalação.',
          isError: true,
        );
        return;
      }

      var dataPrevista = cliente.proximaVisitaEm;
      final expositorLabel = _rotuloExpositor(
        consignacao: consignacaoEscolhida,
        expositorIdInstalacao: expositorId,
      );

      while (mounted) {
        final acao = await _confirmarInicio(
          cliente: cliente,
          dataPrevista: dataPrevista,
          tipo: tipo,
          expositorLabel: expositorLabel,
        );

        if (acao == null || !mounted) return;

        if (acao == _AcaoConfirmacaoInicio.alterarData) {
          final novaData = await _alterarDataPrevista(
            cliente,
            dataPrevista,
          );
          if (novaData != null) dataPrevista = novaData;
          continue;
        }

        final visitaId = await ref.read(visitaRepositoryProvider).iniciar(
          orgId: usuario.orgId,
          clienteId: clienteId,
          vendedorId: usuario.uid,
          tipo: tipo,
          dataPrevista: dataPrevista,
          consignmentId: consignacaoEscolhida?.id,
          expositorId: expositorId,
        );

        if (!mounted) return;

        await _abrirFluxo(
          cliente: cliente,
          visitaId: visitaId,
          dataPrevista: dataPrevista,
          tipo: tipo,
          consignacao: consignacaoEscolhida,
        );
        return;
      }
    } on VisitaJaEmAndamentoException catch (error) {
      ref.invalidate(visitasEmAndamentoProvider);

      if (error.iniciadaPelo(usuario.uid) && error.visitaId != null) {
        final visita = await ref
            .read(visitaRepositoryProvider)
            .buscarById(error.visitaId!);
        if (visita != null && mounted) {
          // Libera o carregamento antes de retomar. Sem isso,
          // _retomarVisita via _clienteCarregandoId != null e saía
          // sem fazer nada.
          _finalizarCarregamento(clienteId);
          await _retomarVisita(cliente, visita);
          return;
        }
      }

      _mostrarMensagem(error.toString(), isError: true);
    } on VendedorComVisitaEmAndamentoException catch (error) {
      ref.invalidate(visitasEmAndamentoProvider);
      _mostrarMensagem(error.toString(), isError: true);
    } catch (error, stackTrace) {
      debugPrint('Erro ao iniciar visita: $error\n$stackTrace');
      _mostrarMensagem(
        'Não foi possível iniciar a visita. Tente novamente.',
        isError: true,
      );
    } finally {
      _finalizarCarregamento(clienteId);
    }
  }

  Future<void> _retomarVisita(
      Cliente cliente,
      Visita visita,
      ) async {
    final usuario = ref.read(appUserProvider).value;
    if (usuario == null) return;

    if (visita.vendedorId != usuario.uid) {
      _mostrarMensagem(
        'Esta visita foi iniciada por outro vendedor.',
        isError: true,
      );
      return;
    }

    final clienteId = cliente.id;
    final visitaId = visita.id;
    if (clienteId == null || visitaId == null) return;

    if (_clienteCarregandoId != null) return;
    setState(() => _clienteCarregandoId = clienteId);

    try {
      Consignment? consignacao;

      if (visita.tipo != VisitaTipo.instalacao) {
        final consignacoes = await ref
            .read(consignmentRepositoryProvider)
            .watchTodasAtivasDoCliente(clienteId)
            .first;

        if (!mounted) return;

        for (final item in consignacoes) {
          if (item.id == visita.consignmentId) {
            consignacao = item;
            break;
          }
        }

        if (consignacao == null && consignacoes.length == 1) {
          consignacao = consignacoes.first;
        }

        if (consignacao == null && consignacoes.length > 1) {
          consignacao = await _escolherExpositor(context, consignacoes);
          if (!mounted) return;
        }

        if (consignacao == null) {
          _mostrarMensagem(
            'A consignação desta visita não está mais ativa.',
            isError: true,
          );
          return;
        }
      }

      if (!mounted) return;

      await _abrirFluxo(
        cliente: cliente,
        visitaId: visitaId,
        dataPrevista: visita.dataPrevista,
        tipo: visita.tipo,
        consignacao: consignacao,
      );
    } catch (error, stackTrace) {
      debugPrint('Erro ao retomar visita: $error\n$stackTrace');
      _mostrarMensagem(
        'Não foi possível retomar a visita.',
        isError: true,
      );
    } finally {
      _finalizarCarregamento(clienteId);
    }
  }

  Future<void> _abrirFluxo({
    required Cliente cliente,
    required String visitaId,
    required DateTime? dataPrevista,
    required VisitaTipo tipo,
    Consignment? consignacao,
  }) async {
    if (tipo == VisitaTipo.instalacao) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => InstalacaoPage(
            cliente: cliente,
            visitaId: visitaId,
            dataPrevista: dataPrevista,
          ),
        ),
      );
    } else if (tipo == VisitaTipo.visita && consignacao != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VisitaExecucaoPage(
            cliente: cliente,
            consignmentAtiva: consignacao,
            visitaId: visitaId,
            dataPrevista: dataPrevista,
          ),
        ),
      );
    } else {
      _mostrarMensagem(
        'Este tipo de atendimento deve ser retomado pela ficha do cliente.',
        isError: true,
      );
    }

    ref.invalidate(visitasEmAndamentoProvider);
    ref.invalidate(visitasRealizadasProvider);
    ref.invalidate(clientesListProvider);
  }

  Future<void> _cancelarVisita(Visita visita) async {
    final visitaId = visita.id;
    if (visitaId == null || _visitaCancelandoId != null) return;

    final confirmar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: const Text('Cancelar visita?'),
        content: const Text(
          'Use esta opção somente quando o atendimento não será continuado. '
              'Uma visita cancelada não poderá ser retomada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cancelar visita'),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) return;
    setState(() => _visitaCancelandoId = visitaId);

    try {
      await ref.read(visitaRepositoryProvider).cancelar(visitaId);
      ref.invalidate(visitasEmAndamentoProvider);
      _mostrarMensagem('Visita cancelada.');
    } catch (error, stackTrace) {
      debugPrint('Erro ao cancelar visita: $error\n$stackTrace');
      _mostrarMensagem(
        'Não foi possível cancelar a visita.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _visitaCancelandoId = null);
    }
  }

  void _finalizarCarregamento(String clienteId) {
    if (!mounted || _clienteCarregandoId != clienteId) return;
    setState(() => _clienteCarregandoId = null);
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
          backgroundColor: isError ? colorScheme.error : colorScheme.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  String? _rotuloExpositor({
    Consignment? consignacao,
    String? expositorIdInstalacao,
  }) {
    final expositores = ref.read(expositoresFisicosListProvider).value ??
        const <ExpositorFisico>[];

    final id = consignacao?.expositorId ?? expositorIdInstalacao;
    if (id == null) return null;

    for (final expositor in expositores) {
      if (expositor.id == id) {
        return '${expositor.numero} · ${expositor.modeloNome}';
      }
    }

    if (consignacao != null) {
      return 'Consignação ${consignacao.numero}';
    }

    return 'Expositor reservado';
  }

  Future<Consignment?> _escolherExpositor(
      BuildContext context,
      List<Consignment> consignacoesAtivas,
      ) async {
    final expositores = ref.read(expositoresFisicosListProvider).value ??
        const <ExpositorFisico>[];

    final expositoresPorId = <String, ExpositorFisico>{
      for (final expositor in expositores)
        if (expositor.id != null) expositor.id!: expositor,
    };

    final isMobile = MediaQuery.sizeOf(context).width < 700;
    if (isMobile) {
      return _mostrarSelecaoMobile(
        context,
        consignacoesAtivas,
        expositoresPorId,
      );
    }

    return _mostrarSelecaoWeb(
      context,
      consignacoesAtivas,
      expositoresPorId,
    );
  }

  Future<Consignment?> _mostrarSelecaoMobile(
      BuildContext context,
      List<Consignment> consignacoes,
      Map<String, ExpositorFisico> expositoresPorId,
      ) {
    final colorScheme = Theme.of(context).colorScheme;

    return showModalBottomSheet<Consignment>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.78,
          child: Material(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(28),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Escolher expositor',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Selecione qual expositor será conferido.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Fechar',
                        onPressed: () => Navigator.of(bottomSheetContext).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: consignacoes.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final consignacao = consignacoes[index];
                      final expositor = consignacao.expositorId != null
                          ? expositoresPorId[consignacao.expositorId]
                          : null;

                      return _ExpositorOptionCard(
                        consignacao: consignacao,
                        expositor: expositor,
                        onTap: () =>
                            Navigator.of(bottomSheetContext).pop(consignacao),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<Consignment?> _mostrarSelecaoWeb(
      BuildContext context,
      List<Consignment> consignacoes,
      Map<String, ExpositorFisico> expositoresPorId,
      ) {
    final altura = (MediaQuery.sizeOf(context).height * 0.72)
        .clamp(340.0, 560.0)
        .toDouble();

    return showDialog<Consignment>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          child: SizedBox(
            width: 540,
            height: altura,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 12, 16),
                  child: Row(
                    children: [
                      const Icon(Icons.view_in_ar_outlined),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Escolher expositor',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 3),
                            const Text(
                              'Este cliente possui mais de um expositor.',
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Fechar',
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(18),
                    itemCount: consignacoes.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final consignacao = consignacoes[index];
                      final expositor = consignacao.expositorId != null
                          ? expositoresPorId[consignacao.expositorId]
                          : null;

                      return _ExpositorOptionCard(
                        consignacao: consignacao,
                        expositor: expositor,
                        onTap: () =>
                            Navigator.of(dialogContext).pop(consignacao),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _atualizarTudo() {
    ref.invalidate(clientesListProvider);
    ref.invalidate(visitasEmAndamentoProvider);
    ref.invalidate(visitasRealizadasProvider);
    ref.invalidate(expositoresFisicosListProvider);
    ref.invalidate(_consignacoesAtivasAgendaProvider);
  }

  @override
  Widget build(BuildContext context) {
    final clientesAsync = ref.watch(clientesListProvider);
    final emAndamentoAsync = ref.watch(visitasEmAndamentoProvider);
    final realizadasAsync = ref.watch(visitasRealizadasProvider);
    final usuario = ref.watch(appUserProvider).value;

    return Scaffold(
      body: clientesAsync.when(
        data: (clientes) {
          final clientesAprovados =
          clientes.where(_clienteAprovado).toList();

          final temConsignacaoAtivaPorCliente = <String, bool>{};

          for (final cliente in clientesAprovados) {
            final clienteId = cliente.id;
            if (clienteId == null || clienteId.isEmpty) continue;

            if (cliente.statusOperacional == StatusOperacional.ativo) {
              final consignacoesAsync = ref.watch(
                _consignacoesAtivasAgendaProvider(clienteId),
              );

              // Enquanto a primeira leitura ainda está carregando,
              // mantém o cliente visível para evitar piscar a agenda.
              // Assim que a leitura chega, cliente sem consignação
              // ativa some automaticamente.
              temConsignacaoAtivaPorCliente[clienteId] =
              consignacoesAsync.value == null &&
                  consignacoesAsync.isLoading
                  ? true
                  : (consignacoesAsync.value ?? const <Consignment>[])
                  .isNotEmpty;
            }
          }

          final aprovados = clientesAprovados.where((cliente) {
            final clienteId = cliente.id;
            final temConsignacaoAtiva =
                clienteId != null &&
                    (temConsignacaoAtivaPorCliente[clienteId] ?? false);

            return _clientePodeEntrarNaAgenda(
              cliente,
              temConsignacaoAtiva: temConsignacaoAtiva,
            );
          }).toList();

          final visitasEmAndamento =
              emAndamentoAsync.value ?? const <Visita>[];
          final visitasPorCliente = <String, Visita>{
            for (final visita in visitasEmAndamento) visita.clienteId: visita,
          };

          Cliente? clienteFoco;
          if (_clienteFocoId != null) {
            for (final cliente in clientes) {
              if (cliente.id == _clienteFocoId) {
                clienteFoco = cliente;
                break;
              }
            }
          }

          var atrasadas = 0;
          var hoje = 0;
          var naSemana = 0;
          for (final cliente in aprovados) {
            final situacao = _situacaoDoCliente(
              cliente,
              visitasPorCliente[cliente.id],
            );
            if (situacao == _SituacaoAgenda.atrasada) atrasadas++;
            if (situacao == _SituacaoAgenda.hoje) hoje++;
            if (situacao == _SituacaoAgenda.hoje ||
                situacao == _SituacaoAgenda.estaSemana) {
              naSemana++;
            }
          }

          return SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1240),
                child: NestedScrollView(
                  headerSliverBuilder: (context, innerBoxIsScrolled) {
                    return [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate(
                            [
                              _AgendaHeader(
                                pesquisaController: _pesquisaController,
                                possuiPesquisa: _pesquisa.isNotEmpty,
                                onPesquisaChanged: (valor) {
                                  setState(() => _pesquisa = valor);
                                },
                                onLimparPesquisa: () {
                                  _pesquisaController.clear();
                                  setState(() => _pesquisa = '');
                                },
                                onAtualizar: _atualizarTudo,
                              ),
                              const SizedBox(height: 16),
                              if (_clienteFocoId != null) ...[
                                _FocoClienteBanner(
                                  nome: clienteFoco == null
                                      ? 'Cliente não encontrado'
                                      : _nomeCliente(clienteFoco),
                                  onLimpar: _limparFoco,
                                ),
                                const SizedBox(height: 12),
                              ],
                              _MetricasAgenda(
                                atrasadas: atrasadas,
                                hoje: hoje,
                                semana: naSemana,
                                emAndamento: visitasEmAndamento.length,
                                onAtrasadas: () {
                                  setState(() {
                                    _tabController.index = 0;
                                    _clienteFocoId = null;
                                    _filtro = _AgendaFiltro.atrasadas;
                                  });
                                },
                                onHoje: () {
                                  setState(() {
                                    _tabController.index = 0;
                                    _clienteFocoId = null;
                                    _filtro = _AgendaFiltro.hoje;
                                  });
                                },
                                onSemana: () {
                                  setState(() {
                                    _tabController.index = 0;
                                    _clienteFocoId = null;
                                    _filtro = _AgendaFiltro.estaSemana;
                                  });
                                },
                                onEmAndamento: () {
                                  setState(() {
                                    _tabController.index = 1;
                                    _clienteFocoId = null;
                                  });
                                },
                              ),
                              const SizedBox(height: 16),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outlineVariant,
                                  ),
                                ),
                                child: TabBar(
                                  controller: _tabController,
                                  isScrollable:
                                  MediaQuery.sizeOf(context).width < 760,
                                  onTap: (_) => setState(() {}),
                                  tabs: [
                                    Tab(
                                      icon: const Icon(
                                        Icons.calendar_month_outlined,
                                      ),
                                      text: 'Agenda (${aprovados.length})',
                                    ),
                                    Tab(
                                      icon: const Icon(
                                        Icons.play_circle_outline,
                                      ),
                                      text:
                                      'Em andamento (${visitasEmAndamento.length})',
                                    ),
                                    Tab(
                                      icon: const Icon(Icons.task_alt_outlined),
                                      text:
                                      'Realizadas (${realizadasAsync.value?.length ?? 0})',
                                    ),
                                  ],
                                ),
                              ),
                              if (_tabController.index == 0) ...[
                                const SizedBox(height: 12),
                                _FiltrosAgenda(
                                  selecionado: _filtro,
                                  onSelecionado: (filtro) {
                                    setState(() => _filtro = filtro);
                                  },
                                ),
                              ],
                              if (emAndamentoAsync.isLoading ||
                                  realizadasAsync.isLoading)
                                const Padding(
                                  padding: EdgeInsets.only(top: 10),
                                  child: LinearProgressIndicator(minHeight: 2),
                                ),
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                      ),
                    ];
                  },
                  body: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: switch (_tabController.index) {
                      0 => _buildAgenda(
                        aprovados,
                        visitasPorCliente,
                        clienteFoco,
                      ),
                      1 => _buildEmAndamento(
                        emAndamentoAsync,
                        clientes,
                        usuario?.uid,
                      ),
                      _ => _buildRealizadas(
                        realizadasAsync,
                        clientes,
                      ),
                    },
                  ),
                ),
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) {
          debugPrint(
            'Erro ao carregar agenda de visitas: $error\n$stackTrace',
          );
          return _EstadoMensagem(
            icon: Icons.cloud_off_outlined,
            titulo: 'Não foi possível carregar a agenda',
            mensagem: 'Verifique sua conexão e tente novamente.',
            textoBotao: 'Tentar novamente',
            onPressed: _atualizarTudo,
          );
        },
      ),
    );
  }

  Widget _buildAgenda(
      List<Cliente> aprovados,
      Map<String, Visita> visitasPorCliente,
      Cliente? clienteFoco,
      ) {
    // Quando a tela foi aberta focando um cliente que já não pode
    // receber atendimento, explica o motivo em vez de mostrar um
    // resultado vazio ou permitir iniciar um fluxo inválido.
    if (_clienteFocoId != null && clienteFoco != null) {
      final estaNaAgenda = aprovados.any(
            (cliente) => cliente.id == clienteFoco.id,
      );

      if (!estaNaAgenda) {
        final mensagem = !_clienteAprovado(clienteFoco)
            ? '${_nomeCliente(clienteFoco)} ainda não está aprovado.'
            : clienteFoco.statusOperacional == StatusOperacional.encerrado
            ? 'A parceria com ${_nomeCliente(clienteFoco)} está encerrada. '
            'As visitas anteriores continuam disponíveis no histórico.'
            : clienteFoco.statusOperacional == StatusOperacional.suspenso
            ? '${_nomeCliente(clienteFoco)} está com o atendimento suspenso.'
            : clienteFoco.statusOperacional ==
            StatusOperacional.aguardandoInstalacao
            ? 'Este cliente ainda não possui um expositor reservado '
            'para iniciar a instalação.'
            : 'Este cliente não possui consignação ativa para uma nova visita.';

        return _EstadoMensagem(
          icon: Icons.assignment_late_outlined,
          titulo: 'Cliente fora da agenda',
          mensagem: mensagem,
          textoBotao: 'Ver todos os clientes',
          onPressed: _limparFoco,
        );
      }
    }

    if (aprovados.isEmpty) {
      return _EstadoMensagem(
        icon: Icons.storefront_outlined,
        titulo: 'Nenhum cliente disponível para visita',
        mensagem:
        'Clientes com instalação pendente e expositor reservado, '
            'ou com consignação ativa, aparecerão aqui.',
        textoBotao: 'Atualizar',
        onPressed: _atualizarTudo,
      );
    }

    final filtrados = aprovados.where((cliente) {
      return _correspondeFoco(cliente.id) &&
          _correspondePesquisa(cliente) &&
          _correspondeFiltro(cliente, visitasPorCliente[cliente.id]);
    }).toList();
    _ordenarAgenda(filtrados, visitasPorCliente);

    if (filtrados.isEmpty) {
      return _EstadoMensagem(
        icon: Icons.event_busy_outlined,
        titulo: 'Nenhuma visita encontrada',
        mensagem: 'Altere a busca ou selecione outro filtro da agenda.',
        textoBotao: 'Limpar filtros',
        onPressed: () {
          _pesquisaController.clear();
          setState(() {
            _pesquisa = '';
            _filtro = _AgendaFiltro.todas;
            _clienteFocoId = null;
          });
        },
      );
    }

    final usuarioId = ref.read(appUserProvider).value?.uid;

    return LayoutBuilder(
      builder: (context, constraints) {
        final colunas = constraints.maxWidth >= 1060
            ? 3
            : constraints.maxWidth >= 680
            ? 2
            : 1;

        return GridView.builder(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(bottom: 24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: colunas,
            mainAxisExtent: 238,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: filtrados.length,
          itemBuilder: (context, index) {
            final cliente = filtrados[index];
            final visita = visitasPorCliente[cliente.id];
            final carregando = _clienteCarregandoId == cliente.id;
            final nome = _nomeCliente(cliente);

            return _ClienteAgendaCard(
              nome: nome,
              documento: _formatarCpfCnpj(cliente.cpfCnpj),
              endereco: cliente.enderecoResumo,
              iniciais: _iniciais(nome),
              situacao: _situacaoDoCliente(cliente, visita),
              textoSituacao: _textoSituacao(cliente, visita),
              carregando: carregando,
              bloqueado: _clienteCarregandoId != null,
              somenteConferencia:
              cliente.statusFinanceiro == StatusFinanceiro.bloqueado &&
                  cliente.statusOperacional == StatusOperacional.ativo,
              visitaDeOutroVendedor:
              visita != null && visita.vendedorId != usuarioId,
              onTap: () => _selecionarCliente(cliente, visita),
            );
          },
        );
      },
    );
  }

  Widget _buildEmAndamento(
      AsyncValue<List<Visita>> visitasAsync,
      List<Cliente> clientes,
      String? usuarioId,
      ) {
    return visitasAsync.when(
      data: (visitas) {
        final clientesPorId = <String, Cliente>{
          for (final cliente in clientes)
            if (cliente.id != null) cliente.id!: cliente,
        };

        final filtradas = visitas.where((visita) {
          if (!_correspondeFoco(visita.clienteId)) return false;

          final cliente = clientesPorId[visita.clienteId];
          if (cliente == null) {
            return visita.id?.toLowerCase().contains(
              _pesquisa.toLowerCase(),
            ) ??
                false;
          }
          return _correspondePesquisa(cliente);
        }).toList();

        if (filtradas.isEmpty) {
          return _EstadoMensagem(
            icon: Icons.pause_circle_outline,
            titulo: 'Nenhuma visita em andamento',
            mensagem: _pesquisa.isEmpty
                ? 'As visitas iniciadas aparecerão aqui para retomada.'
                : 'Nenhuma visita em andamento corresponde à busca.',
            textoBotao: _pesquisa.isEmpty ? 'Atualizar' : 'Limpar pesquisa',
            onPressed: _pesquisa.isEmpty
                ? _atualizarTudo
                : () {
              _pesquisaController.clear();
              setState(() => _pesquisa = '');
            },
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: filtradas.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final visita = filtradas[index];
            final cliente = clientesPorId[visita.clienteId];
            final propria = visita.vendedorId == usuarioId;

            return _VisitaAndamentoCard(
              visita: visita,
              clienteNome: cliente == null
                  ? 'Cliente não encontrado'
                  : _nomeCliente(cliente),
              documento: cliente == null
                  ? visita.clienteId
                  : _formatarCpfCnpj(cliente.cpfCnpj),
              iniciadaEm: _formatarDataHora(visita.inicioEfetivo),
              carregando:
              cliente != null && _clienteCarregandoId == cliente.id,
              cancelando: _visitaCancelandoId == visita.id,
              podeRetomar: propria && cliente != null,
              onRetomar: cliente == null
                  ? null
                  : () => _retomarVisita(cliente, visita),
              onCancelar: propria ? () => _cancelarVisita(visita) : null,
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => _EstadoMensagem(
        icon: Icons.cloud_off_outlined,
        titulo: 'Não foi possível carregar as visitas abertas',
        mensagem: 'Tente atualizar os dados novamente.',
        textoBotao: 'Tentar novamente',
        onPressed: _atualizarTudo,
      ),
    );
  }

  Widget _buildRealizadas(
      AsyncValue<List<Visita>> visitasAsync,
      List<Cliente> clientes,
      ) {
    return visitasAsync.when(
      data: (visitas) {
        final clientesPorId = <String, Cliente>{
          for (final cliente in clientes)
            if (cliente.id != null) cliente.id!: cliente,
        };

        final termo = _pesquisa.trim().toLowerCase();

        final filtradas = visitas.where((visita) {
          if (!_correspondeFoco(visita.clienteId)) return false;
          if (termo.isEmpty) return true;

          if (visita.numero?.toLowerCase().contains(termo) ?? false) {
            return true;
          }
          final cliente = clientesPorId[visita.clienteId];
          return cliente != null && _correspondePesquisa(cliente);
        }).toList();

        if (filtradas.isEmpty) {
          return _EstadoMensagem(
            icon: Icons.history_outlined,
            titulo: 'Nenhuma visita realizada',
            mensagem: _pesquisa.isEmpty
                ? 'As visitas finalizadas aparecerão neste histórico.'
                : 'Nenhuma visita realizada corresponde à busca.',
            textoBotao: _pesquisa.isEmpty ? 'Atualizar' : 'Limpar pesquisa',
            onPressed: _pesquisa.isEmpty
                ? _atualizarTudo
                : () {
              _pesquisaController.clear();
              setState(() => _pesquisa = '');
            },
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: filtradas.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final visita = filtradas[index];
            final cliente = clientesPorId[visita.clienteId];

            return _VisitaRealizadaCard(
              visita: visita,
              clienteNome: cliente == null
                  ? 'Cliente não encontrado'
                  : _nomeCliente(cliente),
              documento: cliente == null
                  ? visita.clienteId
                  : _formatarCpfCnpj(cliente.cpfCnpj),
              finalizadaEm: _formatarDataHora(visita.finalizadaEm),
              resultadoPrazo: _resultadoDoPrazo(visita),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => _EstadoMensagem(
        icon: Icons.cloud_off_outlined,
        titulo: 'Não foi possível carregar o histórico',
        mensagem: 'Tente atualizar os dados novamente.',
        textoBotao: 'Tentar novamente',
        onPressed: _atualizarTudo,
      ),
    );
  }

  String _resultadoDoPrazo(Visita visita) {
    if (visita.dataPrevista == null || visita.finalizadaEm == null) {
      return 'Sem comparação de prazo';
    }

    final diferenca = _somenteData(visita.finalizadaEm!)
        .difference(_somenteData(visita.dataPrevista!))
        .inDays;

    if (diferenca == 0) return 'Realizada no dia previsto';
    if (diferenca == 1) return 'Realizada com 1 dia de atraso';
    if (diferenca > 1) return 'Realizada com $diferenca dias de atraso';
    if (diferenca == -1) return 'Realizada 1 dia antes';
    return 'Realizada ${diferenca.abs()} dias antes';
  }
}

class _FocoClienteBanner extends StatelessWidget {
  const _FocoClienteBanner({
    required this.nome,
    required this.onLimpar,
  });

  final String nome;
  final VoidCallback onLimpar;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.30),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.person_search_outlined,
            size: 20,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Mostrando apenas '),
                  TextSpan(
                    text: nome,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: onLimpar,
            icon: const Icon(Icons.close, size: 18),
            label: const Text('Ver todos'),
          ),
        ],
      ),
    );
  }
}

class _AgendaHeader extends StatelessWidget {
  const _AgendaHeader({
    required this.pesquisaController,
    required this.possuiPesquisa,
    required this.onPesquisaChanged,
    required this.onLimparPesquisa,
    required this.onAtualizar,
  });

  final TextEditingController pesquisaController;
  final bool possuiPesquisa;
  final ValueChanged<String> onPesquisaChanged;
  final VoidCallback onLimparPesquisa;
  final VoidCallback onAtualizar;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final titulo = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Agenda de visitas',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Acompanhe os próximos atendimentos e retome visitas abertas.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Atualizar agenda',
          onPressed: onAtualizar,
          icon: const Icon(Icons.refresh),
        ),
      ],
    );

    final pesquisa = TextField(
      controller: pesquisaController,
      onChanged: onPesquisaChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Buscar cliente, documento ou endereço',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: possuiPesquisa
            ? IconButton(
          tooltip: 'Limpar pesquisa',
          onPressed: onLimparPesquisa,
          icon: const Icon(Icons.close),
        )
            : null,
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              titulo,
              const SizedBox(height: 14),
              pesquisa,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titulo),
            const SizedBox(width: 24),
            SizedBox(width: 410, child: pesquisa),
          ],
        );
      },
    );
  }
}

class _MetricasAgenda extends StatelessWidget {
  const _MetricasAgenda({
    required this.atrasadas,
    required this.hoje,
    required this.semana,
    required this.emAndamento,
    required this.onAtrasadas,
    required this.onHoje,
    required this.onSemana,
    required this.onEmAndamento,
  });

  final int atrasadas;
  final int hoje;
  final int semana;
  final int emAndamento;
  final VoidCallback onAtrasadas;
  final VoidCallback onHoje;
  final VoidCallback onSemana;
  final VoidCallback onEmAndamento;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final colunas = constraints.maxWidth >= 900 ? 4 : 2;
        const espaco = 10.0;
        final largura =
            (constraints.maxWidth - (espaco * (colunas - 1))) / colunas;

        return Wrap(
          spacing: espaco,
          runSpacing: espaco,
          children: [
            SizedBox(
              width: largura,
              child: _MetricaCard(
                label: 'Atrasadas',
                valor: atrasadas,
                icon: Icons.warning_amber_rounded,
                color: colorScheme.error,
                onTap: onAtrasadas,
              ),
            ),
            SizedBox(
              width: largura,
              child: _MetricaCard(
                label: 'Hoje',
                valor: hoje,
                icon: Icons.today_outlined,
                color: colorScheme.primary,
                onTap: onHoje,
              ),
            ),
            SizedBox(
              width: largura,
              child: _MetricaCard(
                label: 'Esta semana',
                valor: semana,
                icon: Icons.date_range_outlined,
                color: Colors.blueAccent,
                onTap: onSemana,
              ),
            ),
            SizedBox(
              width: largura,
              child: _MetricaCard(
                label: 'Em andamento',
                valor: emAndamento,
                icon: Icons.play_circle_outline,
                color: Colors.orangeAccent,
                onTap: onEmAndamento,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MetricaCard extends StatelessWidget {
  const _MetricaCard({
    required this.label,
    required this.valor,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final int valor;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 86,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$valor',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
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

class _FiltrosAgenda extends StatelessWidget {
  const _FiltrosAgenda({
    required this.selecionado,
    required this.onSelecionado,
  });

  final _AgendaFiltro selecionado;
  final ValueChanged<_AgendaFiltro> onSelecionado;

  @override
  Widget build(BuildContext context) {
    const filtros = <(_AgendaFiltro, String, IconData)>[
      (_AgendaFiltro.todas, 'Todas', Icons.list_alt_outlined),
      (_AgendaFiltro.atrasadas, 'Atrasadas', Icons.warning_amber_rounded),
      (_AgendaFiltro.hoje, 'Hoje', Icons.today_outlined),
      (_AgendaFiltro.estaSemana, 'Esta semana', Icons.date_range_outlined),
      (_AgendaFiltro.proximas, 'Próximas', Icons.upcoming_outlined),
      (_AgendaFiltro.semData, 'Sem data', Icons.event_busy_outlined),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filtro in filtros) ...[
            FilterChip(
              selected: selecionado == filtro.$1,
              onSelected: (_) => onSelecionado(filtro.$1),
              avatar: Icon(filtro.$3, size: 17),
              label: Text(filtro.$2),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _ClienteAgendaCard extends StatelessWidget {
  const _ClienteAgendaCard({
    required this.nome,
    required this.documento,
    required this.endereco,
    required this.iniciais,
    required this.situacao,
    required this.textoSituacao,
    required this.carregando,
    required this.bloqueado,
    required this.somenteConferencia,
    required this.visitaDeOutroVendedor,
    required this.onTap,
  });

  final String nome;
  final String documento;
  final String endereco;
  final String iniciais;
  final _SituacaoAgenda situacao;
  final String textoSituacao;
  final bool carregando;
  final bool bloqueado;
  final bool somenteConferencia;
  final bool visitaDeOutroVendedor;
  final VoidCallback onTap;

  Color _cor(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return switch (situacao) {
      _SituacaoAgenda.emAndamento => Colors.orangeAccent,
      _SituacaoAgenda.atrasada => colorScheme.error,
      _SituacaoAgenda.hoje => colorScheme.primary,
      _SituacaoAgenda.estaSemana => Colors.blueAccent,
      _SituacaoAgenda.futura => colorScheme.secondary,
      _SituacaoAgenda.semData => colorScheme.onSurfaceVariant,
    };
  }

  IconData get _icone {
    return switch (situacao) {
      _SituacaoAgenda.emAndamento => Icons.play_circle_outline,
      _SituacaoAgenda.atrasada => Icons.warning_amber_rounded,
      _SituacaoAgenda.hoje => Icons.today_outlined,
      _SituacaoAgenda.estaSemana => Icons.date_range_outlined,
      _SituacaoAgenda.futura => Icons.event_outlined,
      _SituacaoAgenda.semData => Icons.event_busy_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = _cor(context);
    final podeAbrir = !bloqueado && !visitaDeOutroVendedor;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 23,
                  backgroundColor: colorScheme.primaryContainer,
                  foregroundColor: colorScheme.onPrimaryContainer,
                  child: Text(
                    iniciais,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nome,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                        Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        documento,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 17,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    endereco.trim().isEmpty
                        ? 'Endereço não informado'
                        : endereco,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(_icone, size: 18, color: color),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      textoSituacao,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: podeAbrir ? onTap : null,
              icon: carregando
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : Icon(
                situacao == _SituacaoAgenda.emAndamento
                    ? Icons.play_arrow_rounded
                    : Icons.route_outlined,
              ),
              label: Text(
                carregando
                    ? 'Preparando visita...'
                    : visitaDeOutroVendedor
                    ? 'Com outro vendedor'
                    : situacao == _SituacaoAgenda.emAndamento
                    ? 'Retomar visita'
                    : somenteConferencia
                    ? 'Conferir sem repor'
                    : 'Iniciar visita',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VisitaAndamentoCard extends StatelessWidget {
  const _VisitaAndamentoCard({
    required this.visita,
    required this.clienteNome,
    required this.documento,
    required this.iniciadaEm,
    required this.carregando,
    required this.cancelando,
    required this.podeRetomar,
    required this.onRetomar,
    required this.onCancelar,
  });

  final Visita visita;
  final String clienteNome;
  final String documento;
  final String iniciadaEm;
  final bool carregando;
  final bool cancelando;
  final bool podeRetomar;
  final VoidCallback? onRetomar;
  final VoidCallback? onCancelar;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compacto = constraints.maxWidth < 680;

            final informacoes = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: const Text(
                        'EM ANDAMENTO',
                        style: TextStyle(
                          color: Colors.orangeAccent,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _tipoVisitaLabel(visita.tipo),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  clienteNome,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  documento,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  'Iniciada em $iniciadaEm',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            );

            final acoes = Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                if (onCancelar != null)
                  OutlinedButton.icon(
                    onPressed: cancelando ? null : onCancelar,
                    icon: cancelando
                        ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Icon(Icons.close),
                    label: const Text('Cancelar'),
                  ),
                FilledButton.icon(
                  onPressed: podeRetomar && !carregando ? onRetomar : null,
                  icon: carregando
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    podeRetomar ? 'Retomar visita' : 'Com outro vendedor',
                  ),
                ),
              ],
            );

            if (compacto) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  informacoes,
                  const SizedBox(height: 14),
                  acoes,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: informacoes),
                const SizedBox(width: 18),
                acoes,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _VisitaRealizadaCard extends StatelessWidget {
  const _VisitaRealizadaCard({
    required this.visita,
    required this.clienteNome,
    required this.documento,
    required this.finalizadaEm,
    required this.resultadoPrazo,
  });

  final Visita visita;
  final String clienteNome;
  final String documento;
  final String finalizadaEm;
  final String resultadoPrazo;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final atrasada = resultadoPrazo.contains('atraso');

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        leading: CircleAvatar(
          backgroundColor: colorScheme.primaryContainer,
          foregroundColor: colorScheme.onPrimaryContainer,
          child: const Icon(Icons.task_alt),
        ),
        title: Text(
          clienteNome,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$documento · ${_tipoVisitaLabel(visita.tipo)}'),
              const SizedBox(height: 3),
              Text('Finalizada em $finalizadaEm'),
              const SizedBox(height: 5),
              Text(
                resultadoPrazo,
                style: TextStyle(
                  color: atrasada ? colorScheme.error : colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        trailing: visita.numero == null
            ? null
            : Text(
          visita.numero!,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

String _tipoVisitaLabel(VisitaTipo tipo) {
  return switch (tipo) {
    VisitaTipo.instalacao => 'Instalação',
    VisitaTipo.visita => 'Conferência e reposição',
    VisitaTipo.coleta => 'Retirada',
    VisitaTipo.transferencia => 'Transferência',
    VisitaTipo.inventario => 'Inventário',
  };
}

const _comAcento = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
const _semAcento = 'aaaaaeeeeiiiiooooouuuucn';

/// Minúsculas e sem acento: "São João" → "sao joao".
/// Mesma regra da lista de clientes — vale mover para core/utils.
String _normalizar(String valor) {
  final minusculo = valor.trim().toLowerCase();
  final buffer = StringBuffer();
  for (final unit in minusculo.split('')) {
    final indice = _comAcento.indexOf(unit);
    buffer.write(indice >= 0 ? _semAcento[indice] : unit);
  }
  return buffer.toString();
}

class _DialogInfoRow extends StatelessWidget {
  const _DialogInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExpositorOptionCard extends StatelessWidget {
  const _ExpositorOptionCard({
    required this.consignacao,
    required this.expositor,
    required this.onTap,
  });

  final Consignment consignacao;
  final ExpositorFisico? expositor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final titulo = expositor != null
        ? expositor!.numero
        : 'Consignação ${consignacao.numero}';
    final modelo = expositor?.modeloNome;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        leading: CircleAvatar(
          backgroundColor: colorScheme.secondaryContainer,
          foregroundColor: colorScheme.onSecondaryContainer,
          child: const Icon(Icons.view_in_ar_outlined),
        ),
        title: Text(
          titulo,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          [
            if (modelo != null && modelo.isNotEmpty) modelo,
            '${consignacao.itens.length} produto(s)',
          ].join(' • '),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _EstadoMensagem extends StatelessWidget {
  const _EstadoMensagem({
    required this.icon,
    required this.titulo,
    required this.mensagem,
    required this.textoBotao,
    required this.onPressed,
  });

  final IconData icon;
  final String titulo;
  final String mensagem;
  final String textoBotao;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 64, color: colorScheme.primary),
              const SizedBox(height: 20),
              Text(
                titulo,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                mensagem,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.tonalIcon(
                onPressed: onPressed,
                icon: const Icon(Icons.refresh),
                label: Text(textoBotao),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
