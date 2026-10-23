import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_providers.dart';

/// Pede confirmação antes de sair (evita logout acidental) e trata
/// qualquer erro do signOut() em vez de deixar a chamada sem tratamento.
Future<void> confirmarESair(BuildContext context, WidgetRef ref) async {
  final confirmar = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Sair da conta'),
      content: const Text('Tem certeza que deseja sair do NEXT GEAR?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Sair'),
        ),
      ],
    ),
  );

  if (confirmar != true) return;

  try {
    await ref.read(authRepositoryProvider).signOut();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível sair. Tente novamente.'),
        ),
      );
    }
  }
}
