import 'package:flutter/material.dart';

import '../common/placeholder_screen.dart';

class AccountingScreen extends StatelessWidget {
  const AccountingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'Accounting',
      subtitle: 'Cash sessions, settlements and auditable records.',
      icon: Icons.receipt_long,
    );
  }
}
