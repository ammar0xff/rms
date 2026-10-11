import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/core/config/firebase_config.dart';

void main() {
  group('FirebaseConfig', () {
    test('empty config is not usable', () {
      const config = FirebaseConfig.empty();
      expect(config.isConfigured, isFalse);
    });

    test('config missing appId is not usable', () {
      const config = FirebaseConfig(
        apiKey: 'k',
        authDomain: 'a',
        projectId: 'p',
        storageBucket: 's',
        messagingSenderId: 'm',
        appId: '',
      );
      expect(config.isConfigured, isFalse);
    });

    test('fully specified config is usable', () {
      const config = FirebaseConfig(
        apiKey: 'k',
        authDomain: 'a.firebaseapp.com',
        projectId: 'p',
        storageBucket: 's.appspot.com',
        messagingSenderId: '1',
        appId: '1:1:web:abc',
        environment: 'prod',
      );
      expect(config.isConfigured, isTrue);
      expect(config.environment, 'prod');
      final options = config.toOptions();
      expect(options.projectId, 'p');
      expect(options.appId, '1:1:web:abc');
      expect(options.measurementId, isNull);
    });
  });
}
