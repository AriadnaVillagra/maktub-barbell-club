import 'package:maktub_backend/features/club_requests/approve_club_request/approve_club_request_store.dart';
import 'package:maktub_backend/features/club_requests/list_club_requests/list_club_requests_store.dart';
import 'package:maktub_backend/features/club_requests/reject_club_request/reject_club_request_store.dart';
import 'package:maktub_backend/features/club_requests/request_club/request_club_store.dart';
import 'package:maktub_core/maktub_core.dart';

/// One in-memory "database" behind every club request slice's store, so a test can run the whole flow:
/// request → list → approve or reject. It enforces what the Mongo indexes do (one pending request per email,
/// unique email, one membership and athlete per club and user).
class FakeClubRequests
    implements RequestClubStore, ListClubRequestsStore, ApproveClubRequestStore, RejectClubRequestStore {
  final requests = <String, ClubRequest>{};
  final googleSubs = <String, String>{};
  final users = <String, Usuario>{};
  final userSubs = <String, String?>{};
  final clubs = <String, Club>{};
  final memberships = <Membresia>[];
  final athletes = <Atleta>[];

  void put(ClubRequest request, {String googleSub = 'sub-1'}) {
    requests[request.id] = request;
    googleSubs[request.id] = googleSub;
  }

  ClubRequest _with(ClubRequest r, {required ClubRequestStatus status, String? clubId, required String by, required DateTime at}) =>
      ClubRequest(
        id: r.id,
        email: r.email,
        requesterName: r.requesterName,
        clubName: r.clubName,
        note: r.note,
        status: status,
        createdClubId: clubId ?? r.createdClubId,
        reviewedBy: by,
        reviewedAt: at,
        auditoria: r.auditoria.modificada(by, ahora: at),
      );

  // RequestClubStore
  @override
  Future<bool> userExists(String email) async => users.containsKey(email);

  @override
  Future<ClubRequestStatus?> latestStatus(String email) async {
    final mine = requests.values.where((r) => r.email == email).toList()
      ..sort((a, b) => a.auditoria.creadoEn.compareTo(b.auditoria.creadoEn));
    return mine.lastOrNull?.status;
  }

  @override
  Future<bool> insertPending(ClubRequest request, {required String googleSub}) async {
    if (requests.values.any((r) => r.email == request.email && r.isPending)) return false;
    put(request, googleSub: googleSub);
    return true;
  }

  // ListClubRequestsStore
  @override
  Future<List<ClubRequest>> list({ClubRequestStatus? status}) async => [
    for (final r in requests.values.toList()..sort((a, b) => a.auditoria.creadoEn.compareTo(b.auditoria.creadoEn)))
      if (status == null || r.status == status) r,
  ];

  // ApproveClubRequestStore
  @override
  Future<StoredClubRequest?> find(String requestId) async {
    final r = requests[requestId];
    return r == null ? null : (request: r, googleSub: googleSubs[requestId]);
  }

  @override
  Future<StoredClubRequest?> markApproved(
    String requestId, {
    required String clubId,
    required String reviewedBy,
    required DateTime reviewedAt,
  }) async {
    final r = requests[requestId];
    if (r != null && r.isPending) {
      requests[requestId] = _with(r, status: ClubRequestStatus.approved, clubId: clubId, by: reviewedBy, at: reviewedAt);
    }
    return find(requestId);
  }

  @override
  Future<Usuario> insertUserIfMissing(Usuario user, {String? googleSub, required Auditoria auditoria}) async {
    final existing = users[user.email];
    if (existing != null) return existing;
    users[user.email] = user;
    userSubs[user.email] = googleSub;
    return user;
  }

  @override
  Future<void> ensureClub(Club club) async => clubs.putIfAbsent(club.id, () => club);

  @override
  Future<void> ensureMembership(Membresia membership) async {
    if (!memberships.any((m) => m.clubId == membership.clubId && m.usuarioId == membership.usuarioId)) {
      memberships.add(membership);
    }
  }

  @override
  Future<void> ensureAthlete(Atleta athlete) async {
    if (!athletes.any((a) => a.clubId == athlete.clubId && a.usuarioId == athlete.usuarioId)) athletes.add(athlete);
  }

  // RejectClubRequestStore
  @override
  Future<ClubRequest?> markRejected(String requestId, {required String reviewedBy, required DateTime reviewedAt}) async {
    final r = requests[requestId];
    if (r != null && r.isPending) {
      requests[requestId] = _with(r, status: ClubRequestStatus.rejected, by: reviewedBy, at: reviewedAt);
    }
    return requests[requestId];
  }
}
