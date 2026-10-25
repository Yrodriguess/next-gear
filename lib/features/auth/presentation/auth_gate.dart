import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/shell/app_shell.dart';
import '../../../core/widgets/branded_loading_view.dart';
import '../../../core/widgets/friendly_error_view.dart';
import 'auth_providers.dart';
import 'login_page.dart';

/// Decide qual tela mostrar de acordo com o estado de login.
/// Ver seção 4 do Blueprint (perfis e permissões).
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (user) {
        if (user == null) return const LoginPage();
        return const AppShell();
      },
      loading: () => const BrandedLoadingView(),
      error: (error, stack) {
        // Detalhe técnico só no log — o usuário não precisa (nem deveria)
        // ver "Erro ao conectar: $error" na tela.
        debugPrint('AuthGate: erro em authStateProvider: $error\n$stack');
        return FriendlyErrorView(
          message: 'Não foi possível conectar. Tente novamente.',
          onRetry: () => ref.invalidate(authStateProvider),
        );
      },
    );
  }
}
