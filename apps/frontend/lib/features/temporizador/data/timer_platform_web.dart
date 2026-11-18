import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../domain/timer_platform.dart';

/// In the browser: Web Audio for the tone, `navigator.vibrate` and the Screen Wake Lock. Browsers differ on all three
/// (iOS has no vibration), so each one is tried on its own and its failure is the controller's to ignore.
///
/// In the background the page's own timers slow down or stop, so the tones of a running timer are scheduled ahead on
/// the audio clock, which keeps going. While a timer runs the page also plays an inaudible tone: a page that plays
/// audio is not suspended, and on iOS the audio session is set to "playback" so it goes on with the screen locked.
TimerPlatform createTimerPlatform() => _WebTimerPlatform();

class _WebTimerPlatform implements TimerPlatform {
  web.AudioContext? _audio;
  web.WakeLockSentinel? _lock;
  web.OscillatorNode? _keepAlive;
  bool _wantsScreen = false;
  bool _listening = false;

  /// What is scheduled, to redo it on the audio clock if the context was suspended meanwhile (its clock stops then).
  List<ScheduledTone> _tones = const [];
  final _scheduled = <({web.OscillatorNode node, double when})>[];

  /// Back in the foreground: the browser released the lock, and may have suspended the audio.
  void _listenForVisibility() {
    if (_listening) return;
    _listening = true;
    web.document.addEventListener(
      'visibilitychange',
      ((web.Event _) {
        if (!_wantsScreen || web.document.visibilityState != 'visible') return;
        _lockScreen();
        _resumeAudio();
      }).toJS,
    );
  }

  Future<void> _resumeAudio() async {
    final audio = _audio;
    if (audio == null || audio.state == 'running') return;
    try {
      await audio.resume().toDart;
      _place(_tones);
    } catch (_) {
      // Still suspended; the next gesture or visibility change tries again.
    }
  }

  Future<void> _lockScreen() async {
    try {
      _lock = await web.window.navigator.wakeLock.request().toDart;
    } catch (_) {
      _lock = null;
    }
  }

  /// iOS (Safari 16.4+): with "playback" the page's audio goes on in the background and ignores the silent switch.
  void _playbackSession() {
    try {
      final session = (web.window.navigator as JSObject).getProperty<JSObject?>('audioSession'.toJS);
      session?.setProperty('type'.toJS, 'playback'.toJS);
    } catch (_) {
      // Not supported: the default session.
    }
  }

  /// A 30 Hz tone at -60 dB: phone speakers do not play it, but the browser counts the page as playing audio.
  void _startKeepAlive(web.AudioContext audio) {
    if (_keepAlive != null) return;
    final oscillator = audio.createOscillator()..frequency.value = 30;
    final volume = audio.createGain()..gain.value = 0.001;
    oscillator.connect(volume);
    volume.connect(audio.destination);
    oscillator.start();
    _keepAlive = oscillator;
  }

  void _stopKeepAlive() {
    try {
      _keepAlive?.stop();
    } catch (_) {
      // Already stopped.
    }
    _keepAlive = null;
  }

  @override
  Future<void> start() async {
    _wantsScreen = true;
    _listenForVisibility();
    _playbackSession();
    // The audio context only starts from a user gesture, which is when a timer starts.
    try {
      final audio = _audio ??= web.AudioContext();
      if (audio.state == 'suspended') await audio.resume().toDart;
      _startKeepAlive(audio);
    } catch (_) {
      // No sound; the screen lock below is independent of it.
    }
    await _lockScreen();
  }

  @override
  Future<void> stop() async {
    _wantsScreen = false;
    _stopKeepAlive();
    await schedule(const []);
    final lock = _lock;
    _lock = null;
    if (lock != null) await lock.release().toDart;
  }

  /// A tone [seconds] long starting at [when] on the audio clock.
  web.OscillatorNode? _tone(double hz, double seconds, double when) {
    final audio = _audio;
    if (audio == null) return null;
    final oscillator = audio.createOscillator()
      ..type = 'sine'
      ..frequency.value = hz;
    final volume = audio.createGain();
    volume.gain.setValueAtTime(0.0001, when);
    volume.gain.exponentialRampToValueAtTime(0.4, when + 0.01);
    volume.gain.exponentialRampToValueAtTime(0.0001, when + seconds);
    oscillator.connect(volume);
    volume.connect(audio.destination);
    oscillator.start(when);
    oscillator.stop(when + seconds + 0.02);
    return oscillator;
  }

  @override
  Future<void> beep({required double hz, required Duration duration}) async {
    final audio = _audio;
    if (audio == null) return;
    _tone(hz, duration.inMilliseconds / 1000, audio.currentTime);
  }

  @override
  Future<void> schedule(List<ScheduledTone> tones) async {
    _tones = tones;
    _place(tones);
  }

  /// Cancels what was placed and places [tones] that are still ahead, mapping wall-clock instants to the audio clock.
  void _place(List<ScheduledTone> tones) {
    final audio = _audio;
    // Only what has not started: a tone already sounding (the end, as the timer closes) is left to finish.
    for (final tone in _scheduled) {
      if (audio != null && tone.when <= audio.currentTime) continue;
      try {
        tone.node.stop();
      } catch (_) {
        // Already played.
      }
    }
    _scheduled.clear();
    if (audio == null) return;
    final now = DateTime.now();
    final base = audio.currentTime;
    for (final tone in tones) {
      final ahead = tone.at.difference(now).inMilliseconds / 1000;
      if (ahead < 0) continue;
      final when = base + ahead;
      if (_tone(tone.hz, tone.duration.inMilliseconds / 1000, when) case final node?) {
        _scheduled.add((node: node, when: when));
      }
    }
  }

  @override
  Future<void> vibrate(List<int> pattern) async {
    web.window.navigator.vibrate([for (final ms in pattern) ms.toJS].toJS);
  }
}
