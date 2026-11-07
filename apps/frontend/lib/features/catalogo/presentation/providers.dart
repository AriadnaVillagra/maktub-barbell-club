import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';

import '../../../core/red/api_providers.dart';
import '../../access/presentation/providers.dart';
import '../data/http_catalog_repository.dart';
import '../domain/catalog_repository.dart';

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => HttpCatalogRepository(ref.watch(clienteApiProvider)),
);

/// The id of the club whose catalog the app reads: the active club. Null while unknown.
final catalogClubIdProvider = Provider<String?>(
  (ref) => ref.watch(meProvider).value?.activeClub?.club.id,
);

/// Active exercises of the active club in a category (all categories when null).
final activeExercisesProvider = FutureProvider.family<List<Exercise>, String?>((
  ref,
  categoryId,
) async {
  final clubId = await ref
      .watch(meProvider.future)
      .then((me) => me?.activeClub?.club.id);
  if (clubId == null) return const [];
  return ref
      .watch(catalogRepositoryProvider)
      .exercises(clubId, categoryId: categoryId, status: CatalogStatus.active);
});
