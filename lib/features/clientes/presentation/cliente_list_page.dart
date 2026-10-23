import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/br_formatters.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../auth/presentation/usuario_providers.dart';
import '../../visitas/presentation/visita_cliente_selector_page.dart';
import '../domain/cliente.dart';
import 'cliente_detail_page.dart';
import 'cliente_form_page.dart';
import 'cliente_providers.dart';

enum _FiltroRapido { todos, precisaAcao, atrasadas, semAgendamento }

enum _FiltroVisita { todas, atrasadas, hoje, estaSemana, semAgendamento }

enum _OrdenacaoCliente {
  prioridade,
  proximaVisita,
  maisAtrasadas,
  nomeAZ,
  nomeZA,
  cidadeAZ,
}

enum _AcaoCliente { detalhes, agenda, whatsapp, copiarDocumento }

const _limiteInicial = 50;
const _debounceBusca = Duration(milliseconds: 250);

class ClienteListPage extends ConsumerStatefulWidget {
  const ClienteListPage({super.key});

  @override
  ConsumerState<ClienteListPage> createState() => _ClienteListPageState();
}

class _ClienteListPageState extends ConsumerState<ClienteListPage> {
  final _buscaController = TextEditingController();
  final _buscaFocusNode = FocusNode();
  Timer? _buscaDebounce;

  String _busca = '';
  bool _somentePrecisaAcao = false;
  StatusCadastro? _statusCadastro;
  StatusOperacional? _statusOperacional;
  StatusFinanceiro? _statusFinanceiro;
  _FiltroVisita _filtroVisita = _FiltroVisita.todas;
  String? _vendedorId;
  String? _cidadeUf;
  bool _somenteSemVendedor = false;
  _OrdenacaoCliente _ordenacao = _OrdenacaoCliente.prioridade;
  int _limite = _limiteInicial;

  /// Cache dos itens derivados. Só é refeito quando a lista de clientes,
  /// a lista de usuários ou o dia mudam — não a cada tecla digitada.
  _DadosClientes? _cache;

  @override
  void dispose() {
    _buscaDebounce?.cancel();
    _buscaController.dispose();
    _buscaFocusNode.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Dados derivados
  // ---------------------------------------------------------------------------

  _DadosClientes _dadosPara({
    required List<Cliente> clientes,
    required Object usuariosRef,
    required Map<String, String> nomesUsuarios,
    required bool usuariosCarregando,
  }) {
    final hoje = _somenteData(DateTime.now());
    final cache = _cache;

    if (cache != null &&
        identical(cache.clientesRef, clientes) &&
        identical(cache.usuariosRef, usuariosRef) &&
        cache.usuariosCarregando == usuariosCarregando &&
        cache.dia == hoje) {
      return cache;
    }

    final itens = [
      for (final cliente in clientes)
        _ClienteItem.from(cliente, nomesUsuarios, usuariosCarregando),
    ];

    final cidades = itens
        .map((item) => item.localizacao)
        .where((value) => value != 'Não informado')
        .toSet()
        .toList()
      ..sort((a, b) => _normalizar(a).compareTo(_normalizar(b)));

    return _cache = _DadosClientes(
      clientesRef: clientes,
      usuariosRef: usuariosRef,
      usuariosCarregando: usuariosCarregando,
      dia: hoje,
      itens: itens,
      contagens: _ContagensClientes.from(itens),
      cidades: cidades,
    );
  }

  // ---------------------------------------------------------------------------
  // Navegação e ações
  // ---------------------------------------------------------------------------

  Future<void> _recarregar() async {
    ref.invalidate(clientesListProvider);
    ref.invalidate(usuariosListProvider);
    await ref.read(clientesListProvider.future);
  }

  Future<void> _abrirNovoCliente() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ClienteFormPage()),
    );
    if (!mounted) return;
    ref.invalidate(clientesListProvider);
  }

  /// Abre a agenda já filtrada neste cliente.
  Future<void> _abrirAgenda(Cliente cliente) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VisitaClienteSelectorPage(clienteIdInicial: cliente.id),
      ),
    );
    if (!mounted) return;
    // A visita pode ter alterado a próxima data prevista.
    ref.invalidate(clientesListProvider);
  }

  void _abrirCliente(Cliente cliente) {
    final id = cliente.id;
    if (id == null || id.isEmpty) {
      _mostrarMensagem('Não foi possível abrir este cliente.', erro: true);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ClienteDetailPage(clienteId: id)),
    );
  }

  Future<void> _abrirWhatsApp(Cliente cliente) async {
    final telefone = _telefoneWhatsApp(cliente.telefoneResponsavel);
    if (telefone.isEmpty) {
      _mostrarMensagem('Telefone do cliente não cadastrado ou inválido.');
      return;
    }

    final responsavel = cliente.nomeResponsavel.trim();
    final saudacao = responsavel.isEmpty ? 'Olá' : 'Olá, $responsavel';
    final mensagem = Uri.encodeComponent('$saudacao. Aqui é da NEXT GEAR.');
    final uri = Uri.parse('https://wa.me/$telefone?text=$mensagem');

    bool abriu;
    try {
      abriu = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      abriu = false;
    }

    if (!abriu && mounted) {
      _mostrarMensagem('Não foi possível abrir o WhatsApp.', erro: true);
    }
  }

  Future<void> _copiarDocumento(Cliente cliente) async {
    final documento = cliente.cpfCnpj.trim();
    if (documento.isEmpty) {
      _mostrarMensagem('Este cliente não possui CPF/CNPJ cadastrado.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: documento));
    if (!mounted) return;
    _mostrarMensagem('CPF/CNPJ copiado.');
  }

  void _mostrarMensagem(String texto, {bool erro = false}) {
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(texto),
          backgroundColor: erro ? scheme.error : null,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _executarAcao(_AcaoCliente acao, Cliente cliente) {
    switch (acao) {
      case _AcaoCliente.detalhes:
        _abrirCliente(cliente);
      case _AcaoCliente.agenda:
        _abrirAgenda(cliente);
      case _AcaoCliente.whatsapp:
        _abrirWhatsApp(cliente);
      case _AcaoCliente.copiarDocumento:
        _copiarDocumento(cliente);
    }
  }

  // ---------------------------------------------------------------------------
  // Busca e filtros
  // ---------------------------------------------------------------------------

  void _onBuscaChanged(String value) {
    _buscaDebounce?.cancel();
    _buscaDebounce = Timer(_debounceBusca, () {
      if (!mounted) return;
      setState(() {
        _busca = value.trim();
        _limite = _limiteInicial;
      });
    });
  }

  void _onBuscaSubmitted(String value) {
    _buscaDebounce?.cancel();
    setState(() {
      _busca = value.trim();
      _limite = _limiteInicial;
    });
  }

  void _limparBusca() {
    _buscaDebounce?.cancel();
    _buscaController.clear();
    setState(() {
      _busca = '';
      _limite = _limiteInicial;
    });
    _buscaFocusNode.requestFocus();
  }

  /// Único ponto que zera os filtros. Deve ser chamado dentro de setState.
  /// Ao adicionar um filtro novo, basta incluí-lo aqui.
  void _resetarFiltros({bool limparBusca = true}) {
    if (limparBusca) {
      _buscaDebounce?.cancel();
      _buscaController.clear();
      _busca = '';
    }
    _somentePrecisaAcao = false;
    _statusCadastro = null;
    _statusOperacional = null;
    _statusFinanceiro = null;
    _filtroVisita = _FiltroVisita.todas;
    _vendedorId = null;
    _cidadeUf = null;
    _somenteSemVendedor = false;
    _ordenacao = _OrdenacaoCliente.prioridade;
    _limite = _limiteInicial;
  }

  void _limparFiltros({bool manterBusca = false}) {
    setState(() => _resetarFiltros(limparBusca: !manterBusca));
  }

  void _aplicarAtalho({
    StatusCadastro? cadastro,
    StatusOperacional? operacional,
    StatusFinanceiro? financeiro,
    _FiltroVisita visita = _FiltroVisita.todas,
    bool semVendedor = false,
  }) {
    setState(() {
      _resetarFiltros();
      _statusCadastro = cadastro;
      _statusOperacional = operacional;
      _statusFinanceiro = financeiro;
      _filtroVisita = visita;
      _somenteSemVendedor = semVendedor;
    });
  }

  /// Os chips rápidos controlam as MESMAS variáveis dos filtros avançados,
  /// então nunca entram em conflito.
  _FiltroRapido? get _filtroRapidoAtual {
    if (_somentePrecisaAcao) return _FiltroRapido.precisaAcao;
    return switch (_filtroVisita) {
      _FiltroVisita.todas => _FiltroRapido.todos,
      _FiltroVisita.atrasadas => _FiltroRapido.atrasadas,
      _FiltroVisita.semAgendamento => _FiltroRapido.semAgendamento,
      _FiltroVisita.hoje || _FiltroVisita.estaSemana => null,
    };
  }

  void _selecionarFiltroRapido(_FiltroRapido filtro) {
    setState(() {
      _somentePrecisaAcao = filtro == _FiltroRapido.precisaAcao;
      _filtroVisita = switch (filtro) {
        _FiltroRapido.atrasadas => _FiltroVisita.atrasadas,
        _FiltroRapido.semAgendamento => _FiltroVisita.semAgendamento,
        _FiltroRapido.todos || _FiltroRapido.precisaAcao => _FiltroVisita.todas,
      };
      _limite = _limiteInicial;
    });
  }

  List<_ClienteItem> _aplicarFiltros(List<_ClienteItem> itens) {
    Iterable<_ClienteItem> resultado = itens;

    final termo = _normalizar(_busca);
    if (termo.isNotEmpty) {
      // Só compara com CPF/CNPJ/telefone quando o termo parece um número,
      // evitando falsos positivos em buscas como "loja 2".
      final buscaNumerica = _pareceNumero.hasMatch(_busca);
      final termoNumerico = _somenteNumeros(_busca);

      resultado = resultado.where((item) {
        if (item.textoBusca.contains(termo)) return true;
        return buscaNumerica &&
            termoNumerico.isNotEmpty &&
            (item.documentoNumeros.contains(termoNumerico) ||
                item.telefoneNumeros.contains(termoNumerico));
      });
    }

    if (_somentePrecisaAcao) {
      resultado = resultado.where((item) => item.prioridade > 0);
    }
    if (_statusCadastro != null) {
      resultado = resultado.where(
            (item) => item.cliente.statusCadastro == _statusCadastro,
      );
    }
    if (_statusOperacional != null) {
      resultado = resultado.where(
            (item) => item.cliente.statusOperacional == _statusOperacional,
      );
    }
    if (_statusFinanceiro != null) {
      resultado = resultado.where(
            (item) => item.cliente.statusFinanceiro == _statusFinanceiro,
      );
    }
    if (_vendedorId != null) {
      resultado = resultado.where(
            (item) => item.cliente.vendedorResponsavelId == _vendedorId,
      );
    }
    if (_somenteSemVendedor) {
      resultado = resultado.where((item) => item.semVendedor);
    }
    if (_cidadeUf != null) {
      resultado = resultado.where((item) => item.localizacao == _cidadeUf);
    }

    resultado = switch (_filtroVisita) {
      _FiltroVisita.todas => resultado,
      _FiltroVisita.atrasadas => resultado.where(
            (item) => _visitaAtrasada(item.cliente.proximaVisitaEm),
      ),
      _FiltroVisita.hoje => resultado.where(
            (item) => _visitaHoje(item.cliente.proximaVisitaEm),
      ),
      _FiltroVisita.estaSemana => resultado.where(
            (item) => _visitaNestaSemana(item.cliente.proximaVisitaEm),
      ),
      _FiltroVisita.semAgendamento => resultado.where(
            (item) => item.cliente.proximaVisitaEm == null,
      ),
    };

    final lista = resultado.toList();
    _ordenar(lista, _ordenacao);
    return lista;
  }

  int get _quantidadeFiltrosAvancados =>
      (_statusCadastro == null ? 0 : 1) +
          (_statusOperacional == null ? 0 : 1) +
          (_statusFinanceiro == null ? 0 : 1) +
          (_filtroVisita == _FiltroVisita.todas ? 0 : 1) +
          (_vendedorId == null ? 0 : 1) +
          (_cidadeUf == null ? 0 : 1) +
          (_somenteSemVendedor ? 1 : 0);

  Future<void> _abrirFiltrosAvancados(
      List<_OpcaoFiltro> vendedores,
      List<String> cidades,
      ) async {
    var cadastro = _statusCadastro;
    var operacional = _statusOperacional;
    var financeiro = _statusFinanceiro;
    var visita = _filtroVisita;
    var vendedorId = _vendedorId;
    var cidadeUf = _cidadeUf;
    var somenteSemVendedor = _somenteSemVendedor;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, modalSetState) {
            return SafeArea(
              top: false,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Material(
                    color: _neutralSurface(context),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        14,
                        20,
                        20 + MediaQuery.viewInsetsOf(context).bottom,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Center(
                            child: Container(
                              width: 42,
                              height: 4,
                              decoration: BoxDecoration(
                                color: _neutralOutline(context),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Filtros avançados',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Fechar',
                                onPressed: () => Navigator.pop(sheetContext),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final largura = constraints.maxWidth >= 560
                                  ? (constraints.maxWidth - 12) / 2
                                  : constraints.maxWidth;
                              return Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  SizedBox(
                                    width: largura,
                                    child: _NullableDropdown<StatusCadastro>(
                                      label: 'Status do cadastro',
                                      icon: Icons.assignment_ind_outlined,
                                      value: cadastro,
                                      allLabel: 'Todos',
                                      values: StatusCadastro.values,
                                      labelFor: (value) =>
                                      _cadastroInfo(value).$1,
                                      onChanged: (value) =>
                                          modalSetState(() => cadastro = value),
                                    ),
                                  ),
                                  SizedBox(
                                    width: largura,
                                    child: _NullableDropdown<StatusOperacional>(
                                      label: 'Situação operacional',
                                      icon: Icons.storefront_outlined,
                                      value: operacional,
                                      allLabel: 'Todas',
                                      values: StatusOperacional.values,
                                      labelFor: (value) =>
                                      _operacionalInfo(value).$1,
                                      onChanged: (value) => modalSetState(
                                            () => operacional = value,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: largura,
                                    child: _NullableDropdown<StatusFinanceiro>(
                                      label: 'Situação financeira',
                                      icon:
                                      Icons.account_balance_wallet_outlined,
                                      value: financeiro,
                                      allLabel: 'Todas',
                                      values: StatusFinanceiro.values,
                                      labelFor: (value) =>
                                      _financeiroInfo(value).$1,
                                      onChanged: (value) => modalSetState(
                                            () => financeiro = value,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: largura,
                                    child:
                                    DropdownButtonFormField<_FiltroVisita>(
                                      key: ValueKey('agenda_$visita'),
                                      initialValue: visita,
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Agenda de visitas',
                                        prefixIcon: Icon(Icons.event_outlined),
                                      ),
                                      items: [
                                        for (final value in _FiltroVisita.values)
                                          DropdownMenuItem(
                                            value: value,
                                            child:
                                            Text(_filtroVisitaLabel(value)),
                                          ),
                                      ],
                                      onChanged: (value) {
                                        if (value != null) {
                                          modalSetState(() => visita = value);
                                        }
                                      },
                                    ),
                                  ),
                                  SizedBox(
                                    width: largura,
                                    child: _DropdownString(
                                      label: 'Vendedor responsável',
                                      icon: Icons.badge_outlined,
                                      value: vendedorId,
                                      allLabel: 'Todos os vendedores',
                                      options: vendedores,
                                      onChanged: (value) => modalSetState(() {
                                        vendedorId = value;
                                        if (value != null) {
                                          somenteSemVendedor = false;
                                        }
                                      }),
                                    ),
                                  ),
                                  SizedBox(
                                    width: largura,
                                    child: _DropdownString(
                                      label: 'Cidade/UF',
                                      icon: Icons.location_city_outlined,
                                      value: cidadeUf,
                                      allLabel: 'Todas as cidades',
                                      options: [
                                        for (final cidade in cidades)
                                          _OpcaoFiltro(
                                            id: cidade,
                                            label: cidade,
                                          ),
                                      ],
                                      onChanged: (value) =>
                                          modalSetState(() => cidadeUf = value),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Somente clientes sem vendedor'),
                            subtitle: const Text(
                              'Mostra cadastros que ainda precisam de responsável.',
                            ),
                            value: somenteSemVendedor,
                            onChanged: (value) => modalSetState(() {
                              somenteSemVendedor = value;
                              if (value) vendedorId = null;
                            }),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () {
                                    modalSetState(() {
                                      cadastro = null;
                                      operacional = null;
                                      financeiro = null;
                                      visita = _FiltroVisita.todas;
                                      vendedorId = null;
                                      cidadeUf = null;
                                      somenteSemVendedor = false;
                                    });
                                  },
                                  child: const Text('Limpar'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () {
                                    setState(() {
                                      _statusCadastro = cadastro;
                                      _statusOperacional = operacional;
                                      _statusFinanceiro = financeiro;
                                      _filtroVisita = visita;
                                      _vendedorId = vendedorId;
                                      _cidadeUf = cidadeUf;
                                      _somenteSemVendedor = somenteSemVendedor;
                                      _limite = _limiteInicial;
                                    });
                                    Navigator.pop(sheetContext);
                                  },
                                  child: const Text('Aplicar filtros'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final clientesAsync = ref.watch(clientesListProvider);
    final usuariosAsync = ref.watch(usuariosListProvider);
    final telaLarga = MediaQuery.sizeOf(context).width >= 700;
    final temClientes = clientesAsync.value?.isNotEmpty == true;

    return Scaffold(
      floatingActionButton: !telaLarga && temClientes
          ? FloatingActionButton.extended(
        heroTag: 'clientes_novo_fab',
        onPressed: _abrirNovoCliente,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Novo cliente'),
      )
          : null,
      body: clientesAsync.when(
        data: (clientes) {
          if (clientes.isEmpty) {
            return _EmptyClientesState(onCreate: _abrirNovoCliente);
          }

          final usuarios = usuariosAsync.value ?? const [];
          final usuariosCarregando =
              usuariosAsync.isLoading && usuariosAsync.value == null;

          // Barato: a lista de usuários é pequena.
          final nomesUsuarios = <String, String>{
            for (final usuario in usuarios) usuario.uid: usuario.nome,
          };
          final vendedores = [
            for (final usuario in usuarios)
              _OpcaoFiltro(id: usuario.uid, label: usuario.nome),
          ]..sort(
                (a, b) => _normalizar(a.label).compareTo(_normalizar(b.label)),
          );

          final dados = _dadosPara(
            clientes: clientes,
            usuariosRef: usuarios,
            nomesUsuarios: nomesUsuarios,
            usuariosCarregando: usuariosCarregando,
          );

          final filtrados = _aplicarFiltros(dados.itens);
          final exibidos = filtrados.take(_limite).toList();
          final contagens = dados.contagens;

          return SafeArea(
            child: ResponsiveCenter(
              maxWidth: 1280,
              child: RefreshIndicator(
                onRefresh: _recarregar,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final desktop = constraints.maxWidth >= 900;
                    return CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            desktop ? 20 : 16,
                            18,
                            desktop ? 20 : 16,
                            100,
                          ),
                          sliver: SliverList(
                            delegate: SliverChildListDelegate([
                              _ClientesIntro(
                                total: clientes.length,
                                onRefresh: _recarregar,
                                onCreate: telaLarga ? _abrirNovoCliente : null,
                              ),
                              const SizedBox(height: 18),
                              _MetricasClientes(
                                contagens: contagens,
                                onEmAnalise: () => _aplicarAtalho(
                                  cadastro: StatusCadastro.emAnalise,
                                ),
                                onAguardandoInstalacao: () => _aplicarAtalho(
                                  operacional:
                                  StatusOperacional.aguardandoInstalacao,
                                ),
                                onAtrasadas: () => _aplicarAtalho(
                                  visita: _FiltroVisita.atrasadas,
                                ),
                                onBloqueados: () => _aplicarAtalho(
                                  financeiro: StatusFinanceiro.bloqueado,
                                ),
                              ),
                              const SizedBox(height: 14),
                              _PendenciasClientes(
                                ativosSemVisita: contagens.ativosSemVisita,
                                semVendedor: contagens.semVendedor,
                                onAtivosSemVisita: () => _aplicarAtalho(
                                  operacional: StatusOperacional.ativo,
                                  visita: _FiltroVisita.semAgendamento,
                                ),
                                onSemVendedor: () =>
                                    _aplicarAtalho(semVendedor: true),
                              ),
                              const SizedBox(height: 14),
                              _ControlesClientes(
                                controller: _buscaController,
                                focusNode: _buscaFocusNode,
                                filtroRapido: _filtroRapidoAtual,
                                ordenacao: _ordenacao,
                                contagens: contagens,
                                quantidadeFiltros: _quantidadeFiltrosAvancados,
                                onBuscaChanged: _onBuscaChanged,
                                onBuscaSubmitted: _onBuscaSubmitted,
                                onClearSearch: _limparBusca,
                                onFiltroRapido: _selecionarFiltroRapido,
                                onOrdenacao: (value) => setState(() {
                                  _ordenacao = value;
                                  _limite = _limiteInicial;
                                }),
                                onFiltros: () => _abrirFiltrosAvancados(
                                  vendedores,
                                  dados.cidades,
                                ),
                              ),
                              _FiltrosAtivos(
                                statusCadastro: _statusCadastro,
                                statusOperacional: _statusOperacional,
                                statusFinanceiro: _statusFinanceiro,
                                filtroVisita: _filtroVisita,
                                vendedorNome: _vendedorId == null
                                    ? null
                                    : _vendedorLabel(
                                  _vendedorId,
                                  nomesUsuarios,
                                  usuariosCarregando,
                                ),
                                cidadeUf: _cidadeUf,
                                somenteSemVendedor: _somenteSemVendedor,
                                onClear: () =>
                                    _limparFiltros(manterBusca: true),
                              ),
                              const SizedBox(height: 14),
                              _ResultadoCabecalho(
                                exibidos: exibidos.length,
                                total: filtrados.length,
                              ),
                              const SizedBox(height: 10),
                              if (filtrados.isEmpty)
                                _FilteredEmptyState(
                                  onClearFilters: _limparFiltros,
                                )
                              else if (desktop)
                                _DesktopClientesTable(
                                  itens: exibidos,
                                  onClienteTap: _abrirCliente,
                                  onAcao: _executarAcao,
                                )
                              else
                                _MobileClientesList(
                                  itens: exibidos,
                                  onClienteTap: _abrirCliente,
                                  onAcao: _executarAcao,
                                ),
                              if (exibidos.length < filtrados.length) ...[
                                const SizedBox(height: 16),
                                Center(
                                  child: OutlinedButton.icon(
                                    onPressed: () => setState(
                                          () => _limite += _limiteInicial,
                                    ),
                                    icon: const Icon(Icons.expand_more_rounded),
                                    label: const Text('Mostrar mais clientes'),
                                  ),
                                ),
                              ],
                            ]),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
        loading: () => const _ClientesLoadingState(),
        error: (error, stack) {
          debugPrint('Erro ao carregar clientes: $error\n$stack');
          return _ClientesErrorState(onRetry: _recarregar);
        },
      ),
    );
  }
}

// =============================================================================
// Modelos internos
// =============================================================================

class _ClienteItem {
  final Cliente cliente;
  final String nome;
  final String localizacao;
  final String vendedorNome;
  final bool semVendedor;
  final int prioridade;

  // Campos pré-calculados para busca e ordenação.
  final String textoBusca;
  final String documentoNumeros;
  final String telefoneNumeros;
  final String nomeOrdenacao;
  final String localizacaoOrdenacao;

  const _ClienteItem._({
    required this.cliente,
    required this.nome,
    required this.localizacao,
    required this.vendedorNome,
    required this.semVendedor,
    required this.prioridade,
    required this.textoBusca,
    required this.documentoNumeros,
    required this.telefoneNumeros,
    required this.nomeOrdenacao,
    required this.localizacaoOrdenacao,
  });

  factory _ClienteItem.from(
      Cliente cliente,
      Map<String, String> nomesUsuarios,
      bool usuariosCarregando,
      ) {
    final nome = _nomeExibicao(cliente);
    final localizacao = _cidadeUfLabel(cliente);
    final vendedorNome = _vendedorLabel(
      cliente.vendedorResponsavelId,
      nomesUsuarios,
      usuariosCarregando,
    );

    return _ClienteItem._(
      cliente: cliente,
      nome: nome,
      localizacao: localizacao,
      vendedorNome: vendedorNome,
      semVendedor: _clienteSemVendedor(cliente),
      prioridade: _prioridadeCliente(cliente),
      textoBusca: _normalizar(
        [
          nome,
          cliente.nome,
          localizacao,
          vendedorNome,
          cliente.telefoneResponsavel,
        ].join('\n'),
      ),
      documentoNumeros: _somenteNumeros(cliente.cpfCnpj),
      telefoneNumeros: _somenteNumeros(cliente.telefoneResponsavel),
      nomeOrdenacao: _normalizar(nome),
      localizacaoOrdenacao: _normalizar(localizacao),
    );
  }
}

class _DadosClientes {
  final List<Cliente> clientesRef;
  final Object usuariosRef;
  final bool usuariosCarregando;
  final DateTime dia;
  final List<_ClienteItem> itens;
  final _ContagensClientes contagens;
  final List<String> cidades;

  const _DadosClientes({
    required this.clientesRef,
    required this.usuariosRef,
    required this.usuariosCarregando,
    required this.dia,
    required this.itens,
    required this.contagens,
    required this.cidades,
  });
}

class _OpcaoFiltro {
  final String id;
  final String label;

  const _OpcaoFiltro({required this.id, required this.label});
}

// =============================================================================
// Widgets
// =============================================================================

class _ClientesIntro extends StatelessWidget {
  final int total;
  final Future<void> Function() onRefresh;
  final VoidCallback? onCreate;

  const _ClientesIntro({
    required this.total,
    required this.onRefresh,
    this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compacto = constraints.maxWidth < 700;

        final identidade = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: .13),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                Icons.people_alt_outlined,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gestão de clientes',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$total ${total == 1 ? 'cliente cadastrado' : 'clientes cadastrados'} · acompanhe cadastros, agenda e situação operacional.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

        if (compacto) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: identidade),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Atualizar',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: identidade),
            const SizedBox(width: 20),
            OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Atualizar'),
            ),
            if (onCreate != null) ...[
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Novo cliente'),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _MetricasClientes extends StatelessWidget {
  final _ContagensClientes contagens;
  final VoidCallback onEmAnalise;
  final VoidCallback onAguardandoInstalacao;
  final VoidCallback onAtrasadas;
  final VoidCallback onBloqueados;

  const _MetricasClientes({
    required this.contagens,
    required this.onEmAnalise,
    required this.onAguardandoInstalacao,
    required this.onAtrasadas,
    required this.onBloqueados,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final colunas = constraints.maxWidth >= 1050
            ? 4
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        final largura = (constraints.maxWidth - (colunas - 1) * 12) / colunas;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: largura,
              child: _MetricaCard(
                label: 'Em análise',
                value: contagens.emAnalise,
                hint: 'Cadastros aguardando decisão',
                icon: Icons.assignment_outlined,
                color: Colors.lightBlue,
                onTap: onEmAnalise,
              ),
            ),
            SizedBox(
              width: largura,
              child: _MetricaCard(
                label: 'Aguardando instalação',
                value: contagens.aguardandoInstalacao,
                hint: 'Clientes prontos para instalar',
                icon: Icons.handyman_outlined,
                color: Colors.orange,
                onTap: onAguardandoInstalacao,
              ),
            ),
            SizedBox(
              width: largura,
              child: _MetricaCard(
                label: 'Visitas atrasadas',
                value: contagens.atrasadas,
                hint: 'Agenda fora do prazo previsto',
                icon: Icons.event_busy_outlined,
                color: Colors.red,
                onTap: onAtrasadas,
              ),
            ),
            SizedBox(
              width: largura,
              child: _MetricaCard(
                label: 'Financeiro bloqueado',
                value: contagens.bloqueados,
                hint: 'Clientes com operação bloqueada',
                icon: Icons.lock_outline_rounded,
                color: Colors.red,
                onTap: onBloqueados,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MetricaCard extends StatelessWidget {
  final String label;
  final int value;
  final String hint;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _MetricaCard({
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '$value',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendenciasClientes extends StatelessWidget {
  final int ativosSemVisita;
  final int semVendedor;
  final VoidCallback onAtivosSemVisita;
  final VoidCallback onSemVendedor;

  const _PendenciasClientes({
    required this.ativosSemVisita,
    required this.semVendedor,
    required this.onAtivosSemVisita,
    required this.onSemVendedor,
  });

  @override
  Widget build(BuildContext context) {
    if (ativosSemVisita == 0 && semVendedor == 0) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final pendencias = <Widget>[
      if (ativosSemVisita > 0)
        _PendenciaItem(
          text:
          '$ativosSemVisita ${ativosSemVisita == 1 ? 'cliente ativo sem próxima visita' : 'clientes ativos sem próxima visita'}',
          onTap: onAtivosSemVisita,
        ),
      if (semVendedor > 0)
        _PendenciaItem(
          text:
          '$semVendedor ${semVendedor == 1 ? 'cliente sem vendedor responsável' : 'clientes sem vendedor responsável'}',
          onTap: onSemVendedor,
        ),
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange,
                  size: 21,
                ),
                const SizedBox(width: 8),
                Text(
                  'Pendências que precisam de atenção',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 700 && pendencias.length > 1) {
                  return Row(
                    children: [
                      Expanded(child: pendencias[0]),
                      const SizedBox(width: 12),
                      Expanded(child: pendencias[1]),
                    ],
                  );
                }
                return Column(
                  children: [
                    for (var i = 0; i < pendencias.length; i++) ...[
                      pendencias[i],
                      if (i != pendencias.length - 1)
                        const SizedBox(height: 7),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PendenciaItem extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _PendenciaItem({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.orange.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.circle, size: 8, color: Colors.orange),
              const SizedBox(width: 9),
              Expanded(child: Text(text)),
              const Icon(Icons.chevron_right_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _ControlesClientes extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final _FiltroRapido? filtroRapido;
  final _OrdenacaoCliente ordenacao;
  final _ContagensClientes contagens;
  final int quantidadeFiltros;
  final ValueChanged<String> onBuscaChanged;
  final ValueChanged<String> onBuscaSubmitted;
  final VoidCallback onClearSearch;
  final ValueChanged<_FiltroRapido> onFiltroRapido;
  final ValueChanged<_OrdenacaoCliente> onOrdenacao;
  final VoidCallback onFiltros;

  const _ControlesClientes({
    required this.controller,
    required this.focusNode,
    required this.filtroRapido,
    required this.ordenacao,
    required this.contagens,
    required this.quantidadeFiltros,
    required this.onBuscaChanged,
    required this.onBuscaSubmitted,
    required this.onClearSearch,
    required this.onFiltroRapido,
    required this.onOrdenacao,
    required this.onFiltros,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // O botão de limpar reage ao texto digitado na hora,
            // sem esperar o debounce da busca.
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textInputAction: TextInputAction.search,
                  onChanged: onBuscaChanged,
                  onSubmitted: onBuscaSubmitted,
                  decoration: InputDecoration(
                    hintText: 'Buscar cliente, CPF/CNPJ, telefone...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: value.text.isEmpty
                        ? null
                        : IconButton(
                      tooltip: 'Limpar busca',
                      onPressed: onClearSearch,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // Em celulares estreitos, empilha os dois controles para evitar
            // overflow horizontal.
            LayoutBuilder(
              builder: (context, constraints) {
                final empilhar = constraints.maxWidth < 420;

                final filtrosButton = SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: onFiltros,
                    icon: const Icon(Icons.tune_rounded, size: 19),
                    label: Text(
                      quantidadeFiltros == 0
                          ? 'Filtros'
                          : 'Filtros ($quantidadeFiltros)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                );

                final ordenacaoButton = SizedBox(
                  height: 48,
                  child: _OrdenacaoButton(
                    ordenacao: ordenacao,
                    onChanged: onOrdenacao,
                  ),
                );

                if (empilhar) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      filtrosButton,
                      const SizedBox(height: 8),
                      ordenacaoButton,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: filtrosButton),
                    const SizedBox(width: 8),
                    Expanded(child: ordenacaoButton),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _QuickChip(
                  label: 'Todos',
                  count: contagens.todos,
                  selected: filtroRapido == _FiltroRapido.todos,
                  onTap: () => onFiltroRapido(_FiltroRapido.todos),
                ),
                _QuickChip(
                  label: 'Ação',
                  count: contagens.precisaAcao,
                  selected: filtroRapido == _FiltroRapido.precisaAcao,
                  onTap: () => onFiltroRapido(_FiltroRapido.precisaAcao),
                ),
                _QuickChip(
                  label: 'Atrasadas',
                  count: contagens.atrasadas,
                  selected: filtroRapido == _FiltroRapido.atrasadas,
                  onTap: () => onFiltroRapido(_FiltroRapido.atrasadas),
                ),
                _QuickChip(
                  label: 'Sem agenda',
                  count: contagens.semAgendamento,
                  selected: filtroRapido == _FiltroRapido.semAgendamento,
                  onTap: () => onFiltroRapido(_FiltroRapido.semAgendamento),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _QuickChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => onTap(),
      label: Text('$label · $count'),
    );
  }
}

class _OrdenacaoButton extends StatelessWidget {
  final _OrdenacaoCliente ordenacao;
  final ValueChanged<_OrdenacaoCliente> onChanged;

  const _OrdenacaoButton({
    required this.ordenacao,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_OrdenacaoCliente>(
      initialValue: ordenacao,
      tooltip: 'Ordenar clientes',
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final value in _OrdenacaoCliente.values)
          PopupMenuItem(
            value: value,
            child: Text(_ordenacaoLabel(value)),
          ),
      ],
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: _neutralSurface(context),
          border: Border.all(color: _neutralOutline(context)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.swap_vert_rounded, size: 19),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _ordenacaoLabel(ordenacao),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 19),
          ],
        ),
      ),
    );
  }
}

class _FiltrosAtivos extends StatelessWidget {
  final StatusCadastro? statusCadastro;
  final StatusOperacional? statusOperacional;
  final StatusFinanceiro? statusFinanceiro;
  final _FiltroVisita filtroVisita;
  final String? vendedorNome;
  final String? cidadeUf;
  final bool somenteSemVendedor;
  final VoidCallback onClear;

  const _FiltrosAtivos({
    required this.statusCadastro,
    required this.statusOperacional,
    required this.statusFinanceiro,
    required this.filtroVisita,
    required this.vendedorNome,
    required this.cidadeUf,
    required this.somenteSemVendedor,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final labels = <String>[
      if (statusCadastro != null)
        'Cadastro: ${_cadastroInfo(statusCadastro!).$1}',
      if (statusOperacional != null)
        'Operacional: ${_operacionalInfo(statusOperacional!).$1}',
      if (statusFinanceiro != null)
        'Financeiro: ${_financeiroInfo(statusFinanceiro!).$1}',
      if (filtroVisita != _FiltroVisita.todas)
        'Agenda: ${_filtroVisitaLabel(filtroVisita)}',
      if (vendedorNome != null) 'Vendedor: $vendedorNome',
      if (somenteSemVendedor) 'Vendedor: não definido',
      if (cidadeUf != null) 'Cidade: $cidadeUf',
    ];
    if (labels.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Wrap(
        spacing: 7,
        runSpacing: 7,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final label in labels)
            Chip(
              visualDensity: VisualDensity.compact,
              label: Text(label),
            ),
          TextButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
            label: const Text('Limpar filtros'),
          ),
        ],
      ),
    );
  }
}

/// Dropdown com opção "Todos" representada por null.
class _NullableDropdown<T extends Object> extends StatelessWidget {
  final String label;
  final IconData icon;
  final T? value;
  final String allLabel;
  final List<T> values;
  final String Function(T) labelFor;
  final ValueChanged<T?> onChanged;

  const _NullableDropdown({
    required this.label,
    required this.icon,
    required this.value,
    required this.allLabel,
    required this.values,
    required this.labelFor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T?>(
      // A key muda com o valor para o campo refletir o "Limpar" do modal.
      key: ValueKey('${label}_$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
      ),
      items: [
        DropdownMenuItem<T?>(value: null, child: Text(allLabel)),
        for (final item in values)
          DropdownMenuItem<T?>(value: item, child: Text(labelFor(item))),
      ],
      onChanged: onChanged,
    );
  }
}

class _DropdownString extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? value;
  final String allLabel;
  final List<_OpcaoFiltro> options;
  final ValueChanged<String?> onChanged;

  const _DropdownString({
    required this.label,
    required this.icon,
    required this.value,
    required this.allLabel,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Evita erro do Dropdown caso o valor selecionado não exista mais
    // na lista (ex.: vendedor removido).
    final existe = value == null || options.any((o) => o.id == value);

    return DropdownButtonFormField<String?>(
      key: ValueKey('${label}_${value ?? 'todos'}'),
      initialValue: existe ? value : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
      ),
      items: [
        DropdownMenuItem<String?>(value: null, child: Text(allLabel)),
        for (final option in options)
          DropdownMenuItem<String?>(
            value: option.id,
            child: Text(
              option.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

class _ResultadoCabecalho extends StatelessWidget {
  final int exibidos;
  final int total;

  const _ResultadoCabecalho({required this.exibidos, required this.total});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      total == 0
          ? 'Nenhum cliente encontrado'
          : 'Mostrando $exibidos de $total ${total == 1 ? 'cliente' : 'clientes'}',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _DesktopClientesTable extends StatelessWidget {
  final List<_ClienteItem> itens;
  final ValueChanged<Cliente> onClienteTap;
  final void Function(_AcaoCliente, Cliente) onAcao;

  const _DesktopClientesTable({
    required this.itens,
    required this.onClienteTap,
    required this.onAcao,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 1130),
          child: Column(
            children: [
              const _DesktopTableHeader(),
              for (var index = 0; index < itens.length; index++) ...[
                _DesktopClienteRow(
                  item: itens[index],
                  onTap: () => onClienteTap(itens[index].cliente),
                  onAcao: (acao) => onAcao(acao, itens[index].cliente),
                ),
                if (index != itens.length - 1)
                  Divider(height: 1, color: _neutralOutline(context)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopTableHeader extends StatelessWidget {
  const _DesktopTableHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w800,
    );
    return Container(
      height: 48,
      color: _neutralSurfaceElevated(context),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          SizedBox(width: 265, child: Text('Cliente', style: style)),
          SizedBox(width: 145, child: Text('Cidade/UF', style: style)),
          SizedBox(width: 155, child: Text('Vendedor', style: style)),
          SizedBox(width: 175, child: Text('Próxima visita', style: style)),
          SizedBox(width: 150, child: Text('Operacional', style: style)),
          SizedBox(width: 150, child: Text('Financeiro', style: style)),
          SizedBox(width: 50, child: Text('Ações', style: style)),
        ],
      ),
    );
  }
}

class _DesktopClienteRow extends StatefulWidget {
  final _ClienteItem item;
  final VoidCallback onTap;
  final ValueChanged<_AcaoCliente> onAcao;

  const _DesktopClienteRow({
    required this.item,
    required this.onTap,
    required this.onAcao,
  });

  @override
  State<_DesktopClienteRow> createState() => _DesktopClienteRowState();
}

class _DesktopClienteRowState extends State<_DesktopClienteRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final cliente = item.cliente;
    final cadastro = _cadastroInfo(cliente.statusCadastro);
    final operacional = _operacionalInfo(cliente.statusOperacional);
    final financeiro = _financeiroInfo(cliente.statusFinanceiro);

    return Semantics(
      button: true,
      label: 'Abrir cliente ${item.nome}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: _hovered
              ? theme.colorScheme.primary.withValues(alpha: .045)
              : Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 76),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Row(
                children: [
                  SizedBox(
                    width: 265,
                    child: Row(
                      children: [
                        _ClienteAvatar(nome: item.nome, size: 42),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.nome,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      formatarCpfCnpj(cliente.cpfCnpj),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                      theme.textTheme.bodySmall?.copyWith(
                                        color:
                                        theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  _MiniBadge(cadastro.$1, cadastro.$2),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 145,
                    child: Text(
                      item.localizacao,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: 155,
                    child: Text(
                      item.vendedorNome,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: 175,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _VisitaBadge(data: cliente.proximaVisitaEm),
                    ),
                  ),
                  SizedBox(
                    width: 150,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _Badge(operacional.$1, operacional.$2),
                    ),
                  ),
                  SizedBox(
                    width: 150,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _Badge(financeiro.$1, financeiro.$2),
                    ),
                  ),
                  SizedBox(
                    width: 50,
                    child: _ClienteActionsMenu(onSelected: widget.onAcao),
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

class _MobileClientesList extends StatelessWidget {
  final List<_ClienteItem> itens;
  final ValueChanged<Cliente> onClienteTap;
  final void Function(_AcaoCliente, Cliente) onAcao;

  const _MobileClientesList({
    required this.itens,
    required this.onClienteTap,
    required this.onAcao,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < itens.length; index++) ...[
          _MobileClienteCard(
            item: itens[index],
            onTap: () => onClienteTap(itens[index].cliente),
            onAcao: (acao) => onAcao(acao, itens[index].cliente),
          ),
          if (index != itens.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _MobileClienteCard extends StatelessWidget {
  final _ClienteItem item;
  final VoidCallback onTap;
  final ValueChanged<_AcaoCliente> onAcao;

  const _MobileClienteCard({
    required this.item,
    required this.onTap,
    required this.onAcao,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cliente = item.cliente;
    final cadastro = _cadastroInfo(cliente.statusCadastro);
    final operacional = _operacionalInfo(cliente.statusOperacional);
    final financeiro = _financeiroInfo(cliente.statusFinanceiro);
    final bloqueado = cliente.statusFinanceiro == StatusFinanceiro.bloqueado;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: bloqueado
              ? Colors.red.withValues(alpha: .42)
              : _neutralOutline(context),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ClienteAvatar(nome: item.nome, size: 46),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.nome,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          formatarCpfCnpj(cliente.cpfCnpj),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _ClienteActionsMenu(onSelected: onAcao),
                ],
              ),
              const SizedBox(height: 11),
              Row(
                children: [
                  Expanded(
                    child: _IconText(
                      icon: Icons.location_city_outlined,
                      text: item.localizacao,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _IconText(
                      icon: Icons.badge_outlined,
                      text: item.vendedorNome,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              Align(
                alignment: Alignment.centerLeft,
                child: _VisitaBadge(data: cliente.proximaVisitaEm),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _MiniBadge(cadastro.$1, cadastro.$2),
                  _Badge(operacional.$1, operacional.$2),
                  _Badge(financeiro.$1, financeiro.$2),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClienteActionsMenu extends StatelessWidget {
  final ValueChanged<_AcaoCliente> onSelected;

  const _ClienteActionsMenu({required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_AcaoCliente>(
      tooltip: 'Ações do cliente',
      onSelected: onSelected,
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _AcaoCliente.detalhes,
          child: _MenuItem(
            icon: Icons.visibility_outlined,
            label: 'Ver detalhes',
          ),
        ),
        PopupMenuItem(
          value: _AcaoCliente.agenda,
          child: _MenuItem(
            icon: Icons.event_outlined,
            label: 'Abrir agenda de visitas',
          ),
        ),
        PopupMenuItem(
          value: _AcaoCliente.whatsapp,
          child: _MenuItem(
            icon: Icons.chat_outlined,
            label: 'Abrir WhatsApp',
          ),
        ),
        PopupMenuItem(
          value: _AcaoCliente.copiarDocumento,
          child: _MenuItem(
            icon: Icons.content_copy_outlined,
            label: 'Copiar CPF/CNPJ',
          ),
        ),
      ],
      icon: const Icon(Icons.more_vert_rounded),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MenuItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 19),
        const SizedBox(width: 10),
        Text(label),
      ],
    );
  }
}

class _IconText extends StatelessWidget {
  final IconData icon;
  final String text;

  const _IconText({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class _ClienteAvatar extends StatelessWidget {
  final String nome;
  final double size;

  const _ClienteAvatar({required this.nome, required this.size});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: primary.withValues(alpha: .13),
        shape: BoxShape.circle,
        border: Border.all(color: primary.withValues(alpha: .28)),
      ),
      child: Text(
        _iniciais(nome),
        style: TextStyle(
          color: primary,
          fontSize: size * .33,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _VisitaBadge extends StatelessWidget {
  final DateTime? data;

  const _VisitaBadge({required this.data});

  @override
  Widget build(BuildContext context) {
    final visita = data;
    if (visita == null) {
      return const _Badge(
        'Sem agendamento',
        Colors.orange,
        icon: Icons.event_note_outlined,
      );
    }
    final prevista = _somenteData(visita);
    final hoje = _somenteData(DateTime.now());
    final diferenca = prevista.difference(hoje).inDays;
    if (diferenca < 0) {
      final dias = diferenca.abs();
      return _Badge(
        'Atrasada há $dias ${dias == 1 ? 'dia' : 'dias'}',
        Colors.red,
        icon: Icons.schedule_rounded,
      );
    }
    if (diferenca == 0) {
      return const _Badge('Hoje', Colors.green, icon: Icons.today_outlined);
    }
    if (diferenca == 1) {
      return const _Badge(
        'Amanhã',
        Colors.lightBlue,
        icon: Icons.event_outlined,
      );
    }
    return _Badge(
      _formatarData(visita),
      Colors.blueGrey,
      icon: Icons.event_outlined,
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const _Badge(this.label, this.color, {this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: .38)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _MiniBadge(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .11),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          fontSize: 9.5,
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _FilteredEmptyState extends StatelessWidget {
  final VoidCallback onClearFilters;

  const _FilteredEmptyState({required this.onClearFilters});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 52, horizontal: 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 390),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _StateIcon(icon: Icons.search_off_rounded),
                const SizedBox(height: 15),
                Text(
                  'Nenhum cliente encontrado',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tente outro nome, telefone, Cidade/UF ou remova os filtros aplicados.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: onClearFilters,
                  icon: const Icon(Icons.filter_alt_off_outlined),
                  label: const Text('Limpar filtros'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyClientesState extends StatelessWidget {
  final VoidCallback onCreate;

  const _EmptyClientesState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _StateIcon(icon: Icons.person_add_alt_1_rounded),
                const SizedBox(height: 18),
                Text(
                  'Cadastre seu primeiro cliente',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Depois do cadastro, você poderá aprovar o cliente, definir limites e iniciar a instalação do expositor.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Novo cliente'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ClientesLoadingState extends StatelessWidget {
  const _ClientesLoadingState();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ResponsiveCenter(
        maxWidth: 1280,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const _Skeleton(height: 60),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final largura = constraints.maxWidth >= 700
                    ? (constraints.maxWidth - 36) / 4
                    : (constraints.maxWidth - 12) / 2;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: List.generate(
                    4,
                        (_) => SizedBox(
                      width: largura,
                      child: const _Skeleton(height: 96),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            const _Skeleton(height: 116),
            const SizedBox(height: 16),
            for (var i = 0; i < 5; i++) ...[
              const _Skeleton(height: 74),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  final double height;

  const _Skeleton({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: _neutralSurfaceElevated(context),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: _neutralOutline(context)),
      ),
    );
  }
}

class _ClientesErrorState extends StatelessWidget {
  final Future<void> Function() onRetry;

  const _ClientesErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _StateIcon(
                  icon: Icons.cloud_off_rounded,
                  color: Colors.orange,
                ),
                const SizedBox(height: 18),
                Text(
                  'Não foi possível carregar os clientes',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Verifique sua conexão e tente novamente.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.tonalIcon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StateIcon extends StatelessWidget {
  final IconData icon;
  final Color? color;

  const _StateIcon({required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: effectiveColor.withValues(alpha: .12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 34, color: effectiveColor),
    );
  }
}

// =============================================================================
// Contagens, ordenação e helpers
// =============================================================================

class _ContagensClientes {
  final int todos;
  final int emAnalise;
  final int aguardandoInstalacao;
  final int atrasadas;
  final int bloqueados;
  final int precisaAcao;
  final int semAgendamento;
  final int ativosSemVisita;
  final int semVendedor;

  const _ContagensClientes({
    required this.todos,
    required this.emAnalise,
    required this.aguardandoInstalacao,
    required this.atrasadas,
    required this.bloqueados,
    required this.precisaAcao,
    required this.semAgendamento,
    required this.ativosSemVisita,
    required this.semVendedor,
  });

  /// Uma única passada pela lista.
  factory _ContagensClientes.from(List<_ClienteItem> itens) {
    var emAnalise = 0;
    var aguardandoInstalacao = 0;
    var atrasadas = 0;
    var bloqueados = 0;
    var precisaAcao = 0;
    var semAgendamento = 0;
    var ativosSemVisita = 0;
    var semVendedor = 0;

    for (final item in itens) {
      final cliente = item.cliente;
      final semVisita = cliente.proximaVisitaEm == null;

      if (cliente.statusCadastro == StatusCadastro.emAnalise) emAnalise++;
      if (cliente.statusOperacional == StatusOperacional.aguardandoInstalacao) {
        aguardandoInstalacao++;
      }
      if (_visitaAtrasada(cliente.proximaVisitaEm)) atrasadas++;
      if (cliente.statusFinanceiro == StatusFinanceiro.bloqueado) bloqueados++;
      if (item.prioridade > 0) precisaAcao++;
      if (semVisita) semAgendamento++;
      if (cliente.statusOperacional == StatusOperacional.ativo && semVisita) {
        ativosSemVisita++;
      }
      if (item.semVendedor) semVendedor++;
    }

    return _ContagensClientes(
      todos: itens.length,
      emAnalise: emAnalise,
      aguardandoInstalacao: aguardandoInstalacao,
      atrasadas: atrasadas,
      bloqueados: bloqueados,
      precisaAcao: precisaAcao,
      semAgendamento: semAgendamento,
      ativosSemVisita: ativosSemVisita,
      semVendedor: semVendedor,
    );
  }
}

void _ordenar(List<_ClienteItem> itens, _OrdenacaoCliente ordenacao) {
  int porNome(_ClienteItem a, _ClienteItem b) =>
      a.nomeOrdenacao.compareTo(b.nomeOrdenacao);

  switch (ordenacao) {
    case _OrdenacaoCliente.prioridade:
      itens.sort((a, b) {
        final prioridade = b.prioridade.compareTo(a.prioridade);
        return prioridade != 0 ? prioridade : porNome(a, b);
      });
    case _OrdenacaoCliente.proximaVisita:
      itens.sort((a, b) {
        final data = _compararDatasComNulosNoFim(
          a.cliente.proximaVisitaEm,
          b.cliente.proximaVisitaEm,
        );
        return data != 0 ? data : porNome(a, b);
      });
    case _OrdenacaoCliente.maisAtrasadas:
      itens.sort((a, b) {
        final aData = a.cliente.proximaVisitaEm;
        final bData = b.cliente.proximaVisitaEm;
        final aAtrasada = _visitaAtrasada(aData);
        final bAtrasada = _visitaAtrasada(bData);
        if (aAtrasada != bAtrasada) return aAtrasada ? -1 : 1;
        final data = _compararDatasComNulosNoFim(aData, bData);
        return data != 0 ? data : porNome(a, b);
      });
    case _OrdenacaoCliente.nomeAZ:
      itens.sort(porNome);
    case _OrdenacaoCliente.nomeZA:
      itens.sort((a, b) => porNome(b, a));
    case _OrdenacaoCliente.cidadeAZ:
      itens.sort((a, b) {
        final local = a.localizacaoOrdenacao.compareTo(b.localizacaoOrdenacao);
        return local != 0 ? local : porNome(a, b);
      });
  }
}

int _compararDatasComNulosNoFim(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return a.compareTo(b);
}

bool _clienteSemVendedor(Cliente cliente) {
  final id = cliente.vendedorResponsavelId;
  return id == null || id.trim().isEmpty;
}

/// Regra única para exibir o vendedor em qualquer ponto da tela.
String _vendedorLabel(
    String? vendedorId,
    Map<String, String> nomesUsuarios,
    bool usuariosCarregando,
    ) {
  if (vendedorId == null || vendedorId.trim().isEmpty) return 'Sem vendedor';
  final nome = nomesUsuarios[vendedorId];
  if (nome != null) return nome;
  return usuariosCarregando ? 'Carregando...' : 'Vendedor não localizado';
}

int _prioridadeCliente(Cliente cliente) {
  var pontos = 0;
  if (cliente.statusFinanceiro == StatusFinanceiro.bloqueado) pontos += 100;
  if (cliente.statusFinanceiro == StatusFinanceiro.alerta) pontos += 70;
  if (_visitaAtrasada(cliente.proximaVisitaEm)) pontos += 60;
  if (cliente.statusCadastro == StatusCadastro.emAnalise) pontos += 50;
  if (cliente.statusOperacional == StatusOperacional.aguardandoInstalacao) {
    pontos += 40;
  }
  if (cliente.statusOperacional == StatusOperacional.ativo &&
      cliente.proximaVisitaEm == null) {
    pontos += 30;
  }
  if (_clienteSemVendedor(cliente)) pontos += 20;
  return pontos;
}

DateTime _somenteData(DateTime data) =>
    DateTime(data.year, data.month, data.day);

bool _visitaAtrasada(DateTime? data) {
  if (data == null) return false;
  return _somenteData(data).isBefore(_somenteData(DateTime.now()));
}

bool _visitaHoje(DateTime? data) {
  if (data == null) return false;
  return _somenteData(data).isAtSameMomentAs(_somenteData(DateTime.now()));
}

/// De hoje até domingo. Visitas desta semana que já passaram
/// ficam em "Atrasadas", não aqui.
bool _visitaNestaSemana(DateTime? data) {
  if (data == null) return false;
  final hoje = _somenteData(DateTime.now());
  final domingo = hoje.add(Duration(days: DateTime.sunday - hoje.weekday));
  final prevista = _somenteData(data);
  return !prevista.isBefore(hoje) && !prevista.isAfter(domingo);
}

String _formatarData(DateTime data) {
  final dia = data.day.toString().padLeft(2, '0');
  final mes = data.month.toString().padLeft(2, '0');
  return '$dia/$mes/${data.year}';
}

String _nomeExibicao(Cliente cliente) {
  final fantasia = cliente.nomeFantasia?.trim();
  return fantasia?.isNotEmpty == true ? fantasia! : cliente.nome.trim();
}

String _cidadeUfLabel(Cliente cliente) {
  final cidade = cliente.cidade.trim();
  final uf = cliente.uf.trim().toUpperCase();
  if (cidade.isNotEmpty && uf.isNotEmpty) return '$cidade/$uf';
  if (cidade.isNotEmpty) return cidade;
  if (uf.isNotEmpty) return uf;
  return 'Não informado';
}

final _naoNumerico = RegExp(r'[^0-9]');

/// Termo composto só de dígitos e pontuação típica de CPF/CNPJ/telefone.
final _pareceNumero = RegExp(r'^[\d\s().\-/+]+$');

String _somenteNumeros(String valor) => valor.replaceAll(_naoNumerico, '');

const _comAcento = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
const _semAcento = 'aaaaaeeeeiiiiooooouuuucn';

/// Minúsculas e sem acento: "São João" → "sao joao".
String _normalizar(String valor) {
  final minusculo = valor.trim().toLowerCase();
  final buffer = StringBuffer();
  for (final unit in minusculo.split('')) {
    final indice = _comAcento.indexOf(unit);
    buffer.write(indice >= 0 ? _semAcento[indice] : unit);
  }
  return buffer.toString();
}

/// Retorna o número no formato do wa.me (55 + DDD + número) ou vazio.
/// Decide pelo tamanho, não pelo prefixo — DDD 55 (RS) também começa com 55.
String _telefoneWhatsApp(String bruto) {
  final numero = _somenteNumeros(bruto);
  if (numero.length == 10 || numero.length == 11) return '55$numero';
  if ((numero.length == 12 || numero.length == 13) &&
      numero.startsWith('55')) {
    return numero;
  }
  return '';
}

String _filtroVisitaLabel(_FiltroVisita filtro) => switch (filtro) {
  _FiltroVisita.todas => 'Todas',
  _FiltroVisita.atrasadas => 'Atrasadas',
  _FiltroVisita.hoje => 'Hoje',
  _FiltroVisita.estaSemana => 'Esta semana',
  _FiltroVisita.semAgendamento => 'Sem agendamento',
};

String _ordenacaoLabel(_OrdenacaoCliente ordenacao) => switch (ordenacao) {
  _OrdenacaoCliente.prioridade => 'Prioridade',
  _OrdenacaoCliente.proximaVisita => 'Próxima visita',
  _OrdenacaoCliente.maisAtrasadas => 'Mais atrasadas',
  _OrdenacaoCliente.nomeAZ => 'Nome A–Z',
  _OrdenacaoCliente.nomeZA => 'Nome Z–A',
  _OrdenacaoCliente.cidadeAZ => 'Cidade A–Z',
};

(String, Color) _cadastroInfo(StatusCadastro status) => switch (status) {
  StatusCadastro.rascunho => ('Rascunho', Colors.grey),
  StatusCadastro.emAnalise => ('Em análise', Colors.orange),
  StatusCadastro.aprovado => ('Aprovado', Colors.green),
  StatusCadastro.reprovado => ('Reprovado', Colors.red),
};

(String, Color) _operacionalInfo(StatusOperacional status) => switch (status) {
  StatusOperacional.pendente => ('Pendente', Colors.grey),
  StatusOperacional.aguardandoInstalacao =>
  ('Aguard. instalação', Colors.orange),
  StatusOperacional.ativo => ('Ativo', Colors.green),
  StatusOperacional.suspenso => ('Suspenso', Colors.orange),
  StatusOperacional.encerrado => ('Encerrado', Colors.grey),
};

(String, Color) _financeiroInfo(StatusFinanceiro status) => switch (status) {
  StatusFinanceiro.normal => ('Normal', Colors.green),
  StatusFinanceiro.alerta => ('Alerta', Colors.orange),
  StatusFinanceiro.bloqueado => ('Bloqueado', Colors.red),
};

Color _neutralSurface(BuildContext context) {
  final theme = Theme.of(context);
  return theme.brightness == Brightness.dark
      ? const Color(0xFF1D1D20)
      : theme.colorScheme.surface;
}

Color _neutralSurfaceElevated(BuildContext context) {
  final theme = Theme.of(context);
  return theme.brightness == Brightness.dark
      ? const Color(0xFF232327)
      : theme.colorScheme.surfaceContainer;
}

Color _neutralOutline(BuildContext context) {
  final theme = Theme.of(context);
  return theme.brightness == Brightness.dark
      ? const Color(0xFF38383F)
      : theme.colorScheme.outlineVariant;
}

String _iniciais(String nome) {
  final partes = nome
      .trim()
      .split(RegExp(r'\s+'))
      .where((parte) => parte.isNotEmpty)
      .toList();
  if (partes.isEmpty) return '--';
  if (partes.length == 1) {
    final palavra = partes.first;
    return palavra.substring(0, palavra.length >= 2 ? 2 : 1).toUpperCase();
  }
  return '${partes.first[0]}${partes.last[0]}'.toUpperCase();
}