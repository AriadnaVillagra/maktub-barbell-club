import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

void main() {
  final audit = Auditoria.nueva('ari@example.com', ahora: DateTime.utc(2026, 11, 21, 10));

  test('a club request travels to JSON and back, in plataforma, without the Google account', () {
    final request = ClubRequest(
      id: 'r1',
      email: 'ari@example.com',
      requesterName: 'Ari',
      clubName: 'Barra Norte',
      note: 'Somos 8',
      status: ClubRequestStatus.approved,
      createdClubId: 'c9',
      reviewedBy: 'u-andi',
      reviewedAt: DateTime.utc(2026, 11, 21, 12),
      auditoria: audit,
    );
    final json = request.toJson();
    final back = ClubRequest.fromJson(json);

    expect(json['clubId'], clubPlataforma);
    expect(json['estado'], 'aprobado');
    expect(json.keys, isNot(contains('googleSub')));
    expect(
      (back.email, back.requesterName, back.clubName, back.note, back.status, back.createdClubId, back.reviewedBy),
      ('ari@example.com', 'Ari', 'Barra Norte', 'Somos 8', ClubRequestStatus.approved, 'c9', 'u-andi'),
    );
    expect(back.reviewedAt, DateTime.utc(2026, 11, 21, 12));
  });

  test('a new request is pending and leaves out what it does not have yet', () {
    final json = ClubRequest(id: 'r1', email: 'a@b.co', requesterName: 'A', clubName: 'Club', auditoria: audit).toJson();
    expect(json['estado'], 'pendiente');
    expect(json.keys, isNot(containsAll(['nota', 'clubCreadoId', 'revisadoPor', 'revisadoEn'])));
    expect(ClubRequest.fromJson(json).isPending, isTrue);
  });

  test('names and note have limits', () {
    expect(ClubRequest.problems(clubName: 'Barra Norte', requesterName: 'Ari'), isEmpty);
    expect(ClubRequest.problems(clubName: 'B', requesterName: 'Ari'), hasLength(1));
    expect(ClubRequest.problems(clubName: 'x' * 61, requesterName: ''), hasLength(2));
    expect(ClubRequest.problems(clubName: 'Club', requesterName: 'Ari', note: 'x' * 501), hasLength(1));
  });

  test('sign-in refusal codes', () {
    expect(SignInRefusal.fromWireOrNull('pedido_pendiente'), SignInRefusal.requestPending);
    expect(SignInRefusal.fromWireOrNull('otra'), isNull);
    expect(SignInRefusal.fromWireOrNull(null), isNull);
  });

  group('reviewing club requests', () {
    test('depends only on the platform admin flag', () {
      expect(canOnPlatform(Accion.reviewClubRequests, isPlatformAdmin: true), isTrue);
      expect(canOnPlatform(Accion.reviewClubRequests, isPlatformAdmin: false), isFalse);
      expect(puede(const {}, Accion.reviewClubRequests, TipoClub.personal, esAdminPlataforma: true), isTrue);
      expect(puede(const {Rol.coach, Rol.adminClub}, Accion.reviewClubRequests, TipoClub.club), isFalse);
    });

    test('the platform admin flag grants no club action', () {
      for (final a in Accion.values.where((a) => !platformActions.contains(a))) {
        expect(canOnPlatform(a, isPlatformAdmin: true), isFalse, reason: a.name);
        expect(puede(const {}, a, TipoClub.club, esAdminPlataforma: true), isFalse, reason: a.name);
      }
    });
  });
}
