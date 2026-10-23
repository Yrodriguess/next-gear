import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/message_scaffold.dart';
import 'sign_out_helper.dart';

/// Login no Firebase deu certo, mas não existe documento correspondente
/// em "usuarios" no Firestore. Diferente de "sem permissões": aqui o
/// cadastro em si ainda não existe.
class UnregisteredUserPage extends ConsumerWidget {
  const UnregisteredUserPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MessageScaffold(
      icon: Icons.person_off_outlined,
      title: 'Cadastro não encontrado',
      message: 'Seu login foi feito com sucesso, mas ainda não encontramos '
          'seu cadastro no sistema. Fale com um administrador para liberar '
          'seu acesso.',
      actions: [
        OutlinedButton(
          onPressed: () => confirmarESair(context, ref),
          child: const Text('Sair'),
        ),
      ],
    );
  }
}
