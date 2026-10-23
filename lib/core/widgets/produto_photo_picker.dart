import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Seletor de foto principal do produto: câmera ou galeria, com
/// preview, troca e remoção antes de salvar.
///
/// Trabalha com bytes (Uint8List) em vez de dart:io/File — File não
/// funciona de verdade no Flutter Web (o "path" de um XFile ali é uma
/// blob URL, não um caminho de sistema de arquivos). Bytes funcionam
/// igual em Web, Android e iOS.
class ProdutoPhotoPicker extends StatelessWidget {
  final Uint8List? bytesSelecionados;
  final String? urlExistente;
  final ValueChanged<Uint8List?> onChanged;

  const ProdutoPhotoPicker({
    super.key,
    required this.bytesSelecionados,
    required this.urlExistente,
    required this.onChanged,
  });

  Future<void> _selecionar(BuildContext context, ImageSource source) async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: source,
      maxWidth: 2000,
      imageQuality: 90,
    );
    if (xfile == null) return;
    final bytes = await xfile.readAsBytes();
    onChanged(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final temImagem = bytesSelecionados != null || urlExistente != null;

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 160,
            height: 160,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: temImagem
                ? (bytesSelecionados != null
                    ? Image.memory(bytesSelecionados!, fit: BoxFit.cover)
                    : Image.network(urlExistente!, fit: BoxFit.cover))
                : Icon(
                    Icons.inventory_2_outlined,
                    size: 56,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: () => _selecionar(context, ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Tirar foto'),
            ),
            OutlinedButton.icon(
              onPressed: () => _selecionar(context, ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Escolher foto'),
            ),
            if (temImagem)
              TextButton.icon(
                onPressed: () => onChanged(null),
                icon: const Icon(Icons.close),
                label: const Text('Remover'),
              ),
          ],
        ),
      ],
    );
  }
}
