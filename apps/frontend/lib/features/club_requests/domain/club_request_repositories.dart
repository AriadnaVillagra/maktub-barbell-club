import 'package:maktub_core/maktub_core.dart';

/// Sending a club request. There is no session yet: the Google ID token from the failed sign-in proves the
/// email (`POST /auth/pedidos-club`).
abstract interface class ClubRequestApi {
  /// The pending request. Fails with the API's error: 409 with `codigo: pedido_pendiente` when one is already
  /// waiting, 401 when the ID token is no longer valid, 400 for invalid names.
  Future<ClubRequest> send({
    required String idToken,
    required String clubName,
    required String requesterName,
    String? note,
  });
}

/// Reviewing club requests: only platform admins (`/plataforma/pedidos-club`).
abstract interface class ClubRequestsRepository {
  /// The pending requests, oldest first.
  Future<List<ClubRequest>> pending();

  /// Creates the club and the requester's account. Returns the new club.
  Future<Club> approve(String requestId);

  Future<void> reject(String requestId);
}
