import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/sesion/data/shared_preferences_guided_position_store.dart';
import 'package:maktub_frontend/features/sesion/domain/guided_position.dart';
import 'package:maktub_frontend/features/sesion/domain/guided_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const position = GuidedPosition(
    sessionId: 's1',
    passId: 'p1',
    block: 2,
    draft: GuidedStepDraft(
      prescription: 1,
      set: 0,
      running: true,
      notDone: {'andi'},
      edits: {'ari': SetEdit(manualKg: 82.5, reps: 4), 'luz': SetEdit()},
    ),
    reviewing: GuidedStep(prescription: 0, set: 1, athleteIds: ['ari']),
    reviewDraft: GuidedStepDraft(prescription: 0, set: 1, running: true),
  );

  test(
    'a position saved is read back the same by a new store (a reload)',
    () async {
      SharedPreferences.setMockInitialValues({});
      await SharedPreferencesGuidedPositionStore().save(position);

      final read = (await SharedPreferencesGuidedPositionStore().load())!;

      expect((read.sessionId, read.passId, read.block), ('s1', 'p1', 2));
      final draft = read.draft!;
      expect((draft.prescription, draft.set, draft.running), (1, 0, true));
      expect(draft.notDone, {'andi'});
      expect(draft.edits['ari']?.manualKg, 82.5);
      expect(draft.edits['ari']?.reps, 4);
      expect(draft.edits['luz']?.manualKg, isNull);
      expect(
        read.reviewing,
        const GuidedStep(prescription: 0, set: 1, athleteIds: ['ari']),
      );
      expect(read.reviewDraft?.running, true);
    },
  );

  test('null forgets it, and unreadable storage gives nothing', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesGuidedPositionStore();
    await store.save(position);
    await store.save(null);
    expect(await SharedPreferencesGuidedPositionStore().load(), isNull);

    SharedPreferences.setMockInitialValues({
      SharedPreferencesGuidedPositionStore.key: '{not json',
    });
    expect(await SharedPreferencesGuidedPositionStore().load(), isNull);
  });

  test(
    'the memory over the store reads it once, and a save meanwhile wins',
    () async {
      SharedPreferences.setMockInitialValues({});
      await SharedPreferencesGuidedPositionStore().save(position);
      final remembered = RememberedGuidedPosition(
        SharedPreferencesGuidedPositionStore(),
      );
      expect(remembered.loaded, false);
      final loading = remembered.load();
      remembered.save(null);
      await loading;
      expect(remembered.loaded, true);
      expect(remembered.value, isNull);
    },
  );
}
