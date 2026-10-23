import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_collections.dart';
import '../domain/visita.dart';

const List<String> _estadosEmAndamento = <String>[
  'iniciada',
  'emConferencia',
  'conferenciaConcluida',
  'emReposicao',
  'aguardandoAssinatura',
];

const List<String> _estadosConcluidos = <String>[
  'finalizada',
  'sincronizada',
];

class VisitaJaEmAndamentoException implements Exception {
  final String vendedorId;
  final String? visitaId;

  const VisitaJaEmAndamentoException(
      this.vendedorId, {
        this.visitaId,
      });

  /// Mantido temporariamente para não quebrar telas que ainda usam o nome
  /// antigo. O repositório possui somente o id do vendedor, não o nome.
  @Deprecated('Use vendedorId')
  String get vendedorNome => vendedorId;

  bool iniciadaPelo(String usuarioId) => vendedorId == usuarioId;

  @override
  String toString() =>
      'Este cliente já possui uma visita em andamento. Retome a visita existente.';
}

class VendedorComVisitaEmAndamentoException implements Exception {
  final String visitaId;
  final String clienteId;

  const VendedorComVisitaEmAndamentoException({
    required this.visitaId,
    required this.clienteId,
  });

  @override
  String toString() =>
      'Você já possui uma visita em andamento. Finalize ou cancele antes de iniciar outra.';
}

class VisitaRepository {
  final FirebaseFirestore _firestore;

  VisitaRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(FirestoreCollections.visitas);

  CollectionReference<Map<String, dynamic>> get _clientesCollection =>
      _firestore.collection(FirestoreCollections.clientes);

  Stream<Visita?> watchById(String id) {
    return _collection.doc(id).snapshots().map(
          (doc) =>
      doc.exists ? Visita.fromFirestore(doc.id, doc.data()!) : null,
    );
  }

  Future<Visita?> buscarById(String id) async {
    final doc = await _collection.doc(id).get();
    if (!doc.exists) return null;
    return Visita.fromFirestore(doc.id, doc.data()!);
  }

  Stream<List<Visita>> watchHistoricoDoCliente(String clienteId) {
    return _collection
        .where('clienteId', isEqualTo: clienteId)
        .orderBy('criadaEm', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
          .map((doc) => Visita.fromFirestore(doc.id, doc.data()))
          .toList(),
    );
  }

  Stream<Visita?> watchEmAndamentoDoCliente({
    required String orgId,
    required String clienteId,
  }) {
    return _collection
        .where('orgId', isEqualTo: orgId)
        .where('clienteId', isEqualTo: clienteId)
        .where('estado', whereIn: _estadosEmAndamento)
        .limit(1)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      final doc = snapshot.docs.first;
      return Visita.fromFirestore(doc.id, doc.data());
    });
  }

  Stream<List<Visita>> watchEmAndamentoDaOrganizacao(String orgId) {
    return _collection
        .where('orgId', isEqualTo: orgId)
        .where('estado', whereIn: _estadosEmAndamento)
        .snapshots()
        .map((snapshot) {
      final visitas = snapshot.docs
          .map((doc) => Visita.fromFirestore(doc.id, doc.data()))
          .toList();

      visitas.sort((a, b) {
        final inicioA = a.inicioEfetivo ?? DateTime.fromMillisecondsSinceEpoch(0);
        final inicioB = b.inicioEfetivo ?? DateTime.fromMillisecondsSinceEpoch(0);
        return inicioB.compareTo(inicioA);
      });

      return visitas;
    });
  }

  Stream<List<Visita>> watchRealizadasDaOrganizacao(
      String orgId, {
        int limite = 100,
      }) {
    return _collection
        .where('orgId', isEqualTo: orgId)
        .where('estado', whereIn: _estadosConcluidos)
        .orderBy('finalizadaEm', descending: true)
        .limit(limite)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
          .map((doc) => Visita.fromFirestore(doc.id, doc.data()))
          .toList(),
    );
  }

  /// Busca primeiro o vínculo ativo salvo no cliente e depois consulta a
  /// coleção de visitas. A segunda etapa mantém compatibilidade com visitas
  /// criadas antes da existência do campo visitaEmAndamentoId.
  Future<Visita?> buscarEmAndamentoDoCliente({
    required String orgId,
    required String clienteId,
  }) async {
    final clienteDoc = await _clientesCollection.doc(clienteId).get();
    final visitaVinculadaId =
    clienteDoc.data()?['visitaEmAndamentoId'] as String?;

    if (visitaVinculadaId != null && visitaVinculadaId.isNotEmpty) {
      final vinculada = await buscarById(visitaVinculadaId);
      if (vinculada != null &&
          vinculada.orgId == orgId &&
          vinculada.clienteId == clienteId &&
          vinculada.emAndamento) {
        return vinculada;
      }
    }

    final snapshot = await _collection
        .where('orgId', isEqualTo: orgId)
        .where('clienteId', isEqualTo: clienteId)
        .where('estado', whereIn: _estadosEmAndamento)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;

    final doc = snapshot.docs.first;
    return Visita.fromFirestore(doc.id, doc.data());
  }

  Future<Visita?> buscarEmAndamentoDoVendedor({
    required String orgId,
    required String vendedorId,
  }) async {
    final snapshot = await _collection
        .where('orgId', isEqualTo: orgId)
        .where('vendedorId', isEqualTo: vendedorId)
        .where('estado', whereIn: _estadosEmAndamento)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;

    final doc = snapshot.docs.first;
    return Visita.fromFirestore(doc.id, doc.data());
  }

  /// Cria a visita e registra o vínculo ativo no cliente na mesma transação.
  /// Isso impede duas confirmações simultâneas para o mesmo cliente.
  Future<String> iniciar({
    required String orgId,
    required String clienteId,
    required String vendedorId,
    required VisitaTipo tipo,
    DateTime? dataPrevista,
    String? consignmentId,
    String? expositorId,
  }) async {
    final visitaDoCliente = await buscarEmAndamentoDoCliente(
      orgId: orgId,
      clienteId: clienteId,
    );

    if (visitaDoCliente != null) {
      throw VisitaJaEmAndamentoException(
        visitaDoCliente.vendedorId,
        visitaId: visitaDoCliente.id,
      );
    }

    final visitaDoVendedor = await buscarEmAndamentoDoVendedor(
      orgId: orgId,
      vendedorId: vendedorId,
    );

    if (visitaDoVendedor != null &&
        visitaDoVendedor.clienteId != clienteId &&
        visitaDoVendedor.id != null) {
      throw VendedorComVisitaEmAndamentoException(
        visitaId: visitaDoVendedor.id!,
        clienteId: visitaDoVendedor.clienteId,
      );
    }

    final visitaRef = _collection.doc();
    final clienteRef = _clientesCollection.doc(clienteId);

    await _firestore.runTransaction<void>((transaction) async {
      final clienteSnapshot = await transaction.get(clienteRef);

      if (!clienteSnapshot.exists) {
        throw StateError('Cliente não encontrado para iniciar a visita.');
      }

      final clienteData = clienteSnapshot.data();
      final clienteOrgId = clienteData?['orgId'] as String?;

      if (clienteOrgId != null &&
          clienteOrgId.isNotEmpty &&
          clienteOrgId != orgId) {
        throw StateError('O cliente pertence a outra organização.');
      }

      final visitaAtivaId =
      clienteData?['visitaEmAndamentoId'] as String?;

      if (visitaAtivaId != null && visitaAtivaId.isNotEmpty) {
        final visitaAtivaRef = _collection.doc(visitaAtivaId);
        final visitaAtivaSnapshot = await transaction.get(visitaAtivaRef);

        if (visitaAtivaSnapshot.exists) {
          final visitaAtiva = Visita.fromFirestore(
            visitaAtivaSnapshot.id,
            visitaAtivaSnapshot.data()!,
          );

          if (visitaAtiva.emAndamento) {
            throw VisitaJaEmAndamentoException(
              visitaAtiva.vendedorId,
              visitaId: visitaAtiva.id,
            );
          }
        }
      }

      transaction.set(visitaRef, {
        'orgId': orgId,
        'clienteId': clienteId,
        'vendedorId': vendedorId,
        'tipo': tipoParaString(tipo),
        'estado': estadoParaString(VisitaEstado.iniciada),
        'numero': null,
        'criadaEm': FieldValue.serverTimestamp(),
        'dataPrevista': dataPrevista,
        'iniciadaEm': FieldValue.serverTimestamp(),
        'consignmentId': consignmentId,
        'expositorId': expositorId,
        'finalizadaEm': null,
      });

      transaction.update(clienteRef, {
        'visitaEmAndamentoId': visitaRef.id,
      });
    });

    return visitaRef.id;
  }

  Future<void> atualizarEstado(
      String visitaId,
      VisitaEstado estado,
      ) {
    return _collection.doc(visitaId).update({
      'estado': estadoParaString(estado),
    });
  }

  /// Permite definir a consignação e o expositor depois da criação, como no
  /// fluxo de instalação inicial em que esses vínculos ainda não existem.
  Future<void> atualizarVinculos({
    required String visitaId,
    String? consignmentId,
    String? expositorId,
  }) {
    final dados = <String, dynamic>{};

    if (consignmentId != null) {
      dados['consignmentId'] = consignmentId;
    }

    if (expositorId != null) {
      dados['expositorId'] = expositorId;
    }

    if (dados.isEmpty) return Future<void>.value();
    return _collection.doc(visitaId).update(dados);
  }

  /// Salva um snapshot imutável com os dados necessários para gerar
  /// posteriormente o documento da visita.
  ///
  /// Esse snapshot NÃO executa novamente estoque, consignação, financeiro
  /// ou expositor. Ele existe apenas para permitir que uma visita já
  /// finalizada tenha o documento assinado/gerado depois.
  ///
  /// Se já existir um snapshot, ele não é sobrescrito.
  Future<void> salvarSnapshotDocumentoPendente({
    required String visitaId,
    required Map<String, dynamic> snapshot,
  }) async {
    final id = visitaId.trim();

    if (id.isEmpty) {
      throw ArgumentError('O identificador da visita é obrigatório.');
    }

    if (snapshot.isEmpty) {
      throw ArgumentError('O snapshot do documento não pode estar vazio.');
    }

    final visitaRef = _collection.doc(id);

    await _firestore.runTransaction<void>((transaction) async {
      final visitaSnapshot = await transaction.get(visitaRef);

      if (!visitaSnapshot.exists) {
        throw StateError('Visita não encontrada para salvar o documento.');
      }

      final visitaData = visitaSnapshot.data()!;
      final snapshotAtual = visitaData['documentoSnapshot'];

      if (snapshotAtual is Map && snapshotAtual.isNotEmpty) {
        return;
      }

      final estadoAtual = visitaData['estado'] as String?;

      if (!_estadosConcluidos.contains(estadoAtual) &&
          estadoAtual != estadoParaString(
            VisitaEstado.aguardandoAssinatura,
          )) {
        throw StateError(
          'O snapshot do documento só pode ser salvo após a conclusão '
              'da operação.',
        );
      }

      transaction.update(visitaRef, {
        'documentoSnapshot': Map<String, dynamic>.from(snapshot),
        'documentoSnapshotVersao': 1,
        'documentoSnapshotCriadoEm': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Recupera o snapshot usado para reabrir uma assinatura pendente.
  Future<Map<String, dynamic>?> carregarSnapshotDocumento(
      String visitaId,
      ) async {
    final id = visitaId.trim();

    if (id.isEmpty) {
      return null;
    }

    final snapshot = await _collection.doc(id).get();

    if (!snapshot.exists) {
      return null;
    }

    final raw = snapshot.data()?['documentoSnapshot'];

    if (raw is! Map) {
      return null;
    }

    return Map<String, dynamic>.from(raw);
  }

  /// Salva as quantidades escolhidas durante a instalação.
  ///
  /// Somente itens com quantidade maior que zero permanecem no rascunho.
  Future<void> salvarRascunhoInstalacao({
    required String visitaId,
    required Map<String, int> quantidades,
  }) async {
    final id = visitaId.trim();

    if (id.isEmpty) {
      return;
    }

    final rascunho = <String, int>{};

    for (final entry in quantidades.entries) {
      final skuId = entry.key.trim();
      final quantidade = entry.value;

      if (skuId.isEmpty || quantidade <= 0) {
        continue;
      }

      rascunho[skuId] = quantidade;
    }

    if (rascunho.isEmpty) {
      await limparRascunhoInstalacao(id);
      return;
    }

    await _collection.doc(id).update({
      'rascunhoInstalacao': rascunho,
      'rascunhoInstalacaoAtualizadoEm': FieldValue.serverTimestamp(),
    });
  }

  /// Recupera as quantidades salvas anteriormente para esta visita.
  Future<Map<String, int>> carregarRascunhoInstalacao(
      String visitaId,
      ) async {
    final id = visitaId.trim();

    if (id.isEmpty) {
      return <String, int>{};
    }

    final snapshot = await _collection.doc(id).get();

    if (!snapshot.exists) {
      return <String, int>{};
    }

    final raw = snapshot.data()?['rascunhoInstalacao'];

    if (raw is! Map) {
      return <String, int>{};
    }

    final rascunho = <String, int>{};

    raw.forEach((key, value) {
      if (key is! String || value is! num) {
        return;
      }

      final skuId = key.trim();
      final quantidade = value.toInt();

      if (skuId.isEmpty || quantidade <= 0) {
        return;
      }

      rascunho[skuId] = quantidade;
    });

    return rascunho;
  }

  /// Remove o rascunho da instalação.
  Future<void> limparRascunhoInstalacao(
      String visitaId,
      ) async {
    final id = visitaId.trim();

    if (id.isEmpty) {
      return;
    }

    await _collection.doc(id).update({
      'rascunhoInstalacao': FieldValue.delete(),
      'rascunhoInstalacaoAtualizadoEm': FieldValue.delete(),
    });
  }

  /// Salva o andamento da conferência/reposição para permitir retomar
  /// a visita exatamente de onde o vendedor parou.
  Future<void> salvarRascunhoExecucao({
    required String visitaId,
    required List<Map<String, dynamic>> conferencia,
    required Set<String> itensConferidos,
    required Map<String, int> reposicao,
    required int etapa,
  }) async {
    final id = visitaId.trim();

    if (id.isEmpty) {
      return;
    }

    final reposicaoValida = <String, int>{};

    for (final entry in reposicao.entries) {
      final skuId = entry.key.trim();
      final quantidade = entry.value;

      if (skuId.isEmpty || quantidade <= 0) {
        continue;
      }

      reposicaoValida[skuId] = quantidade;
    }

    final conferidosValidos = itensConferidos
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    await _collection.doc(id).update({
      'rascunhoExecucao': {
        'etapa': etapa.clamp(0, 2).toInt(),
        'conferencia': conferencia,
        'itensConferidos': conferidosValidos,
        'reposicao': reposicaoValida,
      },
      'rascunhoExecucaoAtualizadoEm': FieldValue.serverTimestamp(),
    });
  }

  /// Recupera o rascunho da conferência/reposição, quando existir.
  Future<Map<String, dynamic>?> carregarRascunhoExecucao(
      String visitaId,
      ) async {
    final id = visitaId.trim();

    if (id.isEmpty) {
      return null;
    }

    final snapshot = await _collection.doc(id).get();

    if (!snapshot.exists) {
      return null;
    }

    final raw = snapshot.data()?['rascunhoExecucao'];

    if (raw is! Map) {
      return null;
    }

    return Map<String, dynamic>.from(raw);
  }

  /// Remove o rascunho da conferência/reposição.
  Future<void> limparRascunhoExecucao(
      String visitaId,
      ) async {
    final id = visitaId.trim();

    if (id.isEmpty) {
      return;
    }

    await _collection.doc(id).update({
      'rascunhoExecucao': FieldValue.delete(),
      'rascunhoExecucaoAtualizadoEm': FieldValue.delete(),
    });
  }

  Future<void> cancelar(String visitaId) async {
    final visitaRef = _collection.doc(visitaId);

    await _firestore.runTransaction<void>((transaction) async {
      final visitaSnapshot = await transaction.get(visitaRef);
      if (!visitaSnapshot.exists) return;

      final visitaData = visitaSnapshot.data()!;
      final clienteId = visitaData['clienteId'] as String?;

      DocumentReference<Map<String, dynamic>>? clienteRef;
      DocumentSnapshot<Map<String, dynamic>>? clienteSnapshot;

      if (clienteId != null && clienteId.isNotEmpty) {
        clienteRef = _clientesCollection.doc(clienteId);
        clienteSnapshot = await transaction.get(clienteRef);
      }

      transaction.update(visitaRef, {
        'estado': estadoParaString(VisitaEstado.cancelada),
        'rascunhoInstalacao': FieldValue.delete(),
        'rascunhoInstalacaoAtualizadoEm': FieldValue.delete(),
        'rascunhoExecucao': FieldValue.delete(),
        'rascunhoExecucaoAtualizadoEm': FieldValue.delete(),
        'documentoSnapshot': FieldValue.delete(),
        'documentoSnapshotVersao': FieldValue.delete(),
        'documentoSnapshotCriadoEm': FieldValue.delete(),
      });

      if (clienteRef != null &&
          clienteSnapshot != null &&
          clienteSnapshot.exists &&
          clienteSnapshot.data()?['visitaEmAndamentoId'] == visitaId) {
        transaction.update(clienteRef, {
          'visitaEmAndamentoId': FieldValue.delete(),
        });
      }
    });
  }

  /// Gera o número e finaliza de forma idempotente. Se o método for chamado
  /// novamente para a mesma visita, devolve o número já existente sem avançar
  /// o contador uma segunda vez.
  Future<String> finalizar(
      String orgId,
      String visitaId, {
        Map<String, dynamic>? documentoSnapshot,
      }) async {
    final visitaRef = _collection.doc(visitaId);
    final counterRef = _firestore.collection('counters').doc('visitas_$orgId');

    return _firestore.runTransaction<String>((transaction) async {
      final visitaSnapshot = await transaction.get(visitaRef);

      if (!visitaSnapshot.exists) {
        throw StateError('Visita não encontrada para finalização.');
      }

      final visitaData = visitaSnapshot.data()!;
      final visitaOrgId = visitaData['orgId'] as String? ?? '';

      if (visitaOrgId != orgId) {
        throw StateError('A visita pertence a outra organização.');
      }

      final estadoAtual = visitaData['estado'] as String?;
      final numeroAtual = visitaData['numero'] as String?;
      final snapshotAtual = visitaData['documentoSnapshot'];

      final deveSalvarSnapshot =
          documentoSnapshot != null &&
              documentoSnapshot.isNotEmpty &&
              !(snapshotAtual is Map && snapshotAtual.isNotEmpty);

      if (_estadosConcluidos.contains(estadoAtual) &&
          numeroAtual != null &&
          numeroAtual.isNotEmpty) {
        if (deveSalvarSnapshot) {
          transaction.update(visitaRef, {
            'documentoSnapshot':
            Map<String, dynamic>.from(documentoSnapshot),
            'documentoSnapshotVersao': 1,
            'documentoSnapshotCriadoEm': FieldValue.serverTimestamp(),
          });
        }

        return numeroAtual;
      }

      final counterSnapshot = await transaction.get(counterRef);
      final atual = (counterSnapshot.data()?['seq'] as num?)?.toInt() ?? 0;
      final proximo = atual + 1;
      final numero = 'VIS-${proximo.toString().padLeft(6, '0')}';

      final clienteId = visitaData['clienteId'] as String?;
      DocumentReference<Map<String, dynamic>>? clienteRef;
      DocumentSnapshot<Map<String, dynamic>>? clienteSnapshot;

      if (clienteId != null && clienteId.isNotEmpty) {
        clienteRef = _clientesCollection.doc(clienteId);
        clienteSnapshot = await transaction.get(clienteRef);
      }

      transaction.set(
        counterRef,
        {'seq': proximo},
        SetOptions(merge: true),
      );

      final dadosFinalizacao = <String, dynamic>{
        'estado': estadoParaString(VisitaEstado.finalizada),
        'numero': numero,
        'finalizadaEm': FieldValue.serverTimestamp(),
        'rascunhoInstalacao': FieldValue.delete(),
        'rascunhoInstalacaoAtualizadoEm': FieldValue.delete(),
        'rascunhoExecucao': FieldValue.delete(),
        'rascunhoExecucaoAtualizadoEm': FieldValue.delete(),
      };

      if (deveSalvarSnapshot) {
        dadosFinalizacao.addAll({
          'documentoSnapshot':
          Map<String, dynamic>.from(documentoSnapshot),
          'documentoSnapshotVersao': 1,
          'documentoSnapshotCriadoEm': FieldValue.serverTimestamp(),
        });
      }

      transaction.update(visitaRef, dadosFinalizacao);

      if (clienteRef != null &&
          clienteSnapshot != null &&
          clienteSnapshot.exists &&
          clienteSnapshot.data()?['visitaEmAndamentoId'] == visitaId) {
        transaction.update(clienteRef, {
          'visitaEmAndamentoId': FieldValue.delete(),
        });
      }

      return numero;
    });
  }
}
