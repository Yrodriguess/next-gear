import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/current_org_provider.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_providers.dart' hide usuariosListProvider;
import '../../auth/presentation/usuario_providers.dart';
import '../../clientes/domain/cliente.dart';
import '../../clientes/presentation/cliente_providers.dart';
import '../domain/acerto_caixa.dart';
import '../domain/pagamento.dart';
import '../domain/recebivel.dart';
import 'financeiro_providers.dart';
import 'meu_caixa_page.dart';

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _data = DateFormat('dd/MM/yyyy');
String _reais(int centavos) => _moeda.format(centavos / 100);

/// Entrada do menu "Financeiro" — decide o que mostrar de acordo com
/// o papel de quem está logado. Vendedor só vê o próprio caixa, não
/// tem acesso ao painel geral da organização.
class FinanceiroHomePage extends ConsumerWidget {
  const FinanceiroHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usuario = ref.watch(appUserProvider).value;
    if (usuario == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (usuario.role == UserRole.vendedor) {
      return MeuCaixaPage(vendedorId: usuario.uid, vendedorNome: usuario.nome);
    }

    return _FinanceiroDashboard(usuario: usuario);
  }
}

class _FinanceiroDashboard extends ConsumerStatefulWidget {
  final AppUser usuario;
  const _FinanceiroDashboard({required this.usuario});

  @override
  ConsumerState<_FinanceiroDashboard> createState() =>
      _FinanceiroDashboardState();
}

class _FinanceiroDashboardState extends ConsumerState<_FinanceiroDashboard>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _abrirAba(int index) {
    _tabController.animateTo(index);
  }

  void _atualizar(String orgId) {
    ref.invalidate(recebiveisTodosAbertosProvider(orgId));
    ref.invalidate(pagamentosTodosProvider(orgId));
    ref.invalidate(acertosPendentesConfirmacaoProvider(orgId));
    ref.invalidate(clientesListProvider);
    ref.invalidate(usuariosListProvider);
  }

  @override
  Widget build(BuildContext context) {
    final orgId = ref.watch(currentOrgIdProvider);
    if (orgId == null) {
      return const Scaffold(body: Center(child: Text('Sessão inválida.')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Financeiro'),
        actions: [
          IconButton(
            tooltip: 'Atualizar dados',
            onPressed: () => _atualizar(orgId),
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(58),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: const [
                Tab(icon: Icon(Icons.dashboard_outlined), text: 'Painel'),
                Tab(
                  icon: Icon(Icons.account_balance_wallet_outlined),
                  text: 'Contas a receber',
                ),
                Tab(icon: Icon(Icons.history), text: 'Histórico'),
                Tab(
                  icon: Icon(Icons.fact_check_outlined),
                  text: 'Acertos de caixa',
                ),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: TabBarView(
              controller: _tabController,
              children: [
                _PainelTab(
                  orgId: orgId,
                  onAbrirContas: () => _abrirAba(1),
                  onAbrirHistorico: () => _abrirAba(2),
                  onAbrirAcertos: () => _abrirAba(3),
                ),
                _ContasReceberTab(orgId: orgId),
                _HistoricoTab(orgId: orgId),
                _AcertosTab(
                  orgId: orgId,
                  usuarioId: widget.usuario.uid,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Painel ───────────────────────────────────────────────────────────

class _PainelTab extends ConsumerWidget {
  final String orgId;
  final VoidCallback onAbrirContas;
  final VoidCallback onAbrirHistorico;
  final VoidCallback onAbrirAcertos;

  const _PainelTab({
    required this.orgId,
    required this.onAbrirContas,
    required this.onAbrirHistorico,
    required this.onAbrirAcertos,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recebiveisAsync = ref.watch(recebiveisTodosAbertosProvider(orgId));
    final pagamentosAsync = ref.watch(pagamentosTodosProvider(orgId));
    final acertosAsync = ref.watch(acertosPendentesConfirmacaoProvider(orgId));
    final clientesAsync = ref.watch(clientesListProvider);

    if (recebiveisAsync.isLoading ||
        pagamentosAsync.isLoading ||
        acertosAsync.isLoading ||
        clientesAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (recebiveisAsync.hasError ||
        pagamentosAsync.hasError ||
        acertosAsync.hasError ||
        clientesAsync.hasError) {
      return _StateMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Não foi possível carregar o financeiro',
        message: 'Verifique sua conexão e tente atualizar a página.',
        actionLabel: 'Tentar novamente',
        onAction: () {
          ref.invalidate(recebiveisTodosAbertosProvider(orgId));
          ref.invalidate(pagamentosTodosProvider(orgId));
          ref.invalidate(acertosPendentesConfirmacaoProvider(orgId));
          ref.invalidate(clientesListProvider);
        },
      );
    }

    final recebiveis = recebiveisAsync.value ?? const <Recebivel>[];
    final pagamentos = pagamentosAsync.value ?? const <Pagamento>[];
    final acertosPendentes = acertosAsync.value ?? const <AcertoCaixa>[];
    final nomeClientePorId = <String, String>{
      for (final cliente in (clientesAsync.value ?? const <Cliente>[]))
        if (cliente.id != null) cliente.id!: cliente.nome,
    };

    final totalAberto =
    recebiveis.fold<int>(0, (soma, r) => soma + r.saldoEmAbertoCentavos);
    final totalVencido = recebiveis
        .where((r) => r.status == RecebivelStatus.vencido)
        .fold<int>(0, (soma, r) => soma + r.saldoEmAbertoCentavos);

    final agora = DateTime.now();
    final pagamentosNoMes = pagamentos
        .where((p) =>
    p.criadoEm != null &&
        p.criadoEm!.year == agora.year &&
        p.criadoEm!.month == agora.month)
        .toList();
    final recebidoNoMes = pagamentosNoMes.fold<int>(
      0,
          (soma, pagamento) => soma + pagamento.valorTotalCentavos,
    );
    final dinheiroPendente = pagamentos
        .where((p) =>
    p.formaPagamento == FormaPagamento.dinheiro &&
        p.statusRepasse != StatusRepasse.confirmado)
        .fold<int>(0, (soma, p) => soma + p.valorTotalCentavos);

    final vencidos = recebiveis
        .where((r) => r.status == RecebivelStatus.vencido)
        .toList()
      ..sort((a, b) {
        final dataA = a.dataVencimento ?? DateTime(9999);
        final dataB = b.dataVencimento ?? DateTime(9999);
        return dataA.compareTo(dataB);
      });

    final pagamentosRecentes = [...pagamentos]
      ..sort((a, b) {
        final dataA = a.criadoEm ?? DateTime.fromMillisecondsSinceEpoch(0);
        final dataB = b.criadoEm ?? DateTime.fromMillisecondsSinceEpoch(0);
        return dataB.compareTo(dataA);
      });

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _PageIntro(
            title: 'Visão geral',
            subtitle:
            'Acompanhe recebimentos, cobranças vencidas e valores em repasse.',
          ),
          const SizedBox(height: 18),
          _MetricGrid(
            cards: [
              _MetricCard(
                icon: Icons.account_balance_wallet_outlined,
                color: Colors.blue,
                label: 'Total a receber',
                value: _reais(totalAberto),
                helper: '${recebiveis.length} cobrança(s) aberta(s)',
              ),
              _MetricCard(
                icon: Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
                label: 'Vencido',
                value: _reais(totalVencido),
                helper: '${vencidos.length} cobrança(s) atrasada(s)',
              ),
              _MetricCard(
                icon: Icons.trending_up,
                color: Colors.green,
                label: 'Recebido no mês',
                value: _reais(recebidoNoMes),
                helper: '${pagamentosNoMes.length} pagamento(s) no mês',
              ),
              _MetricCard(
                icon: Icons.payments_outlined,
                color: Colors.orange,
                label: 'Dinheiro a repassar',
                value: _reais(dinheiroPendente),
                helper: '${acertosPendentes.length} acerto(s) pendente(s)',
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final cobrancas = _CobrancasPrioritariasCard(
                recebiveis: vencidos.take(4).toList(),
                nomeClientePorId: nomeClientePorId,
                onAbrirContas: onAbrirContas,
              );
              final lateral = Column(
                children: [
                  _PendenciasOperacionaisCard(
                    quantidadeAcertos: acertosPendentes.length,
                    dinheiroPendenteCentavos: dinheiroPendente,
                    onAbrirAcertos: onAbrirAcertos,
                  ),
                  const SizedBox(height: 16),
                  _AtividadeRecenteCard(
                    pagamentos: pagamentosRecentes.take(3).toList(),
                    nomeClientePorId: nomeClientePorId,
                    onAbrirHistorico: onAbrirHistorico,
                  ),
                ],
              );

              if (constraints.maxWidth < 900) {
                return Column(
                  children: [
                    cobrancas,
                    const SizedBox(height: 16),
                    lateral,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: cobrancas),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: lateral),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  final List<Widget> cards;

  const _MetricGrid({required this.cards});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1040
            ? 4
            : constraints.maxWidth >= 560
            ? 2
            : 1;

        return GridView.count(
          crossAxisCount: columns,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: columns == 1 ? 3.2 : 2.25,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: cards,
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String helper;

  const _MetricCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.helper,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    helper,
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
    );
  }
}

class _CobrancasPrioritariasCard extends StatelessWidget {
  final List<Recebivel> recebiveis;
  final Map<String, String> nomeClientePorId;
  final VoidCallback onAbrirContas;

  const _CobrancasPrioritariasCard({
    required this.recebiveis,
    required this.nomeClientePorId,
    required this.onAbrirContas,
  });

  @override
  Widget build(BuildContext context) {
    return _DashboardCard(
      title: 'Cobranças prioritárias',
      subtitle: 'Valores vencidos que precisam de atenção.',
      trailing: TextButton(
        onPressed: onAbrirContas,
        child: const Text('Ver todas'),
      ),
      child: recebiveis.isEmpty
          ? const _CompactEmptyState(
        icon: Icons.task_alt,
        text: 'Nenhuma cobrança vencida.',
      )
          : Column(
        children: [
          for (var index = 0; index < recebiveis.length; index++) ...[
            _CobrancaPrioritariaRow(
              recebivel: recebiveis[index],
              clienteNome:
              nomeClientePorId[recebiveis[index].clienteId] ??
                  'Cliente',
              onReceber: onAbrirContas,
            ),
            if (index != recebiveis.length - 1)
              const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _CobrancaPrioritariaRow extends StatelessWidget {
  final Recebivel recebivel;
  final String clienteNome;
  final VoidCallback onReceber;

  const _CobrancaPrioritariaRow({
    required this.recebivel,
    required this.clienteNome,
    required this.onReceber,
  });

  @override
  Widget build(BuildContext context) {
    final vencimento = recebivel.dataVencimento == null
        ? 'Sem vencimento'
        : _data.format(recebivel.dataVencimento!);

    Widget info() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          clienteNome,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 3),
        Text(
          '${recebivel.numero} • $vencimento',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                info(),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _StatusPill(
                      label: 'Vencido',
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const Spacer(),
                    Text(
                      _reais(recebivel.saldoEmAbertoCentavos),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: onReceber,
                      child: const Text('Receber'),
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Expanded(flex: 3, child: info()),
              const SizedBox(width: 8),
              _StatusPill(
                label: 'Vencido',
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 12),
              Text(
                _reais(recebivel.saldoEmAbertoCentavos),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: onReceber,
                child: const Text('Receber'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PendenciasOperacionaisCard extends StatelessWidget {
  final int quantidadeAcertos;
  final int dinheiroPendenteCentavos;
  final VoidCallback onAbrirAcertos;

  const _PendenciasOperacionaisCard({
    required this.quantidadeAcertos,
    required this.dinheiroPendenteCentavos,
    required this.onAbrirAcertos,
  });

  @override
  Widget build(BuildContext context) {
    return _DashboardCard(
      title: 'Pendências operacionais',
      child: Column(
        children: [
          _ActionRow(
            icon: Icons.pending_actions_outlined,
            color: Colors.orange,
            title: 'Acertos de caixa',
            subtitle: '$quantidadeAcertos aguardando confirmação',
            onTap: onAbrirAcertos,
          ),
          const Divider(height: 1),
          _ActionRow(
            icon: Icons.payments_outlined,
            color: Colors.orange,
            title: 'Dinheiro em mãos',
            subtitle: '${_reais(dinheiroPendenteCentavos)} aguardando repasse',
            onTap: onAbrirAcertos,
          ),
        ],
      ),
    );
  }
}

class _AtividadeRecenteCard extends StatelessWidget {
  final List<Pagamento> pagamentos;
  final Map<String, String> nomeClientePorId;
  final VoidCallback onAbrirHistorico;

  const _AtividadeRecenteCard({
    required this.pagamentos,
    required this.nomeClientePorId,
    required this.onAbrirHistorico,
  });

  @override
  Widget build(BuildContext context) {
    return _DashboardCard(
      title: 'Atividade recente',
      child: pagamentos.isEmpty
          ? const _CompactEmptyState(
        icon: Icons.history,
        text: 'Nenhum pagamento registrado.',
      )
          : Column(
        children: [
          for (var index = 0; index < pagamentos.length; index++) ...[
            _PagamentoRecenteRow(
              pagamento: pagamentos[index],
              clienteNome:
              nomeClientePorId[pagamentos[index].clienteId] ??
                  'Cliente',
              onTap: onAbrirHistorico,
            ),
            if (index != pagamentos.length - 1)
              const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _PagamentoRecenteRow extends StatelessWidget {
  final Pagamento pagamento;
  final String clienteNome;
  final VoidCallback onTap;

  const _PagamentoRecenteRow({
    required this.pagamento,
    required this.clienteNome,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final data = pagamento.criadoEm == null
        ? 'Data não informada'
        : DateFormat('dd/MM/yyyy HH:mm').format(pagamento.criadoEm!);
    final icon = switch (pagamento.formaPagamento) {
      FormaPagamento.dinheiro => Icons.payments_outlined,
      FormaPagamento.pix => Icons.pix,
      FormaPagamento.boleto => Icons.receipt_long_outlined,
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Icon(icon, size: 21, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    clienteNome,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    data,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '+ ${_reais(pagamento.valorTotalCentavos)}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Contas a receber (geral) ───────────────────────────────────────

enum _FiltroRecebivel { todos, vencidos, aVencer }

class _ContasReceberTab extends ConsumerStatefulWidget {
  final String orgId;
  const _ContasReceberTab({required this.orgId});

  @override
  ConsumerState<_ContasReceberTab> createState() => _ContasReceberTabState();
}

class _ContasReceberTabState extends ConsumerState<_ContasReceberTab> {
  final Set<String> _registrando = {};
  final TextEditingController _buscaController = TextEditingController();
  _FiltroRecebivel _filtro = _FiltroRecebivel.todos;

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  Future<void> _registrarRecebimento(Recebivel r, String nomeCliente) async {
    final valorController = TextEditingController(
      text: (r.saldoEmAbertoCentavos / 100)
          .toStringAsFixed(2)
          .replaceAll('.', ','),
    );
    FormaPagamento formaEscolhida = FormaPagamento.boleto;
    String? erroDialogo;

    final resultado = await showDialog<
        ({int valorCentavos, FormaPagamento forma})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final valorDigitado = double.tryParse(
            valorController.text.replaceAll('.', '').replaceAll(',', '.'),
          );
          final valorCentavos = ((valorDigitado ?? 0) * 100).round();
          final saldoRestante = r.saldoEmAbertoCentavos - valorCentavos;

          return AlertDialog(
            title: const Text('Registrar recebimento'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DialogInfoHeader(
                      icon: Icons.account_balance_wallet_outlined,
                      title: nomeCliente,
                      subtitle:
                      '${r.numero} • Em aberto: ${_reais(r.saldoEmAbertoCentavos)}',
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: valorController,
                      autofocus: true,
                      keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Valor recebido',
                        prefixText: 'R\$ ',
                        helperText: 'Pode ser um recebimento total ou parcial.',
                      ),
                      onChanged: (_) {
                        setDialogState(() => erroDialogo = null);
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<FormaPagamento>(
                      initialValue: formaEscolhida,
                      decoration: const InputDecoration(
                        labelText: 'Forma de pagamento',
                      ),
                      items: FormaPagamento.values
                          .map(
                            (forma) => DropdownMenuItem(
                          value: forma,
                          child: Text(formaPagamentoLabel(forma)),
                        ),
                      )
                          .toList(),
                      onChanged: (forma) {
                        if (forma != null) {
                          setDialogState(() => formaEscolhida = forma);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Expanded(child: Text('Saldo após receber')),
                          Text(
                            _reais(saldoRestante < 0 ? 0 : saldoRestante),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                    if (erroDialogo != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        erroDialogo!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      'Ao registrar, o pagamento será confirmado imediatamente.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color:
                        Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: () {
                  if (valorCentavos <= 0) {
                    setDialogState(
                          () => erroDialogo = 'Informe um valor válido.',
                    );
                    return;
                  }
                  if (valorCentavos > r.saldoEmAbertoCentavos) {
                    setDialogState(
                          () => erroDialogo =
                      'O valor não pode ser maior que o saldo em aberto.',
                    );
                    return;
                  }
                  Navigator.of(dialogContext).pop((
                  valorCentavos: valorCentavos,
                  forma: formaEscolhida,
                  ));
                },
                icon: const Icon(Icons.check),
                label: const Text('Confirmar recebimento'),
              ),
            ],
          );
        },
      ),
    );
    valorController.dispose();

    if (resultado == null || !mounted) return;

    setState(() => _registrando.add(r.id!));
    try {
      await ref.read(pagamentoRepositoryProvider).registrarEAlocar(
        orgId: widget.orgId,
        clienteId: r.clienteId,
        valorTotalCentavos: resultado.valorCentavos,
        observacao: 'Registrado manualmente pelo financeiro — ${r.numero}',
        formaPagamento: resultado.forma,
        jaConfirmado: true,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recebimento registrado!')),
        );
      }
    } catch (e) {
      debugPrint('Erro ao registrar recebimento: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível registrar o recebimento.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _registrando.remove(r.id!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final recebiveisAsync =
    ref.watch(recebiveisTodosAbertosProvider(widget.orgId));
    final clientesAsync = ref.watch(clientesListProvider);

    return recebiveisAsync.when(
      data: (recebiveis) {
        final nomePorId = <String, String>{
          for (final c in (clientesAsync.value ?? const <Cliente>[]))
            if (c.id != null) c.id!: c.nome,
        };

        final termo = _buscaController.text.trim().toLowerCase();
        final filtrados = recebiveis.where((recebivel) {
          final nome = nomePorId[recebivel.clienteId] ?? 'Cliente';
          final correspondeBusca = termo.isEmpty ||
              nome.toLowerCase().contains(termo) ||
              recebivel.numero.toLowerCase().contains(termo);
          final correspondeFiltro = switch (_filtro) {
            _FiltroRecebivel.todos => true,
            _FiltroRecebivel.vencidos =>
            recebivel.status == RecebivelStatus.vencido,
            _FiltroRecebivel.aVencer =>
            recebivel.status != RecebivelStatus.vencido,
          };
          return correspondeBusca && correspondeFiltro;
        }).toList()
          ..sort((a, b) {
            final aVencido = a.status == RecebivelStatus.vencido;
            final bVencido = b.status == RecebivelStatus.vencido;
            if (aVencido != bVencido) return aVencido ? -1 : 1;
            final dataA = a.dataVencimento ?? DateTime(9999);
            final dataB = b.dataVencimento ?? DateTime(9999);
            return dataA.compareTo(dataB);
          });

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          children: [
            const _PageIntro(
              title: 'Contas a receber',
              subtitle:
              'Localize cobranças, acompanhe vencimentos e registre pagamentos.',
            ),
            const SizedBox(height: 18),
            _FinanceFilterBar(
              controller: _buscaController,
              hintText: 'Buscar por cliente ou número da cobrança',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: Text('Todos (${recebiveis.length})'),
                  selected: _filtro == _FiltroRecebivel.todos,
                  onSelected: (_) {
                    setState(() => _filtro = _FiltroRecebivel.todos);
                  },
                ),
                ChoiceChip(
                  label: Text(
                    'Vencidos (${recebiveis.where((r) => r.status == RecebivelStatus.vencido).length})',
                  ),
                  selected: _filtro == _FiltroRecebivel.vencidos,
                  onSelected: (_) {
                    setState(() => _filtro = _FiltroRecebivel.vencidos);
                  },
                ),
                ChoiceChip(
                  label: Text(
                    'A vencer (${recebiveis.where((r) => r.status != RecebivelStatus.vencido).length})',
                  ),
                  selected: _filtro == _FiltroRecebivel.aVencer,
                  onSelected: (_) {
                    setState(() => _filtro = _FiltroRecebivel.aVencer);
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '${filtrados.length} resultado(s)',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            if (filtrados.isEmpty)
              const _StateMessage(
                icon: Icons.search_off_outlined,
                title: 'Nenhuma cobrança encontrada',
                message: 'Altere a busca ou os filtros para ver outros itens.',
              )
            else
              for (var index = 0; index < filtrados.length; index++) ...[
                _RecebivelListItem(
                  recebivel: filtrados[index],
                  clienteNome:
                  nomePorId[filtrados[index].clienteId] ?? 'Cliente',
                  registrando: _registrando.contains(filtrados[index].id),
                  onReceber: () => _registrarRecebimento(
                    filtrados[index],
                    nomePorId[filtrados[index].clienteId] ?? 'Cliente',
                  ),
                ),
                if (index != filtrados.length - 1)
                  const SizedBox(height: 10),
              ],
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => _StateMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Não foi possível carregar as cobranças',
        message: 'Verifique sua conexão e tente novamente.',
        actionLabel: 'Tentar novamente',
        onAction: () => ref.invalidate(
          recebiveisTodosAbertosProvider(widget.orgId),
        ),
      ),
    );
  }
}

class _RecebivelListItem extends StatelessWidget {
  final Recebivel recebivel;
  final String clienteNome;
  final bool registrando;
  final VoidCallback onReceber;

  const _RecebivelListItem({
    required this.recebivel,
    required this.clienteNome,
    required this.registrando,
    required this.onReceber,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final vencido = recebivel.status == RecebivelStatus.vencido;
    final vencimento = recebivel.dataVencimento == null
        ? 'Não informado'
        : _data.format(recebivel.dataVencimento!);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cliente = Row(
              children: [
                CircleAvatar(
                  backgroundColor: colorScheme.primaryContainer,
                  foregroundColor: colorScheme.onPrimaryContainer,
                  child: const Icon(Icons.storefront_outlined),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        clienteNome,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        recebivel.numero,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );

            final detalhes = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _LabelValue(label: 'Vencimento', value: vencimento),
                const SizedBox(width: 22),
                _StatusPill(
                  label: vencido ? 'Vencido' : 'A vencer',
                  color: vencido ? colorScheme.error : Colors.green,
                ),
                const SizedBox(width: 22),
                _LabelValue(
                  label: 'Saldo',
                  value: _reais(recebivel.saldoEmAbertoCentavos),
                  valueColor: vencido ? colorScheme.error : null,
                ),
              ],
            );

            final botao = FilledButton.tonalIcon(
              onPressed: registrando ? null : onReceber,
              icon: registrando
                  ? const SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Icon(Icons.add_card_outlined),
              label: Text(registrando ? 'Registrando...' : 'Receber'),
            );

            if (constraints.maxWidth < 720) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  cliente,
                  const SizedBox(height: 14),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: detalhes,
                  ),
                  const SizedBox(height: 14),
                  botao,
                ],
              );
            }

            return Row(
              children: [
                Expanded(flex: 3, child: cliente),
                const SizedBox(width: 20),
                detalhes,
                const SizedBox(width: 20),
                botao,
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Histórico geral (pagamentos) ────────────────────────────────────

enum _FiltroFormaPagamento { todas, pix, dinheiro, boleto }

class _HistoricoTab extends ConsumerStatefulWidget {
  final String orgId;
  const _HistoricoTab({required this.orgId});

  @override
  ConsumerState<_HistoricoTab> createState() => _HistoricoTabState();
}

class _HistoricoTabState extends ConsumerState<_HistoricoTab> {
  final TextEditingController _buscaController = TextEditingController();
  _FiltroFormaPagamento _filtro = _FiltroFormaPagamento.todas;

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pagamentosAsync = ref.watch(pagamentosTodosProvider(widget.orgId));
    final clientesAsync = ref.watch(clientesListProvider);
    final usuariosAsync = ref.watch(usuariosListProvider);

    return pagamentosAsync.when(
      data: (pagamentos) {
        final nomeClientePorId = <String, String>{
          for (final c in (clientesAsync.value ?? const <Cliente>[]))
            if (c.id != null) c.id!: c.nome,
        };
        final nomeVendedorPorId = <String, String>{
          for (final u in (usuariosAsync.value ?? const []))
            u.uid: u.nome,
        };

        final termo = _buscaController.text.trim().toLowerCase();
        final filtrados = pagamentos.where((pagamento) {
          final cliente =
              nomeClientePorId[pagamento.clienteId] ?? 'Cliente';
          final correspondeBusca =
              termo.isEmpty || cliente.toLowerCase().contains(termo);
          final correspondeForma = switch (_filtro) {
            _FiltroFormaPagamento.todas => true,
            _FiltroFormaPagamento.pix =>
            pagamento.formaPagamento == FormaPagamento.pix,
            _FiltroFormaPagamento.dinheiro =>
            pagamento.formaPagamento == FormaPagamento.dinheiro,
            _FiltroFormaPagamento.boleto =>
            pagamento.formaPagamento == FormaPagamento.boleto,
          };
          return correspondeBusca && correspondeForma;
        }).toList()
          ..sort((a, b) {
            final dataA = a.criadoEm ?? DateTime.fromMillisecondsSinceEpoch(0);
            final dataB = b.criadoEm ?? DateTime.fromMillisecondsSinceEpoch(0);
            return dataB.compareTo(dataA);
          });

        final totalFiltrado = filtrados.fold<int>(
          0,
              (soma, pagamento) => soma + pagamento.valorTotalCentavos,
        );

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          children: [
            _PageIntro(
              title: 'Histórico de recebimentos',
              subtitle:
              'Consulte pagamentos registrados e acompanhe os repasses.',
              trailing: _SummaryBadge(
                label: 'Total filtrado',
                value: _reais(totalFiltrado),
              ),
            ),
            const SizedBox(height: 18),
            _FinanceFilterBar(
              controller: _buscaController,
              hintText: 'Buscar por cliente',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Todos'),
                  selected: _filtro == _FiltroFormaPagamento.todas,
                  onSelected: (_) => setState(
                        () => _filtro = _FiltroFormaPagamento.todas,
                  ),
                ),
                ChoiceChip(
                  label: const Text('Pix'),
                  selected: _filtro == _FiltroFormaPagamento.pix,
                  onSelected: (_) => setState(
                        () => _filtro = _FiltroFormaPagamento.pix,
                  ),
                ),
                ChoiceChip(
                  label: const Text('Dinheiro'),
                  selected: _filtro == _FiltroFormaPagamento.dinheiro,
                  onSelected: (_) => setState(
                        () => _filtro = _FiltroFormaPagamento.dinheiro,
                  ),
                ),
                ChoiceChip(
                  label: const Text('Boleto'),
                  selected: _filtro == _FiltroFormaPagamento.boleto,
                  onSelected: (_) => setState(
                        () => _filtro = _FiltroFormaPagamento.boleto,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '${filtrados.length} pagamento(s)',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            if (filtrados.isEmpty)
              const _StateMessage(
                icon: Icons.receipt_long_outlined,
                title: 'Nenhum pagamento encontrado',
                message: 'Altere a busca ou os filtros para consultar o histórico.',
              )
            else
              for (var index = 0; index < filtrados.length; index++) ...[
                _PagamentoListItem(
                  pagamento: filtrados[index],
                  clienteNome:
                  nomeClientePorId[filtrados[index].clienteId] ?? 'Cliente',
                  vendedorNome: filtrados[index].vendedorId == null
                      ? null
                      : nomeVendedorPorId[filtrados[index].vendedorId] ??
                      'Vendedor',
                ),
                if (index != filtrados.length - 1)
                  const SizedBox(height: 10),
              ],
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => _StateMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Não foi possível carregar o histórico',
        message: 'Verifique sua conexão e tente novamente.',
        actionLabel: 'Tentar novamente',
        onAction: () =>
            ref.invalidate(pagamentosTodosProvider(widget.orgId)),
      ),
    );
  }
}

class _PagamentoListItem extends StatelessWidget {
  final Pagamento pagamento;
  final String clienteNome;
  final String? vendedorNome;

  const _PagamentoListItem({
    required this.pagamento,
    required this.clienteNome,
    required this.vendedorNome,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final data = pagamento.criadoEm == null
        ? 'Data não informada'
        : DateFormat('dd/MM/yyyy HH:mm').format(pagamento.criadoEm!);
    final confirmado = pagamento.statusRepasse == StatusRepasse.confirmado;
    final icon = switch (pagamento.formaPagamento) {
      FormaPagamento.dinheiro => Icons.payments_outlined,
      FormaPagamento.pix => Icons.pix,
      FormaPagamento.boleto => Icons.receipt_long_outlined,
    };

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final identificacao = Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        clienteNome,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${formaPagamentoLabel(pagamento.formaPagamento)} • $data',
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
            );

            final complemento = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (vendedorNome != null) ...[
                  _LabelValue(label: 'Responsável', value: vendedorNome!),
                  const SizedBox(width: 20),
                ],
                _StatusPill(
                  label: confirmado ? 'Confirmado' : 'Repasse pendente',
                  color: confirmado ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 20),
                Text(
                  _reais(pagamento.valorTotalCentavos),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            );

            if (constraints.maxWidth < 720) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  identificacao,
                  const SizedBox(height: 14),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: complemento,
                  ),
                ],
              );
            }

            return Row(
              children: [
                Expanded(flex: 3, child: identificacao),
                const SizedBox(width: 20),
                complemento,
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Acertos de caixa — fila de confirmação do financeiro ───────────

class _AcertosTab extends ConsumerStatefulWidget {
  final String orgId;
  final String usuarioId;
  const _AcertosTab({required this.orgId, required this.usuarioId});

  @override
  ConsumerState<_AcertosTab> createState() => _AcertosTabState();
}

class _AcertosTabState extends ConsumerState<_AcertosTab> {
  final Set<String> _confirmando = {};

  Future<void> _confirmar(
      AcertoCaixa acerto,
      String vendedorNome,
      ) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmar recebimento?'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DialogInfoHeader(
                icon: Icons.fact_check_outlined,
                title: vendedorNome,
                subtitle:
                '${_data.format(acerto.data)} • ${acerto.itens.length} recebimento(s)',
              ),
              const SizedBox(height: 18),
              Text(
                _reais(acerto.valorTotalCentavos),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Confirme somente depois que o valor tiver sido recebido e conferido.',
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
            icon: const Icon(Icons.check),
            label: const Text('Confirmar recebimento'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => _confirmando.add(acerto.id!));
    try {
      await ref.read(acertoCaixaRepositoryProvider).confirmar(
        acertoCaixaId: acerto.id!,
        usuarioId: widget.usuarioId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Acerto confirmado!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível confirmar o acerto.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _confirmando.remove(acerto.id!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final acertosAsync =
    ref.watch(acertosPendentesConfirmacaoProvider(widget.orgId));
    final usuariosAsync = ref.watch(usuariosListProvider);

    return acertosAsync.when(
      data: (acertos) {
        final nomeVendedorPorId = <String, String>{
          for (final u in (usuariosAsync.value ?? const []))
            u.uid: u.nome,
        };

        final totalPendente = acertos.fold<int>(
          0,
              (soma, acerto) => soma + acerto.valorTotalCentavos,
        );

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          children: [
            _PageIntro(
              title: 'Acertos de caixa',
              subtitle:
              'Confira os valores entregues pelos vendedores antes de confirmar.',
              trailing: _SummaryBadge(
                label: '${acertos.length} pendente(s)',
                value: _reais(totalPendente),
              ),
            ),
            const SizedBox(height: 18),
            if (acertos.isEmpty)
              const _StateMessage(
                icon: Icons.task_alt,
                title: 'Tudo conferido',
                message: 'Nenhum acerto de caixa aguarda confirmação.',
              )
            else
              for (var index = 0; index < acertos.length; index++) ...[
                Builder(
                  builder: (context) {
                    final acerto = acertos[index];
                    final vendedorNome =
                        nomeVendedorPorId[acerto.vendedorId] ?? 'Vendedor';
                    final confirmando = _confirmando.contains(acerto.id);

                    return Card(
                      margin: EdgeInsets.zero,
                      elevation: 0,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: ExpansionTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.orange.withValues(alpha: 0.14),
                          child: const Icon(
                            Icons.person_outline,
                            color: Colors.orange,
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                vendedorNome,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _reais(acerto.valorTotalCentavos),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                '${_data.format(acerto.data)} • ${acerto.itens.length} recebimento(s)',
                              ),
                              const _StatusPill(
                                label: 'Aguardando confirmação',
                                color: Colors.orange,
                              ),
                            ],
                          ),
                        ),
                        children: [
                          const Divider(height: 1),
                          for (final item in acerto.itens)
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.storefront_outlined),
                              title: Text(item.clienteNome),
                              trailing: Text(
                                _reais(item.valorCentavos),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          if (acerto.observacao != null &&
                              acerto.observacao!.trim().isNotEmpty)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'Observação: ${acerto.observacao}',
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.icon(
                                onPressed: confirmando
                                    ? null
                                    : () => _confirmar(
                                  acerto,
                                  vendedorNome,
                                ),
                                icon: confirmando
                                    ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                    : const Icon(Icons.check),
                                label: Text(
                                  confirmando
                                      ? 'Confirmando...'
                                      : 'Confirmar recebimento',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                if (index != acertos.length - 1)
                  const SizedBox(height: 10),
              ],
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => _StateMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Não foi possível carregar os acertos',
        message: 'Verifique sua conexão e tente novamente.',
        actionLabel: 'Tentar novamente',
        onAction: () => ref.invalidate(
          acertosPendentesConfirmacaoProvider(widget.orgId),
        ),
      ),
    );
  }
}

// ── Componentes visuais compartilhados ─────────────────────────────

class _PageIntro extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;

  const _PageIntro({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    if (trailing == null) return text;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              text,
              const SizedBox(height: 12),
              trailing!,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: text),
            const SizedBox(width: 16),
            trailing!,
          ],
        );
      },
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  const _DashboardCard({
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
        borderRadius: BorderRadius.circular(14),
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
                          fontWeight: FontWeight.w900,
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
                  const SizedBox(width: 8),
                  trailing!,
                ],
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 21, color: color),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _FinanceFilterBar extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;

  const _FinanceFilterBar({
    required this.controller,
    required this.hintText,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
          tooltip: 'Limpar busca',
          onPressed: () {
            controller.clear();
            onChanged('');
          },
          icon: const Icon(Icons.close),
        ),
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _LabelValue extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _LabelValue({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          style: TextStyle(
            color: valueColor,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _SummaryBadge extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryBadge({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _DialogInfoHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _DialogInfoHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
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

class _CompactEmptyState extends StatelessWidget {
  final IconData icon;
  final String text;

  const _CompactEmptyState({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(icon, color: colorScheme.primary, size: 30),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _StateMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _StateMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, size: 30, color: colorScheme.primary),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: onAction,
                  icon: const Icon(Icons.refresh),
                  label: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
