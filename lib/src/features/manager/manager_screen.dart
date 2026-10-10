import 'package:flutter/material.dart';

import '../common/placeholder_screen.dart';

class ManagerScreen extends StatelessWidget {
  const ManagerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'Manager',
      subtitle: 'Sync diagnostics, conflicts and version visibility.',
      icon: Icons.manage_accounts,
    );
  }
}
