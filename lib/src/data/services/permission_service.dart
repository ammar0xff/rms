import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/di/app_services.dart';
import '../../domain/models/permissions.dart';

/// Reads the signed-in operator's explicit permission list. Demo mode and
/// unreadable documents fall back to role defaults (never a lockout); the
/// money itself stays behind manager approvals regardless.
Future<bool> userCan(AppServices services, String key) async {
  final user = services.auth.currentUser;
  if (user == null || !services.firebaseReady) return true;
  try {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get(const GetOptions(source: Source.serverAndCache))
        .timeout(const Duration(seconds: 8));
    final data = doc.data();
    if (data == null) return true;
    return Permissions.parse(data['permissions'], user.role).contains(key);
  } catch (_) {
    return true;
  }
}
