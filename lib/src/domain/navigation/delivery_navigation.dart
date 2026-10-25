import 'package:url_launcher/url_launcher.dart';
import 'delivery_geocoding.dart';

/// Hands turn-by-turn navigation to the phone's own maps app.
///
/// In-app navigation links directly into Google Maps / Apple Maps / Waze,
/// which handle offline tiles, real-time traffic, voice guidance, and rerouting.
Uri deliveryNavigationUri({double? lat, double? lng, required String address}) {
  final destination = (lat != null && lng != null)
      ? '$lat,$lng'
      : address.trim();
  return Uri.parse(
    'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(destination)}',
  );
}

/// Builds active Turn-by-Turn GPS Navigation URI for Google Maps.
Uri googleMapsTurnByTurnUri({required GeoCoord coord, required String address}) {
  return Uri.parse(
    'https://www.google.com/maps/dir/?api=1&destination=${coord.lat},${coord.lng}&travelmode=driving',
  );
}

/// Builds active Live Navigation URI for Waze.
Uri wazeNavigationUri({required GeoCoord coord}) {
  return Uri.parse(
    'https://waze.com/ul?ll=${coord.lat},${coord.lng}&navigate=yes',
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
