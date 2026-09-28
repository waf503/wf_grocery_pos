import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'state/cash_provider.dart';
import 'state/customer_provider.dart';
import 'state/inventory_provider.dart';
import 'state/pos_provider.dart';
import 'state/sales_provider.dart';

class GroceryPosApp extends StatelessWidget {
  const GroceryPosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => InventoryProvider()),
        ChangeNotifierProvider(create: (_) => CustomerProvider()),
        ChangeNotifierProvider(create: (_) => SalesProvider()),
        ChangeNotifierProvider(create: (_) => CashProvider()),
        ChangeNotifierProvider(create: (_) => PosProvider()),
      ],
      child: MaterialApp.router(
        title: 'Mi Tienda POS',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        routerConfig: appRouter,
      ),
    );
  }
}
