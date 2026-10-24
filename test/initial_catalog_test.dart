import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wf_grocery_pos/core/database/app_database.dart';
import 'package:wf_grocery_pos/core/database/initial_catalog_seeder.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('una instalación nueva trae categorías y unidades, y NINGÚN producto', () async {
    await seedInitialCatalogIfEmpty(db);

    expect(await db.select(db.productsTable).get(), isEmpty);
    final categories = await db.select(db.categoriesTable).get();
    expect(categories.map((c) => c.name), containsAll(['Abarrotes', 'Bebidas', 'Gaseosas', 'Farmacia', 'Alcohol y Tabaco']));
    final units = await db.select(db.unitsTable).get();
    expect(units.map((u) => u.abbreviation).toSet(), {'U.', 'paq', 'lb', 'kg', 'L'});
    expect(units.firstWhere((u) => u.abbreviation == 'lb').allowsDecimals, isTrue);
    expect(units.firstWhere((u) => u.abbreviation == 'U.').allowsDecimals, isFalse);
  });

  test('Gaseosas es subcategoría de Bebidas', () async {
    await seedInitialCatalogIfEmpty(db);
    final categories = await db.select(db.categoriesTable).get();
    final bebidas = categories.firstWhere((c) => c.name == 'Bebidas');
    expect(categories.firstWhere((c) => c.name == 'Gaseosas').parentId, bebidas.id);
  });

  test('es idempotente y no pisa datos existentes', () async {
    await seedInitialCatalogIfEmpty(db);
    final before = (await db.select(db.categoriesTable).get()).length;
    await seedInitialCatalogIfEmpty(db);
    expect((await db.select(db.categoriesTable).get()).length, before);

    final other = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(other.close);
    await other.into(other.categoriesTable).insert(CategoriesTableCompanion.insert(name: 'Mía', description: const Value('x')));
    await seedInitialCatalogIfEmpty(other);
    expect((await other.select(other.categoriesTable).get()).map((c) => c.name), ['Mía']);
  });
}
