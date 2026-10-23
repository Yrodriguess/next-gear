import 'package:flutter/material.dart';

const double relatorioMaxWidth = 1280;
const double relatorioGap = 16;

String formatarReais(int centavos) {
  final absoluto = centavos.abs();
  final inteiro = (absoluto ~/ 100).toString();
  final decimal = (absoluto % 100).toString().padLeft(2, '0');
  final partes = <String>[];
  for (var fim = inteiro.length; fim > 0; fim -= 3) {
    final inicio = (fim - 3).clamp(0, inteiro.length).toInt();
    partes.insert(0, inteiro.substring(inicio, fim));
  }
  return '${centavos < 0 ? '- ' : ''}R\$ ${partes.join('.')},$decimal';
}

class RelatorioPageBody extends StatelessWidget {
  final Widget child;

  const RelatorioPageBody({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth < 700 ? 16.0 : 24.0;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: relatorioMaxWidth),
            child: Padding(
              padding: EdgeInsets.fromLTRB(horizontal, 20, horizontal, 32),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class RelatorioIntro extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? action;

  const RelatorioIntro({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final heading = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        );

        if (action == null) return heading;
        if (constraints.maxWidth < 680) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [heading, const SizedBox(height: 12), action!],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: heading),
            const SizedBox(width: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 210, maxWidth: 270),
              child: action!,
            ),
          ],
        );
      },
    );
  }
}

class RelatorioMetricsGrid extends StatelessWidget {
  final List<Widget> children;

  const RelatorioMetricsGrid({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1050
            ? 4
            : constraints.maxWidth >= 620
                ? 2
                : 1;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: children.map((child) => SizedBox(width: width, child: child)).toList(),
        );
      },
    );
  }
}

class RelatorioMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String? hint;
  final IconData icon;
  final Color? color;

  const RelatorioMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.hint,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = color ?? theme.colorScheme.primary;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accent, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 3),
                  Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  if (hint != null) ...[
                    const SizedBox(height: 2),
                    Text(hint!, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RelatorioSectionCard extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const RelatorioSectionCard({
    super.key,
    this.title,
    this.subtitle,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null || trailing != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (title != null) Text(title!, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        if (subtitle != null) ...[
                          const SizedBox(height: 3),
                          Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[const SizedBox(width: 12), trailing!],
                ],
              ),
              const SizedBox(height: 14),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class RelatorioStatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const RelatorioStatusPill({super.key, required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .42)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 5)],
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class RelatorioSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  const RelatorioSearchField({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Limpar busca',
                onPressed: () {
                  controller.clear();
                  onChanged?.call('');
                },
                icon: const Icon(Icons.close),
              ),
      ),
    );
  }
}

class RelatorioEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const RelatorioEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 14),
              Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              if (action != null) ...[const SizedBox(height: 18), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class RelatorioErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const RelatorioErrorState({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return RelatorioEmptyState(
      icon: Icons.cloud_off_outlined,
      title: 'Não foi possível carregar o relatório',
      message: 'Confira sua conexão e tente novamente.',
      action: OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Tentar novamente')),
    );
  }
}

class RelatorioLoading extends StatelessWidget {
  const RelatorioLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(48),
        child: CircularProgressIndicator(),
      ),
    );
  }
}
