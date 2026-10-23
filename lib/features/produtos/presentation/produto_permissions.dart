import '../../auth/domain/app_user.dart';

/// Quem pode editar Produto/SKU (descrição, foto, categoria, preço,
/// estoque mínimo, GTIN). Hoje é a mesma checagem de role de
/// [podeConfigurarTrackingMode] abaixo, mas são conceitos diferentes —
/// o Blueprint prevê permissões granulares distintas no futuro (ex:
/// `product.edit` vs `product.tracking.configure`), então mantemos
/// funções separadas mesmo com a mesma regra hoje. Nunca reusar uma
/// pela outra só porque a checagem é igual agora.
///
/// A autorização de verdade continua sendo responsabilidade do
/// backend/Rules — isto aqui só decide o que mostrar/habilitar na UI.
bool podeEditarProduto(AppUser? appUser) {
  if (appUser == null) return false;
  return appUser.role == UserRole.admin || appUser.role == UserRole.estoque;
}

/// Quem pode configurar o modo de rastreio do SKU (quantidade, lote,
/// número de série). Separado de [podeEditarProduto] de propósito.
bool podeConfigurarTrackingMode(AppUser? appUser) {
  if (appUser == null) return false;
  return appUser.role == UserRole.admin || appUser.role == UserRole.estoque;
}
