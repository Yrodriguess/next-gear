import 'package:flutter/material.dart';

import '../../features/auth/domain/app_user.dart';
import '../../features/auth/presentation/usuarios_page.dart';
import '../../features/clientes/presentation/cliente_list_page.dart';
import '../../features/estoque/presentation/estoque_central_page.dart';
import '../../features/expositores/presentation/expositor_list_page.dart';
import '../../features/financeiro/presentation/financeiro_home_page.dart';
import '../../features/produtos/presentation/produto_list_page.dart';
import '../../features/relatorios/presentation/relatorios_home_page.dart';
import '../../features/visitas/presentation/visita_cliente_selector_page.dart';
import 'navigation_item.dart';

/// Fonte única de verdade de "quais módulos cada papel enxerga".
///
/// Isso é só a interface — nunca confiar só nisso pra segurança de
/// verdade. As regras do Firestore são a trava real contra acesso
/// indevido; esconder um item de menu não impede uma chamada direta
/// à API/Firestore por fora do app.
///
/// Se no futuro o sistema precisar de permissões mais finas do que um
/// papel único (ex.: "vendedor com acesso a relatórios"), este é o
/// lugar certo pra evoluir — trocar o switch por uma checagem de
/// permissões específicas, mantendo a mesma assinatura de retorno.
List<NavigationItem> navigationItemsForRole(UserRole role) {
  final clientes = NavigationItem(
    icon: Icons.store,
    label: 'Clientes',
    builder: (_) => const ClienteListPage(),
  );
  final produtos = NavigationItem(
    icon: Icons.inventory_2,
    label: 'Produtos',
    builder: (_) => const ProdutoListPage(),
  );
  final expositores = NavigationItem(
    icon: Icons.dashboard_customize,
    label: 'Expositores',
    builder: (_) => const ExpositorListPage(),
  );
  final estoque = NavigationItem(
    icon: Icons.warehouse,
    label: 'Estoque',
    builder: (_) => const EstoqueCentralPage(),
  );
  final visitas = NavigationItem(
    icon: Icons.route,
    label: 'Visitas',
    builder: (_) => const VisitaClienteSelectorPage(),
  );
  final relatorios = NavigationItem(
    icon: Icons.bar_chart,
    label: 'Relatórios',
    builder: (_) => const RelatoriosHomePage(),
  );
  final usuarios = NavigationItem(
    icon: Icons.people,
    label: 'Usuários',
    builder: (_) => const UsuariosPage(),
  );
  final financeiro = NavigationItem(
    icon: Icons.account_balance_wallet,
    label: 'Financeiro',
    // A própria página decide o que mostrar de acordo com o papel de
    // quem está logado — vendedor só vê "Meu caixa", admin/financeiro
    // veem o painel completo. Ver FinanceiroHomePage.
    builder: (_) => const FinanceiroHomePage(),
  );

  return switch (role) {
    UserRole.admin => [
        clientes,
        produtos,
        expositores,
        estoque,
        visitas,
        financeiro,
        relatorios,
        usuarios,
      ],
    UserRole.financeiro => [clientes, financeiro, relatorios],
    UserRole.vendedor => [clientes, expositores, estoque, visitas, financeiro],
    UserRole.estoque => [produtos, expositores, estoque],
    UserRole.cliente => [],
  };
}

/// Nome amigável do papel, usado no rodapé do menu.
String roleLabel(UserRole role) => switch (role) {
      UserRole.admin => 'Administrador',
      UserRole.financeiro => 'Financeiro',
      UserRole.vendedor => 'Vendedor',
      UserRole.estoque => 'Estoque',
      UserRole.cliente => 'Cliente',
    };
