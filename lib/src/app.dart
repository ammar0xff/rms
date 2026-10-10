import 'package:flutter/material.dart';

import 'features/accounting/accounting_screen.dart';
import 'features/delivery/delivery_screen.dart';
import 'features/kitchen/kitchen_screen.dart';
import 'features/manager/manager_screen.dart';
import 'features/pos/pos_screen.dart';

class RmsApp extends StatelessWidget {
  const RmsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Restaurant Management System',
      theme: ThemeData(colorSchemeSeed: Colors.deepOrange, useMaterial3: true),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _screens = <Widget>[
    PosScreen(),
    KitchenScreen(),
    DeliveryScreen(),
    ManagerScreen(),
    AccountingScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.point_of_sale), label: 'POS'),
          NavigationDestination(icon: Icon(Icons.kitchen), label: 'Kitchen'),
          NavigationDestination(icon: Icon(Icons.delivery_dining), label: 'Delivery'),
          NavigationDestination(icon: Icon(Icons.manage_accounts), label: 'Manager'),
          NavigationDestination(icon: Icon(Icons.receipt_long), label: 'Accounting'),
        ],
      ),
    );
  }
}
