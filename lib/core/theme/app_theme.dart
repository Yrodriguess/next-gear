import 'package:flutter/material.dart';

/// Cores oficiais da marca NEXT GEAR, extraídas diretamente da logo.
/// Ver seção 17 do Blueprint.
class AppColors {
  AppColors._();

  /// Ponta inicial do gradiente de marca — verde-limão.
  static const Color brandGreen = Color(0xFF8BF730);

  /// Ponta final do gradiente de marca — teal/ciano.
  static const Color brandTeal = Color(0xFF00E7C5);

  /// Fundo padrão do app — a logo já indica dark mode como identidade.
  static const Color backgroundDark = Color(0xFF151517);

  /// Texto/ícone claro sobre fundo escuro.
  static const Color surfaceLight = Color(0xFFDDDDDD);

  /// Superfície um pouco mais clara que o fundo, para cards/inputs.
  static const Color surfaceDark = Color(0xFF1F1F22);

  /// Cores semânticas — NÃO usar as cores de marca para status,
  /// para não confundir "cor da marca" com "estado do sistema".
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFFB020);
  static const Color error = Color(0xFFE5484D);

  /// Gradiente de marca — usar com moderação (ações de destaque,
  /// splash screen, cabeçalho de dashboard). Ver seção 17 do Blueprint.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandGreen, brandTeal],
  );
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    // ColorScheme.fromSeed gera TODOS os papéis de cor do Material 3
    // (primaryContainer, secondaryContainer, tertiary, outline, etc.)
    // a partir de uma única cor-semente. Antes, o tema só sobrescrevia
    // primary/secondary/surface/error em cima do esquema padrão do
    // Flutter — que usa roxo como semente — deixando todos os OUTROS
    // papéis ainda roxos. É por isso que o FloatingActionButton (usa
    // primaryContainer por padrão) e o indicador de seleção do menu
    // lateral (usa secondaryContainer por padrão) apareciam roxos
    // mesmo com primary/secondary corretos.
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.brandGreen,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.brandGreen,
      onPrimary: AppColors.backgroundDark,
      secondary: AppColors.brandTeal,
      onSecondary: AppColors.backgroundDark,
      surface: AppColors.surfaceDark,
      error: AppColors.error,
    );

    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.backgroundDark,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.backgroundDark,
        elevation: 0,
        foregroundColor: AppColors.surfaceLight,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brandGreen,
          foregroundColor: AppColors.backgroundDark,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      // Sem isso, o FAB usa colorScheme.primaryContainer por padrão —
      // que, mesmo com o fromSeed, ainda fica num tom diferente do
      // verde de ação que já usamos nos botões normais.
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.brandGreen,
        foregroundColor: AppColors.backgroundDark,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.backgroundDark,
        indicatorColor: AppColors.brandGreen,
        selectedIconTheme: const IconThemeData(color: AppColors.backgroundDark),
        selectedLabelTextStyle: const TextStyle(
          color: AppColors.brandGreen,
          fontWeight: FontWeight.bold,
        ),
        unselectedIconTheme: IconThemeData(
          color: AppColors.surfaceLight.withValues(alpha: 0.7),
        ),
        unselectedLabelTextStyle: TextStyle(
          color: AppColors.surfaceLight.withValues(alpha: 0.7),
        ),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.backgroundDark,
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(
        indicatorColor: AppColors.brandGreen.withValues(alpha: 0.25),
      ),
      listTileTheme: ListTileThemeData(
        selectedTileColor: AppColors.brandGreen.withValues(alpha: 0.12),
        selectedColor: AppColors.brandGreen,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceDark,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.brandTeal, width: 1.5),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  /// Web (financeiro/admin) pode usar o mesmo tema escuro, mas fica
  /// fácil trocar por um tema claro aqui se a equipe preferir para
  /// leitura prolongada de tabelas — ver seção 17 do Blueprint.
  static ThemeData get web => dark;
}
