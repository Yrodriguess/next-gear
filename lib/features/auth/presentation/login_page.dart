import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import 'auth_providers.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _canSubmit = false;
  bool _manterConectado = true;

  bool _autoLoginDisparado = false;

  String? _errorMessage;

  int _failedAttempts = 0;

  DateTime? _cooldownUntil;
  Timer? _cooldownTimer;

  int _cooldownSecondsLeft = 0;

  static const _maxAttemptsBeforeCooldown = 4;
  static const _cooldownDurationSeconds = 30;

  static const _logoAsset = 'assets/images/logo_nextgear.png';

  static final RegExp _emailRegex =
  RegExp(r'^[\w\.\-\+]+@[\w\-]+\.[\w\-\.]+$');

  static final RegExp _senhaRegex = RegExp(r'^\d{6}$');

  static const _codigosDeCredencialInvalida = {
    'invalid-credential',
    'wrong-password',
    'user-not-found',
  };

  @override
  void initState() {
    super.initState();

    _emailController.addListener(_onFormChanged);
    _passwordController.addListener(_onFormChanged);

    _emailFocusNode.addListener(_onEmailFocusChange);
  }

  @override
  void dispose() {
    _emailController.removeListener(_onFormChanged);
    _passwordController.removeListener(_onFormChanged);

    _emailFocusNode.removeListener(_onEmailFocusChange);

    _emailController.dispose();
    _passwordController.dispose();

    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();

    _cooldownTimer?.cancel();

    super.dispose();
  }

  // =========================================================
  // CONTROLE DO FORMULÁRIO
  // =========================================================

  void _onFormChanged() {
    if (!mounted) return;

    final email = _emailController.text.trim();
    final senha = _passwordController.text;

    final canSubmit =
        email.isNotEmpty &&
            senha.length == 6;

    setState(() {
      _canSubmit = canSubmit;

      // Se o usuário começou a corrigir os dados,
      // removemos a mensagem de erro anterior.
      if (_errorMessage != null) {
        _errorMessage = null;
      }
    });
  }

  void _onEmailFocusChange() {
    if (_emailFocusNode.hasFocus) return;

    final email = _emailController.text.trim();

    if (email == _emailController.text) return;

    _emailController.value = _emailController.value.copyWith(
      text: email,
      selection: TextSelection.collapsed(
        offset: email.length,
      ),
    );
  }

  // =========================================================
  // LOGIN AUTOMÁTICO AO DIGITAR 6 NÚMEROS
  // =========================================================

  void _onPasswordChanged(String value) {
    // Se apagou algum número, permite uma nova tentativa
    // quando completar os 6 dígitos novamente.
    if (value.length < 6) {
      _autoLoginDisparado = false;
      return;
    }

    if (value.length != 6) return;

    final email = _emailController.text.trim();

    if (email.isEmpty) return;

    if (_isLoading) return;

    if (_emCooldown) return;

    if (_autoLoginDisparado) return;

    _autoLoginDisparado = true;

    // Aguarda o TextField terminar de atualizar o valor
    // antes de disparar o login.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (_passwordController.text.length == 6 &&
          _emailController.text.trim().isNotEmpty &&
          !_isLoading &&
          !_emCooldown) {
        _handleLogin();
      }
    });
  }

  // =========================================================
  // COOLDOWN
  // =========================================================

  bool get _emCooldown =>
      _cooldownUntil != null &&
          DateTime.now().isBefore(_cooldownUntil!);

  bool get _botaoHabilitado =>
      !_isLoading &&
          !_emCooldown &&
          _canSubmit;

  void _iniciarCooldown() {
    _cooldownUntil = DateTime.now().add(
      const Duration(
        seconds: _cooldownDurationSeconds,
      ),
    );

    _cooldownSecondsLeft = _cooldownDurationSeconds;

    _cooldownTimer?.cancel();

    _cooldownTimer = Timer.periodic(
      const Duration(seconds: 1),
          (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        final remaining =
            _cooldownUntil!.difference(DateTime.now()).inSeconds;

        if (remaining <= 0) {
          timer.cancel();

          setState(() {
            _cooldownSecondsLeft = 0;
            _cooldownUntil = null;
            _failedAttempts = 0;
            _autoLoginDisparado = false;
          });
        } else {
          setState(() {
            _cooldownSecondsLeft = remaining;
          });
        }
      },
    );
  }

  // =========================================================
  // LOGIN
  // =========================================================

  Future<void> _handleLogin() async {
    if (_isLoading || _emCooldown) return;

    FocusScope.of(context).unfocus();

    // A validação acontece somente aqui.
    // Portanto a tela não começa com os campos vermelhos.
    final formValido =
        _formKey.currentState?.validate() ?? false;

    if (!formValido) {
      _autoLoginDisparado = false;
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // -------------------------------------------------------
      // WEB
      // -------------------------------------------------------

      if (kIsWeb) {
        await FirebaseAuth.instance.setPersistence(
          _manterConectado
              ? Persistence.LOCAL
              : Persistence.SESSION,
        );
      }

      // -------------------------------------------------------
      // AUTENTICAÇÃO
      // -------------------------------------------------------

      await ref.read(authRepositoryProvider).signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;

      // -------------------------------------------------------
      // BLOQUEIO DE ACESSO (ativo: false no Firestore)
      // -------------------------------------------------------
      //
      // O Firebase Auth autentica normalmente mesmo que o usuário
      // esteja marcado como bloqueado no Firestore — esse campo não
      // é verificado pelo Auth em si. Por isso, checamos o AppUser
      // logo após o login e derrubamos a sessão se ele estiver
      // inativo, antes de deixar a navegação prosseguir.
      //
      // OBS: isso só cobre o momento do login. Se o objetivo é
      // também derrubar uma sessão já aberta no instante em que ela
      // for bloqueada, é preciso um guard equivalente em nível de
      // app (ex.: um listener/redirect que observa appUserProvider
      // continuamente), não só aqui.
      final appUser = await ref.read(appUserProvider.future);

      if (appUser != null && !appUser.ativo) {
        await ref.read(authRepositoryProvider).signOut();

        if (!mounted) return;

        _autoLoginDisparado = false;

        setState(() {
          _errorMessage =
          'Seu acesso está bloqueado. Entre em contato com o '
              'administrador.';
        });

        return;
      }

      TextInput.finishAutofillContext();
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;

      // Permite nova tentativa depois de corrigir a senha.
      _autoLoginDisparado = false;

      if (_codigosDeCredencialInvalida.contains(error.code)) {
        _registrarFalha();
      }

      setState(() {
        _errorMessage = _mensagemDeErro(error.code);
      });
    } catch (_) {
      if (!mounted) return;

      _autoLoginDisparado = false;

      setState(() {
        _errorMessage =
        'Ocorreu um erro inesperado. '
            'Tente novamente em instantes.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _registrarFalha() {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      HapticFeedback.lightImpact();
    }

    _failedAttempts++;

    if (_failedAttempts >= _maxAttemptsBeforeCooldown) {
      _iniciarCooldown();
    }
  }

  // =========================================================
  // RECUPERAÇÃO DE SENHA
  // =========================================================

  Future<void> _abrirRecuperacaoSenha() async {
    final controller = TextEditingController(
      text: _emailController.text.trim(),
    );

    final formKey = GlobalKey<FormState>();

    var sending = false;

    final sent = await showDialog<bool>(
      context: context,
      barrierDismissible: !sending,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text(
                'Recuperar senha',
              ),
              content: SizedBox(
                width: 400,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Informe seu e-mail para receber '
                            'as instruções de recuperação.',
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: controller,
                        autofocus: kIsWeb,
                        enabled: !sending,
                        keyboardType:
                        TextInputType.emailAddress,
                        textInputAction:
                        TextInputAction.done,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: const [
                          AutofillHints.email,
                        ],
                        decoration:
                        const InputDecoration(
                          labelText: 'E-mail',
                          prefixIcon: Icon(
                            Icons.email_outlined,
                          ),
                        ),
                        validator: _validarEmail,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: sending
                      ? null
                      : () {
                    Navigator.of(
                      dialogContext,
                    ).pop(false);
                  },
                  child: const Text(
                    'Cancelar',
                  ),
                ),
                FilledButton(
                  onPressed: sending
                      ? null
                      : () async {
                    if (!formKey
                        .currentState!
                        .validate()) {
                      return;
                    }

                    setDialogState(() {
                      sending = true;
                    });

                    try {
                      await FirebaseAuth.instance
                          .sendPasswordResetEmail(
                        email:
                        controller.text.trim(),
                      );

                      if (dialogContext.mounted) {
                        Navigator.of(
                          dialogContext,
                        ).pop(true);
                      }
                    } on FirebaseAuthException catch (
                    error) {
                      if (!dialogContext.mounted) {
                        return;
                      }

                      setDialogState(() {
                        sending = false;
                      });

                      ScaffoldMessenger.of(
                        dialogContext,
                      ).showSnackBar(
                        SnackBar(
                          content: Text(
                            _mensagemRecuperacao(
                              error.code,
                            ),
                          ),
                        ),
                      );
                    }
                  },
                  child: sending
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child:
                    CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                      : const Text(
                    'Enviar',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();

    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Instruções de recuperação enviadas '
                'para seu e-mail.',
          ),
        ),
      );
    }
  }

  // =========================================================
  // VALIDAÇÕES
  // =========================================================

  String? _validarEmail(String? value) {
    final email = value?.trim() ?? '';

    if (email.isEmpty) {
      return 'Informe o e-mail';
    }

    if (!_emailRegex.hasMatch(email)) {
      return 'Informe um e-mail válido';
    }

    return null;
  }

  String? _validarSenha(String? value) {
    final senha = value ?? '';

    if (senha.isEmpty) {
      return 'Informe a senha';
    }

    if (!_senhaRegex.hasMatch(senha)) {
      return 'A senha deve ter exatamente 6 dígitos';
    }

    return null;
  }

  // =========================================================
  // MENSAGENS
  // =========================================================

  String _mensagemDeErro(String code) => switch (code) {
    'user-not-found' ||
    'wrong-password' ||
    'invalid-credential' =>
    'E-mail ou senha incorretos.',

    'invalid-email' =>
    'E-mail inválido.',

    'user-disabled' =>
    'Este usuário está desativado. '
        'Entre em contato com o suporte.',

    'too-many-requests' =>
    'Muitas tentativas. Aguarde um instante '
        'e tente novamente.',

    'network-request-failed' =>
    'Falha de conexão. Verifique sua internet '
        'e tente novamente.',

    _ =>
    'Não foi possível entrar. Tente novamente.',
  };

  String _mensagemRecuperacao(String code) =>
      switch (code) {
        'invalid-email' =>
        'Informe um e-mail válido.',

        'network-request-failed' =>
        'Verifique sua conexão e tente novamente.',

        'too-many-requests' =>
        'Muitas solicitações. Aguarde e tente novamente.',

        _ =>
        'Não foi possível enviar o e-mail de recuperação.',
      };

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    final colorScheme =
        Theme.of(context).colorScheme;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final desktop =
              constraints.maxWidth >= 900;

          return Container(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              gradient: desktop
                  ? null
                  : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colorScheme.surface,
                  colorScheme.primary.withValues(
                    alpha: 0.06,
                  ),
                ],
              ),
            ),
            child: SafeArea(
              child: desktop
                  ? Row(
                children: [
                  const Expanded(
                    flex: 5,
                    child: _BrandPanel(),
                  ),
                  Expanded(
                    flex: 4,
                    child: Center(
                      child:
                      SingleChildScrollView(
                        padding:
                        const EdgeInsets.all(
                          40,
                        ),
                        child: _LoginCard(
                          child: _buildForm(
                            context,
                            desktop: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              )
                  : Center(
                child:
                SingleChildScrollView(
                  padding:
                  const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 24,
                  ),
                  child: ConstrainedBox(
                    constraints:
                    const BoxConstraints(
                      maxWidth: 440,
                    ),
                    child: _buildForm(
                      context,
                      desktop: false,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // =========================================================
  // FORMULÁRIO
  // =========================================================

  Widget _buildForm(
      BuildContext context, {
        required bool desktop,
      }) {
    final theme = Theme.of(context);

    return Form(
      key: _formKey,

      // IMPORTANTE:
      // Não mostra erro/vermelho simplesmente porque
      // o usuário clicou ou entrou no campo.
      autovalidateMode:
      AutovalidateMode.disabled,

      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
        CrossAxisAlignment.stretch,
        children: [
          // ===================================================
          // LOGO MOBILE
          // ===================================================

          if (!desktop) ...[
            Center(
              child: Image.asset(
                _logoAsset,
                width: 180,
                height: 140,
                fit: BoxFit.contain,
                semanticLabel:
                'NEXT GEAR Acessórios',
                errorBuilder:
                    (_, __, ___) =>
                const Icon(
                  Icons.settings_suggest_outlined,
                  size: 72,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],

          // ===================================================
          // TÍTULO
          // ===================================================

          Text(
            'Bem-vindo de volta',
            textAlign: desktop
                ? TextAlign.left
                : TextAlign.center,
            style:
            theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'Acesse sua conta para continuar',
            textAlign: desktop
                ? TextAlign.left
                : TextAlign.center,
            style:
            theme.textTheme.bodyMedium?.copyWith(
              color:
              theme.colorScheme.onSurfaceVariant,
            ),
          ),

          const SizedBox(height: 32),

          // ===================================================
          // CAMPOS
          // ===================================================

          AutofillGroup(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.stretch,
              children: [
                // ---------------------------------------------
                // E-MAIL
                // ---------------------------------------------

                TextFormField(
                  controller: _emailController,
                  focusNode: _emailFocusNode,

                  autofocus: desktop,

                  enabled: !_isLoading,

                  keyboardType:
                  TextInputType.emailAddress,

                  textInputAction:
                  TextInputAction.next,

                  autocorrect: false,

                  enableSuggestions: false,

                  autofillHints: const [
                    AutofillHints.username,
                    AutofillHints.email,
                  ],

                  decoration: InputDecoration(
                    labelText: 'E-mail',
                    hintText:
                    'seuemail@exemplo.com',
                    prefixIcon: const Icon(
                      Icons.email_outlined,
                    ),
                    suffixIcon:
                    _emailController.text.isNotEmpty
                        ? IconButton(
                      tooltip:
                      'Limpar e-mail',
                      onPressed: _isLoading
                          ? null
                          : () {
                        _emailController
                            .clear();

                        _autoLoginDisparado =
                        false;
                      },
                      icon: const Icon(
                        Icons.close,
                      ),
                    )
                        : null,
                  ),

                  validator: _validarEmail,

                  onFieldSubmitted: (_) {
                    _passwordFocusNode
                        .requestFocus();
                  },
                ),

                const SizedBox(height: 16),

                // ---------------------------------------------
                // SENHA
                // ---------------------------------------------

                TextFormField(
                  controller:
                  _passwordController,

                  focusNode:
                  _passwordFocusNode,

                  enabled: !_isLoading,

                  obscureText:
                  _obscurePassword,

                  // No celular abre teclado numérico.
                  keyboardType:
                  TextInputType.number,

                  textInputAction:
                  TextInputAction.done,

                  // Somente números e no máximo 6.
                  inputFormatters: [
                    FilteringTextInputFormatter
                        .digitsOnly,
                    LengthLimitingTextInputFormatter(
                      6,
                    ),
                  ],

                  autofillHints: const [
                    AutofillHints.password,
                  ],

                  maxLength: 6,

                  decoration: InputDecoration(
                    labelText: 'Senha',
                    hintText: '6 dígitos',

                    // Não mostra 0/6 embaixo.
                    counterText: '',

                    prefixIcon: const Icon(
                      Icons.lock_outline,
                    ),

                    suffixIcon: IconButton(
                      tooltip:
                      _obscurePassword
                          ? 'Mostrar senha'
                          : 'Ocultar senha',
                      onPressed: _isLoading
                          ? null
                          : () {
                        setState(() {
                          _obscurePassword =
                          !_obscurePassword;
                        });
                      },
                      icon: Icon(
                        _obscurePassword
                            ? Icons
                            .visibility_outlined
                            : Icons
                            .visibility_off_outlined,
                      ),
                    ),
                  ),

                  validator:
                  _validarSenha,

                  // LOGIN AUTOMÁTICO NO 6º DÍGITO
                  onChanged:
                  _onPasswordChanged,

                  // Continua aceitando Enter também.
                  onFieldSubmitted: (_) {
                    if (_botaoHabilitado) {
                      _handleLogin();
                    }
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // ===================================================
          // MANTER CONECTADO / ESQUECI A SENHA
          // ===================================================

          Row(
            children: [
              if (kIsWeb)
                Expanded(
                  child: CheckboxListTile(
                    contentPadding:
                    EdgeInsets.zero,
                    dense: true,
                    controlAffinity:
                    ListTileControlAffinity
                        .leading,
                    value:
                    _manterConectado,
                    onChanged: _isLoading
                        ? null
                        : (value) {
                      setState(() {
                        _manterConectado =
                            value ?? true;
                      });
                    },
                    title: const Text(
                      'Manter conectado',
                    ),
                  ),
                )
              else
                const Spacer(),

              TextButton(
                onPressed: _isLoading
                    ? null
                    : _abrirRecuperacaoSenha,
                child: const Text(
                  'Esqueci minha senha',
                ),
              ),
            ],
          ),

          // ===================================================
          // ERRO DE LOGIN
          // ===================================================

          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            _MessageBox(
              icon: Icons.error_outline,
              message: _errorMessage!,
              color: AppColors.error,
            ),
          ],

          // ===================================================
          // COOLDOWN
          // ===================================================

          if (_emCooldown) ...[
            const SizedBox(height: 12),
            _MessageBox(
              icon:
              Icons.timer_outlined,
              message:
              'Muitas tentativas incorretas. '
                  'Tente novamente em '
                  '${_cooldownSecondsLeft}s.',
              color: Colors.orange,
            ),
          ],

          const SizedBox(height: 24),

          // ===================================================
          // BOTÃO ENTRAR
          // ===================================================

          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed:
              _botaoHabilitado
                  ? _handleLogin
                  : null,
              child: AnimatedSwitcher(
                duration:
                const Duration(
                  milliseconds: 180,
                ),
                child: _isLoading
                    ? const SizedBox(
                  key:
                  ValueKey(
                    'loading',
                  ),
                  width: 22,
                  height: 22,
                  child:
                  CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
                    : Text(
                  _emCooldown
                      ? 'Aguarde ${_cooldownSecondsLeft}s'
                      : 'Entrar',
                  key: ValueKey(
                    _emCooldown,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ===================================================
          // RODAPÉ
          // ===================================================

          Text(
            'Acesso exclusivo para usuários autorizados.',
            textAlign: TextAlign.center,
            style:
            theme.textTheme.bodySmall?.copyWith(
              color:
              theme.colorScheme.onSurfaceVariant,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            'NEXT GEAR • Versão 1.0.0',
            textAlign: TextAlign.center,
            style:
            theme.textTheme.labelSmall?.copyWith(
              color:
              theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================
// CARD DO LOGIN - DESKTOP
// ===========================================================

class _LoginCard extends StatelessWidget {
  final Widget child;

  const _LoginCard({
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints:
      const BoxConstraints(
        maxWidth: 440,
      ),
      child: Card(
        elevation: 6,
        clipBehavior:
        Clip.antiAlias,
        shape:
        RoundedRectangleBorder(
          borderRadius:
          BorderRadius.circular(
            24,
          ),
        ),
        child: Padding(
          padding:
          const EdgeInsets.symmetric(
            horizontal: 36,
            vertical: 40,
          ),
          child: child,
        ),
      ),
    );
  }
}

// ===========================================================
// PAINEL LATERAL - DESKTOP
// ===========================================================

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration:
      const BoxDecoration(
        gradient: LinearGradient(
          begin:
          Alignment.topLeft,
          end:
          Alignment.bottomRight,
          colors: [
            Color(0xFF111315),
            Color(0xFF17221B),
          ],
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints:
          const BoxConstraints(
            maxWidth: 560,
          ),
          child: Padding(
            padding:
            const EdgeInsets.all(
              56,
            ),
            child: Column(
              mainAxisSize:
              MainAxisSize.min,
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Center(
                  child: Image.asset(
                    _LoginPageState
                        ._logoAsset,
                    width: 300,
                    height: 260,
                    fit: BoxFit.contain,
                    semanticLabel:
                    'NEXT GEAR Acessórios',
                    errorBuilder:
                        (_, __, ___) =>
                    const Icon(
                      Icons
                          .settings_suggest_outlined,
                      color:
                      Colors.white,
                      size: 120,
                    ),
                  ),
                ),

                const SizedBox(
                  height: 36,
                ),

                const Text(
                  'Sua operação em um só lugar.',
                  style: TextStyle(
                    color:
                    Colors.white,
                    fontSize: 32,
                    fontWeight:
                    FontWeight.w700,
                  ),
                ),

                const SizedBox(
                  height: 12,
                ),

                Text(
                  'Gerencie clientes, consignações, estoque '
                      'e expositores com mais controle e agilidade.',
                  style: TextStyle(
                    color: Colors.white.withValues(
                      alpha: 0.88,
                    ),
                    fontSize: 17,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================
// CAIXA DE MENSAGEM
// ===========================================================

class _MessageBox extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;

  const _MessageBox({
    required this.icon,
    required this.message,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding:
        const EdgeInsets.all(
          12,
        ),
        decoration:
        BoxDecoration(
          color:
          color.withValues(
            alpha: 0.10,
          ),
          borderRadius:
          BorderRadius.circular(
            10,
          ),
          border:
          Border.all(
            color:
            color.withValues(
              alpha: 0.35,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: color,
              size: 20,
            ),
            const SizedBox(
              width: 10,
            ),
            Expanded(
              child: Text(
                message,
              ),
            ),
          ],
        ),
      ),
    );
  }
}