import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_collections.dart';
import '../../clientes/presentation/cliente_providers.dart';
import '../../estoque/domain/stock_movement.dart';
import '../../estoque/presentation/estoque_providers.dart';
import '../../expositores/presentation/expositor_providers.dart';
import '../../financeiro/domain/recebivel.dart';
import '../../financeiro/presentation/financeiro_providers.dart';
import 'relatorios_ui.dart';

enum _PeriodoResumo { seteDias, trintaDias, esteMes, noventaDias, tudo }

/// Painel executivo dos relatórios.
///
/// Vendas, comissão, repasse, custo e resultado respeitam o período escolhido.
/// Recebíveis e expositores representam a posição atual da operação.
class RelatorioVisaoGeralPage extends ConsumerStatefulWidget {
  final ValueChanged<int>? onAbrirAba;

  const RelatorioVisaoGeralPage({super.key, this.onAbrirAba});

  @override
  ConsumerState<RelatorioVisaoGeralPage> createState() =>
      _RelatorioVisaoGeralPageState();
}

class _RelatorioVisaoGeralPageState
    extends ConsumerState<RelatorioVisaoGeralPage> {
  _PeriodoResumo _periodo = _PeriodoResumo.trintaDias;
  DateTime _ultimaAtualizacao = DateTime.now();

  String get _periodoLabel => switch (_periodo) {
    _PeriodoResumo.seteDias => 'Últimos 7 dias',
    _PeriodoResumo.trintaDias => 'Últimos 30 dias',
    _PeriodoResumo.esteMes => 'Este mês',
    _PeriodoResumo.noventaDias => 'Últimos 90 dias',
    _PeriodoResumo.tudo => 'Todo o histórico',
  };

  _IntervaloResumo _intervalo(DateTime agora) {
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final amanha = hoje.add(const Duration(days: 1));

    switch (_periodo) {
      case _PeriodoResumo.seteDias:
        final inicio = hoje.subtract(const Duration(days: 6));
        return _IntervaloResumo(
          inicio: inicio,
          fimExclusivo: amanha,
          anteriorInicio: inicio.subtract(const Duration(days: 7)),
          anteriorFimExclusivo: inicio,
        );
      case _PeriodoResumo.trintaDias:
        final inicio = hoje.subtract(const Duration(days: 29));
        return _IntervaloResumo(
          inicio: inicio,
          fimExclusivo: amanha,
          anteriorInicio: inicio.subtract(const Duration(days: 30)),
          anteriorFimExclusivo: inicio,
        );
      case _PeriodoResumo.esteMes:
        final inicio = DateTime(agora.year, agora.month, 1);
        final inicioMesAnterior = DateTime(agora.year, agora.month - 1, 1);
        final duracaoAtual = amanha.difference(inicio);
        final inicioMesAtual = inicio;
        final fimEquivalente = inicioMesAnterior.add(duracaoAtual);
        return _IntervaloResumo(
          inicio: inicio,
          fimExclusivo: amanha,
          anteriorInicio: inicioMesAnterior,
          anteriorFimExclusivo: fimEquivalente.isAfter(inicioMesAtual)
              ? inicioMesAtual
              : fimEquivalente,
        );
      case _PeriodoResumo.noventaDias:
        final inicio = hoje.subtract(const Duration(days: 89));
        return _IntervaloResumo(
          inicio: inicio,
          fimExclusivo: amanha,
          anteriorInicio: inicio.subtract(const Duration(days: 90)),
          anteriorFimExclusivo: inicio,
        );
      case _PeriodoResumo.tudo:
        return const _IntervaloResumo();
    }
  }

  bool _estaNoIntervalo(
      DateTime? data,
      DateTime? inicio,
      DateTime? fimExclusivo,
      ) {
    if (inicio == null && fimExclusivo == null) return true;
    if (data == null) return false;
    if (inicio != null && data.isBefore(inicio)) return false;
    if (fimExclusivo != null && !data.isBefore(fimExclusivo)) return false;
    return true;
  }

  void _recarregar() {
    final orgId = AppConfig.currentOrgId;
    ref.invalidate(vendasProvider(orgId));
    ref.invalidate(recebiveisTodosAbertosProvider(orgId));
    ref.invalidate(expositoresFisicosListProvider);
    ref.invalidate(clientesListProvider);
    setState(() => _ultimaAtualizacao = DateTime.now());
  }

  List<_PontoEvolucao> _montarEvolucao(List<StockMovement> vendas) {
    final acumuladores = <DateTime, _AcumuladorEvolucao>{};

    for (final venda in vendas) {
      final data = venda.timestamp;
      if (data == null) continue;

      final chave = switch (_periodo) {
        _PeriodoResumo.seteDias ||
        _PeriodoResumo.trintaDias ||
        _PeriodoResumo.esteMes => DateTime(data.year, data.month, data.day),
        _PeriodoResumo.noventaDias => _inicioDaSemana(data),
        _PeriodoResumo.tudo => DateTime(data.year, data.month),
      };

      final acumulador = acumuladores.putIfAbsent(
        chave,
            () => _AcumuladorEvolucao(data: chave),
      );

      if (venda.valorVendaCentavosNoMomento != null) {
        acumulador.faturamento += venda.valorVendaTotalCentavos;
      }

      if (_ResumoVendas.temHistoricoCompleto(venda)) {
        acumulador.comissao += venda.comissaoTotalCentavos!;
        acumulador.repasse += venda.repasseNextGearCentavos!;
        acumulador.resultado += venda.resultadoBrutoNextGearCentavos!;
      }
    }

    var pontos = acumuladores.values
        .map(
          (item) => _PontoEvolucao(
        data: item.data,
        faturamento: item.faturamento,
        comissao: item.comissao,
        repasse: item.repasse,
        resultado: item.resultado,
      ),
    )
        .toList()
      ..sort((a, b) => a.data.compareTo(b.data));

    if (_periodo == _PeriodoResumo.tudo && pontos.length > 12) {
      pontos = pontos.sublist(pontos.length - 12);
    }
    return pontos;
  }

  DateTime _inicioDaSemana(DateTime data) {
    final dia = DateTime(data.year, data.month, data.day);
    return dia.subtract(Duration(days: dia.weekday - DateTime.monday));
  }

  @override
  Widget build(BuildContext context) {
    final orgId = AppConfig.currentOrgId;
    final vendasAsync = ref.watch(vendasProvider(orgId));
    final recebiveisAsync = ref.watch(recebiveisTodosAbertosProvider(orgId));
    final expositoresAsync = ref.watch(expositoresFisicosListProvider);
    final clientesAsync = ref.watch(clientesListProvider);

    if (vendasAsync.hasError ||
        recebiveisAsync.hasError ||
        expositoresAsync.hasError ||
        clientesAsync.hasError) {
      return RelatorioErrorState(onRetry: _recarregar);
    }
    if ((vendasAsync.isLoading && !vendasAsync.hasValue) ||
        (recebiveisAsync.isLoading && !recebiveisAsync.hasValue) ||
        (expositoresAsync.isLoading && !expositoresAsync.hasValue) ||
        (clientesAsync.isLoading && !clientesAsync.hasValue)) {
      return const RelatorioLoading();
    }

    final todasVendas = vendasAsync.value;
    final recebiveis = recebiveisAsync.value;
    final expositores = expositoresAsync.value;
    final clientes = clientesAsync.value;
    if (todasVendas == null ||
        recebiveis == null ||
        expositores == null ||
        clientes == null) {
      return const RelatorioLoading();
    }

    final agora = DateTime.now();
    final intervalo = _intervalo(agora);
    final vendas = todasVendas
        .where(
          (venda) => _estaNoIntervalo(
        venda.timestamp,
        intervalo.inicio,
        intervalo.fimExclusivo,
      ),
    )
        .toList();
    final vendasAnteriores = intervalo.temComparacao
        ? todasVendas
        .where(
          (venda) => _estaNoIntervalo(
        venda.timestamp,
        intervalo.anteriorInicio,
        intervalo.anteriorFimExclusivo,
      ),
    )
        .toList()
        : <StockMovement>[];

    final resumo = _ResumoVendas.calcular(vendas);
    final resumoAnterior = _ResumoVendas.calcular(vendasAnteriores);
    final evolucao = _montarEvolucao(vendas);

    final totalAReceber = recebiveis.fold<int>(
      0,
          (total, recebivel) => total + recebivel.saldoEmAbertoCentavos,
    );
    final vencidos = recebiveis
        .where((recebivel) => recebivel.status == RecebivelStatus.vencido)
        .toList();
    final totalVencido = vencidos.fold<int>(
      0,
          (total, recebivel) => total + recebivel.saldoEmAbertoCentavos,
    );
    final percentualVencido = totalAReceber == 0
        ? null
        : totalVencido / totalAReceber * 100;
    final clientesVencidos =
        vencidos.map((recebivel) => recebivel.clienteId).toSet().length;

    final instalados = expositores
        .where((expositor) => expositor.clienteAtualId != null)
        .length;
    final disponiveis = expositores.length - instalados;

    final nomeClientePorId = <String, String>{
      for (final cliente in clientes)
        if (cliente.id != null)
          cliente.id!: cliente.nomeFantasia?.trim().isNotEmpty == true
              ? cliente.nomeFantasia!.trim()
              : cliente.nome.trim(),
    };
    final rankings = _montarRankings(vendas, nomeClientePorId);
    final cobrancas = _montarCobrancas(vencidos, nomeClientePorId);
    final theme = Theme.of(context);

    return SingleChildScrollView(
      child: RelatorioPageBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RelatorioIntro(
              title: 'Visão geral',
              subtitle:
              'Acompanhe vendas, comissão, repasse e pendências em um único painel.',
              icon: Icons.dashboard_outlined,
              action: _AcoesCabecalho(
                periodo: _periodo,
                ultimaAtualizacao: _ultimaAtualizacao,
                onChanged: (value) => setState(() => _periodo = value),
                onRefresh: _recarregar,
              ),
            ),
            const SizedBox(height: 20),
            _TituloGrupo(
              title: 'Desempenho comercial',
              subtitle: '$_periodoLabel · comparação com o período anterior',
            ),
            const SizedBox(height: 12),
            RelatorioMetricsGrid(
              children: [
                _MetricaPrincipalCard(
                  label: 'Faturamento bruto',
                  value: formatarReais(resumo.faturamento),
                  comparison: _textoComparacao(
                    resumo.faturamento,
                    resumoAnterior.faturamento,
                    intervalo.temComparacao,
                  ),
                  icon: Icons.payments_outlined,
                  color: Colors.green,
                  onTap: widget.onAbrirAba == null
                      ? null
                      : () => widget.onAbrirAba!(1),
                ),
                _MetricaPrincipalCard(
                  label: 'Comissão dos lojistas',
                  value: formatarReais(resumo.comissao),
                  comparison: _textoComparacao(
                    resumo.comissao,
                    resumoAnterior.comissao,
                    intervalo.temComparacao,
                  ),
                  icon: Icons.handshake_outlined,
                  color: Colors.orange,
                  onTap: widget.onAbrirAba == null
                      ? null
                      : () => widget.onAbrirAba!(1),
                ),
                _MetricaPrincipalCard(
                  label: 'Repasse à NEXT GEAR',
                  value: formatarReais(resumo.repasse),
                  comparison: _textoComparacao(
                    resumo.repasse,
                    resumoAnterior.repasse,
                    intervalo.temComparacao,
                  ),
                  icon: Icons.account_balance_outlined,
                  color: Colors.lightBlue,
                  onTap: widget.onAbrirAba == null
                      ? null
                      : () => widget.onAbrirAba!(1),
                ),
                _MetricaPrincipalCard(
                  label: 'Resultado bruto NEXT GEAR',
                  value: formatarReais(resumo.resultado),
                  comparison: _textoComparacao(
                    resumo.resultado,
                    resumoAnterior.resultado,
                    intervalo.temComparacao,
                  ),
                  icon: resumo.resultado < 0
                      ? Icons.trending_down
                      : Icons.trending_up,
                  color: resumo.resultado < 0 ? Colors.red : Colors.green,
                  onTap: widget.onAbrirAba == null
                      ? null
                      : () => widget.onAbrirAba!(1),
                ),
              ],
            ),
            if (resumo.movimentosSemHistorico > 0) ...[
              const SizedBox(height: 16),
              _HistoricoFinanceiroAviso(
                incompletos: resumo.movimentosSemHistorico,
                total: resumo.movimentos,
              ),
            ],
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final grafico = RelatorioSectionCard(
                  title: 'Evolução financeira',
                  subtitle: _periodo == _PeriodoResumo.tudo
                      ? 'Últimos 12 meses com movimentação'
                      : 'Comportamento dentro de $_periodoLabel',
                  child: _GraficoEvolucao(
                    pontos: evolucao,
                    periodo: _periodo,
                  ),
                );
                final fluxo = _FluxoFinanceiroCard(resumo: resumo);

                if (constraints.maxWidth < 900) {
                  return Column(
                    children: [
                      grafico,
                      const SizedBox(height: 16),
                      fluxo,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 6, child: grafico),
                    const SizedBox(width: 16),
                    Expanded(flex: 4, child: fluxo),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            RelatorioSectionCard(
              title: 'Indicadores complementares',
              subtitle:
              'Custos do período e posição financeira atual da empresa',
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final colunas = constraints.maxWidth >= 920
                      ? 4
                      : constraints.maxWidth >= 520
                      ? 2
                      : 1;
                  final largura =
                      (constraints.maxWidth - (colunas - 1) * 12) / colunas;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: largura,
                        child: _IndicadorCompacto(
                          label: 'Custo dos produtos',
                          value: formatarReais(resumo.custo),
                          hint: 'Histórico financeiro completo',
                          icon: Icons.inventory_2_outlined,
                          color: Colors.blueGrey,
                        ),
                      ),
                      SizedBox(
                        width: largura,
                        child: _IndicadorCompacto(
                          label: 'Margem sobre o repasse',
                          value: resumo.margem == null
                              ? '—'
                              : '${_formatarPercentual(resumo.margem!)}%',
                          hint: 'Antes de despesas e tributos',
                          icon: Icons.percent,
                          color: resumo.margem != null && resumo.margem! < 0
                              ? Colors.red
                              : Colors.orange,
                        ),
                      ),
                      SizedBox(
                        width: largura,
                        child: _IndicadorCompacto(
                          label: 'Total a receber',
                          value: formatarReais(totalAReceber),
                          hint: '${recebiveis.length} recebíveis em aberto',
                          icon: Icons.account_balance_wallet_outlined,
                          color: Colors.lightBlue,
                        ),
                      ),
                      SizedBox(
                        width: largura,
                        child: _IndicadorCompacto(
                          label: 'Valor vencido',
                          value: formatarReais(totalVencido),
                          hint: percentualVencido == null
                              ? 'Nenhum valor em aberto'
                              : '${_formatarPercentual(percentualVencido)}% do saldo aberto',
                          icon: Icons.warning_amber_rounded,
                          color:
                          totalVencido > 0 ? Colors.red : Colors.green,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final vendasCard = _RankingCard(
                  title: 'Lojistas com mais vendas',
                  subtitle: 'Venda bruta em $_periodoLabel',
                  emptyMessage: 'Nenhuma venda vinculada a lojista no período.',
                  icon: Icons.storefront_outlined,
                  color: Colors.green,
                  items: rankings.vendas,
                  onOpen: widget.onAbrirAba == null
                      ? null
                      : () => widget.onAbrirAba!(1),
                );
                final comissoesCard = _RankingCard(
                  title: 'Maiores comissões',
                  subtitle: 'Comissão retida por lojista',
                  emptyMessage: 'Nenhuma comissão registrada no período.',
                  icon: Icons.handshake_outlined,
                  color: Colors.orange,
                  items: rankings.comissoes,
                  onOpen: widget.onAbrirAba == null
                      ? null
                      : () => widget.onAbrirAba!(1),
                );

                if (constraints.maxWidth < 820) {
                  return Column(
                    children: [
                      vendasCard,
                      const SizedBox(height: 16),
                      comissoesCard,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: vendasCard),
                    const SizedBox(width: 16),
                    Expanded(child: comissoesCard),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final alertas = _PontosAtencaoCard(
                  resumo: resumo,
                  totalVencido: totalVencido,
                  clientesVencidos: clientesVencidos,
                  maiorCobranca: cobrancas.isEmpty ? null : cobrancas.first,
                );
                final operacao = _OperacaoExpositoresCard(
                  total: expositores.length,
                  instalados: instalados,
                  disponiveis: disponiveis,
                  onOpen: widget.onAbrirAba == null
                      ? null
                      : () => widget.onAbrirAba!(4),
                );

                if (constraints.maxWidth < 880) {
                  return Column(
                    children: [
                      alertas,
                      const SizedBox(height: 16),
                      operacao,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 6, child: alertas),
                    const SizedBox(width: 16),
                    Expanded(flex: 4, child: operacao),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            Text(
              'Vendas, comissão, repasse e custos respeitam o período selecionado. Recebíveis e expositores mostram a posição atual. O resultado bruto não desconta despesas operacionais nem tributos.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntervaloResumo {
  final DateTime? inicio;
  final DateTime? fimExclusivo;
  final DateTime? anteriorInicio;
  final DateTime? anteriorFimExclusivo;

  const _IntervaloResumo({
    this.inicio,
    this.fimExclusivo,
    this.anteriorInicio,
    this.anteriorFimExclusivo,
  });

  bool get temComparacao =>
      anteriorInicio != null && anteriorFimExclusivo != null;
}

class _ResumoVendas {
  final int movimentos;
  final int movimentosComHistorico;
  final int faturamento;
  final int faturamentoComHistorico;
  final int comissao;
  final int repasse;
  final int custo;
  final int resultado;

  const _ResumoVendas({
    required this.movimentos,
    required this.movimentosComHistorico,
    required this.faturamento,
    required this.faturamentoComHistorico,
    required this.comissao,
    required this.repasse,
    required this.custo,
    required this.resultado,
  });

  int get movimentosSemHistorico => movimentos - movimentosComHistorico;

  double? get margem => repasse == 0 ? null : resultado / repasse * 100;

  double? get percentualComissao => faturamentoComHistorico == 0
      ? null
      : comissao / faturamentoComHistorico * 100;

  double get cobertura =>
      movimentos == 0 ? 1 : movimentosComHistorico / movimentos;

  static bool temHistoricoCompleto(StockMovement venda) {
    return venda.valorVendaCentavosNoMomento != null &&
        venda.comissaoCentavosNoMomento != null &&
        venda.custoUnitarioCentavosNoMomento != null;
  }

  factory _ResumoVendas.calcular(Iterable<StockMovement> movimentos) {
    var quantidade = 0;
    var completos = 0;
    var faturamento = 0;
    var faturamentoCompleto = 0;
    var comissao = 0;
    var repasse = 0;
    var custo = 0;
    var resultado = 0;

    for (final venda in movimentos) {
      quantidade++;
      if (venda.valorVendaCentavosNoMomento != null) {
        faturamento += venda.valorVendaTotalCentavos;
      }
      if (!temHistoricoCompleto(venda)) continue;

      completos++;
      faturamentoCompleto += venda.valorVendaTotalCentavos;
      comissao += venda.comissaoTotalCentavos!;
      repasse += venda.repasseNextGearCentavos!;
      custo += venda.quantidade * venda.custoUnitarioCentavosNoMomento!;
      resultado += venda.resultadoBrutoNextGearCentavos!;
    }

    return _ResumoVendas(
      movimentos: quantidade,
      movimentosComHistorico: completos,
      faturamento: faturamento,
      faturamentoComHistorico: faturamentoCompleto,
      comissao: comissao,
      repasse: repasse,
      custo: custo,
      resultado: resultado,
    );
  }
}

class _AcoesCabecalho extends StatelessWidget {
  final _PeriodoResumo periodo;
  final DateTime ultimaAtualizacao;
  final ValueChanged<_PeriodoResumo> onChanged;
  final VoidCallback onRefresh;

  const _AcoesCabecalho({
    required this.periodo,
    required this.ultimaAtualizacao,
    required this.onChanged,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final horario =
        '${ultimaAtualizacao.hour.toString().padLeft(2, '0')}:${ultimaAtualizacao.minute.toString().padLeft(2, '0')}';
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<_PeriodoResumo>(
            initialValue: periodo,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Período',
              isDense: true,
            ),
            items: _PeriodoResumo.values
                .map(
                  (item) => DropdownMenuItem(
                value: item,
                child: Text(
                  _labelPeriodo(item),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
                .toList(),
            onChanged: (value) {
              if (value != null) onChanged(value);
            },
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: 'Atualizado às $horario',
          child: IconButton.filledTonal(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
          ),
        ),
      ],
    );
  }
}

String _labelPeriodo(_PeriodoResumo periodo) => switch (periodo) {
  _PeriodoResumo.seteDias => 'Últimos 7 dias',
  _PeriodoResumo.trintaDias => 'Últimos 30 dias',
  _PeriodoResumo.esteMes => 'Este mês',
  _PeriodoResumo.noventaDias => 'Últimos 90 dias',
  _PeriodoResumo.tudo => 'Todo o histórico',
};

class _TituloGrupo extends StatelessWidget {
  final String title;
  final String subtitle;

  const _TituloGrupo({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _MetricaPrincipalCard extends StatelessWidget {
  final String label;
  final String value;
  final String comparison;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _MetricaPrincipalCard({
    required this.label,
    required this.value,
    required this.comparison,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  const Spacer(),
                  if (onTap != null)
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                comparison,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IndicadorCompacto extends StatelessWidget {
  final String label;
  final String value;
  final String hint;
  final IconData icon;
  final Color color;

  const _IndicadorCompacto({
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .20)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FluxoFinanceiroCard extends StatelessWidget {
  final _ResumoVendas resumo;

  const _FluxoFinanceiroCard({required this.resumo});

  @override
  Widget build(BuildContext context) {
    return RelatorioSectionCard(
      title: 'Como o dinheiro se distribui',
      subtitle: 'Somente movimentos com histórico financeiro completo',
      child: Column(
        children: [
          _FluxoLinha(
            label: 'Venda bruta',
            value: formatarReais(resumo.faturamentoComHistorico),
            icon: Icons.add_circle_outline,
            color: Colors.green,
          ),
          const SizedBox(height: 10),
          _FluxoLinha(
            label: 'Comissão dos lojistas',
            value: '− ${formatarReais(resumo.comissao)}',
            icon: Icons.remove_circle_outline,
            color: Colors.orange,
            detail: resumo.percentualComissao == null
                ? null
                : '${_formatarPercentual(resumo.percentualComissao!)}% da venda',
          ),
          const Divider(height: 22),
          _FluxoLinha(
            label: 'Repasse à NEXT GEAR',
            value: formatarReais(resumo.repasse),
            icon: Icons.account_balance_outlined,
            color: Colors.lightBlue,
            strong: true,
          ),
          const SizedBox(height: 10),
          _FluxoLinha(
            label: 'Custo dos produtos',
            value: '− ${formatarReais(resumo.custo)}',
            icon: Icons.remove_circle_outline,
            color: Colors.blueGrey,
          ),
          const Divider(height: 22),
          _FluxoLinha(
            label: 'Resultado bruto',
            value: formatarReais(resumo.resultado),
            icon: resumo.resultado < 0
                ? Icons.trending_down
                : Icons.trending_up,
            color: resumo.resultado < 0 ? Colors.red : Colors.green,
            strong: true,
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${resumo.movimentosComHistorico} de ${resumo.movimentos} movimentos usados no fluxo',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FluxoLinha extends StatelessWidget {
  final String label;
  final String value;
  final String? detail;
  final IconData icon;
  final Color color;
  final bool strong;

  const _FluxoLinha({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.detail,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 19, color: color),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
              if (detail != null)
                Text(
                  detail!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          value,
          style: TextStyle(
            color: strong ? color : null,
            fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _HistoricoFinanceiroAviso extends StatelessWidget {
  final int incompletos;
  final int total;

  const _HistoricoFinanceiroAviso({
    required this.incompletos,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final completos = total - incompletos;
    final cobertura = total == 0 ? 100.0 : completos / total * 100;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: .38)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Colors.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cobertura financeira: ${_formatarPercentual(cobertura)}%',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  '$incompletos movimentos antigos não possuem preço, comissão ou custo completos. Eles entram no faturamento quando houver preço, mas não entram no fluxo de comissão, repasse, custo e resultado.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PontoEvolucao {
  final DateTime data;
  final int faturamento;
  final int comissao;
  final int repasse;
  final int resultado;

  const _PontoEvolucao({
    required this.data,
    required this.faturamento,
    required this.comissao,
    required this.repasse,
    required this.resultado,
  });
}

class _AcumuladorEvolucao {
  final DateTime data;
  int faturamento = 0;
  int comissao = 0;
  int repasse = 0;
  int resultado = 0;

  _AcumuladorEvolucao({required this.data});
}

class _GraficoEvolucao extends StatelessWidget {
  final List<_PontoEvolucao> pontos;
  final _PeriodoResumo periodo;

  const _GraficoEvolucao({required this.pontos, required this.periodo});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (pontos.isEmpty) {
      return const SizedBox(
        height: 236,
        child: Center(
          child: Text('Nenhuma venda registrada no período selecionado.'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 8,
          children: const [
            _LegendaGrafico(label: 'Venda bruta', color: Colors.green),
            _LegendaGrafico(label: 'Comissão', color: Colors.orange),
            _LegendaGrafico(label: 'Repasse', color: Colors.lightBlue),
            _LegendaGrafico(label: 'Resultado', color: Colors.purpleAccent),
          ],
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 180,
          child: CustomPaint(
            painter: _EvolucaoPainter(
              pontos: pontos,
              gridColor: theme.colorScheme.outlineVariant,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatarDataGrafico(pontos.first.data, periodo),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (pontos.length > 2)
              Text(
                '${pontos.length} períodos',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            Text(
              _formatarDataGrafico(pontos.last.data, periodo),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LegendaGrafico extends StatelessWidget {
  final String label;
  final Color color;

  const _LegendaGrafico({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _EvolucaoPainter extends CustomPainter {
  final List<_PontoEvolucao> pontos;
  final Color gridColor;

  const _EvolucaoPainter({required this.pontos, required this.gridColor});

  @override
  void paint(Canvas canvas, Size size) {
    const padding = 5.0;
    final area = Rect.fromLTWH(
      padding,
      padding,
      math.max(1.0, size.width - padding * 2),
      math.max(1.0, size.height - padding * 2),
    );

    final valores = <int>[
      for (final ponto in pontos) ...[
        ponto.faturamento,
        ponto.comissao,
        ponto.repasse,
        ponto.resultado,
      ],
    ];
    final minimo = math.min(0, valores.reduce(math.min));
    final maximo = math.max(1, valores.reduce(math.max));
    final amplitude = math.max(1, maximo - minimo);

    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: .55)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = area.top + area.height * i / 4;
      canvas.drawLine(Offset(area.left, y), Offset(area.right, y), gridPaint);
    }

    final zeroY = area.bottom - ((0 - minimo) / amplitude) * area.height;
    if (minimo < 0) {
      canvas.drawLine(
        Offset(area.left, zeroY),
        Offset(area.right, zeroY),
        Paint()
          ..color = gridColor
          ..strokeWidth = 1.4,
      );
    }

    void desenhar(List<int> serie, Color color) {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final path = Path();

      for (var i = 0; i < serie.length; i++) {
        final x = serie.length == 1
            ? area.center.dx
            : area.left + area.width * i / (serie.length - 1);
        final y = area.bottom - ((serie[i] - minimo) / amplitude) * area.height;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);

      if (serie.length == 1) {
        final y =
            area.bottom - ((serie.first - minimo) / amplitude) * area.height;
        canvas.drawCircle(
          Offset(area.center.dx, y),
          3.5,
          Paint()..color = color,
        );
      }
    }

    desenhar(
      pontos.map((ponto) => ponto.faturamento).toList(),
      Colors.green,
    );
    desenhar(
      pontos.map((ponto) => ponto.comissao).toList(),
      Colors.orange,
    );
    desenhar(
      pontos.map((ponto) => ponto.repasse).toList(),
      Colors.lightBlue,
    );
    desenhar(
      pontos.map((ponto) => ponto.resultado).toList(),
      Colors.purpleAccent,
    );
  }

  @override
  bool shouldRepaint(covariant _EvolucaoPainter oldDelegate) {
    return oldDelegate.pontos != pontos || oldDelegate.gridColor != gridColor;
  }
}

class _RankingItem {
  final String nome;
  final int valor;

  const _RankingItem({required this.nome, required this.valor});
}

class _RankingsResumo {
  final List<_RankingItem> vendas;
  final List<_RankingItem> comissoes;

  const _RankingsResumo({required this.vendas, required this.comissoes});
}

_RankingsResumo _montarRankings(
    List<StockMovement> vendas,
    Map<String, String> nomeClientePorId,
    ) {
  final vendasPorCliente = <String, int>{};
  final comissaoPorCliente = <String, int>{};

  for (final venda in vendas) {
    final clienteId = LocalEstoque.extrairClienteId(venda.origem);
    if (clienteId == null) continue;

    if (venda.valorVendaCentavosNoMomento != null) {
      vendasPorCliente[clienteId] =
          (vendasPorCliente[clienteId] ?? 0) + venda.valorVendaTotalCentavos;
    }
    final comissao = venda.comissaoTotalCentavos;
    if (comissao != null) {
      comissaoPorCliente[clienteId] =
          (comissaoPorCliente[clienteId] ?? 0) + comissao;
    }
  }

  List<_RankingItem> converter(Map<String, int> dados) {
    final itens = dados.entries
        .where((item) => item.value != 0)
        .map(
          (item) => _RankingItem(
        nome: nomeClientePorId[item.key] ?? 'Cliente não localizado',
        valor: item.value,
      ),
    )
        .toList()
      ..sort((a, b) => b.valor.compareTo(a.valor));
    return itens.take(5).toList();
  }

  return _RankingsResumo(
    vendas: converter(vendasPorCliente),
    comissoes: converter(comissaoPorCliente),
  );
}

class _RankingCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String emptyMessage;
  final IconData icon;
  final Color color;
  final List<_RankingItem> items;
  final VoidCallback? onOpen;

  const _RankingCard({
    required this.title,
    required this.subtitle,
    required this.emptyMessage,
    required this.icon,
    required this.color,
    required this.items,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final maiorValor = items.isEmpty
        ? 1
        : math.max(1, items.map((item) => item.valor).reduce(math.max));
    return RelatorioSectionCard(
      title: title,
      subtitle: subtitle,
      trailing: onOpen == null
          ? null
          : IconButton(
        tooltip: 'Abrir relatório de vendas',
        onPressed: onOpen,
        icon: const Icon(Icons.open_in_new, size: 20),
      ),
      child: items.isEmpty
          ? SizedBox(
        height: 120,
        child: Center(
          child: Text(emptyMessage, textAlign: TextAlign.center),
        ),
      )
          : Column(
        children: [
          for (var indice = 0; indice < items.length; indice++) ...[
            _RankingLinha(
              posicao: indice + 1,
              item: items[indice],
              maiorValor: maiorValor,
              icon: icon,
              color: color,
            ),
            if (indice != items.length - 1)
              const SizedBox(height: 13),
          ],
        ],
      ),
    );
  }
}

class _RankingLinha extends StatelessWidget {
  final int posicao;
  final _RankingItem item;
  final int maiorValor;
  final IconData icon;
  final Color color;

  const _RankingLinha({
    required this.posicao,
    required this.item,
    required this.maiorValor,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(9),
          ),
          child: posicao <= 3
              ? Icon(icon, size: 16, color: color)
              : Text(
            '$posicao',
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.nome,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatarReais(item.valor),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: item.valor.abs() / maiorValor.abs(),
                  minHeight: 5,
                  color: color,
                  backgroundColor:
                  theme.colorScheme.surfaceContainerHighest,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CobrancaItem {
  final String nome;
  final int valor;

  const _CobrancaItem({required this.nome, required this.valor});
}

List<_CobrancaItem> _montarCobrancas(
    List<Recebivel> vencidos,
    Map<String, String> nomeClientePorId,
    ) {
  final valores = <String, int>{};
  for (final recebivel in vencidos) {
    valores[recebivel.clienteId] =
        (valores[recebivel.clienteId] ?? 0) +
            recebivel.saldoEmAbertoCentavos;
  }
  final itens = valores.entries
      .map(
        (item) => _CobrancaItem(
      nome: nomeClientePorId[item.key] ?? 'Cliente não localizado',
      valor: item.value,
    ),
  )
      .toList()
    ..sort((a, b) => b.valor.compareTo(a.valor));
  return itens;
}

class _PontosAtencaoCard extends StatelessWidget {
  final _ResumoVendas resumo;
  final int totalVencido;
  final int clientesVencidos;
  final _CobrancaItem? maiorCobranca;

  const _PontosAtencaoCard({
    required this.resumo,
    required this.totalVencido,
    required this.clientesVencidos,
    required this.maiorCobranca,
  });

  @override
  Widget build(BuildContext context) {
    final temAlerta = resumo.movimentos == 0 ||
        resumo.movimentosSemHistorico > 0 ||
        totalVencido > 0 ||
        resumo.resultado < 0;

    return RelatorioSectionCard(
      title: 'Pontos de atenção',
      subtitle: 'Situações que merecem acompanhamento',
      child: !temAlerta
          ? const _ResumoAlerta(
        icon: Icons.verified_outlined,
        title: 'Nenhum alerta financeiro crítico',
        message: 'Os dados do período não apresentam pendências críticas.',
        color: Colors.green,
      )
          : Column(
        children: [
          if (resumo.movimentos == 0)
            const _ResumoAlerta(
              icon: Icons.insights_outlined,
              title: 'Nenhuma venda no período',
              message: 'Altere o período ou confira os lançamentos de venda.',
              color: Colors.orange,
            ),
          if (resumo.movimentos == 0 &&
              (totalVencido > 0 || resumo.movimentosSemHistorico > 0))
            const Divider(height: 24),
          if (totalVencido > 0)
            _ResumoAlerta(
              icon: Icons.warning_amber_rounded,
              title:
              '$clientesVencidos clientes com recebíveis vencidos',
              message: maiorCobranca == null
                  ? '${formatarReais(totalVencido)} aguardando cobrança.'
                  : '${formatarReais(totalVencido)} no total. Maior saldo: ${maiorCobranca!.nome}, ${formatarReais(maiorCobranca!.valor)}.',
              color: Colors.red,
            ),
          if (totalVencido > 0 &&
              (resumo.resultado < 0 ||
                  resumo.movimentosSemHistorico > 0))
            const Divider(height: 24),
          if (resumo.resultado < 0)
            const _ResumoAlerta(
              icon: Icons.trending_down,
              title: 'Resultado bruto negativo',
              message:
              'O repasse do período não cobriu o custo dos produtos vendidos.',
              color: Colors.red,
            ),
          if (resumo.resultado < 0 &&
              resumo.movimentosSemHistorico > 0)
            const Divider(height: 24),
          if (resumo.movimentosSemHistorico > 0)
            _ResumoAlerta(
              icon: Icons.history_toggle_off,
              title:
              '${resumo.movimentosSemHistorico} movimentos com histórico incompleto',
              message:
              'A cobertura atual é ${_formatarPercentual(resumo.cobertura * 100)}%. Resultado e margem não devem ser comparados ao faturamento total.',
              color: Colors.orange,
            ),
        ],
      ),
    );
  }
}

class _OperacaoExpositoresCard extends StatelessWidget {
  final int total;
  final int instalados;
  final int disponiveis;
  final VoidCallback? onOpen;

  const _OperacaoExpositoresCard({
    required this.total,
    required this.instalados,
    required this.disponiveis,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final percentual = total == 0 ? 0.0 : instalados / total;
    final theme = Theme.of(context);
    return RelatorioSectionCard(
      title: 'Expositores',
      subtitle: 'Posição atual da operação em campo',
      trailing: onOpen == null
          ? null
          : IconButton(
        tooltip: 'Abrir relatório de expositores',
        onPressed: onOpen,
        icon: const Icon(Icons.open_in_new, size: 20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _NumeroOperacao(
                  value: '$total',
                  label: 'Total',
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _NumeroOperacao(
                  value: '$instalados',
                  label: 'Instalados',
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _NumeroOperacao(
                  value: '$disponiveis',
                  label: 'Disponíveis',
                  color: Colors.lightBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: percentual,
                    minHeight: 8,
                    color: Colors.green,
                    backgroundColor:
                    theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${_formatarPercentual(percentual * 100)}% em clientes',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NumeroOperacao extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _NumeroOperacao({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ResumoAlerta extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Color color;

  const _ResumoAlerta({
    required this.icon,
    required this.title,
    required this.message,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(message, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

String _textoComparacao(int atual, int anterior, bool comparar) {
  if (!comparar) return 'Acumulado de todo o histórico';
  if (anterior == 0) {
    return atual == 0
        ? 'Sem variação no período anterior'
        : 'Sem base no período anterior';
  }
  final variacao = (atual - anterior) / anterior.abs() * 100;
  final seta = variacao > 0
      ? '↑'
      : variacao < 0
      ? '↓'
      : '→';
  return '$seta ${_formatarPercentual(variacao.abs())}% vs. período anterior';
}

String _formatarPercentual(double valor) {
  return valor.toStringAsFixed(1).replaceAll('.', ',');
}

String _formatarDataGrafico(DateTime data, _PeriodoResumo periodo) {
  if (periodo == _PeriodoResumo.tudo) {
    return '${data.month.toString().padLeft(2, '0')}/${data.year}';
  }
  return '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}';
}
