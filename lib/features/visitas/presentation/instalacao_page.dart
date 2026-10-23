import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/br_formatters.dart';
import '../../../core/utils/money_input_formatter.dart';
import '../../../core/widgets/barcode_scanner_page.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../clientes/domain/cliente.dart';
import '../../clientes/presentation/cliente_providers.dart';
import '../../consignacoes/domain/consignment_item.dart';
import '../../consignacoes/presentation/consignment_providers.dart';
import '../../estoque/data/estoque_repository.dart';
import '../../estoque/domain/stock_movement.dart';
import '../../estoque/presentation/estoque_providers.dart';
import '../../expositores/domain/expositor_fisico.dart';
import '../../expositores/presentation/expositor_providers.dart';
import '../../produtos/domain/produto.dart';
import '../../produtos/domain/sku.dart';
import '../../produtos/presentation/produto_providers.dart';
import '../../produtos/presentation/sku_detail_page.dart';
import '../data/visita_repository.dart';
import '../domain/visita_exceptions.dart';
import '../domain/visita_resultado.dart';
import 'visita_providers.dart';
import 'visita_resultado_page.dart';


String _normalizarTextoBusca(String valor) {
  var texto = valor.toLowerCase();

  const substituicoes = <String, String>{
    'á': 'a', 'à': 'a', 'ã': 'a', 'â': 'a', 'ä': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
    'ó': 'o', 'ò': 'o', 'õ': 'o', 'ô': 'o', 'ö': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c',
  };

  substituicoes.forEach((comAcento, semAcento) {
    texto = texto.replaceAll(comAcento, semAcento);
  });

  return texto.trim();
}

String _normalizarGtinComparacao(String? valor) {
  final digitos = (valor ?? '').replaceAll(RegExp(r'[^0-9]'), '');

  // Mesmo padrão do scanner: UPC-A com 12 dígitos é comparado
  // como EAN-13 com zero à esquerda.
  if (digitos.length == 12) {
    return '0$digitos';
  }

  return digitos;
}

String _statusExpositorLabel(ExpositorStatus status) {
  return switch (status) {
    ExpositorStatus.disponivel => 'Disponível',
    ExpositorStatus.reservado => 'Reservado',
    ExpositorStatus.instalado => 'Instalado',
    ExpositorStatus.manutencao => 'Em manutenção',
    ExpositorStatus.recolhido => 'Recolhido',
    ExpositorStatus.descartado => 'Descartado',
    ExpositorStatus.perdido => 'Perdido',
  };
}

int _valorLiquidoConsignado({
  required Sku sku,
  required int quantidade,
  required int comissaoBasisPoints,
}) {
  if (quantidade <= 0) return 0;

  return ConsignmentItem.calcular(
    produtoId: sku.id ?? '',
    descricaoSnapshot: sku.codigoInterno,
    quantidade: quantidade,
    precoVendaCentavos: sku.precoVendaCentavos,
    custoAquisicaoCentavos: sku.custoInicialCentavos,
    comissaoBasisPoints: comissaoBasisPoints,
  ).valorLiquidoTotalCentavos;
}


String _nomeClienteParaExibicao(Cliente cliente) {
  final fantasia = cliente.nomeFantasia?.trim();
  return fantasia != null && fantasia.isNotEmpty
      ? fantasia
      : cliente.nome;
}

Future<int?> _mostrarDialogoQuantidade({
  required BuildContext context,
  required String nomeProduto,
  required int quantidadeAtual,
  required int saldoDisponivel,
}) async {
  var texto = '$quantidadeAtual';
  String? erro;

  return showDialog<int>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setStateDialog) => AlertDialog(
        title: const Text('Definir quantidade'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                nomeProduto,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Disponível na sua carga: $saldoDisponivel un.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: texto,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: InputDecoration(
                  labelText: 'Quantidade',
                  errorText: erro,
                ),
                onChanged: (value) {
                  texto = value;
                  if (erro != null) {
                    setStateDialog(() => erro = null);
                  }
                },
                onFieldSubmitted: (_) {
                  final valor = int.tryParse(texto.trim());

                  if (valor == null ||
                      valor < 0 ||
                      valor > saldoDisponivel) {
                    setStateDialog(() {
                      erro =
                      'Informe um valor entre 0 e $saldoDisponivel.';
                    });
                    return;
                  }

                  Navigator.of(dialogContext).pop(valor);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final valor = int.tryParse(texto.trim());

              if (valor == null ||
                  valor < 0 ||
                  valor > saldoDisponivel) {
                setStateDialog(() {
                  erro =
                  'Informe um valor entre 0 e $saldoDisponivel.';
                });
                return;
              }

              Navigator.of(dialogContext).pop(valor);
            },
            child: const Text('Aplicar'),
          ),
        ],
      ),
    ),
  );
}

enum _FiltroInstalacao {
  todos,
  selecionados,
  semEstoque,
}

class InstalacaoPage extends ConsumerStatefulWidget {
  final Cliente cliente;

  /// Quando informado, a instalação usa exatamente este expositor
  /// reservado. Isso permite instalar um 2º, 3º ou outro expositor
  /// no mesmo cliente sem depender do expositor inicial salvo no cadastro.
  final String? expositorId;

  final String? visitaId;
  final DateTime? dataPrevista;

  const InstalacaoPage({
    super.key,
    required this.cliente,
    this.expositorId,
    this.visitaId,
    this.dataPrevista,
  });

  @override
  ConsumerState<InstalacaoPage> createState() => _InstalacaoPageState();
}

class _InstalacaoPageState extends ConsumerState<InstalacaoPage> {
  final Map<String, int> _quantidades = {};

  final _buscaController = TextEditingController();

  _FiltroInstalacao _filtro = _FiltroInstalacao.todos;

  bool _isSaving = false;

  bool _rascunhoCarregado = false;

  bool _carregandoRascunho = false;

  String? _rascunhoErrorMessage;

  bool _instalacaoFinalizada = false;

  bool _rascunhoAlterado = false;

  int _rascunhoVersao = 0;

  Timer? _rascunhoDebounce;

  late final VisitaRepository _visitaRepository;

  String _busca = '';

  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _visitaRepository = ref.read(visitaRepositoryProvider);
    Future.microtask(_carregarRascunho);
  }

  @override
  void dispose() {
    _rascunhoDebounce?.cancel();

    final visitaId = widget.visitaId?.trim();

    if (!_instalacaoFinalizada &&
        _rascunhoCarregado &&
        _rascunhoAlterado &&
        visitaId != null &&
        visitaId.isNotEmpty) {
      final quantidadesSnapshot =
      Map<String, int>.from(_quantidades);

      unawaited(
        _visitaRepository
            .salvarRascunhoInstalacao(
          visitaId: visitaId,
          quantidades: quantidadesSnapshot,
        )
            .catchError((e, stack) {
          debugPrint(
            'Erro ao salvar rascunho ao sair da instalação: $e\n$stack',
          );
        }),
      );
    }

    _buscaController.dispose();
    super.dispose();
  }


  Future<void> _carregarRascunho() async {
    if (_carregandoRascunho) return;

    final visitaId = widget.visitaId?.trim();

    if (visitaId == null || visitaId.isEmpty) {
      if (mounted) {
        setState(() {
          _rascunhoCarregado = true;
          _carregandoRascunho = false;
          _rascunhoErrorMessage = null;
        });
      } else {
        _rascunhoCarregado = true;
      }
      return;
    }

    if (mounted) {
      setState(() {
        _carregandoRascunho = true;
        _rascunhoCarregado = false;
        _rascunhoErrorMessage = null;
      });
    }

    try {
      final rascunho =
      await _visitaRepository.carregarRascunhoInstalacao(visitaId);
      final skus = await ref.read(skusListProvider.future);

      final idsValidos = <String>{
        for (final sku in skus)
          if (sku.id != null) sku.id!,
      };

      final rascunhoValido = <String, int>{
        for (final entry in rascunho.entries)
          if (idsValidos.contains(entry.key) && entry.value > 0)
            entry.key: entry.value,
      };

      final quantidadePositivaOriginal =
          rascunho.values.where((quantidade) => quantidade > 0).length;
      final removeuItemInvalido =
          quantidadePositivaOriginal != rascunhoValido.length;

      if (!mounted) return;

      setState(() {
        _quantidades
          ..clear()
          ..addAll(rascunhoValido);
        _rascunhoCarregado = true;
        _carregandoRascunho = false;
        _rascunhoErrorMessage = null;
      });

      if (removeuItemInvalido) {
        _rascunhoAlterado = true;
        _rascunhoVersao++;
        _agendarSalvarRascunho();
      }
    } catch (e, stack) {
      debugPrint(
        'Erro ao carregar rascunho da instalação: $e\n$stack',
      );

      if (!mounted) return;

      setState(() {
        // IMPORTANTE: continua falso para impedir qualquer auto-save
        // até o rascunho original ser carregado com sucesso.
        _rascunhoCarregado = false;
        _carregandoRascunho = false;
        _rascunhoErrorMessage =
        'Não foi possível carregar o rascunho desta visita. '
            'Sua seleção anterior não será sobrescrita.';
      });
    }
  }


  void _agendarSalvarRascunho() {
    final visitaId = widget.visitaId?.trim();

    if (!_rascunhoCarregado ||
        !_rascunhoAlterado ||
        visitaId == null ||
        visitaId.isEmpty ||
        _isSaving) {
      return;
    }

    _rascunhoDebounce?.cancel();

    final quantidadesSnapshot =
    Map<String, int>.from(_quantidades);
    final versaoSnapshot = _rascunhoVersao;

    _rascunhoDebounce = Timer(
      const Duration(milliseconds: 600),
          () async {
        try {
          await _visitaRepository.salvarRascunhoInstalacao(
            visitaId: visitaId,
            quantidades: quantidadesSnapshot,
          );

          if (_rascunhoVersao == versaoSnapshot) {
            _rascunhoAlterado = false;
          }
        } catch (e, stack) {
          debugPrint(
            'Erro ao salvar rascunho da instalação: $e\n$stack',
          );
        }
      },
    );
  }

  void _marcarRascunhoAlterado() {
    if (!_rascunhoCarregado) return;

    _rascunhoAlterado = true;
    _rascunhoVersao++;
    _agendarSalvarRascunho();
  }


  String _descricaoCompleta(
      Sku sku,
      String? descricaoProduto,
      ) {
    final nome = descricaoProduto ?? sku.codigoInterno;

    return sku.variacao != null && sku.variacao!.trim().isNotEmpty
        ? '$nome — ${sku.variacao}'
        : nome;
  }

  String _nomeProduto(
      Sku sku,
      Produto? produto,
      ) {
    return produto?.descricao ?? sku.codigoInterno;
  }

  String? _modeloProduto(Produto? produto) {
    final modelo = produto?.modelo?.trim();

    if (modelo == null || modelo.isEmpty) {
      return null;
    }

    return modelo;
  }

  String? _variacaoProduto(Sku sku) {
    final variacao = sku.variacao?.trim();

    if (variacao == null || variacao.isEmpty) {
      return null;
    }

    return variacao;
  }

  String get _nomeClienteExibicao =>
      _nomeClienteParaExibicao(widget.cliente);

  int _valorNovaExposicaoCentavos(List<Sku> skus, Cliente clienteAtual) {
    final skuPorId = <String, Sku>{
      for (final sku in skus)
        if (sku.id != null) sku.id!: sku,
    };

    var total = 0;

    for (final entry in _quantidades.entries) {
      if (entry.value <= 0) continue;

      final sku = skuPorId[entry.key];
      if (sku == null) continue;

      total += _valorLiquidoConsignado(
        sku: sku,
        quantidade: entry.value,
        comissaoBasisPoints: clienteAtual.comissaoBasisPoints,
      );
    }

    return total;
  }

  bool _temQuantidadeAcimaDoSaldo(
      Map<String, int> saldosPorSku,
      ) {
    for (final entry in _quantidades.entries) {
      if (entry.value <= 0) continue;

      if (entry.value > (saldosPorSku[entry.key] ?? 0)) {
        return true;
      }
    }

    return false;
  }

  Future<void> _editarQuantidade({
    required String skuId,
    required String nomeProduto,
    required int saldoDisponivel,
  }) async {
    if (!_rascunhoCarregado) return;

    final novaQuantidade = await _mostrarDialogoQuantidade(
      context: context,
      nomeProduto: nomeProduto,
      quantidadeAtual: _quantidades[skuId] ?? 0,
      saldoDisponivel: saldoDisponivel,
    );

    if (novaQuantidade == null || !mounted) return;
    if (novaQuantidade == (_quantidades[skuId] ?? 0)) return;

    setState(() {
      if (novaQuantidade == 0) {
        _quantidades.remove(skuId);
      } else {
        _quantidades[skuId] = novaQuantidade;
      }
      _errorMessage = null;
    });

    _marcarRascunhoAlterado();
  }

  Future<void> _escanearProduto({
    required List<Sku> skus,
    required Map<String, Produto> produtoPorId,
    required Map<String, int> saldosPorSku,
  }) async {
    if (!_rascunhoCarregado) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Aguarde o rascunho carregar antes de alterar a instalação.',
          ),
        ),
      );
      return;
    }

    final codigo = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerPage(),
      ),
    );

    if (codigo == null || !mounted) return;

    final normalizado = _normalizarGtinComparacao(codigo);
    if (normalizado.isEmpty) return;

    Sku? encontrado;

    for (final sku in skus) {
      final codigoSku =
      _normalizarGtinComparacao(sku.codigoBarras);

      if (codigoSku.isNotEmpty && codigoSku == normalizado) {
        encontrado = sku;
        break;
      }
    }

    if (encontrado == null || encontrado.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Código $codigo não encontrado nos produtos cadastrados.',
          ),
        ),
      );
      return;
    }

    final skuId = encontrado.id!;
    final saldo = saldosPorSku[skuId] ?? 0;
    final atual = _quantidades[skuId] ?? 0;
    final produto = produtoPorId[encontrado.produtoId];
    final nome = _nomeProduto(encontrado, produto);

    if (saldo <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$nome foi encontrado, mas está sem estoque na sua carga.',
          ),
        ),
      );
      return;
    }

    if (atual >= saldo) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$nome já atingiu o máximo disponível na sua carga: '
                '$saldo un.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _quantidades[skuId] = atual + 1;
      _errorMessage = null;
    });

    _marcarRascunhoAlterado();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$nome: +1 unidade adicionada.'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  int get _totalProdutosSelecionados {
    return _quantidades.values.where((quantidade) => quantidade > 0).length;
  }

  int get _totalUnidadesSelecionadas {
    return _quantidades.values.fold(
      0,
          (total, quantidade) => total + quantidade,
    );
  }

  void _abrirDetalheProduto(Sku sku) {
    final skuId = sku.id;

    if (skuId == null) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SkuDetailPage(
          skuId: skuId,
        ),
      ),
    );
  }

  void _incrementar(
      String skuId,
      int saldoDisponivel,
      ) {
    final atual = _quantidades[skuId] ?? 0;

    if (atual >= saldoDisponivel) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saldoDisponivel <= 0
                ? 'Este produto está sem estoque.'
                : 'Quantidade máxima disponível: $saldoDisponivel.',
          ),
        ),
      );

      return;
    }

    setState(() {
      _quantidades[skuId] = atual + 1;
      _errorMessage = null;
    });

    _marcarRascunhoAlterado();
  }

  void _decrementar(String skuId) {
    final atual = _quantidades[skuId] ?? 0;

    if (atual <= 0) {
      return;
    }

    setState(() {
      _quantidades[skuId] = atual - 1;
      _errorMessage = null;
    });

    _marcarRascunhoAlterado();
  }

  bool _correspondeBusca(
      Sku sku,
      Produto? produto,
      ) {
    final busca = _normalizarTextoBusca(_busca);

    if (busca.isEmpty) {
      return true;
    }

    final campos = _normalizarTextoBusca(
      [
        produto?.descricao ?? '',
        produto?.modelo ?? '',
        produto?.fabricante ?? '',
        sku.variacao ?? '',
        sku.codigoInterno,
        sku.codigoBarras ?? '',
      ].join(' '),
    );

    return campos.contains(busca);
  }


  bool _correspondeFiltro(
      Sku sku,
      int saldo,
      ) {
    final quantidade = _quantidades[sku.id] ?? 0;

    return switch (_filtro) {
      _FiltroInstalacao.todos => true,
      _FiltroInstalacao.selecionados => quantidade > 0,
      _FiltroInstalacao.semEstoque => saldo <= 0,
    };
  }

  Future<void> _abrirConferencia(
      ExpositorFisico expositor,
      List<Sku> skus,
      Map<String, Produto> produtoPorId,
      Map<String, String> descricaoPorSku,
      Map<String, int> saldosPorSku,
      Cliente clienteAtual,
      int exposicaoAtualCentavos,
      ) async {
    final saldosDisponiveis = <String, int>{
      for (final sku in skus)
        if (sku.id != null) sku.id!: saldosPorSku[sku.id!] ?? 0,
    };

    final confirmar = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _ConferenciaInstalacaoPage(
          cliente: clienteAtual,
          expositor: expositor,
          skus: skus,
          produtoPorId: produtoPorId,
          quantidades: _quantidades,
          saldosDisponiveis: saldosDisponiveis,
          exposicaoAtualCentavos: exposicaoAtualCentavos,
          onQuantidadesChanged: (novasQuantidades) {
            if (!mounted) {
              return;
            }

            setState(() {
              _quantidades
                ..clear()
                ..addAll(novasQuantidades);

              _errorMessage = null;
            });

            _marcarRascunhoAlterado();
          },
        ),
      ),
    );

    if (confirmar != true || !mounted) {
      return;
    }

    await _handleFinalizar(
      expositor,
      skus,
      descricaoPorSku,
    );
  }

  Future<void> _handleFinalizar(
      ExpositorFisico expositor,
      List<Sku> skus,
      Map<String, String> descricaoPorSku,
      ) async {
    final itens = <ItemReposicao>[];

    final skuPorId = <String, Sku>{
      for (final sku in skus)
        if (sku.id != null) sku.id!: sku,
    };

    for (final entry in _quantidades.entries) {
      if (entry.value <= 0) {
        continue;
      }

      final sku = skuPorId[entry.key];

      if (sku == null) {
        setState(() {
          _errorMessage =
          'Um produto do rascunho não existe mais. '
              'Atualize a instalação e tente novamente.';
        });
        return;
      }

      itens.add(
        ItemReposicao(
          sku: sku,
          descricaoSnapshot:
          descricaoPorSku[sku.id] ?? sku.codigoInterno,
          quantidade: entry.value,
        ),
      );
    }

    if (itens.isEmpty) {
      setState(() {
        _errorMessage = 'Selecione pelo menos um produto.';
      });

      return;
    }

    final usuario = ref.read(appUserProvider).value;

    if (usuario == null) {
      setState(() {
        _errorMessage =
        'Não foi possível identificar o usuário logado.';
      });

      return;
    }

    _rascunhoDebounce?.cancel();

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final resultado =
      await ref.read(visitaServiceProvider).executarInstalacao(
        orgId: widget.cliente.orgId,
        cliente: widget.cliente,
        vendedorId: usuario.uid,
        itensInstalados: itens,
        expositorId: expositor.id!,
        expositorNumero: expositor.numero,
        expositorModeloNome: expositor.modeloNome,
        visitaId: widget.visitaId,
        dataPrevista: widget.dataPrevista,
      );

      if (!mounted) {
        return;
      }

      _instalacaoFinalizada = true;

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
    } on LimiteExcedidoException catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = e.toString();
      });
    } on EstoqueInsuficienteException catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage =
        'O estoque da sua carga mudou durante a instalação. '
            'Disponível: ${e.disponivel} un. '
            'Solicitado: ${e.solicitado} un. '
            'Atualize as quantidades e tente novamente.';
      });
    } catch (e, stack) {
      debugPrint(
        'Erro ao finalizar instalação: $e\n$stack',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage =
        'Não foi possível finalizar a instalação. '
            'Confira se a visita continua em andamento e se '
            'o expositor permanece reservado para este cliente.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final expositorFisicoId =
        widget.expositorId ?? widget.cliente.expositorFisicoSelecionadoId;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Instalação — $_nomeClienteExibicao',
        ),
      ),
      body: expositorFisicoId == null
          ? const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Nenhum expositor reservado foi informado para esta instalação. '
                'Selecione ou reserve uma unidade antes de instalar.',
            textAlign: TextAlign.center,
          ),
        ),
      )
          : _buildConteudo(
        context,
        expositorFisicoId,
      ),
    );
  }

  Widget _buildConteudo(
      BuildContext context,
      String expositorFisicoId,
      ) {
    final usuario = ref.watch(appUserProvider).value;

    if (usuario == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    final localEstoqueVendedor =
    LocalEstoque.vendedor(usuario.uid);

    final expositorAsync = ref.watch(
      expositorFisicoByIdProvider(
        expositorFisicoId,
      ),
    );

    final skusAsync = ref.watch(
      skusListProvider,
    );

    final produtosAsync = ref.watch(
      produtosListProvider,
    );

    final clienteAtualAsync = ref.watch(
      clienteByIdProvider(widget.cliente.id!),
    );

    final clienteAtual =
        clienteAtualAsync.value ?? widget.cliente;

    final saldosCargaAsync = ref.watch(
      saldosDoLocalProvider(
        (
        orgId: widget.cliente.orgId,
        localId: localEstoqueVendedor,
        ),
      ),
    );

    final consignacoesAtivasAsync = ref.watch(
      consignmentsTodasAtivasDoClienteProvider(
        widget.cliente.id!,
      ),
    );

    if (saldosCargaAsync.hasError &&
        !saldosCargaAsync.hasValue) {
      debugPrint(
        'Erro ao carregar carga do vendedor: '
            '${saldosCargaAsync.error}',
      );
      return const Center(
        child: Text(
          'Não foi possível carregar a sua carga de estoque.',
        ),
      );
    }

    if (consignacoesAtivasAsync.hasError &&
        !consignacoesAtivasAsync.hasValue) {
      debugPrint(
        'Erro ao carregar exposição atual do cliente: '
            '${consignacoesAtivasAsync.error}',
      );
      return const Center(
        child: Text(
          'Não foi possível carregar a exposição do cliente.',
        ),
      );
    }

    // Durante refresh, mantém o valor anterior na tela. Assim a lista
    // não vira um spinner e não perde a posição de rolagem.
    if (!saldosCargaAsync.hasValue ||
        !consignacoesAtivasAsync.hasValue) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    final saldosCarga = saldosCargaAsync.value ?? const [];
    final consignacoesAtivas =
        consignacoesAtivasAsync.value ?? const [];

    final saldoNumericoPorSku = <String, int>{
      for (final saldo in saldosCarga)
        saldo.produtoId: saldo.quantidade,
    };

    final exposicaoAtualCentavos =
    consignacoesAtivas.fold<int>(
      0,
          (total, consignacao) =>
      total + consignacao.valorLiquidoTotalCentavos,
    );

    return expositorAsync.when(
      data: (expositor) {
        if (expositor == null) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'O expositor reservado não foi encontrado.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (expositor.status != ExpositorStatus.reservado) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'O ${expositor.numero} não está mais reservado.\n\n'
                    'Status atual: ${_statusExpositorLabel(expositor.status)}.\n\n'
                    'Confira o expositor no cadastro do cliente.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          );
        }

        if (expositor.clienteReservadoId != widget.cliente.id) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Theme.of(context).colorScheme.error,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Reserva inconsistente',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'O expositor ${expositor.numero} está reservado, '
                        'mas não está vinculado a este cliente.\n\n'
                        'Volte ao cadastro do cliente e confira '
                        'qual expositor está reservado.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return skusAsync.when(
          data: (skus) {
            return produtosAsync.when(
              data: (produtos) {
                if (skus.isEmpty) {
                  return const Center(
                    child: Text(
                      'Cadastre produtos antes de instalar.',
                    ),
                  );
                }

                final produtoPorId = <String, Produto>{
                  for (final produto in produtos)
                    if (produto.id != null) produto.id!: produto,
                };

                final descricaoPorSku = <String, String>{
                  for (final sku in skus)
                    if (sku.id != null)
                      sku.id!: _descricaoCompleta(
                        sku,
                        produtoPorId[sku.produtoId]?.descricao,
                      ),
                };

                final saldosPorSku = <String, int>{
                  for (final sku in skus)
                    if (sku.id != null)
                      sku.id!: saldoNumericoPorSku[sku.id!] ?? 0,
                };

                final skusFiltrados = skus.where((sku) {
                  final skuId = sku.id;

                  if (skuId == null) {
                    return false;
                  }

                  final produto = produtoPorId[sku.produtoId];

                  if (!_correspondeBusca(
                    sku,
                    produto,
                  )) {
                    return false;
                  }

                  final saldo = saldosPorSku[skuId] ?? 0;

                  return _correspondeFiltro(
                    sku,
                    saldo,
                  );
                }).toList();

                skusFiltrados.sort((a, b) {
                  final produtoA =
                  produtoPorId[a.produtoId];

                  final produtoB =
                  produtoPorId[b.produtoId];

                  final nomeA =
                  _nomeProduto(a, produtoA).toLowerCase();

                  final nomeB =
                  _nomeProduto(b, produtoB).toLowerCase();

                  return nomeA.compareTo(nomeB);
                });

                final semEstoque = skus.where((sku) {
                  final id = sku.id;

                  if (id == null) {
                    return false;
                  }

                  final saldo = saldosPorSku[id] ?? 0;

                  return saldo <= 0;
                }).length;

                return Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(
                          bottom: 24,
                        ),
                        child: ResponsiveCenter(
                          maxWidth: 1180,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              16,
                              16,
                              16,
                              8,
                            ),
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.stretch,
                              children: [
                                _buildExpositorCard(
                                  context,
                                  expositor,
                                ),

                                if (_carregandoRascunho ||
                                    _rascunhoErrorMessage != null) ...[
                                  const SizedBox(height: 12),
                                  _buildRascunhoStatus(context),
                                ],

                                const SizedBox(height: 18),

                                _buildBusca(
                                  context,
                                  skus: skus,
                                  produtoPorId: produtoPorId,
                                  saldosPorSku: saldoNumericoPorSku,
                                ),

                                const SizedBox(height: 12),

                                _buildFiltros(
                                  context,
                                  total: skus.length,
                                  selecionados:
                                  _totalProdutosSelecionados,
                                  semEstoque: semEstoque,
                                ),

                                const SizedBox(height: 18),

                                if (skusFiltrados.isEmpty)
                                  _buildListaVazia(
                                    context,
                                  )
                                else
                                  LayoutBuilder(
                                    builder: (
                                        context,
                                        constraints,
                                        ) {
                                      final largura =
                                          constraints.maxWidth;

                                      final colunas =
                                      largura >= 1000
                                          ? 3
                                          : largura >= 680
                                          ? 2
                                          : 1;

                                      const espacamento = 12.0;

                                      final larguraCard =
                                      colunas == 1
                                          ? largura
                                          : (largura -
                                          (espacamento *
                                              (colunas -
                                                  1))) /
                                          colunas;

                                      return Wrap(
                                        spacing: espacamento,
                                        runSpacing: espacamento,
                                        children:
                                        skusFiltrados.map(
                                              (sku) {
                                            final skuId =
                                            sku.id!;

                                            final produto =
                                            produtoPorId[
                                            sku.produtoId];

                                            final saldo =
                                                saldosPorSku[skuId] ?? 0;

                                            return SizedBox(
                                              width:
                                              larguraCard,
                                              child:
                                              _buildProdutoCard(
                                                context,
                                                sku: sku,
                                                produto:
                                                produto,
                                                saldo:
                                                saldo,
                                              ),
                                            );
                                          },
                                        ).toList(),
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    _buildBarraInferior(
                      context,
                      expositor: expositor,
                      skus: skus,
                      produtoPorId: produtoPorId,
                      descricaoPorSku:
                      descricaoPorSku,
                      saldosPorSku:
                      saldosPorSku,
                      clienteAtual:
                      clienteAtual,
                      exposicaoAtualCentavos:
                      exposicaoAtualCentavos,
                    ),
                  ],
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(),
              ),
              error: (e, st) {
                debugPrint(
                  'Erro ao carregar produtos: $e\n$st',
                );

                return const Center(
                  child: Text(
                    'Não foi possível carregar os produtos.',
                  ),
                );
              },
            );
          },
          loading: () => const Center(
            child: CircularProgressIndicator(),
          ),
          error: (e, st) {
            debugPrint(
              'Erro ao carregar SKUs: $e\n$st',
            );

            return const Center(
              child: Text(
                'Não foi possível carregar os produtos.',
              ),
            );
          },
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(),
      ),
      error: (e, st) {
        debugPrint(
          'Erro ao carregar expositor reservado: $e\n$st',
        );

        return const Center(
          child: Text(
            'Não foi possível carregar o expositor reservado.',
          ),
        );
      },
    );
  }

  Widget _buildExpositorCard(
      BuildContext context,
      ExpositorFisico expositor,
      ) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: LayoutBuilder(
          builder: (
              context,
              constraints,
              ) {
            final compacto =
                constraints.maxWidth < 600;

            final icone = Container(
              width: compacto ? 54 : 64,
              height: compacto ? 54 : 64,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary
                    .withValues(alpha: .12),
                borderRadius:
                BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.storefront_outlined,
                color:
                theme.colorScheme.primary,
                size: compacto ? 28 : 34,
              ),
            );

            final informacoes = Expanded(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Text(
                    '${expositor.numero} — ${expositor.modeloNome}',
                    style: theme
                        .textTheme
                        .titleLarge
                        ?.copyWith(
                      fontWeight:
                      FontWeight.w700,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Container(
                    padding:
                    const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: theme
                          .colorScheme.primary
                          .withValues(
                        alpha: .12,
                      ),
                      borderRadius:
                      BorderRadius.circular(
                        20,
                      ),
                      border: Border.all(
                        color: theme
                            .colorScheme.primary
                            .withValues(
                          alpha: .4,
                        ),
                      ),
                    ),
                    child: Text(
                      'Reservado para este cliente',
                      style: TextStyle(
                        color: theme
                            .colorScheme.primary,
                        fontWeight:
                        FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    _nomeClienteExibicao,
                    maxLines: 2,
                    overflow:
                    TextOverflow.ellipsis,
                    style:
                    theme.textTheme.bodyMedium,
                  ),

                  if (widget.cliente.cpfCnpj
                      .trim()
                      .isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      formatarCpfCnpj(widget.cliente.cpfCnpj),
                      style: theme
                          .textTheme.bodySmall
                          ?.copyWith(
                        color: theme
                            .colorScheme
                            .onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            );

            if (compacto) {
              return Row(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  icone,
                  const SizedBox(width: 14),
                  informacoes,
                ],
              );
            }

            return Row(
              children: [
                icone,
                const SizedBox(width: 18),
                informacoes,
                const SizedBox(width: 20),
                _InfoExpositor(
                  icon:
                  Icons.inventory_2_outlined,
                  label: 'Modelo',
                  value:
                  expositor.modeloNome,
                ),
                const SizedBox(width: 28),
                _InfoExpositor(
                  icon: Icons.tag,
                  label: 'Número',
                  value:
                  expositor.numero,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBusca(
      BuildContext context, {
        required List<Sku> skus,
        required Map<String, Produto> produtoPorId,
        required Map<String, int> saldosPorSku,
      }) {
    return TextField(
      controller: _buscaController,
      textInputAction: TextInputAction.search,
      onChanged: (valor) {
        setState(() {
          _busca = valor;
        });
      },
      decoration: InputDecoration(
        hintText:
        'Buscar produto, modelo, variação ou código...',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_busca.isNotEmpty)
              IconButton(
                tooltip: 'Limpar busca',
                onPressed: () {
                  _buscaController.clear();
                  setState(() => _busca = '');
                },
                icon: const Icon(Icons.close_rounded),
              ),
            IconButton(
              tooltip: 'Escanear código de barras',
              onPressed: !_rascunhoCarregado || _isSaving
                  ? null
                  : () => _escanearProduto(
                skus: skus,
                produtoPorId: produtoPorId,
                saldosPorSku: saldosPorSku,
              ),
              icon: const Icon(Icons.qr_code_scanner_rounded),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildFiltros(
      BuildContext context, {
        required int total,
        required int selecionados,
        required int semEstoque,
      }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ChoiceChip(
            selected:
            _filtro ==
                _FiltroInstalacao.todos,
            label:
            Text('Todos ($total)'),
            onSelected: (_) {
              setState(() {
                _filtro =
                    _FiltroInstalacao.todos;
              });
            },
          ),

          const SizedBox(width: 8),

          ChoiceChip(
            selected:
            _filtro ==
                _FiltroInstalacao
                    .selecionados,
            label: Text(
              'Selecionados ($selecionados)',
            ),
            onSelected: (_) {
              setState(() {
                _filtro =
                    _FiltroInstalacao
                        .selecionados;
              });
            },
          ),

          const SizedBox(width: 8),

          ChoiceChip(
            selected:
            _filtro ==
                _FiltroInstalacao.semEstoque,
            label:
            Text('Sem estoque ($semEstoque)'),
            onSelected: (_) {
              setState(() {
                _filtro =
                    _FiltroInstalacao
                        .semEstoque;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProdutoCard(
      BuildContext context, {
        required Sku sku,
        required Produto? produto,
        required int saldo,
      }) {
    final theme = Theme.of(context);

    final skuId = sku.id!;

    final quantidade =
        _quantidades[skuId] ?? 0;

    final selecionado =
        quantidade > 0;

    final quantidadeAcimaDoSaldo =
        quantidade > saldo;

    final podeAdicionar =
        _rascunhoCarregado &&
            !_isSaving &&
            saldo > 0 &&
            quantidade < saldo;

    final nome =
    _nomeProduto(
      sku,
      produto,
    );

    final modelo =
    _modeloProduto(produto);

    final variacao =
    _variacaoProduto(sku);

    return AnimatedContainer(
      duration:
      const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        borderRadius:
        BorderRadius.circular(14),
        border: Border.all(
          color: quantidadeAcimaDoSaldo
              ? theme.colorScheme.error
              : selecionado
              ? theme.colorScheme.primary
              : theme.colorScheme.outline
              .withValues(alpha: .18),
          width: selecionado || quantidadeAcimaDoSaldo ? 1.5 : 1,
        ),
        boxShadow: selecionado
            ? [
          BoxShadow(
            color: theme
                .colorScheme.primary
                .withValues(alpha: .08),
            blurRadius: 12,
          ),
        ]
            : null,
      ),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: LayoutBuilder(
            builder: (
                context,
                constraints,
                ) {
              final muitoEstreito =
                  constraints.maxWidth < 360;

              final foto = _FotoProduto(
                fotoUrl:
                produto?.fotoUrl,
                onTap: () {
                  _abrirDetalheProduto(
                    sku,
                  );
                },
              );

              final informacoes = Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            nome,
                            maxLines: 2,
                            overflow:
                            TextOverflow
                                .ellipsis,
                            style: theme
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                              fontWeight:
                              FontWeight
                                  .w700,
                            ),
                          ),
                        ),

                        if (selecionado) ...[
                          const SizedBox(
                            width: 6,
                          ),
                          Container(
                            width: 24,
                            height: 24,
                            decoration:
                            BoxDecoration(
                              color: theme
                                  .colorScheme
                                  .primary,
                              shape:
                              BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.check,
                              size: 16,
                              color: theme
                                  .colorScheme
                                  .onPrimary,
                            ),
                          ),
                        ],
                      ],
                    ),

                    if (modelo != null) ...[
                      const SizedBox(
                        height: 5,
                      ),
                      _LinhaIdentificacao(
                        titulo: 'Modelo',
                        valor: modelo,
                      ),
                    ],

                    if (variacao != null) ...[
                      const SizedBox(
                        height: 3,
                      ),
                      _LinhaIdentificacao(
                        titulo: 'Variação',
                        valor: variacao,
                      ),
                    ],

                    const SizedBox(height: 3),

                    Text(
                      'Cód. ${sku.codigoInterno}',
                      maxLines: 1,
                      overflow:
                      TextOverflow.ellipsis,
                      style: theme
                          .textTheme.bodySmall
                          ?.copyWith(
                        color: theme
                            .colorScheme
                            .onSurfaceVariant,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      formatarCentavos(
                        sku.precoVendaCentavos,
                      ),
                      style: theme
                          .textTheme.titleMedium
                          ?.copyWith(
                        fontWeight:
                        FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Row(
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 16,
                          color: saldo <= 0 || quantidadeAcimaDoSaldo
                              ? theme.colorScheme.error
                              : selecionado
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            quantidadeAcimaDoSaldo
                                ? 'Na sua carga: $saldo un. • '
                                'Selecionado: $quantidade'
                                : saldo <= 0
                                ? 'Sem estoque na sua carga'
                                : 'Na sua carga: $saldo un.',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: saldo <= 0 || quantidadeAcimaDoSaldo
                                  ? theme.colorScheme.error
                                  : selecionado
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight: saldo <= 0 || selecionado
                                  ? FontWeight.w600
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),

                    if (quantidadeAcimaDoSaldo) ...[
                      Text(
                        'Reduza ${quantidade - saldo} unidade(s) '
                            'para continuar.',
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        if (selecionado &&
                            !muitoEstreito)
                          Expanded(
                            child: Text(
                              'Selecionado',
                              style:
                              TextStyle(
                                color: theme
                                    .colorScheme
                                    .primary,
                                fontSize: 12,
                                fontWeight:
                                FontWeight
                                    .w600,
                              ),
                            ),
                          )
                        else
                          const Spacer(),
                        _SeletorQuantidade(
                          quantidade: quantidade,
                          erro: quantidadeAcimaDoSaldo,
                          podeDiminuir: _rascunhoCarregado &&
                              !_isSaving &&
                              quantidade > 0,
                          podeEditar: _rascunhoCarregado && !_isSaving,
                          podeAdicionar: podeAdicionar,
                          onDiminuir: () => _decrementar(skuId),
                          onEditar: () => _editarQuantidade(
                            skuId: skuId,
                            nomeProduto: nome,
                            saldoDisponivel: saldo,
                          ),
                          onAdicionar: () => _incrementar(
                            skuId,
                            saldo,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );

              return Row(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  foto,
                  const SizedBox(width: 12),
                  informacoes,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildListaVazia(
      BuildContext context,
      ) {
    return Padding(
      padding:
      const EdgeInsets.symmetric(
        vertical: 60,
      ),
      child: Column(
        children: [
          Icon(
            _filtro ==
                _FiltroInstalacao
                    .selecionados
                ? Icons
                .check_box_outline_blank
                : Icons.search_off_rounded,
            size: 52,
            color: Theme.of(context)
                .colorScheme
                .onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            _filtro ==
                _FiltroInstalacao
                    .selecionados
                ? 'Nenhum produto selecionado.'
                : 'Nenhum produto encontrado.',
            style: Theme.of(context)
                .textTheme
                .titleMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildRascunhoStatus(BuildContext context) {
    final theme = Theme.of(context);

    if (_carregandoRascunho) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Carregando rascunho da visita...',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: .30),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compacto = constraints.maxWidth < 560;

          final mensagem = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _rascunhoErrorMessage ??
                      'Não foi possível carregar o rascunho.',
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          );

          final botao = OutlinedButton.icon(
            onPressed: _carregandoRascunho
                ? null
                : _carregarRascunho,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Tentar novamente'),
          );

          if (compacto) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                mensagem,
                const SizedBox(height: 10),
                botao,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: mensagem),
              const SizedBox(width: 12),
              botao,
            ],
          );
        },
      ),
    );
  }


  Widget _buildBarraInferior(
      BuildContext context, {
        required ExpositorFisico expositor,
        required List<Sku> skus,
        required Map<String, Produto> produtoPorId,
        required Map<String, String> descricaoPorSku,
        required Map<String, int> saldosPorSku,
        required Cliente clienteAtual,
        required int exposicaoAtualCentavos,
      }) {
    final theme = Theme.of(context);

    final novaExposicaoCentavos =
    _valorNovaExposicaoCentavos(skus, clienteAtual);
    final exposicaoAposCentavos =
        exposicaoAtualCentavos + novaExposicaoCentavos;
    final limiteCentavos = clienteAtual.limiteCreditoCentavos;

    final excedenteCentavos =
    exposicaoAposCentavos > limiteCentavos
        ? exposicaoAposCentavos - limiteCentavos
        : 0;

    final estoqueInconsistente =
    _temQuantidadeAcimaDoSaldo(saldosPorSku);

    final podeConferir =
        _rascunhoCarregado &&
            !_isSaving &&
            _totalProdutosSelecionados > 0 &&
            !estoqueInconsistente &&
            excedenteCentavos <= 0;

    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: theme.dividerColor,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error
                            .withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: theme.colorScheme.error
                              .withValues(alpha: .28),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            color: theme.colorScheme.error,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(
                                color: theme.colorScheme.error,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compacto = constraints.maxWidth < 700;

                      final resumo = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$_totalProdutosSelecionados produto(s) • '
                                '$_totalUnidadesSelecionadas unidade(s)',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Nova exposição: '
                                '${formatarCentavos(novaExposicaoCentavos)}',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Após instalação: '
                                '${formatarCentavos(exposicaoAposCentavos)} de '
                                '${formatarCentavos(limiteCentavos)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: excedenteCentavos > 0
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight: excedenteCentavos > 0
                                  ? FontWeight.w700
                                  : null,
                            ),
                          ),
                          if (excedenteCentavos > 0) ...[
                            const SizedBox(height: 3),
                            Text(
                              'Limite excedido em '
                                  '${formatarCentavos(excedenteCentavos)}.',
                              style: TextStyle(
                                color: theme.colorScheme.error,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                          if (estoqueInconsistente) ...[
                            const SizedBox(height: 3),
                            Text(
                              'Há produto com quantidade acima da sua carga.',
                              style: TextStyle(
                                color: theme.colorScheme.error,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      );

                      final botao = FilledButton.icon(
                        onPressed: podeConferir
                            ? () {
                          _abrirConferencia(
                            expositor,
                            skus,
                            produtoPorId,
                            descricaoPorSku,
                            saldosPorSku,
                            clienteAtual,
                            exposicaoAtualCentavos,
                          );
                        }
                            : null,
                        icon: const Icon(Icons.fact_check_outlined),
                        label: const Text('Conferir instalação'),
                      );

                      if (compacto) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            resumo,
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 46,
                              child: botao,
                            ),
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(child: resumo),
                          const SizedBox(width: 20),
                          SizedBox(
                            height: 46,
                            child: botao,
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

}

class _ConferenciaInstalacaoPage extends StatefulWidget {
  final Cliente cliente;
  final ExpositorFisico expositor;
  final List<Sku> skus;
  final Map<String, Produto> produtoPorId;
  final Map<String, int> quantidades;
  final Map<String, int> saldosDisponiveis;
  final int exposicaoAtualCentavos;
  final ValueChanged<Map<String, int>> onQuantidadesChanged;

  const _ConferenciaInstalacaoPage({
    required this.cliente,
    required this.expositor,
    required this.skus,
    required this.produtoPorId,
    required this.quantidades,
    required this.saldosDisponiveis,
    required this.exposicaoAtualCentavos,
    required this.onQuantidadesChanged,
  });

  @override
  State<_ConferenciaInstalacaoPage> createState() =>
      _ConferenciaInstalacaoPageState();
}

class _ConferenciaInstalacaoPageState
    extends State<_ConferenciaInstalacaoPage> {
  late final Map<String, int> _quantidades;

  @override
  void initState() {
    super.initState();

    _quantidades = Map<String, int>.from(
      widget.quantidades,
    );
  }

  int get _totalProdutos {
    return _quantidades.values
        .where((quantidade) => quantidade > 0)
        .length;
  }

  int get _totalUnidades {
    return _quantidades.values.fold(
      0,
          (total, quantidade) => total + quantidade,
    );
  }

  List<Sku> get _skusSelecionados {
    final selecionados = widget.skus.where(
          (sku) {
        final skuId = sku.id;

        if (skuId == null) {
          return false;
        }

        return (_quantidades[skuId] ?? 0) > 0;
      },
    ).toList();

    selecionados.sort(
          (a, b) {
        final produtoA =
        widget.produtoPorId[a.produtoId];

        final produtoB =
        widget.produtoPorId[b.produtoId];

        final nomeA =
            produtoA?.descricao ?? a.codigoInterno;

        final nomeB =
            produtoB?.descricao ?? b.codigoInterno;

        return nomeA
            .toLowerCase()
            .compareTo(
          nomeB.toLowerCase(),
        );
      },
    );

    return selecionados;
  }

  int get _valorNovaExposicaoCentavos {
    var total = 0;

    for (final sku in widget.skus) {
      final skuId = sku.id;
      if (skuId == null) continue;

      total += _valorLiquidoConsignado(
        sku: sku,
        quantidade: _quantidades[skuId] ?? 0,
        comissaoBasisPoints: widget.cliente.comissaoBasisPoints,
      );
    }

    return total;
  }

  int get _exposicaoAposCentavos =>
      widget.exposicaoAtualCentavos +
          _valorNovaExposicaoCentavos;

  int get _excedenteLimiteCentavos {
    final limite = widget.cliente.limiteCreditoCentavos;
    return _exposicaoAposCentavos > limite
        ? _exposicaoAposCentavos - limite
        : 0;
  }

  bool get _temQuantidadeAcimaDoSaldo {
    for (final entry in _quantidades.entries) {
      if (entry.value <= 0) continue;
      if (entry.value >
          (widget.saldosDisponiveis[entry.key] ?? 0)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _editarQuantidade(
      String skuId,
      String nomeProduto,
      ) async {
    final saldo = widget.saldosDisponiveis[skuId] ?? 0;

    final novaQuantidade = await _mostrarDialogoQuantidade(
      context: context,
      nomeProduto: nomeProduto,
      quantidadeAtual: _quantidades[skuId] ?? 0,
      saldoDisponivel: saldo,
    );

    if (novaQuantidade == null || !mounted) return;

    setState(() {
      if (novaQuantidade == 0) {
        _quantidades.remove(skuId);
      } else {
        _quantidades[skuId] = novaQuantidade;
      }
    });

    _notificarAlteracao();
  }

  void _notificarAlteracao() {
    widget.onQuantidadesChanged(
      Map<String, int>.from(
        _quantidades,
      ),
    );
  }

  void _incrementar(
      String skuId,
      ) {
    final atual =
        _quantidades[skuId] ?? 0;

    final saldo =
        widget.saldosDisponiveis[skuId] ?? 0;

    if (atual >= saldo) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saldo <= 0
                ? 'Este produto está sem estoque.'
                : 'Quantidade máxima disponível: $saldo.',
          ),
        ),
      );

      return;
    }

    setState(() {
      _quantidades[skuId] =
          atual + 1;
    });

    _notificarAlteracao();
  }

  void _decrementar(
      String skuId,
      ) {
    final atual =
        _quantidades[skuId] ?? 0;

    if (atual <= 0) {
      return;
    }

    setState(() {
      _quantidades[skuId] =
          atual - 1;
    });

    _notificarAlteracao();
  }

  void _abrirDetalhe(
      Sku sku,
      ) {
    final skuId = sku.id;

    if (skuId == null) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SkuDetailPage(
          skuId: skuId,
        ),
      ),
    );
  }

  void _voltar() {
    Navigator.of(context).pop(false);
  }

  void _confirmar() {
    if (_totalProdutos == 0 ||
        _temQuantidadeAcimaDoSaldo ||
        _excedenteLimiteCentavos > 0) {
      return;
    }

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme =
    Theme.of(context);

    final selecionados =
        _skusSelecionados;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Voltar e editar',
          onPressed: _voltar,
          icon: const Icon(
            Icons.arrow_back,
          ),
        ),
        title: const Text(
          'Conferir instalação',
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding:
              const EdgeInsets.only(
                bottom: 24,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints:
                  const BoxConstraints(
                    maxWidth: 1000,
                  ),
                  child: Padding(
                    padding:
                    const EdgeInsets
                        .fromLTRB(
                      16,
                      16,
                      16,
                      8,
                    ),
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment
                          .stretch,
                      children: [
                        Card(
                          margin:
                          EdgeInsets.zero,
                          child: Padding(
                            padding:
                            const EdgeInsets
                                .all(
                              16,
                            ),
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration:
                                      BoxDecoration(
                                        color: theme
                                            .colorScheme
                                            .primary
                                            .withValues(
                                          alpha: .12,
                                        ),
                                        borderRadius:
                                        BorderRadius
                                            .circular(
                                          12,
                                        ),
                                      ),
                                      child: Icon(
                                        Icons
                                            .fact_check_outlined,
                                        color: theme
                                            .colorScheme
                                            .primary,
                                      ),
                                    ),

                                    const SizedBox(
                                      width: 12,
                                    ),

                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                        CrossAxisAlignment
                                            .start,
                                        children: [
                                          Text(
                                            _nomeClienteParaExibicao(
                                              widget.cliente,
                                            ),
                                            maxLines:
                                            2,
                                            overflow:
                                            TextOverflow
                                                .ellipsis,
                                            style: theme
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                              fontWeight:
                                              FontWeight
                                                  .w700,
                                            ),
                                          ),
                                          const SizedBox(
                                            height: 3,
                                          ),
                                          Text(
                                            '${widget.expositor.numero} — '
                                                '${widget.expositor.modeloNome}',
                                            style: theme
                                                .textTheme
                                                .bodyMedium,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(
                                  height: 14,
                                ),

                                Container(
                                  width:
                                  double.infinity,
                                  padding:
                                  const EdgeInsets
                                      .all(
                                    12,
                                  ),
                                  decoration:
                                  BoxDecoration(
                                    color: theme
                                        .colorScheme
                                        .primary
                                        .withValues(
                                      alpha: .08,
                                    ),
                                    borderRadius:
                                    BorderRadius
                                        .circular(
                                      10,
                                    ),
                                  ),
                                  child: Text(
                                    '$_totalProdutos produto(s) • '
                                        '$_totalUnidades unidade(s)',
                                    style: TextStyle(
                                      color: theme
                                          .colorScheme
                                          .primary,
                                      fontWeight:
                                      FontWeight
                                          .w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        Card(
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Limite de crédito',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                _LinhaResumoFinanceira(
                                  label: 'Exposição atual',
                                  valor: formatarCentavos(
                                    widget.exposicaoAtualCentavos,
                                  ),
                                ),
                                _LinhaResumoFinanceira(
                                  label: 'Nova instalação',
                                  valor: formatarCentavos(
                                    _valorNovaExposicaoCentavos,
                                  ),
                                ),
                                _LinhaResumoFinanceira(
                                  label: 'Após instalação',
                                  valor: formatarCentavos(
                                    _exposicaoAposCentavos,
                                  ),
                                  destaque:
                                  _excedenteLimiteCentavos > 0,
                                ),
                                _LinhaResumoFinanceira(
                                  label: 'Limite aprovado',
                                  valor: formatarCentavos(
                                    widget.cliente.limiteCreditoCentavos,
                                  ),
                                ),
                                if (_excedenteLimiteCentavos > 0) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Limite excedido em '
                                        '${formatarCentavos(_excedenteLimiteCentavos)}.',
                                    style: TextStyle(
                                      color: theme.colorScheme.error,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                                if (_temQuantidadeAcimaDoSaldo) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Há produto com quantidade acima '
                                        'do estoque da sua carga.',
                                    style: TextStyle(
                                      color: theme.colorScheme.error,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(
                          height: 18,
                        ),

                        Text(
                          'Confira os produtos antes de confirmar',
                          style: theme
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                            fontWeight:
                            FontWeight
                                .w700,
                          ),
                        ),

                        const SizedBox(
                          height: 4,
                        ),

                        Text(
                          'Você ainda pode alterar as quantidades.',
                          style: theme
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                            color: theme
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),

                        const SizedBox(
                          height: 14,
                        ),

                        if (selecionados.isEmpty)
                          Padding(
                            padding:
                            const EdgeInsets
                                .symmetric(
                              vertical: 60,
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons
                                      .inventory_2_outlined,
                                  size: 52,
                                  color: theme
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                                const SizedBox(
                                  height: 12,
                                ),
                                const Text(
                                  'Nenhum produto selecionado.',
                                ),
                              ],
                            ),
                          )
                        else
                          LayoutBuilder(
                            builder: (
                                context,
                                constraints,
                                ) {
                              final colunas =
                              constraints
                                  .maxWidth >=
                                  760
                                  ? 2
                                  : 1;

                              const espacamento =
                              12.0;

                              final largura =
                              colunas == 1
                                  ? constraints
                                  .maxWidth
                                  : (constraints
                                  .maxWidth -
                                  espacamento) /
                                  2;

                              return Wrap(
                                spacing:
                                espacamento,
                                runSpacing:
                                espacamento,
                                children:
                                selecionados
                                    .map(
                                      (sku) {
                                    return SizedBox(
                                      width:
                                      largura,
                                      child:
                                      _buildProdutoConferencia(
                                        context,
                                        sku,
                                      ),
                                    );
                                  },
                                ).toList(),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          _buildRodape(
            context,
          ),
        ],
      ),
    );
  }

  Widget _buildProdutoConferencia(
      BuildContext context,
      Sku sku,
      ) {
    final theme =
    Theme.of(context);

    final skuId = sku.id!;

    final produto =
    widget.produtoPorId[sku.produtoId];

    final quantidade =
        _quantidades[skuId] ?? 0;

    final saldo =
        widget.saldosDisponiveis[skuId] ?? 0;

    final nome =
        produto?.descricao ??
            sku.codigoInterno;

    final quantidadeAcimaDoSaldo =
        quantidade > saldo;

    final modelo =
    produto?.modelo?.trim();

    final variacao =
    sku.variacao?.trim();

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: quantidadeAcimaDoSaldo
              ? theme.colorScheme.error
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding:
        const EdgeInsets.all(
          12,
        ),
        child: Row(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            _FotoProduto(
              fotoUrl:
              produto?.fotoUrl,
              onTap: () {
                _abrirDetalhe(
                  sku,
                );
              },
            ),

            const SizedBox(
              width: 12,
            ),

            Expanded(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment
                    .start,
                children: [
                  Text(
                    nome,
                    maxLines: 2,
                    overflow:
                    TextOverflow.ellipsis,
                    style: theme
                        .textTheme
                        .titleSmall
                        ?.copyWith(
                      fontWeight:
                      FontWeight.w700,
                    ),
                  ),

                  if (modelo != null &&
                      modelo.isNotEmpty) ...[
                    const SizedBox(
                      height: 5,
                    ),
                    _LinhaIdentificacao(
                      titulo:
                      'Modelo',
                      valor:
                      modelo,
                    ),
                  ],

                  if (variacao != null &&
                      variacao.isNotEmpty) ...[
                    const SizedBox(
                      height: 3,
                    ),
                    _LinhaIdentificacao(
                      titulo:
                      'Variação',
                      valor:
                      variacao,
                    ),
                  ],

                  const SizedBox(
                    height: 3,
                  ),

                  Text(
                    'Cód. ${sku.codigoInterno}',
                    maxLines: 1,
                    overflow:
                    TextOverflow.ellipsis,
                    style: theme
                        .textTheme
                        .bodySmall
                        ?.copyWith(
                      color: quantidadeAcimaDoSaldo
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: quantidadeAcimaDoSaldo
                          ? FontWeight.w700
                          : null,
                    ),
                  ),

                  const SizedBox(
                    height: 8,
                  ),

                  Text(
                    formatarCentavos(
                      sku.precoVendaCentavos,
                    ),
                    style: theme
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                      fontWeight:
                      FontWeight.w700,
                    ),
                  ),

                  const SizedBox(
                    height: 4,
                  ),

                  Text(
                    quantidadeAcimaDoSaldo
                        ? 'Na sua carga: $saldo un. • '
                        'Selecionado: $quantidade'
                        : 'Na sua carga: $saldo un.',
                    style: theme
                        .textTheme
                        .bodySmall
                        ?.copyWith(
                      color: theme
                          .colorScheme
                          .onSurfaceVariant,
                    ),
                  ),

                  const SizedBox(
                    height: 12,
                  ),

                  Row(
                    mainAxisAlignment:
                    MainAxisAlignment.end,
                    children: [
                      _SeletorQuantidade(
                        quantidade: quantidade,
                        erro: quantidadeAcimaDoSaldo,
                        podeDiminuir: quantidade > 0,
                        podeEditar: true,
                        podeAdicionar: quantidade < saldo,
                        onDiminuir: () => _decrementar(skuId),
                        onEditar: () => _editarQuantidade(
                          skuId,
                          nome,
                        ),
                        onAdicionar: () => _incrementar(skuId),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRodape(
      BuildContext context,
      ) {
    final theme =
    Theme.of(context);

    return Material(
      color:
      theme.scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color:
                theme.dividerColor,
              ),
            ),
          ),
          padding:
          const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints:
              const BoxConstraints(
                maxWidth: 1000,
              ),
              child: LayoutBuilder(
                builder: (
                    context,
                    constraints,
                    ) {
                  final compacto =
                      constraints.maxWidth <
                          600;

                  final resumo = Column(
                    crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                    mainAxisSize:
                    MainAxisSize.min,
                    children: [
                      Text(
                        '$_totalProdutos produto(s) • '
                            '$_totalUnidades unidade(s)',
                        style: theme
                            .textTheme
                            .titleSmall
                            ?.copyWith(
                          fontWeight:
                          FontWeight
                              .w700,
                        ),
                      ),
                      const SizedBox(
                        height: 2,
                      ),
                      Text(
                        'Revise antes de confirmar',
                        style: theme
                            .textTheme
                            .bodySmall,
                      ),
                    ],
                  );

                  final voltar =
                  OutlinedButton.icon(
                    onPressed:
                    _voltar,
                    icon: const Icon(
                      Icons
                          .arrow_back,
                    ),
                    label: const Text(
                      'Voltar e editar',
                    ),
                  );

                  final confirmar =
                  FilledButton.icon(
                    onPressed:
                    _totalProdutos > 0 &&
                        !_temQuantidadeAcimaDoSaldo &&
                        _excedenteLimiteCentavos <= 0
                        ? _confirmar
                        : null,
                    icon: const Icon(
                      Icons
                          .check_circle_outline,
                    ),
                    label: const Text(
                      'Confirmar instalação',
                    ),
                  );

                  if (compacto) {
                    return Column(
                      crossAxisAlignment:
                      CrossAxisAlignment
                          .stretch,
                      children: [
                        resumo,
                        const SizedBox(
                          height: 10,
                        ),
                        SizedBox(
                          height: 46,
                          child:
                          confirmar,
                        ),
                        const SizedBox(
                          height: 8,
                        ),
                        SizedBox(
                          height: 44,
                          child:
                          voltar,
                        ),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(
                        child:
                        resumo,
                      ),
                      voltar,
                      const SizedBox(
                        width: 10,
                      ),
                      SizedBox(
                        height: 46,
                        child:
                        confirmar,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LinhaResumoFinanceira extends StatelessWidget {
  final String label;
  final String valor;
  final bool destaque;

  const _LinhaResumoFinanceira({
    required this.label,
    required this.valor,
    this.destaque = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
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
            valor,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight:
              destaque ? FontWeight.w800 : FontWeight.w600,
              color: destaque ? theme.colorScheme.error : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _LinhaIdentificacao extends StatelessWidget {
  final String titulo;
  final String valor;

  const _LinhaIdentificacao({
    required this.titulo,
    required this.valor,
  });

  @override
  Widget build(BuildContext context) {
    final theme =
    Theme.of(context);

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$titulo: ',
            style: TextStyle(
              color: theme
                  .colorScheme
                  .onSurfaceVariant,
              fontWeight:
              FontWeight.w500,
            ),
          ),
          TextSpan(
            text: valor,
            style: TextStyle(
              color: theme
                  .colorScheme
                  .onSurface,
              fontWeight:
              FontWeight.w600,
            ),
          ),
        ],
      ),
      maxLines: 1,
      overflow:
      TextOverflow.ellipsis,
      style:
      theme.textTheme.bodyMedium,
    );
  }
}

class _FotoProduto extends StatelessWidget {
  final String? fotoUrl;
  final VoidCallback? onTap;

  const _FotoProduto({
    required this.fotoUrl,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme =
    Theme.of(context);

    return Tooltip(
      message: 'Ver detalhes do produto',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius:
          BorderRadius.circular(11),
          onTap: onTap,
          child: Stack(
            children: [
              ClipRRect(
                borderRadius:
                BorderRadius.circular(11),
                child: Container(
                  width: 92,
                  height: 92,
                  color: theme
                      .colorScheme
                      .surfaceContainerHighest,
                  child: fotoUrl != null &&
                      fotoUrl!
                          .trim()
                          .isNotEmpty
                      ? Image.network(
                    fotoUrl!,
                    fit: BoxFit.cover,
                    cacheWidth: 184,
                    errorBuilder:
                        (_, __, ___) =>
                        _placeholder(
                          context,
                        ),
                  )
                      : _placeholder(
                    context,
                  ),
                ),
              ),

              Positioned(
                right: 5,
                bottom: 5,
                child: Container(
                  width: 27,
                  height: 27,
                  decoration: BoxDecoration(
                    color: theme
                        .colorScheme
                        .surface
                        .withValues(
                      alpha: .90,
                    ),
                    borderRadius:
                    BorderRadius.circular(
                      8,
                    ),
                    border: Border.all(
                      color: theme
                          .colorScheme
                          .outline
                          .withValues(
                        alpha: .25,
                      ),
                    ),
                  ),
                  child: Icon(
                    Icons
                        .zoom_in_rounded,
                    size: 18,
                    color: theme
                        .colorScheme
                        .primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder(
      BuildContext context,
      ) {
    return Icon(
      Icons.inventory_2_outlined,
      size: 34,
      color: Theme.of(context)
          .colorScheme
          .onSurfaceVariant,
    );
  }
}

class _SeletorQuantidade extends StatelessWidget {
  final int quantidade;
  final bool erro;
  final bool podeDiminuir;
  final bool podeEditar;
  final bool podeAdicionar;
  final VoidCallback onDiminuir;
  final VoidCallback onEditar;
  final VoidCallback onAdicionar;

  const _SeletorQuantidade({
    required this.quantidade,
    required this.erro,
    required this.podeDiminuir,
    required this.podeEditar,
    required this.podeAdicionar,
    required this.onDiminuir,
    required this.onEditar,
    required this.onAdicionar,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BotaoQuantidade(
          icon: Icons.remove,
          enabled: podeDiminuir,
          onPressed: onDiminuir,
        ),
        Tooltip(
          message: 'Toque para digitar a quantidade',
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: podeEditar ? onEditar : null,
            child: Container(
              width: 46,
              height: 38,
              alignment: Alignment.center,
              margin: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                border: Border.all(
                  color: erro
                      ? theme.colorScheme.error
                      : theme.colorScheme.outline
                      .withValues(alpha: .45),
                ),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                '$quantidade',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        _BotaoQuantidade(
          icon: Icons.add,
          enabled: podeAdicionar,
          destaque: true,
          onPressed: onAdicionar,
        ),
      ],
    );
  }
}

class _BotaoQuantidade extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final bool destaque;
  final VoidCallback onPressed;

  const _BotaoQuantidade({
    required this.icon,
    required this.enabled,
    required this.onPressed,
    this.destaque = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme =
    Theme.of(context);

    return SizedBox(
      width: 38,
      height: 38,
      child: IconButton(
        padding: EdgeInsets.zero,
        onPressed:
        enabled ? onPressed : null,
        style: IconButton.styleFrom(
          backgroundColor:
          destaque && enabled
              ? theme
              .colorScheme
              .primary
              : theme
              .colorScheme
              .surfaceContainerHighest,
          foregroundColor:
          destaque && enabled
              ? theme
              .colorScheme
              .onPrimary
              : null,
          shape:
          RoundedRectangleBorder(
            borderRadius:
            BorderRadius.circular(
              9,
            ),
          ),
        ),
        icon: Icon(
          icon,
          size: 20,
        ),
      ),
    );
  }
}

class _InfoExpositor extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoExpositor({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize:
      MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 22,
          color: Theme.of(context)
              .colorScheme
              .onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall,
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                fontWeight:
                FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
