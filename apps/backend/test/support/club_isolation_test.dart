import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

import 'club_isolation.dart';

/// Stand-in for a slice store: records tagged with their club.
class _NotesStore {
  final notes = <({String clubId, String text})>[];

  void add(String clubId, String text) => notes.add((clubId: clubId, text: text));
}

/// Test endpoint under `/clubes/{clubId}/notes`: the correct way, filtering by the context's club.
Handler _notesEndpoint(_NotesStore store) => (context) {
      final club = context.read<ClubContext>();
      final mine = store.notes.where((n) => n.clubId == club.clubId).map((n) => n.text).toList();
      return Response.json(body: {'notes': mine});
    };

/// The bug the helper must catch: it ignores `clubId` and returns every note.
Handler _leakyEndpoint(_NotesStore store) => (context) {
      context.read<ClubContext>();
      return Response(body: jsonEncode({'notes': store.notes.map((n) => n.text).toList()}));
    };

void main() {
  final store = _NotesStore();

  testClubIsolation(
    'GET /clubes/{clubId}/notes (test endpoint)',
    endpoint: _notesEndpoint(store),
    path: '/clubes/{clubId}/notes',
    action: Accion.planificar,
    seed: store.add,
  );

  group('the helper fails on an endpoint that does not filter by clubId', () {
    final leakyStore = _NotesStore();
    final check = ClubIsolationCheck(
      endpoint: _leakyEndpoint(leakyStore),
      path: '/clubes/{clubId}/notes',
      action: Accion.planificar,
      seed: leakyStore.add,
    );

    test('the cross-club case fails', () {
      expect(check.hidesOtherClubs, throwsA(isA<TestFailure>()));
    });

    test('the membership and role cases still pass, they are guarded by requireClub', () async {
      await check.rejectsNonMember();
      await check.rejectsWrongRole();
    });
  });

  test('the helper fails on an endpoint that never returns its seeded data', () {
    final check = ClubIsolationCheck(
      endpoint: (_) => Response.json(body: {'notes': <String>[]}),
      path: '/clubes/{clubId}/notes',
      action: Accion.planificar,
      seed: (_, _) {},
    );

    expect(check.hidesOtherClubs, throwsA(isA<TestFailure>()));
  });
}
