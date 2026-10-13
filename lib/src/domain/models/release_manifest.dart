/// A server-controlled capability switch.
///
/// Flags gate optional workflows; they never override a backend capability
/// check, and the last cached manifest keeps them available while offline.
class FeatureFlag {
  const FeatureFlag({
    required this.key,
    required this.label,
    required this.enabled,
    this.scope = '',
  });

  final String key;
  final String label;
  final bool enabled;
  final String scope;

  Map<String, Object?> toRecord() => {
        'key': key,
        'label': label,
        'enabled': enabled,
        'scope': scope,
      };

  static FeatureFlag fromRecord(Map<String, Object?> record) => FeatureFlag(
        key: record['key'] as String,
        label: record['label'] as String,
        enabled: record['enabled'] as bool? ?? false,
        scope: record['scope'] as String? ?? '',
      );
}

/// The release the device is allowed to run, cached locally so it is available
/// offline. The manifest describes the update channel and rollout, and carries
/// the feature flags the server wants this client to honour.
class ReleaseManifest {
  const ReleaseManifest({
    required this.channel,
    required this.version,
    required this.minSupportedVersion,
    required this.rolloutPercent,
    required this.mandatory,
    required this.publishedAt,
    this.apiContract = '',
    this.flags = const [],
  });

  final String channel;
  final String version;
  final String minSupportedVersion;
  final int rolloutPercent;
  final bool mandatory;
  final DateTime publishedAt;
  final String apiContract;
  final List<FeatureFlag> flags;

  bool isEnabled(String key, {bool fallback = false}) {
    for (final flag in flags) {
      if (flag.key == key) return flag.enabled;
    }
    return fallback;
  }

  Map<String, Object?> toRecord() => {
        'channel': channel,
        'version': version,
        'minSupportedVersion': minSupportedVersion,
        'rolloutPercent': rolloutPercent,
        'mandatory': mandatory,
        'publishedAt': publishedAt.toIso8601String(),
        'apiContract': apiContract,
        'flags': [for (final f in flags) f.toRecord()],
      };

  static ReleaseManifest fromRecord(Map<String, Object?> record) =>
      ReleaseManifest(
        channel: record['channel'] as String,
        version: record['version'] as String,
        minSupportedVersion: record['minSupportedVersion'] as String,
        rolloutPercent: record['rolloutPercent'] as int? ?? 0,
        mandatory: record['mandatory'] as bool? ?? false,
        publishedAt: DateTime.parse(record['publishedAt'] as String),
        apiContract: record['apiContract'] as String? ?? '',
        flags: [
          for (final f in (record['flags'] as List? ?? const []))
            FeatureFlag.fromRecord(Map<String, Object?>.from(f as Map)),
        ],
      );
}
