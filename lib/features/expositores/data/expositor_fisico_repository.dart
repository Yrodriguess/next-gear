import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_collections.dart';
import '../domain/expositor_fisico.dart';
import '../domain/expositor_movimentacao.dart';

class ExpositorFisicoRepository {
  final FirebaseFirestore _firestore;

  ExpositorFisicoRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(FirestoreCollections.expositoresFisicos);

  CollectionReference<Map<String, dynamic>> get _movimentacoes =>
      _firestore.collection(FirestoreCollections.expositorMovimentacoes);

  Stream<List<ExpositorFisico>> watchAll(String orgId) {
    return _collection
        .where('orgId', isEqualTo: orgId)
        .orderBy('numero')
        .snapshots()
        .map((snap) => snap.docs
        .map((d) => ExpositorFisico.fromFirestore(d.id, d.data()))
        .toList());
  }

  /// Busca um expositor específico, validando que ele pertence à
  /// organização informada — antes, watchById confiava só no ID do
  /// documento, sem checar orgId (um ID vazado/adivinhado de outra
  /// organização passaria batido).
  Stream<ExpositorFisico?> watchById(String orgId, String id) {
    return _collection.doc(id).snapshots().map((doc) {
      if (!doc.exists) return null;
      final expositor = ExpositorFisico.fromFirestore(doc.id, doc.data()!);
      return expositor.orgId == orgId ? expositor : null;
    });
  }

  /// Expositores disponíveis pra instalar (em estoque, sem cliente) —
  /// usado na tela de Instalação (seção 7.5 do Blueprint).
  Stream<List<ExpositorFisico>> watchDisponiveis(String orgId) {
    return _collection
        .where('orgId', isEqualTo: orgId)
        .where('status', isEqualTo: 'disponivel')
        .snapshots()
        .map((snap) => snap.docs
        .map((d) => ExpositorFisico.fromFirestore(d.id, d.data()))
        .toList());
  }

  /// Abreviação de 3 letras do nome do modelo pro código de inventário
  /// — "Grande" → "GRA", "Pequeno" → "PEQ".
  String _abreviarModelo(String modeloNome) {
    final letras = modeloNome
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z]'), '');
    if (letras.isEmpty) return 'EXP';
    return letras.length >= 3 ? letras.substring(0, 3) : letras.padRight(3, 'X');
  }

  /// Gera o próximo código de inventário no formato EXP-MOD-000 (ex:
  /// EXP-GRA-001), usando uma transação num contador dedicado por
  /// modelo+organização — evita colisão entre cadastros simultâneos.
  Future<String> _gerarProximoNumero(String orgId, String modeloNome) async {
    final abreviacao = _abreviarModelo(modeloNome);
    final counterRef = _firestore
        .collection(FirestoreCollections.counters)
        .doc('expositores_${abreviacao}_$orgId');

    final novoNumero = await _firestore.runTransaction<int>((transaction) async {
      final snapshot = await transaction.get(counterRef);
      final atual = (snapshot.data()?['seq'] as int?) ?? 0;
      final proximo = atual + 1;
      transaction.set(counterRef, {'seq': proximo});
      return proximo;
    });

    return 'EXP-$abreviacao-${novoNumero.toString().padLeft(3, '0')}';
  }

  Map<String, dynamic> _eventoMovimentacao({
    required String orgId,
    required String expositorId,
    required TipoMovimentacaoExpositor tipo,
    required String usuarioId,
    String? clienteAnteriorId,
    String? clienteNovoId,
    String? statusAnterior,
    required String statusNovo,
    String? origem,
    String? destino,
    String? observacao,
  }) {
    return {
      'orgId': orgId,
      'expositorId': expositorId,
      'tipo': tipoMovimentacaoParaString(tipo),
      'usuarioId': usuarioId,
      'clienteAnteriorId': clienteAnteriorId,
      'clienteNovoId': clienteNovoId,
      'statusAnterior': statusAnterior,
      'statusNovo': statusNovo,
      'origem': origem,
      'destino': destino,
      'observacao': observacao,
      'timestamp': FieldValue.serverTimestamp(),
    };
  }

  Future<String> create({
    required String orgId,
    required String modeloId,
    required String modeloNome,
    required String usuarioId,
    String? numeroSerieFabricante,
    String? observacoes,
  }) async {
    final numero = await _gerarProximoNumero(orgId, modeloNome);
    final docRef = _collection.doc();
    final expositor = ExpositorFisico(
      orgId: orgId,
      numero: numero,
      modeloId: modeloId,
      modeloNome: modeloNome,
      numeroSerieFabricante: numeroSerieFabricante,
      observacoes: observacoes,
    );
    final data = expositor.toFirestore();
    data['createdAt'] = FieldValue.serverTimestamp();
    data['createdBy'] = usuarioId;

    final batch = _firestore.batch();
    batch.set(docRef, data);
    batch.set(
      _movimentacoes.doc(),
      _eventoMovimentacao(
        orgId: orgId,
        expositorId: docRef.id,
        tipo: TipoMovimentacaoExpositor.cadastro,
        usuarioId: usuarioId,
        statusNovo: 'disponivel',
        destino: LocalExpositor.central,
        observacao: observacoes,
      ),
    );
    await batch.commit();
    return numero;
  }

  /// Só pra mostrar uma prévia ("serão criados de EXP-GRA-003 até
  /// EXP-GRA-052") antes de confirmar o lote — não reserva nada, é só
  /// leitura. A garantia de verdade contra colisão é a transação
  /// dentro de createLote().
  Future<int> obterProximaSequencia(String orgId, String modeloNome) async {
    final abreviacao = _abreviarModelo(modeloNome);
    final doc = await _firestore
        .collection(FirestoreCollections.counters)
        .doc('expositores_${abreviacao}_$orgId')
        .get();
    return ((doc.data()?['seq'] as int?) ?? 0) + 1;
  }

  /// Cadastro em lote: cria várias unidades do mesmo modelo de uma vez
  /// (ex: 50 "Grande" viram EXP-GRA-001 até EXP-GRA-050). A reserva de
  /// toda a faixa de números acontece numa única transação no
  /// contador — evita dois lotes simultâneos colidindo em sequência.
  /// Limite de 200 por lote: cada unidade grava 2 operações (o
  /// expositor + o evento no histórico), ficando bem abaixo do máximo
  /// de 500 operações de um batch do Firestore.
  Future<List<String>> createLote({
    required String orgId,
    required String modeloId,
    required String modeloNome,
    required int quantidade,
    required String usuarioId,
  }) async {
    if (quantidade <= 0 || quantidade > 200) {
      throw ArgumentError('Quantidade precisa ser entre 1 e 200.');
    }

    final abreviacao = _abreviarModelo(modeloNome);
    final counterRef = _firestore
        .collection(FirestoreCollections.counters)
        .doc('expositores_${abreviacao}_$orgId');

    final numeroInicial = await _firestore.runTransaction<int>((transaction) async {
      final snapshot = await transaction.get(counterRef);
      final atual = (snapshot.data()?['seq'] as int?) ?? 0;
      transaction.set(counterRef, {'seq': atual + quantidade});
      return atual;
    });

    final batch = _firestore.batch();
    final numeros = <String>[];

    for (var i = 1; i <= quantidade; i++) {
      final seq = numeroInicial + i;
      final numero = 'EXP-$abreviacao-${seq.toString().padLeft(3, '0')}';
      numeros.add(numero);

      final docRef = _collection.doc();
      final expositor = ExpositorFisico(
        orgId: orgId,
        numero: numero,
        modeloId: modeloId,
        modeloNome: modeloNome,
      );
      final data = expositor.toFirestore();
      data['createdAt'] = FieldValue.serverTimestamp();
      data['createdBy'] = usuarioId;
      batch.set(docRef, data);

      batch.set(
        _movimentacoes.doc(),
        _eventoMovimentacao(
          orgId: orgId,
          expositorId: docRef.id,
          tipo: TipoMovimentacaoExpositor.cadastro,
          usuarioId: usuarioId,
          statusNovo: 'disponivel',
          destino: LocalExpositor.central,
          observacao: 'Cadastro em lote ($quantidade unidades).',
        ),
      );
    }

    await batch.commit();
    return numeros;
  }

  Future<void> atualizarStatus(
      String id,
      ExpositorStatus status, {
        required String usuarioId,
      }) {
    return _collection.doc(id).update({
      'status': _enumToString(status),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': usuarioId,
    });
  }

  /// Reserva uma unidade disponível para um cliente sem instalá-la.
  /// A instalação real acontece depois pela InstalacaoPage, que movimenta
  /// estoque, cria a consignação, finaliza a visita e só então chama
  /// confirmarInstalacao().
  Future<void> reservarParaCliente({
    required String expositorId,
    required String clienteId,
    required String usuarioId,
    String? observacao,
  }) async {
    final expositorRef = _collection.doc(expositorId);
    final clienteRef =
    _firestore.collection(FirestoreCollections.clientes).doc(clienteId);
    final eventoRef = _movimentacoes.doc();

    await _firestore.runTransaction((transaction) async {
      final expositorSnap = await transaction.get(expositorRef);
      if (!expositorSnap.exists) {
        throw Exception('Expositor não encontrado.');
      }

      final clienteSnap = await transaction.get(clienteRef);
      if (!clienteSnap.exists) {
        throw Exception('Cliente não encontrado.');
      }

      final expositor = ExpositorFisico.fromFirestore(
        expositorSnap.id,
        expositorSnap.data()!,
      );
      final clienteData = clienteSnap.data()!;

      if (expositor.status != ExpositorStatus.disponivel) {
        throw Exception(
          'Somente expositores disponíveis podem ser reservados.',
        );
      }

      if (expositor.clienteAtualId != null ||
          expositor.clienteReservadoId != null) {
        throw Exception(
          'Este expositor já possui vínculo com um cliente.',
        );
      }

      if (clienteData['orgId'] != expositor.orgId) {
        throw Exception(
          'Cliente e expositor pertencem a organizações diferentes.',
        );
      }

      if (clienteData['statusCadastro'] != 'aprovado') {
        throw Exception(
          'O cliente precisa estar aprovado antes de reservar um expositor.',
        );
      }

      transaction.update(expositorRef, {
        'status': _enumToString(ExpositorStatus.reservado),
        'clienteReservadoId': clienteId,
        'dataReserva': FieldValue.serverTimestamp(),
        'reservadoPor': usuarioId,
        'localAtual': LocalExpositor.central,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': usuarioId,
      });

      transaction.set(
        eventoRef,
        _eventoMovimentacao(
          orgId: expositor.orgId,
          expositorId: expositorId,
          tipo: TipoMovimentacaoExpositor.reserva,
          usuarioId: usuarioId,
          clienteAnteriorId: null,
          clienteNovoId: clienteId,
          statusAnterior: _enumToString(ExpositorStatus.disponivel),
          statusNovo: _enumToString(ExpositorStatus.reservado),
          origem: expositor.localAtual,
          destino: LocalExpositor.central,
          observacao: observacao,
        ),
      );
    });
  }

  /// Atribui o expositor a um cliente e marca como instalado — chamado
  /// na instalação inicial (seção 7.1 e 7.5 do Blueprint).
  Future<void> atribuirAoCliente({
    required String expositorId,
    required String clienteId,
    required String usuarioId,
  }) async {
    final docRef = _collection.doc(expositorId);
    final snapshot = await docRef.get();
    final anterior = snapshot.exists
        ? ExpositorFisico.fromFirestore(snapshot.id, snapshot.data()!)
        : null;

    final batch = _firestore.batch();
    batch.update(docRef, {
      'clienteAtualId': clienteId,
      'localAtual': LocalExpositor.cliente(clienteId),
      'status': _enumToString(ExpositorStatus.instalado),
      'dataInstalacao': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': usuarioId,
    });
    batch.set(
      _movimentacoes.doc(),
      _eventoMovimentacao(
        orgId: anterior?.orgId ?? '',
        expositorId: expositorId,
        tipo: TipoMovimentacaoExpositor.instalacao,
        usuarioId: usuarioId,
        clienteAnteriorId: anterior?.clienteAtualId,
        clienteNovoId: clienteId,
        statusAnterior:
        anterior != null ? _enumToString(anterior.status) : null,
        statusNovo: _enumToString(ExpositorStatus.instalado),
        origem: anterior?.localAtual,
        destino: LocalExpositor.cliente(clienteId),
      ),
    );
    await batch.commit();
  }

  /// Transfere o expositor direto de um cliente pra outro, sem passar
  /// por "disponível" no meio — ver seção 8 do documento de melhorias.
  /// Diferente de retirarDoCliente: aqui o expositor continua
  /// instalado o tempo todo, só troca de dono.
  Future<void> transferirParaCliente({
    required String expositorId,
    required String novoClienteId,
    required String usuarioId,
    String? observacao,
  }) async {
    final docRef = _collection.doc(expositorId);
    final snapshot = await docRef.get();
    final anterior = snapshot.exists
        ? ExpositorFisico.fromFirestore(snapshot.id, snapshot.data()!)
        : null;

    final batch = _firestore.batch();
    batch.update(docRef, {
      'clienteAtualId': novoClienteId,
      'localAtual': LocalExpositor.cliente(novoClienteId),
      'status': _enumToString(ExpositorStatus.instalado),
      'dataInstalacao': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': usuarioId,
    });
    batch.set(
      _movimentacoes.doc(),
      _eventoMovimentacao(
        orgId: anterior?.orgId ?? '',
        expositorId: expositorId,
        tipo: TipoMovimentacaoExpositor.transferencia,
        usuarioId: usuarioId,
        clienteAnteriorId: anterior?.clienteAtualId,
        clienteNovoId: novoClienteId,
        statusAnterior:
        anterior != null ? _enumToString(anterior.status) : null,
        statusNovo: _enumToString(ExpositorStatus.instalado),
        origem: anterior?.localAtual,
        destino: LocalExpositor.cliente(novoClienteId),
        observacao: observacao,
      ),
    );
    await batch.commit();
  }

  /// Retira o expositor do cliente atual, mandando pro destino
  /// escolhido — ver seção 7 do documento de melhorias. Sempre limpa
  /// o vínculo com o cliente; o que muda é o status/local final.
  Future<void> retirarDoCliente({
    required String expositorId,
    required DestinoRetirada destino,
    required String usuarioId,
    String? observacao,
    EstadoConservacao? estadoConservacao,
  }) async {
    final docRef = _collection.doc(expositorId);
    final snapshot = await docRef.get();
    final anterior = snapshot.exists
        ? ExpositorFisico.fromFirestore(snapshot.id, snapshot.data()!)
        : null;

    final novoStatus = switch (destino) {
      DestinoRetirada.estoque => ExpositorStatus.disponivel,
      DestinoRetirada.recolhido => ExpositorStatus.recolhido,
      DestinoRetirada.manutencao => ExpositorStatus.manutencao,
      DestinoRetirada.descarte => ExpositorStatus.descartado,
      DestinoRetirada.perdido => ExpositorStatus.perdido,
    };
    final novoLocal = destino == DestinoRetirada.manutencao
        ? LocalExpositor.manutencao
        : LocalExpositor.central;
    final tipoEvento = switch (destino) {
      DestinoRetirada.manutencao => TipoMovimentacaoExpositor.manutencaoEntrada,
      DestinoRetirada.descarte => TipoMovimentacaoExpositor.descarte,
      DestinoRetirada.perdido => TipoMovimentacaoExpositor.perda,
      _ => TipoMovimentacaoExpositor.retirada,
    };

    final batch = _firestore.batch();
    batch.update(docRef, {
      'clienteAtualId': null,
      'localAtual': novoLocal,
      'status': _enumToString(novoStatus),
      if (observacao != null && observacao.isNotEmpty) 'observacoes': observacao,
      if (estadoConservacao != null)
        'estadoConservacao': conservacaoParaString(estadoConservacao),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': usuarioId,
    });
    batch.set(
      _movimentacoes.doc(),
      _eventoMovimentacao(
        orgId: anterior?.orgId ?? '',
        expositorId: expositorId,
        tipo: tipoEvento,
        usuarioId: usuarioId,
        clienteAnteriorId: anterior?.clienteAtualId,
        clienteNovoId: null,
        statusAnterior:
        anterior != null ? _enumToString(anterior.status) : null,
        statusNovo: _enumToString(novoStatus),
        origem: anterior?.localAtual,
        destino: novoLocal,
        observacao: observacao,
      ),
    );
    await batch.commit();
  }

  /// Alteração administrativa de status para unidades que NÃO estão
  /// instaladas nem reservadas. Mantém as transições controladas e sempre
  /// grava um evento no histórico.
  ///
  /// Permitido:
  /// disponível -> manutenção / descartado / perdido
  /// recolhido  -> manutenção / descartado / perdido
  /// manutenção -> descartado / perdido
  Future<void> alterarStatusAdministrativo({
    required String expositorId,
    required ExpositorStatus novoStatus,
    required String usuarioId,
    required String observacao,
  }) async {
    final motivo = observacao.trim();

    if (motivo.isEmpty) {
      throw ArgumentError(
        'Informe o motivo da alteração de status.',
      );
    }

    if (novoStatus != ExpositorStatus.manutencao &&
        novoStatus != ExpositorStatus.descartado &&
        novoStatus != ExpositorStatus.perdido) {
      throw ArgumentError(
        'Status administrativo não permitido.',
      );
    }

    final expositorRef = _collection.doc(expositorId);
    final eventoRef = _movimentacoes.doc();

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(expositorRef);

      if (!snapshot.exists) {
        throw Exception('Expositor não encontrado.');
      }

      final atual = ExpositorFisico.fromFirestore(
        snapshot.id,
        snapshot.data()!,
      );

      final permitido = switch (atual.status) {
        ExpositorStatus.disponivel =>
        novoStatus == ExpositorStatus.manutencao ||
            novoStatus == ExpositorStatus.descartado ||
            novoStatus == ExpositorStatus.perdido,
        ExpositorStatus.recolhido =>
        novoStatus == ExpositorStatus.manutencao ||
            novoStatus == ExpositorStatus.descartado ||
            novoStatus == ExpositorStatus.perdido,
        ExpositorStatus.manutencao =>
        novoStatus == ExpositorStatus.descartado ||
            novoStatus == ExpositorStatus.perdido,
        _ => false,
      };

      if (!permitido) {
        throw Exception(
          'Não é permitido alterar ${_enumToString(atual.status)} '
              'diretamente para ${_enumToString(novoStatus)}.',
        );
      }

      final novoLocal = novoStatus == ExpositorStatus.manutencao
          ? LocalExpositor.manutencao
          : atual.localAtual;

      final tipoEvento = switch (novoStatus) {
        ExpositorStatus.manutencao =>
        TipoMovimentacaoExpositor.manutencaoEntrada,
        ExpositorStatus.descartado =>
        TipoMovimentacaoExpositor.descarte,
        ExpositorStatus.perdido =>
        TipoMovimentacaoExpositor.perda,
        _ => throw StateError('Status administrativo inválido.'),
      };

      transaction.update(expositorRef, {
        'status': _enumToString(novoStatus),
        'localAtual': novoLocal,
        'clienteAtualId': null,
        'observacoes': motivo,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': usuarioId,
      });

      transaction.set(
        eventoRef,
        _eventoMovimentacao(
          orgId: atual.orgId,
          expositorId: expositorId,
          tipo: tipoEvento,
          usuarioId: usuarioId,
          clienteAnteriorId: atual.clienteAtualId,
          clienteNovoId: null,
          statusAnterior: _enumToString(atual.status),
          statusNovo: _enumToString(novoStatus),
          origem: atual.localAtual,
          destino: novoLocal,
          observacao: motivo,
        ),
      );
    });
  }

  /// Finaliza a manutenção — volta pra "disponível" no estoque
  /// central. Ação principal quando o status é "manutenção" (item 7).
  Future<void> finalizarManutencao({
    required String expositorId,
    required String usuarioId,
    String? observacao,
  }) async {
    final docRef = _collection.doc(expositorId);
    final snapshot = await docRef.get();
    final anterior = snapshot.exists
        ? ExpositorFisico.fromFirestore(snapshot.id, snapshot.data()!)
        : null;

    final batch = _firestore.batch();
    batch.update(docRef, {
      'status': _enumToString(ExpositorStatus.disponivel),
      'localAtual': LocalExpositor.central,
      if (observacao != null && observacao.isNotEmpty) 'observacoes': observacao,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': usuarioId,
    });
    batch.set(
      _movimentacoes.doc(),
      _eventoMovimentacao(
        orgId: anterior?.orgId ?? '',
        expositorId: expositorId,
        tipo: TipoMovimentacaoExpositor.manutencaoSaida,
        usuarioId: usuarioId,
        statusAnterior: anterior != null ? _enumToString(anterior.status) : null,
        statusNovo: _enumToString(ExpositorStatus.disponivel),
        origem: anterior?.localAtual,
        destino: LocalExpositor.central,
        observacao: observacao,
      ),
    );
    await batch.commit();
  }

  /// Conferência pós-recolhimento — volta pra "disponível", já
  /// permitindo atualizar o estado de conservação encontrado na
  /// conferência. Ação principal quando o status é "recolhido".
  Future<void> confirmarDisponibilidadeAposConferencia({
    required String expositorId,
    required String usuarioId,
    EstadoConservacao? estadoConservacao,
    String? observacao,
  }) async {
    final docRef = _collection.doc(expositorId);
    final snapshot = await docRef.get();
    final anterior = snapshot.exists
        ? ExpositorFisico.fromFirestore(snapshot.id, snapshot.data()!)
        : null;

    final batch = _firestore.batch();
    batch.update(docRef, {
      'status': _enumToString(ExpositorStatus.disponivel),
      'localAtual': LocalExpositor.central,
      if (estadoConservacao != null)
        'estadoConservacao': conservacaoParaString(estadoConservacao),
      if (observacao != null && observacao.isNotEmpty) 'observacoes': observacao,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': usuarioId,
    });
    batch.set(
      _movimentacoes.doc(),
      _eventoMovimentacao(
        orgId: anterior?.orgId ?? '',
        expositorId: expositorId,
        tipo: TipoMovimentacaoExpositor.conferencia,
        usuarioId: usuarioId,
        statusAnterior: anterior != null ? _enumToString(anterior.status) : null,
        statusNovo: _enumToString(ExpositorStatus.disponivel),
        origem: anterior?.localAtual,
        destino: LocalExpositor.central,
        observacao: observacao,
      ),
    );
    await batch.commit();
  }

  /// Cancela uma reserva sem que o cliente tenha sido reprovado —
  /// usado quando o admin/estoque decide manualmente liberar a
  /// unidade (ex: cliente desistiu, mudou de ideia sobre o modelo).
  /// Não mexe no cadastro do cliente, só no expositor.
  Future<void> cancelarReserva({
    required String expositorId,
    required String usuarioId,
  }) async {
    final docRef = _collection.doc(expositorId);
    final snapshot = await docRef.get();
    if (!snapshot.exists) throw Exception('Expositor não encontrado.');
    final expositor = ExpositorFisico.fromFirestore(snapshot.id, snapshot.data()!);

    if (expositor.status != ExpositorStatus.reservado) {
      throw Exception('Este expositor não está reservado.');
    }

    final batch = _firestore.batch();
    batch.update(docRef, {
      'status': _enumToString(ExpositorStatus.disponivel),
      'clienteReservadoId': null,
      'dataReserva': null,
      'reservadoPor': null,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': usuarioId,
    });
    batch.set(
      _movimentacoes.doc(),
      _eventoMovimentacao(
        orgId: expositor.orgId,
        expositorId: expositorId,
        tipo: TipoMovimentacaoExpositor.cancelamentoReserva,
        usuarioId: usuarioId,
        clienteAnteriorId: expositor.clienteReservadoId,
        clienteNovoId: null,
        statusAnterior: _enumToString(ExpositorStatus.reservado),
        statusNovo: _enumToString(ExpositorStatus.disponivel),
        origem: expositor.localAtual,
        destino: expositor.localAtual,
        observacao: 'Reserva cancelada manualmente.',
      ),
    );
    await batch.commit();
  }

  /// Confirma a instalação de um expositor RESERVADO — transacional:
  /// valida que a reserva pertence mesmo a esse cliente antes de
  /// instalar, e já atualiza o cliente pra "ativo" na mesma transação
  /// (cruza pra coleção de clientes de propósito, pra garantir que os
  /// dois lados nunca fiquem dessincronizados). Ver plano de reserva
  /// de expositor, seção 7.
  Future<void> confirmarInstalacao({
    required String expositorId,
    required String clienteId,
    required String usuarioId,
  }) async {
    final expositorRef = _collection.doc(expositorId);
    final clienteRef =
    _firestore.collection(FirestoreCollections.clientes).doc(clienteId);

    await _firestore.runTransaction((transaction) async {
      final expositorSnap = await transaction.get(expositorRef);
      if (!expositorSnap.exists) {
        throw Exception('Expositor não encontrado.');
      }
      final expositor =
      ExpositorFisico.fromFirestore(expositorSnap.id, expositorSnap.data()!);

      if (expositor.status != ExpositorStatus.reservado ||
          expositor.clienteReservadoId != clienteId) {
        throw Exception(
            'Este expositor não está mais reservado para esse cliente.');
      }

      transaction.update(expositorRef, {
        'clienteAtualId': clienteId,
        'clienteReservadoId': null,
        'dataReserva': null,
        'reservadoPor': null,
        'localAtual': LocalExpositor.cliente(clienteId),
        'status': _enumToString(ExpositorStatus.instalado),
        'dataInstalacao': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': usuarioId,
      });

      transaction.update(clienteRef, {
        'statusOperacional': 'ativo',
      });

      transaction.set(
        _movimentacoes.doc(),
        _eventoMovimentacao(
          orgId: expositor.orgId,
          expositorId: expositorId,
          tipo: TipoMovimentacaoExpositor.instalacao,
          usuarioId: usuarioId,
          clienteAnteriorId: null,
          clienteNovoId: clienteId,
          statusAnterior: _enumToString(ExpositorStatus.reservado),
          statusNovo: _enumToString(ExpositorStatus.instalado),
          origem: expositor.localAtual,
          destino: LocalExpositor.cliente(clienteId),
        ),
      );
    });
  }
}

String _enumToString(Object enumValue) => enumValue.toString().split('.').last;
