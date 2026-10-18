import 'package:flutter/services.dart';

enum PieSound {
  click,
  pop,
  beep,
  chime,
}

/// Unified sound effects controller for PIE operations.
///
/// Provides snappy, tactile feedback for:
/// - Button taps, keypad presses, and category changes ([PieSound.click], [PieSound.pop])
/// - Errors, voids, and invalid validation ([PieSound.beep])
/// - Successful order placement, payments, and shift closings ([PieSound.chime])
///
/// Sound effects are toggleable via Settings.
class PieSoundService {
  PieSoundService._();
  static final PieSoundService instance = PieSoundService._();

  bool enabled = true;

  void play(PieSound sound) {
    if (!enabled) return;
    try {
      switch (sound) {
        case PieSound.click:
          SystemSound.play(SystemSoundType.click);
          HapticFeedback.selectionClick();
          break;
        case PieSound.pop:
          SystemSound.play(SystemSoundType.click);
          HapticFeedback.lightImpact();
          break;
        case PieSound.beep:
          SystemSound.play(SystemSoundType.alert);
          HapticFeedback.heavyImpact();
          break;
        case PieSound.chime:
          SystemSound.play(SystemSoundType.click);
          HapticFeedback.mediumImpact();
          break;
      }
    } catch (_) {}
  }

  void click() => play(PieSound.click);
  void pop() => play(PieSound.pop);
  void beep() => play(PieSound.beep);
  void chime() => play(PieSound.chime);

  static void playOrderPlaced() => instance.chime();
  static void playCashDrawer() => instance.chime();
  static void playRoleSwitch() => instance.pop();
  static void playClick() => instance.click();
  static void playBeep() => instance.beep();
}
