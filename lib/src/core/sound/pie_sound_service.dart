import 'package:flutter/services.dart';
import 'sound_player.dart';

enum PieSound {
  click,
  pop,
  beep,
  chime,
  alert,
}

/// Unified sound effects controller for PIE operations.
///
/// Provides snappy, tactile feedback for:
/// - Button taps, keypad presses, and category changes ([PieSound.click], [PieSound.pop])
/// - Item additions, barcode scans, quantity increases ([PieSound.beep])
/// - Successful order placement, payments, shift closings ([PieSound.chime])
/// - Errors, cancellations, voids ([PieSound.alert])
///
/// Supports Web Audio API synthesis in browsers and native SystemSound/haptics on mobile/desktop.
/// Sound effects are toggleable via Settings.
class PieSoundService {
  PieSoundService._();
  static final PieSoundService instance = PieSoundService._();

  static final SoundPlayerTransport _transport = createSoundPlayerTransport();

  bool enabled = true;

  void play(PieSound sound) {
    if (!enabled) return;
    try {
      // 1. Web Audio API synthesized sound (instant in browser)
      final playedOnWeb = _transport.playSound(sound.name);

      // 2. Native haptics & system sounds (mobile/desktop fallback)
      switch (sound) {
        case PieSound.click:
          if (!playedOnWeb) SystemSound.play(SystemSoundType.click);
          HapticFeedback.selectionClick();
          break;
        case PieSound.pop:
          if (!playedOnWeb) SystemSound.play(SystemSoundType.click);
          HapticFeedback.lightImpact();
          break;
        case PieSound.beep:
          if (!playedOnWeb) SystemSound.play(SystemSoundType.alert);
          HapticFeedback.lightImpact();
          break;
        case PieSound.chime:
          if (!playedOnWeb) SystemSound.play(SystemSoundType.click);
          HapticFeedback.mediumImpact();
          break;
        case PieSound.alert:
          if (!playedOnWeb) SystemSound.play(SystemSoundType.alert);
          HapticFeedback.heavyImpact();
          break;
      }
    } catch (_) {}
  }

  void click() => play(PieSound.click);
  void pop() => play(PieSound.pop);
  void beep() => play(PieSound.beep);
  void chime() => play(PieSound.chime);
  void alert() => play(PieSound.alert);

  static void playOrderPlaced() => instance.chime();
  static void playCashDrawer() => instance.chime();
  static void playRoleSwitch() => instance.pop();
  static void playClick() => instance.click();
  static void playBeep() => instance.beep();
  static void playAlert() => instance.alert();
}
