import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';

import 'package:wf_grocery_pos/core/database/app_database.dart';
import 'package:wf_grocery_pos/features/categories/data/category_seeder.dart';
import 'package:wf_grocery_pos/features/products/data/drift_product_repository.dart';
import 'package:wf_grocery_pos/features/units/data/unit_seeder.dart';
import 'package:wf_grocery_pos/models/product.dart';
import 'package:wf_grocery_pos/models/product_combo.dart';
import 'package:wf_grocery_pos/shared/widgets/product_thumbnail.dart';
import 'package:wf_grocery_pos/state/inventory_provider.dart';

Uint8List _png(int shade) {
  final image = img.Image(width: 32, height: 32);
  for (final pixel in image) {
    pixel
      ..r = shade
      ..g = shade
      ..b = shade;
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  late AppDatabase db;
  late DriftProductRepository repo;
  late InventoryProvider provider;
  late String baseId;

  final dark = _png(40);
  final light = _png(220);

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 250));

  Product byName(String name) => provider.products.firstWhere((p) => p.name == name);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final categories = await seedCategoriesIfEmpty(db);
    final units = await seedUnitsIfEmpty(db);
    repo = DriftProductRepository(db);
    provider = InventoryProvider(repo);

    // El producto base tiene miniatura; las presentaciones NO tienen la suya.
    baseId = await repo.add(
      ProductsTableCompanion.insert(
        name: 'Cigarro suelto',
        categoryId: categories.values.first,
        unitId: units['Pieza']!,
        priceCents: 10,
        costCents: 6,
        stock: const Value(100),
      ),
      image: dark,
    );
    await repo.savePresentations(baseId, const [
      PresentationDraft(name: 'Cajetilla de 20', unitsPerPack: 20, priceCents: 175),
      PresentationDraft(name: 'Paquete de 20 cajetillas', unitsPerPack: 400, priceCents: 3000),
    ]);
    await settle();
  });

  tearDown(() async {
    provider.dispose();
    await db.close();
  });

  test('las presentaciones muestran la miniatura del producto base', () async {
    final box = byName('Cajetilla de 20');
    final carton = byName('Paquete de 20 cajetillas');

    expect(box.hasImage, isTrue);
    expect(carton.hasImage, isTrue);
    expect(box.imageSourceId, baseId);
    expect(byName('Cigarro suelto').imageSourceId, isNull); // el base usa la suya

    expect(await provider.imageFor(box), dark);
    expect(await provider.imageFor(carton), dark);
    expect(await provider.imageFor(byName('Cigarro suelto')), dark);
    // No se copió: solo existe UNA fila de imagen, la del base.
    expect(await db.select(db.productImagesTable).get(), hasLength(1));
  });

  test('al cambiar la miniatura del base, todas las presentaciones la ven actualizada', () async {
    expect(await provider.imageFor(byName('Cajetilla de 20')), dark); // queda en la caché

    final base = byName('Cigarro suelto');
    await provider.updateProduct(
      id: baseId,
      name: base.name,
      categoryId: base.categoryId,
      unitId: base.unitId,
      priceCents: base.priceCents,
      costCents: base.costCents,
      stock: base.stock,
      minStock: base.minStock,
      image: light,
    );
    await settle();

    expect(await provider.imageFor(byName('Cajetilla de 20')), light);
    expect(await provider.imageFor(byName('Paquete de 20 cajetillas')), light);
  });

  test('al quitar la miniatura del base, las presentaciones se quedan sin imagen', () async {
    final base = byName('Cigarro suelto');
    await provider.updateProduct(
      id: baseId,
      name: base.name,
      categoryId: base.categoryId,
      unitId: base.unitId,
      priceCents: base.priceCents,
      costCents: base.costCents,
      stock: base.stock,
      minStock: base.minStock,
      removeImage: true,
    );
    await settle();

    expect(byName('Cajetilla de 20').hasImage, isFalse);
    expect(await provider.imageFor(byName('Cajetilla de 20')), isNull);
  });

  test('una presentación nueva hereda la miniatura sin hacer nada', () async {
    await repo.savePresentations(baseId, const [
      PresentationDraft(name: 'Media cajetilla', unitsPerPack: 10, priceCents: 90),
    ]);
    await settle();

    final half = byName('Media cajetilla');
    expect(half.hasImage, isTrue);
    expect(await provider.imageFor(half), dark);
  });

  test('un producto base sin imagen deja a sus presentaciones sin imagen', () async {
    await repo.update(ProductsTableCompanion(id: Value(baseId)), removeImage: true);
    await repo.savePresentations(baseId, const [
      PresentationDraft(name: 'Docena', unitsPerPack: 12, priceCents: 100),
    ]);
    await settle();
    expect(byName('Docena').hasImage, isFalse);
  });

  testWidgets('la tarjeta y la tabla dibujan la miniatura de la presentación', (tester) async {
    await tester.runAsync(settle);
    final box = byName('Cajetilla de 20');

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<InventoryProvider>.value(
          value: provider,
          child: Scaffold(body: Center(child: ProductThumbnail(product: box, size: 56))),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();

    // Con imagen se dibuja una foto (Image); sin ella, el ícono de reemplazo.
    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.inventory_2_outlined), findsNothing);
  });
}
