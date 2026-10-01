import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../models/product.dart';
import '../../../models/product_family.dart';
import 'product_repository.dart';

class DriftProductRepository implements ProductRepository {
  DriftProductRepository(this._db);

  final AppDatabase _db;

  /// Los tres joins que arman un `Product` aplanado se repiten en dos
  /// métodos (`watchAllVariants` y `getVariantById`) — factorizados aquí
  /// para no duplicar la misma cadena de `join([...])` dos veces.
  ///
  /// El tipo de retorno explícito importa: usar `dynamic` aquí compila
  /// sin quejarse, pero rompe en tiempo de EJECUCIÓN (el `.map()` de más
  /// abajo deja de saber a qué tipo convertir el Stream). Ya nos pasó.
  JoinedSelectStatement<HasResultSet, dynamic> _variantJoin() {
    return _db.select(_db.productVariantsTable).join([
      innerJoin(
        _db.productsTable,
        _db.productsTable.id.equalsExp(_db.productVariantsTable.productId),
      ),
      innerJoin(
        _db.categoriesTable,
        _db.categoriesTable.id.equalsExp(_db.productsTable.categoryId),
      ),
    ]);
  }

  @override
  Stream<List<Product>> watchAllVariants() {
    return _variantJoin().watch().map((rows) {
      return rows.map((row) {
        return _toModel(
          row.readTable(_db.productVariantsTable),
          row.readTable(_db.productsTable),
          row.readTable(_db.categoriesTable),
        );
      }).toList();
    });
  }

  @override
  Stream<List<ProductFamily>> watchFamilies() {
    return _db.select(_db.productsTable).watch().map(
          (rows) => rows.map(_familyToModel).toList(),
        );
  }

  @override
  Future<Product?> getVariantById(String id) async {
    final query = _variantJoin()..where(_db.productVariantsTable.id.equals(id));
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    return _toModel(
      row.readTable(_db.productVariantsTable),
      row.readTable(_db.productsTable),
      row.readTable(_db.categoriesTable),
    );
  }

  @override
  Future<ProductFamily> findOrCreateFamily({
    required String name,
    required String categoryId,
    String? brand,
  }) async {
    final normalized = name.trim();
    final existing = await (_db.select(_db.productsTable)
          ..where((row) => row.name.lower().equals(normalized.toLowerCase())))
        .getSingleOrNull();
    if (existing != null) return _familyToModel(existing);

    final inserted = await _db.into(_db.productsTable).insertReturning(
          ProductsTableCompanion.insert(
            name: normalized,
            categoryId: categoryId,
            brand: Value(brand),
          ),
        );
    return _familyToModel(inserted);
  }

  @override
  Future<void> addVariant(String familyId, ProductVariantsTableCompanion variant) {
    return _db.into(_db.productVariantsTable).insert(
          variant.copyWith(productId: Value(familyId)),
        );
  }

  @override
  Future<void> updateVariant(ProductVariantsTableCompanion variant) {
    return (_db.update(_db.productVariantsTable)
          ..where((row) => row.id.equals(variant.id.value)))
        .write(variant);
  }

  @override
  Future<void> deleteVariant(String variantId) {
    return (_db.delete(_db.productVariantsTable)
          ..where((row) => row.id.equals(variantId)))
        .go();
  }

  @override
  Future<void> decreaseStock(String variantId, double quantity) async {
    final product = await getVariantById(variantId);
    if (product == null) return;
    await updateVariant(
      ProductVariantsTableCompanion(
        id: Value(variantId),
        stock: Value(product.stock - quantity),
      ),
    );
  }

  Product _toModel(
    ProductVariantsTableData variant,
    ProductsTableData family,
    CategoriesTableData category,
  ) {
    return Product(
      id: variant.id,
      familyId: family.id,
      familyName: family.name,
      presentation: variant.presentation,
      name: '${family.name} — ${variant.presentation}',
      categoryId: category.id,
      category: category.name,
      unit: variant.unit,
      price: variant.price,
      cost: variant.cost,
      stock: variant.stock,
      minStock: variant.minStock,
      barcode: variant.barcode,
    );
  }

  ProductFamily _familyToModel(ProductsTableData row) {
    return ProductFamily(
      id: row.id,
      name: row.name,
      categoryId: row.categoryId,
      brand: row.brand,
    );
  }
}
