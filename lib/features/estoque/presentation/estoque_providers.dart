import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/estoque_repository.dart';
import '../domain/estoque_saldo.dart';
import '../domain/stock_movement.dart';

final estoqueRepositoryProvider = Provider<EstoqueRepository>((ref) {
  return EstoqueRepository();
});

/// Saldo de um produto específico num local específico.
final saldoProvider = StreamProvider.family<int, ({String localId, String produtoId})>(
        (ref, params) {
      return ref
          .watch(estoqueRepositoryProvider)
          .watchSaldo(params.localId, params.produtoId);
    });

/// Tudo que está num local (ex: o que está no estoque central agora),
/// restrito à organização informada — ver comentário em
/// EstoqueRepository.watchSaldosDoLocal sobre por que isso importa.
final saldosDoLocalProvider =
StreamProvider.family<List<EstoqueSaldo>, ({String orgId, String localId})>(
        (ref, params) {
      return ref
          .watch(estoqueRepositoryProvider)
          .watchSaldosDoLocal(params.orgId, params.localId);
    });

/// Todos os saldos positivos da organização. Usado em relatórios que precisam
/// consolidar estoque central, cargas dos vendedores e demais locais sem abrir
/// uma assinatura separada para cada usuário.
final saldosDaOrganizacaoProvider =
StreamProvider.family<List<EstoqueSaldo>, String>((ref, orgId) {
  return ref
      .watch(estoqueRepositoryProvider)
      .watchSaldosDaOrganizacao(orgId);
});

/// Todas as vendas apuradas da organização — base do relatório de
/// vendas (seção 9 do Blueprint).
final vendasProvider =
StreamProvider.family<List<StockMovement>, String>((ref, orgId) {
  return ref.watch(estoqueRepositoryProvider).watchVendas(orgId);
});

/// Se um SKU já tem alguma movimentação registrada — usado pra travar
/// a troca de trackingMode na edição de produto.
final temMovimentacaoProvider =
FutureProvider.family<bool, ({String orgId, String skuId})>((ref, params) {
  return ref
      .watch(estoqueRepositoryProvider)
      .temMovimentacao(params.orgId, params.skuId);
});
