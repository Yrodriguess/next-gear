import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/providers/current_org_provider.dart';
import '../../../core/utils/br_formatters.dart';
import '../../../core/widgets/produto_photo_picker.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../auth/presentation/usuario_providers.dart';
import '../../expositores/domain/expositor_fisico.dart';
import '../../expositores/presentation/expositor_providers.dart';
import '../data/cliente_repository.dart';
import '../domain/cliente.dart';
import 'cliente_providers.dart';

const _verdeNextGear = Color(0xFF76FF03);
const _frequenciasPermitidas = <int>[15, 20, 30, 45];
const _limiteFotoBytes = 8 * 1024 * 1024;

enum _StatusConsultaDocumento {
  nenhum,
  consultando,
  disponivel,
  duplicado,
  falha,
}

class ClienteFormPage extends ConsumerStatefulWidget {
  /// Quando informado, o formulário abre em modo de continuação — os
  /// campos vêm pré-preenchidos e o salvamento grava por cima do MESMO
  /// documento, nunca cria um cliente novo. Usado por "Continuar
  /// cadastro" (rascunho) e "Corrigir e reenviar" (reprovado).
  final Cliente? clienteExistente;

  const ClienteFormPage({super.key, this.clienteExistente});

  @override
  ConsumerState<ClienteFormPage> createState() => _ClienteFormPageState();
}

class _ClienteFormPageState extends ConsumerState<ClienteFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _numeroFocusNode = FocusNode();

  TipoDocumento _tipoDocumento = TipoDocumento.pessoaJuridica;
  final _cpfCnpjController = TextEditingController();
  final _nomeController = TextEditingController();
  final _nomeFantasiaController = TextEditingController();

  final _cepController = TextEditingController();
  final _logradouroController = TextEditingController();
  final _numeroController = TextEditingController();
  final _complementoController = TextEditingController();
  final _bairroController = TextEditingController();
  final _cidadeController = TextEditingController();
  final _ufController = TextEditingController();
  final _localizacaoController = TextEditingController();

  final _nomeResponsavelController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _emailController = TextEditingController();

  final _prazoController = TextEditingController(text: '7');
  final _comissaoController = TextEditingController(text: '30');
  final _observacoesController = TextEditingController();

  String? _vendedorSelecionadoId;
  String? _expositorFisicoSelecionadoId;
  int _frequenciaVisitaDias = 30;
  PeriodoPreferencialVisita _periodoPreferencial =
      PeriodoPreferencialVisita.qualquerHorario;
  AntecedenciaAvisoVisita _antecedenciaAviso =
      AntecedenciaAvisoVisita.naoAvisar;
  Uint8List? _fotoFachadaBytes;
  String? _fotoFachadaUrlExistente;

  bool _isSaving = false;
  bool _dirty = false;
  bool _tentouEnviar = false;
  bool _consultandoCep = false;
  bool _consultandoCnpj = false;
  bool _obtendoLocalizacao = false;
  int _etapasConcluidasCache = -1;
  int _versaoConsultaDocumento = 0;
  _StatusConsultaDocumento _statusConsultaDocumento =
      _StatusConsultaDocumento.nenhum;
  String? _ultimoCepConsultado;
  String? _cepFeedback;
  String? _cnpjFeedback;
  String? _errorMessage;

  bool get _isPJ => _tipoDocumento == TipoDocumento.pessoaJuridica;

  String get _tituloAppBar => switch (widget.clienteExistente?.statusCadastro) {
    StatusCadastro.reprovado => 'Corrigir e reenviar',
    StatusCadastro.rascunho => 'Continuar cadastro',
    _ => 'Novo cliente',
  };

  @override
  void initState() {
    super.initState();
    final cliente = widget.clienteExistente;
    if (cliente == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _etapasConcluidasCache =
            _etapasConcluidas(ref.read(appUserProvider).value);
      });
      return;
    }

    _tipoDocumento = cliente.tipoDocumento;
    _cpfCnpjController.text = formatarCpfCnpj(cliente.cpfCnpj);
    _nomeController.text = cliente.nome;
    _nomeFantasiaController.text = cliente.nomeFantasia ?? '';
    _cepController.text = cliente.cep.length == 8
        ? '${cliente.cep.substring(0, 5)}-${cliente.cep.substring(5)}'
        : cliente.cep;
    _logradouroController.text = cliente.logradouro;
    _numeroController.text = cliente.numero;
    _complementoController.text = cliente.complemento ?? '';
    _bairroController.text = cliente.bairro;
    _cidadeController.text = cliente.cidade;
    _ufController.text = cliente.uf;
    _localizacaoController.text = cliente.localizacaoMapsUrl;
    _nomeResponsavelController.text = cliente.nomeResponsavel;
    _telefoneController.text = formatarTelefone(cliente.telefoneResponsavel);
    _emailController.text = cliente.emailResponsavel ?? '';
    _prazoController.text = '${cliente.prazoAcertoDias}';
    final comissaoPercentual = cliente.comissaoPropostaBasisPoints / 100;
    _comissaoController.text = comissaoPercentual % 1 == 0
        ? comissaoPercentual.toStringAsFixed(0)
        : comissaoPercentual.toStringAsFixed(1);
    _observacoesController.text = cliente.observacoesOperacionais ?? '';

    _vendedorSelecionadoId = cliente.vendedorResponsavelId;
    _expositorFisicoSelecionadoId = cliente.expositorFisicoSelecionadoId;
    _frequenciaVisitaDias = cliente.frequenciaVisitaDiasPadrao;
    _periodoPreferencial = cliente.periodoPreferencialVisita;
    _antecedenciaAviso = cliente.antecedenciaAvisoVisita;
    _fotoFachadaUrlExistente =
    (cliente.fotoFachadaUrl?.isNotEmpty ?? false) ? cliente.fotoFachadaUrl : null;
    // _dirty continua false — só abrir pra continuar não conta como
    // alteração ainda não salva.

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _etapasConcluidasCache =
          _etapasConcluidas(ref.read(appUserProvider).value);
    });
  }

  @override
  void dispose() {
    _cpfCnpjController.dispose();
    _nomeController.dispose();
    _nomeFantasiaController.dispose();
    _cepController.dispose();
    _logradouroController.dispose();
    _numeroController.dispose();
    _complementoController.dispose();
    _bairroController.dispose();
    _cidadeController.dispose();
    _ufController.dispose();
    _localizacaoController.dispose();
    _nomeResponsavelController.dispose();
    _telefoneController.dispose();
    _emailController.dispose();
    _prazoController.dispose();
    _comissaoController.dispose();
    _observacoesController.dispose();
    _numeroFocusNode.dispose();
    super.dispose();
  }

  void _marcarAlterado() {
    final novasEtapas =
    _etapasConcluidas(ref.read(appUserProvider).value);

    final precisaAtualizarTela =
        !_dirty ||
            _errorMessage != null ||
            _etapasConcluidasCache != novasEtapas;

    if (precisaAtualizarTela) {
      setState(() {
        _dirty = true;
        _errorMessage = null;
        _etapasConcluidasCache = novasEtapas;
      });
      return;
    }

    // O texto do próprio campo já é atualizado pelo TextEditingController.
    // Evita reconstruir todo o formulário a cada caractere digitado.
    _dirty = true;
  }

  void _aoAlterarDocumento() {
    final versao = ++_versaoConsultaDocumento;
    final documento = _somenteDigitos(_cpfCnpjController.text);
    final documentoValido =
    _isPJ ? _cnpjValido(documento) : _cpfValido(documento);

    setState(() {
      _dirty = true;
      _errorMessage = null;
      _cnpjFeedback = null;
      _statusConsultaDocumento = _StatusConsultaDocumento.nenhum;
    });

    if (!documentoValido) return;

    // O documento só é considerado válido quando já possui todos os
    // dígitos. Portanto não é necessário aguardar um debounce: ao digitar
    // ou colar o último número, a consulta começa imediatamente.
    unawaited(_consultarDocumentoAoDigitar(documento, versao));
  }

  Future<void> _consultarDocumentoAoDigitar(
      String documento,
      int versao,
      ) async {
    if (!mounted || versao != _versaoConsultaDocumento) return;
    final orgId = ref.read(currentOrgIdProvider);
    if (orgId == null || orgId.isEmpty) {
      setState(() {
        _statusConsultaDocumento = _StatusConsultaDocumento.falha;
      });
      return;
    }

    setState(() {
      _statusConsultaDocumento = _StatusConsultaDocumento.consultando;
    });

    try {
      final existente =
      await ref.read(clienteRepositoryProvider).buscarPorCpfCnpj(
        orgId: orgId,
        cpfCnpj: documento,
        ignorarClienteId: widget.clienteExistente?.id,
      );
      if (!mounted || versao != _versaoConsultaDocumento) return;
      setState(() {
        _statusConsultaDocumento = existente == null
            ? _StatusConsultaDocumento.disponivel
            : _StatusConsultaDocumento.duplicado;
      });
    } catch (e, stack) {
      debugPrint('Erro na consulta automática de CPF/CNPJ: $e\n$stack');
      if (!mounted || versao != _versaoConsultaDocumento) return;
      setState(() {
        _statusConsultaDocumento = _StatusConsultaDocumento.falha;
      });
    }
  }

  Future<void> _solicitarSaida() async {
    if (_isSaving) return;
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }

    final sair = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Descartar alterações?'),
        content: const Text(
          'Existem informações que ainda não foram salvas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Continuar preenchendo'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );

    if (sair == true && mounted) {
      setState(() => _dirty = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  Cliente _montarCliente(String orgId, AppUser? appUser) {
    final comissaoPercentual =
        double.tryParse(_comissaoController.text.replaceAll(',', '.')) ?? 30;

    return Cliente(
      id: widget.clienteExistente?.id,
      orgId: orgId,
      tipoDocumento: _tipoDocumento,
      cpfCnpj: _somenteDigitos(_cpfCnpjController.text),
      nome: _normalizarMaiusculo(_nomeController.text),
      nomeFantasia: _isPJ
          ? _normalizarMaiusculo(_nomeFantasiaController.text)
          : null,
      cep: _somenteDigitos(_cepController.text),
      logradouro: _normalizarMaiusculo(_logradouroController.text),
      numero: _normalizarMaiusculo(_numeroController.text),
      complemento: _textoOpcionalMaiusculo(_complementoController.text),
      bairro: _normalizarMaiusculo(_bairroController.text),
      cidade: _normalizarMaiusculo(_cidadeController.text),
      uf: _normalizarMaiusculo(_ufController.text),
      localizacaoMapsUrl: _localizacaoController.text.trim(),
      // Se não trocou a foto agora, mantém a que já existia — senão o
      // "continuar cadastro" apagaria a foto que já tinha sido enviada.
      fotoFachadaUrl:
      _fotoFachadaBytes == null ? _fotoFachadaUrlExistente : null,
      nomeResponsavel: _normalizarMaiusculo(_nomeResponsavelController.text),
      telefoneResponsavel: _somenteDigitos(_telefoneController.text),
      emailResponsavel: _emailController.text.trim().toLowerCase(),
      vendedorResponsavelId: appUser?.role == UserRole.vendedor
          ? appUser!.uid
          : _vendedorSelecionadoId,
      prazoAcertoDias: int.tryParse(_prazoController.text) ?? 7,
      observacoesOperacionais:
      _textoOpcional(_observacoesController.text),
      periodoPreferencialVisita: _periodoPreferencial,
      antecedenciaAvisoVisita: _antecedenciaAviso,
      frequenciaVisitaDiasPadrao: _frequenciaVisitaDias,
      expositorFisicoSelecionadoId: _expositorFisicoSelecionadoId,
      comissaoPropostaBasisPoints: (comissaoPercentual * 100).round(),
      comissaoBasisPoints: 0,
      limiteCreditoCentavos: 0,
    );
  }

  Future<bool> _documentoDisponivelParaCadastro(String orgId) async {
    final documento = _somenteDigitos(_cpfCnpjController.text);
    final documentoValido =
    _isPJ ? _cnpjValido(documento) : _cpfValido(documento);

    if (!documentoValido) {
      if (mounted) {
        setState(() {
          _statusConsultaDocumento = _StatusConsultaDocumento.nenhum;
          _errorMessage = _isPJ
              ? 'Informe um CNPJ válido antes de salvar.'
              : 'Informe um CPF válido antes de salvar.';
        });
      }
      return false;
    }

    try {
      if (mounted) {
        setState(() {
          _statusConsultaDocumento = _StatusConsultaDocumento.consultando;
        });
      }
      final existente =
      await ref.read(clienteRepositoryProvider).buscarPorCpfCnpj(
        orgId: orgId,
        cpfCnpj: documento,
        ignorarClienteId: widget.clienteExistente?.id,
      );

      if (!mounted) return false;
      if (existente != null) {
        setState(() {
          _statusConsultaDocumento = _StatusConsultaDocumento.duplicado;
          _errorMessage =
          'Já existe um cliente cadastrado com este CPF/CNPJ.';
        });
        return false;
      }
      setState(() {
        _statusConsultaDocumento = _StatusConsultaDocumento.disponivel;
      });
      return true;
    } catch (e, stack) {
      debugPrint('Erro ao verificar CPF/CNPJ: $e\n$stack');
      if (mounted) {
        setState(() {
          _statusConsultaDocumento = _StatusConsultaDocumento.falha;
          _errorMessage =
          'Não foi possível verificar o CPF/CNPJ. Confira sua conexão e tente novamente.';
        });
      }
      return false;
    }
  }

  Future<void> _handleSalvarRascunho() async {
    if (_isSaving) return;
    if (_nomeController.text.trim().isEmpty) {
      setState(() => _errorMessage =
      'Informe ao menos o nome para salvar o rascunho.');
      return;
    }

    final orgId = ref.read(currentOrgIdProvider);
    if (orgId == null) {
      setState(() =>
      _errorMessage = 'Sessão inválida. Faça login novamente.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final documentoDisponivel =
      await _documentoDisponivelParaCadastro(orgId);
      if (!documentoDisponivel || !mounted) return;

      final usuario = ref.read(appUserProvider).value;
      final cliente = _montarCliente(orgId, usuario);
      await ref.read(clienteRepositoryProvider).salvarRascunho(
        cliente,
        fotoFachadaBytes: _fotoFachadaBytes,
        clienteIdExistente: widget.clienteExistente?.id,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rascunho salvo.')),
      );
      setState(() => _dirty = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(true);
      });
    } on CpfCnpjDuplicadoException catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    } catch (e, stack) {
      debugPrint('Erro ao salvar rascunho: $e\n$stack');
      if (mounted) {
        setState(() => _errorMessage =
        'Não foi possível salvar o rascunho. Tente novamente.');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _handleEnviarParaAnalise() async {
    if (_isSaving) return;
    FocusScope.of(context).unfocus();

    if (!_tentouEnviar) {
      setState(() => _tentouEnviar = true);
    }

    final formularioValido = _formKey.currentState?.validate() ?? false;
    if (!formularioValido) {
      setState(() => _errorMessage =
      'Revise os campos destacados antes de continuar.');
      return;
    }
    if (_expositorFisicoSelecionadoId == null) {
      setState(() => _errorMessage =
      'Selecione um expositor disponível antes de enviar.');
      return;
    }
    if (_fotoFachadaBytes == null &&
        (_fotoFachadaUrlExistente == null || _fotoFachadaUrlExistente!.isEmpty)) {
      setState(() => _errorMessage =
      'Adicione uma foto da fachada antes de enviar para análise.');
      return;
    }
    if (_fotoFachadaBytes != null &&
        _fotoFachadaBytes!.lengthInBytes > _limiteFotoBytes) {
      setState(() => _errorMessage =
      'A foto da fachada precisa ter no máximo 8 MB.');
      return;
    }

    final orgId = ref.read(currentOrgIdProvider);
    final usuario = ref.read(appUserProvider).value;
    if (orgId == null || usuario == null) {
      setState(() =>
      _errorMessage = 'Sessão inválida. Faça login novamente.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    final documentoDisponivelAntesDaRevisao =
    await _documentoDisponivelParaCadastro(orgId);
    if (mounted) setState(() => _isSaving = false);
    if (!documentoDisponivelAntesDaRevisao || !mounted) return;

    final confirmado = await _mostrarRevisao();
    if (confirmado != true || !mounted) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final documentoAindaDisponivel =
      await _documentoDisponivelParaCadastro(orgId);
      if (!documentoAindaDisponivel || !mounted) return;

      final cliente = _montarCliente(orgId, usuario);
      await ref.read(clienteRepositoryProvider).enviarParaAnaliseComExpositor(
        cliente: cliente,
        expositorFisicoId: _expositorFisicoSelecionadoId!,
        usuarioId: usuario.uid,
        fotoFachadaBytes: _fotoFachadaBytes,
        clienteIdExistente: widget.clienteExistente?.id,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cliente enviado para análise.')),
      );
      setState(() => _dirty = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(true);
      });
    } on CpfCnpjDuplicadoException catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    } on ExpositorIndisponivelException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _expositorFisicoSelecionadoId = null;
        });
      }
    } catch (e, stack) {
      debugPrint('Erro ao enviar cliente: $e\n$stack');
      if (mounted) {
        setState(() => _errorMessage =
        'Não foi possível enviar o cadastro. Confira sua conexão e tente novamente.');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _consultarCep({bool moverParaNumero = true}) async {
    final cep = _somenteDigitos(_cepController.text);
    if (cep.length != 8 || _consultandoCep) return;

    setState(() {
      _consultandoCep = true;
      _cepFeedback = null;
      _ultimoCepConsultado = cep;
    });

    try {
      final response = await http
          .get(Uri.parse('https://viacep.com.br/ws/$cep/json/'))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw Exception('CEP indisponível');
      }

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map<String, dynamic> || data['erro'] == true) {
        if (mounted) {
          setState(() => _cepFeedback =
          'CEP não encontrado. Preencha o endereço manualmente.');
        }
        return;
      }

      _logradouroController.text = _normalizarMaiusculo('${data['logradouro'] ?? ''}');
      _bairroController.text = _normalizarMaiusculo('${data['bairro'] ?? ''}');
      _cidadeController.text = _normalizarMaiusculo('${data['localidade'] ?? ''}');
      _ufController.text = _normalizarMaiusculo('${data['uf'] ?? ''}');
      final complementoCep = _normalizarMaiusculo('${data['complemento'] ?? ''}');
      if (_complementoController.text.trim().isEmpty && complementoCep.isNotEmpty) {
        _complementoController.text = complementoCep;
      }

      if (mounted) {
        setState(() {
          _dirty = true;
          _cepFeedback = 'Endereço localizado. Confirme os dados.';
        });
        if (moverParaNumero) _numeroFocusNode.requestFocus();
      }
    } catch (e, stack) {
      debugPrint('Erro ao consultar CEP: $e\n$stack');
      if (mounted) {
        setState(() => _cepFeedback =
        'Não foi possível consultar agora. Você pode preencher manualmente.');
      }
    } finally {
      if (mounted) setState(() => _consultandoCep = false);
    }
  }

  Future<void> _consultarCnpj() async {
    if (_consultandoCnpj || !_isPJ) return;
    final cnpj = _somenteDigitos(_cpfCnpjController.text);
    if (!_cnpjValido(cnpj)) {
      setState(() => _cnpjFeedback = 'Informe um CNPJ válido para consultar.');
      return;
    }

    setState(() {
      _consultandoCnpj = true;
      _cnpjFeedback = null;
    });

    try {
      final response = await http
          .get(Uri.parse('https://brasilapi.com.br/api/cnpj/v1/$cnpj'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 404) {
        if (mounted) {
          setState(() => _cnpjFeedback =
          'CNPJ não encontrado. Continue o preenchimento manualmente.');
        }
        return;
      }
      if (response.statusCode != 200) {
        throw Exception('Consulta retornou ${response.statusCode}');
      }

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map<String, dynamic>) throw const FormatException();

      void preencherMaiusculo(TextEditingController controller, Object? valor) {
        final texto = _normalizarMaiusculo('${valor ?? ''}');
        if (texto.isNotEmpty) controller.text = texto;
      }

      preencherMaiusculo(_nomeController, data['razao_social']);
      preencherMaiusculo(_nomeFantasiaController, data['nome_fantasia']);
      preencherMaiusculo(_logradouroController, data['logradouro']);
      preencherMaiusculo(_numeroController, data['numero']);
      preencherMaiusculo(_complementoController, data['complemento']);
      preencherMaiusculo(_bairroController, data['bairro']);
      preencherMaiusculo(_cidadeController, data['municipio']);
      preencherMaiusculo(_ufController, data['uf']);

      final cep = _somenteDigitos('${data['cep'] ?? ''}');
      if (cep.length == 8) _cepController.text = _formatarCep(cep);
      final telefone = _somenteDigitos('${data['ddd_telefone_1'] ?? ''}');
      if (telefone.length >= 10) {
        _telefoneController.text = _formatarTelefone(telefone);
      }
      final email = '${data['email'] ?? ''}'.trim().toLowerCase();
      if (_emailValido(email)) _emailController.text = email;

      if (mounted) {
        setState(() {
          _dirty = true;
          _cnpjFeedback =
          'Dados localizados. Confira e complete as informações.';
        });
      }
    } catch (e, stack) {
      debugPrint('Erro ao consultar CNPJ: $e\n$stack');
      if (mounted) {
        setState(() => _cnpjFeedback =
        'Consulta indisponível. Continue o preenchimento manualmente.');
      }
    } finally {
      if (mounted) setState(() => _consultandoCnpj = false);
    }
  }

  Future<void> _usarLocalizacaoAtual() async {
    if (_obtendoLocalizacao || _isSaving) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _obtendoLocalizacao = true;
      _errorMessage = null;
    });

    try {
      final servicoAtivo =
      await Geolocator.isLocationServiceEnabled();

      if (!servicoAtivo) {
        if (mounted) {
          setState(() {
            _errorMessage =
            'Ative a localização do aparelho para continuar.';
          });
        }
        return;
      }

      var permissao = await Geolocator.checkPermission();

      if (permissao == LocationPermission.denied) {
        permissao = await Geolocator.requestPermission();
      }

      if (permissao == LocationPermission.denied) {
        if (mounted) {
          setState(() {
            _errorMessage =
            'A permissão de localização foi negada.';
          });
        }
        return;
      }

      if (permissao == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _errorMessage =
            'A permissão de localização está bloqueada nas configurações do aparelho.';
          });
        }
        return;
      }

      final posicao = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final latitude = posicao.latitude.toStringAsFixed(7);
      final longitude = posicao.longitude.toStringAsFixed(7);

      final url =
          'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude';

      if (!mounted) return;

      setState(() {
        _localizacaoController.text = url;
        _dirty = true;
        _errorMessage = null;
        _etapasConcluidasCache =
            _etapasConcluidas(ref.read(appUserProvider).value);
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Localização atual registrada no cadastro.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (e, stack) {
      debugPrint('Erro ao obter localização atual: $e\n$stack');

      if (mounted) {
        setState(() {
          _errorMessage =
          'Não foi possível obter a localização atual. '
              'Você ainda pode buscar pelo endereço ou colar o link do Maps.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _obtendoLocalizacao = false;
        });
      }
    }
  }

  Future<void> _abrirBuscaMaps() async {
    final partes = [
      _nomeFantasiaController.text.trim(),
      _logradouroController.text.trim(),
      _numeroController.text.trim(),
      _bairroController.text.trim(),
      _cidadeController.text.trim(),
      _ufController.text.trim(),
      _cepController.text.trim(),
    ].where((value) => value.isNotEmpty).toList();

    if (partes.length < 3) {
      setState(() => _errorMessage =
      'Preencha o endereço antes de buscar a localização no Maps.');
      return;
    }

    final uri = Uri.https(
      'www.google.com',
      '/maps/search/',
      {'api': '1', 'query': partes.join(', ')},
    );
    final abriu = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!abriu && mounted) {
      setState(() =>
      _errorMessage = 'Não foi possível abrir o Google Maps.');
    }
  }

  Future<void> _testarLocalizacao() async {
    final texto = _localizacaoController.text.trim();
    if (!_linkMapsValido(texto)) {
      setState(() => _errorMessage =
      'Cole um link válido compartilhado pelo Google Maps.');
      return;
    }
    final abriu = await launchUrl(
      Uri.parse(texto),
      mode: LaunchMode.externalApplication,
    );
    if (!abriu && mounted) {
      setState(() => _errorMessage =
      'Não foi possível abrir o link informado.');
    }
  }

  Future<bool?> _mostrarRevisao() {
    final appUser = ref.read(appUserProvider).value;
    final vendedores = ref.read(vendedoresListProvider).value ?? <AppUser>[];
    final orgId = ref.read(currentOrgIdProvider);
    final expositores = orgId == null
        ? <ExpositorFisico>[]
        : ref.read(expositoresDisponiveisProvider(orgId)).value ??
        <ExpositorFisico>[];

    final vendedorNome = appUser?.role == UserRole.vendedor
        ? appUser?.nome ?? 'Vendedor atual'
        : _nomeVendedor(vendedores, _vendedorSelecionadoId);
    final expositorNome =
    _nomeExpositor(expositores, _expositorFisicoSelecionadoId);

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _RevisaoClienteDialog(
        fotoBytes: _fotoFachadaBytes,
        linhas: [
          ('Cliente', _nomeExibicao),
          (_isPJ ? 'CNPJ' : 'CPF', _cpfCnpjController.text),
          ('Endereço', _enderecoResumo),
          ('Responsável', _nomeResponsavelController.text.trim()),
          ('Telefone', _telefoneController.text.trim()),
          ('Vendedor', vendedorNome),
          ('Expositor', expositorNome),
          ('Prazo de acerto', '${_prazoController.text} dias'),
          ('Comissão proposta', '${_comissaoController.text}%'),
          ('Periodicidade', 'A cada $_frequenciaVisitaDias dias'),
          ('Melhor período', _periodoLabel(_periodoPreferencial)),
          ('Avisar', _antecedenciaLabel(_antecedenciaAviso)),
          ('Localização', 'Link do Google Maps informado'),
          if (_observacoesController.text.trim().isNotEmpty)
            ('Observação', _observacoesController.text.trim()),
        ],
      ),
    );
  }

  String get _nomeExibicao {
    final fantasia = _nomeFantasiaController.text.trim();
    if (_isPJ && fantasia.isNotEmpty) return fantasia;
    final nome = _nomeController.text.trim();
    return nome.isEmpty ? 'Não informado' : nome;
  }

  String get _enderecoResumo {
    return [
      '${_logradouroController.text.trim()}, ${_numeroController.text.trim()}',
      _bairroController.text.trim(),
      '${_cidadeController.text.trim()}/${_ufController.text.trim()}',
      _cepController.text.trim(),
    ].where((value) => value.replaceAll(RegExp(r'[,/]'), '').trim().isNotEmpty)
        .join(' - ');
  }

  int _etapasConcluidas(AppUser? appUser) {
    var total = 0;
    final documento = _somenteDigitos(_cpfCnpjController.text);
    final identificacaoOk = _isPJ
        ? _cnpjValido(documento) &&
        _nomeController.text.trim().isNotEmpty &&
        _nomeFantasiaController.text.trim().isNotEmpty
        : _cpfValido(documento) && _nomeController.text.trim().isNotEmpty;
    if (identificacaoOk) total++;

    final enderecoOk = _somenteDigitos(_cepController.text).length == 8 &&
        _logradouroController.text.trim().isNotEmpty &&
        _numeroController.text.trim().isNotEmpty &&
        _bairroController.text.trim().isNotEmpty &&
        _cidadeController.text.trim().isNotEmpty &&
        _ufsValidas.contains(_ufController.text.trim().toUpperCase()) &&
        _linkMapsValido(_localizacaoController.text);
    if (enderecoOk) total++;

    final contatoOk = _nomeResponsavelController.text.trim().isNotEmpty &&
        _telefoneValido(_telefoneController.text) &&
        _emailValido(_emailController.text);
    if (contatoOk) total++;

    final vendedorOk = appUser?.role == UserRole.vendedor ||
        _vendedorSelecionadoId != null;
    final operacaoOk = vendedorOk &&
        _expositorFisicoSelecionadoId != null &&
        _fotoFachadaBytes != null &&
        _prazoValido(_prazoController.text) &&
        _comissaoValida(_comissaoController.text);
    if (operacaoOk) total++;
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final appUser = ref.watch(appUserProvider).value;
    final vendedoresAsync = ref.watch(vendedoresListProvider);
    final orgId = ref.watch(currentOrgIdProvider);
    final AsyncValue<List<ExpositorFisico>> expositoresAsync = orgId == null
        ? const AsyncValue.data(<ExpositorFisico>[])
        : ref.watch(expositoresDisponiveisProvider(orgId));

    expositoresAsync.whenData((expositores) {
      if (_expositorFisicoSelecionadoId != null &&
          !expositores.any((e) => e.id == _expositorFisicoSelecionadoId)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _expositorFisicoSelecionadoId = null);
        });
      }
    });

    final carregandoDependencias =
        vendedoresAsync.isLoading || expositoresAsync.isLoading;
    final etapas = _etapasConcluidas(appUser);
    if (_etapasConcluidasCache < 0) {
      _etapasConcluidasCache = etapas;
    }

    return PopScope(
      canPop: !_dirty && !_isSaving,
      onPopInvoked: (didPop) async {
        if (!didPop) await _solicitarSaida();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            tooltip: 'Voltar',
            onPressed: _isSaving ? null : _solicitarSaida,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Text(_tituloAppBar),
        ),
        bottomNavigationBar: _BarraAcoesCliente(
          salvando: _isSaving,
          bloquearEnvio: carregandoDependencias ||
              _consultandoCep ||
              _consultandoCnpj,
          onRascunho: _handleSalvarRascunho,
          onEnviar: _handleEnviarParaAnalise,
        ),
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 28),
            child: ResponsiveCenter(
              maxWidth: 1180,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Form(
                  key: _formKey,
                  autovalidateMode: _tentouEnviar
                      ? AutovalidateMode.onUserInteraction
                      : AutovalidateMode.disabled,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _CabecalhoCadastro(etapasConcluidas: etapas),
                      const SizedBox(height: 16),
                      if (_errorMessage != null) ...[
                        _MensagemErro(texto: _errorMessage!),
                        const SizedBox(height: 16),
                      ],
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final desktop = constraints.maxWidth >= 900;
                          final esquerda = Column(
                            children: [
                              _buildIdentificacaoCard(),
                              const SizedBox(height: 16),
                              _buildResponsavelCard(),
                            ],
                          );
                          final direita = Column(
                            children: [
                              _buildEnderecoCard(),
                              const SizedBox(height: 16),
                              _buildOperacaoCard(
                                appUser: appUser,
                                vendedoresAsync: vendedoresAsync,
                                expositoresAsync: expositoresAsync,
                                orgId: orgId,
                              ),
                              const SizedBox(height: 16),
                              _buildFotoCard(),
                            ],
                          );

                          if (!desktop) {
                            return Column(
                              children: [
                                esquerda,
                                const SizedBox(height: 16),
                                direita,
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: esquerda),
                              const SizedBox(width: 16),
                              Expanded(child: direita),
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
        ),
      ),
    );
  }

  Widget _buildIdentificacaoCard() {
    return _CardSecao(
      icon: Icons.badge_outlined,
      titulo: 'Identificação',
      subtitulo: 'Dados legais e comerciais do cliente.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: SegmentedButton<TipoDocumento>(
              segments: const [
                ButtonSegment(
                  value: TipoDocumento.pessoaFisica,
                  label: Text('Pessoa física'),
                ),
                ButtonSegment(
                  value: TipoDocumento.pessoaJuridica,
                  label: Text('Pessoa jurídica'),
                ),
              ],
              selected: {_tipoDocumento},
              onSelectionChanged: _isSaving
                  ? null
                  : (value) {
                _versaoConsultaDocumento++;
                setState(() {
                  _tipoDocumento = value.first;
                  _cpfCnpjController.clear();
                  _cnpjFeedback = null;
                  _statusConsultaDocumento =
                      _StatusConsultaDocumento.nenhum;
                  _dirty = true;
                  _errorMessage = null;
                });
              },
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _cpfCnpjController,
            enabled: !_isSaving,
            keyboardType: TextInputType.number,
            inputFormatters: [_DocumentoFormatter(tipo: _tipoDocumento)],
            decoration: InputDecoration(
              labelText: _isPJ ? 'CNPJ *' : 'CPF *',
              prefixIcon: const Icon(Icons.numbers_rounded),
            ),
            validator: (value) {
              final digitos = _somenteDigitos(value ?? '');
              if (digitos.isEmpty) return 'Campo obrigatório';
              final valido = _isPJ ? _cnpjValido(digitos) : _cpfValido(digitos);
              return valido ? null : (_isPJ ? 'CNPJ inválido' : 'CPF inválido');
            },
            onChanged: (_) => _aoAlterarDocumento(),
          ),
          if (_statusConsultaDocumento !=
              _StatusConsultaDocumento.nenhum) ...[
            const SizedBox(height: 7),
            _DocumentoConsultaFeedback(status: _statusConsultaDocumento),
          ],
          if (_isPJ) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _isSaving || _consultandoCnpj
                    ? null
                    : _consultarCnpj,
                icon: _consultandoCnpj
                    ? const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.manage_search_rounded),
                label: Text(_consultandoCnpj
                    ? 'Consultando...'
                    : 'Consultar dados do CNPJ'),
              ),
            ),
            if (_cnpjFeedback != null) ...[
              const SizedBox(height: 6),
              _TextoApoio(_cnpjFeedback!),
            ],
          ],
          const SizedBox(height: 14),
          TextFormField(
            controller: _nomeController,
            enabled: !_isSaving,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [_UpperCaseTextFormatter()],
            decoration: InputDecoration(
              labelText: _isPJ ? 'Razão social *' : 'Nome completo *',
              prefixIcon: const Icon(Icons.storefront_outlined),
            ),
            validator: _obrigatorio,
            onChanged: (_) => _marcarAlterado(),
          ),
          if (_isPJ) ...[
            const SizedBox(height: 14),
            TextFormField(
              controller: _nomeFantasiaController,
              enabled: !_isSaving,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [_UpperCaseTextFormatter()],
              decoration: const InputDecoration(
                labelText: 'Nome fantasia *',
                prefixIcon: Icon(Icons.business_outlined),
              ),
              validator: _obrigatorio,
              onChanged: (_) => _marcarAlterado(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEnderecoCard() {
    return _CardSecao(
      icon: Icons.location_on_outlined,
      titulo: 'Endereço e localização',
      subtitulo:
      'Se estiver no cliente, registre a localização atual. O link continuará disponível para toda a equipe.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _cepController,
            enabled: !_isSaving,
            keyboardType: TextInputType.number,
            inputFormatters: [_CepFormatter()],
            decoration: InputDecoration(
              labelText: 'CEP *',
              prefixIcon: const Icon(Icons.local_post_office_outlined),
              suffixIcon: _consultandoCep
                  ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
                  : IconButton(
                tooltip: 'Buscar CEP',
                onPressed: _isSaving ? null : _consultarCep,
                icon: const Icon(Icons.search_rounded),
              ),
            ),
            validator: (value) => _somenteDigitos(value ?? '').length == 8
                ? null
                : 'CEP inválido',
            onChanged: (value) {
              _cepFeedback = null;
              _marcarAlterado();
              final cep = _somenteDigitos(value);
              if (cep.length == 8 && cep != _ultimoCepConsultado) {
                _consultarCep();
              }
            },
          ),
          if (_cepFeedback != null) ...[
            const SizedBox(height: 6),
            _TextoApoio(_cepFeedback!),
          ],
          const SizedBox(height: 14),
          _ResponsivePair(
            firstFlex: 3,
            secondFlex: 1,
            first: TextFormField(
              controller: _logradouroController,
              enabled: !_isSaving,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [_UpperCaseTextFormatter()],
              decoration: const InputDecoration(labelText: 'Logradouro *'),
              validator: _obrigatorio,
              onChanged: (_) => _marcarAlterado(),
            ),
            second: TextFormField(
              controller: _numeroController,
              focusNode: _numeroFocusNode,
              enabled: !_isSaving,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [_UpperCaseTextFormatter()],
              decoration: const InputDecoration(
                labelText: 'Número *',
                hintText: 'S/N',
              ),
              validator: _obrigatorio,
              onChanged: (_) => _marcarAlterado(),
            ),
          ),
          const SizedBox(height: 14),
          _ResponsivePair(
            first: TextFormField(
              controller: _bairroController,
              enabled: !_isSaving,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [_UpperCaseTextFormatter()],
              decoration: const InputDecoration(labelText: 'Bairro *'),
              validator: _obrigatorio,
              onChanged: (_) => _marcarAlterado(),
            ),
            second: TextFormField(
              controller: _complementoController,
              enabled: !_isSaving,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [_UpperCaseTextFormatter()],
              decoration: const InputDecoration(
                labelText: 'Complemento',
                hintText: 'Opcional',
              ),
              onChanged: (_) => _marcarAlterado(),
            ),
          ),
          const SizedBox(height: 14),
          _ResponsivePair(
            firstFlex: 3,
            secondFlex: 1,
            first: TextFormField(
              controller: _cidadeController,
              enabled: !_isSaving,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [_UpperCaseTextFormatter()],
              decoration: const InputDecoration(labelText: 'Cidade *'),
              validator: _obrigatorio,
              onChanged: (_) => _marcarAlterado(),
            ),
            second: TextFormField(
              controller: _ufController,
              enabled: !_isSaving,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                LengthLimitingTextInputFormatter(2),
                FilteringTextInputFormatter.allow(RegExp('[a-zA-Z]')),
                _UpperCaseTextFormatter(),
              ],
              decoration: const InputDecoration(labelText: 'UF *'),
              validator: (value) => _ufsValidas
                  .contains((value ?? '').trim().toUpperCase())
                  ? null
                  : 'UF inválida',
              onChanged: (_) => _marcarAlterado(),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _localizacaoController,
            enabled: !_isSaving,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Link da localização no Google Maps *',
              hintText: 'https://maps.app.goo.gl/...',
              prefixIcon: Icon(Icons.map_outlined),
            ),
            validator: (value) {
              if ((value ?? '').trim().isEmpty) return 'Campo obrigatório';
              return _linkMapsValido(value!) ? null : 'Link do Maps inválido';
            },
            onChanged: (_) => _marcarAlterado(),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _isSaving || _obtendoLocalizacao
                    ? null
                    : _usarLocalizacaoAtual,
                icon: _obtendoLocalizacao
                    ? const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
                    : const Icon(Icons.my_location_rounded),
                label: Text(
                  _obtendoLocalizacao
                      ? 'Obtendo localização...'
                      : 'Usar localização atual',
                ),
              ),
              OutlinedButton.icon(
                onPressed: _isSaving ? null : _abrirBuscaMaps,
                icon: const Icon(Icons.travel_explore_rounded),
                label: const Text('Buscar pelo endereço'),
              ),
              TextButton.icon(
                onPressed: _isSaving ? null : _testarLocalizacao,
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Testar localização'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const _TextoApoio(
            'No cliente, use a localização atual. Se estiver cadastrando à distância, '
                'busque pelo endereço ou cole um link compartilhado do Google Maps.',
          ),
        ],
      ),
    );
  }

  Widget _buildResponsavelCard() {
    return _CardSecao(
      icon: Icons.person_outline_rounded,
      titulo: 'Responsável',
      subtitulo: 'Contato principal do estabelecimento.',
      child: Column(
        children: [
          TextFormField(
            controller: _nomeResponsavelController,
            enabled: !_isSaving,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [_UpperCaseTextFormatter()],
            decoration: const InputDecoration(
              labelText: 'Nome do responsável *',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: _obrigatorio,
            onChanged: (_) => _marcarAlterado(),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _telefoneController,
            enabled: !_isSaving,
            keyboardType: TextInputType.phone,
            inputFormatters: [_TelefoneBrasileiroFormatter()],
            decoration: const InputDecoration(
              labelText: 'Telefone/WhatsApp *',
              hintText: '(61) 98668-6853',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
            validator: (value) => _telefoneValido(value ?? '')
                ? null
                : 'Informe DDD e telefone válidos',
            onChanged: (_) => _marcarAlterado(),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _emailController,
            enabled: !_isSaving,
            keyboardType: TextInputType.emailAddress,
            textCapitalization: TextCapitalization.none,
            inputFormatters: [_LowerCaseTextFormatter()],
            decoration: const InputDecoration(
              labelText: 'E-mail *',
              prefixIcon: Icon(Icons.alternate_email_rounded),
            ),
            validator: (value) {
              if ((value ?? '').trim().isEmpty) return 'Campo obrigatório';
              return _emailValido(value!) ? null : 'E-mail inválido';
            },
            onChanged: (_) => _marcarAlterado(),
          ),
        ],
      ),
    );
  }

  Widget _buildOperacaoCard({
    required AppUser? appUser,
    required AsyncValue<List<AppUser>> vendedoresAsync,
    required AsyncValue<List<ExpositorFisico>> expositoresAsync,
    required String? orgId,
  }) {
    final podeEditarCondicoes = appUser?.role == UserRole.admin ||
        appUser?.role == UserRole.financeiro;

    return _CardSecao(
      icon: Icons.tune_rounded,
      titulo: 'Operação comercial',
      subtitulo: 'Responsável pela rota, expositor e condições do atendimento.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (appUser?.role == UserRole.vendedor)
            _InfoDestaque(
              icon: Icons.person_pin_circle_outlined,
              texto: 'Vendedor responsável: ${appUser?.nome ?? ''}',
            )
          else
            vendedoresAsync.when(
              data: (vendedores) => DropdownButtonFormField<String>(
                initialValue: _vendedorSelecionadoId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Vendedor responsável *',
                ),
                items: vendedores
                    .map(
                      (vendedor) => DropdownMenuItem(
                    value: vendedor.uid,
                    child: Text(
                      vendedor.nome,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                    .toList(),
                validator: (value) => value == null
                    ? 'Selecione o vendedor responsável'
                    : null,
                onChanged: _isSaving
                    ? null
                    : (value) {
                  setState(() {
                    _vendedorSelecionadoId = value;
                    _dirty = true;
                    _errorMessage = null;
                  });
                },
              ),
              loading: () => const LinearProgressIndicator(),
              error: (e, stack) {
                debugPrint('Erro ao carregar vendedores: $e\n$stack');
                return const _MensagemDependencia(
                  texto: 'Não foi possível carregar os vendedores.',
                );
              },
            ),
          const SizedBox(height: 14),
          expositoresAsync.when(
            data: (expositores) {
              if (expositores.isEmpty) {
                return _SemExpositor(
                  onAtualizar: orgId == null
                      ? null
                      : () => ref.invalidate(
                    expositoresDisponiveisProvider(orgId),
                  ),
                );
              }

              final expositoresOrdenados = [...expositores]
                ..sort(
                      (a, b) => a.numero
                      .toLowerCase()
                      .compareTo(b.numero.toLowerCase()),
                );

              return DropdownButtonFormField<String>(
                initialValue: _expositorFisicoSelecionadoId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Expositor a reservar *',
                ),
                items: expositoresOrdenados
                    .map(
                      (expositor) => DropdownMenuItem(
                    value: expositor.id,
                    child: Text(
                      '${expositor.numero} — ${expositor.modeloNome}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                    .toList(),
                validator: (value) => value == null
                    ? 'Selecione um expositor disponível'
                    : null,
                onChanged: _isSaving
                    ? null
                    : (value) {
                  setState(() {
                    _expositorFisicoSelecionadoId = value;
                    _dirty = true;
                    _errorMessage = null;
                  });
                },
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (e, stack) {
              debugPrint('Erro ao carregar expositores: $e\n$stack');
              return const _MensagemDependencia(
                texto: 'Não foi possível carregar os expositores disponíveis.',
              );
            },
          ),
          const SizedBox(height: 8),
          const _TextoApoio(
            'A unidade só fica reservada quando o cadastro é enviado para análise.',
          ),
          const SizedBox(height: 16),
          _ResponsivePair(
            first: TextFormField(
              controller: _prazoController,
              enabled: !_isSaving,
              readOnly: !podeEditarCondicoes,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Prazo de acerto (dias) *',
                suffixIcon: !podeEditarCondicoes
                    ? const Icon(Icons.lock_outline_rounded, size: 19)
                    : null,
              ),
              validator: (value) => _prazoValido(value ?? '')
                  ? null
                  : 'Informe de 1 a 120 dias',
              onChanged: (_) => _marcarAlterado(),
            ),
            second: TextFormField(
              controller: _comissaoController,
              enabled: !_isSaving,
              readOnly: !podeEditarCondicoes,
              keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
              ],
              decoration: InputDecoration(
                labelText: 'Comissão proposta (%) *',
                suffixIcon: !podeEditarCondicoes
                    ? const Icon(Icons.lock_outline_rounded, size: 19)
                    : null,
              ),
              validator: (value) => _comissaoValida(value ?? '')
                  ? null
                  : 'Informe de 0% a 100%',
              onChanged: (_) => _marcarAlterado(),
            ),
          ),
          const SizedBox(height: 8),
          _TextoApoio(
            podeEditarCondicoes
                ? 'Os valores começam em 7 dias e 30%, mas podem ser ajustados pelo administrativo/financeiro.'
                : 'Condição padrão: acerto em 7 dias e comissão proposta de 30%.',
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: _frequenciaVisitaDias,
            decoration: const InputDecoration(
              labelText: 'Periodicidade das visitas *',
            ),
            items: _frequenciasPermitidas
                .map(
                  (dias) => DropdownMenuItem(
                value: dias,
                child: Text('A cada $dias dias'),
              ),
            )
                .toList(),
            onChanged: _isSaving
                ? null
                : (value) {
              if (value == null) return;
              setState(() {
                _frequenciaVisitaDias = value;
                _dirty = true;
                _errorMessage = null;
              });
            },
          ),
          const SizedBox(height: 14),
          _ResponsivePair(
            first: DropdownButtonFormField<PeriodoPreferencialVisita>(
              initialValue: _periodoPreferencial,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Melhor período para visita *',
              ),
              items: PeriodoPreferencialVisita.values
                  .map(
                    (periodo) => DropdownMenuItem(
                  value: periodo,
                  child: Text(_periodoLabel(periodo)),
                ),
              )
                  .toList(),
              onChanged: _isSaving
                  ? null
                  : (value) {
                if (value == null) return;
                setState(() {
                  _periodoPreferencial = value;
                  _dirty = true;
                  _errorMessage = null;
                });
              },
            ),
            second: DropdownButtonFormField<AntecedenciaAvisoVisita>(
              initialValue: _antecedenciaAviso,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Avisar antes da visita *',
              ),
              items: AntecedenciaAvisoVisita.values
                  .map(
                    (aviso) => DropdownMenuItem(
                  value: aviso,
                  child: Text(_antecedenciaLabel(aviso)),
                ),
              )
                  .toList(),
              onChanged: _isSaving
                  ? null
                  : (value) {
                if (value == null) return;
                setState(() {
                  _antecedenciaAviso = value;
                  _dirty = true;
                  _errorMessage = null;
                });
              },
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _observacoesController,
            enabled: !_isSaving,
            minLines: 3,
            maxLines: 5,
            maxLength: 600,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Observações operacionais',
              hintText:
              'Ex.: responsável só está à tarde; ligar um dia antes para separar o dinheiro.',
              alignLabelWithHint: true,
            ),
            onChanged: (_) => _marcarAlterado(),
          ),
        ],
      ),
    );
  }

  Widget _buildFotoCard() {
    return _CardSecao(
      icon: Icons.add_a_photo_outlined,
      titulo: 'Foto da fachada',
      subtitulo: 'Ajuda qualquer vendedor a reconhecer o comércio.',
      child: Column(
        children: [
          Center(
            child: ProdutoPhotoPicker(
              bytesSelecionados: _fotoFachadaBytes,
              urlExistente: _fotoFachadaUrlExistente,
              onChanged: (bytes) {
                setState(() {
                  _fotoFachadaBytes = bytes;
                  _dirty = true;
                  _errorMessage = null;
                });
              },
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _fotoFachadaBytes != null
                ? 'Foto adicionada. Toque novamente para substituir.'
                : (_fotoFachadaUrlExistente != null
                ? 'Foto já cadastrada. Toque para substituir.'
                : 'Obrigatória para enviar para análise; opcional no rascunho.'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: (_fotoFachadaBytes != null || _fotoFachadaUrlExistente != null)
                  ? _verdeNextGear
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _CabecalhoCadastro extends StatelessWidget {
  final int etapasConcluidas;

  const _CabecalhoCadastro({required this.etapasConcluidas});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _verdeNextGear.withOpacity(.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.person_add_alt_1_rounded,
                      color: _verdeNextGear, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cadastro de cliente',
                        overflow: TextOverflow.ellipsis,
                        style: tema.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$etapasConcluidas de 4 etapas completas',
                        overflow: TextOverflow.ellipsis,
                        style: tema.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${etapasConcluidas * 25}%',
                  style: tema.textTheme.titleMedium?.copyWith(
                    color: _verdeNextGear,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: etapasConcluidas / 4,
                minHeight: 7,
                backgroundColor: tema.colorScheme.surfaceContainerHighest,
                valueColor:
                const AlwaysStoppedAnimation<Color>(_verdeNextGear),
              ),
            ),
            const SizedBox(height: 9),
            Text(
              'Campos com * são obrigatórios para enviar. O rascunho pode ser salvo incompleto.',
              style: tema.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _CardSecao extends StatelessWidget {
  final IconData icon;
  final String titulo;
  final String subtitulo;
  final Widget child;

  const _CardSecao({
    required this.icon,
    required this.titulo,
    required this.subtitulo,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: _verdeNextGear, size: 23),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: tema.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(subtitulo, style: tema.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

class _ResponsivePair extends StatelessWidget {
  final Widget first;
  final Widget second;
  final int firstFlex;
  final int secondFlex;

  const _ResponsivePair({
    required this.first,
    required this.second,
    this.firstFlex = 1,
    this.secondFlex = 1,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 470) {
          return Column(
            children: [
              first,
              const SizedBox(height: 14),
              second,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: firstFlex, child: first),
            const SizedBox(width: 12),
            Expanded(flex: secondFlex, child: second),
          ],
        );
      },
    );
  }
}

class _BarraAcoesCliente extends StatelessWidget {
  final bool salvando;
  final bool bloquearEnvio;
  final VoidCallback onRascunho;
  final VoidCallback onEnviar;

  const _BarraAcoesCliente({
    required this.salvando,
    required this.bloquearEnvio,
    required this.onRascunho,
    required this.onEnviar,
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Material(
      color: tema.scaffoldBackgroundColor,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final rascunho = OutlinedButton.icon(
                onPressed: salvando ? null : onRascunho,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Salvar rascunho'),
              );
              final enviar = FilledButton.icon(
                onPressed: salvando || bloquearEnvio ? null : onEnviar,
                icon: salvando
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.fact_check_outlined),
                label: Text(salvando ? 'Salvando...' : 'Revisar e enviar'),
              );

              if (constraints.maxWidth < 480) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    enviar,
                    const SizedBox(height: 8),
                    rascunho,
                  ],
                );
              }
              return Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  rascunho,
                  const SizedBox(width: 10),
                  enviar,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _RevisaoClienteDialog extends StatelessWidget {
  final Uint8List? fotoBytes;
  final List<(String, String)> linhas;

  const _RevisaoClienteDialog({
    required this.fotoBytes,
    required this.linhas,
  });

  @override
  Widget build(BuildContext context) {
    final tamanho = MediaQuery.sizeOf(context);
    final largura = tamanho.width >= 720 ? 680.0 : tamanho.width - 28;
    final altura = tamanho.height * .84;

    return Dialog(
      insetPadding: const EdgeInsets.all(14),
      child: SizedBox(
        width: largura,
        height: altura,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
              child: Row(
                children: [
                  const Icon(Icons.fact_check_outlined,
                      color: _verdeNextGear),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Revisar cadastro',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (fotoBytes != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.memory(
                          fotoBytes!,
                          height: 180,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    for (var i = 0; i < linhas.length; i++) ...[
                      _LinhaRevisao(
                        label: linhas[i].$1,
                        value: linhas[i].$2,
                      ),
                      if (i != linhas.length - 1)
                        const Divider(height: 22),
                    ],
                    const SizedBox(height: 16),
                    const _InfoDestaque(
                      icon: Icons.info_outline_rounded,
                      texto:
                      'O expositor será reservado somente após esta confirmação.',
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Voltar e ajustar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.send_rounded),
                      label: const Text('Confirmar envio'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinhaRevisao extends StatelessWidget {
  final String label;
  final String value;

  const _LinhaRevisao({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _MensagemErro extends StatelessWidget {
  final String texto;

  const _MensagemErro({required this.texto});

  @override
  Widget build(BuildContext context) {
    final cor = Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: cor.withOpacity(.09),
        border: Border.all(color: cor.withOpacity(.35)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: cor),
          const SizedBox(width: 10),
          Expanded(child: Text(texto)),
        ],
      ),
    );
  }
}

class _MensagemDependencia extends StatelessWidget {
  final String texto;

  const _MensagemDependencia({required this.texto});

  @override
  Widget build(BuildContext context) {
    final cor = Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cor.withOpacity(.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, color: cor),
          const SizedBox(width: 9),
          Expanded(child: Text(texto)),
        ],
      ),
    );
  }
}

class _SemExpositor extends StatelessWidget {
  final VoidCallback? onAtualizar;

  const _SemExpositor({this.onAtualizar});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(.08),
        border: Border.all(color: Colors.orange.withOpacity(.35)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.inventory_2_outlined, color: Colors.orange),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Nenhum expositor disponível',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          const Text(
            'Você pode salvar o cadastro como rascunho e reservar uma unidade quando houver disponibilidade.',
          ),
          if (onAtualizar != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onAtualizar,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Atualizar disponibilidade'),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoDestaque extends StatelessWidget {
  final IconData icon;
  final String texto;

  const _InfoDestaque({required this.icon, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _verdeNextGear.withOpacity(.08),
        border: Border.all(color: _verdeNextGear.withOpacity(.28)),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Icon(icon, color: _verdeNextGear, size: 20),
          const SizedBox(width: 9),
          Expanded(child: Text(texto)),
        ],
      ),
    );
  }
}

class _TextoApoio extends StatelessWidget {
  final String texto;

  const _TextoApoio(this.texto);

  @override
  Widget build(BuildContext context) {
    return Text(texto, style: Theme.of(context).textTheme.bodySmall);
  }
}

class _DocumentoConsultaFeedback extends StatelessWidget {
  final _StatusConsultaDocumento status;

  const _DocumentoConsultaFeedback({required this.status});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (icone, texto, cor) = switch (status) {
      _StatusConsultaDocumento.consultando => (
      Icons.sync_rounded,
      'Verificando CPF/CNPJ no cadastro...',
      colorScheme.onSurfaceVariant,
      ),
      _StatusConsultaDocumento.disponivel => (
      Icons.check_circle_outline_rounded,
      'Documento disponível para cadastro.',
      _verdeNextGear,
      ),
      _StatusConsultaDocumento.duplicado => (
      Icons.error_outline_rounded,
      'Este CPF/CNPJ já está cadastrado.',
      colorScheme.error,
      ),
      _StatusConsultaDocumento.falha => (
      Icons.cloud_off_outlined,
      'Não foi possível verificar agora. Tente novamente.',
      Colors.orange,
      ),
      _StatusConsultaDocumento.nenhum => (
      Icons.info_outline_rounded,
      '',
      colorScheme.onSurfaceVariant,
      ),
    };

    return Row(
      children: [
        if (status == _StatusConsultaDocumento.consultando)
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: cor),
          )
        else
          Icon(icone, size: 17, color: cor),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            texto,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cor),
          ),
        ),
      ],
    );
  }
}

class _UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

class _LowerCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toLowerCase());
  }
}

class _DocumentoFormatter extends TextInputFormatter {
  final TipoDocumento tipo;

  const _DocumentoFormatter({required this.tipo});

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var digitos = _somenteDigitos(newValue.text);
    final limite = tipo == TipoDocumento.pessoaFisica ? 11 : 14;
    if (digitos.length > limite) digitos = digitos.substring(0, limite);
    final texto = tipo == TipoDocumento.pessoaFisica
        ? _formatarCpf(digitos)
        : _formatarCnpj(digitos);
    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}

class _CepFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var digitos = _somenteDigitos(newValue.text);
    if (digitos.length > 8) digitos = digitos.substring(0, 8);
    final texto = _formatarCep(digitos);
    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}

class _TelefoneBrasileiroFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var digitos = _somenteDigitos(newValue.text);
    if (digitos.startsWith('55') && digitos.length > 11) {
      digitos = digitos.substring(2);
    }
    if (digitos.length > 11) digitos = digitos.substring(0, 11);
    final texto = _formatarTelefone(digitos);
    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}

String? _obrigatorio(String? value) => (value ?? '').trim().isEmpty
    ? 'Campo obrigatório'
    : null;

String _somenteDigitos(String value) =>
    value.replaceAll(RegExp(r'[^0-9]'), '');

String _normalizarMaiusculo(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();

String? _textoOpcionalMaiusculo(String value) {
  final texto = _normalizarMaiusculo(value);
  return texto.isEmpty ? null : texto;
}

String? _textoOpcional(String value) {
  final texto = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  return texto.isEmpty ? null : texto;
}

String _formatarCpf(String digitos) {
  if (digitos.length <= 3) return digitos;
  if (digitos.length <= 6) {
    return '${digitos.substring(0, 3)}.${digitos.substring(3)}';
  }
  if (digitos.length <= 9) {
    return '${digitos.substring(0, 3)}.${digitos.substring(3, 6)}.${digitos.substring(6)}';
  }
  return '${digitos.substring(0, 3)}.${digitos.substring(3, 6)}.${digitos.substring(6, 9)}-${digitos.substring(9)}';
}

String _formatarCnpj(String digitos) {
  if (digitos.length <= 2) return digitos;
  if (digitos.length <= 5) {
    return '${digitos.substring(0, 2)}.${digitos.substring(2)}';
  }
  if (digitos.length <= 8) {
    return '${digitos.substring(0, 2)}.${digitos.substring(2, 5)}.${digitos.substring(5)}';
  }
  if (digitos.length <= 12) {
    return '${digitos.substring(0, 2)}.${digitos.substring(2, 5)}.${digitos.substring(5, 8)}/${digitos.substring(8)}';
  }
  return '${digitos.substring(0, 2)}.${digitos.substring(2, 5)}.${digitos.substring(5, 8)}/${digitos.substring(8, 12)}-${digitos.substring(12)}';
}

String _formatarCep(String digitos) {
  if (digitos.length <= 5) return digitos;
  return '${digitos.substring(0, 5)}-${digitos.substring(5)}';
}

String _formatarTelefone(String entrada) {
  var digitos = _somenteDigitos(entrada);
  if (digitos.startsWith('55') && digitos.length > 11) {
    digitos = digitos.substring(2);
  }
  if (digitos.length > 11) digitos = digitos.substring(0, 11);
  if (digitos.length <= 2) return digitos;
  final ddd = digitos.substring(0, 2);
  final restante = digitos.substring(2);
  if (restante.length <= 4) return '($ddd) $restante';
  if (restante.length <= 8) {
    return '($ddd) ${restante.substring(0, 4)}-${restante.substring(4)}';
  }
  return '($ddd) ${restante.substring(0, 5)}-${restante.substring(5)}';
}

bool _cpfValido(String entrada) {
  final cpf = _somenteDigitos(entrada);
  if (cpf.length != 11 || RegExp(r'^(\d)\1{10}$').hasMatch(cpf)) {
    return false;
  }
  final numeros = cpf.split('').map(int.parse).toList();
  for (var digito = 9; digito < 11; digito++) {
    var soma = 0;
    for (var i = 0; i < digito; i++) {
      soma += numeros[i] * (digito + 1 - i);
    }
    final calculado = (soma * 10) % 11 % 10;
    if (numeros[digito] != calculado) return false;
  }
  return true;
}

bool _cnpjValido(String entrada) {
  final cnpj = _somenteDigitos(entrada);
  if (cnpj.length != 14 || RegExp(r'^(\d)\1{13}$').hasMatch(cnpj)) {
    return false;
  }
  final numeros = cnpj.split('').map(int.parse).toList();

  int calcular(List<int> pesos, int quantidade) {
    var soma = 0;
    for (var i = 0; i < quantidade; i++) {
      soma += numeros[i] * pesos[i];
    }
    final resto = soma % 11;
    return resto < 2 ? 0 : 11 - resto;
  }

  const pesosPrimeiro = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
  const pesosSegundo = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
  return numeros[12] == calcular(pesosPrimeiro, 12) &&
      numeros[13] == calcular(pesosSegundo, 13);
}

bool _telefoneValido(String entrada) {
  final digitos = _somenteDigitos(entrada);
  return digitos.length == 10 || digitos.length == 11;
}

bool _emailValido(String entrada) {
  final email = entrada.trim();
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
}

bool _linkMapsValido(String entrada) {
  final uri = Uri.tryParse(entrada.trim());
  if (uri == null || !uri.hasScheme || uri.scheme != 'https') return false;
  final host = uri.host.toLowerCase();
  return host == 'maps.app.goo.gl' ||
      host == 'goo.gl' ||
      host == 'maps.google.com' ||
      host == 'www.google.com' ||
      host.endsWith('.google.com');
}

bool _prazoValido(String value) {
  final dias = int.tryParse(value);
  return dias != null && dias > 0 && dias <= 120;
}

bool _comissaoValida(String value) {
  final comissao = double.tryParse(value.replaceAll(',', '.'));
  return comissao != null && comissao >= 0 && comissao <= 100;
}

String _periodoLabel(PeriodoPreferencialVisita value) {
  return switch (value) {
    PeriodoPreferencialVisita.qualquerHorario => 'Qualquer horário',
    PeriodoPreferencialVisita.manha => 'Manhã',
    PeriodoPreferencialVisita.tarde => 'Tarde',
    PeriodoPreferencialVisita.noite => 'Noite',
  };
}

String _antecedenciaLabel(AntecedenciaAvisoVisita value) {
  return switch (value) {
    AntecedenciaAvisoVisita.naoAvisar => 'Não avisar',
    AntecedenciaAvisoVisita.mesmoDia => 'No mesmo dia',
    AntecedenciaAvisoVisita.umDiaAntes => 'Um dia antes',
  };
}

String _nomeVendedor(List<AppUser> vendedores, String? id) {
  if (id == null) return 'Não selecionado';
  for (final vendedor in vendedores) {
    if (vendedor.uid == id) return vendedor.nome;
  }
  return 'Vendedor selecionado';
}

String _nomeExpositor(List<ExpositorFisico> expositores, String? id) {
  if (id == null) return 'Não selecionado';
  for (final expositor in expositores) {
    if (expositor.id == id) {
      return '${expositor.numero} — ${expositor.modeloNome}';
    }
  }
  return 'Expositor selecionado';
}

const _ufsValidas = {
  'AC',
  'AL',
  'AP',
  'AM',
  'BA',
  'CE',
  'DF',
  'ES',
  'GO',
  'MA',
  'MT',
  'MS',
  'MG',
  'PA',
  'PB',
  'PR',
  'PE',
  'PI',
  'RJ',
  'RN',
  'RS',
  'RO',
  'RR',
  'SC',
  'SP',
  'SE',
  'TO',
};
