/// A three-part semantic version (`major.minor.patch`) with strict parsing.
///
/// Release manifests carry versions as free-form strings coming from the
/// backend, so they are parsed defensively: anything that is not exactly three
/// non-negative integer parts is rejected rather than guessed at. Comparing
/// through [compareTo] keeps version ordering consistent no matter which
/// platform evaluates the manifest.
class SemanticVersion implements Comparable<SemanticVersion> {
  const SemanticVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  /// Parses `major.minor.patch`, or returns null when [value] is malformed.
  ///
  /// Pre-release or build metadata suffixes are intentionally unsupported: the
  /// update control plane only ever publishes plain numeric versions.
  static SemanticVersion? tryParse(String? value) {
    if (value == null) return null;
    final parts = value.split('.');
    if (parts.length != 3) return null;
    final numbers = <int>[];
    for (final part in parts) {
      if (part.isEmpty) return null;
      final number = int.tryParse(part);
      if (number == null || number < 0) return null;
      numbers.add(number);
    }
    return SemanticVersion(numbers[0], numbers[1], numbers[2]);
  }

  @override
  int compareTo(SemanticVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator >(SemanticVersion other) => compareTo(other) > 0;

  bool operator <(SemanticVersion other) => compareTo(other) < 0;

  bool operator >=(SemanticVersion other) => compareTo(other) >= 0;

  bool operator <=(SemanticVersion other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) =>
      other is SemanticVersion &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}
