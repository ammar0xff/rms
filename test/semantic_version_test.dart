import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/domain/models/semantic_version.dart';

void main() {
  group('SemanticVersion.tryParse', () {
    test('parses a plain three-part version', () {
      final version = SemanticVersion.tryParse('1.20.300');
      expect(version, const SemanticVersion(1, 20, 300));
      expect(version.toString(), '1.20.300');
    });

    test('rejects malformed versions', () {
      expect(SemanticVersion.tryParse(null), isNull);
      expect(SemanticVersion.tryParse(''), isNull);
      expect(SemanticVersion.tryParse('1'), isNull);
      expect(SemanticVersion.tryParse('1.2'), isNull);
      expect(SemanticVersion.tryParse('1.2.3.4'), isNull);
      expect(SemanticVersion.tryParse('1.2.x'), isNull);
      expect(SemanticVersion.tryParse('1.2.-3'), isNull);
      expect(SemanticVersion.tryParse('1.2.3-beta'), isNull);
      expect(SemanticVersion.tryParse(' 1.2.3'), isNull);
    });

    test('compares by major, then minor, then patch', () {
      expect(
        SemanticVersion.tryParse('2.0.0')!.compareTo(
          const SemanticVersion(1, 9, 9),
        ),
        greaterThan(0),
      );
      expect(
        const SemanticVersion(1, 2, 0) > const SemanticVersion(1, 1, 9),
        isTrue,
      );
      expect(
        const SemanticVersion(1, 2, 0) < const SemanticVersion(1, 2, 1),
        isTrue,
      );
      expect(const SemanticVersion(1, 2, 3) >= const SemanticVersion(1, 2, 3),
          isTrue);
      expect(const SemanticVersion(1, 2, 3) <= const SemanticVersion(1, 2, 3),
          isTrue);
      expect(const SemanticVersion(1, 2, 3), const SemanticVersion(1, 2, 3));
      expect(const SemanticVersion(1, 2, 3).hashCode,
          const SemanticVersion(1, 2, 3).hashCode);
      expect(const SemanticVersion(1, 2, 3),
          isNot(const SemanticVersion(1, 2, 4)));
    });
  });
}
