import 'package:flutter/material.dart';

import '../common/placeholder_screen.dart';

class DeliveryScreen extends StatelessWidget {
  const DeliveryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'Delivery',
      subtitle: 'Cached assignments and queued driver events.',
      icon: Icons.delivery_dining,
    );
  }
}
