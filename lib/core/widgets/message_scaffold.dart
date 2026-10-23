import 'package:flutter/material.dart';

/// Tela genérica de "estado especial": ícone + título + mensagem amigável
/// + ações opcionais (ex.: botão de sair, botão de tentar novamente).
///
/// Usada por telas de erro, usuário sem cadastro e usuário sem permissões,
/// pra manter a mesma identidade visual sem duplicar o layout em cada uma.
class MessageScaffold extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final List<Widget> actions;

  const MessageScaffold({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 56,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.center,
                      children: actions,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
