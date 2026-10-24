import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/database/app_database.dart';
import 'core/router/app_router.dart';
import 'core/security/pin_hasher.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/drift_user_repository.dart';
import 'features/cash/data/drift_cash_repository.dart';
import 'features/catalog/data/drift_catalog_repository.dart';
import 'features/catalog/data/open_facts_client.dart';
import 'features/catalog/data/product_lookup_service.dart';
import 'features/catalog/data/vtex_retail_client.dart';
import 'features/categories/data/drift_category_repository.dart';
import 'features/customers/data/drift_customer_repository.dart';
import 'features/products/data/drift_product_repository.dart';
import 'features/sales/data/drift_sale_repository.dart';
import 'features/settings/data/settings_repository.dart';
import 'features/printing/print_service.dart';
import 'features/units/data/drift_unit_repository.dart';
import 'state/auth_provider.dart';
import 'state/cash_provider.dart';
import 'state/category_provider.dart';
import 'state/customer_provider.dart';
import 'state/inventory_provider.dart';
import 'state/pos_provider.dart';
import 'state/sales_provider.dart';
import 'state/settings_provider.dart';
import 'state/unit_provider.dart';

class GroceryPosApp extends StatefulWidget {
  const GroceryPosApp({
    super.key,
    required this.database,
    this.idleLockAfter = const Duration(minutes: 10),
    this.pinHasher = const PinHasher(),
  });

  final AppDatabase database;

  /// Sin tocar el equipo este tiempo, la sesión se bloquea y pide el PIN otra vez.
  final Duration idleLockAfter;

  /// Costo del hash del PIN (las pruebas lo bajan para ir más rápido).
  final PinHasher pinHasher;

  @override
  State<GroceryPosApp> createState() => _GroceryPosAppState();
}

class _GroceryPosAppState extends State<GroceryPosApp> {
  late final AuthProvider _auth = AuthProvider(DriftUserRepository(widget.database, hasher: widget.pinHasher));
  late final SettingsProvider _settings = SettingsProvider(DriftSettingsRepository(widget.database));
  late final PrintService _printService = PrintService(_settings);
  late final GoRouter _router = createAppRouter(_auth);

  @override
  void initState() {
    super.initState();
    _auth.load();
    _settings.load();
  }

  @override
  void dispose() {
    _router.dispose();
    _auth.dispose();
    _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final database = widget.database;
    return MultiProvider(
      // Los providers respaldados por la base de datos van con `lazy: false`:
      // por defecto Provider los crea hasta la PRIMERA vez que alguien los
      // lee, y su primera lectura de la base de datos es asíncrona. Así, un
      // `context.read<UnitProvider>()` hecho al abrir un diálogo encontraba la
      // lista vacía (el bug de "Falta crear una unidad"). Creados al arrancar,
      // ya tienen sus datos cuando el usuario llega a la pantalla.
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: _auth),
        ChangeNotifierProvider<SettingsProvider>.value(value: _settings),
        Provider<PrintService>.value(value: _printService),
        ChangeNotifierProvider(
          lazy: false,
          create: (_) => CategoryProvider(DriftCategoryRepository(database)),
        ),
        ChangeNotifierProvider(
          lazy: false,
          create: (_) => UnitProvider(DriftUnitRepository(database)),
        ),
        ChangeNotifierProvider(
          lazy: false,
          create: (_) => InventoryProvider(DriftProductRepository(database)),
        ),
        ChangeNotifierProvider(
          lazy: false,
          create: (_) => CustomerProvider(DriftCustomerRepository(database)),
        ),
        ChangeNotifierProvider(
          lazy: false,
          create: (_) => SalesProvider(DriftSaleRepository(database)),
        ),
        ChangeNotifierProvider(
          lazy: false,
          create: (_) => CashProvider(DriftCashRepository(database)),
        ),
        ChangeNotifierProvider(create: (_) => PosProvider()),
        Provider<ProductLookupService>(
          create: (_) => ProductLookupService(
            DriftCatalogRepository(database),
            // Primero las bases abiertas; si no conocen el código, el
            // catálogo de la tienda en línea (que sí tiene productos locales).
            ChainedLookup([OpenFactsClient(), VtexRetailClient()]),
          ),
          dispose: (_, service) => service.dispose(),
        ),
      ],
      child: MaterialApp.router(
        onGenerateTitle: (context) => context.read<SettingsProvider>().businessName,
        debugShowCheckedModeBanner: false,
        // Textos de los componentes de Material (selector de fechas, etc.) en español.
        locale: const Locale('es', 'MX'),
        supportedLocales: const [Locale('es', 'MX'), Locale('es')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: AppTheme.light(),
        routerConfig: _router,
        builder: (context, child) => _IdleLock(after: widget.idleLockAfter, child: child ?? const SizedBox()),
      ),
    );
  }
}

/// Bloquea la sesión tras un rato sin actividad (ratón, toque o teclado): el
/// cajero que se levanta de la caja no deja el sistema abierto. El carrito se
/// conserva, así que no se pierde una venta a medias.
class _IdleLock extends StatefulWidget {
  const _IdleLock({required this.after, required this.child});

  final Duration after;
  final Widget child;

  @override
  State<_IdleLock> createState() => _IdleLockState();
}

class _IdleLockState extends State<_IdleLock> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _restart();
  }

  bool _onKey(KeyEvent event) {
    _restart();
    return false;
  }

  void _restart() {
    _timer?.cancel();
    _timer = Timer(widget.after, () {
      if (mounted) context.read<AuthProvider>().logout();
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _restart(),
      onPointerMove: (_) => _restart(),
      onPointerSignal: (_) => _restart(),
      child: widget.child,
    );
  }
}
