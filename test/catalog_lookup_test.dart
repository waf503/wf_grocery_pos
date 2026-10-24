import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import 'package:wf_grocery_pos/core/database/app_database.dart';
import 'package:wf_grocery_pos/core/text/product_tags.dart';
import 'package:wf_grocery_pos/features/catalog/catalog_item.dart';
import 'package:wf_grocery_pos/features/catalog/data/drift_catalog_repository.dart';
import 'package:wf_grocery_pos/features/catalog/data/open_facts_client.dart';
import 'package:wf_grocery_pos/features/catalog/data/product_lookup_service.dart';
import 'package:wf_grocery_pos/features/categories/data/category_seeder.dart';
import 'package:wf_grocery_pos/features/products/data/drift_product_repository.dart';
import 'package:wf_grocery_pos/features/units/data/unit_seeder.dart';
import 'package:drift/drift.dart' show Value;

final _png = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3, 4]);

/// Respuesta de Open Facts para un producto encontrado.
http.Response _found(Map<String, Object?> product) =>
    http.Response(jsonEncode({'status': 1, 'product': product}), 200, headers: {'content-type': 'application/json'});

http.Response _notFound() =>
    http.Response(jsonEncode({'status': 0, 'status_verbose': 'product not found'}), 404);

http.Response _image(List<int> bytes) =>
    http.Response.bytes(bytes, 200, headers: {'content-type': 'image/jpeg'});

void main() {
  group('nombre sugerido', () {
    test('arma marca + nombre + presentación sin repetir lo que ya trae', () {
      expect(
        const CatalogItem(source: 's', name: 'Champoings', brand: 'Pantene', quantity: '275 ml').suggestedName,
        'Pantene Champoings 275 ml',
      );
      // La marca ya está en el nombre ("Coca-Cola ..."): no se antepone.
      expect(
        const CatalogItem(
          source: 's',
          name: 'Coca-Cola Original',
          brand: 'COCA-COLA SERVICES SA/NV',
          quantity: '330 ml',
        ).suggestedName,
        'Coca-Cola Original 330 ml',
      );
      // La presentación ya está en el nombre.
      expect(
        const CatalogItem(source: 's', name: 'Jalapeños 150g', brand: 'Diana', quantity: '150 g').suggestedName,
        'Diana Jalapeños 150g',
      );
    });

    test('convierte nombres en MAYÚSCULAS a formato de título y usa la marca si falta el nombre', () {
      expect(const CatalogItem(source: 's', name: 'JABON PARA TRASTES').suggestedName, 'Jabon Para Trastes');
      expect(const CatalogItem(source: 's', name: 'Pantene', brand: 'Pantene', quantity: '90 ml').suggestedName,
          'Pantene 90 ml');
    });
  });

  test('los tags salen solo del título: ni la categoría ni la marca en inglés se agregan', () {
    const oreo = CatalogItem(
      source: 'Open Food Facts',
      name: 'Galleta Oreo',
      brand: 'Oreo',
      categoryHint: 'Biscuits',
      quantity: '154 g',
    );
    final tags = buildTags(oreo.suggestedName).split(' ');
    expect(tags, ['galleta', 'oreo']); // sin la categoría ni números ni letras sueltas
  });

  group('cliente Open Facts', () {
    test('consulta las tres bases y prefiere la primera que conozca el código', () async {
      final hosts = <String>[];
      final client = OpenFactsClient(
        client: MockClient((request) async {
          hosts.add(request.url.host);
          if (request.url.host == 'images.openbeautyfacts.org') return _image(_png);
          if (request.url.host == 'world.openbeautyfacts.org') {
            return _found({
              'product_name': 'Champoings',
              'brands': 'Pantene, P&G',
              'quantity': '275 ml',
              'categories': 'Shampoos, Hair care',
              'image_front_small_url': 'https://images.openbeautyfacts.org/images/x.jpg',
            });
          }
          return _notFound();
        }),
      );

      final result = await client.fetch('8001090151780');

      expect(hosts.toSet(), containsAll(['world.openfoodfacts.org', 'world.openbeautyfacts.org', 'world.openproductsfacts.org']));
      final item = result.item!;
      expect(item.source, 'Open Beauty Facts');
      expect(item.name, 'Champoings');
      expect(item.brand, 'Pantene'); // solo la primera marca
      expect(item.quantity, '275 ml');
      expect(item.categoryHint, 'Shampoos');
      expect(item.barcode, '8001090151780');
      expect(item.imageBytes, _png);
      expect(result.offline, isFalse);
    });

    test('prefiere el nombre en español y descarta resultados sin nombre ni marca', () async {
      final client = OpenFactsClient(
        client: MockClient((request) async {
          if (request.url.host == 'world.openfoodfacts.org') {
            return _found({'product_name': 'Cola', 'product_name_es': 'Refresco de cola'});
          }
          return _found({'product_name': '', 'brands': ''}); // las otras bases: vacío
        }),
      );
      final result = await client.fetch('5449000000996');
      expect(result.item!.name, 'Refresco de cola');

      final empty = OpenFactsClient(client: MockClient((_) async => _found({'product_name': ' '})));
      final none = await empty.fetch('5449000000996');
      expect(none.item, isNull);
      expect(none.offline, isFalse);
    });

    test('código desconocido: sin resultado y sin marcar falta de internet', () async {
      final client = OpenFactsClient(client: MockClient((_) async => _notFound()));
      final result = await client.fetch('7410000000000');
      expect(result.item, isNull);
      expect(result.offline, isFalse);
    });

    test('sin internet (todas las fuentes fallan) se marca offline', () async {
      final client = OpenFactsClient(
        client: MockClient((_) async => throw const SocketException('sin red')),
      );
      final result = await client.fetch('5449000000996');
      expect(result.item, isNull);
      expect(result.offline, isTrue);
    });

    test('la imagen se descarta si es demasiado grande o no es una imagen, pero el producto se sugiere', () async {
      http.Response imageResponse = _image(List.filled(500 * 1024, 1));
      final client = OpenFactsClient(
        client: MockClient((request) async {
          if (request.url.host == 'images.openfoodfacts.org') return imageResponse;
          if (request.url.host == 'world.openfoodfacts.org') {
            return _found({'product_name': 'Cola', 'image_small_url': 'https://images.openfoodfacts.org/a.jpg'});
          }
          return _notFound();
        }),
      );

      var result = await client.fetch('5449000000996');
      expect(result.item!.name, 'Cola');
      expect(result.item!.imageBytes, isNull); // más de 400 KB

      imageResponse = http.Response('<html>', 200, headers: {'content-type': 'text/html'});
      result = await client.fetch('5449000000996');
      expect(result.item!.imageBytes, isNull); // no es imagen
    });
  });

  group('servicio de búsqueda por código', () {
    late AppDatabase db;
    late DriftCatalogRepository local;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      local = DriftCatalogRepository(db);
    });

    tearDown(() => db.close());

    test('solo consulta códigos comerciales, no los internos de la tienda', () {
      expect(ProductLookupService.isLookupable('5449000000996'), isTrue);
      expect(ProductLookupService.isLookupable('01234567'), isTrue); // EAN-8
      expect(ProductLookupService.isLookupable('2000000000017'), isFalse); // interno (prefijo 200)
      expect(ProductLookupService.isLookupable('123'), isFalse);
      expect(ProductLookupService.isLookupable('abc12345678'), isFalse);
      expect(ProductLookupService.isLookupable('../etc'), isFalse);
    });

    test('lo encontrado en internet se guarda y la segunda vez no consulta de nuevo', () async {
      final remote = _FakeRemote(
        const LookupResult(item: CatalogItem(source: 'Open Beauty Facts', name: 'Champú', brand: 'Pantene')),
      );
      final service = ProductLookupService(local, remote);

      final first = await service.lookup('8001090151780');
      expect(first.item!.name, 'Champú');
      expect(first.fromCache, isFalse);
      expect(remote.calls, 1);

      final second = await service.lookup('8001090151780');
      expect(second.item!.name, 'Champú');
      expect(second.item!.barcode, '8001090151780');
      expect(second.fromCache, isTrue);
      expect(remote.calls, 1); // no volvió a internet
    });

    test('lo no encontrado no se guarda (puede aparecer después) y los códigos internos no salen a internet', () async {
      final remote = _FakeRemote(const LookupResult());
      final service = ProductLookupService(local, remote);

      expect((await service.lookup('7410000000000')).item, isNull);
      expect((await service.lookup('7410000000000')).item, isNull);
      expect(remote.calls, 2); // se reintenta

      await service.lookup('2000000000017');
      expect(remote.calls, 2); // código interno: no se consulta
    });

    test('con el mismo código solo hay una fila en el catálogo (se reemplaza)', () async {
      await local.save(const CatalogItem(source: 'a', name: 'Viejo', barcode: '5449000000996'));
      await local.save(const CatalogItem(source: 'b', name: 'Nuevo', barcode: '5449000000996', imageBytes: null));
      final rows = await db.select(db.catalogItemsTable).get();
      expect(rows, hasLength(1));
      expect((await local.findByBarcode('5449000000996'))!.name, 'Nuevo');
    });

    test('la miniatura descargada se guarda para verla sin internet', () async {
      await local.save(CatalogItem(source: 'a', name: 'Cola', barcode: '5449000000996', imageBytes: _png));
      expect((await local.findByBarcode('5449000000996'))!.imageBytes, _png);
    });
  });

  group('miniatura del producto', () {
    late AppDatabase db;
    late DriftProductRepository products;
    late String categoryId;
    late String unitId;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      final categories = await seedCategoriesIfEmpty(db);
      final units = await seedUnitsIfEmpty(db);
      categoryId = categories.values.first;
      unitId = units.values.first;
      products = DriftProductRepository(db);
    });

    tearDown(() => db.close());

    ProductsTableCompanion product(String id) => ProductsTableCompanion.insert(
          id: Value(id),
          name: 'Champú Pantene 275 ml',
          categoryId: categoryId,
          unitId: unitId,
          priceCents: 500,
          costCents: 300,
        );

    test('se guarda con el producto, se reemplaza y se quita', () async {
      await products.add(product('p1'), image: _png);
      var saved = (await products.getById('p1'))!;
      expect(saved.hasImage, isTrue);
      expect(await products.getImage('p1'), _png);

      final other = Uint8List.fromList([9, 9, 9]);
      await products.update(ProductsTableCompanion(id: const Value('p1')), image: other);
      expect(await products.getImage('p1'), other);

      // Editar sin tocar la imagen la conserva.
      await products.update(ProductsTableCompanion(id: const Value('p1'), stock: const Value(3)));
      expect(await products.getImage('p1'), other);
      expect((await products.getById('p1'))!.hasImage, isTrue);

      await products.update(ProductsTableCompanion(id: const Value('p1')), removeImage: true);
      saved = (await products.getById('p1'))!;
      expect(saved.hasImage, isFalse);
      expect(await products.getImage('p1'), isNull);
    });

    test('un producto sin imagen no guarda fila y al borrarlo se borra su imagen', () async {
      await products.add(product('p0'));
      expect((await products.getById('p0'))!.hasImage, isFalse);
      expect(await db.select(db.productImagesTable).get(), isEmpty);

      await products.add(product('p1'), image: _png);
      expect(await db.select(db.productImagesTable).get(), hasLength(1));
      await products.delete('p1');
      expect(await db.select(db.productImagesTable).get(), isEmpty);
    });
  });

  group('migración v13 → v14', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('wf_lookup_test');
      dbFile = File(p.join(tempDir.path, 'test.sqlite'));
    });

    tearDown(() => tempDir.delete(recursive: true));

    test('conserva los productos y agrega imágenes y catálogo', () async {
      final seeded = AppDatabase.forTesting(NativeDatabase(dbFile));
      final categories = await seedCategoriesIfEmpty(seeded);
      final units = await seedUnitsIfEmpty(seeded);
      await seeded.into(seeded.productsTable).insert(
            ProductsTableCompanion.insert(
              name: 'Bolillo',
              categoryId: categories.values.first,
              unitId: units.values.first,
              priceCents: 300,
              costCents: 150,
            ),
          );
      await seeded.customStatement('DROP TABLE product_images');
      await seeded.customStatement('DROP TABLE catalog_items');
      await seeded.customStatement('ALTER TABLE products DROP COLUMN has_image');
      await seeded.customStatement('ALTER TABLE sales DROP COLUMN tendered_cents');
      await seeded.customStatement('ALTER TABLE sales DROP COLUMN change_cents');
      await seeded.customStatement('DROP TABLE product_combos');
      await seeded.customStatement('ALTER TABLE products DROP COLUMN base_product_id');
      await seeded.customStatement('ALTER TABLE products DROP COLUMN units_per_pack');
      await seeded.customStatement('ALTER TABLE sale_items DROP COLUMN stock_product_id');
      await seeded.customStatement('ALTER TABLE sale_items DROP COLUMN stock_quantity');
      await seeded.customStatement('PRAGMA user_version = 13');
      await seeded.close();

      final migrated = AppDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(migrated.close);
      final repo = DriftProductRepository(migrated);
      final list = await repo.watchAll().first;
      expect(list.single.name, 'Bolillo');
      expect(list.single.hasImage, isFalse);

      await repo.update(ProductsTableCompanion(id: Value(list.single.id)), image: _png);
      expect(await repo.getImage(list.single.id), _png);
      await DriftCatalogRepository(migrated)
          .save(const CatalogItem(source: 'x', name: 'Cola', barcode: '5449000000996'));
      expect(await DriftCatalogRepository(migrated).findByBarcode('5449000000996'), isNotNull);
    });
  });
}

class _FakeRemote implements RemoteLookup {
  _FakeRemote(this.result);

  final LookupResult result;
  int calls = 0;

  @override
  Future<LookupResult> fetch(String barcode) async {
    calls++;
    return result;
  }

  @override
  void close() {}
}
