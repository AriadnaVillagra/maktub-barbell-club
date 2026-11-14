import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../domain/timer_platform.dart';

/// In the browser: Web Audio for the tone, `navigator.vibrate` and the Screen Wake Lock. Browsers differ on all three
/// (iOS has no vibration), so each one is tried on its own and its failure is the controller's to ignore.
TimerPlatform createTimerPlatform() => _WebTimerPlatform();

class _WebTimerPlatform implements TimerPlatform {
  web.AudioContext? _audio;
  web.WakeLockSentinel? _lock;
  bool _wantsScreen = false;
  bool _listening = false;

  /// The browser releases the lock when the tab is hidden; ask again when it comes back.
  void _listenForVisibility() {
    if (_listening) return;
    _listening = true;
    web.document.addEventListener(
      'visibilitychange',
      ((web.Event _) {
        if (_wantsScreen && web.document.visibilityState == 'visible') _lockScreen();
      }).toJS,
    );
  }

  Future<void> _lockScreen() async {
    try {
      _lock = await web.window.navigator.wakeLock.request().toDart;
    } catch (_) {
      _lock = null;
    }
  }

  @override
  Future<void> start() async {
    _wantsScreen = true;
    _listenForVisibility();
    // The audio context only starts from a user gesture, which is when a timer starts.
    try {
      final audio = _audio ??= web.AudioContext();
      if (audio.state == 'suspended') await audio.resume().toDart;
    } catch (_) {
      // No sound; the screen lock below is independent of it.
    }
    await _lockScreen();
  }

  @override
  Future<void> stop() async {
    _wantsScreen = false;
    final lock = _lock;
    _lock = null;
    if (lock != null) await lock.release().toDart;
  }

  @override
  Future<void> beep({required double hz, required Duration duration}) async {
    final audio = _audio;
    if (audio == null) return;
    final seconds = duration.inMilliseconds / 1000;
    final now = audio.currentTime;
    final oscillator = audio.createOscillator()
      ..type = 'sine'
      ..frequency.value = hz;
    final volume = audio.createGain();
    volume.gain.setValueAtTime(0.0001, now);
    volume.gain.exponentialRampToValueAtTime(0.4, now + 0.01);
    volume.gain.exponentialRampToValueAtTime(0.0001, now + seconds);
    oscillator.connect(volume);
    volume.connect(audio.destination);
    oscillator.start();
    oscillator.stop(now + seconds + 0.02);
  }

  @override
  Future<void> vibrate(List<int> pattern) async {
    web.window.navigator.vibrate([for (final ms in pattern) ms.toJS].toJS);
  }
}
