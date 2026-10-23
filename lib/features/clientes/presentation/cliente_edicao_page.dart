import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/br_formatters.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_providers.dart';
import '../domain/cliente.dart';
import 'cliente_providers.dart';

const _ufsValidas = {
  'AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 'MT', 'MS',
  'MG', 'PA', 'PB', 'PR', 'PE', 'PI', 'RJ', 'RN', 'RS', 'RO', 'RR', 'SC',
  'SP', 'SE', 'TO',
};
const _frequenciasPermitidas = <int>[15, 20, 30, 45];

/// Edita dados cadastrais de um cliente já existente — endereço,
/// contato e prazo de acerto. Diferente do formulário de cadastro
/// (ClienteFormPage), NUNCA mexe em status, comissão, expositor ou
/// limite de crédito — só o que muda no dia a dia (endereço que mudou,
/// telefone novo, etc.).
class ClienteEdicaoPage extends ConsumerStatefulWidget {
  final Cliente cliente;

  const ClienteEdicaoPage({super.key, required this.cliente});

  @override
  ConsumerState<ClienteEdicaoPage> createState() => _ClienteEdicaoPageState();
}

class _ClienteEdicaoPageState extends ConsumerState<ClienteEdicaoPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nomeController;
  late final TextEditingController _nomeFantasiaController;
  late final TextEditingController _cepController;
  late final TextEditingController _logradouroController;
  late final TextEditingController _numeroController;
  late final TextEditingController _complementoController;
  late final TextEditingController _bairroController;
  late final TextEditingController _cidadeController;
  late final TextEditingController _ufController;
  late final TextEditingController _localizacaoController;
  late final TextEditingController _nomeResponsavelController;
  late final TextEditingController _telefoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _prazoController;
  late final TextEditingController _observacoesController;

  late int _frequenciaVisitaDias;
  late PeriodoPreferencialVisita _periodoPreferencial;
  late AntecedenciaAvisoVisita _antecedenciaAviso;

  bool _isSaving = false;
  String? _errorMessage;

  bool get _isPJ => widget.cliente.tipoDocumento == TipoDocumento.pessoaJuridica;

  @override
  void initState() {
    super.initState();
    final c = widget.cliente;
    _nomeController = TextEditingController(text: c.nome);
    _nomeFantasiaController = TextEditingController(text: c.nomeFantasia ?? '');
    _cepController = TextEditingController(text: c.cep);
    _logradouroController = TextEditingController(text: c.logradouro);
    _numeroController = TextEditingController(text: c.numero);
    _complementoController = TextEditingController(text: c.complemento ?? '');
    _bairroController = TextEditingController(text: c.bairro);
    _cidadeController = TextEditingController(text: c.cidade);
    _ufController = TextEditingController(text: c.uf);
    _localizacaoController =
        TextEditingController(text: c.localizacaoMapsUrl);
    _nomeResponsavelController = TextEditingController(text: c.nomeResponsavel);
    _telefoneController = TextEditingController(text: c.telefoneResponsavel);
    _emailController = TextEditingController(text: c.emailResponsavel ?? '');
    _prazoController = TextEditingController(text: '${c.prazoAcertoDias}');
    _observacoesController =
        TextEditingController(text: c.observacoesOperacionais ?? '');
    _frequenciaVisitaDias = c.frequenciaVisitaDiasPadrao;
    if (!_frequenciasPermitidas.contains(_frequenciaVisitaDias)) {
      _frequenciaVisitaDias = 30;
    }
    _periodoPreferencial = c.periodoPreferencialVisita;
    _antecedenciaAviso = c.antecedenciaAvisoVisita;
  }

  @override
  void dispose() {
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
    _observacoesController.dispose();
    super.dispose();
  }

  Future<void> _handleSalvar() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;

    final usuario = ref.read(appUserProvider).value;
    final clienteId = widget.cliente.id;
    if (usuario == null || clienteId == null) {
      setState(() =>
      _errorMessage = 'Sessão inválida. Faça login novamente.');
      return;
    }
    final podeEditar = usuario.role == UserRole.admin ||
        usuario.role == UserRole.financeiro ||
        (usuario.role == UserRole.vendedor &&
            widget.cliente.vendedorResponsavelId == usuario.uid);
    if (!podeEditar || usuario.orgId != widget.cliente.orgId) {
      setState(() => _errorMessage =
      'Você não tem permissão para editar este cliente.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final camposAlterados =
      await ref.read(clienteRepositoryProvider).editarDados(
        clienteId: clienteId,
        orgId: usuario.orgId,
        usuarioId: usuario.uid,
        usuarioNome:
        usuario.nome.trim().isEmpty ? usuario.email : usuario.nome,
        usuarioPerfil: usuario.role.name,
        nome: _nomeController.text.trim().toUpperCase(),
        nomeFantasia: _isPJ && _nomeFantasiaController.text.trim().isNotEmpty
            ? _nomeFantasiaController.text.trim().toUpperCase()
            : null,
        cep: _cepController.text.replaceAll(RegExp(r'[^0-9]'), ''),
        logradouro: _logradouroController.text.trim().toUpperCase(),
        numero: _numeroController.text.trim().toUpperCase(),
        complemento: _complementoController.text.trim().isEmpty
            ? null
            : _complementoController.text.trim().toUpperCase(),
        bairro: _bairroController.text.trim().toUpperCase(),
        cidade: _cidadeController.text.trim().toUpperCase(),
        uf: _ufController.text.trim().toUpperCase(),
        nomeResponsavel:
        _nomeResponsavelController.text.trim().toUpperCase(),
        telefoneResponsavel:
        _telefoneController.text.replaceAll(RegExp(r'[^0-9]'), ''),
        emailResponsavel: _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim().toLowerCase(),
        prazoAcertoDias: int.tryParse(_prazoController.text) ?? 7,
        localizacaoMapsUrl: _localizacaoController.text.trim(),
        observacoesOperacionais:
        _observacoesController.text.trim().isEmpty
            ? null
            : _observacoesController.text.trim(),
        frequenciaVisitaDiasPadrao: _frequenciaVisitaDias,
        periodoPreferencialVisita: _periodoPreferencial,
        antecedenciaAvisoVisita: _antecedenciaAviso,
      );

      ref.invalidate(clienteByIdProvider(clienteId));
      ref.invalidate(clientesListProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              camposAlterados.isEmpty
                  ? 'Nenhuma alteração foi identificada.'
                  : 'Dados atualizados e alteração registrada.',
            ),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e, stack) {
      debugPrint('Erro ao editar cliente: $e\n$stack');
      if (mounted) {
        setState(() =>
        _errorMessage = 'Não foi possível salvar. Tente novamente.');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Editar dados do cliente')),
      body: SingleChildScrollView(
        child: ResponsiveCenter(
          maxWidth: 560,
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Text('Identificação', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: formatarCpfCnpj(widget.cliente.cpfCnpj),
                  enabled: false,
                  decoration: const InputDecoration(
                    labelText: 'CPF/CNPJ',
                    helperText:
                    'O documento não pode ser alterado nesta tela.',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nomeController,
                  enabled: !_isSaving,
                  decoration: InputDecoration(
                      labelText: _isPJ ? 'Razão social' : 'Nome completo'),
                  validator: (v) =>
                  (v == null || v.isEmpty) ? 'Campo obrigatório' : null,
                ),
                if (_isPJ) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nomeFantasiaController,
                    enabled: !_isSaving,
                    decoration: const InputDecoration(labelText: 'Nome fantasia'),
                  ),
                ],
                const Divider(height: 40),
                Text('Endereço', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cepController,
                  enabled: !_isSaving,
                  keyboardType: TextInputType.number,
                  inputFormatters: [CepInputFormatter()],
                  decoration: const InputDecoration(labelText: 'CEP'),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Campo obrigatório';
                    final digitos = v.replaceAll(RegExp(r'[^0-9]'), '');
                    if (digitos.length != 8) return 'CEP precisa ter 8 números';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _logradouroController,
                        enabled: !_isSaving,
                        decoration: const InputDecoration(labelText: 'Rua'),
                        validator: (v) =>
                        (v == null || v.isEmpty) ? 'Obrigatório' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _numeroController,
                        enabled: !_isSaving,
                        decoration: const InputDecoration(
                            labelText: 'Número', hintText: 'ou S/N'),
                        validator: (v) =>
                        (v == null || v.isEmpty) ? 'Obrigatório' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _bairroController,
                        enabled: !_isSaving,
                        decoration: const InputDecoration(labelText: 'Bairro'),
                        validator: (v) =>
                        (v == null || v.isEmpty) ? 'Obrigatório' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _complementoController,
                        enabled: !_isSaving,
                        decoration: const InputDecoration(
                            labelText: 'Complemento (opcional)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _cidadeController,
                        enabled: !_isSaving,
                        decoration: const InputDecoration(labelText: 'Cidade'),
                        validator: (v) =>
                        (v == null || v.isEmpty) ? 'Obrigatório' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _ufController,
                        enabled: !_isSaving,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(2),
                          FilteringTextInputFormatter.allow(RegExp('[a-zA-Z]')),
                        ],
                        decoration: const InputDecoration(labelText: 'UF'),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Obrigatório';
                          if (v.length != 2) return 'UF inválida';
                          if (!_ufsValidas.contains(v.toUpperCase())) {
                            return 'UF inválida';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _localizacaoController,
                  enabled: !_isSaving,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Link da localização no Google Maps',
                    hintText: 'https://maps.app.goo.gl/...',
                  ),
                  validator: (v) {
                    final texto = (v ?? '').trim();
                    if (texto.isEmpty) return 'Campo obrigatório';
                    final uri = Uri.tryParse(texto);
                    if (uri == null ||
                        !uri.hasScheme ||
                        (uri.scheme != 'http' && uri.scheme != 'https')) {
                      return 'Informe um link válido';
                    }
                    return null;
                  },
                ),
                const Divider(height: 40),
                Text('Responsável', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nomeResponsavelController,
                  enabled: !_isSaving,
                  decoration:
                  const InputDecoration(labelText: 'Nome do responsável'),
                  validator: (v) =>
                  (v == null || v.isEmpty) ? 'Campo obrigatório' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _telefoneController,
                  enabled: !_isSaving,
                  decoration: const InputDecoration(
                      labelText: 'Telefone do responsável'),
                  keyboardType: TextInputType.phone,
                  inputFormatters: [TelefoneInputFormatter()],
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Campo obrigatório';
                    final digitos = v.replaceAll(RegExp(r'[^0-9]'), '');
                    if (digitos.length != 10 && digitos.length != 11) {
                      return 'Telefone precisa ter 10 ou 11 números';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  enabled: !_isSaving,
                  decoration:
                  const InputDecoration(labelText: 'E-mail (opcional)'),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                        .hasMatch(v.trim());
                    return ok ? null : 'E-mail inválido';
                  },
                ),
                const Divider(height: 40),
                Text('Operação', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _prazoController,
                  enabled: !_isSaving,
                  decoration:
                  const InputDecoration(labelText: 'Prazo de acerto (dias)'),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Obrigatório';
                    final dias = int.tryParse(v);
                    if (dias == null || dias <= 0) {
                      return 'Precisa ser maior que zero';
                    }
                    if (dias > 120) return 'Máximo de 120 dias';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: _frequenciaVisitaDias,
                  decoration: const InputDecoration(
                    labelText: 'Periodicidade das visitas',
                  ),
                  items: _frequenciasPermitidas
                      .map(
                        (dias) => DropdownMenuItem(
                      value: dias,
                      child: Text('$dias dias'),
                    ),
                  )
                      .toList(),
                  onChanged: _isSaving
                      ? null
                      : (valor) {
                    if (valor != null) {
                      setState(() => _frequenciaVisitaDias = valor);
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<PeriodoPreferencialVisita>(
                  value: _periodoPreferencial,
                  decoration: const InputDecoration(
                    labelText: 'Melhor período para visita',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: PeriodoPreferencialVisita.qualquerHorario,
                      child: Text('Qualquer horário'),
                    ),
                    DropdownMenuItem(
                      value: PeriodoPreferencialVisita.manha,
                      child: Text('Manhã'),
                    ),
                    DropdownMenuItem(
                      value: PeriodoPreferencialVisita.tarde,
                      child: Text('Tarde'),
                    ),
                    DropdownMenuItem(
                      value: PeriodoPreferencialVisita.noite,
                      child: Text('Noite'),
                    ),
                  ],
                  onChanged: _isSaving
                      ? null
                      : (valor) {
                    if (valor != null) {
                      setState(() => _periodoPreferencial = valor);
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<AntecedenciaAvisoVisita>(
                  value: _antecedenciaAviso,
                  decoration: const InputDecoration(
                    labelText: 'Avisar antes da visita',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: AntecedenciaAvisoVisita.naoAvisar,
                      child: Text('Não avisar'),
                    ),
                    DropdownMenuItem(
                      value: AntecedenciaAvisoVisita.mesmoDia,
                      child: Text('No mesmo dia'),
                    ),
                    DropdownMenuItem(
                      value: AntecedenciaAvisoVisita.umDiaAntes,
                      child: Text('Um dia antes'),
                    ),
                  ],
                  onChanged: _isSaving
                      ? null
                      : (valor) {
                    if (valor != null) {
                      setState(() => _antecedenciaAviso = valor);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _observacoesController,
                  enabled: !_isSaving,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 600,
                  decoration: const InputDecoration(
                    labelText: 'Observações operacionais',
                    hintText:
                    'Ex.: responsável só está à tarde; ligar antes da visita.',
                    alignLabelWithHint: true,
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isSaving ? null : _handleSalvar,
                  child: _isSaving
                      ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Text('Salvar alterações'),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
