import 'package:flutter/widgets.dart';

/// Constrói a página do módulo só quando ela for realmente exibida pela
/// primeira vez (ver cache em AppShell), em vez de vir pronta na config.
typedef NavigationPageBuilder = Widget Function(BuildContext context);

/// Um módulo do menu: ícone, nome e como construir a tela dele.
class NavigationItem {
  final IconData icon;
  final String label;
  final NavigationPageBuilder builder;

  const NavigationItem({
    required this.icon,
    required this.label,
    required this.builder,
  });
}
