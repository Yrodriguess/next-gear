import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../../core/constants/firestore_collections.dart';
import '../../expositores/domain/expositor_fisico.dart';
import '../../expositores/domain/expositor_movimentacao.dart';
import '../domain/cliente.dart';

class CpfCnpjDuplicadoException implements Exception {
  final String cpfCnpj;
  CpfCnpjDuplicadoException(this.cpfCnpj);

  @override
  String toString() => 'Já existe um cliente cadastrado com o documento $cpfCnpj.';
}

/// Lançada quando a unidade escolhida não pode mais ser reservada —
/// já foi pega por outro vendedor, não existe, ou é de outra
/// organização. A mensagem já vem pronta pra mostrar na tela.
class ExpositorIndisponivelException implements Exception {
  final String mensagem;
  ExpositorIndisponivelException(this.mensagem);

  @override
  String toString() => mensagem;
}

class ClienteRepository {
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  ClienteRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(FirestoreCollections.clientes);

  CollectionReference<Map<String, dynamic>> get _expositores =>
      _firestore.collection(FirestoreCollections.expositoresFisicos);

  CollectionReference<Map<String, dynamic>> get _movimentacoesExpositor =>
      _firestore.collection(FirestoreCollections.expositorMovimentacoes);

  CollectionReference<Map<String, dynamic>> get _auditLogs =>
      _firestore.collection(FirestoreCollections.auditLogs);

  Reference _fotoFachadaRef(String orgId, String clienteId) =>
      _storage.ref().child('clientes/$orgId/$clienteId/fachada.jpg');

  Future<String> _salvarFotoFachada({
    required String orgId,
    required String clienteId,
    required Uint8List bytes,
  }) async {
    final referencia = _fotoFachadaRef(orgId, clienteId);
    await referencia.putData(
      bytes,
      SettableMetadata(
        contentType: 'image/jpeg',
        cacheControl: 'public,max-age=3600',
      ),
    );
    return referencia.getDownloadURL();
  }

  Future<void> _removerFotoSilenciosamente(
      String orgId, String clienteId) async {
    try {
      await _fotoFachadaRef(orgId, clienteId).delete();
    } catch (_) {
      // Limpeza de compensação: não pode esconder o erro principal.
    }
  }

  /// Documento de controle que garante CPF/CNPJ único por organização,
  /// inclusive para cadastros salvos como rascunho.
  DocumentReference<Map<String, dynamic>> _controleCpfCnpjRef(
      String orgId, String cpfCnpjLimpo) {
    return _firestore
        .collection(FirestoreCollections.clienteCpfCnpjControle)
        .doc('${orgId}_$cpfCnpjLimpo');
  }

  /// Lista todos os clientes da organização, em tempo real.
  /// Mais pra frente, quando o volume crescer, isso precisa de paginação
  /// (ver seção 15.1 do Blueprint — telas rápidas, poucas consultas).
  Stream<List<Cliente>> watchAll(String orgId) {
    return _collection
        .where('orgId', isEqualTo: orgId)
        .orderBy('nome')
        .snapshots()
        .map((snap) =>
        snap.docs.map((d) => Cliente.fromFirestore(d.id, d.data())).toList());
  }

  Stream<Cliente?> watchById(String clienteId) {
    return _collection.doc(clienteId).snapshots().map(
            (doc) => doc.exists ? Cliente.fromFirestore(doc.id, doc.data()!) : null);
  }

  Future<Cliente?> fetchById(String clienteId) async {
    final doc = await _collection.doc(clienteId).get();
    if (!doc.exists) return null;
    return Cliente.fromFirestore(doc.id, doc.data()!);
  }

  /// Consulta preventiva usada pelo formulário. A transação feita durante
  /// a gravação continua sendo a garantia definitiva contra concorrência.
  Future<Cliente?> buscarPorCpfCnpj({
    required String orgId,
    required String cpfCnpj,
    String? ignorarClienteId,
  }) async {
    final cpfCnpjLimpo = _somenteDigitos(cpfCnpj);
    if (orgId.isEmpty || cpfCnpjLimpo.isEmpty) return null;

    // Cadastros feitos pela versão atual possuem uma trava determinística.
    // Consultá-la primeiro deixa a resposta rápida e também detecta um
    // documento que esteja sendo reservado por outro cadastro.
    final controle =
    await _controleCpfCnpjRef(orgId, cpfCnpjLimpo).get();
    if (controle.exists) {
      final clienteId = controle.data()?['clienteId'] as String?;
      if (clienteId != ignorarClienteId) {
        if (clienteId != null && clienteId.isNotEmpty) {
          final clienteDoc = await _collection.doc(clienteId).get();
          if (clienteDoc.exists) {
            return Cliente.fromFirestore(clienteDoc.id, clienteDoc.data()!);
          }
        }

        // Mesmo que o documento do cliente não tenha sido localizado, a
        // trava existente precisa ser tratada como ocupada. A transação de
        // salvamento também fará esse bloqueio.
        return Cliente.fromFirestore(
          clienteId ?? controle.id,
          {'orgId': orgId, 'cpfCnpj': cpfCnpjLimpo},
        );
      }
    }

    // Compatibilidade com clientes antigos, que podem ter sido gravados com
    // pontos, barra e traço no próprio campo cpfCnpj. Os cadastros novos são
    // sempre armazenados apenas com números.
    final formatosPossiveis = <String>{
      cpfCnpjLimpo,
      cpfCnpj.trim(),
      _formatarDocumentoLegado(cpfCnpjLimpo),
    }..removeWhere((valor) => valor.isEmpty);

    for (final formato in formatosPossiveis) {
      final resultado = await _collection
          .where('orgId', isEqualTo: orgId)
          .where('cpfCnpj', isEqualTo: formato)
          .limit(2)
          .get();

      for (final documento in resultado.docs) {
        if (documento.id != ignorarClienteId) {
          return Cliente.fromFirestore(documento.id, documento.data());
        }
      }
    }
    return null;
  }

  Future<void> _garantirSemCadastroExistente({
    required String orgId,
    required String cpfCnpj,
    String? ignorarClienteId,
  }) async {
    final existente = await buscarPorCpfCnpj(
      orgId: orgId,
      cpfCnpj: cpfCnpj,
      ignorarClienteId: ignorarClienteId,
    );
    if (existente != null) {
      throw CpfCnpjDuplicadoException(cpfCnpj);
    }
  }

  /// Salva sem enviar pra análise — fica em `rascunho`. O CPF/CNPJ é
  /// reservado desde este momento, mas o expositor indicado continua
  /// disponível até o envio para análise.
  ///
  /// [clienteIdExistente]: use ao continuar um rascunho ou corrigir um
  /// reprovado — grava por cima do MESMO documento em vez de criar um
  /// cliente novo. Sem isso, "Continuar cadastro" duplicaria o
  /// registro no Firestore.
  Future<String> salvarRascunho(
      Cliente cliente, {
        Uint8List? fotoFachadaBytes,
        String? clienteIdExistente,
      }) async {
    final cpfCnpjLimpo = _somenteDigitos(cliente.cpfCnpj);
    final documentoValido = cliente.tipoDocumento == TipoDocumento.pessoaJuridica
        ? _cnpjValido(cpfCnpjLimpo)
        : _cpfValido(cpfCnpjLimpo);
    if (!documentoValido) {
      throw ArgumentError('Informe um CPF ou CNPJ válido antes de salvar.');
    }

    await _garantirSemCadastroExistente(
      orgId: cliente.orgId,
      cpfCnpj: cpfCnpjLimpo,
      ignorarClienteId: clienteIdExistente,
    );

    final docRef = clienteIdExistente != null
        ? _collection.doc(clienteIdExistente)
        : _collection.doc();
    final novoControleRef =
    _controleCpfCnpjRef(cliente.orgId, cpfCnpjLimpo);

    String? fotoUrl = cliente.fotoFachadaUrl;
    var fotoEnviadaAgora = false;

    try {
      if (fotoFachadaBytes != null) {
        fotoUrl = await _salvarFotoFachada(
          orgId: cliente.orgId,
          clienteId: docRef.id,
          bytes: fotoFachadaBytes,
        );
        fotoEnviadaAgora = true;
      }

      await _firestore.runTransaction((transaction) async {
        Cliente? clienteAtual;
        if (clienteIdExistente != null) {
          final atualSnap = await transaction.get(docRef);
          if (!atualSnap.exists) {
            throw Exception(
                'O rascunho não foi encontrado. Atualize a lista e tente novamente.');
          }
          clienteAtual =
              Cliente.fromFirestore(atualSnap.id, atualSnap.data()!);
          if (clienteAtual.orgId != cliente.orgId) {
            throw Exception('Este rascunho não pertence à sua organização.');
          }
          if (clienteAtual.statusCadastro != StatusCadastro.rascunho &&
              clienteAtual.statusCadastro != StatusCadastro.reprovado) {
            throw Exception(
                'Esse cadastro não está mais em rascunho ou reprovado — atualize a página e tente novamente.');
          }
        }

        final novoControleSnap = await transaction.get(novoControleRef);
        final documentoAntigo =
        clienteAtual == null ? '' : _somenteDigitos(clienteAtual.cpfCnpj);
        final controleAntigoRef = documentoAntigo.isNotEmpty &&
            documentoAntigo != cpfCnpjLimpo
            ? _controleCpfCnpjRef(cliente.orgId, documentoAntigo)
            : null;
        final controleAntigoSnap = controleAntigoRef == null
            ? null
            : await transaction.get(controleAntigoRef);

        if (novoControleSnap.exists &&
            novoControleSnap.data()?['clienteId'] != docRef.id) {
          throw CpfCnpjDuplicadoException(cpfCnpjLimpo);
        }

        final controleAntigoEhDoCliente = controleAntigoSnap != null &&
            controleAntigoSnap.exists &&
            controleAntigoSnap.data()?['clienteId'] == docRef.id;
        if (controleAntigoRef != null && controleAntigoEhDoCliente) {
          transaction.delete(controleAntigoRef);
        }

        transaction.set(novoControleRef, {
          'orgId': cliente.orgId,
          'cpfCnpj': cpfCnpjLimpo,
          'clienteId': docRef.id,
          'statusCadastro': _enumToStringPublic(StatusCadastro.rascunho),
          'criadoEm': FieldValue.serverTimestamp(),
        });
        transaction.set(
          docRef,
          cliente
              .copyWith(
            cpfCnpj: cpfCnpjLimpo,
            fotoFachadaUrl: fotoUrl,
            statusCadastro: StatusCadastro.rascunho,
            statusOperacional: StatusOperacional.pendente,
          )
              .toFirestore(),
        );
      });
      return docRef.id;
    } catch (_) {
      if (fotoEnviadaAgora) {
        await _removerFotoSilenciosamente(cliente.orgId, docRef.id);
      }
      rethrow;
    }
  }

  /// O coração da correção de reserva: cria o cliente E reserva o
  /// expositor físico escolhido, tudo numa única transação — dois
  /// vendedores não conseguem reservar a mesma unidade, e o CPF/CNPJ
  /// não pode ser duplicado por corrida entre dois cadastros
  /// simultâneos.
  ///
  /// [clienteIdExistente]: use ao reenviar um rascunho ou corrigir um
  /// reprovado — grava por cima do MESMO documento em vez de criar um
  /// cliente novo (senão o rascunho original ficaria órfão). Também
  /// trata a trava de CPF/CNPJ desse MESMO cliente como válida (não
  /// duplicidade) — importante porque reprovar() nunca libera essa
  /// trava, só a do expositor; sem esse tratamento, reenviar o próprio
  /// cliente reprovado seria barrado como "documento duplicado".
  Future<String> enviarParaAnaliseComExpositor({
    required Cliente cliente,
    required String expositorFisicoId,
    required String usuarioId,
    Uint8List? fotoFachadaBytes,
    String? clienteIdExistente,
  }) async {
    final cpfCnpjLimpo = _somenteDigitos(cliente.cpfCnpj);
    final documentoValido = cliente.tipoDocumento == TipoDocumento.pessoaJuridica
        ? _cnpjValido(cpfCnpjLimpo)
        : _cpfValido(cpfCnpjLimpo);
    if (!documentoValido) {
      throw ArgumentError('Informe um CPF ou CNPJ válido antes de enviar.');
    }

    await _garantirSemCadastroExistente(
      orgId: cliente.orgId,
      cpfCnpj: cpfCnpjLimpo,
      ignorarClienteId: clienteIdExistente,
    );

    final controleRef = _controleCpfCnpjRef(cliente.orgId, cpfCnpjLimpo);
    final expositorRef = _expositores.doc(expositorFisicoId);
    final clienteRef = clienteIdExistente != null
        ? _collection.doc(clienteIdExistente)
        : _collection.doc();
    final movRef = _movimentacoesExpositor.doc();

    String? fotoUrl = cliente.fotoFachadaUrl;
    var fotoEnviadaAgora = false;

    if (fotoFachadaBytes != null) {
      fotoUrl = await _salvarFotoFachada(
        orgId: cliente.orgId,
        clienteId: clienteRef.id,
        bytes: fotoFachadaBytes,
      );
      fotoEnviadaAgora = true;
    }

    try {
      await _firestore.runTransaction((transaction) async {
        // Todas as leituras primeiro — regra do Firestore pra transação.
        Cliente? clienteAtual;
        if (clienteIdExistente != null) {
          final atualSnap = await transaction.get(clienteRef);
          if (!atualSnap.exists) {
            throw Exception(
                'O cadastro não foi encontrado. Atualize a lista e tente novamente.');
          }
          clienteAtual =
              Cliente.fromFirestore(atualSnap.id, atualSnap.data()!);
          if (clienteAtual.orgId != cliente.orgId) {
            throw Exception('Este cadastro não pertence à sua organização.');
          }
          if (clienteAtual.statusCadastro != StatusCadastro.rascunho &&
              clienteAtual.statusCadastro != StatusCadastro.reprovado) {
            throw Exception(
                'Esse cadastro já não está mais em rascunho/reprovado — atualize a página e tente novamente.');
          }
        }

        final controleSnap = await transaction.get(controleRef);
        final documentoAntigo =
        clienteAtual == null ? '' : _somenteDigitos(clienteAtual.cpfCnpj);
        final controleAntigoRef = documentoAntigo.isNotEmpty &&
            documentoAntigo != cpfCnpjLimpo
            ? _controleCpfCnpjRef(cliente.orgId, documentoAntigo)
            : null;
        final controleAntigoSnap = controleAntigoRef == null
            ? null
            : await transaction.get(controleAntigoRef);
        if (controleSnap.exists) {
          final donoAtualId = controleSnap.data()?['clienteId'] as String?;
          final ehOMesmoCliente =
              clienteIdExistente != null && donoAtualId == clienteIdExistente;
          if (!ehOMesmoCliente) {
            throw CpfCnpjDuplicadoException(cliente.cpfCnpj);
          }
          // É o próprio cliente renovando o envio (ex: reprovado
          // corrigindo e reenviando) — não é duplicidade de verdade.
        }

        final expositorSnap = await transaction.get(expositorRef);
        if (!expositorSnap.exists) {
          throw ExpositorIndisponivelException(
              'O expositor selecionado não foi encontrado.');
        }
        final expositor =
        ExpositorFisico.fromFirestore(expositorSnap.id, expositorSnap.data()!);
        if (expositor.orgId != cliente.orgId) {
          throw ExpositorIndisponivelException(
              'O expositor selecionado não pertence à sua organização.');
        }
        if (expositor.status != ExpositorStatus.disponivel) {
          throw ExpositorIndisponivelException(
              'O expositor ${expositor.numero} não está mais disponível. '
                  'Selecione outra unidade.');
        }

        // Agora as escritas.
        final controleAntigoEhDoCliente = controleAntigoSnap != null &&
            controleAntigoSnap.exists &&
            controleAntigoSnap.data()?['clienteId'] == clienteRef.id;
        if (controleAntigoRef != null && controleAntigoEhDoCliente) {
          transaction.delete(controleAntigoRef);
        }

        transaction.set(controleRef, {
          'orgId': cliente.orgId,
          'cpfCnpj': cpfCnpjLimpo,
          'clienteId': clienteRef.id,
          'statusCadastro': _enumToStringPublic(StatusCadastro.emAnalise),
          'criadoEm': FieldValue.serverTimestamp(),
        });

        final clienteData = cliente
            .copyWith(
          fotoFachadaUrl: fotoUrl,
          statusCadastro: StatusCadastro.emAnalise,
          statusOperacional: StatusOperacional.pendente,
          expositorFisicoSelecionadoId: expositorFisicoId,
        )
            .toFirestore();
        transaction.set(clienteRef, clienteData);

        transaction.update(expositorRef, {
          'status': _enumToStringPublic(ExpositorStatus.reservado),
          'clienteReservadoId': clienteRef.id,
          'dataReserva': FieldValue.serverTimestamp(),
          'reservadoPor': usuarioId,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': usuarioId,
        });

        transaction.set(movRef, {
          'orgId': cliente.orgId,
          'expositorId': expositorFisicoId,
          'tipo': tipoMovimentacaoParaString(TipoMovimentacaoExpositor.reserva),
          'usuarioId': usuarioId,
          'clienteAnteriorId': null,
          'clienteNovoId': clienteRef.id,
          'statusAnterior': _enumToStringPublic(ExpositorStatus.disponivel),
          'statusNovo': _enumToStringPublic(ExpositorStatus.reservado),
          'origem': expositor.localAtual,
          'destino': expositor.localAtual,
          'observacao': 'Reservado no cadastro do cliente.',
          'timestamp': FieldValue.serverTimestamp(),
        });
      });
    } catch (_) {
      if (fotoEnviadaAgora) {
        await _removerFotoSilenciosamente(cliente.orgId, clienteRef.id);
      }
      rethrow;
    }

    return clienteRef.id;
  }

  /// Atualiza somente a fachada. O caminho é estável, então uma nova foto
  /// substitui a anterior sem acumular arquivos órfãos no Storage.
  Future<String> atualizarFotoFachada({
    required String clienteId,
    required String orgId,
    required Uint8List bytes,
  }) async {
    final url = await _salvarFotoFachada(
      orgId: orgId,
      clienteId: clienteId,
      bytes: bytes,
    );
    await _collection.doc(clienteId).update({'fotoFachadaUrl': url});
    return url;
  }

  Future<void> update(String clienteId, Cliente cliente) {
    return _collection.doc(clienteId).update(cliente.toFirestore());
  }

  /// Edita dados cadastrais (endereço, contato, prazo de acerto etc.)
  /// depois que o cliente já está aprovado — diferente do formulário
  /// de cadastro, isso NUNCA mexe em status, comissão, expositor ou
  /// limite. Só os campos que realmente podem mudar no dia a dia.
  Future<List<String>> editarDados({
    required String clienteId,
    required String orgId,
    required String usuarioId,
    required String usuarioNome,
    required String usuarioPerfil,
    required String nome,
    String? nomeFantasia,
    required String cep,
    required String logradouro,
    required String numero,
    String? complemento,
    required String bairro,
    required String cidade,
    required String uf,
    required String nomeResponsavel,
    required String telefoneResponsavel,
    String? emailResponsavel,
    required int prazoAcertoDias,
    String? localizacaoMapsUrl,
    String? observacoesOperacionais,
    int? frequenciaVisitaDiasPadrao,
    PeriodoPreferencialVisita? periodoPreferencialVisita,
    AntecedenciaAvisoVisita? antecedenciaAvisoVisita,
  }) async {
    final dados = <String, dynamic>{
      'nome': nome,
      'nomeFantasia': nomeFantasia,
      'cep': cep,
      'logradouro': logradouro,
      'numero': numero,
      'complemento': complemento,
      'bairro': bairro,
      'cidade': cidade,
      'uf': uf,
      'nomeResponsavel': nomeResponsavel,
      'telefoneResponsavel': telefoneResponsavel,
      'emailResponsavel': emailResponsavel,
      'prazoAcertoDias': prazoAcertoDias,
      'localizacaoMapsUrl': localizacaoMapsUrl,
      'observacoesOperacionais': observacoesOperacionais,
      if (frequenciaVisitaDiasPadrao != null)
        'frequenciaVisitaDiasPadrao': frequenciaVisitaDiasPadrao,
      if (periodoPreferencialVisita != null)
        'periodoPreferencialVisita':
        _enumToStringPublic(periodoPreferencialVisita),
      if (antecedenciaAvisoVisita != null)
        'antecedenciaAvisoVisita':
        _enumToStringPublic(antecedenciaAvisoVisita),
    };

    final clienteRef = _collection.doc(clienteId);
    final auditRef = _auditLogs.doc();

    return _firestore.runTransaction<List<String>>((transaction) async {
      final clienteSnap = await transaction.get(clienteRef);
      if (!clienteSnap.exists) {
        throw Exception('Cliente não encontrado.');
      }

      final dadosAtuais = clienteSnap.data()!;
      if (dadosAtuais['orgId'] != orgId) {
        throw Exception('Este cliente não pertence à sua organização.');
      }

      final alteracoes = <String, Map<String, dynamic>>{};
      for (final campo in dados.entries) {
        final valorAnterior = dadosAtuais[campo.key];
        if (valorAnterior != campo.value) {
          alteracoes[campo.key] = {
            'anterior': valorAnterior,
            'novo': campo.value,
          };
        }
      }

      if (alteracoes.isEmpty) return const <String>[];

      transaction.update(clienteRef, {
        ...dados,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': usuarioId,
      });
      transaction.set(auditRef, {
        'orgId': orgId,
        'entidade': 'cliente',
        'entidadeId': clienteId,
        'acao': 'dados_cadastrais_editados',
        'usuarioId': usuarioId,
        'usuarioNome': usuarioNome,
        'usuarioPerfil': usuarioPerfil,
        'camposAlterados': alteracoes.keys.toList(),
        'alteracoes': alteracoes,
        'criadoEm': FieldValue.serverTimestamp(),
      });

      return alteracoes.keys.toList(growable: false);
    });
  }

  /// Ajusta a comissão a qualquer momento, mesmo com o cliente já
  /// aprovado — diferente da comissão proposta no cadastro, essa é a
  /// que entra nos cálculos de consignação daqui pra frente. Ciclos já
  /// fechados não mudam (o valor deles já está congelado no
  /// documento), só as próximas consignações usam o valor novo.
  Future<void> ajustarComissao({
    required String clienteId,
    required int novaComissaoBasisPoints,
  }) {
    if (novaComissaoBasisPoints < 0 || novaComissaoBasisPoints > 10000) {
      throw ArgumentError('Comissão precisa estar entre 0% e 100%.');
    }
    return _collection.doc(clienteId).update({
      'comissaoBasisPoints': novaComissaoBasisPoints,
    });
  }

  /// Ajusta o limite de crédito depois que o cliente já foi aprovado.
  /// O limite nunca pode ser negativo.
  Future<void> ajustarLimiteCredito({
    required String clienteId,
    required int novoLimiteCentavos,
  }) async {
    if (novoLimiteCentavos < 0) {
      throw ArgumentError(
        'O limite de crédito não pode ser negativo.',
      );
    }

    final clienteRef = _collection.doc(clienteId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(clienteRef);

      if (!snapshot.exists) {
        throw Exception('Cliente não encontrado.');
      }

      final cliente = Cliente.fromFirestore(
        snapshot.id,
        snapshot.data()!,
      );

      if (cliente.statusCadastro != StatusCadastro.aprovado) {
        throw Exception(
          'O limite só pode ser alterado após a aprovação do cliente.',
        );
      }

      transaction.update(clienteRef, {
        'limiteCreditoCentavos': novoLimiteCentavos,
      });
    });
  }

  /// Define/ajusta a data da próxima visita — sempre editável na mão,
  /// sobrescreve qualquer sugestão automática anterior.
  Future<void> definirProximaVisita({
    required String clienteId,
    required DateTime data,
  }) {
    return _collection.doc(clienteId).update({
      'proximaVisitaEm': Timestamp.fromDate(data),
    });
  }

  /// Ajusta de quanto em quanto tempo o sistema sugere visitar esse
  /// cliente por padrão — cada loja vende num ritmo diferente.
  Future<void> ajustarFrequenciaVisita({
    required String clienteId,
    required int dias,
  }) {
    if (dias <= 0) {
      throw ArgumentError('A frequência precisa ser maior que zero.');
    }
    return _collection.doc(clienteId).update({
      'frequenciaVisitaDiasPadrao': dias,
    });
  }

  /// Chamado ao finalizar uma visita (instalação ou reposição) —
  /// sugere a próxima data como "hoje + frequência do cliente", sem
  /// travar nada: o vendedor/financeiro pode sobrescrever a qualquer
  /// momento com definirProximaVisita. Versão simples por enquanto —
  /// calcular a partir da média real de vendas de cada cliente é
  /// trabalho futuro (precisa consultar o histórico de visitas).
  Future<void> sugerirProximaVisitaAposFinalizar({
    required String clienteId,
    required int frequenciaVisitaDiasPadrao,
  }) {
    final sugestao = DateTime.now().add(Duration(days: frequenciaVisitaDiasPadrao));
    return _collection.doc(clienteId).update({
      'proximaVisitaEm': Timestamp.fromDate(sugestao),
    });
  }

  /// Encerra operacionalmente o cliente quando a retirada fechou a
  /// ÚLTIMA consignação ativa. O cadastro continua aprovado e todo o
  /// histórico permanece preservado; apenas a operação corrente é encerrada.
  Future<void> encerrarOperacaoAposUltimaRetirada({
    required String clienteId,
    required String usuarioId,
  }) async {
    final clienteRef = _collection.doc(clienteId);
    final auditRef = _auditLogs.doc();

    await _firestore.runTransaction((transaction) async {
      final clienteSnap = await transaction.get(clienteRef);

      if (!clienteSnap.exists) {
        throw Exception('Cliente não encontrado.');
      }

      final cliente =
      Cliente.fromFirestore(clienteSnap.id, clienteSnap.data()!);

      if (cliente.statusCadastro != StatusCadastro.aprovado) {
        throw Exception(
          'Somente cliente aprovado pode ser encerrado após retirada.',
        );
      }

      transaction.update(clienteRef, {
        'statusOperacional':
        _enumToStringPublic(StatusOperacional.encerrado),
        'expositorFisicoSelecionadoId': null,
        'proximaVisitaEm': null,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': usuarioId,
      });

      transaction.set(auditRef, {
        'orgId': cliente.orgId,
        'entidade': 'cliente',
        'entidadeId': clienteId,
        'acao': 'operacao_encerrada_apos_retirada',
        'usuarioId': usuarioId,
        'camposAlterados': [
          'statusOperacional',
          'expositorFisicoSelecionadoId',
          'proximaVisitaEm',
        ],
        'criadoEm': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Reativa um cliente aprovado que estava encerrado e reserva uma nova
  /// unidade física para uma futura instalação. Não cria outro cadastro,
  /// não apaga histórico e não exige nova aprovação financeira.
  Future<void> prepararNovaInstalacao({
    required String clienteId,
    required String expositorFisicoId,
    required String usuarioId,
  }) async {
    final clienteRef = _collection.doc(clienteId);
    final expositorRef = _expositores.doc(expositorFisicoId);
    final movRef = _movimentacoesExpositor.doc();
    final auditRef = _auditLogs.doc();

    await _firestore.runTransaction((transaction) async {
      // Todas as leituras vêm antes das escritas.
      final clienteSnap = await transaction.get(clienteRef);
      final expositorSnap = await transaction.get(expositorRef);

      if (!clienteSnap.exists) {
        throw Exception('Cliente não encontrado.');
      }

      if (!expositorSnap.exists) {
        throw ExpositorIndisponivelException(
          'O expositor selecionado não foi encontrado.',
        );
      }

      final cliente =
      Cliente.fromFirestore(clienteSnap.id, clienteSnap.data()!);
      final expositor = ExpositorFisico.fromFirestore(
        expositorSnap.id,
        expositorSnap.data()!,
      );

      if (cliente.statusCadastro != StatusCadastro.aprovado) {
        throw Exception(
          'O cliente precisa estar aprovado para uma nova instalação.',
        );
      }

      if (cliente.statusOperacional != StatusOperacional.encerrado) {
        throw Exception(
          'A nova instalação só pode ser preparada para cliente encerrado.',
        );
      }

      if (cliente.statusFinanceiro == StatusFinanceiro.bloqueado) {
        throw Exception(
          'O cliente está bloqueado financeiramente. '
              'Regularize antes de reservar um novo expositor.',
        );
      }

      if (expositor.orgId != cliente.orgId) {
        throw ExpositorIndisponivelException(
          'O expositor selecionado não pertence à organização do cliente.',
        );
      }

      if (expositor.status != ExpositorStatus.disponivel) {
        throw ExpositorIndisponivelException(
          'O expositor ${expositor.numero} não está mais disponível. '
              'Selecione outra unidade.',
        );
      }

      transaction.update(clienteRef, {
        'statusOperacional':
        _enumToStringPublic(StatusOperacional.aguardandoInstalacao),
        'expositorFisicoSelecionadoId': expositorFisicoId,
        'proximaVisitaEm': null,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': usuarioId,
      });

      transaction.update(expositorRef, {
        'status': _enumToStringPublic(ExpositorStatus.reservado),
        'clienteReservadoId': clienteId,
        'dataReserva': FieldValue.serverTimestamp(),
        'reservadoPor': usuarioId,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': usuarioId,
      });

      transaction.set(movRef, {
        'orgId': cliente.orgId,
        'expositorId': expositorFisicoId,
        'tipo':
        tipoMovimentacaoParaString(TipoMovimentacaoExpositor.reserva),
        'usuarioId': usuarioId,
        'clienteAnteriorId': null,
        'clienteNovoId': clienteId,
        'statusAnterior':
        _enumToStringPublic(ExpositorStatus.disponivel),
        'statusNovo': _enumToStringPublic(ExpositorStatus.reservado),
        'origem': expositor.localAtual,
        'destino': expositor.localAtual,
        'observacao':
        'Reservado para nova instalação após encerramento anterior.',
        'timestamp': FieldValue.serverTimestamp(),
      });

      transaction.set(auditRef, {
        'orgId': cliente.orgId,
        'entidade': 'cliente',
        'entidadeId': clienteId,
        'acao': 'nova_instalacao_preparada',
        'usuarioId': usuarioId,
        'camposAlterados': [
          'statusOperacional',
          'expositorFisicoSelecionadoId',
        ],
        'expositorFisicoId': expositorFisicoId,
        'criadoEm': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Aprovação pelo financeiro/admin — ver seção 5.2. Transacional:
  /// confirma que o cliente está em análise e que a reserva do
  /// expositor (se houver) ainda é válida antes de aprovar. Não mexe
  /// no expositor — ele continua reservado até a instalação de
  /// verdade (confirmarInstalacao).
  Future<void> aprovar({
    required String clienteId,
    required int limiteCreditoCentavos,
    required int comissaoBasisPoints,
    required String usuarioId,
  }) async {
    final clienteRef = _collection.doc(clienteId);

    await _firestore.runTransaction((transaction) async {
      final clienteSnap = await transaction.get(clienteRef);
      if (!clienteSnap.exists) {
        throw Exception('Cliente não encontrado.');
      }
      final cliente = Cliente.fromFirestore(clienteSnap.id, clienteSnap.data()!);
      if (cliente.statusCadastro != StatusCadastro.emAnalise) {
        throw Exception('Só é possível aprovar um cliente em análise.');
      }

      if (cliente.expositorFisicoSelecionadoId != null) {
        final expositorRef =
        _expositores.doc(cliente.expositorFisicoSelecionadoId);
        final expositorSnap = await transaction.get(expositorRef);
        if (!expositorSnap.exists) {
          throw ExpositorIndisponivelException(
              'O expositor reservado não foi encontrado mais.');
        }
        final expositor =
        ExpositorFisico.fromFirestore(expositorSnap.id, expositorSnap.data()!);
        if (expositor.status != ExpositorStatus.reservado ||
            expositor.clienteReservadoId != clienteId) {
          throw ExpositorIndisponivelException(
              'A reserva desse expositor não é mais válida.');
        }
        // Continua reservado — só confirma que a reserva é real.
      }

      transaction.update(clienteRef, {
        'statusCadastro': _enumToStringPublic(StatusCadastro.aprovado),
        'statusOperacional': _enumToStringPublic(StatusOperacional.aguardandoInstalacao),
        'limiteCreditoCentavos': limiteCreditoCentavos,
        'comissaoBasisPoints': comissaoBasisPoints,
      });
    });
  }

  /// Reprovação — transacional: muda o cliente pra reprovado/encerrado
  /// e libera o expositor reservado (se a reserva ainda pertencer a
  /// esse cliente), registrando o cancelamento no histórico do
  /// expositor.
  Future<void> reprovar({
    required String clienteId,
    required String usuarioId,
    String? motivo,
  }) async {
    final clienteRef = _collection.doc(clienteId);

    await _firestore.runTransaction((transaction) async {
      final clienteSnap = await transaction.get(clienteRef);
      if (!clienteSnap.exists) {
        throw Exception('Cliente não encontrado.');
      }
      final cliente = Cliente.fromFirestore(clienteSnap.id, clienteSnap.data()!);
      if (cliente.statusCadastro != StatusCadastro.emAnalise) {
        throw Exception('Só é possível reprovar um cliente em análise.');
      }

      DocumentReference<Map<String, dynamic>>? expositorRef;
      ExpositorFisico? expositor;
      if (cliente.expositorFisicoSelecionadoId != null) {
        expositorRef = _expositores.doc(cliente.expositorFisicoSelecionadoId);
        final expositorSnap = await transaction.get(expositorRef);
        if (expositorSnap.exists) {
          expositor = ExpositorFisico.fromFirestore(
              expositorSnap.id, expositorSnap.data()!);
        }
      }

      transaction.update(clienteRef, {
        'statusCadastro': _enumToStringPublic(StatusCadastro.reprovado),
        'statusOperacional': _enumToStringPublic(StatusOperacional.encerrado),
      });

      if (expositor != null &&
          expositorRef != null &&
          expositor.status == ExpositorStatus.reservado &&
          expositor.clienteReservadoId == clienteId) {
        transaction.update(expositorRef, {
          'status': _enumToStringPublic(ExpositorStatus.disponivel),
          'clienteReservadoId': null,
          'dataReserva': null,
          'reservadoPor': null,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': usuarioId,
        });

        transaction.set(_movimentacoesExpositor.doc(), {
          'orgId': cliente.orgId,
          'expositorId': expositor.id,
          'tipo': tipoMovimentacaoParaString(
              TipoMovimentacaoExpositor.cancelamentoReserva),
          'usuarioId': usuarioId,
          'clienteAnteriorId': clienteId,
          'clienteNovoId': null,
          'statusAnterior': _enumToStringPublic(ExpositorStatus.reservado),
          'statusNovo': _enumToStringPublic(ExpositorStatus.disponivel),
          'origem': expositor.localAtual,
          'destino': expositor.localAtual,
          'observacao': motivo ?? 'Cliente reprovado — reserva liberada.',
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
    });
  }
}

String _enumToStringPublic(Object enumValue) => enumValue.toString().split('.').last;

String _somenteDigitos(String valor) =>
    valor.replaceAll(RegExp(r'[^0-9]'), '');

String _formatarDocumentoLegado(String digitos) {
  if (digitos.length == 11) {
    return '${digitos.substring(0, 3)}.'
        '${digitos.substring(3, 6)}.'
        '${digitos.substring(6, 9)}-'
        '${digitos.substring(9)}';
  }
  if (digitos.length == 14) {
    return '${digitos.substring(0, 2)}.'
        '${digitos.substring(2, 5)}.'
        '${digitos.substring(5, 8)}/'
        '${digitos.substring(8, 12)}-'
        '${digitos.substring(12)}';
  }
  return digitos;
}

bool _cpfValido(String entrada) {
  final cpf = _somenteDigitos(entrada);
  if (cpf.length != 11 || RegExp(r'^(\d)\1+$').hasMatch(cpf)) return false;

  int calcularDigito(int tamanho) {
    var soma = 0;
    for (var i = 0; i < tamanho; i++) {
      soma += int.parse(cpf[i]) * (tamanho + 1 - i);
    }
    final resto = (soma * 10) % 11;
    return resto == 10 ? 0 : resto;
  }

  return calcularDigito(9) == int.parse(cpf[9]) &&
      calcularDigito(10) == int.parse(cpf[10]);
}

bool _cnpjValido(String entrada) {
  final cnpj = _somenteDigitos(entrada);
  if (cnpj.length != 14 || RegExp(r'^(\d)\1+$').hasMatch(cnpj)) return false;

  int calcularDigito(String base, List<int> pesos) {
    var soma = 0;
    for (var i = 0; i < pesos.length; i++) {
      soma += int.parse(base[i]) * pesos[i];
    }
    final resto = soma % 11;
    return resto < 2 ? 0 : 11 - resto;
  }

  final primeiro = calcularDigito(
    cnpj.substring(0, 12),
    const [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2],
  );
  final segundo = calcularDigito(
    '${cnpj.substring(0, 12)}$primeiro',
    const [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2],
  );
  return cnpj.endsWith('$primeiro$segundo');
}
