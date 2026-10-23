import 'package:flutter/material.dart';

import 'message_scaffold.dart';

/// Tela de erro genérica para o usuário final. Os detalhes técnicos
/// (exceção, stack trace) devem ir para debugPrint/logs no momento em que
/// o erro é capturado — nunca aparecer direto nesta tela.
class FriendlyErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const FriendlyErrorView({
    super.key,
    this.message = 'Não foi possível carregar o sistema. Tente novamente.',
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return MessageScaffold(
      icon: Icons.error_outline,
      title: 'Ops!',
      message: message,
      actions: [
        if (onRetry != null)
          FilledButton(
            onPressed: onRetry,
            child: const Text('Tentar novamente'),
          ),
      ],
    );
  }
}
