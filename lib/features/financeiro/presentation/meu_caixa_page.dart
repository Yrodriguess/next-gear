import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../clientes/domain/cliente.dart';
import '../../clientes/presentation/cliente_providers.dart';
import '../domain/acerto_caixa.dart';
import '../domain/pagamento.dart';
import 'financeiro_providers.dart';

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _data = DateFormat('dd/MM/yyyy');
String _reais(int centavos) => _moeda.format(centavos / 100);

/// Fechamento diário de caixa do vendedor — mostra o que ele recebeu
/// em dinheiro e ainda não repassou, detalhado por cliente, com o
/// total do dia. Pix e boleto não aparecem aqui: já contam como
/// recebidos na hora, não passam pelo vendedor.
class MeuCaixaPage extends ConsumerStatefulWidget {
  final String vendedorId;
  final String vendedorNome;

  const MeuCaixaPage({
    super.key,
    required this.vendedorId,
    required this.vendedorNome,
  });

  @override
  ConsumerState<MeuCaixaPage> createState() => _MeuCaixaPageState();
}

class _MeuCaixaPageState extends ConsumerState<MeuCaixaPage> {
  bool _isFechando = false;
  final _observacaoController = TextEditingController();

  @override
  void dispose() {
    _observacaoController.dispose();
    super.dispose();
  }

  Future<void> _handleFecharCaixa(List<Pagamento> pendentes) async {
    if (pendentes.isEmpty || _isFechando) return;

    final clientes = ref.read(clientesListProvider).value ?? const <Cliente>[];
    final nomePorId = <String, String>{
      for (final c in clientes)
        if (c.id != null) c.id!: c.nome,
    };

    final total = pendentes.fold<int>(0, (s, p) => s + p.valorTotalCentavos);

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Fechar caixa do dia?'),
        content: Text(
          'Você está declarando ${_reais(total)} em ${pendentes.length} '
          'recebimento(s). Depois de fechar, isso fica registrado e aguarda '
          'a confirmação do financeiro.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Fechar caixa'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => _isFechando = true);
    try {
      await ref.read(acertoCaixaRepositoryProvider).fecharCaixaDoDia(
            orgId: pendentes.first.orgId,
            vendedorId: widget.vendedorId,
            pagamentosPendentes: pendentes,
            nomeClientePorId: nomePorId,
            observacao: _observacaoController.text.trim().isEmpty
                ? null
                : _observacaoController.text.trim(),
          );
      _observacaoController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Caixa fechado! Aguardando confirmação do financeiro.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao fechar caixa: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isFechando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendentesAsync =
        ref.watch(pagamentosPendentesRepasseProvider(widget.vendedorId));
    final acertosAsync = ref.watch(meusAcertosCaixaProvider(widget.vendedorId));
    final clientesAsync = ref.watch(clientesListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Meu caixa')),
      body: pendentesAsync.when(
        data: (pendentes) {
          final nomePorId = <String, String>{
            for (final c in (clientesAsync.value ?? const <Cliente>[]))
              if (c.id != null) c.id!: c.nome,
          };
          final total =
              pendentes.fold<int>(0, (s, p) => s + p.valorTotalCentavos);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Pendente de repasse hoje',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 4),
                      Text(_reais(total),
                          style: const TextStyle(
                              fontSize: 28, fontWeight: FontWeight.bold)),
                      Text('${pendentes.length} recebimento(s) em dinheiro'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (pendentes.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                      child: Text('Nada pendente de repasse no momento.')),
                )
              else ...[
                Text('Detalhamento por cliente',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < pendentes.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          title:
                              Text(nomePorId[pendentes[i].clienteId] ?? 'Cliente'),
                          subtitle: pendentes[i].criadoEm != null
                              ? Text(DateFormat('dd/MM HH:mm')
                                  .format(pendentes[i].criadoEm!))
                              : null,
                          trailing: Text(_reais(pendentes[i].valorTotalCentavos)),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _observacaoController,
                  decoration: const InputDecoration(
                    labelText: 'Observação (opcional)',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _isFechando
                      ? null
                      : () => _handleFecharCaixa(pendentes),
                  icon: _isFechando
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.lock_outline),
                  label: Text(_isFechando
                      ? 'Fechando...'
                      : 'Fechar caixa do dia'),
                ),
              ],
              const Divider(height: 40),
              Text('Meus acertos', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              acertosAsync.when(
                data: (acertos) {
                  if (acertos.isEmpty) {
                    return const Text('Nenhum acerto fechado ainda.',
                        style: TextStyle(color: Colors.grey));
                  }
                  return Column(
                    children: [
                      for (final acerto in acertos)
                        Card(
                          child: ListTile(
                            title: Text(_reais(acerto.valorTotalCentavos)),
                            subtitle: Text(
                                '${_data.format(acerto.data)} • ${acerto.itens.length} recebimento(s)'),
                            trailing: Chip(
                              label: Text(
                                acerto.status == StatusAcertoCaixa.confirmado
                                    ? 'Confirmado'
                                    : 'Aguardando',
                              ),
                              backgroundColor:
                                  acerto.status == StatusAcertoCaixa.confirmado
                                      ? Colors.green.withValues(alpha: 0.15)
                                      : Colors.orange.withValues(alpha: 0.15),
                            ),
                          ),
                        ),
                    ],
                  );
                },
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, st) => Text('Erro ao carregar acertos: $e'),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Erro ao carregar: $e')),
      ),
    );
  }
}
