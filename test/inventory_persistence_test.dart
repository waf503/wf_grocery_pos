import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:wf_grocery_pos/core/database/app_database.dart';
import 'package:wf_grocery_pos/core/text/product_tags.dart';
import 'package:wf_grocery_pos/features/categories/data/category_seeder.dart';
import 'package:wf_grocery_pos/features/products/data/drift_product_repository.dart';
import 'package:wf_grocery_pos/features/products/data/product_seeder.dart';
import 'package:wf_grocery_pos/features/units/data/drift_unit_repository.dart';
import 'package:wf_grocery_pos/features/units/data/unit_repository.dart';
import 'package:wf_grocery_pos/features/units/data/unit_seeder.dart';
import 'package:wf_grocery_pos/state/inventory_provider.dart';

void main() {
  test('un producto nuevo sobrevive a cerrar y volver a abrir la app', () async {
    final tempDir = await Directory.systemTemp.createTemp('wf_grocery_pos_test');
    final dbFile = File(p.join(tempDir.path, 'test.sqlite'));
    addTearDown(() => tempDir.delete(recursive: true));

    // 1. "Primera sesión de la app": abre la base, siembra categorías,
    //    unidades y catálogo, crea un producto nuevo, y cierra la conexión
    //    (simula cerrar la app).
    final firstSession = AppDatabase.forTesting(NativeDatabase(dbFile));
    final categoryIds = await seedCategoriesIfEmpty(firstSession);
    final unitIds = await seedUnitsIfEmpty(firstSession);
    await seedProductsIfEmpty(firstSession, categoryIds, unitIds);
    final repository = DriftProductRepository(firstSession);

    await repository.add(
      ProductsTableCompanion.insert(
        name: 'Chocolate Abuelita Tableta 90g',
        categoryId: categoryIds['Abarrotes']!,
        unitId: unitIds['Pieza']!,
        priceCents: 3500,
        costCents: 2700,
        tags: Value(buildTags('Chocolate Abuelita Tableta 90g')),
      ),
    );
    await firstSession.close();

    // 2. "Segunda sesión": abre el MISMO archivo desde cero, como si la app
    //    se hubiera reiniciado por completo (o se hubiera ido la luz).
    final secondSession = AppDatabase.forTesting(NativeDatabase(dbFile));
    final products = await secondSession.select(secondSession.productsTable).get();
    final categories = await secondSession.select(secondSession.categoriesTable).get();
    final units = await secondSession.select(secondSession.unitsTable).get();
    await secondSession.close();

    expect(products.any((row) => row.name == 'Chocolate Abuelita Tableta 90g'), isTrue);
    expect(categories.any((row) => row.name == 'Gaseosas' && row.parentId != null), isTrue);
    expect(units.map((u) => u.name), containsAll(['Pieza', 'Kilogramo', 'Libra', 'Litro', 'Paquete']));
  });

  test('las sugerencias salen de los tags y desaparecen al borrar el producto', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final categoryIds = await seedCategoriesIfEmpty(db);
    final unitIds = await seedUnitsIfEmpty(db);
    final repository = DriftProductRepository(db);

    await repository.add(
      ProductsTableCompanion.insert(
        name: 'Coca-Cola Lata 355ml',
        categoryId: categoryIds['Gaseosas']!,
        unitId: unitIds['Pieza']!,
        priceCents: 1200,
        costCents: 800,
        tags: Value(buildTags('Coca-Cola Lata 355ml', extra: 'refresco')),
      ),
    );

    final inventory = InventoryProvider(repository);
    addTearDown(inventory.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(inventory.suggestionsFor('coca').map((p) => p.name), ['Coca-Cola Lata 355ml']);
    expect(inventory.suggestionsFor('COCA lat').length, 1);
    expect(inventory.suggestionsFor('refre').length, 1);
    expect(inventory.suggestionsFor('pepsi'), isEmpty);
    expect(inventory.products.single.unit, 'pz');
    expect(inventory.products.single.allowsDecimals, isFalse);

    await inventory.deleteProduct(inventory.products.single.id);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(inventory.suggestionsFor('coca'), isEmpty);
  });

  test('una unidad en uso no se puede borrar; una libre sí', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final categoryIds = await seedCategoriesIfEmpty(db);
    final unitIds = await seedUnitsIfEmpty(db);
    await seedProductsIfEmpty(db, categoryIds, unitIds);
    final units = DriftUnitRepository(db);

    final inUse = await units.delete(unitIds['Pieza']!);
    expect(inUse.error, DeleteUnitError.hasProducts);

    final free = await units.delete(unitIds['Libra']!);
    expect(free.isSuccess, isTrue);
  });
}
