import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/documento_repository.dart';
import '../data/pdf_service.dart';
import '../domain/documento_gerado.dart';

final documentoRepositoryProvider = Provider<DocumentoRepository>((ref) {
  return DocumentoRepository();
});

final pdfServiceProvider = Provider<PdfService>((ref) {
  return PdfService();
});

final documentosDoClienteProvider =
StreamProvider.family<List<DocumentoGerado>, String>((ref, clienteId) {
  return ref.watch(documentoRepositoryProvider).watchDoCliente(clienteId);
});