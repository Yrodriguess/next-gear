class FirestoreCollections {
  FirestoreCollections._();

  static const String organizations = 'organizations';
  static const String usuarios = 'usuarios';
  static const String clientes = 'clientes';

  /// Documento de controle pra CPF/CNPJ único por organização — mesmo
  /// padrão de reserva usado no GTIN de produtos. Chave:
  /// {orgId}_{cpfCnpjLimpo}.
  static const String clienteCpfCnpjControle = 'clienteCpfCnpjControle';
  static const String produtos = 'produtos';

  // Ver seção 6.3 do Blueprint: produto (linha genérica) e SKU (a
  // variação que de fato se movimenta em estoque) são entidades
  // separadas.
  static const String skus = 'skus';
  static const String categoriasProduto = 'categoriasProduto';

  // Histórico de vigência de preço por SKU (seção 7.8). A tela de
  // edição com histórico completo ainda não existe — por enquanto só
  // recebe o primeiro registro na criação do SKU.
  static const String skuPrecos = 'skuPrecos';

  // Um documento por GTIN/EAN existente (id = orgId_codigoBarras).
  // Criado dentro da mesma transação do SKU — a existência do
  // documento É a garantia de unicidade (o Firestore não permite dois
  // clientes criarem o mesmo ID na mesma transação sem conflito).
  static const String skuBarcodes = 'skuBarcodes';

  static const String expositoresFisicos = 'expositoresFisicos';

  // Histórico permanente de movimentações do expositor (instalação,
  // retirada, manutenção etc) — nunca editado/apagado, mesmo espírito
  // de estoqueMovimentacoes.
  static const String expositorMovimentacoes = 'expositorMovimentacoes';
  static const String expositorModelos = 'expositorModelos';
  static const String consignments = 'consignments';
  static const String visitas = 'visitas';
  static const String estoqueMovimentacoes = 'estoqueMovimentacoes';
  static const String estoqueSaldos = 'estoqueSaldos';
  static const String contasAReceber = 'contasAReceber';
  static const String documentosGerados = 'documentosGerados';
  static const String auditLogs = 'auditLogs';
  static const String counters = 'counters';
}

/// Enquanto o plano SaaS é único (seção 13 do Blueprint), usamos uma
/// organização fixa. Isso já deixa o campo `orgId` em todo lugar,
/// pronto para virar multiempresa de verdade no futuro sem remodelar nada.
class AppConfig {
  AppConfig._();

  static const String currentOrgId = 'next-gear';
}
