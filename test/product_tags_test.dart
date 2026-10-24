import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:wf_grocery_pos/core/database/app_database.dart';
import 'package:wf_grocery_pos/core/text/product_tags.dart';
import 'package:wf_grocery_pos/features/categories/data/category_seeder.dart';
import 'package:wf_grocery_pos/features/units/data/unit_seeder.dart';

void main() {
  searchTests();
  group('tags de solo texto', () {
    test('las palabras con números y las letras sueltas no son tags', () {
      expect(buildTags('Coca-Cola Lata 355ml'), 'coca cola lata');
      expect(buildTags('Galleta Oreo 154 g'), 'galleta oreo');
      expect(buildTags('Coca-Cola Botella 2L'), 'coca cola botella');
      expect(buildTags('Arroz Morelos 1kg'), 'arroz morelos');
    });

    test('se conservan acentos normalizados, sin repetir, y las etiquetas extra también son solo texto', () {
      expect(buildTags('Azúcar Estándar', extra: 'dulce azucar 500g'), 'azucar estandar dulce');
    });

    test('isTagWord exige al menos dos letras y ningún número', () {
      expect(isTagWord('oreo'), isTrue);
      expect(isTagWord('ml'), isTrue);
      expect(isTagWord('g'), isFalse);
      expect(isTagWord('355ml'), isFalse);
      expect(isTagWord('2'), isFalse);
    });
  });

  group('migración v14 → v15', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('wf_tags_test');
      dbFile = File(p.join(tempDir.path, 'test.sqlite'));
    });

    tearDown(() => tempDir.delete(recursive: true));

    test('quita de los productos ya guardados los tags con números', () async {
      final seeded = AppDatabase.forTesting(NativeDatabase(dbFile));
      final categories = await seedCategoriesIfEmpty(seeded);
      final units = await seedUnitsIfEmpty(seeded);
      Future<void> insert(String id, String name, String tags) => seeded.into(seeded.productsTable).insert(
            ProductsTableCompanion.insert(
              id: Value(id),
              name: name,
              categoryId: categories.values.first,
              unitId: units.values.first,
              priceCents: 100,
              costCents: 50,
              tags: Value(tags),
            ),
          );
      await insert('a', 'Coca-Cola Lata 355ml', 'coca cola lata 355ml');
      await insert('b', 'Galleta Oreo 154 g', 'galleta oreo 154 g refresco');
      await insert('c', 'Bolillo', 'bolillo');
      await seeded.customStatement('ALTER TABLE sales DROP COLUMN tendered_cents');
      await seeded.customStatement('ALTER TABLE sales DROP COLUMN change_cents');
      await seeded.customStatement('DROP TABLE product_combos');
      await seeded.customStatement('ALTER TABLE products DROP COLUMN base_product_id');
      await seeded.customStatement('ALTER TABLE products DROP COLUMN units_per_pack');
      await seeded.customStatement('ALTER TABLE sale_items DROP COLUMN stock_product_id');
      await seeded.customStatement('ALTER TABLE sale_items DROP COLUMN stock_quantity');
      await seeded.customStatement('DROP TABLE users');
      await seeded.customStatement('DROP TABLE settings');
      await seeded.customStatement('ALTER TABLE cash_sessions DROP COLUMN opened_by');
      await seeded.customStatement('ALTER TABLE cash_sessions DROP COLUMN closed_by');
      await seeded.customStatement('ALTER TABLE cash_movements DROP COLUMN created_by');
      await seeded.customStatement('ALTER TABLE customer_account_movements DROP COLUMN received_by');
      await seeded.customStatement('ALTER TABLE sales DROP COLUMN cashier_name');
      await seeded.customStatement('ALTER TABLE sales DROP COLUMN voided_by');
      await seeded.customStatement('PRAGMA user_version = 14');
      await seeded.close();

      final migrated = AppDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(migrated.close);
      final rows = await migrated.select(migrated.productsTable).get();
      final tagsById = {for (final r in rows) r.id: r.tags};
      expect(tagsById['a'], 'coca cola lata');
      expect(tagsById['b'], 'galleta oreo refresco'); // la etiqueta extra de texto se conserva
      expect(tagsById['c'], 'bolillo');
    });
  });
}

void searchTests() {
  group('buscador de productos', () {
    bool match(String query, String name, {String? tags, String? barcode}) =>
        matchesProductQuery(query, name: name, tags: tags ?? buildTags(name), barcode: barcode);

    test('"pan" no encuentra "Company": solo coincide al comienzo de una palabra', () {
      expect(match('pan', 'Procter & Gamble Company Secret coconut 45 g'), isFalse);
      expect(match('pan', 'Pan de Caja Bimbo Grande'), isTrue);
      expect(match('pan', 'Panadería surtida'), isTrue);
      expect(match('pan', 'Muffin banano canela', tags: 'muffin banano canela pan'), isTrue); // etiqueta extra
    });

    test('no distingue mayúsculas ni acentos y cada palabra puede estar en cualquier orden', () {
      expect(match('AZUCAR', 'Azúcar Estándar 1kg'), isTrue);
      expect(match('cola coca', 'Coca-Cola Lata 355ml'), isTrue);
      expect(match('coca-cola', 'Coca-Cola Lata 355ml'), isTrue);
      expect(match('coca fanta', 'Coca-Cola Lata 355ml'), isFalse); // todas las palabras deben coincidir
    });

    test('los números buscan al comienzo de una palabra del nombre', () {
      expect(match('355', 'Coca-Cola Lata 355ml'), isTrue);
      expect(match('55', 'Coca-Cola Lata 355ml'), isFalse);
    });

    test('si se escriben solo números también busca dentro del código de barras', () {
      expect(match('2133', 'Galleta Oreo', barcode: '7702133009037'), isTrue);
      expect(match('9037', 'Galleta Oreo', barcode: '7702133009037'), isTrue);
      expect(match('oreo', 'Galleta Oreo', barcode: '7702133009037'), isTrue);
      // Texto que no es solo dígitos no se busca dentro del código.
      expect(match('770a', 'Galleta Oreo', barcode: '7702133009037'), isFalse);
    });

    test('sin texto se muestran todos', () {
      expect(match('', 'Cualquier cosa'), isTrue);
      expect(match('   ', 'Cualquier cosa'), isTrue);
      expect(match('--', 'Cualquier cosa'), isTrue);
    });
  });
}
