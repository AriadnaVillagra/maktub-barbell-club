import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/timer_platform_stub.dart' if (dart.library.js_interop) '../data/timer_platform_web.dart';
import '../domain/crono_result.dart';
import '../domain/timer_platform.dart';

/// Sound, vibration and wake lock of the device. Tests override it with a fake.
final timerPlatformProvider = Provider<TimerPlatform>((ref) => createTimerPlatform());

/// What the athlete finished in the running timer, or in the last one: the for time's final time, the Death By round.
/// A new timer clears it.
final cronoResultsProvider = NotifierProvider<CronoResults, List<CronoResult>>(CronoResults.new);

class CronoResults extends Notifier<List<CronoResult>> {
  @override
  List<CronoResult> build() => const [];

  void add(CronoResult result) => state = [...state, result];

  void clear() => state = const [];
}
