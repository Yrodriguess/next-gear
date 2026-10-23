import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/auth_providers.dart';
import '../../features/auth/presentation/no_access_page.dart';
import '../../features/auth/presentation/sign_out_helper.dart';
import '../../features/auth/presentation/unregistered_user_page.dart';
import '../navigation/app_navigation.dart';
import '../navigation/navigation_item.dart';
import '../theme/app_theme.dart';
import '../widgets/branded_loading_view.dart';
import '../widgets/friendly_error_view.dart';

/// Acima dessa largura mostramos a sidebar fixa/recolhível de desktop;
/// abaixo, o Drawer clássico de mobile/tablet.
const double _kDesktopBreakpoint = 840;

/// Mesma logo usada na tela de login e no loading — mantém a
/// identidade visual consistente em todo o app.
const _logoAsset = 'assets/images/logo_nextgear.png';

/// Pega as iniciais do nome pra usar em avatares (ex.: "Ytalo Silva" -> "YS").
String _iniciaisNome(String nome) {
  final partes = nome
      .trim()
      .split(RegExp(r'\s+'))
      .where((parte) => parte.isNotEmpty)
      .toList();

  if (partes.isEmpty) return '?';

  if (partes.length == 1) {
    final texto = partes.first;
    return texto.length >= 2
        ? texto.substring(0, 2).toUpperCase()
        : texto.toUpperCase();
  }

  return '${partes.first[0]}${partes.last[0]}'.toUpperCase();
}

/// Casca pós-login: monta o menu (sidebar ou Drawer, dependendo da
/// largura da tela) só com os módulos que o papel do usuário pode ver.
/// A lista de módulos por papel vive em app_navigation.dart — não
/// espalhar switch (role) por outros lugares do projeto.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _railExtended = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // A decisão mobile/desktop (isDesktop, logo abaixo) é tomada aqui
    // em cima — bem acima de qualquer tela aberta depois. Em alguns
    // navegadores mobile, a primeira medição de largura vem errada
    // (barra de endereço do navegador ainda recolhendo, etc.) — sem
    // isso, o app inteiro nasce com a decisão errada e nada dentro
    // dele (nem forçar rebuild de uma tela filha) corrige sozinho.
    // Isso garante que, assim que uma métrica de verdade chegar, o
    // AppShell reavalia do zero.
    if (mounted) setState(() {});
  }

  // Páginas já construídas, indexadas pela posição no menu. Construir sob
  // demanda (e manter em cache) preserva scroll/filtros/formulário de cada
  // módulo ao trocar de aba, sem montar telas que o usuário nunca abriu.
  final Map<int, Widget> _builtPages = {};

  // Um Navigator próprio por aba, só usado no desktop — é o que permite
  // "Novo Cliente"/"Detalhes" abrirem SEM a sidebar sumir: o push vai
  // pro Navigator aninhado da aba, não pro Navigator raiz do app. As
  // GlobalKeys garantem que o Flutter reconheça "é o mesmo Navigator"
  // entre rebuilds e preserve a pilha de navegação de cada aba.
  final Map<int, GlobalKey<NavigatorState>> _navKeys = {};

  void _selecionarModulo(int index) => setState(() => _currentIndex = index);

  Widget? _paginaEmCache(List<NavigationItem> items, int i, {required bool ativo}) {
    if (ativo) {
      return _builtPages.putIfAbsent(i, () => items[i].builder(context));
    }
    // Só devolve o que já foi construído; os demais módulos nem
    // chegam a ser montados enquanto o usuário não passar por eles.
    return _builtPages[i];
  }

  /// Mobile: sem Navigator aninhado — um push vai pro Navigator raiz
  /// e ocupa a tela toda, escondendo a sidebar/Drawer temporariamente.
  /// É o padrão esperado em mobile (like qualquer app com Drawer);
  /// diferente do desktop, aqui não faria sentido manter duas AppBars
  /// empilhadas (a da aba + a da tela aberta).
  Widget _buildContent(List<NavigationItem> items, int index) {
    return IndexedStack(
      index: index,
      children: List.generate(items.length, (i) {
        return _paginaEmCache(items, i, ativo: i == index) ??
            const SizedBox.shrink();
      }),
    );
  }

  /// Desktop: cada aba ganha seu próprio Navigator aninhado, então
  /// "Novo Cliente"/"Detalhes" abrem dentro da área de conteúdo,
  /// mantendo a sidebar sempre visível.
  Widget _buildDesktopContent(List<NavigationItem> items, int index) {
    return IndexedStack(
      index: index,
      children: List.generate(items.length, (i) {
        final pagina = _paginaEmCache(items, i, ativo: i == index);
        if (pagina == null) return const SizedBox.shrink();
        return Navigator(
          key: _navKeys.putIfAbsent(i, () => GlobalKey<NavigatorState>()),
          onGenerateInitialRoutes: (navigator, initialRoute) => [
            MaterialPageRoute(builder: (_) => pagina),
          ],
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appUserAsync = ref.watch(appUserProvider);

    return appUserAsync.when(
      data: (appUser) {
        if (appUser == null) return const UnregisteredUserPage();

        final items = navigationItemsForRole(appUser.role);
        if (items.isEmpty) return const NoAccessPage();

        final index = _currentIndex < items.length ? _currentIndex : 0;

        final email = ref.watch(authStateProvider).value?.email ?? '';
        // Prioriza o nome cadastrado; cai pro e-mail só se o nome
        // vier vazio por algum motivo (dado legado, por exemplo).
        final nome = appUser.nome.trim().isNotEmpty
            ? appUser.nome.trim()
            : (email.isNotEmpty ? email : 'Usuário');
        final perfil = roleLabel(appUser.role);

        return LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= _kDesktopBreakpoint;
            return isDesktop
                ? _DesktopLayout(
              items: items,
              currentIndex: index,
              extended: _railExtended,
              nome: nome,
              perfil: perfil,
              onToggleExtended: () =>
                  setState(() => _railExtended = !_railExtended),
              onSelect: _selecionarModulo,
              content: _buildDesktopContent(items, index),
            )
                : _MobileLayout(
              items: items,
              currentIndex: index,
              nome: nome,
              perfil: perfil,
              onSelect: _selecionarModulo,
              content: _buildContent(items, index),
            );
          },
        );
      },
      loading: () => const BrandedLoadingView(),
      error: (error, stack) {
        debugPrint('AppShell: erro em appUserProvider: $error\n$stack');
        return FriendlyErrorView(
          message: 'Não foi possível carregar seus dados. Tente novamente.',
          onRetry: () => ref.invalidate(appUserProvider),
        );
      },
    );
  }
}

/// Layout de desktop/web: sidebar (NavigationRail) recolhível + conteúdo.
class _DesktopLayout extends StatelessWidget {
  final List<NavigationItem> items;
  final int currentIndex;
  final bool extended;
  final String nome;
  final String perfil;
  final VoidCallback onToggleExtended;
  final ValueChanged<int> onSelect;
  final Widget content;

  const _DesktopLayout({
    required this.items,
    required this.currentIndex,
    required this.extended,
    required this.nome,
    required this.perfil,
    required this.onToggleExtended,
    required this.onSelect,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              extended: extended,
              minExtendedWidth: 220,
              selectedIndex: currentIndex,
              onDestinationSelected: onSelect,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: IconButton(
                  tooltip: extended ? 'Recolher menu' : 'Expandir menu',
                  icon: Icon(extended ? Icons.menu_open : Icons.menu),
                  onPressed: onToggleExtended,
                ),
              ),
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  // NavigationRail entrega largura não limitada (w<=Infinity)
                  // pro trailing. O _SidebarFooter usa crossAxisAlignment
                  // .stretch, que precisa de largura definida — sem esse
                  // SizedBox o layout quebra com "BoxConstraints forces an
                  // infinite width".
                  child: SizedBox(
                    width: extended ? 220 : 56,
                    child: _SidebarFooter(
                      extended: extended,
                      nome: nome,
                      perfil: perfil,
                    ),
                  ),
                ),
              ),
              destinations: items
                  .map((item) => NavigationRailDestination(
                icon: Icon(item.icon),
                label: Text(item.label),
              ))
                  .toList(),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
}

/// Rodapé fixo da sidebar: avatar/nome, perfil e botão Sair (com confirmação).
class _SidebarFooter extends ConsumerWidget {
  final bool extended;
  final String nome;
  final String perfil;

  const _SidebarFooter({
    required this.extended,
    required this.nome,
    required this.perfil,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final corPrimaria = Theme.of(context).colorScheme.primary;

    if (!extended) {
      // Recolhida: mostra um avatar pequeno (com tooltip do nome) em
      // cima do botão de sair, pra dar pelo menos alguma pista de
      // quem está logado sem precisar expandir o menu.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: '$nome ($perfil)',
              child: CircleAvatar(
                radius: 14,
                backgroundColor: corPrimaria.withValues(alpha: 0.16),
                child: Text(
                  _iniciaisNome(nome),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: corPrimaria,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            IconButton(
              tooltip: 'Sair ($perfil)',
              icon: const Icon(Icons.logout),
              onPressed: () => confirmarESair(context, ref),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 24),
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: corPrimaria.withValues(alpha: 0.16),
                child: Text(
                  _iniciaisNome(nome),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: corPrimaria,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nome,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      perfil,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: corPrimaria,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => confirmarESair(context, ref),
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Sair'),
          ),
        ],
      ),
    );
  }
}

/// Layout de celular/tablet: AppBar com ☰ + Drawer + conteúdo.
class _MobileLayout extends StatelessWidget {
  final List<NavigationItem> items;
  final int currentIndex;
  final String nome;
  final String perfil;
  final ValueChanged<int> onSelect;
  final Widget content;

  const _MobileLayout({
    required this.items,
    required this.currentIndex,
    required this.nome,
    required this.perfil,
    required this.onSelect,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(items[currentIndex].label)),
      // Scaffold já mostra o ☰ automaticamente na AppBar quando há Drawer.
      drawer: _AppDrawer(
        items: items,
        currentIndex: currentIndex,
        nome: nome,
        perfil: perfil,
        onSelect: (i) {
          Navigator.of(context).pop(); // fecha o Drawer antes de trocar
          onSelect(i);
        },
      ),
      body: SafeArea(child: content),
    );
  }
}

/// Drawer de mobile: cabeçalho com a logo, lista de módulos e rodapé
/// com usuário/perfil/sair — mesmo conteúdo do rodapé da sidebar.
class _AppDrawer extends ConsumerWidget {
  final List<NavigationItem> items;
  final int currentIndex;
  final String nome;
  final String perfil;
  final ValueChanged<int> onSelect;

  const _AppDrawer({
    required this.items,
    required this.currentIndex,
    required this.nome,
    required this.perfil,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            DrawerHeader(
              child: Align(
                alignment: Alignment.center,
                child: Image.asset(
                  _logoAsset,
                  height: 96,
                  fit: BoxFit.contain,
                  semanticLabel: 'NEXT GEAR Acessórios',
                  // Se o asset não carregar, volta pro texto — nunca
                  // deixa o cabeçalho do Drawer vazio.
                  errorBuilder: (_, __, ___) => ShaderMask(
                    shaderCallback: (bounds) =>
                        AppColors.brandGradient.createShader(bounds),
                    child: const Text(
                      'NEXTGEAR',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (var i = 0; i < items.length; i++)
                    ListTile(
                      leading: Icon(items[i].icon),
                      title: Text(items[i].label),
                      selected: i == currentIndex,
                      selectedTileColor: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.12),
                      onTap: () => onSelect(i),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.16),
                child: Text(
                  _iniciaisNome(nome),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              title: Text(
                nome,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(perfil),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sair'),
              onTap: () => confirmarESair(context, ref),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}