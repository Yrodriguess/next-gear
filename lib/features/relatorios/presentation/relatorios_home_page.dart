import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/firestore_collections.dart';
import '../../clientes/presentation/cliente_providers.dart';
import '../../consignacoes/presentation/consignment_providers.dart';
import '../../estoque/presentation/estoque_providers.dart';
import '../../expositores/presentation/expositor_providers.dart';
import '../../financeiro/presentation/financeiro_providers.dart';
import '../../produtos/presentation/produto_providers.dart';
import 'relatorio_aging_page.dart';
import 'relatorio_expositores_page.dart';
import 'relatorio_giro_page.dart';
import 'relatorio_vendas_page.dart';
import 'relatorio_visao_geral_page.dart';

/// Central de relatórios. Cada aba começa a ouvir os providers somente depois
/// do primeiro acesso e permanece montada para preservar filtros e rolagem.
class RelatoriosHomePage extends ConsumerStatefulWidget {
  const RelatoriosHomePage({super.key});

  @override
  ConsumerState<RelatoriosHomePage> createState() =>
      _RelatoriosHomePageState();
}

class _RelatoriosHomePageState extends ConsumerState<RelatoriosHomePage>
    with SingleTickerProviderStateMixin {
  static const _abas = [
    Tab(icon: Icon(Icons.dashboard_outlined), text: 'Visão geral'),
    Tab(icon: Icon(Icons.trending_up), text: 'Vendas'),
    Tab(icon: Icon(Icons.hourglass_bottom), text: 'Capital em campo'),
    Tab(icon: Icon(Icons.sync_alt), text: 'Giro de estoque'),
    Tab(icon: Icon(Icons.view_in_ar_outlined), text: 'Expositores'),
  ];

  late final TabController _tabController;
  final Set<int> _visitados = {0};
  int _indiceAtivo = 0;
  DateTime _atualizadoEm = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _abas.length, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    final novoIndice = _tabController.index;
    if (novoIndice == _indiceAtivo) return;
    setState(() {
      _indiceAtivo = novoIndice;
      _visitados.add(novoIndice);
    });
  }

  void _abrirAba(int index) {
    if (index < 0 || index >= _abas.length) return;
    _tabController.animateTo(index);
  }

  void _atualizarTudo() {
    final orgId = AppConfig.currentOrgId;
    ref.invalidate(vendasProvider(orgId));
    ref.invalidate(consignmentsAtivasProvider(orgId));
    ref.invalidate(recebiveisTodosAbertosProvider(orgId));
    ref.invalidate(clientesListProvider);
    ref.invalidate(produtosListProvider);
    ref.invalidate(skusListProvider);
    ref.invalidate(expositoresFisicosListProvider);
    ref.invalidate(expositorMovimentacoesRecentesProvider);
    setState(() => _atualizadoEm = DateTime.now());
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  Widget _construirAba(int index) {
    if (!_visitados.contains(index)) return const SizedBox.shrink();
    return switch (index) {
      0 => RelatorioVisaoGeralPage(onAbrirAba: _abrirAba),
      1 => const RelatorioVendasPage(),
      2 => const RelatorioAgingPage(),
      3 => const RelatorioGiroPage(),
      _ => const RelatorioExpositoresPage(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final largura = MediaQuery.sizeOf(context).width;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Material(
              color: theme.colorScheme.surface,
              elevation: 1,
              child: Column(
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1280),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.analytics_outlined,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Relatórios',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    'Indicadores comerciais, financeiros e operacionais',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (largura >= 620)
                              Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: Text(
                                  'Atualizado às ${DateFormat('HH:mm').format(_atualizadoEm)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            IconButton.filledTonal(
                              tooltip: 'Atualizar relatórios',
                              onPressed: _atualizarTudo,
                              icon: const Icon(Icons.refresh),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1280),
                      child: TabBar(
                        controller: _tabController,
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        tabs: _abas,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _indiceAtivo,
                children: List.generate(_abas.length, _construirAba),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
