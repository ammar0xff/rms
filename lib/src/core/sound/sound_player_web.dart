import 'dart:js_interop';
import 'sound_player_interface.dart';

@JS('piePlaySound')
external bool _piePlaySound(JSString type);

SoundPlayerTransport createSoundPlayerTransport() => _WebSoundPlayerTransport();

class _WebSoundPlayerTransport implements SoundPlayerTransport {
  @override
  bool playSound(String type) {
    try {
      return _piePlaySound(type.toJS);
    } catch (_) {
      return false;
    }
  }
}
