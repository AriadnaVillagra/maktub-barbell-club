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
      members: [
        AssignmentMember(athleteId: 'a1', from: DateTime.utc(2026, 11, 9)),
        AssignmentMember(
          athleteId: 'a2',
          from: DateTime.utc(2026, 11, 9),
          to: DateTime.utc(2026, 11, 20),
        ),
      ],
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

    test('the athletes round trip with their dates', () {
      final json = _roundTrip(make().toJson());
      expect(json['atletas'], [
        {'atletaId': 'a1', 'desde': '2026-11-09'},
        {'atletaId': 'a2', 'desde': '2026-11-09', 'hasta': '2026-11-20'},
      ]);
      expect(json.containsKey('grupoId'), isFalse);
      final back = Assignment.fromJson(json);
      expect(back.toJson(), json);
      expect(back.athleteIds, ['a1', 'a2']);
      expect(back.currentAthleteIds, ['a1']);
      expect(back.athleteIdsOn(DateTime.utc(2026, 11, 20)), ['a1', 'a2']);
      expect(back.athleteIdsOn(DateTime.utc(2026, 11, 21)), ['a1']);
      expect(back.hasAthleteOn('a2', DateTime.utc(2026, 11, 8)), isFalse);
    });

    test('a document from before E6.7 with atletaId reads as that athlete from the start', () {
      final json = make().toJson()
        ..remove('atletas')
        ..['atletaId'] = 'a9';
      final back = Assignment.fromJson(json);
      expect(back.members.single.athleteId, 'a9');
      expect(back.members.single.from, DateTime.utc(2026, 11, 9));
      expect(back.members.single.to, isNull);
    });

    test(
      'a document from before E6.7 with only grupoId keeps it, with no members',
      () {
        final json = make().toJson()
          ..remove('atletas')
          ..['grupoId'] = 'g1';
        final back = Assignment.fromJson(json);
        expect(back.groupId, 'g1');
        expect(back.members, isEmpty);
      },
    );
  });

  group('membersAfterChange', () {
    final start = DateTime.utc(2026, 11, 2);
    final today = DateTime.utc(2026, 11, 18);
    final a = AssignmentMember(athleteId: 'a', from: start);
    final b = AssignmentMember(athleteId: 'b', from: start);

    test('someone removed stays until the day before', () {
      final r = membersAfterChange(
        [a, b],
        athleteIds: ['a'],
        date: today,
        startDate: start,
      );
      expect(r[0], same(a));
      expect(r[1].athleteId, 'b');
      expect(r[1].to, DateTime.utc(2026, 11, 17));
    });

    test('someone added is in from the date', () {
      final r = membersAfterChange(
        [a],
        athleteIds: ['a', 'c'],
        date: today,
        startDate: start,
      );
      expect(r.map((m) => m.athleteId), ['a', 'c']);
      expect(r[1].from, today);
      expect(r[1].to, isNull);
    });

    test('someone added back gets a second period and keeps the first', () {
      final left = AssignmentMember(
        athleteId: 'b',
        from: start,
        to: DateTime.utc(2026, 11, 10),
      );
      final r = membersAfterChange(
        [a, left],
        athleteIds: ['a', 'b'],
        date: today,
        startDate: start,
      );
      expect(r, hasLength(3));
      expect(r[1], same(left));
      expect(r[2].from, today);
    });

    test('before the plan starts, joining is from the start and leaving leaves no trace', () {
      final future = DateTime.utc(2026, 12, 1);
      final x = AssignmentMember(athleteId: 'x', from: future);
      final r = membersAfterChange(
        [x],
        athleteIds: ['y'],
        date: today,
        startDate: future,
      );
      expect(r.single.athleteId, 'y');
      expect(r.single.from, future);
    });

    test('someone removed the day they joined disappears', () {
      final c = AssignmentMember(athleteId: 'c', from: today);
      final r = membersAfterChange(
        [a, c],
        athleteIds: ['a'],
        date: today,
        startDate: start,
      );
      expect(r.single, same(a));
    });
  });
}
