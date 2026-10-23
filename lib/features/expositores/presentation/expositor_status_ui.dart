import 'package:flutter/material.dart';

import '../domain/expositor_fisico.dart';

/// Nome, cor e ícone de cada status — centralizado aqui pra não
/// repetir a mesma lógica na lista, no detalhe e no relatório.
String statusLabel(ExpositorStatus status) => switch (status) {
      ExpositorStatus.disponivel => 'Disponível',
      ExpositorStatus.reservado => 'Reservado',
      ExpositorStatus.instalado => 'Instalado',
      ExpositorStatus.manutencao => 'Manutenção',
      ExpositorStatus.recolhido => 'Recolhido',
      ExpositorStatus.descartado => 'Descartado',
      ExpositorStatus.perdido => 'Perdido',
    };

Color statusColor(ExpositorStatus status) => switch (status) {
      ExpositorStatus.disponivel => Colors.green,
      ExpositorStatus.reservado => Colors.blue,
      ExpositorStatus.instalado => Colors.teal,
      ExpositorStatus.manutencao => Colors.orange,
      ExpositorStatus.recolhido => Colors.blueGrey,
      ExpositorStatus.descartado => Colors.grey,
      ExpositorStatus.perdido => Colors.red,
    };

IconData statusIcon(ExpositorStatus status) => switch (status) {
      ExpositorStatus.disponivel => Icons.check_circle_outline,
      ExpositorStatus.reservado => Icons.bookmark_border,
      ExpositorStatus.instalado => Icons.store_outlined,
      ExpositorStatus.manutencao => Icons.build_outlined,
      ExpositorStatus.recolhido => Icons.inventory_2_outlined,
      ExpositorStatus.descartado => Icons.delete_outline,
      ExpositorStatus.perdido => Icons.help_outline,
    };

/// Selo visual de status — ícone + cor + texto, nunca só cor sozinha
/// (acessibilidade).
class StatusChip extends StatelessWidget {
  final ExpositorStatus status;
  const StatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    return Chip(
      avatar: Icon(statusIcon(status), size: 16, color: color),
      label: Text(statusLabel(status), style: const TextStyle(fontSize: 12)),
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide(color: color.withValues(alpha: 0.5)),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      visualDensity: VisualDensity.compact,
    );
  }
}
