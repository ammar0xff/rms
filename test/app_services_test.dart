import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/core/config/firebase_config.dart';
import 'package:rms/src/core/di/app_services.dart';
import 'package:rms/src/data/repositories/demo_auth_repository.dart';

const FirebaseConfig _configured = FirebaseConfig(
  apiKey: 'k',
  authDomain: 'a.firebaseapp.com',
  projectId: 'p',
  storageBucket: 's.appspot.com',
  messagingSenderId: '1',
  appId: '1:1:web:abc',
);

void main() {
  group('AppServices', () {
    test('is demo when Firebase is unconfigured', () {
      final services = AppServices(
        config: const FirebaseConfig.empty(),
        auth: DemoAuthRepository(),
        firebaseReady: false,
      );
      expect(services.isDemo, isTrue);
      expect(services.hasLocalStore, isFalse);
    });

    test('is demo when configured but not ready', () {
      final services = AppServices(
        config: _configured,
        auth: DemoAuthRepository(),
        firebaseReady: false,
      );
      expect(services.isDemo, isTrue);
    });

    test('is not demo when Firebase is ready', () {
      final services = AppServices(
        config: _configured,
        auth: DemoAuthRepository(),
        firebaseReady: true,
      );
      expect(services.isDemo, isFalse);
    });
  });
}
