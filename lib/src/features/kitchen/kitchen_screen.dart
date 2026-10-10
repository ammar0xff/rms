import 'package:flutter/material.dart';

import '../common/placeholder_screen.dart';

class KitchenScreen extends StatelessWidget {
  const KitchenScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'Kitchen',
      subtitle: 'Local ticket queue that survives restarts.',
      icon: Icons.kitchen,
    );
  }
}
