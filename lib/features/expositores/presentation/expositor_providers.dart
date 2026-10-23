import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/current_org_provider.dart';
import '../data/expositor_fisico_repository.dart';
import '../data/expositor_modelo_repository.dart';
import '../data/expositor_movimentacao_repository.dart';
import '../domain/expositor_fisico.dart';
import '../domain/expositor_modelo.dart';
import '../domain/expositor_movimentacao.dart';

final expositorModeloRepositoryProvider =
Provider<ExpositorModeloRepository>((ref) => ExpositorModeloRepository());

final expositorFisicoRepositoryProvider =
Provider<ExpositorFisicoRepository>((ref) => ExpositorFisicoRepository());

final expositorModelosListProvider =
StreamProvider<List<ExpositorModelo>>((ref) {
  final orgId = ref.watch(currentOrgIdProvider);
  if (orgId == null) return const Stream.empty();
  return ref.watch(expositorModeloRepositoryProvider).watchAll(orgId);
});

final expositoresFisicosListProvider =
StreamProvider<List<ExpositorFisico>>((ref) {
  final orgId = ref.watch(currentOrgIdProvider);
  if (orgId == null) return const Stream.empty();
  return ref.watch(expositorFisicoRepositoryProvider).watchAll(orgId);
});

final expositoresDisponiveisProvider =
StreamProvider.family<List<ExpositorFisico>, String>((ref, orgId) {
  return ref.watch(expositorFisicoRepositoryProvider).watchDisponiveis(orgId);
});

/// Um único expositor, sem precisar carregar a lista inteira só pra
/// abrir a ficha de um — antes, a tela de detalhe reaproveitava
/// expositoresFisicosListProvider e filtrava na memória.
final expositorFisicoByIdProvider =
StreamProvider.family<ExpositorFisico?, String>((ref, expositorId) {
  final orgId = ref.watch(currentOrgIdProvider);
  if (orgId == null) return const Stream.empty();
  return ref
      .watch(expositorFisicoRepositoryProvider)
      .watchById(orgId, expositorId);
});

final expositorMovimentacaoRepositoryProvider =
Provider<ExpositorMovimentacaoRepository>(
        (ref) => ExpositorMovimentacaoRepository());

/// Linha do tempo de um expositor — cadastro, instalação, retirada,
/// manutenção etc, do mais recente pro mais antigo. Ver seção 10 do
/// documento de melhorias do módulo de expositores.
final expositorHistoricoProvider =
StreamProvider.family<List<ExpositorMovimentacao>, String>(
        (ref, expositorId) {
      final orgId = ref.watch(currentOrgIdProvider);
      if (orgId == null) return const Stream.empty();
      return ref
          .watch(expositorMovimentacaoRepositoryProvider)
          .watchDoExpositor(orgId, expositorId);
    });

/// Movimentações recentes de TODOS os expositores da organização —
/// usado no relatório consolidado (Relatórios → Expositores).
final expositorMovimentacoesRecentesProvider =
StreamProvider<List<ExpositorMovimentacao>>((ref) {
  final orgId = ref.watch(currentOrgIdProvider);
  if (orgId == null) return const Stream.empty();
  return ref
      .watch(expositorMovimentacaoRepositoryProvider)
      .watchRecentes(orgId);
});

/// Janela ampliada usada no relatório para localizar a movimentação mais
/// recente de cada expositor e calcular há quanto tempo ele está na situação
/// atual. A lista visual continua limitada; os demais eventos servem apenas
/// para a consolidação em memória.
final expositorMovimentacoesRelatorioProvider =
StreamProvider<List<ExpositorMovimentacao>>((ref) {
  final orgId = ref.watch(currentOrgIdProvider);
  if (orgId == null) return const Stream.empty();
  return ref
      .watch(expositorMovimentacaoRepositoryProvider)
      .watchRecentes(orgId, limit: 500);
});
