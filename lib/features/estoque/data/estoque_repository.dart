import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_collections.dart';
import '../domain/estoque_saldo.dart';
import '../domain/stock_movement.dart';

class EstoqueInsuficienteException implements Exception {
  final String local;
  final int disponivel;
  final int solicitado;

  EstoqueInsuficienteException({
    required this.local,
    required this.disponivel,
    required this.solicitado,
  });

  @override
  String toString() =>
      'Estoque insuficiente em "$local": disponível $disponivel, solicitado $solicitado.';
}

class EstoqueRepository {
  final FirebaseFirestore _firestore;

  EstoqueRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _movimentacoes =>
      _firestore.collection(FirestoreCollections.estoqueMovimentacoes);

  CollectionReference<Map<String, dynamic>> get _saldos =>
      _firestore.collection(FirestoreCollections.estoqueSaldos);

  CollectionReference<Map<String, dynamic>> get _skus =>
      _firestore.collection(FirestoreCollections.skus);

  DocumentReference<Map<String, dynamic>> _saldoRef(
      String localId,
      String produtoId,
      ) =>
      _saldos.doc(
        EstoqueSaldo.idPara(localId, produtoId),
      );

  DocumentReference<Map<String, dynamic>> _skuRef(
      String skuId,
      ) =>
      _skus.doc(skuId);

  Stream<int> watchSaldo(
      String localId,
      String produtoId,
      ) {
    return _saldoRef(localId, produtoId).snapshots().map(
          (doc) => (doc.data()?['quantidade'] as int?) ?? 0,
    );
  }

  Future<int> obterSaldo(
      String localId,
      String produtoId,
      ) async {
    final doc =
    await _saldoRef(localId, produtoId).get();

    return (doc.data()?['quantidade'] as int?) ?? 0;
  }

  /// Todo saldo positivo de um local, restrito à organização do
  /// chamador.
  Stream<List<EstoqueSaldo>> watchSaldosDoLocal(
      String orgId,
      String localId,
      ) {
    return _saldos
        .where('orgId', isEqualTo: orgId)
        .where('localId', isEqualTo: localId)
        .where('quantidade', isGreaterThan: 0)
        .snapshots()
        .map(
          (snap) => snap.docs
          .map(
            (d) => EstoqueSaldo.fromFirestore(
          d.data(),
        ),
      )
          .toList(),
    );
  }

  /// Todos os saldos positivos da organização,
  /// independentemente do local.
  Stream<List<EstoqueSaldo>> watchSaldosDaOrganizacao(
      String orgId,
      ) {
    return _saldos
        .where('orgId', isEqualTo: orgId)
        .snapshots()
        .map(
          (snap) => snap.docs
          .map(
            (doc) => EstoqueSaldo.fromFirestore(
          doc.data(),
        ),
      )
          .where(
            (saldo) => saldo.quantidade > 0,
      )
          .toList(),
    );
  }

  Stream<List<StockMovement>> watchMovimentacoesDoProduto(
      String orgId,
      String produtoId,
      ) {
    return _movimentacoes
        .where('orgId', isEqualTo: orgId)
        .where('produtoId', isEqualTo: produtoId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
          .map(
            (d) => StockMovement.fromFirestore(
          d.id,
          d.data(),
        ),
      )
          .toList(),
    );
  }

  /// Existe pelo menos uma movimentação pra esse SKU?
  Future<bool> temMovimentacao(
      String orgId,
      String produtoId,
      ) async {
    final snap = await _movimentacoes
        .where('orgId', isEqualTo: orgId)
        .where('produtoId', isEqualTo: produtoId)
        .limit(1)
        .get();

    return snap.docs.isNotEmpty;
  }

  /// Todas as vendas apuradas da organização.
  Stream<List<StockMovement>> watchVendas(
      String orgId,
      ) {
    return _movimentacoes
        .where('orgId', isEqualTo: orgId)
        .where(
      'motivo',
      isEqualTo:
      motivoToString(MovimentoMotivo.vendaApurada),
    )
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
          .map(
            (d) => StockMovement.fromFirestore(
          d.id,
          d.data(),
        ),
      )
          .toList(),
    );
  }

  Future<void> registrarMovimento({
    required String orgId,
    required String produtoId,
    required int quantidade,
    required String origem,
    required String destino,
    required MovimentoMotivo motivo,
    required String usuarioId,
    int? custoUnitarioCentavosNoMomento,
    int? valorVendaCentavosNoMomento,
    int? comissaoCentavosNoMomento,
    String? observacao,
  }) async {
    if (quantidade <= 0) {
      throw ArgumentError(
        'A quantidade movimentada precisa ser maior que zero.',
      );
    }

    if (comissaoCentavosNoMomento != null &&
        comissaoCentavosNoMomento < 0) {
      throw ArgumentError(
        'A comissão da venda não pode ser negativa.',
      );
    }

    if (comissaoCentavosNoMomento != null &&
        valorVendaCentavosNoMomento != null &&
        comissaoCentavosNoMomento >
            valorVendaCentavosNoMomento) {
      throw ArgumentError(
        'A comissão não pode ser maior que o valor de venda unitário.',
      );
    }

    // Compra/entrada real de mercadoria.
    final ehEntradaFornecedor =
        motivo == MovimentoMotivo.entrada &&
            origem == LocalEstoque.fornecedor &&
            destino == LocalEstoque.central;

    if (ehEntradaFornecedor &&
        (custoUnitarioCentavosNoMomento == null ||
            custoUnitarioCentavosNoMomento <= 0)) {
      throw ArgumentError(
        'Informe o custo unitário da entrada.',
      );
    }

    EstoqueInsuficienteException? falha;

    await _firestore.runTransaction(
          (transaction) async {
        final origemEhLocalReal =
        LocalEstoque.ehLocalReal(origem);

        final destinoEhLocalReal =
        LocalEstoque.ehLocalReal(destino);

        // =====================================================
        // LEITURAS
        // =====================================================

        DocumentSnapshot<Map<String, dynamic>>?
        origemSnapshot;

        if (origemEhLocalReal) {
          origemSnapshot = await transaction.get(
            _saldoRef(
              origem,
              produtoId,
            ),
          );

          final saldoAtual =
              (origemSnapshot.data()?['quantidade']
              as int?) ??
                  0;

          if (saldoAtual < quantidade) {
            falha = EstoqueInsuficienteException(
              local: origem,
              disponivel: saldoAtual,
              solicitado: quantidade,
            );

            return;
          }
        }

        DocumentSnapshot<Map<String, dynamic>>?
        destinoSnapshot;

        if (destinoEhLocalReal) {
          destinoSnapshot =
          await transaction.get(
            _saldoRef(
              destino,
              produtoId,
            ),
          );
        }

        // produtoId neste repositório representa o SKU
        // movimentado.
        //
        // Lemos o SKU para manter a quantidade total física
        // e, quando for compra, atualizar os custos.
        final skuRef =
        _skuRef(produtoId);

        final skuSnapshot =
        await transaction.get(skuRef);

        final skuData =
        skuSnapshot.data();

        // Quantidade total pertencente à empresa,
        // independentemente de estar:
        //
        // - no estoque central;
        // - com vendedor;
        // - consignada no cliente.
        //
        // Transferências internas não alteram esse total.
        final quantidadeTotalAtual =
            (skuData?['quantidadeTotalEstoque']
            as int?) ??
                0;

        var novaQuantidadeTotal =
            quantidadeTotalAtual;

        // Entrada de fora da empresa.
        if (!origemEhLocalReal &&
            destinoEhLocalReal) {
          novaQuantidadeTotal =
              quantidadeTotalAtual +
                  quantidade;
        }

        // Saída definitiva da empresa:
        // venda, avaria, extravio etc.
        if (origemEhLocalReal &&
            !destinoEhLocalReal) {
          final calculado =
              quantidadeTotalAtual -
                  quantidade;

          novaQuantidadeTotal =
          calculado < 0
              ? 0
              : calculado;
        }

        // =====================================================
        // CUSTO MÉDIO
        // =====================================================

        int? novoCustoMedio;

        if (ehEntradaFornecedor) {
          final custoNovaCompra =
          custoUnitarioCentavosNoMomento!;

          final custoInicial =
              (skuData?['custoInicialCentavos']
              as int?) ??
                  custoNovaCompra;

          final custoMedioAtual =
              (skuData?['custoMedioCentavos']
              as int?) ??
                  custoInicial;

          if (quantidadeTotalAtual <= 0) {
            // Se não havia estoque, o novo custo médio
            // passa a ser o custo desta compra.
            novoCustoMedio =
                custoNovaCompra;
          } else {
            // Média ponderada:
            //
            // estoque atual × custo médio atual
            // +
            // nova quantidade × novo custo
            //
            // dividido pelo novo estoque total.
            final valorEstoqueAtual =
                quantidadeTotalAtual *
                    custoMedioAtual;

            final valorNovaEntrada =
                quantidade *
                    custoNovaCompra;

            final quantidadeAposEntrada =
                quantidadeTotalAtual +
                    quantidade;

            novoCustoMedio =
                ((valorEstoqueAtual +
                    valorNovaEntrada) /
                    quantidadeAposEntrada)
                    .round();
          }
        }

        // =====================================================
        // MOVIMENTAÇÃO
        // =====================================================

        final movRef =
        _movimentacoes.doc();

        transaction.set(
          movRef,
          {
            'orgId': orgId,
            'produtoId': produtoId,
            'quantidade': quantidade,
            'origem': origem,
            'destino': destino,
            'motivo':
            motivoToString(motivo),
            'usuarioId': usuarioId,
            'custoUnitarioCentavosNoMomento':
            custoUnitarioCentavosNoMomento,
            'valorVendaCentavosNoMomento':
            valorVendaCentavosNoMomento,
            'comissaoCentavosNoMomento':
            comissaoCentavosNoMomento,
            'observacao': observacao,
            'timestamp':
            FieldValue.serverTimestamp(),
          },
        );

        // =====================================================
        // SALDO DA ORIGEM
        // =====================================================

        if (origemEhLocalReal) {
          final saldoAtual =
              (origemSnapshot
                  ?.data()?['quantidade']
              as int?) ??
                  0;

          transaction.set(
            _saldoRef(
              origem,
              produtoId,
            ),
            {
              'orgId': orgId,
              'localId': origem,
              'produtoId': produtoId,
              'quantidade':
              saldoAtual -
                  quantidade,
            },
          );
        }

        // =====================================================
        // SALDO DO DESTINO
        // =====================================================

        if (destinoEhLocalReal) {
          final saldoAtual =
              (destinoSnapshot
                  ?.data()?['quantidade']
              as int?) ??
                  0;

          transaction.set(
            _saldoRef(
              destino,
              produtoId,
            ),
            {
              'orgId': orgId,
              'localId': destino,
              'produtoId': produtoId,
              'quantidade':
              saldoAtual +
                  quantidade,
            },
          );
        }

        // =====================================================
        // SKU / CUSTOS
        // =====================================================

        final alterouQuantidadeTotal =
            origemEhLocalReal !=
                destinoEhLocalReal;

        if (alterouQuantidadeTotal ||
            ehEntradaFornecedor) {
          final atualizacoes =
          <String, dynamic>{
            'quantidadeTotalEstoque':
            novaQuantidadeTotal,
          };

          if (ehEntradaFornecedor) {
            atualizacoes[
            'custoUltimaCompraCentavos'] =
                custoUnitarioCentavosNoMomento;

            atualizacoes[
            'custoMedioCentavos'] =
                novoCustoMedio;
          }

          transaction.update(
            skuRef,
            atualizacoes,
          );
        }
      },
    );

    if (falha != null) {
      throw falha!;
    }
  }
}