import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/barcode_scanner_page.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../clientes/domain/cliente.dart';
import '../../consignacoes/domain/consignment.dart';
import '../../estoque/data/estoque_repository.dart';
import '../../estoque/domain/stock_movement.dart';
import '../../estoque/presentation/estoque_providers.dart';
import '../../produtos/domain/sku.dart';
import '../../produtos/presentation/produto_providers.dart';
import '../domain/conferencia_item.dart';
import '../domain/visita_exceptions.dart';
import '../domain/visita_resultado.dart';
import 'visita_providers.dart';
import 'visita_resultado_page.dart';

String _classificacaoLabel(ClassificacaoDiferenca classificacao) =>
    switch (classificacao) {
      ClassificacaoDiferenca.vendido => 'Vendido',
      ClassificacaoDiferenca.avaria => 'Avaria',
      ClassificacaoDiferenca.extravio => 'Extravio',
      ClassificacaoDiferenca.devolvido => 'Devolvido',
      ClassificacaoDiferenca.erroDeEstoque => 'Erro de estoque',
      ClassificacaoDiferenca.outro => 'Outro',
    };

class VisitaExecucaoPage extends ConsumerStatefulWidget {
  final Cliente cliente;
  final Consignment consignmentAtiva;
  final String? visitaId;
  final DateTime? dataPrevista;

  const VisitaExecucaoPage({
    super.key,
    required this.cliente,
    required this.consignmentAtiva,
    this.visitaId,
    this.dataPrevista,
  });

  @override
  ConsumerState<VisitaExecucaoPage> createState() =>
      _VisitaExecucaoPageState();
}

class _VisitaExecucaoPageState extends ConsumerState<VisitaExecucaoPage> {
  late List<ConferenciaItem> _conferencia;
  final Map<String, int> _reposicao = {};
  final Set<String> _itensConferidos = {};
  final TextEditingController _buscaController = TextEditingController();
  Timer? _rascunhoTimer;

  int _etapa = 0;
  bool _somenteSelecionados = false;
  bool _isSaving = false;
  bool _liberarSaida = false;
  bool _dialogSaidaAberto = false;
  bool _rascunhoCarregado = false;
  bool _bloquearSalvamentoRascunho = false;
  String? _errorMessage;

  bool get _inadimplente =>
      widget.cliente.statusFinanceiro == StatusFinanceiro.bloqueado;

  int get _totalEsperado => _conferencia.fold<int>(
    0,
        (total, item) => total + item.quantidadeEsperada,
  );

  int get _totalEncontrado => _conferencia.fold<int>(
    0,
        (total, item) => total + item.quantidadeEncontrada,
  );

  int get _totalDiferenca => _conferencia.fold<int>(
    0,
        (total, item) => total + item.diferenca,
  );

  int get _totalVendido => _conferencia.fold<int>(
    0,
        (total, item) => total + item.quantidadeVendida,
  );

  int get _itensReposicaoSelecionados =>
      _reposicao.values.where((quantidade) => quantidade > 0).length;

  int get _totalUnidadesReposicao => _reposicao.values.fold<int>(
    0,
        (total, quantidade) =>
    total + (quantidade > 0 ? quantidade : 0),
  );

  bool get _conferenciaCompleta {
    if (_itensConferidos.length != _conferencia.length) return false;

    for (final item in _conferencia) {
      if (item.temDiferenca && item.classificacaoDiferenca == null) {
        return false;
      }
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    _conferencia = widget.consignmentAtiva.itens
        .map(
          (item) => ConferenciaItem(
        produtoId: item.produtoId,
        descricaoSnapshot: item.descricaoSnapshot,
        quantidadeEsperada: item.quantidade,
        quantidadeEncontrada: item.quantidade,
      ),
    )
        .toList();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _carregarRascunho();
    });
  }

  @override
  void dispose() {
    _rascunhoTimer?.cancel();
    _buscaController.dispose();
    super.dispose();
  }

  String _descricaoCompleta(Sku sku, String? descricaoProduto) {
    final nome = descricaoProduto ?? sku.codigoInterno;
    return sku.variacao != null ? '$nome — ${sku.variacao}' : nome;
  }

  String _normalizarGtinComparacao(String? valor) {
    final digitos = (valor ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (digitos.length == 12) return '0$digitos';
    return digitos;
  }

  int _saldoDisponivel(
      String skuId,
      Map<String, int> saldosVendedor,
      ) {
    final saldo = saldosVendedor[skuId] ?? 0;
    return saldo > 0 ? saldo : 0;
  }

  bool _reposicaoAcimaDoEstoque(
      Map<String, int> saldosVendedor,
      ) {
    for (final entry in _reposicao.entries) {
      if (entry.value <= 0) continue;
      if (entry.value > _saldoDisponivel(entry.key, saldosVendedor)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _escanearReposicao(
      List<Sku> skus,
      Map<String, int> saldosVendedor,
      ) async {
    final codigo = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerPage(),
      ),
    );

    if (codigo == null || !mounted) return;

    final gtinLido = _normalizarGtinComparacao(codigo);
    if (gtinLido.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Código de barras inválido.'),
        ),
      );
      return;
    }

    Sku? skuEncontrado;
    for (final sku in skus) {
      if (_normalizarGtinComparacao(sku.codigoBarras) == gtinLido) {
        skuEncontrado = sku;
        break;
      }
    }

    if (skuEncontrado == null || skuEncontrado.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Código de barras não encontrado no cadastro.'),
        ),
      );
      return;
    }

    final skuId = skuEncontrado.id!;
    final disponivel = _saldoDisponivel(skuId, saldosVendedor);
    final atual = _reposicao[skuId] ?? 0;

    if (disponivel <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Produto encontrado, mas sem estoque disponível na sua carga.',
          ),
        ),
      );
      return;
    }

    if (atual >= disponivel) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Quantidade máxima disponível na sua carga atingida '
                '($disponivel un.).',
          ),
        ),
      );
      return;
    }

    setState(() {
      _reposicao[skuId] = atual + 1;
      _somenteSelecionados = false;
      _buscaController.text = skuEncontrado!.codigoInterno;
      _buscaController.selection = TextSelection.collapsed(
        offset: _buscaController.text.length,
      );
      _errorMessage = null;
    });

    _agendarSalvarRascunho();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${skuEncontrado.codigoInterno}: '
              '${atual + 1} de $disponivel un. selecionada(s) para reposição.',
        ),
      ),
    );
  }

  Future<void> _carregarRascunho() async {
    final visitaId = widget.visitaId?.trim();

    if (visitaId == null || visitaId.isEmpty) {
      _rascunhoCarregado = true;
      return;
    }

    try {
      final rascunho = await ref
          .read(visitaRepositoryProvider)
          .carregarRascunhoExecucao(visitaId);

      if (!mounted) return;

      if (rascunho == null) {
        _rascunhoCarregado = true;
        return;
      }

      final conferenciaSalva = <String, ConferenciaItem>{};
      final conferenciaRaw = rascunho['conferencia'];

      if (conferenciaRaw is List) {
        for (final raw in conferenciaRaw) {
          if (raw is! Map) continue;

          final item = ConferenciaItem.fromMap(
            Map<String, dynamic>.from(raw),
          );

          if (item.produtoId.trim().isEmpty) continue;
          conferenciaSalva[item.produtoId] = item;
        }
      }

      final idsAtuais = _conferencia
          .map((item) => item.produtoId)
          .toSet();

      final conferidos = <String>{};
      final conferidosRaw = rascunho['itensConferidos'];

      if (conferidosRaw is List) {
        for (final raw in conferidosRaw) {
          if (raw is! String) continue;
          if (idsAtuais.contains(raw)) {
            conferidos.add(raw);
          }
        }
      }

      final reposicao = <String, int>{};
      final reposicaoRaw = rascunho['reposicao'];

      if (reposicaoRaw is Map) {
        reposicaoRaw.forEach((key, value) {
          if (key is! String || value is! num) return;

          final quantidade = value.toInt();
          if (quantidade <= 0) return;

          reposicao[key] = quantidade;
        });
      }

      var etapa = 0;
      final etapaRaw = rascunho['etapa'];

      if (etapaRaw is num) {
        etapa = etapaRaw.toInt().clamp(0, 2).toInt();
      }

      if (_inadimplente && etapa == 1) {
        etapa = 2;
      }

      setState(() {
        _conferencia = _conferencia.map((base) {
          final salvo = conferenciaSalva[base.produtoId];
          if (salvo == null) return base;

          final encontrada = salvo.quantidadeEncontrada
              .clamp(0, base.quantidadeEsperada)
              .toInt();

          final temDiferenca = encontrada != base.quantidadeEsperada;

          return ConferenciaItem(
            produtoId: base.produtoId,
            descricaoSnapshot: base.descricaoSnapshot,
            quantidadeEsperada: base.quantidadeEsperada,
            quantidadeEncontrada: encontrada,
            classificacaoDiferenca:
            temDiferenca ? salvo.classificacaoDiferenca : null,
            observacao: salvo.observacao,
          );
        }).toList();

        _itensConferidos
          ..clear()
          ..addAll(conferidos);

        for (final item in _conferencia) {
          if (item.temDiferenca && item.classificacaoDiferenca == null) {
            _itensConferidos.remove(item.produtoId);
          }
        }

        _reposicao
          ..clear()
          ..addAll(reposicao);

        _etapa = etapa;
        _errorMessage = null;
        _rascunhoCarregado = true;
      });
    } catch (error, stack) {
      debugPrint('Erro ao carregar rascunho da visita: $error\n$stack');

      if (mounted) {
        setState(() {
          _rascunhoCarregado = true;
        });
      }
    }
  }

  void _agendarSalvarRascunho() {
    if (!_rascunhoCarregado || _bloquearSalvamentoRascunho) {
      return;
    }

    final visitaId = widget.visitaId?.trim();
    if (visitaId == null || visitaId.isEmpty) {
      return;
    }

    _rascunhoTimer?.cancel();
    _rascunhoTimer = Timer(
      const Duration(milliseconds: 600),
          () {
        unawaited(_salvarRascunhoAgora());
      },
    );
  }

  Future<void> _salvarRascunhoAgora() async {
    if (_bloquearSalvamentoRascunho) {
      return;
    }

    final visitaId = widget.visitaId?.trim();
    if (visitaId == null || visitaId.isEmpty) {
      return;
    }

    _rascunhoTimer?.cancel();

    try {
      await ref.read(visitaRepositoryProvider).salvarRascunhoExecucao(
        visitaId: visitaId,
        conferencia: _conferencia.map((item) => item.toMap()).toList(),
        itensConferidos: _itensConferidos,
        reposicao: _reposicao,
        etapa: _etapa,
      );
    } catch (error, stack) {
      debugPrint('Erro ao salvar rascunho da visita: $error\n$stack');
    }
  }

  void _alterarQuantidadeEncontrada(
      ConferenciaItem item,
      int novaQuantidade,
      ) {
    final index = _conferencia.indexWhere(
          (atual) => atual.produtoId == item.produtoId,
    );
    if (index < 0) return;

    setState(() {
      _conferencia[index] = ConferenciaItem(
        produtoId: item.produtoId,
        descricaoSnapshot: item.descricaoSnapshot,
        quantidadeEsperada: item.quantidadeEsperada,
        quantidadeEncontrada:
        novaQuantidade.clamp(0, item.quantidadeEsperada).toInt(),
        classificacaoDiferenca: null,
        observacao: item.observacao,
      );
      _itensConferidos.remove(item.produtoId);
      _errorMessage = null;
    });

    _agendarSalvarRascunho();
  }

  void _alterarClassificacao(
      ConferenciaItem item,
      ClassificacaoDiferenca classificacao,
      ) {
    final index = _conferencia.indexWhere(
          (atual) => atual.produtoId == item.produtoId,
    );
    if (index < 0) return;

    setState(() {
      _conferencia[index] = ConferenciaItem(
        produtoId: item.produtoId,
        descricaoSnapshot: item.descricaoSnapshot,
        quantidadeEsperada: item.quantidadeEsperada,
        quantidadeEncontrada: item.quantidadeEncontrada,
        classificacaoDiferenca: classificacao,
        observacao: item.observacao,
      );
      _itensConferidos.remove(item.produtoId);
      _errorMessage = null;
    });

    _agendarSalvarRascunho();
  }

  void _confirmarItem(ConferenciaItem item) {
    if (item.temDiferenca && item.classificacaoDiferenca == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Classifique a diferença antes de confirmar este produto.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _itensConferidos.add(item.produtoId);
      _errorMessage = null;
    });

    _agendarSalvarRascunho();
  }

  Future<void> _confirmarTudo() async {
    final possuiAlteracao = _conferencia.any(
          (item) =>
      item.quantidadeEncontrada != item.quantidadeEsperada ||
          item.classificacaoDiferenca != null ||
          (item.observacao?.trim().isNotEmpty ?? false),
    );

    if (possuiAlteracao) {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded),
          title: const Text('Marcar tudo como conferido?'),
          content: const Text(
            'Já existem alterações na conferência. Se continuar, todas as '
                'quantidades voltarão para o esperado e as divergências serão '
                'apagadas.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Tudo confere'),
            ),
          ],
        ),
      );

      if (confirmar != true || !mounted) {
        return;
      }
    }

    setState(() {
      _conferencia = _conferencia
          .map(
            (item) => ConferenciaItem(
          produtoId: item.produtoId,
          descricaoSnapshot: item.descricaoSnapshot,
          quantidadeEsperada: item.quantidadeEsperada,
          quantidadeEncontrada: item.quantidadeEsperada,
          observacao: item.observacao,
        ),
      )
          .toList();
      _itensConferidos
        ..clear()
        ..addAll(_conferencia.map((item) => item.produtoId));
      _errorMessage = null;
    });

    _agendarSalvarRascunho();
  }

  void _avancarDaConferencia() {
    if (!_conferenciaCompleta) {
      setState(() {
        _errorMessage =
        'Confirme todos os produtos e classifique as diferenças.';
      });
      return;
    }

    setState(() {
      _etapa = _inadimplente ? 2 : 1;
      _errorMessage = null;
    });

    _agendarSalvarRascunho();
  }

  void _voltarEtapa() {
    if (_isSaving) return;
    setState(() {
      if (_etapa == 2 && _inadimplente) {
        _etapa = 0;
      } else if (_etapa > 0) {
        _etapa--;
      }
      _errorMessage = null;
    });

    _agendarSalvarRascunho();
  }

  void _irParaEtapa(int etapa) {
    if (_isSaving || etapa >= _etapa) return;
    if (_inadimplente && etapa == 1) return;

    setState(() {
      _etapa = etapa;
      _errorMessage = null;
    });

    _agendarSalvarRascunho();
  }

  Future<void> _tentarSairDoAtendimento() async {
    if (_isSaving) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aguarde a finalização da visita antes de sair.'),
        ),
      );
      return;
    }

    if (_dialogSaidaAberto) return;
    _dialogSaidaAberto = true;

    final sair = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: const Text('Sair do atendimento?'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: const Text(
            'A visita ainda não foi finalizada. O andamento desta tela será '
                'salvo automaticamente e você poderá retomar a conferência e '
                'a reposição depois pela Agenda.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Continuar atendimento'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.exit_to_app),
            label: const Text('Sair e retomar depois'),
          ),
        ],
      ),
    );

    _dialogSaidaAberto = false;
    if (sair != true || !mounted) return;

    await _salvarRascunhoAgora();
    if (!mounted) return;

    setState(() => _liberarSaida = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  void _sugerirReposicao(
      List<Sku> skus,
      Map<String, int> saldosVendedor,
      ) {
    final idsDisponiveis = {
      for (final sku in skus)
        if (sku.id != null) sku.id!,
    };

    setState(() {
      for (final item in _conferencia) {
        if (item.classificacaoDiferenca != ClassificacaoDiferenca.vendido ||
            item.diferenca <= 0 ||
            !idsDisponiveis.contains(item.produtoId)) {
          continue;
        }

        final disponivel =
        _saldoDisponivel(item.produtoId, saldosVendedor);

        if (disponivel <= 0) {
          _reposicao.remove(item.produtoId);
          continue;
        }

        final sugerida = item.diferenca < disponivel
            ? item.diferenca
            : disponivel;

        if (sugerida > 0) {
          _reposicao[item.produtoId] = sugerida;
        }
      }

      _somenteSelecionados = false;
      _errorMessage = null;
    });

    _agendarSalvarRascunho();
  }

  void _limparReposicao() {
    setState(() {
      _reposicao.clear();
      _somenteSelecionados = false;
      _errorMessage = null;
    });

    _agendarSalvarRascunho();
  }

  Future<void> _handleFinalizar(
      List<Sku> skus,
      Map<String, String> descricaoPorSku,
      Map<String, int> saldosVendedor,
      ) async {
    if (!_conferenciaCompleta) {
      setState(() {
        _errorMessage =
        'Classifique e confirme todas as diferenças antes de finalizar.';
      });
      return;
    }

    if (_reposicaoAcimaDoEstoque(saldosVendedor)) {
      String? mensagem;

      for (final entry in _reposicao.entries) {
        if (entry.value <= 0) continue;

        final disponivel =
        _saldoDisponivel(entry.key, saldosVendedor);

        if (entry.value <= disponivel) continue;

        final descricao =
            descricaoPorSku[entry.key] ?? entry.key;

        mensagem =
        '$descricao: você selecionou ${entry.value} un., '
            'mas há $disponivel un. disponível(is) na sua carga.';
        break;
      }

      setState(() {
        _errorMessage = mensagem ??
            'A carga do vendedor mudou. Ajuste a reposição antes de finalizar.';
      });
      return;
    }

    final usuario = ref.read(appUserProvider).value;
    if (usuario == null) {
      setState(() {
        _errorMessage =
        'Sua sessão não está disponível. Entre novamente para continuar.';
      });
      return;
    }

    final itensReposicao = <ItemReposicao>[];
    for (final entry in _reposicao.entries) {
      if (entry.value <= 0) continue;

      final indiceSku = skus.indexWhere((sku) => sku.id == entry.key);
      if (indiceSku < 0) continue;

      final sku = skus[indiceSku];
      itensReposicao.add(
        ItemReposicao(
          sku: sku,
          descricaoSnapshot:
          descricaoPorSku[sku.id] ?? sku.codigoInterno,
          quantidade: entry.value,
        ),
      );
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    _rascunhoTimer?.cancel();
    await _salvarRascunhoAgora();

    try {
      final resultado = await ref.read(visitaServiceProvider).executarVisita(
        orgId: widget.cliente.orgId,
        cliente: widget.cliente,
        vendedorId: usuario.uid,
        consignmentAtiva: widget.consignmentAtiva,
        conferencia: _conferencia,
        itensReposicao: itensReposicao,
        visitaId: widget.visitaId,
        dataPrevista: widget.dataPrevista,
      );

      if (!mounted) return;

      _rascunhoTimer?.cancel();
      _bloquearSalvamentoRascunho = true;

      final visitaId = widget.visitaId?.trim();
      if (visitaId != null && visitaId.isNotEmpty) {
        try {
          await ref
              .read(visitaRepositoryProvider)
              .limparRascunhoExecucao(visitaId);
        } catch (error, stack) {
          debugPrint(
            'Erro ao limpar rascunho após finalizar visita: $error\n$stack',
          );
        }
      }

      if (!mounted) return;

      setState(() => _liberarSaida = true);

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => VisitaResultadoPage(
            resultado: resultado,
            orgId: widget.cliente.orgId,
            clienteId: widget.cliente.id!,
            nomeCliente: widget.cliente.nome,
            cpfCnpjCliente: widget.cliente.cpfCnpj,
            vendedorNome: usuario.nome,
          ),
        ),
      );
    } on LimiteExcedidoException catch (error) {
      if (mounted) setState(() => _errorMessage = error.toString());
    } on ReposicaoBloqueadaException catch (error) {
      if (mounted) setState(() => _errorMessage = error.toString());
    } on EstoqueInsuficienteException catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage =
          'Estoque disponível: ${error.disponivel}. Ajuste a reposição.';
        });
      }
    } catch (error, stack) {
      debugPrint('Erro ao finalizar visita: $error\n$stack');
      if (mounted) {
        setState(() {
          _errorMessage =
          'Não foi possível finalizar a visita. Tente novamente.';
        });
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usuario = ref.watch(appUserProvider).value;
    final skusAsync = ref.watch(skusListProvider);
    final produtosAsync = ref.watch(produtosListProvider);

    final saldosCargaAsync = usuario == null
        ? null
        : ref.watch(
      saldosDoLocalProvider(
        (
        orgId: widget.cliente.orgId,
        localId: LocalEstoque.vendedor(usuario.uid),
        ),
      ),
    );

    final codigoPorSku = <String, String>{
      for (final sku in skusAsync.value ?? <Sku>[])
        if (sku.id != null) sku.id!: sku.codigoInterno,
    };

    final fotoPorProduto = <String, String?>{};
    final produtosCarregados = produtosAsync.value;
    if (produtosCarregados != null) {
      for (final produto in produtosCarregados) {
        if (produto.id != null) {
          fotoPorProduto[produto.id!] = produto.fotoUrl;
        }
      }
    }

    final fotoPorSku = <String, String?>{
      for (final sku in skusAsync.value ?? <Sku>[])
        if (sku.id != null) sku.id!: fotoPorProduto[sku.produtoId],
    };

    Widget etapaComDados(
        Widget Function(
            List<Sku> skus,
            Map<String, String> descricaoPorSku,
            Map<String, String?> fotoPorSku,
            Map<String, int> saldosVendedor,
            ) builder,
        ) {
      if (usuario == null || saldosCargaAsync == null) {
        return const _LoadErrorCard(
          message: 'Não foi possível identificar a carga do vendedor.',
        );
      }

      final skus = skusAsync.value;
      final produtos = produtosAsync.value;
      final saldos = saldosCargaAsync.value;

      final primeiraCarga =
          skus == null || produtos == null || saldos == null;

      if (primeiraCarga) {
        if (skusAsync.hasError || produtosAsync.hasError) {
          return const _LoadErrorCard(
            message: 'Não foi possível carregar os produtos.',
          );
        }

        if (saldosCargaAsync.hasError) {
          return const _LoadErrorCard(
            message: 'Não foi possível carregar o estoque da sua carga.',
          );
        }

        return const _LoadingCard(
          message: 'Carregando produtos e sua carga...',
        );
      }

      final descricaoPorSku = <String, String>{};
      final fotoPorProduto = <String, String?>{
        for (final produto in produtos)
          if (produto.id != null) produto.id!: produto.fotoUrl,
      };
      final fotos = <String, String?>{};

      for (final sku in skus) {
        if (sku.id == null) continue;

        String? descricaoProduto;
        for (final produto in produtos) {
          if (produto.id == sku.produtoId) {
            descricaoProduto = produto.descricao;
            break;
          }
        }

        descricaoPorSku[sku.id!] =
            _descricaoCompleta(sku, descricaoProduto);
        fotos[sku.id!] = fotoPorProduto[sku.produtoId];
      }

      final saldosVendedor = <String, int>{
        for (final saldo in saldos)
          saldo.produtoId:
          saldo.quantidade > 0 ? saldo.quantidade : 0,
      };

      return builder(
        skus,
        descricaoPorSku,
        fotos,
        saldosVendedor,
      );
    }

    late final Widget conteudoEtapa;
    if (_etapa == 0) {
      conteudoEtapa =
          _buildEtapaConferencia(context, codigoPorSku, fotoPorSku);
    } else if (_etapa == 1) {
      conteudoEtapa = etapaComDados(
            (skus, descricaoPorSku, fotos, saldosVendedor) =>
            _buildEtapaReposicao(
              context,
              skus,
              descricaoPorSku,
              fotos,
              saldosVendedor,
            ),
      );
    } else {
      conteudoEtapa = etapaComDados(
            (skus, descricaoPorSku, fotos, saldosVendedor) =>
            _buildEtapaRevisao(
              context,
              skus,
              descricaoPorSku,
              fotos,
              saldosVendedor,
            ),
      );
    }

    return PopScope(
      canPop: _liberarSaida,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _tentarSairDoAtendimento();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          titleSpacing: 16,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Visita em andamento',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: _StatusPill(
                  icon: Icons.assignment_outlined,
                  label: widget.consignmentAtiva.numero,
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final mobile = constraints.maxWidth < 600;

              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  mobile ? 12 : 24,
                  mobile ? 12 : 22,
                  mobile ? 12 : 24,
                  32,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _VisitaContextCard(
                          clienteNome: widget.cliente.nome,
                          cpfCnpj: widget.cliente.cpfCnpj,
                          consignacaoNumero: widget.consignmentAtiva.numero,
                          quantidadeProdutos:
                          widget.consignmentAtiva.itens.length,
                          bloqueado: _inadimplente,
                        ),
                        const SizedBox(height: 14),
                        if (_inadimplente) ...[
                          const _WarningBanner(
                            title: 'Reposição bloqueada',
                            message:
                            'A conferência pode ser concluída normalmente, '
                                'mas nenhum produto poderá ser reposto enquanto '
                                'houver pendência financeira.',
                            icon: Icons.lock_outline,
                          ),
                          const SizedBox(height: 14),
                        ],
                        _VisitaSteps(
                          currentStep: _etapa,
                          reposicaoBloqueada: _inadimplente,
                          onStepPressed: _irParaEtapa,
                        ),
                        SizedBox(height: mobile ? 20 : 26),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: KeyedSubtree(
                            key: ValueKey(_etapa),
                            child: conteudoEtapa,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildEtapaConferencia(
      BuildContext context,
      Map<String, String> codigoPorSku,
      Map<String, String?> fotoPorSku,
      ) {
    final pendentes = _conferencia.length - _itensConferidos.length;

    final lista = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _ListHeader(
                title: 'Produtos consignados',
                subtitle:
                '${_itensConferidos.length} de ${_conferencia.length} conferidos',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_conferencia.isEmpty)
          const _EmptyStateCard(
            icon: Icons.inventory_2_outlined,
            title: 'Nenhum produto na consignação',
            description: 'Não existem itens disponíveis para conferência.',
          )
        else
          ..._conferencia.map(
                (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ConferenciaProductCard(
                item: item,
                skuCode: codigoPorSku[item.produtoId],
                imageUrl: fotoPorSku[item.produtoId],
                conferido: _itensConferidos.contains(item.produtoId),
                onEncontradoChanged: (quantidade) =>
                    _alterarQuantidadeEncontrada(item, quantidade),
                onClassificacaoChanged: (classificacao) =>
                    _alterarClassificacao(item, classificacao),
                onConfirmar: () => _confirmarItem(item),
                onReabrir: () {
                  setState(() {
                    _itensConferidos.remove(item.produtoId);
                    _errorMessage = null;
                  });
                  _agendarSalvarRascunho();
                },
              ),
            ),
          ),
      ],
    );

    final resumo = _ResumoVisitaCard(
      produtos: _conferencia.length,
      esperado: _totalEsperado,
      encontrado: _totalEncontrado,
      diferenca: _totalDiferenca,
      conferidos: _itensConferidos.length,
      totalParaConferir: _conferencia.length,
      helperText: pendentes > 0
          ? '$pendentes produto(s) ainda precisam ser confirmados.'
          : _totalDiferenca > 0
          ? 'Revise as divergências classificadas antes de continuar.'
          : 'Conferência concluída sem divergências.',
      primaryLabel:
      _inadimplente ? 'Revisar conferência' : 'Continuar para reposição',
      primaryIcon:
      _inadimplente ? Icons.fact_check_outlined : Icons.arrow_forward,
      primaryEnabled: _conferenciaCompleta,
      onPrimary: _avancarDaConferencia,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PageHeading(
          eyebrow: 'ETAPA 1 DE 3',
          title: 'Conferência do expositor',
          description:
          'Informe o que foi encontrado fisicamente e classifique toda '
              'diferença antes de confirmar cada produto.',
          action: FilledButton.tonalIcon(
            onPressed: _conferencia.isEmpty ? null : _confirmarTudo,
            icon: const Icon(Icons.done_all),
            label: const Text('Tudo confere'),
          ),
        ),
        const SizedBox(height: 18),
        _ConferenceMetrics(
          esperado: _totalEsperado,
          encontrado: _totalEncontrado,
          diferenca: _totalDiferenca,
          conferidos: _itensConferidos.length,
          totalItens: _conferencia.length,
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 920) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  lista,
                  const SizedBox(height: 10),
                  resumo,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: lista),
                const SizedBox(width: 14),
                SizedBox(width: 310, child: resumo),
              ],
            );
          },
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          _ErrorBanner(message: _errorMessage!),
        ],
      ],
    );
  }

  Widget _buildEtapaReposicao(
      BuildContext context,
      List<Sku> skus,
      Map<String, String> descricaoPorSku,
      Map<String, String?> fotoPorSku,
      Map<String, int> saldosVendedor,
      ) {
    if (_inadimplente) {
      return _BlockedReposicao(
        onVoltar: _voltarEtapa,
        onRevisar: () {
          setState(() => _etapa = 2);
          _agendarSalvarRascunho();
        },
      );
    }

    final busca = _buscaController.text.trim().toLowerCase();
    final skusFiltrados = skus.where((sku) {
      final id = sku.id;
      if (id == null) return false;

      final selecionado = (_reposicao[id] ?? 0) > 0;
      final disponivel = _saldoDisponivel(id, saldosVendedor);

      if (_somenteSelecionados && !selecionado) return false;

      // A reposição só pode sair da carga do vendedor. Um item que já
      // estava selecionado continua visível mesmo se o saldo cair, para
      // que o vendedor consiga corrigir a quantidade.
      if (!selecionado && disponivel <= 0) return false;

      if (busca.isEmpty) return true;

      final descricao =
      (descricaoPorSku[id] ?? '').toLowerCase();
      final codigo = sku.codigoInterno.toLowerCase();
      final barras = (sku.codigoBarras ?? '').toLowerCase();

      return descricao.contains(busca) ||
          codigo.contains(busca) ||
          barras.contains(busca);
    }).toList();

    final possuiExcesso =
    _reposicaoAcimaDoEstoque(saldosVendedor);

    final lista = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _buscaController,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Buscar por produto, SKU ou código de barras...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Ler código de barras',
                  onPressed: () =>
                      _escanearReposicao(skus, saldosVendedor),
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                ),
                if (_buscaController.text.isNotEmpty)
                  IconButton(
                    tooltip: 'Limpar busca',
                    onPressed: () {
                      _buscaController.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              selected: _somenteSelecionados,
              onSelected: (value) {
                setState(() => _somenteSelecionados = value);
              },
              avatar: const Icon(Icons.checklist, size: 18),
              label: const Text('Somente selecionados'),
            ),
            ActionChip(
              onPressed: () =>
                  _sugerirReposicao(skus, saldosVendedor),
              avatar: const Icon(
                Icons.auto_awesome_outlined,
                size: 18,
              ),
              label: const Text('Sugerir pelo vendido'),
            ),
            if (_reposicao.isNotEmpty)
              ActionChip(
                onPressed: _limparReposicao,
                avatar: const Icon(
                  Icons.delete_outline,
                  size: 18,
                ),
                label: const Text('Limpar reposição'),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _ListHeader(
          title: 'Produtos disponíveis na sua carga',
          subtitle:
          '${skusFiltrados.length} resultado(s) com saldo disponível',
        ),
        const SizedBox(height: 10),
        if (skusFiltrados.isEmpty)
          const _EmptyStateCard(
            icon: Icons.inventory_2_outlined,
            title: 'Nenhum produto disponível',
            description:
            'Sua carga não possui saldo para os filtros informados.',
          )
        else
          ...skusFiltrados.map((sku) {
            final id = sku.id!;
            final quantidade = _reposicao[id] ?? 0;
            final disponivel =
            _saldoDisponivel(id, saldosVendedor);
            final acimaDoEstoque = quantidade > disponivel;

            final indiceConferencia = _conferencia.indexWhere(
                  (item) => item.produtoId == id,
            );

            final quantidadeAtual = indiceConferencia >= 0
                ? _conferencia[indiceConferencia]
                .quantidadeEncontrada
                : null;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ReposicaoProductCard(
                description:
                descricaoPorSku[id] ?? sku.codigoInterno,
                skuCode: sku.codigoInterno,
                imageUrl: fotoPorSku[id],
                currentQuantity: quantidadeAtual,
                availableQuantity: disponivel,
                quantity: quantidade,
                overStock: acimaDoEstoque,
                onDecrease: quantidade > 0
                    ? () {
                  setState(() {
                    final novaQuantidade =
                        quantidade - 1;

                    if (novaQuantidade <= 0) {
                      _reposicao.remove(id);
                    } else {
                      _reposicao[id] =
                          novaQuantidade;
                    }

                    _errorMessage = null;
                  });
                  _agendarSalvarRascunho();
                }
                    : null,
                onIncrease: quantidade < disponivel
                    ? () {
                  setState(() {
                    _reposicao[id] =
                        quantidade + 1;
                    _errorMessage = null;
                  });
                  _agendarSalvarRascunho();
                }
                    : null,
              ),
            );
          }),
      ],
    );

    final resumo = _ReposicaoSummaryCard(
      itensSelecionados: _itensReposicaoSelecionados,
      unidades: _totalUnidadesReposicao,
      vendidos: _totalVendido,
      estoqueInvalido: possuiExcesso,
      onBack: _voltarEtapa,
      onContinue: possuiExcesso
          ? null
          : () {
        setState(() {
          _etapa = 2;
          _errorMessage = null;
        });
        _agendarSalvarRascunho();
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _PageHeading(
          eyebrow: 'ETAPA 2 DE 3',
          title: 'Reposição de produtos',
          description:
          'Selecione somente produtos disponíveis na sua carga. '
              'O limite do cliente será validado ao finalizar.',
        ),
        const SizedBox(height: 14),
        const _InfoBanner(
          message:
          'A sugestão considera somente diferenças classificadas como '
              'venda e nunca ultrapassa o estoque disponível na sua carga.',
        ),
        if (possuiExcesso) ...[
          const SizedBox(height: 12),
          const _WarningBanner(
            title: 'Sua carga mudou',
            message:
            'Uma ou mais quantidades selecionadas ficaram maiores que '
                'o saldo disponível. Reduza a reposição antes de continuar.',
          ),
        ],
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 920) {
              return Column(
                crossAxisAlignment:
                CrossAxisAlignment.stretch,
                children: [
                  lista,
                  const SizedBox(height: 10),
                  resumo,
                ],
              );
            }

            return Row(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: lista),
                const SizedBox(width: 14),
                SizedBox(width: 310, child: resumo),
              ],
            );
          },
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          _ErrorBanner(message: _errorMessage!),
        ],
      ],
    );
  }

  Widget _buildEtapaRevisao(
      BuildContext context,
      List<Sku> skus,
      Map<String, String> descricaoPorSku,
      Map<String, String?> fotoPorSku,
      Map<String, int> saldosVendedor,
      ) {
    final divergencias =
    _conferencia.where((item) => item.temDiferenca).toList();

    final conferenciaPorSku = <String, ConferenciaItem>{
      for (final item in _conferencia) item.produtoId: item,
    };
    final skuPorId = <String, Sku>{
      for (final sku in skus)
        if (sku.id != null) sku.id!: sku,
    };
    final idsNovaPosicao = <String>[];

    for (final item in _conferencia) {
      final quantidadeFinal =
          item.quantidadeEncontrada + (_reposicao[item.produtoId] ?? 0);
      if (quantidadeFinal > 0) idsNovaPosicao.add(item.produtoId);
    }
    for (final entry in _reposicao.entries) {
      if (entry.value > 0 && !idsNovaPosicao.contains(entry.key)) {
        idsNovaPosicao.add(entry.key);
      }
    }

    final conferenciaCard = _SectionCard(
      icon: Icons.fact_check_outlined,
      title: 'Resultado da conferência',
      action: TextButton.icon(
        onPressed: () => _irParaEtapa(0),
        icon: const Icon(Icons.edit_outlined, size: 18),
        label: const Text('Ajustar'),
      ),
      child: Column(
        children: [
          _ReviewLine(label: 'Unidades esperadas', value: '$_totalEsperado'),
          const Divider(height: 22),
          _ReviewLine(label: 'Unidades encontradas', value: '$_totalEncontrado'),
          const Divider(height: 22),
          _ReviewLine(label: 'Total de diferenças', value: '$_totalDiferenca'),
          const Divider(height: 22),
          _ReviewLine(label: 'Unidades vendidas', value: '$_totalVendido'),
        ],
      ),
    );

    final reposicaoCard = _SectionCard(
      icon: _inadimplente
          ? Icons.lock_outline
          : Icons.add_shopping_cart_outlined,
      title: 'Reposição',
      action: _inadimplente
          ? null
          : TextButton.icon(
        onPressed: () => _irParaEtapa(1),
        icon: const Icon(Icons.edit_outlined, size: 18),
        label: const Text('Ajustar'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_inadimplente)
            const Text(
              'Visita sem reposição porque o cliente está com bloqueio '
                  'financeiro.',
            )
          else ...[
            _ReviewLine(
              label: 'Produtos selecionados',
              value: '$_itensReposicaoSelecionados',
            ),
            const Divider(height: 22),
            _ReviewLine(
              label: 'Unidades para repor',
              value: '$_totalUnidadesReposicao',
            ),
          ],
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _PageHeading(
          eyebrow: 'ETAPA 3 DE 3',
          title: 'Revise a visita',
          description:
          'Confira as divergências e a reposição. Ao finalizar, o '
              'resultado será preparado para assinatura e documento.',
        ),
        const SizedBox(height: 18),
        _ConferenceMetrics(
          esperado: _totalEsperado,
          encontrado: _totalEncontrado,
          diferenca: _totalDiferenca,
          conferidos: _itensConferidos.length,
          totalItens: _conferencia.length,
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 760) {
              return Column(
                children: [
                  conferenciaCard,
                  const SizedBox(height: 10),
                  reposicaoCard,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: conferenciaCard),
                const SizedBox(width: 14),
                Expanded(child: reposicaoCard),
              ],
            );
          },
        ),
        if (divergencias.isNotEmpty) ...[
          const SizedBox(height: 14),
          _SectionCard(
            icon: Icons.warning_amber_rounded,
            title: 'Divergências classificadas',
            accentColor: Theme.of(context).colorScheme.tertiary,
            child: Column(
              children: [
                for (var index = 0; index < divergencias.length; index++) ...[
                  _ReviewProductRow(
                    title: divergencias[index].descricaoSnapshot,
                    subtitle: [
                      if (skuPorId[divergencias[index].produtoId] != null)
                        'SKU: ${skuPorId[divergencias[index].produtoId]!.codigoInterno}',
                      'Esperado: ${divergencias[index].quantidadeEsperada}',
                      'Encontrado: ${divergencias[index].quantidadeEncontrada}',
                      'Diferença: ${divergencias[index].diferenca}',
                    ].join(' • '),
                    badge: _classificacaoLabel(
                      divergencias[index].classificacaoDiferenca!,
                    ),
                    imageUrl: fotoPorSku[divergencias[index].produtoId],
                    tone: _PillTone.warning,
                  ),
                  if (index < divergencias.length - 1)
                    const Divider(height: 22),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        _SectionCard(
          icon: Icons.inventory_2_outlined,
          title: 'Nova posição no expositor',
          action: _inadimplente
              ? null
              : TextButton.icon(
            onPressed: () => _irParaEtapa(1),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Ajustar reposição'),
          ),
          child: idsNovaPosicao.isEmpty
              ? Text(
            'Nenhum produto permanecerá consignado no expositor.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          )
              : Column(
            children: [
              for (var index = 0;
              index < idsNovaPosicao.length;
              index++) ...[
                Builder(
                  builder: (context) {
                    final skuId = idsNovaPosicao[index];
                    final conferencia = conferenciaPorSku[skuId];
                    final saldoConferido =
                        conferencia?.quantidadeEncontrada ?? 0;
                    final quantidadeReposta = _reposicao[skuId] ?? 0;
                    final quantidadeFinal =
                        saldoConferido + quantidadeReposta;
                    final sku = skuPorId[skuId];

                    return _ReviewProductRow(
                      title: conferencia?.descricaoSnapshot ??
                          descricaoPorSku[skuId] ??
                          sku?.codigoInterno ??
                          skuId,
                      subtitle: [
                        if (sku != null) 'SKU: ${sku.codigoInterno}',
                        'Conferido: $saldoConferido',
                        'Reposição: +$quantidadeReposta',
                        'Na sua carga: ${_saldoDisponivel(skuId, saldosVendedor)}',
                        'Final: $quantidadeFinal',
                      ].join(' • '),
                      badge: '$quantidadeFinal un.',
                      imageUrl: fotoPorSku[skuId],
                      tone: quantidadeReposta >
                          _saldoDisponivel(skuId, saldosVendedor)
                          ? _PillTone.warning
                          : _PillTone.success,
                    );
                  },
                ),
                if (index < idsNovaPosicao.length - 1)
                  const Divider(height: 22),
              ],
            ],
          ),
        ),
        if (_reposicaoAcimaDoEstoque(saldosVendedor)) ...[
          const SizedBox(height: 14),
          const _WarningBanner(
            title: 'Ajuste a reposição',
            message:
            'A carga do vendedor mudou e existe quantidade selecionada '
                'acima do estoque disponível.',
          ),
        ],
        const SizedBox(height: 14),
        const _NextStepCard(),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          _ErrorBanner(message: _errorMessage!),
        ],
        const SizedBox(height: 14),
        _FinalActions(
          loading: _isSaving,
          onBack: _voltarEtapa,
          backLabel: _inadimplente
              ? 'Voltar para conferência'
              : 'Voltar para reposição',
          onFinish: () => _handleFinalizar(
            skus,
            descricaoPorSku,
            saldosVendedor,
          ),
        ),
      ],
    );
  }
}

class _VisitaContextCard extends StatelessWidget {
  final String clienteNome;
  final String cpfCnpj;
  final String consignacaoNumero;
  final int quantidadeProdutos;
  final bool bloqueado;

  const _VisitaContextCard({
    required this.clienteNome,
    required this.cpfCnpj,
    required this.consignacaoNumero,
    required this.quantidadeProdutos,
    required this.bloqueado,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colors.primaryContainer.withValues(alpha: 0.24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.primary.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final mobile = constraints.maxWidth < 650;

            final cliente = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                  child: const Icon(Icons.storefront_outlined),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        clienteNome,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        cpfCnpj,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          _StatusPill(
                            icon: bloqueado
                                ? Icons.lock_outline
                                : Icons.verified_outlined,
                            label: bloqueado
                                ? 'Financeiro bloqueado'
                                : 'Financeiro normal',
                            tone: bloqueado
                                ? _PillTone.danger
                                : _PillTone.success,
                          ),
                          _StatusPill(
                            icon: bloqueado
                                ? Icons.block
                                : Icons.add_box_outlined,
                            label: bloqueado
                                ? 'Sem reposição'
                                : 'Reposição permitida',
                            tone: bloqueado
                                ? _PillTone.warning
                                : _PillTone.info,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );

            final dados = Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: mobile ? WrapAlignment.start : WrapAlignment.end,
              children: [
                _ContextInfo(
                  icon: Icons.description_outlined,
                  label: 'Consignação',
                  value: consignacaoNumero,
                ),
                _ContextInfo(
                  icon: Icons.inventory_2_outlined,
                  label: 'Produtos',
                  value: '$quantidadeProdutos item(ns)',
                ),
              ],
            );

            if (mobile) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  cliente,
                  const SizedBox(height: 15),
                  const Divider(height: 1),
                  const SizedBox(height: 15),
                  dados,
                ],
              );
            }

            return Row(
              children: [
                Expanded(flex: 5, child: cliente),
                const SizedBox(width: 24),
                Expanded(flex: 5, child: dados),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _VisitaSteps extends StatelessWidget {
  final int currentStep;
  final bool reposicaoBloqueada;
  final ValueChanged<int> onStepPressed;

  const _VisitaSteps({
    required this.currentStep,
    required this.reposicaoBloqueada,
    required this.onStepPressed,
  });

  @override
  Widget build(BuildContext context) {
    const labels = ['Conferência', 'Reposição', 'Revisão'];
    final colors = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            for (var index = 0; index < labels.length; index++) ...[
              Expanded(
                child: InkWell(
                  onTap: index < currentStep &&
                      !(reposicaoBloqueada && index == 1)
                      ? () => onStepPressed(index)
                      : null,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final hideLabel = constraints.maxWidth < 105;
                        final active = index == currentStep;
                        final completed = index < currentStep &&
                            !(reposicaoBloqueada && index == 1);
                        final blocked = reposicaoBloqueada && index == 1;

                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: active || completed
                                    ? colors.primary
                                    : colors.surfaceContainerHighest,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                blocked
                                    ? Icons.lock_outline
                                    : completed
                                    ? Icons.check
                                    : switch (index) {
                                  0 => Icons.fact_check_outlined,
                                  1 => Icons.add_box_outlined,
                                  _ => Icons.receipt_long_outlined,
                                },
                                size: 17,
                                color: active || completed
                                    ? colors.onPrimary
                                    : colors.onSurfaceVariant,
                              ),
                            ),
                            if (!hideLabel) ...[
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  labels[index],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                    color: active
                                        ? colors.primary
                                        : colors.onSurface,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
              if (index < labels.length - 1)
                Container(
                  width: 12,
                  height: 1,
                  color: colors.outlineVariant,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PageHeading extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String description;
  final Widget? action;

  const _PageHeading({
    required this.eyebrow,
    required this.title,
    required this.description,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: theme.textTheme.labelMedium?.copyWith(
            color: colors.primary,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          description,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
            height: 1.4,
          ),
        ),
      ],
    );

    if (action == null) return text;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 680) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              text,
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerLeft, child: action!),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: text),
            const SizedBox(width: 20),
            action!,
          ],
        );
      },
    );
  }
}

class _ConferenceMetrics extends StatelessWidget {
  final int esperado;
  final int encontrado;
  final int diferenca;
  final int conferidos;
  final int totalItens;

  const _ConferenceMetrics({
    required this.esperado,
    required this.encontrado,
    required this.diferenca,
    required this.conferidos,
    required this.totalItens,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760 ? 4 : 2;
        const spacing = 10.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            _MetricTile(
              width: width,
              icon: Icons.inventory_2_outlined,
              label: 'Esperado',
              value: '$esperado',
              color: colors.primary,
            ),
            _MetricTile(
              width: width,
              icon: Icons.check_circle_outline,
              label: 'Encontrado',
              value: '$encontrado',
              color: Colors.green.shade700,
            ),
            _MetricTile(
              width: width,
              icon: Icons.warning_amber_rounded,
              label: 'Diferença',
              value: '$diferenca',
              color: diferenca > 0 ? colors.tertiary : colors.onSurfaceVariant,
            ),
            _MetricTile(
              width: width,
              icon: Icons.fact_check_outlined,
              label: 'Conferidos',
              value: '$conferidos/$totalItens',
              color: conferidos == totalItens
                  ? Colors.green.shade700
                  : colors.secondary,
            ),
          ],
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  final double width;
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MetricTile({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductThumbnail extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final IconData fallbackIcon;

  const _ProductThumbnail({
    required this.imageUrl,
    required this.size,
    this.fallbackIcon = Icons.inventory_2_outlined,
  });

  bool get _hasImage => imageUrl?.trim().isNotEmpty == true;

  void _openPreview(BuildContext context) {
    final url = imageUrl?.trim();
    if (url == null || url.isEmpty) return;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 720,
            maxHeight: 720,
          ),
          child: AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: Theme.of(dialogContext).colorScheme.surface,
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4,
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => _fallback(dialogContext),
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: IconButton.filledTonal(
                    tooltip: 'Fechar imagem',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fallback(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.primary.withValues(alpha: 0.10),
      child: Center(
        child: Icon(
          fallbackIcon,
          color: colors.primary,
          size: size * 0.48,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final image = _hasImage
        ? Image.network(
      imageUrl!.trim(),
      width: size,
      height: size,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: progress.expectedTotalBytes == null
                  ? null
                  : progress.cumulativeBytesLoaded /
                  progress.expectedTotalBytes!,
            ),
          ),
        );
      },
      errorBuilder: (_, __, ___) => _fallback(context),
    )
        : _fallback(context);

    return Semantics(
      button: _hasImage,
      label: _hasImage
          ? 'Foto do produto. Toque para ampliar.'
          : 'Produto sem foto cadastrada.',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _hasImage ? () => _openPreview(context) : null,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: image,
          ),
        ),
      ),
    );
  }
}

class _ConferenciaProductCard extends StatelessWidget {
  final ConferenciaItem item;
  final String? skuCode;
  final String? imageUrl;
  final bool conferido;
  final ValueChanged<int> onEncontradoChanged;
  final ValueChanged<ClassificacaoDiferenca> onClassificacaoChanged;
  final VoidCallback onConfirmar;
  final VoidCallback onReabrir;

  const _ConferenciaProductCard({
    required this.item,
    required this.skuCode,
    required this.imageUrl,
    required this.conferido,
    required this.onEncontradoChanged,
    required this.onClassificacaoChanged,
    required this.onConfirmar,
    required this.onReabrir,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final product = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProductThumbnail(
          imageUrl: imageUrl,
          size: 52,
          fallbackIcon: Icons.inventory_2_outlined,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.descricaoSnapshot,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (skuCode != null) ...[
                const SizedBox(height: 3),
                Text(
                  'SKU: $skuCode',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 7),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  _StatusPill(
                    icon: Icons.inventory_outlined,
                    label: 'Esperado: ${item.quantidadeEsperada}',
                  ),
                  if (conferido)
                    const _StatusPill(
                      icon: Icons.check_circle_outline,
                      label: 'Conferido',
                      tone: _PillTone.success,
                    ),
                  if (item.temDiferenca)
                    _StatusPill(
                      icon: Icons.warning_amber_rounded,
                      label: 'Diferença: ${item.diferenca}',
                      tone: _PillTone.warning,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    final counter = _QuantityCounter(
      value: item.quantidadeEncontrada,
      label: 'Encontrado',
      enabled: !conferido,
      onDecrease: item.quantidadeEncontrada > 0
          ? () => onEncontradoChanged(item.quantidadeEncontrada - 1)
          : null,
      onIncrease: item.quantidadeEncontrada < item.quantidadeEsperada
          ? () => onEncontradoChanged(item.quantidadeEncontrada + 1)
          : null,
    );

    final action = conferido
        ? OutlinedButton.icon(
      onPressed: onReabrir,
      icon: const Icon(Icons.edit_outlined),
      label: const Text('Reabrir'),
    )
        : FilledButton.icon(
      onPressed: onConfirmar,
      icon: const Icon(Icons.check),
      label: const Text('Confirmar'),
    );

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: conferido
          ? Colors.green.withValues(alpha: 0.05)
          : colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: conferido
              ? Colors.green.withValues(alpha: 0.30)
              : colors.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = constraints.maxWidth >= 670;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (horizontal)
                  Row(
                    children: [
                      Expanded(child: product),
                      const SizedBox(width: 16),
                      counter,
                      const SizedBox(width: 12),
                      SizedBox(width: 132, child: action),
                    ],
                  )
                else ...[
                  product,
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      counter,
                      action,
                    ],
                  ),
                ],
                if (item.temDiferenca) ...[
                  const SizedBox(height: 13),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.tertiaryContainer.withValues(alpha: 0.30),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'O que aconteceu com a diferença?',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: ClassificacaoDiferenca.values
                              .map(
                                (classificacao) => ChoiceChip(
                              label: Text(
                                _classificacaoLabel(classificacao),
                              ),
                              selected: item.classificacaoDiferenca ==
                                  classificacao,
                              onSelected: conferido
                                  ? null
                                  : (_) => onClassificacaoChanged(
                                classificacao,
                              ),
                            ),
                          )
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _QuantityCounter extends StatelessWidget {
  final int value;
  final String label;
  final bool enabled;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;

  const _QuantityCounter({
    required this.value,
    required this.label,
    required this.enabled,
    required this.onDecrease,
    required this.onIncrease,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 50,
      width: 170,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Diminuir',
            onPressed: enabled ? onDecrease : null,
            icon: const Icon(Icons.remove),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$value',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(label, style: theme.textTheme.labelSmall),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Aumentar',
            onPressed: enabled ? onIncrease : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

class _ResumoVisitaCard extends StatelessWidget {
  final int produtos;
  final int esperado;
  final int encontrado;
  final int diferenca;
  final int conferidos;
  final int totalParaConferir;
  final String helperText;
  final String primaryLabel;
  final IconData primaryIcon;
  final bool primaryEnabled;
  final VoidCallback onPrimary;

  const _ResumoVisitaCard({
    required this.produtos,
    required this.esperado,
    required this.encontrado,
    required this.diferenca,
    required this.conferidos,
    required this.totalParaConferir,
    required this.helperText,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.primaryEnabled,
    required this.onPrimary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = totalParaConferir == 0
        ? 1.0
        : conferidos / totalParaConferir;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Resumo da visita',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 16),
            _SummaryLine(label: 'Produtos', value: '$produtos'),
            const SizedBox(height: 10),
            _SummaryLine(label: 'Esperado total', value: '$esperado'),
            const SizedBox(height: 10),
            _SummaryLine(label: 'Encontrado total', value: '$encontrado'),
            const SizedBox(height: 10),
            _SummaryLine(
              label: 'Diferença total',
              value: '$diferenca',
              warning: diferenca > 0,
            ),
            const Divider(height: 28),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Progresso',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text('${(progress * 100).round()}%'),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress.clamp(0, 1).toDouble(),
              borderRadius: BorderRadius.circular(999),
              minHeight: 7,
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(
                helperText,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: primaryEnabled ? onPrimary : null,
                icon: Icon(primaryIcon),
                label: Text(primaryLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReposicaoProductCard extends StatelessWidget {
  final String description;
  final String skuCode;
  final String? imageUrl;
  final int? currentQuantity;
  final int availableQuantity;
  final int quantity;
  final bool overStock;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;

  const _ReposicaoProductCard({
    required this.description,
    required this.skuCode,
    required this.imageUrl,
    required this.currentQuantity,
    required this.availableQuantity,
    required this.quantity,
    required this.overStock,
    required this.onDecrease,
    required this.onIncrease,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selected = quantity > 0;

    final borderColor = overStock
        ? colors.error
        : selected
        ? colors.primary.withValues(alpha: 0.40)
        : colors.outlineVariant;

    final backgroundColor = overStock
        ? colors.errorContainer.withValues(alpha: 0.22)
        : selected
        ? colors.primaryContainer.withValues(alpha: 0.18)
        : colors.surface;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = constraints.maxWidth >= 500;

            final product = Row(
              children: [
                _ProductThumbnail(
                  imageUrl: imageUrl,
                  size: 50,
                  fallbackIcon: Icons.add_box_outlined,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Text(
                        description,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'SKU: $skuCode',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      if (currentQuantity != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Encontrado no expositor: '
                              '$currentQuantity',
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        'Na sua carga: $availableQuantity un.',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(
                          color: overStock
                              ? colors.error
                              : availableQuantity > 0
                              ? Colors.green.shade700
                              : colors.onSurfaceVariant,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (overStock) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Reduza para no máximo '
                              '$availableQuantity un.',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(
                            color: colors.error,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );

            final counter = _QuantityCounter(
              value: quantity,
              label: 'Repor',
              enabled: true,
              onDecrease: onDecrease,
              onIncrease: onIncrease,
            );

            if (!horizontal) {
              return Column(
                crossAxisAlignment:
                CrossAxisAlignment.stretch,
                children: [
                  product,
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: counter,
                  ),
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: product),
                const SizedBox(width: 16),
                counter,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ReposicaoSummaryCard extends StatelessWidget {
  final int itensSelecionados;
  final int unidades;
  final int vendidos;
  final bool estoqueInvalido;
  final VoidCallback onBack;
  final VoidCallback? onContinue;

  const _ReposicaoSummaryCard({
    required this.itensSelecionados,
    required this.unidades,
    required this.vendidos,
    required this.estoqueInvalido,
    required this.onBack,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Resumo da reposição',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 16),
            _SummaryLine(
              label: 'Itens selecionados',
              value: '$itensSelecionados',
            ),
            const SizedBox(height: 10),
            _SummaryLine(label: 'Unidades', value: '$unidades'),
            const SizedBox(height: 10),
            _SummaryLine(label: 'Unidades vendidas', value: '$vendidos'),
            const Divider(height: 28),
            Text(
              estoqueInvalido
                  ? 'Ajuste as quantidades acima do saldo da sua carga.'
                  : unidades == 0
                  ? 'Você pode continuar sem adicionar produtos.'
                  : 'As quantidades respeitam o estoque atual da sua carga.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: onContinue,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Revisar visita'),
              ),
            ),
            const SizedBox(height: 7),
            TextButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Voltar para conferência'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  final Color? accentColor;
  final Widget? action;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
    this.accentColor,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = accentColor ?? theme.colorScheme.primary;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(width: 8),
                  action!,
                ],
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _ReviewLine extends StatelessWidget {
  final String label;
  final String value;

  const _ReviewLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _ReviewProductRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final String badge;
  final String? imageUrl;
  final _PillTone tone;

  const _ReviewProductRow({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.imageUrl,
    this.tone = _PillTone.info,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProductThumbnail(
          imageUrl: imageUrl,
          size: 50,
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _StatusPill(
          icon: Icons.label_outline,
          label: badge,
          tone: tone,
        ),
      ],
    );
  }
}

class _NextStepCard extends StatelessWidget {
  const _NextStepCard();

  @override
  Widget build(BuildContext context) {
    return const _SectionCard(
      icon: Icons.draw_outlined,
      title: 'Próximos passos',
      child: Column(
        children: [
          _NextStepRow(
            number: 1,
            title: 'Finalizar a visita',
            description: 'Registra a conferência e movimenta a reposição.',
          ),
          SizedBox(height: 12),
          _NextStepRow(
            number: 2,
            title: 'Coletar assinatura',
            description: 'O cliente confirma os dados da operação.',
          ),
          SizedBox(height: 12),
          _NextStepRow(
            number: 3,
            title: 'Gerar documento',
            description: 'O termo fica vinculado ao histórico da visita.',
          ),
        ],
      ),
    );
  }
}

class _NextStepRow extends StatelessWidget {
  final int number;
  final String title;
  final String description;

  const _NextStepRow({
    required this.number,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: colors.primary.withValues(alpha: 0.12),
          child: Text(
            '$number',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FinalActions extends StatelessWidget {
  final bool loading;
  final VoidCallback onBack;
  final VoidCallback onFinish;
  final String backLabel;

  const _FinalActions({
    required this.loading,
    required this.onBack,
    required this.onFinish,
    this.backLabel = 'Voltar',
  });

  @override
  Widget build(BuildContext context) {
    final finishButton = FilledButton.icon(
      onPressed: loading ? null : onFinish,
      icon: loading
          ? const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      )
          : const Icon(Icons.check_circle_outline),
      label: Text(loading ? 'Finalizando...' : 'Finalizar visita'),
    );

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 560) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: 48, child: finishButton),
                  const SizedBox(height: 5),
                  TextButton.icon(
                    onPressed: loading ? null : onBack,
                    icon: const Icon(Icons.arrow_back),
                    label: Text(backLabel),
                  ),
                ],
              );
            }

            return Row(
              children: [
                OutlinedButton.icon(
                  onPressed: loading ? null : onBack,
                  icon: const Icon(Icons.arrow_back),
                  label: Text(backLabel),
                ),
                const Spacer(),
                SizedBox(height: 46, child: finishButton),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BlockedReposicao extends StatelessWidget {
  final VoidCallback onVoltar;
  final VoidCallback onRevisar;

  const _BlockedReposicao({
    required this.onVoltar,
    required this.onRevisar,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _PageHeading(
          eyebrow: 'ETAPA 2 DE 3',
          title: 'Reposição indisponível',
          description:
          'A conferência foi registrada, mas o cliente não está liberado '
              'para receber novos produtos.',
        ),
        const SizedBox(height: 16),
        const _EmptyStateCard(
          icon: Icons.lock_outline,
          title: 'Reposição bloqueada pelo financeiro',
          description:
          'Você pode revisar e finalizar esta visita sem adicionar '
              'produtos ao expositor.',
        ),
        const SizedBox(height: 12),
        _FinalActions(
          loading: false,
          onBack: onVoltar,
          onFinish: onRevisar,
        ),
      ],
    );
  }
}

class _ListHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _ListHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SummaryLine extends StatelessWidget {
  final String label;
  final String value;
  final bool warning;

  const _SummaryLine({
    required this.label,
    required this.value,
    this.warning = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: warning ? theme.colorScheme.tertiary : null,
          ),
        ),
      ],
    );
  }
}

enum _PillTone { neutral, success, warning, danger, info }

class _StatusPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final _PillTone tone;

  const _StatusPill({
    required this.icon,
    required this.label,
    this.tone = _PillTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = switch (tone) {
      _PillTone.success => Colors.green.shade700,
      _PillTone.warning => colors.tertiary,
      _PillTone.danger => colors.error,
      _PillTone.info => colors.primary,
      _PillTone.neutral => colors.onSurfaceVariant,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContextInfo extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ContextInfo({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelSmall),
              Text(
                value,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;

  const _WarningBanner({
    required this.title,
    required this.message,
    this.icon = Icons.warning_amber_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: colors.errorContainer.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: colors.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: colors.onErrorContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onErrorContainer,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final String message;

  const _InfoBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: colors.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _EmptyStateCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
        child: Column(
          children: [
            Icon(
              icon,
              size: 38,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  final String message;

  const _LoadingCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 14),
            Text(message),
          ],
        ),
      ),
    );
  }
}

class _LoadErrorCard extends StatelessWidget {
  final String message;

  const _LoadErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
        child: Column(
          children: [
            Icon(Icons.cloud_off_outlined, size: 36, color: colors.error),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onErrorContainer),
            ),
          ],
        ),
      ),
    );
  }
}
