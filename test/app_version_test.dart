import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/core/config/app_version.dart';
import 'package:rms/src/core/config/app_version_reader.dart';
import 'package:rms/src/core/config/device_update_context.dart';

const _channel = MethodChannel('test/app-version');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    AppVersion.reset();
  });

  void mock(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, handler);
  }

  test('hydrate records the version the platform reports', () async {
    mock((_) async => {'versionName': '0.10.0', 'versionCode': 42});

    await AppVersionReader.hydrate(channel: _channel);

    expect(AppVersion.number, '0.10.0');
    expect(AppVersion.build, 42);
    expect(AppVersion.string, '0.10.0 · build 42');
  });

  test('the update engine compares against the hydrated version', () async {
    mock((_) async => {'versionName': '0.10.0', 'versionCode': 42});
    await AppVersionReader.hydrate(channel: _channel);

    final context = buildUpdateContext(now: DateTime(2026, 10, 14));

    expect(context.installedVersion, '0.10.0');
    expect(context.installedBuild, 42);
  });

  test('a blank version name is ignored, keeping the fallback', () async {
    mock((_) async => {'versionName': '   ', 'versionCode': 7});

    await AppVersionReader.hydrate(channel: _channel);

    expect(AppVersion.number, AppVersion.compiledNumber);
    // The build number is still usable, and is applied on its own.
    expect(AppVersion.build, 7);
  });

  test('a nonsensical build number is ignored', () {
    AppVersion.apply(version: '1.2.3', build: 0);

    expect(AppVersion.build, AppVersion.compiledBuild);
  });

  test('a platform with no handler leaves the fallbacks in place', () async {
    // Nothing registered on the channel: the handler is missing, which is the
    // shape of web, desktop, and a plain test host.
    await AppVersionReader.hydrate(channel: _channel);

    expect(AppVersion.number, AppVersion.compiledNumber);
    expect(AppVersion.build, AppVersion.compiledBuild);
  });

  test('a platform error leaves the fallbacks in place', () async {
    mock((_) async => throw PlatformException(code: 'boom'));

    await AppVersionReader.hydrate(channel: _channel);

    expect(AppVersion.number, AppVersion.compiledNumber);
  });

  test('a malformed reply leaves the fallbacks in place', () async {
    mock((_) async => {'versionName': 1, 'versionCode': 'two'});

    await AppVersionReader.hydrate(channel: _channel);

    expect(AppVersion.number, AppVersion.compiledNumber);
    expect(AppVersion.build, AppVersion.compiledBuild);
  });
}
