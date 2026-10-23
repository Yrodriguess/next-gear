import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/responsive_center.dart';
import '../domain/app_user.dart';
import 'auth_providers.dart';

/// Remove acentos/diacríticos para permitir busca "joao" encontrar "João".
String _semAcentos(String texto) {
  const comAcento =
      'àáâãäåèéêëìíîïòóôõöùúûüçñÀÁÂÃÄÅÈÉÊËÌÍÎÏÒÓÔÕÖÙÚÛÜÇÑ';
  const semAcento =
      'aaaaaaeeeeiiiiooooouuuucnAAAAAAEEEEIIIIOOOOOUUUUCN';

  final buffer = StringBuffer();

  for (final char in texto.split('')) {
    final indice = comAcento.indexOf(char);
    buffer.write(indice == -1 ? char : semAcento[indice]);
  }

  return buffer.toString();
}

class UsuariosPage extends ConsumerStatefulWidget {
  const UsuariosPage({super.key});

  @override
  ConsumerState<UsuariosPage> createState() => _UsuariosPageState();
}

class _UsuariosPageState extends ConsumerState<UsuariosPage> {
  final _buscaController = TextEditingController();

  UserRole? _filtroRole;
  String _busca = '';

  // uids com uma ação de status em andamento — evita duplo toque
  // disparando duas chamadas concorrentes pro mesmo usuário.
  final Set<String> _idsProcessando = {};

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  String _roleLabel(UserRole role) => switch (role) {
    UserRole.admin => 'Admin',
    UserRole.financeiro => 'Financeiro',
    UserRole.vendedor => 'Vendedor',
    UserRole.estoque => 'Estoque',
    UserRole.cliente => 'Cliente',
  };

  IconData _roleIcon(UserRole role) => switch (role) {
    UserRole.admin => Icons.admin_panel_settings_outlined,
    UserRole.financeiro => Icons.account_balance_wallet_outlined,
    UserRole.vendedor => Icons.person_outline_rounded,
    UserRole.estoque => Icons.inventory_2_outlined,
    UserRole.cliente => Icons.storefront_outlined,
  };

  String _iniciais(String nome) {
    final partes = nome
        .trim()
        .split(RegExp(r'\s+'))
        .where((parte) => parte.isNotEmpty)
        .toList();

    if (partes.isEmpty) {
      return '?';
    }

    if (partes.length == 1) {
      final texto = partes.first;

      return texto.length >= 2
          ? texto.substring(0, 2).toUpperCase()
          : texto.toUpperCase();
    }

    return '${partes.first[0]}${partes.last[0]}'.toUpperCase();
  }

  String _formatarData(DateTime? data) {
    if (data == null) {
      return 'Data não disponível';
    }

    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');

    return '$dia/$mes/${data.year}';
  }

  List<AppUser> _filtrarUsuarios(List<AppUser> usuarios) {
    final busca = _semAcentos(_busca.trim().toLowerCase());

    final filtrados = usuarios.where((usuario) {
      final correspondeBusca =
          busca.isEmpty ||
              _semAcentos(usuario.nome.toLowerCase()).contains(busca) ||
              usuario.email.toLowerCase().contains(busca);

      final correspondeRole =
          _filtroRole == null || usuario.role == _filtroRole;

      return correspondeBusca && correspondeRole;
    }).toList();

    filtrados.sort(
          (a, b) => a.nome.toLowerCase().compareTo(
        b.nome.toLowerCase(),
      ),
    );

    return filtrados;
  }

  int _contarRole(
      List<AppUser> usuarios,
      UserRole role,
      ) {
    return usuarios.where((usuario) => usuario.role == role).length;
  }

  /// Quantos admins ativos existem na organização.
  int _contarAdminsAtivos(List<AppUser> usuarios) {
    return usuarios
        .where(
          (usuario) =>
      usuario.role == UserRole.admin && usuario.ativo,
    )
        .length;
  }

  /// Verdadeiro quando esse usuário é o único admin ativo restante —
  /// nesse caso ele não pode ser bloqueado nem ter o perfil trocado,
  /// senão a organização fica sem ninguém com acesso de administrador.
  bool _ehUltimoAdminAtivo(
      AppUser usuario,
      List<AppUser> usuarios,
      ) {
    return usuario.role == UserRole.admin &&
        usuario.ativo &&
        _contarAdminsAtivos(usuarios) <= 1;
  }

  void _abrirNovoUsuario() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const _NovoUsuarioPage(),
      ),
    );
  }

  void _abrirEditarUsuario(
      AppUser usuario,
      String usuarioAtualId,
      List<AppUser> usuarios,
      ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _EditarUsuarioPage(
          usuario: usuario,
          ehUsuarioAtual: usuario.uid == usuarioAtualId,
          ehUltimoAdminAtivo: _ehUltimoAdminAtivo(
            usuario,
            usuarios,
          ),
        ),
      ),
    );
  }

  Future<void> _copiarEmail(String email) async {
    await Clipboard.setData(ClipboardData(text: email));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('E-mail copiado.'),
        ),
      );
    }
  }

  Future<void> _alterarStatusUsuario(
      AppUser usuario,
      String usuarioAtualId,
      List<AppUser> usuarios,
      ) async {
    if (usuario.uid == usuarioAtualId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Você não pode bloquear sua própria conta.',
          ),
        ),
      );

      return;
    }

    // Já existe uma ação em andamento pra esse usuário — ignora
    // o novo toque em vez de disparar uma segunda chamada.
    if (_idsProcessando.contains(usuario.uid)) {
      return;
    }

    final novoStatus = !usuario.ativo;

    // Bloquear é o único caso perigoso aqui: reativar um admin nunca
    // reduz a contagem de admins ativos, então não precisa da checagem.
    if (!novoStatus && _ehUltimoAdminAtivo(usuario, usuarios)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não é possível bloquear o último administrador ativo. '
                'Promova outro usuário a Admin antes de bloquear este.',
          ),
        ),
      );

      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          novoStatus
              ? 'Reativar usuário?'
              : 'Bloquear usuário?',
        ),
        content: Text(
          novoStatus
              ? '${usuario.nome} voltará a ter acesso ao sistema.'
              : '${usuario.nome} deixará de ter acesso ao sistema.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(false);
            },
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(true);
            },
            child: Text(
              novoStatus ? 'Reativar' : 'Bloquear',
            ),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) {
      return;
    }

    setState(() {
      _idsProcessando.add(usuario.uid);
    });

    try {
      await ref
          .read(usuarioRepositoryProvider)
          .atualizarStatus(
        usuario.uid,
        novoStatus,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            novoStatus
                ? 'Usuário reativado.'
                : 'Usuário bloqueado.',
          ),
        ),
      );
    } catch (e, stack) {
      debugPrint(
        'Erro ao alterar status do usuário: $e\n$stack',
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível alterar o status do usuário.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _idsProcessando.remove(usuario.uid);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final usuarioAtualAsync = ref.watch(appUserProvider);
    final usuarioAtual = usuarioAtualAsync.value;

    if (usuarioAtualAsync.isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (usuarioAtual == null || usuarioAtual.orgId.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Usuários'),
        ),
        body: const Center(
          child: Text(
            'Não foi possível identificar a organização.',
          ),
        ),
      );
    }

    final usuariosAsync =
    ref.watch(usuariosListProvider(usuarioAtual.orgId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Usuários'),
      ),
      floatingActionButton: MediaQuery.sizeOf(context).width < 700
          ? FloatingActionButton.extended(
        onPressed: _abrirNovoUsuario,
        icon: const Icon(
          Icons.person_add_alt_1_rounded,
        ),
        label: const Text(
          'Novo usuário',
        ),
      )
          : null,
      body: usuariosAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (error, stack) {
          debugPrint(
            'Erro ao carregar usuários: $error\n$stack',
          );

          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 48,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Não foi possível carregar os usuários.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () {
                      ref.invalidate(
                        usuariosListProvider(
                          usuarioAtual.orgId,
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.refresh_rounded,
                    ),
                    label: const Text(
                      'Tentar novamente',
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        data: (usuarios) {
          final filtrados = _filtrarUsuarios(usuarios);

          return SafeArea(
            child: ResponsiveCenter(
              maxWidth: 1180,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  16,
                  20,
                  16,
                  100,
                ),
                children: [
                  _CabecalhoUsuarios(
                    totalUsuarios: usuarios.length,
                    onNovoUsuario: _abrirNovoUsuario,
                  ),

                  const SizedBox(height: 20),

                  _BarraBuscaUsuarios(
                    controller: _buscaController,
                    busca: _busca,
                    onChanged: (valor) {
                      setState(() {
                        _busca = valor;
                      });
                    },
                    onLimpar: () {
                      _buscaController.clear();

                      setState(() {
                        _busca = '';
                      });
                    },
                  ),

                  const SizedBox(height: 14),

                  _FiltrosUsuarios(
                    usuarios: usuarios,
                    filtroAtual: _filtroRole,
                    contarRole: _contarRole,
                    onSelecionar: (role) {
                      setState(() {
                        _filtroRole =
                        _filtroRole == role ? null : role;
                      });
                    },
                    onLimparFiltro: () {
                      setState(() {
                        _filtroRole = null;
                      });
                    },
                    roleLabel: _roleLabel,
                  ),

                  const SizedBox(height: 16),

                  Text(
                    _busca.isEmpty && _filtroRole == null
                        ? '${usuarios.length} usuário(s)'
                        : '${filtrados.length} resultado(s)',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),

                  const SizedBox(height: 10),

                  if (usuarios.isEmpty)
                    const _UsuariosVazio()
                  else if (filtrados.isEmpty)
                    const _NenhumResultado()
                  else
                    ...filtrados.map(
                          (usuario) => Padding(
                        padding: const EdgeInsets.only(
                          bottom: 10,
                        ),
                        child: _UsuarioCard(
                          usuario: usuario,
                          usuarioAtualId: usuarioAtual.uid,
                          iniciais: _iniciais(
                            usuario.nome,
                          ),
                          roleLabel: _roleLabel(
                            usuario.role,
                          ),
                          roleIcon: _roleIcon(
                            usuario.role,
                          ),
                          dataCriacao: _formatarData(
                            usuario.createdAt,
                          ),
                          processando: _idsProcessando.contains(
                            usuario.uid,
                          ),
                          impedirBloqueio: _ehUltimoAdminAtivo(
                            usuario,
                            usuarios,
                          ),
                          onEditar: () {
                            _abrirEditarUsuario(
                              usuario,
                              usuarioAtual.uid,
                              usuarios,
                            );
                          },
                          onAlterarStatus: () {
                            _alterarStatusUsuario(
                              usuario,
                              usuarioAtual.uid,
                              usuarios,
                            );
                          },
                          onCopiarEmail: () {
                            _copiarEmail(usuario.email);
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CabecalhoUsuarios extends StatelessWidget {
  final int totalUsuarios;
  final VoidCallback onNovoUsuario;

  const _CabecalhoUsuarios({
    required this.totalUsuarios,
    required this.onNovoUsuario,
  });

  @override
  Widget build(BuildContext context) {
    final desktop =
        MediaQuery.sizeOf(context).width >= 700;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Usuários',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Gerencie os usuários da sua organização.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '$totalUsuarios usuário(s) cadastrado(s)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (desktop)
          FilledButton.icon(
            onPressed: onNovoUsuario,
            icon: const Icon(
              Icons.person_add_alt_1_rounded,
            ),
            label: const Text(
              'Novo usuário',
            ),
          ),
      ],
    );
  }
}

class _BarraBuscaUsuarios extends StatelessWidget {
  final TextEditingController controller;
  final String busca;
  final ValueChanged<String> onChanged;
  final VoidCallback onLimpar;

  const _BarraBuscaUsuarios({
    required this.controller,
    required this.busca,
    required this.onChanged,
    required this.onLimpar,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Buscar por nome ou e-mail',
        prefixIcon: const Icon(
          Icons.search_rounded,
        ),
        suffixIcon: busca.isNotEmpty
            ? IconButton(
          tooltip: 'Limpar busca',
          onPressed: onLimpar,
          icon: const Icon(
            Icons.close_rounded,
          ),
        )
            : null,
      ),
    );
  }
}

class _FiltrosUsuarios extends StatelessWidget {
  final List<AppUser> usuarios;
  final UserRole? filtroAtual;

  final int Function(
      List<AppUser>,
      UserRole,
      ) contarRole;

  final ValueChanged<UserRole> onSelecionar;

  /// Chamado quando o chip "Todos" é tocado — sempre limpa o
  /// filtro, independente de qual role estava selecionada antes.
  final VoidCallback onLimparFiltro;

  final String Function(UserRole) roleLabel;

  const _FiltrosUsuarios({
    required this.usuarios,
    required this.filtroAtual,
    required this.contarRole,
    required this.onSelecionar,
    required this.onLimparFiltro,
    required this.roleLabel,
  });

  @override
  Widget build(BuildContext context) {
    const roles = [
      UserRole.admin,
      UserRole.financeiro,
      UserRole.vendedor,
      UserRole.estoque,
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ChoiceChip(
            label: Text(
              'Todos  ${usuarios.length}',
            ),
            selected: filtroAtual == null,
            onSelected: (_) {
              onLimparFiltro();
            },
          ),

          const SizedBox(width: 8),

          for (final role in roles) ...[
            ChoiceChip(
              label: Text(
                '${roleLabel(role)}  ${contarRole(usuarios, role)}',
              ),
              selected: filtroAtual == role,
              onSelected: (_) {
                onSelecionar(role);
              },
            ),

            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _UsuarioCard extends StatelessWidget {
  final AppUser usuario;
  final String usuarioAtualId;
  final String iniciais;
  final String roleLabel;
  final IconData roleIcon;
  final String dataCriacao;
  final bool processando;

  /// Verdadeiro quando este usuário é o último admin ativo — nesse
  /// caso a ação de bloquear fica desabilitada no menu.
  final bool impedirBloqueio;

  final VoidCallback onEditar;
  final VoidCallback onAlterarStatus;
  final VoidCallback onCopiarEmail;

  const _UsuarioCard({
    required this.usuario,
    required this.usuarioAtualId,
    required this.iniciais,
    required this.roleLabel,
    required this.roleIcon,
    required this.dataCriacao,
    required this.processando,
    required this.impedirBloqueio,
    required this.onEditar,
    required this.onAlterarStatus,
    required this.onCopiarEmail,
  });

  @override
  Widget build(BuildContext context) {
    final souEu =
        usuario.uid == usuarioAtualId;

    final corStatus = usuario.ativo
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.error;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compacto =
                constraints.maxWidth < 680;

            final avatar = CircleAvatar(
              radius: 25,
              backgroundColor: souEu
                  ? Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: .16)
                  : Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest,
              child: Text(
                iniciais,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: souEu
                      ? Theme.of(context)
                      .colorScheme
                      .primary
                      : null,
                ),
              ),
            );

            final identificacao = Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment:
                  WrapCrossAlignment.center,
                  children: [
                    Text(
                      usuario.nome,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(
                        fontWeight:
                        FontWeight.w700,
                      ),
                    ),
                    if (souEu)
                      Container(
                        padding:
                        const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(
                            alpha: .14,
                          ),
                          borderRadius:
                          BorderRadius.circular(
                            20,
                          ),
                        ),
                        child: Text(
                          'Você',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .primary,
                            fontWeight:
                            FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 3),

                Text(
                  usuario.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall,
                ),

                const SizedBox(height: 5),

                Text(
                  'Criado em: $dataCriacao',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant,
                  ),
                ),
              ],
            );

            final role = Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .outline
                      .withValues(
                    alpha: .5,
                  ),
                ),
                borderRadius:
                BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    roleIcon,
                    size: 17,
                    color: Theme.of(context)
                        .colorScheme
                        .primary,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    roleLabel,
                    style: const TextStyle(
                      fontWeight:
                      FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );

            final status = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: corStatus,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  usuario.ativo
                      ? 'Ativo'
                      : 'Bloqueado',
                  style: TextStyle(
                    color: corStatus,
                    fontWeight:
                    FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            );

            // Enquanto uma ação de status está em andamento pra esse
            // usuário, mostra um spinner no lugar do menu — impede
            // um segundo toque disparar uma chamada concorrente.
            final menu = processando
                ? const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              ),
            )
                : PopupMenuButton<String>(
              tooltip: 'Ações',
              onSelected: (value) {
                switch (value) {
                  case 'editar':
                    onEditar();
                    break;

                  case 'status':
                    onAlterarStatus();
                    break;

                  case 'copiar':
                    onCopiarEmail();
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'editar',
                  child: Row(
                    children: [
                      Icon(
                        Icons.edit_outlined,
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Editar usuário',
                      ),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'copiar',
                  child: Row(
                    children: [
                      Icon(
                        Icons.copy_outlined,
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Copiar e-mail',
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'status',
                  // Bloquear é desabilitado quando este é o último
                  // admin ativo — reativar nunca tem esse problema.
                  enabled: !souEu &&
                      !(usuario.ativo && impedirBloqueio),
                  child: Row(
                    children: [
                      Icon(
                        usuario.ativo
                            ? Icons.block_outlined
                            : Icons
                            .check_circle_outline,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          usuario.ativo
                              ? (impedirBloqueio
                              ? 'Bloquear acesso (último admin)'
                              : 'Bloquear acesso')
                              : 'Reativar acesso',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );

            if (compacto) {
              return Row(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  avatar,

                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        identificacao,

                        const SizedBox(height: 12),

                        Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          crossAxisAlignment:
                          WrapCrossAlignment.center,
                          children: [
                            role,
                            status,
                          ],
                        ),
                      ],
                    ),
                  ),

                  menu,
                ],
              );
            }

            return Row(
              children: [
                avatar,

                const SizedBox(width: 14),

                Expanded(
                  child: identificacao,
                ),

                const SizedBox(width: 20),

                SizedBox(
                  width: 170,
                  child: Align(
                    alignment:
                    Alignment.centerLeft,
                    child: role,
                  ),
                ),

                SizedBox(
                  width: 110,
                  child: status,
                ),

                menu,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _UsuariosVazio extends StatelessWidget {
  const _UsuariosVazio();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 60,
      ),
      child: Column(
        children: [
          Icon(
            Icons.group_outlined,
            size: 56,
            color: Theme.of(context)
                .colorScheme
                .onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'Nenhum usuário cadastrado',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(
              fontWeight:
              FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _NenhumResultado extends StatelessWidget {
  const _NenhumResultado();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 60,
      ),
      child: Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 52,
            color: Theme.of(context)
                .colorScheme
                .onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'Nenhum usuário encontrado.',
            style: Theme.of(context)
                .textTheme
                .titleSmall,
          ),
        ],
      ),
    );
  }
}

// ===========================================================
// EDITAR USUÁRIO
// ===========================================================

class _EditarUsuarioPage
    extends ConsumerStatefulWidget {
  final AppUser usuario;
  final bool ehUsuarioAtual;

  /// Verdadeiro quando este usuário é o único admin ativo da
  /// organização — o perfil dele não pode ser trocado nesta tela.
  final bool ehUltimoAdminAtivo;

  const _EditarUsuarioPage({
    required this.usuario,
    required this.ehUsuarioAtual,
    required this.ehUltimoAdminAtivo,
  });

  @override
  ConsumerState<_EditarUsuarioPage> createState() =>
      _EditarUsuarioPageState();
}

class _EditarUsuarioPageState
    extends ConsumerState<_EditarUsuarioPage> {
  final _formKey =
  GlobalKey<FormState>();

  late final TextEditingController
  _nomeController;

  late UserRole _roleSelecionada;

  bool _isSaving = false;

  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    _nomeController = TextEditingController(
      text: widget.usuario.nome,
    );

    _roleSelecionada =
        widget.usuario.role;
  }

  @override
  void dispose() {
    _nomeController.dispose();
    super.dispose();
  }

  String? _validarNome(String? value) {
    final nome =
        value?.trim() ?? '';

    if (nome.isEmpty) {
      return 'Informe o nome';
    }

    if (nome.length < 2) {
      return 'Nome muito curto';
    }

    return null;
  }

  Future<void> _salvar() async {
    if (_isSaving) {
      return;
    }

    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Rede de segurança: o dropdown já vem desabilitado nesse caso,
    // mas garantimos aqui também que o último admin não perde o
    // perfil de admin por essa tela.
    if (widget.ehUltimoAdminAtivo &&
        _roleSelecionada != UserRole.admin) {
      setState(() {
        _errorMessage =
        'Este é o último administrador ativo — não é possível '
            'trocar o perfil dele.';
      });

      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(usuarioRepositoryProvider)
          .atualizarUsuario(
        usuarioId:
        widget.usuario.uid,
        nome:
        _nomeController.text.trim(),
        role: widget.ehUsuarioAtual
            ? widget.usuario.role
            : _roleSelecionada,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Usuário atualizado!',
          ),
        ),
      );

      Navigator.of(context).pop();
    } catch (e, stack) {
      debugPrint(
        'Erro ao editar usuário: $e\n$stack',
      );

      if (mounted) {
        setState(() {
          _errorMessage =
          'Não foi possível salvar as alterações.';
        });
      }
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
    final corStatus =
    widget.usuario.ativo
        ? Theme.of(context)
        .colorScheme
        .primary
        : Theme.of(context)
        .colorScheme
        .error;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Editar usuário',
        ),
      ),

      bottomNavigationBar: Material(
        color: Theme.of(context)
            .scaffoldBackgroundColor,
        child: SafeArea(
          top: false,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color:
                  Theme.of(context)
                      .dividerColor,
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            child: Align(
              alignment: Alignment.center,
              heightFactor: 1,
              child: ConstrainedBox(
                constraints:
                const BoxConstraints(
                  maxWidth: 560,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                        _isSaving
                            ? null
                            : () {
                          Navigator.of(
                            context,
                          ).pop();
                        },
                        child: const Text(
                          'Cancelar',
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: FilledButton.icon(
                        onPressed:
                        _isSaving
                            ? null
                            : _salvar,
                        icon: _isSaving
                            ? const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                          CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                            : const Icon(
                          Icons
                              .save_outlined,
                        ),
                        label: Text(
                          _isSaving
                              ? 'Salvando...'
                              : 'Salvar alterações',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),

      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 560,
          ),
          child: Form(
            key: _formKey,
            autovalidateMode:
            AutovalidateMode
                .onUserInteraction,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                16,
                24,
                16,
                32,
              ),
              children: [
                Text(
                  'Editar usuário',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(
                    fontWeight:
                    FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  'Atualize os dados e permissões deste usuário.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(
                    color:
                    Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant,
                  ),
                ),

                const SizedBox(height: 24),

                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding:
                    const EdgeInsets.all(
                      20,
                    ),
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment
                          .stretch,
                      children: [
                        TextFormField(
                          controller:
                          _nomeController,
                          enabled:
                          !_isSaving,
                          textCapitalization:
                          TextCapitalization
                              .words,
                          textInputAction:
                          TextInputAction.next,
                          decoration:
                          const InputDecoration(
                            labelText:
                            'Nome completo *',
                            prefixIcon:
                            Icon(
                              Icons
                                  .person_outline_rounded,
                            ),
                          ),
                          validator:
                          _validarNome,
                        ),

                        const SizedBox(
                          height: 16,
                        ),

                        TextFormField(
                          initialValue:
                          widget.usuario.email,
                          enabled: false,
                          decoration:
                          const InputDecoration(
                            labelText: 'E-mail',
                            prefixIcon:
                            Icon(
                              Icons
                                  .alternate_email_rounded,
                            ),
                            helperText:
                            'O e-mail de acesso não pode ser alterado nesta tela.',
                          ),
                        ),

                        const SizedBox(
                          height: 16,
                        ),

                        DropdownButtonFormField<
                            UserRole>(
                          initialValue:
                          _roleSelecionada,
                          isExpanded: true,
                          decoration:
                          const InputDecoration(
                            labelText:
                            'Perfil',
                            prefixIcon:
                            Icon(
                              Icons
                                  .badge_outlined,
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value:
                              UserRole.admin,
                              child:
                              Text('Admin'),
                            ),
                            DropdownMenuItem(
                              value:
                              UserRole
                                  .financeiro,
                              child:
                              Text(
                                'Financeiro',
                              ),
                            ),
                            DropdownMenuItem(
                              value:
                              UserRole
                                  .vendedor,
                              child:
                              Text(
                                'Vendedor',
                              ),
                            ),
                            DropdownMenuItem(
                              value:
                              UserRole
                                  .estoque,
                              child:
                              Text(
                                'Estoque',
                              ),
                            ),
                          ],
                          onChanged: _isSaving ||
                              widget
                                  .ehUsuarioAtual ||
                              widget
                                  .ehUltimoAdminAtivo
                              ? null
                              : (value) {
                            if (value !=
                                null) {
                              setState(() {
                                _roleSelecionada =
                                    value;
                              });
                            }
                          },
                        ),

                        if (widget
                            .ehUsuarioAtual) ...[
                          const SizedBox(
                            height: 8,
                          ),
                          Text(
                            'Seu próprio perfil não pode ser alterado nesta tela.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                              color: Theme.of(
                                context,
                              )
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ] else if (widget
                            .ehUltimoAdminAtivo) ...[
                          const SizedBox(
                            height: 8,
                          ),
                          Text(
                            'Este é o último administrador ativo — '
                                'promova outro usuário a Admin antes '
                                'de trocar este perfil.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                              color: Theme.of(
                                context,
                              )
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],

                        const SizedBox(
                          height: 20,
                        ),

                        Container(
                          padding:
                          const EdgeInsets
                              .symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration:
                          BoxDecoration(
                            color: corStatus
                                .withValues(
                              alpha: .08,
                            ),
                            borderRadius:
                            BorderRadius
                                .circular(
                              10,
                            ),
                            border:
                            Border.all(
                              color: corStatus
                                  .withValues(
                                alpha: .25,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 9,
                                height: 9,
                                decoration:
                                BoxDecoration(
                                  color:
                                  corStatus,
                                  shape: BoxShape
                                      .circle,
                                ),
                              ),

                              const SizedBox(
                                width: 10,
                              ),

                              Expanded(
                                child: Text(
                                  widget.usuario
                                      .ativo
                                      ? 'Usuário ativo'
                                      : 'Usuário bloqueado',
                                  style:
                                  TextStyle(
                                    color:
                                    corStatus,
                                    fontWeight:
                                    FontWeight
                                        .w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                if (_errorMessage !=
                    null) ...[
                  const SizedBox(
                    height: 16,
                  ),
                  _ErroUsuario(
                    mensagem:
                    _errorMessage!,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================
// NOVO USUÁRIO
// ===========================================================

class _NovoUsuarioPage
    extends ConsumerStatefulWidget {
  const _NovoUsuarioPage();

  @override
  ConsumerState<_NovoUsuarioPage> createState() =>
      _NovoUsuarioPageState();
}

class _NovoUsuarioPageState
    extends ConsumerState<_NovoUsuarioPage> {
  final _formKey =
  GlobalKey<FormState>();

  final _nomeController =
  TextEditingController();

  final _emailController =
  TextEditingController();

  final _senhaController =
  TextEditingController();

  final _confirmarSenhaController =
  TextEditingController();

  UserRole _roleSelecionada =
      UserRole.vendedor;

  bool _isSaving = false;
  bool _mostrarSenha = false;
  bool _mostrarConfirmacao = false;

  String? _errorMessage;

  @override
  void dispose() {
    _nomeController.dispose();
    _emailController.dispose();
    _senhaController.dispose();
    _confirmarSenhaController.dispose();

    super.dispose();
  }

  String? _validarNome(String? value) {
    final nome =
        value?.trim() ?? '';

    if (nome.isEmpty) {
      return 'Informe o nome';
    }

    if (nome.length < 2) {
      return 'Nome muito curto';
    }

    return null;
  }

  String? _validarEmail(String? value) {
    final email =
        value?.trim().toLowerCase() ?? '';

    if (email.isEmpty) {
      return 'Informe o e-mail';
    }

    final valido = RegExp(
      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
    ).hasMatch(email);

    if (!valido) {
      return 'Informe um e-mail válido';
    }

    return null;
  }

  String? _validarSenha(String? value) {
    if (value == null ||
        value.length < 6) {
      return 'A senha deve ter pelo menos 6 caracteres';
    }

    return null;
  }

  String? _validarConfirmacao(
      String? value,
      ) {
    if (value !=
        _senhaController.text) {
      return 'As senhas não são iguais';
    }

    return null;
  }

  Future<void> _handleCriar() async {
    if (_isSaving) {
      return;
    }

    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final usuarioAtual =
        ref.read(appUserProvider).value;

    if (usuarioAtual == null ||
        usuarioAtual.orgId.isEmpty) {
      setState(() {
        _errorMessage =
        'Não foi possível identificar sua organização.';
      });

      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(usuarioRepositoryProvider)
          .criarUsuario(
        orgId:
        usuarioAtual.orgId,
        nome:
        _nomeController.text.trim(),
        email: _emailController.text
            .trim()
            .toLowerCase(),
        senha:
        _senhaController.text,
        role:
        _roleSelecionada,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Usuário criado com sucesso!',
          ),
        ),
      );

      Navigator.of(context).pop();
    } on FirebaseAuthException catch (error, stack) {
      debugPrint(
        'Erro ao criar usuário (${error.code}): '
            '${error.message}\n$stack',
      );

      if (mounted) {
        setState(() {
          _errorMessage = _mensagemErroCriacao(error.code);
        });
      }
    } catch (e, stack) {
      debugPrint(
        'Erro ao criar usuário: $e\n$stack',
      );

      if (mounted) {
        setState(() {
          _errorMessage =
          'Não foi possível criar o usuário. '
              'Verifique os dados e tente novamente.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  /// Traduz os códigos mais comuns do Firebase Auth pra uma mensagem
  /// que o usuário do painel entende. Assume que o
  /// usuarioRepositoryProvider deixa a FirebaseAuthException
  /// original subir sem embrulhar em outra exceção — se em algum
  /// momento o repository passar a envelopar o erro, o tipo
  /// capturado no catch acima precisa acompanhar essa mudança.
  String _mensagemErroCriacao(String code) => switch (code) {
    'email-already-in-use' =>
    'Este e-mail já está cadastrado no sistema.',

    'weak-password' =>
    'A senha é muito fraca. Use uma senha mais forte.',

    'invalid-email' =>
    'E-mail inválido.',

    'network-request-failed' =>
    'Falha de conexão. Verifique sua internet e tente novamente.',

    'too-many-requests' =>
    'Muitas tentativas. Aguarde um instante e tente novamente.',

    _ =>
    'Não foi possível criar o usuário. '
        'Verifique os dados e tente novamente.',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Novo usuário',
        ),
      ),

      bottomNavigationBar: Material(
        color: Theme.of(context)
            .scaffoldBackgroundColor,
        child: SafeArea(
          top: false,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color:
                  Theme.of(context)
                      .dividerColor,
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            child: Align(
              alignment: Alignment.center,
              heightFactor: 1,
              child: ConstrainedBox(
                constraints:
                const BoxConstraints(
                  maxWidth: 560,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                        _isSaving
                            ? null
                            : () {
                          Navigator.of(
                            context,
                          ).pop();
                        },
                        child: const Text(
                          'Cancelar',
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: FilledButton.icon(
                        onPressed:
                        _isSaving
                            ? null
                            : _handleCriar,
                        icon: _isSaving
                            ? const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                          CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                            : const Icon(
                          Icons
                              .person_add_alt_1_rounded,
                        ),
                        label: Text(
                          _isSaving
                              ? 'Criando...'
                              : 'Criar usuário',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),

      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 560,
          ),
          child: Form(
            key: _formKey,
            autovalidateMode:
            AutovalidateMode
                .onUserInteraction,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                16,
                24,
                16,
                32,
              ),
              children: [
                Text(
                  'Criar novo usuário',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(
                    fontWeight:
                    FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  'Cadastre os dados de acesso e defina o perfil do usuário.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(
                    color:
                    Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant,
                  ),
                ),

                const SizedBox(height: 24),

                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding:
                    const EdgeInsets.all(
                      20,
                    ),
                    child: Column(
                      children: [
                        TextFormField(
                          controller:
                          _nomeController,
                          enabled:
                          !_isSaving,
                          textCapitalization:
                          TextCapitalization.words,
                          textInputAction:
                          TextInputAction.next,
                          decoration:
                          const InputDecoration(
                            labelText:
                            'Nome completo *',
                            prefixIcon:
                            Icon(
                              Icons
                                  .person_outline_rounded,
                            ),
                          ),
                          validator:
                          _validarNome,
                        ),

                        const SizedBox(
                          height: 16,
                        ),

                        TextFormField(
                          controller:
                          _emailController,
                          enabled:
                          !_isSaving,
                          keyboardType:
                          TextInputType
                              .emailAddress,
                          textInputAction:
                          TextInputAction.next,
                          decoration:
                          const InputDecoration(
                            labelText:
                            'E-mail *',
                            prefixIcon:
                            Icon(
                              Icons
                                  .alternate_email_rounded,
                            ),
                            helperText:
                            'O e-mail será usado para acessar o sistema.',
                          ),
                          validator:
                          _validarEmail,
                        ),

                        const SizedBox(
                          height: 16,
                        ),

                        TextFormField(
                          controller:
                          _senhaController,
                          enabled:
                          !_isSaving,
                          obscureText:
                          !_mostrarSenha,
                          textInputAction:
                          TextInputAction.next,
                          decoration:
                          InputDecoration(
                            labelText:
                            'Senha *',
                            prefixIcon:
                            const Icon(
                              Icons
                                  .lock_outline_rounded,
                            ),
                            helperText:
                            'Mínimo de 6 caracteres.',
                            suffixIcon:
                            IconButton(
                              onPressed: () {
                                setState(() {
                                  _mostrarSenha =
                                  !_mostrarSenha;
                                });
                              },
                              icon: Icon(
                                _mostrarSenha
                                    ? Icons
                                    .visibility_off_outlined
                                    : Icons
                                    .visibility_outlined,
                              ),
                            ),
                          ),
                          validator:
                          _validarSenha,
                        ),

                        const SizedBox(
                          height: 16,
                        ),

                        TextFormField(
                          controller:
                          _confirmarSenhaController,
                          enabled:
                          !_isSaving,
                          obscureText:
                          !_mostrarConfirmacao,
                          textInputAction:
                          TextInputAction.done,
                          onFieldSubmitted: (_) {
                            _handleCriar();
                          },
                          decoration:
                          InputDecoration(
                            labelText:
                            'Confirmar senha *',
                            prefixIcon:
                            const Icon(
                              Icons
                                  .lock_reset_rounded,
                            ),
                            suffixIcon:
                            IconButton(
                              onPressed: () {
                                setState(() {
                                  _mostrarConfirmacao =
                                  !_mostrarConfirmacao;
                                });
                              },
                              icon: Icon(
                                _mostrarConfirmacao
                                    ? Icons
                                    .visibility_off_outlined
                                    : Icons
                                    .visibility_outlined,
                              ),
                            ),
                          ),
                          validator:
                          _validarConfirmacao,
                        ),

                        const SizedBox(
                          height: 16,
                        ),

                        DropdownButtonFormField<
                            UserRole>(
                          initialValue:
                          _roleSelecionada,
                          isExpanded: true,
                          decoration:
                          const InputDecoration(
                            labelText:
                            'Perfil *',
                            prefixIcon:
                            Icon(
                              Icons
                                  .badge_outlined,
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value:
                              UserRole.admin,
                              child:
                              Text('Admin'),
                            ),
                            DropdownMenuItem(
                              value:
                              UserRole
                                  .financeiro,
                              child:
                              Text(
                                'Financeiro',
                              ),
                            ),
                            DropdownMenuItem(
                              value:
                              UserRole
                                  .vendedor,
                              child:
                              Text(
                                'Vendedor',
                              ),
                            ),
                            DropdownMenuItem(
                              value:
                              UserRole
                                  .estoque,
                              child:
                              Text(
                                'Estoque',
                              ),
                            ),
                          ],
                          onChanged:
                          _isSaving
                              ? null
                              : (value) {
                            if (value !=
                                null) {
                              setState(() {
                                _roleSelecionada =
                                    value;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                if (_errorMessage !=
                    null) ...[
                  const SizedBox(
                    height: 16,
                  ),
                  _ErroUsuario(
                    mensagem:
                    _errorMessage!,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErroUsuario extends StatelessWidget {
  final String mensagem;

  const _ErroUsuario({
    required this.mensagem,
  });

  @override
  Widget build(BuildContext context) {
    final cor =
        Theme.of(context)
            .colorScheme
            .error;

    return Container(
      padding:
      const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:
        cor.withValues(alpha: .1),
        borderRadius:
        BorderRadius.circular(12),
        border: Border.all(
          color:
          cor.withValues(alpha: .3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: cor,
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Text(
              mensagem,
              style: TextStyle(
                color: cor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}