import 'package:maktub_core/maktub_core.dart';

import '../../../core/offline/local_copy.dart';
import '../domain/catalog_admin_repository.dart';

/// The club's timers and equipment with the device's copy (E7.15), so the day's rests start without signal. Writes
/// go straight to the server.
class CachedCatalogAdminRepository implements CatalogAdminRepository {
  CachedCatalogAdminRepository(this._remote, this._reads);

  final CatalogAdminRepository _remote;
  final LocalCopyReads _reads;

  @override
  Future<List<Temporizador>> timers(String clubId) => _reads.read(
    copyKey(['timers', clubId]),
    () => _remote.timers(clubId),
    encode: (ts) => [for (final t in ts) t.toJson()],
    decode: (d) => [
      for (final t in d as List)
        Temporizador.fromJson((t as Map).cast<String, dynamic>()),
    ],
  );

  @override
  Future<Equipo> team(String clubId) => _reads.read(
    copyKey(['team', clubId]),
    () => _remote.team(clubId),
    encode: (t) => t.toJson(),
    decode: (d) => Equipo.fromJson((d as Map).cast<String, dynamic>()),
  );

  @override
  Future<Category> createCategory(String clubId, String name) =>
      _remote.createCategory(clubId, name);

  @override
  Future<Category> renameCategory(String clubId, String id, String name) =>
      _remote.renameCategory(clubId, id, name);

  @override
  Future<Category> setCategoryStatus(
    String clubId,
    String id,
    CatalogStatus status,
  ) => _remote.setCategoryStatus(clubId, id, status);

  @override
  Future<RemovalOutcome> deleteCategory(String clubId, String id) =>
      _remote.deleteCategory(clubId, id);

  @override
  Future<Temporizador> createTimer(String clubId, Temporizador draft) =>
      _remote.createTimer(clubId, draft);

  @override
  Future<Temporizador> updateTimer(String clubId, Temporizador timer) =>
      _remote.updateTimer(clubId, timer);

  @override
  Future<Temporizador> archiveTimer(String clubId, String id) =>
      _remote.archiveTimer(clubId, id);

  @override
  Future<RemovalOutcome> deleteTimer(String clubId, String id) =>
      _remote.deleteTimer(clubId, id);

  @override
  Future<Equipo> saveTeam(String clubId, Equipo team) =>
      _remote.saveTeam(clubId, team);
}
