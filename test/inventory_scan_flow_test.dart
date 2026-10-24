import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:wf_grocery_pos/core/database/app_database.dart';
import 'package:wf_grocery_pos/features/catalog/catalog_item.dart';
import 'package:wf_grocery_pos/features/catalog/data/drift_catalog_repository.dart';
import 'package:wf_grocery_pos/features/catalog/data/open_facts_client.dart';
import 'package:wf_grocery_pos/features/catalog/data/product_lookup_service.dart';
import 'package:wf_grocery_pos/features/categories/data/category_seeder.dart';
import 'package:wf_grocery_pos/features/categories/data/drift_category_repository.dart';
import 'package:wf_grocery_pos/features/inventory/inventory_screen.dart';
import 'package:wf_grocery_pos/features/products/data/drift_product_repository.dart';
import 'package:wf_grocery_pos/features/units/data/drift_unit_repository.dart';
import 'package:wf_grocery_pos/features/units/data/unit_seeder.dart';
import 'package:wf_grocery_pos/state/category_provider.dart';
import 'package:wf_grocery_pos/state/inventory_provider.dart';
import 'package:wf_grocery_pos/state/unit_provider.dart';

class _Remote implements RemoteLookup {
  _Remote(this.result);

  final LookupResult result;

  @override
  Future<LookupResult> fetch(String barcode) async {
    return result;
  }

  @override
  void close() {}
}

/// El título del formulario de producto (el botón de la pantalla también dice
/// "Nuevo producto", por eso se busca dentro del cuadro de diálogo).
Finder get _formTitle =>
    find.descendant(of: find.byType(AlertDialog), matching: find.text('Nuevo producto'));

/// Un campo de texto cuyo contenido es exactamente [text].
Finder _fieldWithText(String text) =>
    find.byWidgetPredicate((w) => w is EditableText && w.controller.text == text);

/// Deja correr el trabajo real (base de datos, Futures) que `pump` no avanza.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Desmonta la pantalla y deja terminar los temporizadores que Drift usa al
/// cerrar sus flujos de datos (si no, la prueba falla por "Timer pendiente").
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _scan(WidgetTester tester, LookupResult result) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  await tester.runAsync(() async {
    await seedCategoriesIfEmpty(db);
    await seedUnitsIfEmpty(db);
  });

  await tester.binding.setSurfaceSize(const Size(1400, 1000));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(lazy: false, create: (_) => CategoryProvider(DriftCategoryRepository(db))),
        ChangeNotifierProvider(lazy: false, create: (_) => UnitProvider(DriftUnitRepository(db))),
        ChangeNotifierProvider(lazy: false, create: (_) => InventoryProvider(DriftProductRepository(db))),
        Provider<ProductLookupService>(
          create: (_) => ProductLookupService(DriftCatalogRepository(db), _Remote(result)),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: InventoryScreen())),
    ),
  );
  await _settle(tester);

  // El lector de códigos "teclea" el código y envía Enter.
  await tester.enterText(find.byType(TextField).first, '4006000180205');
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await _settle(tester);
}

void main() {
  testWidgets('escanear un código nuevo con información abre el formulario con los datos sugeridos', (tester) async {
    await _scan(
      tester,
      const LookupResult(
        item: CatalogItem(
          source: 'Walmart El Salvador',
          name: 'Desodorante Nivea Derma Control tono uniforme roll on femenino - 50 ml',
          brand: 'NIVEA',
        ),
      ),
    );

    expect(_formTitle, findsOneWidget);
    expect(find.textContaining('Datos sugeridos de Walmart El Salvador'), findsOneWidget);
    expect(find.textContaining('Desodorante Nivea Derma Control'), findsWidgets);
    // El código escaneado queda en el campo de código de barras.
    expect(_fieldWithText('4006000180205'), findsOneWidget);
    await _teardown(tester);
  });

  testWidgets('escanear un código sin información igual abre el formulario con el código puesto', (tester) async {
    await _scan(tester, const LookupResult());

    expect(_formTitle, findsOneWidget);
    expect(_fieldWithText('4006000180205'), findsOneWidget);
    await _teardown(tester);
  });

  testWidgets('sin internet igual se puede registrar el producto', (tester) async {
    await _scan(tester, const LookupResult(offline: true));

    expect(_formTitle, findsOneWidget);
    expect(_fieldWithText('4006000180205'), findsOneWidget);
    await _teardown(tester);
  });
}
