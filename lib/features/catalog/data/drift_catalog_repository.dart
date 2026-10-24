import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../catalog_item.dart';
import 'catalog_repository.dart';

class DriftCatalogRepository implements CatalogRepository {
  DriftCatalogRepository(this._db, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  @override
  Future<CatalogItem?> findByBarcode(String barcode) async {
    final row = await (_db.select(_db.catalogItemsTable)..where((r) => r.barcode.equals(barcode)))
        .getSingleOrNull();
    if (row == null) return null;
    return CatalogItem(
      source: row.source,
      name: row.name,
      barcode: row.barcode,
      brand: row.brand,
      quantity: row.quantity,
      categoryHint: row.categoryHint,
      description: row.description,
      imageUrl: row.imageUrl,
      imageBytes: row.imageBytes,
    );
  }

  @override
  Future<void> save(CatalogItem item) {
    return _db.transaction(() async {
      // El código de barras es único: reemplazar lo que hubiera de antes.
      if (item.barcode != null) {
        await (_db.delete(_db.catalogItemsTable)..where((r) => r.barcode.equals(item.barcode!))).go();
      }
      await _db.into(_db.catalogItemsTable).insert(
            CatalogItemsTableCompanion.insert(
              source: item.source,
              barcode: Value(item.barcode),
              name: item.name,
              brand: Value(item.brand),
              quantity: Value(item.quantity),
              categoryHint: Value(item.categoryHint),
              description: Value(item.description),
              imageUrl: Value(item.imageUrl),
              imageBytes: Value(item.imageBytes),
              fetchedAt: _clock(),
            ),
          );
    });
  }
}
