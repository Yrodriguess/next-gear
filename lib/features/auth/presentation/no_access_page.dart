import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/message_scaffold.dart';
import 'sign_out_helper.dart';

/// O usuário está cadastrado e tem um papel válido, mas esse papel ainda
/// não enxerga nenhum módulo (ex.: UserRole.cliente hoje). Diferente de
/// "sem cadastro": aqui o AppUser existe, só falta liberação de acesso.
class NoAccessPage extends ConsumerWidget {
  const NoAccessPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MessageScaffold(
      icon: Icons.lock_outline,
      title: 'Sem acesso a módulos',
      message: 'Seu cadastro está ativo, mas seu perfil ainda não tem '
          'acesso a nenhum módulo do sistema. Fale com um administrador '
          'se acha que isso é um engano.',
      actions: [
        OutlinedButton(
          onPressed: () => confirmarESair(context, ref),
          child: const Text('Sair'),
        ),
      ],
    );
  }
}
