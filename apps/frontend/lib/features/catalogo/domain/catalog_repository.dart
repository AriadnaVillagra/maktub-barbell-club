import 'package:maktub_core/maktub_core.dart';

/// Reads the catalog visible to a club (base entries plus the club's own): `GET /clubes/{id}/catalogo/...`.
/// Shared by the exercise picker (E2.10) and the catalog screens (E2.8).
abstract interface class CatalogRepository {
  /// Exercises visible to [clubId], by name. Both states when [status] is null.
  Future<List<Exercise>> exercises(
    String clubId, {
    String? categoryId,
    CatalogStatus? status,
  });

  Future<List<Category>> categories(String clubId);
}
