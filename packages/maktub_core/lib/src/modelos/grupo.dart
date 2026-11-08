/// Group of athletes that shares a calendar (E6.1; docs/diseno.md, "Plan y asignación").
///
/// The group is just its members: the athletes of the club that follow the same assignments together. The
/// seeding script creates it (D14); the app has no screen to edit it in M1. Identifiers are English; the wire
/// (JSON keys) stays Spanish like the other contracts.
library;

import 'base.dart';
import 'json.dart';

class AthleteGroup implements DelClub {
  const AthleteGroup({
    required this.id,
    required this.clubId,
    required this.name,
    this.memberIds = const [],
    required this.auditoria,
  });

  final String id;
  @override
  final String clubId;

  /// Label to tell groups apart in lists.
  final String name;

  /// Ids of the club's athletes (`Atleta.id`, not the user id), in the order they were added.
  final List<String> memberIds;
  final Auditoria auditoria;

  factory AthleteGroup.fromJson(Json j) => AthleteGroup(
    id: '${j['id']}',
    clubId: '${j['clubId']}',
    name: '${j['nombre'] ?? ''}',
    memberIds: [for (final m in (j['miembros'] as List? ?? const [])) '$m'],
    auditoria: Auditoria.fromJson(
      (j['auditoria'] as Map).cast<String, dynamic>(),
    ),
  );

  Json toJson() => {
    'id': id,
    'clubId': clubId,
    'nombre': name,
    'miembros': memberIds,
    'auditoria': auditoria.toJson(),
  };
}
