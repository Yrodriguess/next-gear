import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/visita_repository.dart';
import '../data/visita_service.dart';
import '../domain/visita.dart';

final visitaRepositoryProvider = Provider<VisitaRepository>((ref) {
  return VisitaRepository();
});

final visitaServiceProvider = Provider<VisitaService>((ref) {
  return VisitaService(
    visitaRepository: ref.watch(visitaRepositoryProvider),
  );
});

/// Mantém a visita sincronizada enquanto as telas de execução ou retomada
/// estiverem abertas.
final visitaPorIdProvider =
StreamProvider.autoDispose.family<Visita?, String>((ref, visitaId) {
  if (visitaId.trim().isEmpty) {
    return Stream<Visita?>.value(null);
  }

  return ref.watch(visitaRepositoryProvider).watchById(visitaId);
});

/// Histórico de visitas de um cliente, mais recente primeiro.
final visitaHistoricoDoClienteProvider =
StreamProvider.autoDispose.family<List<Visita>, String>((ref, clienteId) {
  if (clienteId.trim().isEmpty) {
    return Stream<List<Visita>>.value(const <Visita>[]);
  }

  return ref
      .watch(visitaRepositoryProvider)
      .watchHistoricoDoCliente(clienteId);
});

/// Uma única assinatura para todas as visitas abertas da organização.
/// A Agenda deriva os demais estados deste provider, evitando criar um
/// listener separado para cada card de cliente.
final visitasEmAndamentoProvider =
StreamProvider.autoDispose<List<Visita>>((ref) {
  final usuario = ref.watch(appUserProvider).value;

  if (usuario == null || usuario.orgId.trim().isEmpty) {
    return Stream<List<Visita>>.value(const <Visita>[]);
  }

  return ref
      .watch(visitaRepositoryProvider)
      .watchEmAndamentoDaOrganizacao(usuario.orgId);
});

/// Mapa usado pela Agenda para descobrir rapidamente se um cliente possui
/// visita aberta e trocar "Iniciar visita" por "Retomar visita".
final visitasEmAndamentoPorClienteProvider =
Provider.autoDispose<AsyncValue<Map<String, Visita>>>((ref) {
  final visitasAsync = ref.watch(visitasEmAndamentoProvider);

  return visitasAsync.whenData((visitas) {
    final porCliente = <String, Visita>{};

    for (final visita in visitas) {
      final existente = porCliente[visita.clienteId];

      if (existente == null) {
        porCliente[visita.clienteId] = visita;
        continue;
      }

      final inicioExistente =
          existente.inicioEfetivo ?? DateTime.fromMillisecondsSinceEpoch(0);
      final inicioAtual =
          visita.inicioEfetivo ?? DateTime.fromMillisecondsSinceEpoch(0);

      if (inicioAtual.isAfter(inicioExistente)) {
        porCliente[visita.clienteId] = visita;
      }
    }

    return Map<String, Visita>.unmodifiable(porCliente);
  });
});

/// Visita aberta de um cliente específico. É derivada do mapa acima e não
/// abre uma nova consulta no Firestore.
final visitaEmAndamentoDoClienteProvider =
Provider.autoDispose.family<AsyncValue<Visita?>, String>(
      (ref, clienteId) {
    return ref
        .watch(visitasEmAndamentoPorClienteProvider)
        .whenData((porCliente) => porCliente[clienteId]);
  },
);

/// Visita que o usuário atual deve retomar. Também impede que ele inicie
/// outro cliente antes de finalizar ou cancelar o atendimento aberto.
final visitaEmAndamentoDoVendedorProvider =
Provider.autoDispose<AsyncValue<Visita?>>((ref) {
  final usuario = ref.watch(appUserProvider).value;

  return ref.watch(visitasEmAndamentoProvider).whenData((visitas) {
    if (usuario == null) return null;

    for (final visita in visitas) {
      if (visita.vendedorId == usuario.uid) {
        return visita;
      }
    }

    return null;
  });
});

/// Visitas concluídas exibidas na aba "Realizadas".
final visitasRealizadasProvider =
StreamProvider.autoDispose<List<Visita>>((ref) {
  final usuario = ref.watch(appUserProvider).value;

  if (usuario == null || usuario.orgId.trim().isEmpty) {
    return Stream<List<Visita>>.value(const <Visita>[]);
  }

  return ref
      .watch(visitaRepositoryProvider)
      .watchRealizadasDaOrganizacao(usuario.orgId);
});
