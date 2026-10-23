import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/current_org_provider.dart';
import '../data/categoria_repository.dart';
import '../data/produto_cadastro_service.dart';
import '../data/produto_edicao_service.dart';
import '../data/produto_imagem_service.dart';
import '../data/produto_repository.dart';
import '../data/sku_repository.dart';
import '../domain/categoria.dart';
import '../domain/produto.dart';
import '../domain/sku.dart';

final produtoRepositoryProvider = Provider<ProdutoRepository>((ref) {
  return ProdutoRepository();
});

final skuRepositoryProvider = Provider<SkuRepository>((ref) {
  return SkuRepository();
});

final categoriaRepositoryProvider = Provider<CategoriaRepository>((ref) {
  return CategoriaRepository();
});

final produtoImagemServiceProvider = Provider<ProdutoImagemService>((ref) {
  return ProdutoImagemService();
});

final produtoCadastroServiceProvider = Provider<ProdutoCadastroService>((ref) {
  return ProdutoCadastroService(
    skuRepository: ref.watch(skuRepositoryProvider),
    imagemService: ref.watch(produtoImagemServiceProvider),
  );
});

final produtoEdicaoServiceProvider = Provider<ProdutoEdicaoService>((ref) {
  return ProdutoEdicaoService(
    skuRepository: ref.watch(skuRepositoryProvider),
    imagemService: ref.watch(produtoImagemServiceProvider),
  );
});

/// null enquanto o usuário ainda não carregou — as telas que dependem
/// disso pra escrever precisam checar antes de chamar o serviço.
final produtosListProvider = StreamProvider<List<Produto>>((ref) {
  final orgId = ref.watch(currentOrgIdProvider);
  if (orgId == null) return const Stream.empty();
  return ref.watch(produtoRepositoryProvider).watchAll(orgId);
});

final produtoByIdProvider =
    StreamProvider.family<Produto?, String>((ref, produtoId) {
  return ref.watch(produtoRepositoryProvider).watchById(produtoId);
});

final categoriasListProvider = StreamProvider<List<Categoria>>((ref) {
  final orgId = ref.watch(currentOrgIdProvider);
  if (orgId == null) return const Stream.empty();
  return ref.watch(categoriaRepositoryProvider).watchAll(orgId);
});

/// Todos os SKUs da organização — é o SKU (não o Produto) que aparece
/// nas telas de estoque e movimentação, já que é ele que de fato se
/// movimenta (seção 6.3 do Blueprint).
final skusListProvider = StreamProvider<List<Sku>>((ref) {
  final orgId = ref.watch(currentOrgIdProvider);
  if (orgId == null) return const Stream.empty();
  return ref.watch(skuRepositoryProvider).watchAll(orgId);
});

/// Um SKU específico, em tempo real — usado na tela de detalhe.
final skuByIdProvider = StreamProvider.family<Sku?, String>((ref, skuId) {
  return ref.watch(skuRepositoryProvider).watchById(skuId);
});
