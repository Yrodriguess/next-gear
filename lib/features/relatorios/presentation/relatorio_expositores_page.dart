import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../auth/presentation/usuario_providers.dart';
import '../../clientes/domain/cliente.dart';
import '../../clientes/presentation/cliente_providers.dart';
import '../../expositores/domain/expositor_fisico.dart';
import '../../expositores/domain/expositor_movimentacao.dart';
import '../../expositores/presentation/expositor_detail_page.dart';
import '../../expositores/presentation/expositor_providers.dart';
import '../../expositores/presentation/expositor_status_ui.dart';
import 'relatorios_ui.dart';

enum _LocalFiltro { todos, central, cliente, manutencao, inconsistente }
enum _TempoFiltro { todos, ate30, de31a90, acima90, semData }
enum _Ordem { numero, cliente, modelo, status, maisTempo }

class RelatorioExpositoresPage extends ConsumerStatefulWidget {
  const RelatorioExpositoresPage({super.key});

  @override
  ConsumerState<RelatorioExpositoresPage> createState() =>
      _RelatorioExpositoresPageState();
}

class _RelatorioExpositoresPageState
    extends ConsumerState<RelatorioExpositoresPage> {
  final _buscaController = TextEditingController();
  ExpositorStatus? _status;
  String? _modeloId;
  String? _clienteId;
  _LocalFiltro _local = _LocalFiltro.todos;
  _TempoFiltro _tempo = _TempoFiltro.todos;
  _Ordem _ordem = _Ordem.numero;
  int _limite = 50;

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  void _recarregar() {
    ref.invalidate(expositoresFisicosListProvider);
    ref.invalidate(expositorMovimentacoesRelatorioProvider);
    ref.invalidate(clientesListProvider);
    ref.invalidate(usuariosListProvider);
  }

  void _limparFiltros() {
    setState(() {
      _buscaController.clear();
      _status = null;
      _modeloId = null;
      _clienteId = null;
      _local = _LocalFiltro.todos;
      _tempo = _TempoFiltro.todos;
      _ordem = _Ordem.numero;
      _limite = 50;
    });
  }

  void _abrirExpositor(String? id) {
    if (id == null || id.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ExpositorDetailPage(expositorId: id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final expositoresAsync = ref.watch(expositoresFisicosListProvider);
    final movimentosAsync = ref.watch(expositorMovimentacoesRelatorioProvider);
    final clientesAsync = ref.watch(clientesListProvider);
    final usuariosAsync = ref.watch(usuariosListProvider);

    if (expositoresAsync.hasError ||
        movimentosAsync.hasError ||
        clientesAsync.hasError ||
        usuariosAsync.hasError) {
      return RelatorioErrorState(onRetry: _recarregar);
    }
    if ((expositoresAsync.isLoading && !expositoresAsync.hasValue) ||
        (movimentosAsync.isLoading && !movimentosAsync.hasValue) ||
        (clientesAsync.isLoading && !clientesAsync.hasValue) ||
        (usuariosAsync.isLoading && !usuariosAsync.hasValue)) {
      return const RelatorioLoading();
    }

    final expositores = expositoresAsync.value;
    final movimentos = movimentosAsync.value;
    final clientes = clientesAsync.value;
    final usuarios = usuariosAsync.value;
    if (expositores == null ||
        movimentos == null ||
        clientes == null ||
        usuarios == null) {
      return const RelatorioLoading();
    }

    final clientePorId = {
      for (final cliente in clientes)
        if (cliente.id != null) cliente.id!: cliente,
    };
    final nomeClientePorId = {
      for (final cliente in clientes)
        if (cliente.id != null) cliente.id!: _nomeCliente(cliente),
    };
    final usuarioPorId = {for (final usuario in usuarios) usuario.uid: usuario};
    final ultimoMovimentoPorExpositor = <String, ExpositorMovimentacao>{};
    for (final movimento in movimentos) {
      ultimoMovimentoPorExpositor.putIfAbsent(
        movimento.expositorId,
            () => movimento,
      );
    }

    final todas = expositores.map((expositor) {
      final clienteRelacionadoId = expositor.status == ExpositorStatus.reservado
          ? expositor.clienteReservadoId
          : expositor.clienteAtualId;
      final cliente = clienteRelacionadoId == null
          ? null
          : clientePorId[clienteRelacionadoId];
      final vendedorId = cliente?.vendedorResponsavelId;
      final vendedor = vendedorId == null ? null : usuarioPorId[vendedorId];
      final ultimoMovimento = expositor.id == null
          ? null
          : ultimoMovimentoPorExpositor[expositor.id];
      final dataReferencia = ultimoMovimento?.timestamp ??
          _dataReferenciaDoExpositor(expositor);

      return _Linha(
        id: expositor.id,
        numero: expositor.numero,
        numeroSerie: expositor.numeroSerieFabricante,
        modeloId: expositor.modeloId,
        modeloNome: expositor.modeloNome,
        fotoUrl: expositor.fotoUrl,
        clienteId: clienteRelacionadoId,
        cliente: clienteRelacionadoId == null
            ? '—'
            : cliente == null
            ? 'Cliente não localizado'
            : _nomeCliente(cliente),
        vendedor: vendedorId == null
            ? '—'
            : vendedor?.nome ?? 'Vendedor não localizado',
        status: expositor.status,
        conservacao: expositor.estadoConservacao,
        localAtual: expositor.localAtual,
        localizacao: _localizacaoLabel(expositor),
        proximaVisitaEm: cliente?.proximaVisitaEm,
        dataReferencia: dataReferencia,
        dias: _diasDesde(dataReferencia),
        ultimoMovimento: ultimoMovimento,
        inconsistencias: _detectarInconsistencias(
          expositor,
          clienteLocalizado: cliente != null,
          dataReferencia: dataReferencia,
        ),
      );
    }).toList();

    final modelos = <String, String>{};
    for (final linha in todas) {
      modelos[linha.modeloId] = linha.modeloNome;
    }
    final opcoesModelos = modelos.entries
        .map((item) => _Opcao(id: item.key, label: item.value))
        .toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    final opcoesClientes = clientes
        .where((cliente) => cliente.id != null)
        .map((cliente) => _Opcao(id: cliente.id!, label: _nomeCliente(cliente)))
        .toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

    final query = _buscaController.text.trim().toLowerCase();
    final filtradas = todas.where((linha) {
      if (_status != null && linha.status != _status) return false;
      if (_modeloId != null && linha.modeloId != _modeloId) return false;
      if (_clienteId != null && linha.clienteId != _clienteId) return false;
      if (!_filtraLocal(linha, _local)) return false;
      if (!_filtraTempo(linha, _tempo)) return false;
      if (query.isEmpty) return true;
      return linha.numero.toLowerCase().contains(query) ||
          (linha.numeroSerie ?? '').toLowerCase().contains(query) ||
          linha.modeloNome.toLowerCase().contains(query) ||
          linha.cliente.toLowerCase().contains(query) ||
          linha.vendedor.toLowerCase().contains(query) ||
          statusLabel(linha.status).toLowerCase().contains(query);
    }).toList();
    _ordenar(filtradas, _ordem);

    final ativos = todas.where(
          (linha) => linha.status != ExpositorStatus.descartado &&
          linha.status != ExpositorStatus.perdido,
    ).length;
    final instalados = todas
        .where((linha) => linha.status == ExpositorStatus.instalado)
        .length;
    final disponiveis = todas
        .where((linha) => linha.status == ExpositorStatus.disponivel)
        .length;
    final taxaUtilizacao = ativos == 0 ? 0.0 : instalados / ativos * 100;
    final porStatus = <ExpositorStatus, int>{
      for (final status in ExpositorStatus.values) status: 0,
    };
    for (final linha in todas) {
      porStatus[linha.status] = (porStatus[linha.status] ?? 0) + 1;
    }

    final exibidas = filtradas.take(_limite).toList();
    final filtrosAtivos = query.isNotEmpty ||
        _status != null ||
        _modeloId != null ||
        _clienteId != null ||
        _local != _LocalFiltro.todos ||
        _tempo != _TempoFiltro.todos ||
        _ordem != _Ordem.numero;

    return SingleChildScrollView(
      child: RelatorioPageBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RelatorioIntro(
              title: 'Gestão de expositores',
              subtitle:
              'Controle localização, disponibilidade, conservação e pendências dos ativos físicos.',
              icon: Icons.view_in_ar_outlined,
              action: OutlinedButton.icon(
                onPressed: _recarregar,
                icon: const Icon(Icons.refresh),
                label: const Text('Atualizar'),
              ),
            ),
            const SizedBox(height: 20),
            RelatorioMetricsGrid(
              children: [
                RelatorioMetricCard(
                  label: 'Ativos operacionais',
                  value: '$ativos',
                  hint: '${todas.length} cadastrados no inventário',
                  icon: Icons.inventory_2_outlined,
                  color: Colors.lightBlue,
                ),
                RelatorioMetricCard(
                  label: 'Instalados em clientes',
                  value: '$instalados',
                  hint: 'Contados pelo status operacional',
                  icon: Icons.storefront_outlined,
                  color: Colors.green,
                ),
                RelatorioMetricCard(
                  label: 'Disponíveis',
                  value: '$disponiveis',
                  hint: 'Prontos para uma nova instalação',
                  icon: Icons.warehouse_outlined,
                  color: disponiveis == 0 ? Colors.orange : Colors.green,
                ),
                RelatorioMetricCard(
                  label: 'Taxa de utilização',
                  value: _percentual(taxaUtilizacao),
                  hint: 'Instalados sobre ativos operacionais',
                  icon: Icons.pie_chart_outline,
                  color: Colors.teal,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _StatusResumo(
              porStatus: porStatus,
              selecionado: _status,
              onSelected: (status) => setState(() {
                _status = _status == status ? null : status;
                _limite = 50;
              }),
            ),
            const SizedBox(height: 16),
            _Alertas(linhas: todas),
            const SizedBox(height: 16),
            _Filtros(
              buscaController: _buscaController,
              modelos: opcoesModelos,
              clientes: opcoesClientes,
              modeloId: _modeloId,
              clienteId: _clienteId,
              local: _local,
              tempo: _tempo,
              ordem: _ordem,
              resultados: filtradas.length,
              onBusca: (_) => setState(() => _limite = 50),
              onModelo: (value) => setState(() {
                _modeloId = value;
                _limite = 50;
              }),
              onCliente: (value) => setState(() {
                _clienteId = value;
                _limite = 50;
              }),
              onLocal: (value) => setState(() {
                _local = value;
                _limite = 50;
              }),
              onTempo: (value) => setState(() {
                _tempo = value;
                _limite = 50;
              }),
              onOrdem: (value) => setState(() {
                _ordem = value;
                _limite = 50;
              }),
              onClear: filtrosAtivos ? _limparFiltros : null,
            ),
            const SizedBox(height: 16),
            RelatorioSectionCard(
              title: 'Localização dos expositores',
              subtitle: filtradas.isEmpty
                  ? 'Nenhum resultado encontrado'
                  : 'Mostrando ${exibidas.length} de ${filtradas.length} expositores',
              child: filtradas.isEmpty
                  ? RelatorioEmptyState(
                icon: Icons.view_in_ar_outlined,
                title: expositores.isEmpty
                    ? 'Nenhum expositor cadastrado'
                    : 'Nenhum expositor encontrado',
                message: expositores.isEmpty
                    ? 'Cadastre os ativos para acompanhar localização e disponibilidade.'
                    : 'Altere ou limpe os filtros para ampliar os resultados.',
                action: expositores.isEmpty
                    ? null
                    : TextButton.icon(
                  onPressed: _limparFiltros,
                  icon: const Icon(Icons.filter_alt_off_outlined),
                  label: const Text('Limpar filtros'),
                ),
              )
                  : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Resultado(
                    linhas: exibidas,
                    onAbrir: _abrirExpositor,
                  ),
                  if (exibidas.length < filtradas.length) ...[
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.center,
                      child: OutlinedButton.icon(
                        onPressed: () => setState(() => _limite += 50),
                        icon: const Icon(Icons.expand_more),
                        label: const Text('Mostrar mais'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            RelatorioSectionCard(
              title: 'Movimentações recentes',
              subtitle: 'Últimos eventos registrados no controle patrimonial',
              child: _Movimentacoes(
                movimentacoes: movimentos,
                numeroPorId: {
                  for (final expositor in expositores)
                    if (expositor.id != null) expositor.id!: expositor.numero,
                },
                clientePorId: nomeClientePorId,
                usuarioPorId: {
                  for (final usuario in usuarios) usuario.uid: usuario.nome,
                },
                onAbrir: _abrirExpositor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Linha {
  final String? id;
  final String numero;
  final String? numeroSerie;
  final String modeloId;
  final String modeloNome;
  final String? fotoUrl;
  final String? clienteId;
  final String cliente;
  final String vendedor;
  final ExpositorStatus status;
  final EstadoConservacao conservacao;
  final String localAtual;
  final String localizacao;
  final DateTime? proximaVisitaEm;
  final DateTime? dataReferencia;
  final int? dias;
  final ExpositorMovimentacao? ultimoMovimento;
  final List<String> inconsistencias;

  const _Linha({
    required this.id,
    required this.numero,
    required this.numeroSerie,
    required this.modeloId,
    required this.modeloNome,
    required this.fotoUrl,
    required this.clienteId,
    required this.cliente,
    required this.vendedor,
    required this.status,
    required this.conservacao,
    required this.localAtual,
    required this.localizacao,
    required this.proximaVisitaEm,
    required this.dataReferencia,
    required this.dias,
    required this.ultimoMovimento,
    required this.inconsistencias,
  });
}

class _Opcao {
  final String id;
  final String label;

  const _Opcao({required this.id, required this.label});
}

class _Filtros extends StatelessWidget {
  final TextEditingController buscaController;
  final List<_Opcao> modelos;
  final List<_Opcao> clientes;
  final String? modeloId;
  final String? clienteId;
  final _LocalFiltro local;
  final _TempoFiltro tempo;
  final _Ordem ordem;
  final int resultados;
  final ValueChanged<String> onBusca;
  final ValueChanged<String?> onModelo;
  final ValueChanged<String?> onCliente;
  final ValueChanged<_LocalFiltro> onLocal;
  final ValueChanged<_TempoFiltro> onTempo;
  final ValueChanged<_Ordem> onOrdem;
  final VoidCallback? onClear;

  const _Filtros({
    required this.buscaController,
    required this.modelos,
    required this.clientes,
    required this.modeloId,
    required this.clienteId,
    required this.local,
    required this.tempo,
    required this.ordem,
    required this.resultados,
    required this.onBusca,
    required this.onModelo,
    required this.onCliente,
    required this.onLocal,
    required this.onTempo,
    required this.onOrdem,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return RelatorioSectionCard(
      title: 'Filtros',
      subtitle: '$resultados expositores encontrados',
      trailing: onClear == null
          ? null
          : TextButton.icon(
        onPressed: onClear,
        icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
        label: const Text('Limpar'),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final largura = constraints.maxWidth;
          final campo = largura >= 1060
              ? (largura - 24) / 3
              : largura >= 680
              ? (largura - 12) / 2
              : largura;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: campo,
                child: RelatorioSearchField(
                  controller: buscaController,
                  hint: 'Patrimônio, série, modelo, cliente ou vendedor',
                  onChanged: onBusca,
                ),
              ),
              SizedBox(
                width: campo,
                child: _DropdownId(
                  key: ValueKey('modelo_${modeloId ?? 'todos'}'),
                  label: 'Modelo',
                  icon: Icons.category_outlined,
                  allLabel: 'Todos os modelos',
                  value: modeloId,
                  options: modelos,
                  onChanged: onModelo,
                ),
              ),
              SizedBox(
                width: campo,
                child: _DropdownId(
                  key: ValueKey('cliente_${clienteId ?? 'todos'}'),
                  label: 'Cliente atual ou reservado',
                  icon: Icons.storefront_outlined,
                  allLabel: 'Todos os clientes',
                  value: clienteId,
                  options: clientes,
                  onChanged: onCliente,
                ),
              ),
              SizedBox(
                width: campo,
                child: DropdownButtonFormField<_LocalFiltro>(
                  key: ValueKey('local_${local.name}'),
                  initialValue: local,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Localização',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                  items: _LocalFiltro.values
                      .map(
                        (item) => DropdownMenuItem(
                      value: item,
                      child: Text(_localFiltroLabel(item)),
                    ),
                  )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) onLocal(value);
                  },
                ),
              ),
              SizedBox(
                width: campo,
                child: DropdownButtonFormField<_TempoFiltro>(
                  key: ValueKey('tempo_${tempo.name}'),
                  initialValue: tempo,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Tempo na situação atual',
                    prefixIcon: Icon(Icons.schedule_outlined),
                  ),
                  items: _TempoFiltro.values
                      .map(
                        (item) => DropdownMenuItem(
                      value: item,
                      child: Text(_tempoFiltroLabel(item)),
                    ),
                  )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) onTempo(value);
                  },
                ),
              ),
              SizedBox(
                width: campo,
                child: DropdownButtonFormField<_Ordem>(
                  key: ValueKey('ordem_${ordem.name}'),
                  initialValue: ordem,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Ordenar por',
                    prefixIcon: Icon(Icons.sort),
                  ),
                  items: _Ordem.values
                      .map(
                        (item) => DropdownMenuItem(
                      value: item,
                      child: Text(_ordemLabel(item)),
                    ),
                  )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) onOrdem(value);
                  },
                ),
              ),
              if (largura < 680 && onClear != null)
                SizedBox(
                  width: largura,
                  child: OutlinedButton.icon(
                    onPressed: onClear,
                    icon: const Icon(Icons.filter_alt_off_outlined),
                    label: const Text('Limpar filtros'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DropdownId extends StatelessWidget {
  final String label;
  final IconData icon;
  final String allLabel;
  final String? value;
  final List<_Opcao> options;
  final ValueChanged<String?> onChanged;

  const _DropdownId({
    super.key,
    required this.label,
    required this.icon,
    required this.allLabel,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value ?? '',
      isExpanded: true,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      items: [
        DropdownMenuItem(value: '', child: Text(allLabel)),
        ...options.map(
              (item) => DropdownMenuItem(
            value: item.id,
            child: Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
      onChanged: (selected) =>
          onChanged(selected == null || selected.isEmpty ? null : selected),
    );
  }
}

class _StatusResumo extends StatelessWidget {
  final Map<ExpositorStatus, int> porStatus;
  final ExpositorStatus? selecionado;
  final ValueChanged<ExpositorStatus> onSelected;

  const _StatusResumo({
    required this.porStatus,
    required this.selecionado,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return RelatorioSectionCard(
      title: 'Distribuição por status',
      subtitle: 'Selecione um status para filtrar o detalhamento',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: ExpositorStatus.values.map((status) {
          final color = statusColor(status);
          return FilterChip(
            selected: selecionado == status,
            onSelected: (_) => onSelected(status),
            avatar: Icon(statusIcon(status), size: 17, color: color),
            label: Text('${statusLabel(status)} · ${porStatus[status] ?? 0}'),
          );
        }).toList(),
      ),
    );
  }
}

class _Alertas extends StatelessWidget {
  final List<_Linha> linhas;

  const _Alertas({required this.linhas});

  @override
  Widget build(BuildContext context) {
    final inconsistentes =
        linhas.where((linha) => linha.inconsistencias.isNotEmpty).length;
    final reservasAntigas = linhas.where(
          (linha) => linha.status == ExpositorStatus.reservado &&
          (linha.dias ?? -1) > 7,
    ).length;
    final manutencoesAntigas = linhas.where(
          (linha) => linha.status == ExpositorStatus.manutencao &&
          (linha.dias ?? -1) > 15,
    ).length;
    final recolhidos = linhas.where(
          (linha) => linha.status == ExpositorStatus.recolhido &&
          (linha.dias ?? -1) > 3,
    ).length;
    final semAgenda = linhas.where(
          (linha) => linha.status == ExpositorStatus.instalado &&
          linha.proximaVisitaEm == null,
    ).length;

    final alertas = <_AlertaInfo>[
      if (inconsistentes > 0)
        _AlertaInfo(
          icon: Icons.sync_problem,
          title: '$inconsistentes inconsistências de vínculo',
          message: 'Status, cliente ou localização precisam ser conferidos.',
          color: Colors.red,
        ),
      if (reservasAntigas > 0)
        _AlertaInfo(
          icon: Icons.bookmark_border,
          title: '$reservasAntigas reservas acima de 7 dias',
          message: 'Confirme a instalação ou libere os expositores.',
          color: Colors.orange,
        ),
      if (manutencoesAntigas > 0)
        _AlertaInfo(
          icon: Icons.build_outlined,
          title: '$manutencoesAntigas manutenções acima de 15 dias',
          message: 'Verifique o prazo de retorno dos equipamentos.',
          color: Colors.orange,
        ),
      if (recolhidos > 0)
        _AlertaInfo(
          icon: Icons.fact_check_outlined,
          title: '$recolhidos recolhidos aguardando conferência',
          message: 'Estão parados no estoque há mais de 3 dias.',
          color: Colors.orange,
        ),
      if (semAgenda > 0)
        _AlertaInfo(
          icon: Icons.event_busy_outlined,
          title: '$semAgenda instalados sem próxima visita',
          message: 'Os clientes precisam de acompanhamento agendado.',
          color: Colors.orange,
        ),
    ];

    return RelatorioSectionCard(
      title: 'Alertas operacionais',
      subtitle: 'Pendências que merecem acompanhamento',
      child: alertas.isEmpty
          ? const _AlertaLinha(
        info: _AlertaInfo(
          icon: Icons.verified_outlined,
          title: 'Nenhuma pendência crítica',
          message: 'Os vínculos e prazos estão consistentes.',
          color: Colors.green,
        ),
      )
          : Column(
        children: [
          for (var i = 0; i < alertas.length; i++) ...[
            _AlertaLinha(info: alertas[i]),
            if (i != alertas.length - 1) const Divider(height: 24),
          ],
        ],
      ),
    );
  }
}

class _AlertaInfo {
  final IconData icon;
  final String title;
  final String message;
  final Color color;

  const _AlertaInfo({
    required this.icon,
    required this.title,
    required this.message,
    required this.color,
  });
}

class _AlertaLinha extends StatelessWidget {
  final _AlertaInfo info;

  const _AlertaLinha({required this.info});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: info.color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(info.icon, color: info.color, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(info.title,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(info.message, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _Resultado extends StatelessWidget {
  final List<_Linha> linhas;
  final ValueChanged<String?> onAbrir;

  const _Resultado({required this.linhas, required this.onAbrir});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 800) {
          return Column(
            children: [
              for (var i = 0; i < linhas.length; i++) ...[
                _MobileCard(
                  linha: linhas[i],
                  onAbrir: () => onAbrir(linhas[i].id),
                ),
                if (i != linhas.length - 1) const SizedBox(height: 10),
              ],
            ],
          );
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Expositor')),
                DataColumn(label: Text('Modelo')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Localização')),
                DataColumn(label: Text('Cliente / reserva')),
                DataColumn(label: Text('Vendedor')),
                DataColumn(label: Text('Conservação')),
                DataColumn(label: Text('Próxima visita')),
                DataColumn(label: Text('Tempo atual'), numeric: true),
                DataColumn(label: Text('Última movimentação')),
              ],
              rows: linhas.map((linha) {
                return DataRow(
                  color: linha.inconsistencias.isEmpty
                      ? null
                      : WidgetStatePropertyAll(
                    Colors.red.withValues(alpha: .04),
                  ),
                  cells: [
                    DataCell(
                      SizedBox(
                        width: 165,
                        child: Row(
                          children: [
                            _Avatar(fotoUrl: linha.fotoUrl, size: 34),
                            const SizedBox(width: 9),
                            Expanded(
                              child: TextButton(
                                onPressed: linha.id == null
                                    ? null
                                    : () => onAbrir(linha.id),
                                style: TextButton.styleFrom(
                                  alignment: Alignment.centerLeft,
                                  padding: EdgeInsets.zero,
                                ),
                                child: Text(
                                  linha.numero,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    DataCell(Text(linha.modeloNome)),
                    DataCell(StatusChip(status: linha.status)),
                    DataCell(Text(linha.localizacao)),
                    DataCell(
                      SizedBox(
                        width: 190,
                        child: Text(
                          linha.cliente,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(
                      SizedBox(
                        width: 145,
                        child: Text(
                          linha.vendedor,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(Text(_conservacaoLabel(linha.conservacao))),
                    DataCell(_ProximaVisita(data: linha.proximaVisitaEm)),
                    DataCell(Text(_tempoLabel(linha))),
                    DataCell(
                      SizedBox(
                        width: 175,
                        child: Text(
                          _ultimoMovimentoLabel(linha),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}

class _MobileCard extends StatelessWidget {
  final _Linha linha;
  final VoidCallback onAbrir;

  const _MobileCard({required this.linha, required this.onAbrir});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: linha.inconsistencias.isEmpty
              ? theme.dividerColor
              : Colors.red.withValues(alpha: .5),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        leading: _Avatar(fotoUrl: linha.fotoUrl, size: 42),
        title: Text(
          linha.numero,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(linha.modeloNome),
              const SizedBox(height: 6),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusChip(status: linha.status),
                  if (linha.inconsistencias.isNotEmpty)
                    const RelatorioStatusPill(
                      label: 'Inconsistência',
                      color: Colors.red,
                      icon: Icons.sync_problem,
                    ),
                ],
              ),
            ],
          ),
        ),
        children: [
          const Divider(height: 18),
          _InfoLinha(label: 'Localização', value: linha.localizacao),
          _InfoLinha(label: 'Cliente / reserva', value: linha.cliente),
          _InfoLinha(label: 'Vendedor', value: linha.vendedor),
          _InfoLinha(
            label: 'Conservação',
            value: _conservacaoLabel(linha.conservacao),
          ),
          _InfoLinha(label: 'Tempo atual', value: _tempoLabel(linha)),
          _InfoLinha(
            label: 'Próxima visita',
            value: _dataVisitaLabel(linha.proximaVisitaEm),
          ),
          _InfoLinha(
            label: 'Última movimentação',
            value: _ultimoMovimentoLabel(linha),
          ),
          if (linha.numeroSerie?.isNotEmpty == true)
            _InfoLinha(label: 'Número de série', value: linha.numeroSerie!),
          if (linha.inconsistencias.isNotEmpty) ...[
            const Divider(height: 22),
            Text(
              'Verificar cadastro',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
            for (final problema in linha.inconsistencias)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('• $problema'),
              ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: linha.id == null ? null : onAbrir,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Ver expositor'),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoLinha extends StatelessWidget {
  final String label;
  final String value;

  const _InfoLinha({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? fotoUrl;
  final double size;

  const _Avatar({required this.fotoUrl, required this.size});

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.view_in_ar_outlined, size: size * .52),
    );
    final url = fotoUrl?.trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: url == null || url.isEmpty
          ? fallback
          : Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

class _ProximaVisita extends StatelessWidget {
  final DateTime? data;

  const _ProximaVisita({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data == null) {
      return const RelatorioStatusPill(
        label: 'Sem agenda',
        color: Colors.orange,
        icon: Icons.event_note_outlined,
      );
    }
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final prevista = DateTime(data!.year, data!.month, data!.day);
    final atrasada = prevista.isBefore(hoje);
    final hojeMesmo = prevista.isAtSameMomentAs(hoje);
    return RelatorioStatusPill(
      label: hojeMesmo ? 'Hoje' : DateFormat('dd/MM/yyyy').format(data!),
      color: atrasada
          ? Colors.red
          : hojeMesmo
          ? Colors.green
          : Colors.blueGrey,
      icon: atrasada
          ? Icons.event_busy_outlined
          : hojeMesmo
          ? Icons.today_outlined
          : Icons.event_outlined,
    );
  }
}

class _Movimentacoes extends StatelessWidget {
  final List<ExpositorMovimentacao> movimentacoes;
  final Map<String, String> numeroPorId;
  final Map<String, String> clientePorId;
  final Map<String, String> usuarioPorId;
  final ValueChanged<String?> onAbrir;

  const _Movimentacoes({
    required this.movimentacoes,
    required this.numeroPorId,
    required this.clientePorId,
    required this.usuarioPorId,
    required this.onAbrir,
  });

  @override
  Widget build(BuildContext context) {
    if (movimentacoes.isEmpty) {
      return const RelatorioEmptyState(
        icon: Icons.history,
        title: 'Nenhuma movimentação registrada',
        message: 'Os eventos dos expositores aparecerão aqui.',
      );
    }

    final exibidas = movimentacoes.take(20).toList();
    return Column(
      children: [
        for (var i = 0; i < exibidas.length; i++) ...[
          _MovimentoLinha(
            movimento: exibidas[i],
            codigo:
            numeroPorId[exibidas[i].expositorId] ?? exibidas[i].expositorId,
            usuario: usuarioPorId[exibidas[i].usuarioId] ??
                'Usuário não localizado',
            origem: _localMovimentoLabel(exibidas[i].origem, clientePorId),
            destino: _localMovimentoLabel(exibidas[i].destino, clientePorId),
            onTap: () => onAbrir(exibidas[i].expositorId),
          ),
          if (i != exibidas.length - 1) const Divider(height: 18),
        ],
      ],
    );
  }
}

class _MovimentoLinha extends StatelessWidget {
  final ExpositorMovimentacao movimento;
  final String codigo;
  final String usuario;
  final String origem;
  final String destino;
  final VoidCallback onTap;

  const _MovimentoLinha({
    required this.movimento,
    required this.codigo,
    required this.usuario,
    required this.origem,
    required this.destino,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = _tipoColor(movimento.tipo);
    final data = movimento.timestamp == null
        ? 'Data não informada'
        : DateFormat('dd/MM/yyyy HH:mm').format(movimento.timestamp!);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: .12),
        foregroundColor: color,
        child: Icon(_tipoIcon(movimento.tipo), size: 19),
      ),
      title: Text(
        '$codigo · ${_tipoLabel(movimento.tipo)}',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 3),
          Text('$data · $usuario'),
          if (origem != '—' || destino != '—') Text('$origem → $destino'),
          if (movimento.observacao?.trim().isNotEmpty == true)
            Text(
              movimento.observacao!.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

List<String> _detectarInconsistencias(
    ExpositorFisico expositor, {
      required bool clienteLocalizado,
      required DateTime? dataReferencia,
    }) {
  final problemas = <String>[];
  final clienteDoLocal = LocalExpositor.extrairClienteId(expositor.localAtual);

  if (expositor.status == ExpositorStatus.instalado) {
    if (expositor.clienteAtualId == null) {
      problemas.add('Status instalado sem cliente atual.');
    }
    if (clienteDoLocal != expositor.clienteAtualId) {
      problemas.add('Localização não corresponde ao cliente atual.');
    }
  } else if (expositor.clienteAtualId != null) {
    problemas.add('Possui cliente atual, mas o status não é instalado.');
  }

  if (expositor.status == ExpositorStatus.reservado) {
    if (expositor.clienteReservadoId == null) {
      problemas.add('Status reservado sem cliente da reserva.');
    }
  } else if (expositor.clienteReservadoId != null) {
    problemas.add('Possui cliente reservado, mas o status não é reservado.');
  }
  if (expositor.status == ExpositorStatus.manutencao &&
      expositor.localAtual != LocalExpositor.manutencao) {
    problemas.add('Em manutenção fora do local de manutenção.');
  }
  if (expositor.status == ExpositorStatus.disponivel &&
      expositor.localAtual != LocalExpositor.central) {
    problemas.add('Disponível fora do estoque central.');
  }
  if ((expositor.clienteAtualId != null ||
      expositor.clienteReservadoId != null) &&
      !clienteLocalizado) {
    problemas.add('Cliente vinculado não foi localizado.');
  }
  if (dataReferencia != null && dataReferencia.isAfter(DateTime.now())) {
    problemas.add('Data da situação atual está no futuro.');
  }
  return problemas;
}

DateTime? _dataReferenciaDoExpositor(ExpositorFisico expositor) {
  return switch (expositor.status) {
    ExpositorStatus.instalado =>
    expositor.dataInstalacao ?? expositor.updatedAt ?? expositor.createdAt,
    ExpositorStatus.reservado =>
    expositor.dataReserva ?? expositor.updatedAt ?? expositor.createdAt,
    _ => expositor.updatedAt ?? expositor.createdAt,
  };
}

int? _diasDesde(DateTime? data) {
  if (data == null) return null;
  final agora = DateTime.now();
  final hoje = DateTime(agora.year, agora.month, agora.day);
  final referencia = DateTime(data.year, data.month, data.day);
  if (referencia.isAfter(hoje)) return null;
  return hoje.difference(referencia).inDays;
}

bool _filtraLocal(_Linha linha, _LocalFiltro filtro) => switch (filtro) {
  _LocalFiltro.todos => true,
  _LocalFiltro.central => linha.localAtual == LocalExpositor.central,
  _LocalFiltro.cliente =>
  LocalExpositor.extrairClienteId(linha.localAtual) != null,
  _LocalFiltro.manutencao =>
  linha.localAtual == LocalExpositor.manutencao,
  _LocalFiltro.inconsistente => linha.inconsistencias.isNotEmpty,
};

bool _filtraTempo(_Linha linha, _TempoFiltro filtro) {
  final dias = linha.dias;
  return switch (filtro) {
    _TempoFiltro.todos => true,
    _TempoFiltro.ate30 => dias != null && dias <= 30,
    _TempoFiltro.de31a90 => dias != null && dias >= 31 && dias <= 90,
    _TempoFiltro.acima90 => dias != null && dias > 90,
    _TempoFiltro.semData => dias == null,
  };
}

void _ordenar(List<_Linha> linhas, _Ordem ordem) {
  switch (ordem) {
    case _Ordem.numero:
      linhas.sort((a, b) => _compararNumeroNatural(a.numero, b.numero));
      break;
    case _Ordem.cliente:
      linhas.sort(
            (a, b) => a.cliente.toLowerCase().compareTo(b.cliente.toLowerCase()),
      );
      break;
    case _Ordem.modelo:
      linhas.sort(
            (a, b) =>
            a.modeloNome.toLowerCase().compareTo(b.modeloNome.toLowerCase()),
      );
      break;
    case _Ordem.status:
      linhas.sort(
            (a, b) => statusLabel(a.status).compareTo(statusLabel(b.status)),
      );
      break;
    case _Ordem.maisTempo:
      linhas.sort((a, b) => (b.dias ?? -1).compareTo(a.dias ?? -1));
      break;
  }
}

int _compararNumeroNatural(String a, String b) {
  final regex = RegExp(r'^(.*?)(\d+)$');
  final matchA = regex.firstMatch(a);
  final matchB = regex.firstMatch(b);
  if (matchA == null || matchB == null) return a.compareTo(b);
  final prefixo = matchA.group(1)!.compareTo(matchB.group(1)!);
  if (prefixo != 0) return prefixo;
  final numeroA = int.tryParse(matchA.group(2)!) ?? 0;
  final numeroB = int.tryParse(matchB.group(2)!) ?? 0;
  return numeroA.compareTo(numeroB);
}

String _localizacaoLabel(ExpositorFisico expositor) =>
    switch (expositor.status) {
      ExpositorStatus.instalado => 'No cliente',
      ExpositorStatus.reservado => 'Central · reservado',
      ExpositorStatus.manutencao => 'Manutenção',
      ExpositorStatus.recolhido => 'Central · conferência',
      ExpositorStatus.descartado => 'Descartado',
      ExpositorStatus.perdido => 'Local desconhecido',
      ExpositorStatus.disponivel => 'Estoque central',
    };

String _localFiltroLabel(_LocalFiltro filtro) => switch (filtro) {
  _LocalFiltro.todos => 'Todas as localizações',
  _LocalFiltro.central => 'Estoque central',
  _LocalFiltro.cliente => 'Nos clientes',
  _LocalFiltro.manutencao => 'Em manutenção',
  _LocalFiltro.inconsistente => 'Com inconsistência',
};

String _tempoFiltroLabel(_TempoFiltro filtro) => switch (filtro) {
  _TempoFiltro.todos => 'Qualquer período',
  _TempoFiltro.ate30 => 'Até 30 dias',
  _TempoFiltro.de31a90 => 'De 31 a 90 dias',
  _TempoFiltro.acima90 => 'Acima de 90 dias',
  _TempoFiltro.semData => 'Sem data identificada',
};

String _ordemLabel(_Ordem ordem) => switch (ordem) {
  _Ordem.numero => 'Número patrimonial',
  _Ordem.cliente => 'Cliente A–Z',
  _Ordem.modelo => 'Modelo A–Z',
  _Ordem.status => 'Status',
  _Ordem.maisTempo => 'Mais tempo na situação',
};

String _conservacaoLabel(EstadoConservacao conservacao) =>
    switch (conservacao) {
      EstadoConservacao.novo => 'Novo',
      EstadoConservacao.bom => 'Bom',
      EstadoConservacao.regular => 'Regular',
      EstadoConservacao.ruim => 'Ruim',
    };

String _tempoLabel(_Linha linha) {
  if (linha.dataReferencia == null) return 'Sem data';
  if (linha.dias == null) return 'Data futura';
  if (linha.dias == 0) return 'Hoje';
  return '${linha.dias} ${linha.dias == 1 ? 'dia' : 'dias'}';
}

String _dataVisitaLabel(DateTime? data) =>
    data == null ? 'Sem agendamento' : DateFormat('dd/MM/yyyy').format(data);

String _ultimoMovimentoLabel(_Linha linha) {
  final movimento = linha.ultimoMovimento;
  if (movimento == null) return 'Sem movimentação localizada';
  final data = movimento.timestamp == null
      ? 'sem data'
      : DateFormat('dd/MM/yyyy').format(movimento.timestamp!);
  return '${_tipoLabel(movimento.tipo)} · $data';
}

String _localMovimentoLabel(
    String? local,
    Map<String, String> clientePorId,
    ) {
  if (local == null || local.isEmpty) return '—';
  if (local == LocalExpositor.central) return 'Estoque central';
  if (local == LocalExpositor.manutencao) return 'Manutenção';
  final clienteId = LocalExpositor.extrairClienteId(local);
  if (clienteId != null) {
    return clientePorId[clienteId] ?? 'Cliente não localizado';
  }
  return local;
}

String _tipoLabel(TipoMovimentacaoExpositor tipo) => switch (tipo) {
  TipoMovimentacaoExpositor.cadastro => 'Cadastrado',
  TipoMovimentacaoExpositor.instalacao => 'Instalado',
  TipoMovimentacaoExpositor.retirada => 'Retirado',
  TipoMovimentacaoExpositor.transferencia => 'Transferido',
  TipoMovimentacaoExpositor.manutencaoEntrada => 'Enviado à manutenção',
  TipoMovimentacaoExpositor.manutencaoSaida => 'Saiu da manutenção',
  TipoMovimentacaoExpositor.descarte => 'Descartado',
  TipoMovimentacaoExpositor.perda => 'Registrado como perdido',
  TipoMovimentacaoExpositor.conferencia => 'Conferido',
  TipoMovimentacaoExpositor.reserva => 'Reservado',
  TipoMovimentacaoExpositor.cancelamentoReserva => 'Reserva cancelada',
};

IconData _tipoIcon(TipoMovimentacaoExpositor tipo) => switch (tipo) {
  TipoMovimentacaoExpositor.cadastro => Icons.add_circle_outline,
  TipoMovimentacaoExpositor.instalacao => Icons.add_location_alt_outlined,
  TipoMovimentacaoExpositor.retirada => Icons.move_to_inbox_outlined,
  TipoMovimentacaoExpositor.transferencia => Icons.swap_horiz,
  TipoMovimentacaoExpositor.manutencaoEntrada => Icons.build_outlined,
  TipoMovimentacaoExpositor.manutencaoSaida => Icons.build_circle_outlined,
  TipoMovimentacaoExpositor.descarte => Icons.delete_outline,
  TipoMovimentacaoExpositor.perda => Icons.help_outline,
  TipoMovimentacaoExpositor.conferencia => Icons.fact_check_outlined,
  TipoMovimentacaoExpositor.reserva => Icons.bookmark_outline,
  TipoMovimentacaoExpositor.cancelamentoReserva =>
  Icons.bookmark_remove_outlined,
};

Color _tipoColor(TipoMovimentacaoExpositor tipo) => switch (tipo) {
  TipoMovimentacaoExpositor.instalacao => Colors.green,
  TipoMovimentacaoExpositor.manutencaoEntrada => Colors.orange,
  TipoMovimentacaoExpositor.descarte => Colors.grey,
  TipoMovimentacaoExpositor.perda => Colors.red,
  TipoMovimentacaoExpositor.reserva => Colors.lightBlue,
  _ => Colors.blueGrey,
};

String _percentual(double valor) =>
    '${valor.toStringAsFixed(1).replaceAll('.', ',')}%';

String _nomeCliente(Cliente cliente) {
  final fantasia = cliente.nomeFantasia?.trim();
  return fantasia == null || fantasia.isEmpty ? cliente.nome : fantasia;
}
