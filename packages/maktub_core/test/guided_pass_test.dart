import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

final _t0 = DateTime.utc(2026, 11, 14, 10);
DateTime _at(int minutes) => _t0.add(Duration(minutes: minutes));

const _starts = [
  GuidedBlockStart(
    athleteMode: AthleteMode.simultaneous,
    executionMode: ExecutionMode.sequential,
  ),
  GuidedBlockStart(
    athleteMode: AthleteMode.turns,
    executionMode: ExecutionMode.circuit,
  ),
];

GuidedPassAction _begin({
  String id = 'p1',
  String? replaces,
  int version = 0,
  List<String> athletes = const ['ari', 'andi'],
  bool redo = false,
  List<GuidedBlockStart> blocks = _starts,
}) => GuidedPassAction.begin(
  passId: id,
  version: version,
  at: _t0,
  replaces: replaces,
  athleteIds: athletes,
  redo: redo,
  blocks: blocks,
);

GuidedPassAction _on(
  GuidedActionKind kind,
  int block, {
  String id = 'p1',
  int minute = 1,
}) => GuidedPassAction.onBlock(
  kind,
  passId: id,
  version: 1,
  at: _at(minute),
  block: block,
);

GuidedPass _apply(GuidedPass? pass, List<GuidedPassAction> actions) =>
    actions.fold(pass, applyGuidedAction)!;

void main() {
  group('wire', () {
    test('a pass travels and comes back the same', () {
      final pass = _apply(null, [
        _begin(redo: true),
        _on(GuidedActionKind.startBlock, 0),
        GuidedPassAction.passSets(
          passId: 'p1',
          version: 2,
          at: _at(2),
          block: 0,
          sets: {const AthleteSet('ari', 0, 0)},
        ),
        GuidedPassAction.leave(
          passId: 'p1',
          version: 3,
          at: _at(2),
          block: 0,
          left: {const LeftPrescription('andi', 1)},
        ),
      ]);
      final json = pass.toJson();
      expect(json['atletaIds'], ['ari', 'andi']);
      expect(json['deNuevo'], true);
      expect(json['actual'], 0);
      expect(json['terminada'], false);
      expect(json['inicio'], _at(1).toIso8601String());
      final block = (json['bloques'] as List).first as Map;
      expect(block['estado'], 'en_curso');
      expect(block['modoAtletas'], 'simultaneo');
      expect(block['modoEjecucion'], 'secuencial');
      expect(block['pasadas'], [
        {'atletaId': 'ari', 'prescripcion': 0, 'serie': 0},
      ]);
      expect(block['dejados'], [
        {'atletaId': 'andi', 'prescripcion': 1},
      ]);

      final back = GuidedPass.fromJson(json);
      expect(back.toJson(), json);
      expect(back.blocks[0].passed, {const AthleteSet('ari', 0, 0)});
    });

    test('a session without a pass has none, and keeps it when it has one', () {
      final session = Session(
        id: 's1',
        clubId: 'c1',
        assignmentId: 'a1',
        planId: 'p',
        cycle: 1,
        week: 1,
        day: 1,
        date: DateTime.utc(2026, 11, 14),
        auditoria: Auditoria.nueva('u', ahora: _t0),
      );
      expect(session.toJson().containsKey('pasadaGuiada'), false);
      expect(Session.fromJson(session.toJson()).guidedPass, isNull);

      final json = {
        ...session.toJson(),
        'pasadaGuiada': _apply(null, [_begin()]).toJson(),
      };
      expect(Session.fromJson(json).guidedPass!.id, 'p1');
      expect(Session.fromJson(json).toJson(), json);
    });

    test('every action travels and comes back the same', () {
      final actions = [
        _begin(replaces: 'p0', redo: true),
        GuidedPassAction.athleteMode(
          passId: 'p1',
          version: 1,
          at: _t0,
          block: 1,
          mode: AthleteMode.simultaneous,
        ),
        GuidedPassAction.executionMode(
          passId: 'p1',
          version: 2,
          at: _t0,
          block: 1,
          mode: ExecutionMode.sequential,
        ),
        for (final k in [
          GuidedActionKind.startBlock,
          GuidedActionKind.skipBlock,
          GuidedActionKind.finishBlock,
          GuidedActionKind.interruptBlock,
        ])
          _on(k, 0),
        GuidedPassAction.passSets(
          passId: 'p1',
          version: 3,
          at: _t0,
          block: 0,
          sets: {const AthleteSet('ari', 0, 1)},
        ),
        GuidedPassAction.leave(
          passId: 'p1',
          version: 3,
          at: _t0,
          block: 0,
          left: {const LeftPrescription('ari', 0)},
        ),
        GuidedPassAction.finish(passId: 'p1', version: 4, at: _t0),
      ];
      for (final a in actions) {
        final json = a.toJson();
        expect(GuidedPassAction.fromJson(json).toJson(), json, reason: '$json');
      }
      expect(actions.first.toJson()['tipo'], 'comenzar');
      expect(actions.last.toJson()['tipo'], 'terminar');
    });

    test('a malformed action is refused', () {
      final ok = _begin().toJson();
      for (final bad in [
        {...ok, 'tipo': 'otra'},
        {...ok, 'pasadaId': 'con espacios'},
        {...ok, 'pasadaId': 'x' * 41},
        {...ok, 'version': -1},
        {...ok, 'en': 'ayer'},
        {...ok, 'atletaIds': <String>[]},
        {..._on(GuidedActionKind.startBlock, 0).toJson(), 'bloque': -1},
        {..._on(GuidedActionKind.startBlock, 0).toJson(), 'bloque': null},
      ]) {
        expect(
          () => GuidedPassAction.fromJson(bad),
          throwsFormatException,
          reason: '$bad',
        );
      }
    });

    test('the time of a block takes its id from the pass', () {
      expect(blockTimeIdOf('p1', 3), 'p1-3');
      expect(isValidGuidedPassId('a' * maxGuidedPassIdLength), true);
      expect(isValidGuidedPassId(''), false);
    });
  });

  group('applying', () {
    test('begin makes a pass with each block pending and its modes', () {
      final pass = _apply(null, [_begin()]);
      expect(pass.version, 1);
      expect(pass.current, 0);
      expect(pass.start, isNull);
      expect(pass.blocks.map((b) => b.status), [
        GuidedBlockStatus.pending,
        GuidedBlockStatus.pending,
      ]);
      expect(pass.blocks[1].athleteMode, AthleteMode.turns);
      expect(pass.blocks[1].executionMode, ExecutionMode.circuit);
    });

    test('a day without blocks finishes at once', () {
      final pass = _apply(null, [_begin(blocks: const [])]);
      expect(pass.finished, true);
      expect(pass.end, _t0);
    });

    test('start, finish and skip walk the blocks to the end', () {
      final pass = _apply(null, [
        _begin(),
        _on(GuidedActionKind.startBlock, 0, minute: 1),
        _on(GuidedActionKind.finishBlock, 0, minute: 4),
        _on(GuidedActionKind.skipBlock, 1, minute: 5),
      ]);
      expect(pass.blocks[0].status, GuidedBlockStatus.done);
      expect(pass.blocks[0].start, _at(1));
      expect(pass.blocks[0].end, _at(4));
      expect(pass.blocks[1].status, GuidedBlockStatus.skipped);
      expect(pass.start, _at(1));
      expect(pass.finished, true);
      expect(pass.end, _at(5));
      expect(pass.version, 4);
    });

    test('finishing the day interrupts the block running', () {
      final pass = _apply(null, [
        _begin(),
        _on(GuidedActionKind.startBlock, 0, minute: 1),
        GuidedPassAction.finish(passId: 'p1', version: 2, at: _at(3)),
      ]);
      expect(pass.finished, true);
      expect(pass.blocks[0].status, GuidedBlockStatus.interrupted);
      expect(pass.blocks[0].end, _at(3));
      expect(pass.blocks[1].status, GuidedBlockStatus.pending);
    });

    test('modes change only on a block that is not closed', () {
      var pass = _apply(null, [
        _begin(),
        GuidedPassAction.athleteMode(
          passId: 'p1',
          version: 1,
          at: _t0,
          block: 1,
          mode: AthleteMode.simultaneous,
        ),
        GuidedPassAction.executionMode(
          passId: 'p1',
          version: 2,
          at: _t0,
          block: 1,
          mode: ExecutionMode.sequential,
        ),
      ]);
      expect(pass.blocks[1].athleteMode, AthleteMode.simultaneous);
      expect(pass.blocks[1].executionMode, ExecutionMode.sequential);
      pass = _apply(pass, [_on(GuidedActionKind.skipBlock, 0)]);
      final closed = _apply(pass, [
        _on(GuidedActionKind.startBlock, 1),
        _on(GuidedActionKind.finishBlock, 1),
      ]);
      expect(
        applyGuidedAction(
          closed,
          GuidedPassAction.athleteMode(
            passId: 'p1',
            version: 9,
            at: _t0,
            block: 1,
            mode: AthleteMode.turns,
          ),
        ),
        same(closed),
      );
    });
  });

  group('two devices at once', () {
    test('every action applied twice changes nothing the second time', () {
      final actions = [
        _begin(),
        GuidedPassAction.athleteMode(
          passId: 'p1',
          version: 1,
          at: _t0,
          block: 0,
          mode: AthleteMode.turns,
        ),
        _on(GuidedActionKind.startBlock, 0),
        GuidedPassAction.passSets(
          passId: 'p1',
          version: 3,
          at: _t0,
          block: 0,
          sets: {const AthleteSet('ari', 0, 0)},
        ),
        GuidedPassAction.leave(
          passId: 'p1',
          version: 4,
          at: _t0,
          block: 0,
          left: {const LeftPrescription('andi', 0)},
        ),
        _on(GuidedActionKind.finishBlock, 0),
        _on(GuidedActionKind.skipBlock, 1),
      ];
      GuidedPass? pass;
      for (final a in actions) {
        pass = applyGuidedAction(pass, a);
        expect(applyGuidedAction(pass, a), same(pass), reason: a.kind.cable);
      }
      final finished = applyGuidedAction(
        pass,
        GuidedPassAction.finish(passId: 'p1', version: 7, at: _t0),
      );
      expect(finished, same(pass), reason: 'it was already finished');
    });

    test('finishing a block both finished keeps the first one\'s end', () {
      final started = _apply(null, [
        _begin(),
        _on(GuidedActionKind.startBlock, 0, minute: 1),
      ]);
      final first = _apply(started, [
        _on(GuidedActionKind.finishBlock, 0, minute: 3),
      ]);
      final second = applyGuidedAction(
        first,
        _on(GuidedActionKind.finishBlock, 0, minute: 4),
      );
      expect(second, same(first));
      expect(first.blocks[0].end, _at(3));
    });

    test('skipping a block another device started does nothing', () {
      final started = _apply(null, [
        _begin(),
        _on(GuidedActionKind.startBlock, 0),
      ]);
      expect(
        applyGuidedAction(started, _on(GuidedActionKind.skipBlock, 0)),
        same(started),
      );
    });

    test('sets passed on both devices add up', () {
      final started = _apply(null, [
        _begin(),
        _on(GuidedActionKind.startBlock, 0),
      ]);
      final pass = _apply(started, [
        GuidedPassAction.passSets(
          passId: 'p1',
          version: 2,
          at: _t0,
          block: 0,
          sets: {const AthleteSet('ari', 0, 0)},
        ),
        GuidedPassAction.passSets(
          passId: 'p1',
          version: 2,
          at: _t0,
          block: 0,
          sets: {const AthleteSet('andi', 0, 0)},
        ),
      ]);
      expect(pass.blocks[0].passed, {
        const AthleteSet('ari', 0, 0),
        const AthleteSet('andi', 0, 0),
      });
      expect(pass.version, 4);
    });

    test('two "Comenzar" at once: the second joins the first', () {
      final first = _apply(null, [_begin(id: 'a')]);
      final second = applyGuidedAction(first, _begin(id: 'b'));
      expect(second, same(first));
    });

    test('a new pass replaces the one the device saw, or a finished one', () {
      final going = _apply(null, [_begin(id: 'a')]);
      final redone = _apply(going, [
        _begin(id: 'b', replaces: 'a', version: 1, redo: true),
      ]);
      expect(redone.id, 'b');
      expect(redone.redo, true);
      expect(redone.version, 2);

      final finished = _apply(redone, [
        GuidedPassAction.finish(passId: 'b', version: 2, at: _t0),
      ]);
      expect(_apply(finished, [_begin(id: 'c')]).id, 'c');
    });

    test('an action on another pass does nothing', () {
      final pass = _apply(null, [_begin(id: 'b')]);
      expect(
        applyGuidedAction(pass, _on(GuidedActionKind.startBlock, 0, id: 'a')),
        same(pass),
      );
      expect(
        applyGuidedAction(null, _on(GuidedActionKind.startBlock, 0)),
        isNull,
      );
    });
  });
}
