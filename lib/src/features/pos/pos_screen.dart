import 'package:flutter/material.dart';

import '../common/placeholder_screen.dart';

class PosScreen extends StatelessWidget {
  const PosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'POS',
      subtitle: 'Offline order creation, cached menu and pricing.',
      icon: Icons.point_of_sale,
    );
  }
}
