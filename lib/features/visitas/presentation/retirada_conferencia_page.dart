import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../clientes/domain/cliente.dart';
import '../../consignacoes/domain/consignment.dart';
import '../../expositores/domain/expositor_fisico.dart';
import '../../produtos/presentation/produto_providers.dart';
import '../domain/visita_resultado.dart';
import 'retirada_resultado_page.dart';
import 'visita_providers.dart';

String destinoRetiradaLabel(DestinoRetirada destino) => switch (destino) {
  DestinoRetirada.estoque => 'Estoque central (boas condições)',
  DestinoRetirada.recolhido => 'Recolhido — aguardando conferência',
  DestinoRetirada.manutencao => 'Manutenção',
  DestinoRetirada.descarte => 'Descarte',
  DestinoRetirada.perdido => 'Perdido',
};

String estadoConservacaoLabel(EstadoConservacao estado) => switch (estado) {
  EstadoConservacao.novo => 'Novo',
  EstadoConservacao.bom => 'Bom',
  EstadoConservacao.regular => 'Regular',
  EstadoConservacao.ruim => 'Ruim',
};

/// Destinos que indicam problema e exigem uma justificativa.
const _destinosQueExigemObservacao = {
  DestinoRetirada.manutencao,
  DestinoRetirada.descarte,
  DestinoRetirada.perdido,
};

class RetiradaConferenciaPage extends ConsumerStatefulWidget {
  final Cliente cliente;
  final Consignment consignmentAtiva;
  final ExpositorFisico expositor;

  const RetiradaConferenciaPage({
    super.key,
    required this.cliente,
    required this.consignmentAtiva,
    required this.expositor,
  });

  @override
  ConsumerState<RetiradaConferenciaPage> createState() =>
      _RetiradaConferenciaPageState();
}

class _RetiradaConferenciaPageState
    extends ConsumerState<RetiradaConferenciaPage> {
  int _etapa = 0;

  late final Map<String, int> _quantidadeDevolvida;
  final Set<String> _itensConferidos = {};
  final Map<String, ClassificacaoNaoDevolvida> _classificacao = {};

  final _observacaoController = TextEditingController();
  MotivoRetirada _motivo = MotivoRetirada.solicitacaoCliente;
  DestinoRetirada _destino = DestinoRetirada.recolhido;
  EstadoConservacao _estadoConservacao = EstadoConservacao.bom;

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _quantidadeDevolvida = {
      for (final item in widget.consignmentAtiva.itens)
        item.produtoId: item.quantidade,
    };
  }

  @override
  void dispose() {
    _observacaoController.dispose();
    super.dispose();
  }

  int get _totalEsperado => widget.consignmentAtiva.itens
      .fold<int>(0, (total, item) => total + item.quantidade);

  int get _totalDevolvido => widget.consignmentAtiva.itens.fold<int>(
    0,
        (total, item) =>
    total + (_quantidadeDevolvida[item.produtoId] ?? 0),
  );

  int get _totalNaoDevolvido => _totalEsperado - _totalDevolvido;

  bool get _todosConferidos =>
      _itensConferidos.length == widget.consignmentAtiva.itens.length;

  bool get _observacaoObrigatoria =>
      _destinosQueExigemObservacao.contains(_destino) ||
          _motivo == MotivoRetirada.outro;

  bool get _podeAvancarMotivo =>
      !_observacaoObrigatoria ||
          _observacaoController.text.trim().isNotEmpty;

  String get _nomeCliente => widget.cliente.nome;

  bool _itemPrecisaClassificacao(String produtoId) {
    final esperado = widget.consignmentAtiva.itens
        .firstWhere((item) => item.produtoId == produtoId)
        .quantidade;
    final devolvida = _quantidadeDevolvida[produtoId] ?? 0;
    return esperado - devolvida > 0;
  }

  void _alterarQuantidade({
    required String produtoId,
    required int quantidade,
    required int esperado,
  }) {
    setState(() {
      _quantidadeDevolvida[produtoId] =
          quantidade.clamp(0, esperado).toInt();
      _itensConferidos.remove(produtoId);

      if (quantidade >= esperado) {
        _classificacao.remove(produtoId);
      }
    });
  }

  void _confirmarConferenciaItem(String produtoId) {
    if (_itemPrecisaClassificacao(produtoId) &&
        _classificacao[produtoId] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Classifique o que aconteceu antes de confirmar este item.',
          ),
        ),
      );
      return;
    }

    setState(() => _itensConferidos.add(produtoId));
  }

  void _confirmarTudoDevolvido() {
    setState(() {
      for (final item in widget.consignmentAtiva.itens) {
        _quantidadeDevolvida[item.produtoId] = item.quantidade;
        _classificacao.remove(item.produtoId);
        _itensConferidos.add(item.produtoId);
      }
    });
  }

  void _irParaEtapa(int etapa) {
    if (_isSaving || etapa < 0 || etapa > 2) return;

    if (etapa > _etapa) {
      if (_etapa == 0 && !_todosConferidos) return;
      if (_etapa == 1 && !_podeAvancarMotivo) return;
    }

    setState(() {
      _etapa = etapa;
      _errorMessage = null;
    });
  }

  Future<void> _handleConfirmar() async {
    final usuario = ref.read(appUserProvider).value;
    if (usuario == null) {
      setState(() {
        _errorMessage =
        'Sua sessão não está disponível. Entre novamente para continuar.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final skus = ref.read(skusListProvider).value ?? [];
      final codigoInternoPorProduto = {
        for (final sku in skus)
          if (sku.id != null) sku.id!: sku.codigoInterno,
      };

      final conferencia = widget.consignmentAtiva.itens
          .map(
            (item) => ItemRetirada(
          produtoId: item.produtoId,
          codigoInterno:
          codigoInternoPorProduto[item.produtoId] ?? item.produtoId,
          descricaoSnapshot: item.descricaoSnapshot,
          quantidadeEsperada: item.quantidade,
          quantidadeDevolvida:
          _quantidadeDevolvida[item.produtoId] ?? 0,
          classificacao: _classificacao[item.produtoId],
        ),
      )
          .toList();

      final resultado = await ref.read(visitaServiceProvider).executarRetirada(
        orgId: widget.cliente.orgId,
        cliente: widget.cliente,
        vendedorId: usuario.uid,
        consignmentAtiva: widget.consignmentAtiva,
        conferenciaRetirada: conferencia,
        expositorId: widget.expositor.id!,
        expositorNumero: widget.expositor.numero,
        expositorModeloNome: widget.expositor.modeloNome,
        destinoExpositor: _destino,
        destinoExpositorLabel: destinoRetiradaLabel(_destino),
        motivo: _motivo,
        observacao: _observacaoController.text.trim().isEmpty
            ? null
            : _observacaoController.text.trim(),
        estadoConservacaoExpositor: _estadoConservacao,
      );

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => RetiradaResultadoPage(
            resultado: resultado,
            orgId: widget.cliente.orgId,
            clienteId: widget.cliente.id!,
            nomeCliente: widget.cliente.nome,
            cpfCnpjCliente: widget.cliente.cpfCnpj,
            vendedorNome: usuario.nome,
          ),
        ),
      );
    } catch (error, stack) {
      debugPrint('Erro ao executar retirada: $error\n$stack');
      if (mounted) {
        setState(() {
          _errorMessage =
          'Não foi possível concluir a retirada. Tente novamente.';
        });
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Retirada do expositor'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: _StatusBadge(
                icon: Icons.inventory_2_outlined,
                label: widget.expositor.numero,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final mobile = constraints.maxWidth < 600;
            final horizontalPadding = mobile ? 12.0 : 24.0;

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                mobile ? 12 : 24,
                horizontalPadding,
                28,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ContextoRetiradaCard(
                        nomeCliente: _nomeCliente,
                        cpfCnpj: widget.cliente.cpfCnpj,
                        expositorNumero: widget.expositor.numero,
                        expositorModelo: widget.expositor.modeloNome,
                        consignacaoNumero: widget.consignmentAtiva.numero,
                      ),
                      const SizedBox(height: 16),
                      _EtapasRetirada(
                        etapaAtual: _etapa,
                        onEtapaPressed: (etapa) {
                          if (etapa <= _etapa) _irParaEtapa(etapa);
                        },
                      ),
                      SizedBox(height: mobile ? 20 : 28),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: KeyedSubtree(
                          key: ValueKey(_etapa),
                          child: switch (_etapa) {
                            0 => _buildEtapaConferencia(context),
                            1 => _buildEtapaMotivoDestino(context),
                            _ => _buildEtapaRevisao(context),
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: _buildBottomActions(context),
    );
  }

  Widget _buildBottomActions(BuildContext context) {
    final podeContinuar = switch (_etapa) {
      0 => _todosConferidos,
      1 => _podeAvancarMotivo,
      _ => !_isSaving,
    };

    final textoPrincipal = switch (_etapa) {
      0 => 'Continuar',
      1 => 'Revisar retirada',
      _ => 'Confirmar e coletar assinatura',
    };

    final iconePrincipal = switch (_etapa) {
      0 => Icons.arrow_forward,
      1 => Icons.fact_check_outlined,
      _ => Icons.draw_outlined,
    };

    String? ajuda;
    if (_etapa == 0 && !_todosConferidos) {
      final pendentes =
          widget.consignmentAtiva.itens.length - _itensConferidos.length;
      ajuda = '$pendentes item(ns) ainda precisam ser conferidos.';
    } else if (_etapa == 1 && !_podeAvancarMotivo) {
      ajuda = 'Informe uma observação para o motivo ou destino escolhido.';
    }

    return _RetiradaBottomActions(
      textoPrincipal: textoPrincipal,
      iconePrincipal: iconePrincipal,
      podeContinuar: podeContinuar,
      carregando: _isSaving,
      ajuda: ajuda,
      onVoltar: _etapa == 0 ? null : () => _irParaEtapa(_etapa - 1),
      onContinuar: () {
        if (_etapa == 2) {
          _handleConfirmar();
        } else {
          _irParaEtapa(_etapa + 1);
        }
      },
    );
  }

  Widget _buildEtapaConferencia(BuildContext context) {
    final theme = Theme.of(context);
    final quantidadeItens = widget.consignmentAtiva.itens.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PageHeading(
          eyebrow: 'ETAPA 1 DE 3',
          title: 'Confira o que voltou',
          description:
          'Ajuste as quantidades e confirme cada produto. Toda diferença '
              'precisa ser classificada antes de continuar.',
          trailing: FilledButton.tonalIcon(
            onPressed: quantidadeItens == 0 ? null : _confirmarTudoDevolvido,
            icon: const Icon(Icons.done_all),
            label: const Text('Tudo voltou'),
          ),
        ),
        const SizedBox(height: 20),
        _ResumoQuantidades(
          totalEsperado: _totalEsperado,
          totalDevolvido: _totalDevolvido,
          totalNaoDevolvido: _totalNaoDevolvido,
          conferidos: _itensConferidos.length,
          totalItens: quantidadeItens,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                'Produtos da consignação',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '${_itensConferidos.length} de $quantidadeItens conferidos',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (widget.consignmentAtiva.itens.isEmpty)
          const _EmptyItemsCard()
        else
          ...widget.consignmentAtiva.itens.map((item) {
            final devolvida = _quantidadeDevolvida[item.produtoId] ?? 0;
            final conferido = _itensConferidos.contains(item.produtoId);

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ProdutoConferenciaCard(
                descricao: item.descricaoSnapshot,
                esperado: item.quantidade,
                devolvido: devolvida,
                conferido: conferido,
                classificacao: _classificacao[item.produtoId],
                onDiminuir: devolvida > 0
                    ? () => _alterarQuantidade(
                  produtoId: item.produtoId,
                  quantidade: devolvida - 1,
                  esperado: item.quantidade,
                )
                    : null,
                onAumentar: devolvida < item.quantidade
                    ? () => _alterarQuantidade(
                  produtoId: item.produtoId,
                  quantidade: devolvida + 1,
                  esperado: item.quantidade,
                )
                    : null,
                onClassificacaoChanged: (classificacao) {
                  setState(() {
                    _classificacao[item.produtoId] = classificacao;
                  });
                },
                onConfirmar: () =>
                    _confirmarConferenciaItem(item.produtoId),
                onReabrir: () {
                  setState(() => _itensConferidos.remove(item.produtoId));
                },
              ),
            );
          }),
      ],
    );
  }

  Widget _buildEtapaMotivoDestino(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _PageHeading(
          eyebrow: 'ETAPA 2 DE 3',
          title: 'Motivo e destino',
          description:
          'Registre por que o expositor está sendo retirado, sua condição '
              'aparente e para onde ele seguirá.',
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final duasColunas = constraints.maxWidth >= 820;

            final motivo = _SectionCard(
              icon: Icons.assignment_outlined,
              title: 'Motivo da retirada',
              description: 'Selecione a razão informada para a retirada.',
              child: DropdownButtonFormField<MotivoRetirada>(
                initialValue: _motivo,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Motivo',
                  prefixIcon: Icon(Icons.help_outline),
                ),
                items: MotivoRetirada.values
                    .map(
                      (motivo) => DropdownMenuItem(
                    value: motivo,
                    child: Text(
                      motivoRetiradaLabel(motivo),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                    .toList(),
                onChanged: (motivo) {
                  if (motivo != null) setState(() => _motivo = motivo);
                },
              ),
            );

            final destino = _SectionCard(
              icon: Icons.local_shipping_outlined,
              title: 'Expositor e destino',
              description:
              'Informe a condição visual e o encaminhamento inicial.',
              child: Column(
                children: [
                  DropdownButtonFormField<EstadoConservacao>(
                    initialValue: _estadoConservacao,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Condição aparente',
                      prefixIcon: Icon(Icons.health_and_safety_outlined),
                    ),
                    items: EstadoConservacao.values
                        .map(
                          (estado) => DropdownMenuItem(
                        value: estado,
                        child: Text(estadoConservacaoLabel(estado)),
                      ),
                    )
                        .toList(),
                    onChanged: (estado) {
                      if (estado != null) {
                        setState(() => _estadoConservacao = estado);
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<DestinoRetirada>(
                    initialValue: _destino,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Destino do expositor',
                      prefixIcon: Icon(Icons.route_outlined),
                    ),
                    items: DestinoRetirada.values
                        .map(
                          (destino) => DropdownMenuItem(
                        value: destino,
                        child: Text(
                          destinoRetiradaLabel(destino),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                        .toList(),
                    onChanged: (destino) {
                      if (destino != null) setState(() => _destino = destino);
                    },
                  ),
                ],
              ),
            );

            if (!duasColunas) {
              return Column(
                children: [
                  motivo,
                  const SizedBox(height: 12),
                  destino,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: motivo),
                const SizedBox(width: 16),
                Expanded(child: destino),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        _SectionCard(
          icon: Icons.notes_outlined,
          title: 'Observações',
          description: _observacaoObrigatoria
              ? 'Obrigatória para o motivo ou destino selecionado.'
              : 'Opcional. Registre avarias, combinações ou informações úteis.',
          accentColor: _observacaoObrigatoria
              ? Theme.of(context).colorScheme.error
              : null,
          child: TextFormField(
            controller: _observacaoController,
            minLines: 3,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: _observacaoObrigatoria
                  ? 'Observação obrigatória'
                  : 'Observação',
              hintText: 'Descreva detalhes relevantes da retirada...',
              alignLabelWithHint: true,
              prefixIcon: const Padding(
                padding: EdgeInsets.only(bottom: 58),
                child: Icon(Icons.edit_note_outlined),
              ),
              errorText: _observacaoObrigatoria &&
                  _observacaoController.text.trim().isEmpty
                  ? 'Explique o motivo ou o destino selecionado.'
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 12),
        const _InfoBanner(
          icon: Icons.info_outline,
          text:
          'O destino “Recolhido” mantém o expositor aguardando a '
              'conferência interna antes da decisão final.',
        ),
      ],
    );
  }

  Widget _buildEtapaRevisao(BuildContext context) {
    final itensComDivergencia = widget.consignmentAtiva.itens
        .where(
          (item) =>
      (_quantidadeDevolvida[item.produtoId] ?? 0) < item.quantidade,
    )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _PageHeading(
          eyebrow: 'ETAPA 3 DE 3',
          title: 'Revise antes de confirmar',
          description:
          'Confira os totais e o encaminhamento. Depois da confirmação, '
              'a próxima etapa será a coleta da assinatura.',
        ),
        const SizedBox(height: 20),
        _ResumoQuantidades(
          totalEsperado: _totalEsperado,
          totalDevolvido: _totalDevolvido,
          totalNaoDevolvido: _totalNaoDevolvido,
          conferidos: _itensConferidos.length,
          totalItens: widget.consignmentAtiva.itens.length,
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final duasColunas = constraints.maxWidth >= 820;

            final resumo = _SectionCard(
              icon: Icons.receipt_long_outlined,
              title: 'Dados da retirada',
              child: Column(
                children: [
                  _ReviewRow(
                    label: 'Motivo',
                    value: motivoRetiradaLabel(_motivo),
                  ),
                  const Divider(height: 24),
                  _ReviewRow(
                    label: 'Condição do expositor',
                    value: estadoConservacaoLabel(_estadoConservacao),
                  ),
                  const Divider(height: 24),
                  _ReviewRow(
                    label: 'Destino',
                    value: destinoRetiradaLabel(_destino),
                  ),
                  if (_observacaoController.text.trim().isNotEmpty) ...[
                    const Divider(height: 24),
                    _ReviewRow(
                      label: 'Observação',
                      value: _observacaoController.text.trim(),
                    ),
                  ],
                ],
              ),
            );

            final proximoPasso = _SectionCard(
              icon: Icons.draw_outlined,
              title: 'Próximo passo',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _TimelineItem(
                    active: true,
                    icon: Icons.fact_check_outlined,
                    title: 'Conferência registrada',
                    description: 'Quantidades e divergências desta retirada.',
                  ),
                  const _TimelineItem(
                    active: false,
                    icon: Icons.draw_outlined,
                    title: 'Coleta de assinatura',
                    description:
                    'A assinatura será solicitada na próxima tela.',
                  ),
                  const _TimelineItem(
                    active: false,
                    last: true,
                    icon: Icons.description_outlined,
                    title: 'Documento da visita',
                    description:
                    'O comprovante ficará vinculado ao histórico.',
                  ),
                ],
              ),
            );

            if (!duasColunas) {
              return Column(
                children: [
                  resumo,
                  const SizedBox(height: 12),
                  proximoPasso,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: resumo),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: proximoPasso),
              ],
            );
          },
        ),
        if (itensComDivergencia.isNotEmpty) ...[
          const SizedBox(height: 12),
          _DivergenciasCard(
            children: itensComDivergencia
                .map(
                  (item) => _DivergenciaRow(
                descricao: item.descricaoSnapshot,
                esperado: item.quantidade,
                devolvido:
                _quantidadeDevolvida[item.produtoId] ?? 0,
                classificacao: classificacaoNaoDevolvidaLabel(
                  _classificacao[item.produtoId]!,
                ),
              ),
            )
                .toList(),
          ),
        ],
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          _ErrorBanner(message: _errorMessage!),
        ],
      ],
    );
  }
}

class _ContextoRetiradaCard extends StatelessWidget {
  final String nomeCliente;
  final String cpfCnpj;
  final String expositorNumero;
  final String expositorModelo;
  final String consignacaoNumero;

  const _ContextoRetiradaCard({
    required this.nomeCliente,
    required this.cpfCnpj,
    required this.expositorNumero,
    required this.expositorModelo,
    required this.consignacaoNumero,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colors.primaryContainer.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.primary.withValues(alpha: 0.16)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final mobile = constraints.maxWidth < 620;

            final cliente = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: mobile ? 22 : 25,
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                  child: const Icon(Icons.storefront_outlined),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nomeCliente,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        cpfCnpj,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );

            final detalhes = Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: mobile ? WrapAlignment.start : WrapAlignment.end,
              children: [
                _InfoChip(
                  icon: Icons.inventory_2_outlined,
                  label: 'Expositor $expositorNumero',
                ),
                _InfoChip(
                  icon: Icons.category_outlined,
                  label: expositorModelo,
                ),
                _InfoChip(
                  icon: Icons.assignment_outlined,
                  label: 'Consignação $consignacaoNumero',
                ),
              ],
            );

            if (mobile) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  cliente,
                  const SizedBox(height: 14),
                  detalhes,
                ],
              );
            }

            return Row(
              children: [
                Expanded(flex: 4, child: cliente),
                const SizedBox(width: 24),
                Expanded(flex: 6, child: detalhes),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EtapasRetirada extends StatelessWidget {
  final int etapaAtual;
  final ValueChanged<int> onEtapaPressed;

  const _EtapasRetirada({
    required this.etapaAtual,
    required this.onEtapaPressed,
  });

  @override
  Widget build(BuildContext context) {
    const etapas = [
      ('Conferência', 'Produtos'),
      ('Motivo', 'Destino'),
      ('Revisão', 'Assinatura'),
    ];

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            for (var index = 0; index < etapas.length; index++) ...[
              Expanded(
                child: _EtapaItem(
                  numero: index + 1,
                  titulo: etapas[index].$1,
                  subtitulo: etapas[index].$2,
                  ativa: index == etapaAtual,
                  concluida: index < etapaAtual,
                  onPressed:
                  index <= etapaAtual ? () => onEtapaPressed(index) : null,
                ),
              ),
              if (index < etapas.length - 1)
                Container(
                  width: 12,
                  height: 1,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EtapaItem extends StatelessWidget {
  final int numero;
  final String titulo;
  final String subtitulo;
  final bool ativa;
  final bool concluida;
  final VoidCallback? onPressed;

  const _EtapaItem({
    required this.numero,
    required this.titulo,
    required this.subtitulo,
    required this.ativa,
    required this.concluida,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final destaque = ativa || concluida;

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compacto = constraints.maxWidth < 150;

            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: destaque ? colors.primary : colors.surfaceContainer,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: destaque ? colors.primary : colors.outlineVariant,
                    ),
                  ),
                  child: concluida
                      ? Icon(Icons.check, size: 18, color: colors.onPrimary)
                      : Text(
                    '$numero',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: destaque
                          ? colors.onPrimary
                          : colors.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (!compacto) ...[
                  const SizedBox(width: 9),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titulo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: ativa
                                ? colors.primary
                                : colors.onSurface,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          subtitulo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PageHeading extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String description;
  final Widget? trailing;

  const _PageHeading({
    required this.eyebrow,
    required this.title,
    required this.description,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compacto = constraints.maxWidth < 700;

        final textos = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              eyebrow,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        );

        if (trailing == null) return textos;

        if (compacto) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              textos,
              const SizedBox(height: 14),
              Align(alignment: Alignment.centerLeft, child: trailing!),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: textos),
            const SizedBox(width: 24),
            trailing!,
          ],
        );
      },
    );
  }
}

class _ResumoQuantidades extends StatelessWidget {
  final int totalEsperado;
  final int totalDevolvido;
  final int totalNaoDevolvido;
  final int conferidos;
  final int totalItens;

  const _ResumoQuantidades({
    required this.totalEsperado,
    required this.totalDevolvido,
    required this.totalNaoDevolvido,
    required this.conferidos,
    required this.totalItens,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final colunas = constraints.maxWidth >= 760 ? 4 : 2;
        const gap = 10.0;
        final largura =
            (constraints.maxWidth - (gap * (colunas - 1))) / colunas;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            _MetricCard(
              width: largura,
              icon: Icons.inventory_2_outlined,
              label: 'Esperado',
              value: '$totalEsperado',
              color: colors.primary,
            ),
            _MetricCard(
              width: largura,
              icon: Icons.keyboard_return_outlined,
              label: 'Devolvido',
              value: '$totalDevolvido',
              color: colors.primary,
            ),
            _MetricCard(
              width: largura,
              icon: Icons.warning_amber_rounded,
              label: 'Não devolvido',
              value: '$totalNaoDevolvido',
              color: totalNaoDevolvido > 0
                  ? colors.error
                  : colors.onSurfaceVariant,
            ),
            _MetricCard(
              width: largura,
              icon: Icons.fact_check_outlined,
              label: 'Itens conferidos',
              value: '$conferidos/$totalItens',
              color: conferidos == totalItens
                  ? colors.primary
                  : colors.tertiary,
            ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  final double width;
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MetricCard({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProdutoConferenciaCard extends StatelessWidget {
  final String descricao;
  final int esperado;
  final int devolvido;
  final bool conferido;
  final ClassificacaoNaoDevolvida? classificacao;
  final VoidCallback? onDiminuir;
  final VoidCallback? onAumentar;
  final ValueChanged<ClassificacaoNaoDevolvida> onClassificacaoChanged;
  final VoidCallback onConfirmar;
  final VoidCallback onReabrir;

  const _ProdutoConferenciaCard({
    required this.descricao,
    required this.esperado,
    required this.devolvido,
    required this.conferido,
    required this.classificacao,
    required this.onDiminuir,
    required this.onAumentar,
    required this.onClassificacaoChanged,
    required this.onConfirmar,
    required this.onReabrir,
  });

  int get naoDevolvido => esperado - devolvido;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final statusColor = conferido ? colors.primary : colors.onSurfaceVariant;

    final produto = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            conferido ? Icons.check_rounded : Icons.inventory_2_outlined,
            color: statusColor,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                descricao,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Esperado: $esperado',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  if (conferido)
                    const _StatusBadge(
                      icon: Icons.check_circle_outline,
                      label: 'Conferido',
                      success: true,
                    ),
                  if (naoDevolvido > 0)
                    _StatusBadge(
                      icon: Icons.warning_amber_rounded,
                      label: '$naoDevolvido não devolvido(s)',
                      warning: true,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    final quantidade = _QuantityControl(
      value: devolvido,
      enabled: !conferido,
      onDecrease: onDiminuir,
      onIncrease: onAumentar,
    );

    final acao = conferido
        ? OutlinedButton.icon(
      onPressed: onReabrir,
      icon: const Icon(Icons.edit_outlined),
      label: const Text('Reabrir'),
    )
        : FilledButton.icon(
      onPressed: onConfirmar,
      icon: const Icon(Icons.check),
      label: const Text('Confirmar item'),
    );

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: conferido
          ? colors.primary.withValues(alpha: 0.055)
          : colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: conferido
              ? colors.primary.withValues(alpha: 0.34)
              : colors.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 760;
            final podeManterAcoesNaMesmaLinha =
                constraints.maxWidth >= 520;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (desktop)
                  Row(
                    children: [
                      Expanded(child: produto),
                      const SizedBox(width: 24),
                      quantidade,
                      const SizedBox(width: 16),
                      SizedBox(width: 176, child: acao),
                    ],
                  )
                else if (podeManterAcoesNaMesmaLinha) ...[
                  produto,
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: quantidade),
                      const SizedBox(width: 12),
                      Flexible(child: acao),
                    ],
                  ),
                ] else ...[
                  produto,
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: quantidade,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(width: double.infinity, child: acao),
                ],
                if (naoDevolvido > 0) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.errorContainer.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'O que aconteceu com a diferença?',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children:
                          ClassificacaoNaoDevolvida.values.map((opcao) {
                            return ChoiceChip(
                              label: Text(
                                classificacaoNaoDevolvidaLabel(opcao),
                              ),
                              selected: classificacao == opcao,
                              onSelected: conferido
                                  ? null
                                  : (_) => onClassificacaoChanged(opcao),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _QuantityControl extends StatelessWidget {
  final int value;
  final bool enabled;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;

  const _QuantityControl({
    required this.value,
    required this.enabled,
    required this.onDecrease,
    required this.onIncrease,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: 'Quantidade devolvida: $value',
      child: Container(
        height: 48,
        constraints: const BoxConstraints(minWidth: 164, maxWidth: 190),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Diminuir quantidade',
              onPressed: enabled ? onDecrease : null,
              icon: const Icon(Icons.remove),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$value',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'devolvida',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Aumentar quantidade',
              onPressed: enabled ? onIncrease : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? description;
  final Widget child;
  final Color? accentColor;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
    this.description,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = accentColor ?? theme.colorScheme.primary;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (description != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          description!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  final String label;
  final String value;

  const _ReviewRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final empilhar = constraints.maxWidth < 430;
        final labelWidget = Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        );
        final valueWidget = Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        );

        if (empilhar) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              labelWidget,
              const SizedBox(height: 4),
              valueWidget,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 170, child: labelWidget),
            const SizedBox(width: 12),
            Expanded(child: valueWidget),
          ],
        );
      },
    );
  }
}

class _DivergenciasCard extends StatelessWidget {
  final List<Widget> children;

  const _DivergenciasCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colors.errorContainer.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.error.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: colors.error),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Produtos com divergência',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < children.length; index++) ...[
              children[index],
              if (index < children.length - 1)
                Divider(
                  height: 22,
                  color: colors.error.withValues(alpha: 0.18),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DivergenciaRow extends StatelessWidget {
  final String descricao;
  final int esperado;
  final int devolvido;
  final String classificacao;

  const _DivergenciaRow({
    required this.descricao,
    required this.esperado,
    required this.devolvido,
    required this.classificacao,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Wrap(
      spacing: 12,
      runSpacing: 6,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 200, maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                descricao,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Esperado: $esperado • Devolvido: $devolvido',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        Chip(
          avatar: const Icon(Icons.label_outline, size: 17),
          label: Text(classificacao),
        ),
      ],
    );
  }
}

class _TimelineItem extends StatelessWidget {
  final bool active;
  final bool last;
  final IconData icon;
  final String title;
  final String description;

  const _TimelineItem({
    required this.active,
    required this.icon,
    required this.title,
    required this.description,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
    active ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RetiradaBottomActions extends StatelessWidget {
  final String textoPrincipal;
  final IconData iconePrincipal;
  final bool podeContinuar;
  final bool carregando;
  final String? ajuda;
  final VoidCallback? onVoltar;
  final VoidCallback onContinuar;

  const _RetiradaBottomActions({
    required this.textoPrincipal,
    required this.iconePrincipal,
    required this.podeContinuar,
    required this.carregando,
    required this.ajuda,
    required this.onVoltar,
    required this.onContinuar,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final botaoPrincipal = FilledButton.icon(
      onPressed: podeContinuar && !carregando ? onContinuar : null,
      icon: carregando
          ? const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      )
          : Icon(iconePrincipal),
      label: Text(carregando ? 'Salvando...' : textoPrincipal),
    );

    return Material(
      color: theme.colorScheme.surface,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.center,
          // Sem o heightFactor, o Align/Center pode ocupar toda a altura
          // disponível quando usado no bottomNavigationBar e esconder o body.
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final mobile = constraints.maxWidth < 600;

                    if (mobile) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (ajuda != null) ...[
                            Text(
                              ajuda!,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 7),
                          ],
                          SizedBox(height: 48, child: botaoPrincipal),
                          if (onVoltar != null) ...[
                            const SizedBox(height: 4),
                            TextButton.icon(
                              onPressed: carregando ? null : onVoltar,
                              icon: const Icon(Icons.arrow_back),
                              label: const Text('Voltar'),
                            ),
                          ],
                        ],
                      );
                    }

                    return Row(
                      children: [
                        if (onVoltar != null)
                          OutlinedButton.icon(
                            onPressed: carregando ? null : onVoltar,
                            icon: const Icon(Icons.arrow_back),
                            label: const Text('Voltar'),
                          )
                        else
                          const SizedBox.shrink(),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ajuda == null
                              ? const SizedBox.shrink()
                              : Text(
                            ajuda!,
                            textAlign: TextAlign.right,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(height: 46, child: botaoPrincipal),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colors.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool success;
  final bool warning;

  const _StatusBadge({
    required this.icon,
    required this.label,
    this.success = false,
    this.warning = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = success
        ? colors.primary
        : warning
        ? colors.error
        : colors.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoBanner({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.primary.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colors.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyItemsCard extends StatelessWidget {
  const _EmptyItemsCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        child: Column(
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 38,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            Text(
              'Nenhum produto nesta consignação',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}