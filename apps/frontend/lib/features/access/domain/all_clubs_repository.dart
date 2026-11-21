import 'package:maktub_core/maktub_core.dart';

/// Every club of the platform, for a platform admin to enter any of them (support).
abstract interface class AllClubsRepository {
  /// `GET /plataforma/clubes`: every club of type `club`, by name.
  Future<List<Club>> allClubs();
}
