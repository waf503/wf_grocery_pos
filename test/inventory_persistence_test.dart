import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:wf_grocery_pos/core/database/app_database.dart';
import 'package:wf_grocery_pos/features/categories/data/category_seeder.dart';
import 'package:wf_grocery_pos/features/products/data/drift_product_repository.dart';
import 'package:wf_grocery_pos/features/products/data/product_seeder.dart';

void main() {
  test('una variante nueva sobrevive a cerrar y volver a abrir la app', () async {
    final tempDir = await Directory.systemTemp.createTemp('wf_grocery_pos_test');
    final dbFile = File(p.join(tempDir.path, 'test.sqlite'));
    addTearDown(() => tempDir.delete(recursive: true));

    // 1. "Primera sesión de la app": abre la base, siembra categorías y
    //    catálogo, crea una familia + variante nueva, y cierra la conexión
    //    (simula cerrar la app).
    final firstSession = AppDatabase.forTesting(NativeDatabase(dbFile));
    final categoryIds = await seedCategoriesIfEmpty(firstSession);
    await seedProductsIfEmpty(firstSession, categoryIds);
    final repository = DriftProductRepository(firstSession);

    final family = await repository.findOrCreateFamily(
      name: 'Chocolate Abuelita',
      categoryId: categoryIds['Abarrotes']!,
    );
    await repository.addVariant(
      family.id,
      ProductVariantsTableCompanion.insert(
        productId: family.id,
        presentation: 'Tableta 90g',
        unit: 'pieza',
        price: 35.0,
        cost: 27.0,
      ),
    );
    await firstSession.close();

    // 2. "Segunda sesión": abre el MISMO archivo desde cero, como si la app
    //    se hubiera reiniciado por completo (o se hubiera ido la luz).
    final secondSession = AppDatabase.forTesting(NativeDatabase(dbFile));
    final secondRepository = DriftProductRepository(secondSession);

    final families = await secondSession.select(secondSession.productsTable).get();
    final variants = await secondSession.select(secondSession.productVariantsTable).get();
    final categories = await secondSession.select(secondSession.categoriesTable).get();
    expect(families.any((row) => row.name == 'Chocolate Abuelita'), isTrue);
    expect(variants.any((row) => row.presentation == 'Tableta 90g'), isTrue);
    expect(categories.any((row) => row.name == 'Gaseosas' && row.parentId != null), isTrue);

    // Volver a pedir la misma familia por nombre NO debe crear un
    // duplicado — prueba que `findOrCreateFamily` reutiliza correctamente
    // una familia creada en una sesión anterior.
    final sameFamily = await secondRepository.findOrCreateFamily(
      name: 'Chocolate Abuelita',
      categoryId: categoryIds['Abarrotes']!,
    );
    final familiesAfter = await secondSession.select(secondSession.productsTable).get();
    await secondSession.close();

    expect(sameFamily.id, family.id);
    expect(familiesAfter.where((row) => row.name == 'Chocolate Abuelita').length, 1);
  });
}
