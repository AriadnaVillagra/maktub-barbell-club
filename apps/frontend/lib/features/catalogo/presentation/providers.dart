import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';

import '../../../core/offline/local_copy_providers.dart';
import '../../../core/red/api_providers.dart';
import '../../access/presentation/providers.dart';
import '../data/cached_catalog_admin_repository.dart';
import '../data/cached_catalog_repository.dart';
import '../data/http_catalog_admin_repository.dart';
import '../data/http_catalog_repository.dart';
import '../domain/catalog_admin_repository.dart';
import '../domain/catalog_repository.dart';

/// The catalog straight from the server. Tests replace it to keep the device's copy in between.
final remoteCatalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => HttpCatalogRepository(ref.watch(clienteApiProvider)),
);

/// The catalog with the device's copy as fallback for its reads without signal (E7.15).
final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CachedCatalogRepository(
    ref.watch(remoteCatalogRepositoryProvider),
    ref.watch(localCopyReadsProvider),
  ),
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

/// Writes and reads of the club's categories, timers and equipment (E2.9).
final remoteCatalogAdminRepositoryProvider = Provider<CatalogAdminRepository>(
  (ref) => HttpCatalogAdminRepository(ref.watch(clienteApiProvider)),
);

/// Timers and equipment are kept on the device for reading without signal (E7.15).
final catalogAdminRepositoryProvider = Provider<CatalogAdminRepository>(
  (ref) => CachedCatalogAdminRepository(
    ref.watch(remoteCatalogAdminRepositoryProvider),
    ref.watch(localCopyReadsProvider),
  ),
);
