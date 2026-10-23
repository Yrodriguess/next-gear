import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'core/widgets/friendly_error_view.dart';
import 'features/auth/presentation/auth_gate.dart';
import 'firebase_options.dart';

// Se a inicialização crescer mais do que isso, extrair para bootstrap.dart.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e, stack) {
    debugPrint('Falha ao inicializar o Firebase: $e\n$stack');
    runApp(const _InitializationErrorApp());
    return;
  }

  runApp(const ProviderScope(child: NextGearApp()));
}

class NextGearApp extends StatelessWidget {
  const NextGearApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NEXT GEAR',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const AuthGate(),
    );
  }
}

/// Tela mínima exibida se o próprio Firebase.initializeApp falhar — não dá
/// pra abrir o ProviderScope/AuthGate normal, então roda um app à parte.
class _InitializationErrorApp extends StatelessWidget {
  const _InitializationErrorApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const FriendlyErrorView(
        message: 'Não foi possível iniciar o NEXT GEAR. Tente novamente.',
      ),
    );
  }
}
