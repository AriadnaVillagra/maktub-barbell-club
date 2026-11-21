/// The guided pass (E7.26): the guided mode of a session as state of the session, the same on every device.
///
/// It keeps who trains, whether the day is redone (E7.23), when it started and ended, and how far each block went
/// (status, instants, athlete mode, order, E7.22). The step on screen is not stored: it follows from the session's
/// records and the sets the pass already went through. Every write is a [GuidedPassAction], applied on the server
/// with `applyGuidedAction` over whatever state is current, so two devices writing at once never break it.
/// Identifiers are English; the wire stays Spanish like the other contracts.
library;

import 'cable.dart';
import 'json.dart';
import 'plan.dart';
import '../reglas/guided_steps.dart';

/// The longest id of a pass: the block times of a pass take their ids from it (`{pass}-{block}`, at most 64).
const maxGuidedPassIdLength = 40;

final _passIdPattern = RegExp(r'^[A-Za-z0-9_-]+$');

/// Whether [id] can be the id of a pass.
bool isValidGuidedPassId(String id) =>
    id.isNotEmpty &&
    id.length <= maxGuidedPassIdLength &&
    _passIdPattern.hasMatch(id);

/// The id of the time of block [blockIndex] in the pass [passId] (E7.19): the same on every device, so the block's
/// time is written once even if two devices close it at once.
String blockTimeIdOf(String passId, int blockIndex) => '$passId-$blockIndex';

/// Where one block of the pass stands.
enum GuidedBlockStatus implements ConCable {
  /// Not started yet: its preview is on screen, or it is still ahead.
  pending('pendiente'),
  running('en_curso'),
  done('terminado'),

  /// Cut short: what was finished stays, the rest is left undone.
  interrupted('interrumpido'),
  skipped('salteado');

  const GuidedBlockStatus(this.cable);
  @override
  final String cable;

  static GuidedBlockStatus deCable(Object? v) =>
      desdeCable(values, v, 'Estado del bloque');
}

/// How far one block of the day went in the pass. What E7.21 turns into a `BlockTime` and the summary.
class GuidedBlockRun {
  const GuidedBlockRun({
    required this.blockIndex,
    required this.athleteMode,
    required this.executionMode,
    this.status = GuidedBlockStatus.pending,
    this.start,
    this.end,
    this.left = const {},
    this.passed = const {},
  });

  /// Position of the block in the day (0-based).
  final int blockIndex;

  /// The athlete mode in force; once closed, the one it ended with. Meaningless for a block without steps.
  final AthleteMode athleteMode;

  /// Sequential or circuit in force (E7.22); starts as the plan's and does not change the plan.
  final ExecutionMode executionMode;
  final GuidedBlockStatus status;

  /// When "Iniciar bloque" was tapped and when the block closed; null for a skipped block.
  final DateTime? start;
  final DateTime? end;

  /// Athletes who left a prescription, or the whole prescription when "Saltar este ejercicio".
  final Set<LeftPrescription> left;

  /// Sets the pass went through, recorded or marked "No hizo esta serie": they are not offered again.
  final Set<AthleteSet> passed;

  bool get closed =>
      status == GuidedBlockStatus.done ||
      status == GuidedBlockStatus.interrupted ||
      status == GuidedBlockStatus.skipped;

  GuidedBlockRun copyWith({
    AthleteMode? athleteMode,
    ExecutionMode? executionMode,
    GuidedBlockStatus? status,
    DateTime? start,
    DateTime? end,
    Set<LeftPrescription>? left,
    Set<AthleteSet>? passed,
  }) => GuidedBlockRun(
    blockIndex: blockIndex,
    athleteMode: athleteMode ?? this.athleteMode,
    executionMode: executionMode ?? this.executionMode,
    status: status ?? this.status,
    start: start ?? this.start,
    end: end ?? this.end,
    left: left ?? this.left,
    passed: passed ?? this.passed,
  );

  factory GuidedBlockRun.fromJson(Json j) => GuidedBlockRun(
    blockIndex: enteroOpcional(j['bloque'])!,
    athleteMode: AthleteMode.deCable(j['modoAtletas']),
    executionMode: ExecutionMode.deCable(j['modoEjecucion']),
    status: GuidedBlockStatus.deCable(j['estado']),
    start: _instantOrNull(j['inicio']),
    end: _instantOrNull(j['fin']),
    left: {for (final l in listaJson(j['dejados'])) _leftFromJson(l)},
    passed: {for (final s in listaJson(j['pasadas'])) _setFromJson(s)},
  );

  Json toJson() => {
    'bloque': blockIndex,
    'modoAtletas': athleteMode.cable,
    'modoEjecucion': executionMode.cable,
    'estado': status.cable,
    ...sinNulos({
      'inicio': start?.toUtc().toIso8601String(),
      'fin': end?.toUtc().toIso8601String(),
    }),
    'dejados': [for (final l in left) _leftToJson(l)],
    'pasadas': [for (final s in passed) _setToJson(s)],
  };
}

/// The guided mode of a session, shared by every device in it. A session without one has not been trained in the
/// guided mode yet (sessions written before E7.26 have none).
class GuidedPass {
  const GuidedPass({
    required this.id,
    this.version = 1,
    required this.athleteIds,
    this.redo = false,
    this.start,
    this.end,
    this.blocks = const [],
    this.current = 0,
    this.finished = false,
  });

  /// Generated by the device that began it ([isValidGuidedPassId]). A new pass ("hacer todo de nuevo", or after
  /// the day was finished) has a new one.
  final String id;

  /// How many changes the pass has had, from 1 when it begins. Each write carries the version it read.
  final int version;

  /// Who trains, in the order chosen: the order of the turns and of the cards.
  final List<String> athleteIds;

  /// "Hacer todo de nuevo" (E7.23): every set is walked again, recorded or not; only what this pass went through
  /// counts as done. Nothing is ever unmarked.
  final bool redo;

  /// When the pass began ("Comenzar"), and when it finished. A pass begun before that was stamped has the first
  /// block's start.
  final DateTime? start;
  final DateTime? end;

  /// One per block of the day, in order.
  final List<GuidedBlockRun> blocks;

  /// Index of the block on screen: the ones before it are closed.
  final int current;

  /// The day was finished: every device goes to the summary.
  final bool finished;

  /// The block on screen while the pass goes on.
  GuidedBlockRun? get run =>
      finished || current >= blocks.length ? null : blocks[current];

  GuidedPass copyWith({
    int? version,
    DateTime? start,
    DateTime? end,
    List<GuidedBlockRun>? blocks,
    int? current,
    bool? finished,
  }) => GuidedPass(
    id: id,
    version: version ?? this.version,
    athleteIds: athleteIds,
    redo: redo,
    start: start ?? this.start,
    end: end ?? this.end,
    blocks: blocks ?? this.blocks,
    current: current ?? this.current,
    finished: finished ?? this.finished,
  );

  factory GuidedPass.fromJson(Json j) => GuidedPass(
    id: '${j['id']}',
    version: enteroOpcional(j['version']) ?? 1,
    athleteIds: [for (final a in (j['atletaIds'] as List? ?? const [])) '$a'],
    redo: j['deNuevo'] == true,
    start: _instantOrNull(j['inicio']),
    end: _instantOrNull(j['fin']),
    blocks: [
      for (final b in listaJson(j['bloques'])) GuidedBlockRun.fromJson(b),
    ],
    current: enteroOpcional(j['actual']) ?? 0,
    finished: j['terminada'] == true,
  );

  Json toJson() => {
    'id': id,
    'version': version,
    'atletaIds': athleteIds,
    'deNuevo': redo,
    ...sinNulos({
      'inicio': start?.toUtc().toIso8601String(),
      'fin': end?.toUtc().toIso8601String(),
    }),
    'bloques': [for (final b in blocks) b.toJson()],
    'actual': current,
    'terminada': finished,
  };
}

/// What a write of the pass does.
enum GuidedActionKind implements ConCable {
  /// "Comenzar": a new pass with the athletes chosen.
  begin('comenzar'),

  /// Simultaneous or by turns for a block.
  athleteMode('modo_atletas'),

  /// Sequential or circuit for a block (E7.22).
  executionMode('modo_ejecucion'),
  startBlock('iniciar_bloque'),
  skipBlock('saltar_bloque'),

  /// "Terminar bloque", or the block closing by itself once nothing is left of it.
  finishBlock('terminar_bloque'),
  interruptBlock('interrumpir_bloque'),

  /// Sets the pass went through ("Terminar serie", including the athletes marked "No hizo esta serie").
  passSets('pasar_series'),

  /// "Dejar el ejercicio" or "Saltar este ejercicio".
  leave('dejar'),

  /// "Terminar" the day: the pass closes for every device.
  finish('terminar');

  const GuidedActionKind(this.cable);
  @override
  final String cable;

  static GuidedActionKind deCable(Object? v) =>
      desdeCable(values, v, 'Acción de la pasada');
}

/// The modes a block starts with when a pass begins: the plan's.
class GuidedBlockStart {
  const GuidedBlockStart({
    required this.athleteMode,
    required this.executionMode,
  });

  final AthleteMode athleteMode;
  final ExecutionMode executionMode;

  factory GuidedBlockStart.fromJson(Json j) => GuidedBlockStart(
    athleteMode: AthleteMode.deCable(j['modoAtletas']),
    executionMode: ExecutionMode.deCable(j['modoEjecucion']),
  );

  Json toJson() => {
    'modoAtletas': athleteMode.cable,
    'modoEjecucion': executionMode.cable,
  };
}

/// One write of the pass. It says what was meant, on which pass and block, so applying it again over a newer state
/// does what still makes sense and nothing else (finishing a block that already closed does nothing).
class GuidedPassAction {
  const GuidedPassAction._({
    required this.kind,
    required this.passId,
    required this.version,
    required this.at,
    this.replaces,
    this.athleteIds = const [],
    this.redo = false,
    this.blockStarts = const [],
    this.blockIndex,
    this.athleteMode,
    this.executionMode,
    this.sets = const {},
    this.left = const {},
  });

  /// A new pass [passId]. [replaces] is the pass the device saw, if any: a pass begun meanwhile by another device
  /// that is still going on wins, and this one joins it.
  const GuidedPassAction.begin({
    required String passId,
    required int version,
    required DateTime at,
    String? replaces,
    required List<String> athleteIds,
    bool redo = false,
    required List<GuidedBlockStart> blocks,
  }) : this._(
         kind: GuidedActionKind.begin,
         passId: passId,
         version: version,
         at: at,
         replaces: replaces,
         athleteIds: athleteIds,
         redo: redo,
         blockStarts: blocks,
       );

  const GuidedPassAction.athleteMode({
    required String passId,
    required int version,
    required DateTime at,
    required int block,
    required AthleteMode mode,
  }) : this._(
         kind: GuidedActionKind.athleteMode,
         passId: passId,
         version: version,
         at: at,
         blockIndex: block,
         athleteMode: mode,
       );

  const GuidedPassAction.executionMode({
    required String passId,
    required int version,
    required DateTime at,
    required int block,
    required ExecutionMode mode,
  }) : this._(
         kind: GuidedActionKind.executionMode,
         passId: passId,
         version: version,
         at: at,
         blockIndex: block,
         executionMode: mode,
       );

  /// "Iniciar bloque", "Saltar bloque", "Terminar bloque" or "Interrumpir bloque" on [block].
  const GuidedPassAction.onBlock(
    GuidedActionKind kind, {
    required String passId,
    required int version,
    required DateTime at,
    required int block,
  }) : this._(
         kind: kind,
         passId: passId,
         version: version,
         at: at,
         blockIndex: block,
       );

  const GuidedPassAction.passSets({
    required String passId,
    required int version,
    required DateTime at,
    required int block,
    required Set<AthleteSet> sets,
  }) : this._(
         kind: GuidedActionKind.passSets,
         passId: passId,
         version: version,
         at: at,
         blockIndex: block,
         sets: sets,
       );

  const GuidedPassAction.leave({
    required String passId,
    required int version,
    required DateTime at,
    required int block,
    required Set<LeftPrescription> left,
  }) : this._(
         kind: GuidedActionKind.leave,
         passId: passId,
         version: version,
         at: at,
         blockIndex: block,
         left: left,
       );

  const GuidedPassAction.finish({
    required String passId,
    required int version,
    required DateTime at,
  }) : this._(
         kind: GuidedActionKind.finish,
         passId: passId,
         version: version,
         at: at,
       );

  final GuidedActionKind kind;

  /// The pass it acts on; for [GuidedActionKind.begin], the new pass.
  final String passId;

  /// The version of the pass the device read when it wrote this (0 without a pass).
  final int version;

  /// When it happened on the device (UTC). The pass's instants come from here, so a write sent later without
  /// signal keeps the time it was done.
  final DateTime at;

  final String? replaces;
  final List<String> athleteIds;
  final bool redo;
  final List<GuidedBlockStart> blockStarts;
  final int? blockIndex;
  final AthleteMode? athleteMode;
  final ExecutionMode? executionMode;
  final Set<AthleteSet> sets;
  final Set<LeftPrescription> left;

  /// Reads a write as the device sent it. Throws [FormatException] when it is malformed.
  factory GuidedPassAction.fromJson(Json j) {
    final kind = GuidedActionKind.deCable(j['tipo']);
    final passId = j['pasadaId'];
    if (passId is! String || !isValidGuidedPassId(passId)) {
      throw const FormatException('"pasadaId" no es válido.');
    }
    final version = j['version'];
    if (version is! num || version < 0 || version != version.roundToDouble()) {
      throw const FormatException('"version" debe ser un entero desde 0.');
    }
    final at = j['en'] is String ? DateTime.tryParse(j['en'] as String) : null;
    if (at == null) {
      throw const FormatException('"en" debe ser un instante ISO 8601.');
    }
    int block() {
      final b = j['bloque'];
      if (b is! num || b < 0 || b != b.roundToDouble()) {
        throw const FormatException('"bloque" debe ser un entero desde 0.');
      }
      return b.toInt();
    }

    final common = (passId: passId, version: version.toInt(), at: at.toUtc());
    switch (kind) {
      case GuidedActionKind.begin:
        final athletes = j['atletaIds'];
        if (athletes is! List ||
            athletes.isEmpty ||
            athletes.any((a) => a is! String || a.trim().isEmpty)) {
          throw const FormatException(
            '"atletaIds" debe ser una lista de ids, al menos uno.',
          );
        }
        final replaces = j['reemplaza'];
        if (replaces != null && replaces is! String) {
          throw const FormatException('"reemplaza" debe ser texto.');
        }
        final blocks = j['bloques'];
        if (blocks is! List || blocks.length > maxGuidedBlocks) {
          throw const FormatException('"bloques" debe ser una lista.');
        }
        return GuidedPassAction.begin(
          passId: common.passId,
          version: common.version,
          at: common.at,
          replaces: replaces as String?,
          athleteIds: [
            for (final a in {...athletes.cast<String>()}) a,
          ],
          redo: j['deNuevo'] == true,
          blocks: [
            for (final b in blocks)
              GuidedBlockStart.fromJson((b as Map).cast<String, dynamic>()),
          ],
        );
      case GuidedActionKind.athleteMode:
        return GuidedPassAction.athleteMode(
          passId: common.passId,
          version: common.version,
          at: common.at,
          block: block(),
          mode: AthleteMode.deCable(j['modoAtletas']),
        );
      case GuidedActionKind.executionMode:
        return GuidedPassAction.executionMode(
          passId: common.passId,
          version: common.version,
          at: common.at,
          block: block(),
          mode: ExecutionMode.deCable(j['modoEjecucion']),
        );
      case GuidedActionKind.startBlock ||
          GuidedActionKind.skipBlock ||
          GuidedActionKind.finishBlock ||
          GuidedActionKind.interruptBlock:
        return GuidedPassAction.onBlock(
          kind,
          passId: common.passId,
          version: common.version,
          at: common.at,
          block: block(),
        );
      case GuidedActionKind.passSets:
        return GuidedPassAction.passSets(
          passId: common.passId,
          version: common.version,
          at: common.at,
          block: block(),
          sets: {for (final s in listaJson(j['series'])) _setFromJson(s)},
        );
      case GuidedActionKind.leave:
        return GuidedPassAction.leave(
          passId: common.passId,
          version: common.version,
          at: common.at,
          block: block(),
          left: {for (final l in listaJson(j['dejados'])) _leftFromJson(l)},
        );
      case GuidedActionKind.finish:
        return GuidedPassAction.finish(
          passId: common.passId,
          version: common.version,
          at: common.at,
        );
    }
  }

  Json toJson() => {
    'tipo': kind.cable,
    'pasadaId': passId,
    'version': version,
    'en': at.toUtc().toIso8601String(),
    if (kind == GuidedActionKind.begin) ...{
      'reemplaza': ?replaces,
      'atletaIds': athleteIds,
      'deNuevo': redo,
      'bloques': [for (final b in blockStarts) b.toJson()],
    },
    'bloque': ?blockIndex,
    'modoAtletas': ?athleteMode?.cable,
    'modoEjecucion': ?executionMode?.cable,
    if (kind == GuidedActionKind.passSets)
      'series': [for (final s in sets) _setToJson(s)],
    if (kind == GuidedActionKind.leave)
      'dejados': [for (final l in left) _leftToJson(l)],
  };
}

/// The most blocks a pass takes: far above any real day.
const maxGuidedBlocks = 100;

DateTime? _instantOrNull(Object? v) =>
    v == null ? null : DateTime.parse('$v').toUtc();

int _index(Object? v, String field) {
  if (v is! num || v < 0 || v != v.roundToDouble()) {
    throw FormatException('"$field" debe ser un entero desde 0.');
  }
  return v.toInt();
}

String _athlete(Object? v) {
  if (v is! String || v.trim().isEmpty) {
    throw const FormatException('"atletaId" debe ser un id.');
  }
  return v;
}

LeftPrescription _leftFromJson(Json j) => LeftPrescription(
  _athlete(j['atletaId']),
  _index(j['prescripcion'], 'prescripcion'),
);

Json _leftToJson(LeftPrescription l) => {
  'atletaId': l.athleteId,
  'prescripcion': l.prescription,
};

AthleteSet _setFromJson(Json j) => AthleteSet(
  _athlete(j['atletaId']),
  _index(j['prescripcion'], 'prescripcion'),
  _index(j['serie'], 'serie'),
);

Json _setToJson(AthleteSet s) => {
  'atletaId': s.athleteId,
  'prescripcion': s.prescription,
  'serie': s.set,
};
