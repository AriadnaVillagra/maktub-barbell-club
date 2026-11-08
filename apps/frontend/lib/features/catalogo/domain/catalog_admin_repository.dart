import 'package:maktub_core/maktub_core.dart';

/// What a delete did on the server: removed the entry, or archived it because something uses it.
enum RemovalOutcome { deleted, archived }

/// Management of the club's own categories, timers and equipment (E2.9). Reading the categories
/// stays in `CatalogRepository`. Default entries need a platform admin.
abstract interface class CatalogAdminRepository {
  Future<Category> createCategory(String clubId, String name);
  Future<Category> renameCategory(String clubId, String id, String name);
  Future<Category> setCategoryStatus(
    String clubId,
    String id,
    CatalogStatus status,
  );
  Future<RemovalOutcome> deleteCategory(String clubId, String id);

  /// Base and club timers, both states.
  Future<List<Temporizador>> timers(String clubId);

  /// Creates [draft] (its id, scope and status are the server's).
  Future<Temporizador> createTimer(String clubId, Temporizador draft);

  /// Saves the content of [timer], including its status (that is how an archived one is reactivated).
  Future<Temporizador> updateTimer(String clubId, Temporizador timer);
  Future<Temporizador> archiveTimer(String clubId, String id);
  Future<RemovalOutcome> deleteTimer(String clubId, String id);

  /// The club's equipment (the standard when it never saved one).
  Future<Equipo> team(String clubId);
  Future<Equipo> saveTeam(String clubId, Equipo team);
}
