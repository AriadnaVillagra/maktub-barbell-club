import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';

import '../../../core/red/api_providers.dart';
import '../../catalogo/presentation/providers.dart';
import '../data/http_wod_repository.dart';
import '../domain/wod_repository.dart';

final wodRepositoryProvider = Provider<WodRepository>(
  (ref) => HttpWodRepository(ref.watch(clienteApiProvider)),
);

/// The WoDs of the active club's library, by name.
final wodsProvider = FutureProvider<List<Wod>>((ref) async {
  final clubId = ref.watch(catalogClubIdProvider);
  if (clubId == null) return const [];
  return ref.watch(wodRepositoryProvider).wods(clubId);
});
