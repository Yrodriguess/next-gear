import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/responsive_center.dart';
import '../../clientes/domain/cliente.dart';
import '../domain/recebivel.dart';
import 'financeiro_providers.dart';

class ContasReceberPage extends ConsumerStatefulWidget {
  final Cliente cliente;
  const ContasReceberPage({super.key, required this.cliente});

  @override
  ConsumerState<ContasReceberPage> createState() => _ContasReceberPageState();
}

class _ContasReceberPageState extends ConsumerState<ContasReceberPage> {
  final _valorController = TextEditingController();
  bool _isSaving = false;
  String? _errorMessage;

  String _reais(int centavos) => 'R\$ ${(centavos / 100).toStringAsFixed(2)}';

  Future<void> _handlePagar() async {
    final valorReais = double.tryParse(_valorController.text.replaceAll(',', '.'));
    if (valorReais == null || valorReais <= 0) {
      setState(() => _errorMessage = 'Informe um valor válido.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await ref.read(pagamentoRepositoryProvider).registrarEAlocar(
        orgId: widget.cliente.orgId,
        clienteId: widget.cliente.id!,
        valorTotalCentavos: (valorReais * 100).round(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pagamento registrado!')),
        );
        _valorController.clear();
      }
    } catch (e) {
      setState(() => _errorMessage = 'Erro: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recebiveisAsync =
    ref.watch(recebiveisDoClienteProvider(widget.cliente.id!));

    return Scaffold(
      appBar: AppBar(title: Text('Contas a Receber — ${widget.cliente.nome}')),
      body: SingleChildScrollView(
        child: ResponsiveCenter(
          maxWidth: 640,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Registrar pagamento',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              const Text(
                'O valor é alocado automaticamente entre as cobranças em aberto, da mais antiga pra mais nova — ver seção 15.1 do Blueprint.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _valorController,
                      decoration: const InputDecoration(labelText: 'Valor recebido (R\$)'),
                      keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _handlePagar,
                    child: _isSaving
                        ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Registrar'),
                  ),
                ],
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              ],
              const Divider(height: 40),
              Text('Cobranças', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              recebiveisAsync.when(
                data: (recebiveis) {
                  if (recebiveis.isEmpty) {
                    return const Text('Nenhuma cobrança gerada ainda.',
                        style: TextStyle(color: Colors.grey));
                  }
                  return Column(
                    children: recebiveis
                        .map((r) => Card(
                      child: ListTile(
                        title: Text(r.numero),
                        subtitle: Text(
                          r.dataVencimento != null
                              ? 'Vence em ${DateFormat('dd/MM/yyyy').format(r.dataVencimento!)}'
                              : '',
                        ),
                        trailing: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_reais(r.valorCentavos)),
                            _RecebivelStatusChip(status: r.status),
                          ],
                        ),
                      ),
                    ))
                        .toList(),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Erro: $e'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecebivelStatusChip extends StatelessWidget {
  final RecebivelStatus status;
  const _RecebivelStatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      RecebivelStatus.aberto => ('Aberto', Colors.orange),
      RecebivelStatus.parcial => ('Parcial', Colors.blue),
      RecebivelStatus.pago => ('Pago', Colors.green),
      RecebivelStatus.vencido => ('Vencido', Colors.red),
      RecebivelStatus.cancelado => ('Cancelado', Colors.grey),
    };
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      backgroundColor: color.withValues(alpha: 0.2),
      side: BorderSide(color: color),
      padding: EdgeInsets.zero,
    );
  }
}