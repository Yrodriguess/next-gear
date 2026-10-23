import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/auth_providers.dart';

/// A organização do usuário autenticado — é isto, não
/// AppConfig.currentOrgId, que qualquer fluxo de escrita deve usar.
/// AppConfig.currentOrgId continua existindo só como valor de
/// bootstrap/documentação (o sistema roda com uma única organização
/// por enquanto), mas nunca deveria ser lido direto num Provider ou
/// numa tela — a origem de verdade é sempre a sessão.
///
/// `null` enquanto o usuário ainda não carregou (ver appUserProvider)
/// OU se o documento `usuarios/{uid}` não tiver `orgId` preenchido —
/// uma string vazia é tratada como inválida, não como "sem
/// organização mas tudo bem": gravar dado com orgId vazio é pior que
/// não gravar nada, porque quebra silenciosamente todas as consultas
/// que dependem dele depois.
///
/// Confiar apenas nisso na interface não é segurança de verdade — as
/// regras do Firestore/backend também precisam validar que o usuário
/// pertence à organização que está tentando escrever.
final currentOrgIdProvider = Provider<String?>((ref) {
  final orgId = ref.watch(appUserProvider).value?.orgId;
  return (orgId == null || orgId.isEmpty) ? null : orgId;
});
