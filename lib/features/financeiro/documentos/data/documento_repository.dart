import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../../../core/constants/firestore_collections.dart';
import '../domain/documento_gerado.dart';

/// Reserva persistente de um documento que já recebeu assinatura.
///
/// Enquanto o PDF ainda não foi concluído, a assinatura PNG fica
/// temporariamente no Firestore como Blob. Quando o documento vira
/// `ativo`, esse Blob é removido.
class DocumentoPreparacao {
  final String documentoId;
  final String numero;
  final DocumentoTipo tipo;
  final DocumentoStatus status;
  final Assinatura assinatura;
  final Uint8List assinaturaPng;

  const DocumentoPreparacao({
    required this.documentoId,
    required this.numero,
    required this.tipo,
    required this.status,
    required this.assinatura,
    required this.assinaturaPng,
  });
}

class DocumentoRepository {
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  DocumentoRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(FirestoreCollections.documentosGerados);

  String _prefixo(DocumentoTipo tipo) => switch (tipo) {
    DocumentoTipo.instalacao => 'INS',
    DocumentoTipo.acertoEReposicao => 'REP',
    DocumentoTipo.encerramento => 'RET',
  };

  DocumentReference<Map<String, dynamic>> _counterRef(
      String orgId,
      DocumentoTipo tipo,
      ) {
    final prefixo = _prefixo(tipo);
    return _firestore
        .collection('counters')
        .doc('documentos_${prefixo}_$orgId');
  }

  /// ID determinístico: a mesma visita + tipo aponta sempre para a
  /// mesma preparação. Isso impede duas reservas concorrentes para o
  /// mesmo documento.
  DocumentReference<Map<String, dynamic>> _preparacaoRef({
    required String orgId,
    required String visitaId,
    required DocumentoTipo tipo,
  }) {
    final chave = '$orgId|$visitaId|${tipoToString(tipo)}';
    final digest = sha256.convert(utf8.encode(chave)).toString();
    return _collection.doc('op_$digest');
  }

  DocumentoPreparacao? _preparacaoFromSnapshot(
      DocumentSnapshot<Map<String, dynamic>> snapshot,
      ) {
    if (!snapshot.exists) return null;

    final data = snapshot.data();
    if (data == null) return null;

    final statusTexto = data['status'] as String?;
    final status = switch (statusTexto) {
      'gerando' => DocumentoStatus.gerando,
      'erro' => DocumentoStatus.erro,
      'cancelado' => DocumentoStatus.cancelado,
      _ => DocumentoStatus.ativo,
    };

    if (status != DocumentoStatus.gerando &&
        status != DocumentoStatus.erro) {
      return null;
    }

    final assinaturaData = data['assinatura'];
    final assinaturaBlob = data['assinaturaPngTemporaria'];

    if (assinaturaData is! Map<String, dynamic> ||
        assinaturaBlob is! Blob) {
      return null;
    }

    return DocumentoPreparacao(
      documentoId: snapshot.id,
      numero: data['numero'] as String? ?? '',
      tipo: DocumentoTipo.values.firstWhere(
            (item) => item.name == data['tipo'],
        orElse: () => DocumentoTipo.acertoEReposicao,
      ),
      status: status,
      assinatura: Assinatura.fromMap(assinaturaData),
      assinaturaPng: Uint8List.fromList(assinaturaBlob.bytes),
    );
  }

  /// Compatibilidade com fluxos antigos.
  ///
  /// Os fluxos atualizados devem usar [prepararDocumentoAssinado],
  /// porque ele reserva o número E persiste a assinatura na mesma
  /// transação.
  Future<String> reservarNumero(
      String orgId,
      DocumentoTipo tipo,
      ) async {
    final prefixo = _prefixo(tipo);
    final counterRef = _counterRef(orgId, tipo);

    final novoNumero =
    await _firestore.runTransaction<int>((transaction) async {
      final snapshot = await transaction.get(counterRef);
      final atual = (snapshot.data()?['seq'] as num?)?.toInt() ?? 0;
      final proximo = atual + 1;

      transaction.set(
        counterRef,
        {'seq': proximo},
        SetOptions(merge: true),
      );

      return proximo;
    });

    return '$prefixo-${novoNumero.toString().padLeft(6, '0')}';
  }

  /// Reserva o número e salva a assinatura ANTES de gerar o PDF.
  ///
  /// Se a operação já possuir uma preparação em `gerando` ou `erro`,
  /// devolve a mesma reserva e a mesma assinatura, sem consumir outro
  /// número e sem pedir nova assinatura.
  Future<DocumentoPreparacao> prepararDocumentoAssinado({
    required String orgId,
    required DocumentoTipo tipo,
    required String clienteId,
    required String nomeCliente,
    required String visitaId,
    required Assinatura assinatura,
    required Uint8List assinaturaPng,
  }) async {
    final org = orgId.trim();
    final cliente = clienteId.trim();
    final visita = visitaId.trim();

    if (org.isEmpty || cliente.isEmpty || visita.isEmpty) {
      throw ArgumentError(
        'Organização, cliente e visita são obrigatórios.',
      );
    }

    if (assinaturaPng.isEmpty) {
      throw ArgumentError('A assinatura não pode estar vazia.');
    }

    final docRef = _preparacaoRef(
      orgId: org,
      visitaId: visita,
      tipo: tipo,
    );
    final counterRef = _counterRef(org, tipo);
    final prefixo = _prefixo(tipo);

    return _firestore.runTransaction<DocumentoPreparacao>(
          (transaction) async {
        final existente = await transaction.get(docRef);

        if (existente.exists) {
          final data = existente.data()!;
          final status = data['status'] as String?;

          if (status == statusToString(DocumentoStatus.ativo)) {
            throw StateError(
              'O documento desta visita já foi gerado.',
            );
          }

          if (status == statusToString(DocumentoStatus.cancelado)) {
            throw StateError(
              'O documento desta visita foi cancelado. '
                  'A reemissão deve usar o fluxo de reemissão.',
            );
          }

          final numero = data['numero'] as String? ?? '';
          if (numero.isEmpty) {
            throw StateError(
              'A preparação existente não possui número válido.',
            );
          }

          final assinaturaExistente = data['assinatura'];
          final pngExistente = data['assinaturaPngTemporaria'];

          if (assinaturaExistente is Map<String, dynamic> &&
              pngExistente is Blob) {
            return DocumentoPreparacao(
              documentoId: docRef.id,
              numero: numero,
              tipo: tipo,
              status: status == statusToString(DocumentoStatus.erro)
                  ? DocumentoStatus.erro
                  : DocumentoStatus.gerando,
              assinatura: Assinatura.fromMap(assinaturaExistente),
              assinaturaPng:
              Uint8List.fromList(pngExistente.bytes),
            );
          }

          // Registro incompleto de uma tentativa antiga: preserva o
          // mesmo número e completa a assinatura.
          transaction.update(docRef, {
            'clienteId': cliente,
            'nomeCliente': nomeCliente.trim(),
            'visitaId': visita,
            'assinatura': assinatura.toMap(),
            'assinaturaPngTemporaria': Blob(assinaturaPng),
            'status': statusToString(DocumentoStatus.gerando),
            'erroGeracao': FieldValue.delete(),
            'atualizadoEm': FieldValue.serverTimestamp(),
          });

          return DocumentoPreparacao(
            documentoId: docRef.id,
            numero: numero,
            tipo: tipo,
            status: DocumentoStatus.gerando,
            assinatura: assinatura,
            assinaturaPng: Uint8List.fromList(assinaturaPng),
          );
        }

        final counterSnapshot = await transaction.get(counterRef);
        final atual =
            (counterSnapshot.data()?['seq'] as num?)?.toInt() ?? 0;
        final proximo = atual + 1;
        final numero =
            '$prefixo-${proximo.toString().padLeft(6, '0')}';

        transaction.set(
          counterRef,
          {'seq': proximo},
          SetOptions(merge: true),
        );

        transaction.set(docRef, {
          'orgId': org,
          'numero': numero,
          'tipo': tipoToString(tipo),
          'clienteId': cliente,
          'nomeCliente': nomeCliente.trim(),
          'visitaId': visita,
          'urlStorage': '',
          'hash': '',
          'status': statusToString(DocumentoStatus.gerando),
          'assinatura': assinatura.toMap(),
          'assinaturaPngTemporaria': Blob(assinaturaPng),
          'tentativasGeracao': 0,
          'criadoEm': FieldValue.serverTimestamp(),
          'atualizadoEm': FieldValue.serverTimestamp(),
        });

        return DocumentoPreparacao(
          documentoId: docRef.id,
          numero: numero,
          tipo: tipo,
          status: DocumentoStatus.gerando,
          assinatura: assinatura,
          assinaturaPng: Uint8List.fromList(assinaturaPng),
        );
      },
    );
  }

  /// Recupera uma tentativa incompleta para permitir retry sem pedir
  /// nova assinatura.
  Future<DocumentoPreparacao?> buscarPreparacaoDaVisita({
    required String orgId,
    required String visitaId,
    required DocumentoTipo tipo,
  }) async {
    final ref = _preparacaoRef(
      orgId: orgId.trim(),
      visitaId: visitaId.trim(),
      tipo: tipo,
    );

    final snapshot = await ref.get();
    return _preparacaoFromSnapshot(snapshot);
  }

  /// Registra a falha sem perder número nem assinatura.
  Future<void> marcarErroGeracao({
    required String orgId,
    required String visitaId,
    required DocumentoTipo tipo,
    required Object erro,
  }) async {
    final ref = _preparacaoRef(
      orgId: orgId.trim(),
      visitaId: visitaId.trim(),
      tipo: tipo,
    );

    final snapshot = await ref.get();
    if (!snapshot.exists) return;

    final status = snapshot.data()?['status'] as String?;
    if (status == statusToString(DocumentoStatus.ativo) ||
        status == statusToString(DocumentoStatus.cancelado)) {
      return;
    }

    final mensagem = erro.toString().trim();
    final mensagemSegura = mensagem.length > 500
        ? mensagem.substring(0, 500)
        : mensagem;

    await ref.update({
      'status': statusToString(DocumentoStatus.erro),
      'erroGeracao': mensagemSegura,
      'tentativasGeracao': FieldValue.increment(1),
      'atualizadoEm': FieldValue.serverTimestamp(),
    });
  }

  /// Sobe o PDF e ativa o MESMO registro reservado.
  ///
  /// Se for chamado novamente depois de sucesso, devolve o documento
  /// ativo já existente. Se não houver preparação (compatibilidade com
  /// telas antigas), mantém o comportamento legado de criar o registro.
  Future<DocumentoGerado> salvarDocumento({
    required String orgId,
    required String numero,
    required DocumentoTipo tipo,
    required String clienteId,
    required String nomeCliente,
    required String visitaId,
    required Uint8List pdfBytes,
    required Assinatura assinatura,
  }) async {
    final preparacaoRef = _preparacaoRef(
      orgId: orgId.trim(),
      visitaId: visitaId.trim(),
      tipo: tipo,
    );

    final preparacaoSnapshot = await preparacaoRef.get();

    if (preparacaoSnapshot.exists) {
      final data = preparacaoSnapshot.data()!;
      final status = data['status'] as String?;

      if (status == statusToString(DocumentoStatus.ativo) &&
          (data['urlStorage'] as String? ?? '').isNotEmpty) {
        return DocumentoGerado.fromFirestore(
          preparacaoSnapshot.id,
          data,
        );
      }

      final numeroReservado = data['numero'] as String? ?? '';
      if (numeroReservado.isNotEmpty && numeroReservado != numero) {
        throw StateError(
          'O número informado não corresponde à reserva desta visita.',
        );
      }
    }

    final hash = sha256.convert(pdfBytes).toString();

    final nomeArquivoSeguro = nomeCliente
        .trim()
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-');

    final nomeArquivo = nomeArquivoSeguro.isEmpty
        ? '$numero.pdf'
        : '${numero}_$nomeArquivoSeguro.pdf';

    final storageRef =
    _storage.ref().child('documentos/$orgId/$nomeArquivo');

    try {
      await storageRef.putData(
        pdfBytes,
        SettableMetadata(contentType: 'application/pdf'),
      );

      final url = await storageRef.getDownloadURL();

      if (preparacaoSnapshot.exists) {
        await _firestore.runTransaction((transaction) async {
          final atual = await transaction.get(preparacaoRef);

          if (!atual.exists) {
            throw StateError(
              'A reserva do documento não foi encontrada.',
            );
          }

          final atualData = atual.data()!;
          final atualStatus = atualData['status'] as String?;

          if (atualStatus ==
              statusToString(DocumentoStatus.ativo)) {
            return;
          }

          transaction.update(preparacaoRef, {
            'orgId': orgId,
            'numero': numero,
            'tipo': tipoToString(tipo),
            'clienteId': clienteId,
            'nomeCliente': nomeCliente.trim(),
            'visitaId': visitaId,
            'urlStorage': url,
            'hash': hash,
            'status': statusToString(DocumentoStatus.ativo),
            'assinatura': assinatura.toMap(),
            'assinaturaPngTemporaria': FieldValue.delete(),
            'erroGeracao': FieldValue.delete(),
            'atualizadoEm': FieldValue.serverTimestamp(),
          });
        });

        final finalizado = await preparacaoRef.get();
        return DocumentoGerado.fromFirestore(
          finalizado.id,
          finalizado.data()!,
        );
      }

      // Compatibilidade com chamadas antigas que ainda usam
      // reservarNumero() sem preparação persistente.
      final docRef = await _collection.add({
        'orgId': orgId,
        'numero': numero,
        'tipo': tipoToString(tipo),
        'clienteId': clienteId,
        'nomeCliente': nomeCliente.trim(),
        'visitaId': visitaId,
        'urlStorage': url,
        'hash': hash,
        'status': statusToString(DocumentoStatus.ativo),
        'assinatura': assinatura.toMap(),
        'criadoEm': FieldValue.serverTimestamp(),
        'atualizadoEm': FieldValue.serverTimestamp(),
      });

      return DocumentoGerado(
        id: docRef.id,
        orgId: orgId,
        numero: numero,
        tipo: tipo,
        clienteId: clienteId,
        visitaId: visitaId,
        urlStorage: url,
        hash: hash,
        assinatura: assinatura,
      );
    } catch (erro) {
      if (preparacaoSnapshot.exists) {
        try {
          await marcarErroGeracao(
            orgId: orgId,
            visitaId: visitaId,
            tipo: tipo,
            erro: erro,
          );
        } catch (_) {
          // Não mascara o erro principal da geração.
        }
      }

      rethrow;
    }
  }

  Stream<List<DocumentoGerado>> watchDoCliente(String clienteId) {
    return _collection
        .where('clienteId', isEqualTo: clienteId)
        .orderBy('criadoEm', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
          .map(
            (d) => DocumentoGerado.fromFirestore(
          d.id,
          d.data(),
        ),
      )
          .toList(),
    );
  }
}
