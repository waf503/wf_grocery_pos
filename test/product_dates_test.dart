import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wf_grocery_pos/core/database/app_database.dart';
import 'package:wf_grocery_pos/features/categories/data/category_seeder.dart';
import 'package:wf_grocery_pos/features/products/data/drift_product_repository.dart';
import 'package:wf_grocery_pos/features/products/data/product_seeder.dart';
import 'package:wf_grocery_pos/features/units/data/unit_seeder.dart';

void main() {
  test('un producto sin editar muestra su fecha de creación; al editarlo se actualiza', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final categoryIds = await seedCategoriesIfEmpty(db);
    final unitIds = await seedUnitsIfEmpty(db);
    await seedProductsIfEmpty(db, categoryIds, unitIds);
    final repository = DriftProductRepository(db);

    final before = (await repository.watchAll().first).first;
    expect(before.updatedAt, before.createdAt);

    await repository.update(ProductsTableCompanion(id: Value(before.id), stock: const Value(99)));

    final after = await repository.getById(before.id);
    expect(after!.stock, 99);
    expect(after.createdAt, before.createdAt);
    expect(after.updatedAt.isAfter(before.createdAt) || after.updatedAt == before.createdAt, isTrue);
    final raw = await (db.select(db.productsTable)..where((row) => row.id.equals(before.id))).getSingle();
    expect(raw.updatedAt, isNotNull);
  });
}
