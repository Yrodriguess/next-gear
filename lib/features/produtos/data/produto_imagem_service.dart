import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Tamanho máximo aceito do arquivo original, antes até da compressão
/// (seção 15.1 do Blueprint: validação de upload — tamanho máximo,
/// tipos permitidos).
const int _kTamanhoMaximoOriginalBytes = 15 * 1024 * 1024; // 15 MB

class ProdutoFotoUpload {
  final String url;
  final String storagePath;
  const ProdutoFotoUpload({required this.url, required this.storagePath});
}

/// Comprime e envia a foto principal de um produto para o Storage,
/// isolada por organização e por produto
/// (organizations/{orgId}/products/{produtoId}/foto.jpg) — mantém o
/// isolamento multiempresa previsto no projeto. Só a URL/referência vai
/// pro Firestore; o binário nunca é gravado lá.
///
/// Trabalha inteiramente com bytes (Uint8List), nunca com dart:io/File
/// — funciona igual em Web, Android e iOS. `compressWithList` (em vez
/// de `compressAndGetFile`) é a variante do flutter_image_compress que
/// não depende de sistema de arquivos, por isso funciona no navegador.
class ProdutoImagemService {
  final FirebaseStorage _storage;

  ProdutoImagemService({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  Future<ProdutoFotoUpload> upload({
    required String orgId,
    required String produtoId,
    required Uint8List bytes,
  }) async {
    if (bytes.lengthInBytes > _kTamanhoMaximoOriginalBytes) {
      throw ArgumentError('Imagem muito grande. Escolha um arquivo de até 15 MB.');
    }

    final bytesComprimidos = await _comprimir(bytes);

    final path = 'organizations/$orgId/products/$produtoId/foto.jpg';
    final ref = _storage.ref(path);
    await ref.putData(
      bytesComprimidos,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    final url = await ref.getDownloadURL();

    return ProdutoFotoUpload(url: url, storagePath: path);
  }

  /// Remove um arquivo de foto já enviado — usado tanto ao trocar a
  /// imagem quanto na limpeza de arquivo órfão se o cadastro falhar
  /// depois do upload.
  Future<void> remover(String storagePath) async {
    try {
      await _storage.ref(storagePath).delete();
    } catch (_) {
      // Já não existe (ou nunca existiu) — nada a limpar.
    }
  }

  Future<Uint8List> _comprimir(Uint8List original) async {
    final resultado = await FlutterImageCompress.compressWithList(
      original,
      quality: 75,
      minWidth: 1280,
      minHeight: 1280,
      format: CompressFormat.jpeg,
    );
    return resultado;
  }
}
