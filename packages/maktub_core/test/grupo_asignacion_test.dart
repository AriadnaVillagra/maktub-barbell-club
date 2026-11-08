import 'dart:convert';

import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

final _audit = Auditoria.nueva('coach', ahora: DateTime.utc(2026, 11, 8));

Json _roundTrip(Json j) => jsonDecode(jsonEncode(j)) as Json;

void main() {
  group('Group JSON', () {
    test('a group survives a JSON round trip', () {
      final group = AthleteGroup(
        id: 'g1',
        clubId: 'c1',
        name: 'Main',
        memberIds: const ['a1', 'a2'],
        auditoria: _audit,
      );
      final json = _roundTrip(group.toJson());
      final back = AthleteGroup.fromJson(json);
      expect(back.toJson(), json);
      expect(back.clubId, 'c1');
      expect(back.memberIds, ['a1', 'a2']);
      expect(back.auditoria.creadoPor, 'coach');
    });

    test('an empty group round trips with an empty member list', () {
      final json = _roundTrip(
        AthleteGroup(
          id: 'g',
          clubId: 'c',
          name: 'x',
          auditoria: _audit,
        ).toJson(),
      );
      expect(json['miembros'], isEmpty);
      expect(AthleteGroup.fromJson(json).memberIds, isEmpty);
    });
  });

  group('Assignment JSON', () {
    Assignment make({
      AssignmentStatus status = AssignmentStatus.active,
      DateTime? endDate,
    }) => Assignment(
      id: 'as1',
      clubId: 'c1',
      planId: 'p1',
      groupId: 'g1',
      startDate: DateTime.utc(2026, 11, 9),
      status: status,
      endDate: endDate,
      auditoria: _audit,
    );

    test('an active assignment round trips and omits the end date', () {
      final json = _roundTrip(make().toJson());
      expect(json['fechaInicio'], '2026-11-09');
      expect(json['estado'], 'activa');
      expect(json.containsKey('fechaFin'), isFalse);
      final back = Assignment.fromJson(json);
      expect(back.toJson(), json);
      expect(back.startDate, DateTime.utc(2026, 11, 9));
      expect(back.endDate, isNull);
    });

    test('an ended assignment keeps its end date as a calendar date', () {
      final json = _roundTrip(
        make(
          status: AssignmentStatus.ended,
          endDate: DateTime.utc(2027, 1, 3),
        ).toJson(),
      );
      expect(json['fechaFin'], '2027-01-03');
      final back = Assignment.fromJson(json);
      expect(back.status, AssignmentStatus.ended);
      expect(back.endDate, DateTime.utc(2027, 1, 3));
      expect(back.toJson(), json);
    });

    test('wire names of the status are stable', () {
      expect(
        [for (final s in AssignmentStatus.values) s.cable],
        ['activa', 'pausada', 'terminada'],
      );
      for (final s in AssignmentStatus.values) {
        expect(AssignmentStatus.deCable(s.cable), s);
      }
    });

    test('an unknown status is rejected', () {
      final json = make().toJson()..['estado'] = 'otra';
      expect(() => Assignment.fromJson(json), throwsFormatException);
    });
  });
}
