import '../modelos/base.dart';
import '../modelos/cable.dart';
import '../modelos/json.dart';

/// Where a club request stands. A rejected one stays as history; its author may request again.
enum ClubRequestStatus implements ConCable {
  pending('pendiente'),
  approved('aprobado'),
  rejected('rechazado');

  const ClubRequestStatus(this.cable);
  @override
  final String cable;

  static ClubRequestStatus fromWire(Object? v) => desdeCable(values, v, 'Estado del pedido');
}

/// Why Google sign-in was refused although the token was valid: the `codigo` of the API's 403, next to
/// `error`. The app uses it to offer a club request or to show where the request stands.
enum SignInRefusal implements ConCable {
  /// No account and no request: the person may request a club.
  noAccount('sin_cuenta'),

  /// A request is waiting for a platform admin.
  requestPending('pedido_pendiente'),

  /// The latest request was rejected; another one may be sent.
  requestRejected('pedido_rechazado');

  const SignInRefusal(this.cable);
  @override
  final String cable;

  /// Null for a missing or unknown code (an older API, or another 403).
  static SignInRefusal? fromWireOrNull(Object? v) {
    for (final r in values) {
      if (r.cable == v) return r;
    }
    return null;
  }
}

/// Someone without an account asks for a club for their team (pedido de alta de club, 2026-11-21). A
/// platform admin approves it (the club, the user and their memberships are created then) or rejects it.
///
/// It is platform data, so its `clubId` is always [clubPlataforma]. The requester's Google account id
/// (proven by the ID token they sent) lives only in the backend's document, never on the wire.
class ClubRequest implements DelClub {
  const ClubRequest({
    required this.id,
    this.clubId = clubPlataforma,
    required this.email,
    required this.requesterName,
    required this.clubName,
    this.note,
    this.status = ClubRequestStatus.pending,
    this.createdClubId,
    this.reviewedBy,
    this.reviewedAt,
    required this.auditoria,
  });

  static const maxClubName = 60;
  static const maxRequesterName = 60;
  static const maxNote = 500;

  final String id;
  @override
  final String clubId;

  /// Normalized (`normalizarEmail`), as proven by Google.
  final String email;
  final String requesterName;
  final String clubName;

  /// Optional words for the platform admin (who the team is, how many people…).
  final String? note;
  final ClubRequestStatus status;

  /// The club created on approval; set from the moment it is approved.
  final String? createdClubId;

  /// Platform admin who approved or rejected it, and when (UTC).
  final String? reviewedBy;
  final DateTime? reviewedAt;

  /// Created by the requester's email (there is no user yet), modified by the reviewer.
  final Auditoria auditoria;

  bool get isPending => status == ClubRequestStatus.pending;

  /// What is wrong with the requested names and note, already trimmed; empty when they are fine.
  static List<String> problems({required String clubName, required String requesterName, String? note}) => [
    if (clubName.length < 2) 'El nombre del club tiene que tener al menos 2 letras.',
    if (clubName.length > maxClubName) 'El nombre del club puede tener hasta $maxClubName caracteres.',
    if (requesterName.isEmpty) 'Falta tu nombre.',
    if (requesterName.length > maxRequesterName) 'Tu nombre puede tener hasta $maxRequesterName caracteres.',
    if ((note ?? '').length > maxNote) 'La nota puede tener hasta $maxNote caracteres.',
  ];

  factory ClubRequest.fromJson(Json j) => ClubRequest(
    id: '${j['id']}',
    clubId: '${j['clubId'] ?? clubPlataforma}',
    email: '${j['email']}',
    requesterName: '${j['nombreSolicitante']}',
    clubName: '${j['nombreClub']}',
    note: textoOpcional(j['nota']),
    status: ClubRequestStatus.fromWire(j['estado']),
    createdClubId: textoOpcional(j['clubCreadoId']),
    reviewedBy: textoOpcional(j['revisadoPor']),
    reviewedAt: j['revisadoEn'] == null ? null : DateTime.parse('${j['revisadoEn']}').toUtc(),
    auditoria: Auditoria.fromJson((j['auditoria'] as Map).cast<String, dynamic>()),
  );

  Json toJson() => sinNulos({
    'id': id,
    'clubId': clubId,
    'email': email,
    'nombreSolicitante': requesterName,
    'nombreClub': clubName,
    'nota': note,
    'estado': status.cable,
    'clubCreadoId': createdClubId,
    'revisadoPor': reviewedBy,
    'revisadoEn': reviewedAt?.toUtc().toIso8601String(),
    'auditoria': auditoria.toJson(),
  });
}
