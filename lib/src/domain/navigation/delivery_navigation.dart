import 'package:url_launcher/url_launcher.dart';

/// Hands turn-by-turn navigation to the phone's own maps app.
///
/// In-app navigation would need a maps SDK, API keys, and billing per
/// platform; every production driver app (Onfleet, Circuit) instead deep
/// links the stop into Google Maps / Apple Maps / Waze, which already handle
/// offline tiles, traffic, and rerouting. The URI builder is pure so the
/// exact link is unit tested; only the launch itself touches the plugin.
Uri deliveryNavigationUri({double? lat, double? lng, required String address}) {
  final destination = (lat != null && lng != null)
      ? '$lat,$lng'
      : address.trim();
  return Uri.parse(
    'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(destination)}',
  );
}

/// Opens [uri] in an external maps app. Returns false when nothing on the
/// device can handle it, so the caller can say so instead of dying silent.
Future<bool> openDeliveryNavigation(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
