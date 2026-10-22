import 'sound_player_interface.dart';

SoundPlayerTransport createSoundPlayerTransport() => _StubSoundPlayerTransport();

class _StubSoundPlayerTransport implements SoundPlayerTransport {
  @override
  bool playSound(String type) => false;
}
