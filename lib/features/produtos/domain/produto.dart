/// A linha genérica do catálogo (ver seção 6.3 do Blueprint) — ex:
/// "Cabo USB-C Turbo Native Union".
///
/// Quem de fato se movimenta em estoque é o Sku (ver sku.dart),
/// não o Produto.
class Produto {
  final String? id;
  final String orgId;

  final String descricao;
  final String categoria;
  final String? modelo;
  final String? fabricante;

  final String? fotoUrl;

  // Guardado à parte da URL para permitir excluir/trocar a imagem
  // no Storage sem precisar reconstruir o caminho.
  final String? fotoStoragePath;

  const Produto({
    this.id,
    required this.orgId,
    required this.descricao,
    required this.categoria,
    this.modelo,
    this.fabricante,
    this.fotoUrl,
    this.fotoStoragePath,
  });

  factory Produto.fromFirestore(
      String id,
      Map<String, dynamic> data,
      ) {
    return Produto(
      id: id,
      orgId: data['orgId'] as String? ?? '',
      descricao: data['descricao'] as String? ?? '',
      categoria: data['categoria'] as String? ?? '',
      modelo: data['modelo'] as String?,
      fabricante: data['fabricante'] as String?,
      fotoUrl: data['fotoUrl'] as String?,
      fotoStoragePath: data['fotoStoragePath'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'orgId': orgId,
      'descricao': descricao,
      'categoria': categoria,
      'modelo': modelo,
      'fabricante': fabricante,
      'fotoUrl': fotoUrl,
      'fotoStoragePath': fotoStoragePath,
    };
  }

  Produto copyWith({
    String? fotoUrl,
    String? fotoStoragePath,
  }) {
    return Produto(
      id: id,
      orgId: orgId,
      descricao: descricao,
      categoria: categoria,
      modelo: modelo,
      fabricante: fabricante,
      fotoUrl: fotoUrl ?? this.fotoUrl,
      fotoStoragePath:
      fotoStoragePath ?? this.fotoStoragePath,
    );
  }
}