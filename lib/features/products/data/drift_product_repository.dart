import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../models/product.dart';
import 'product_repository.dart';

class DriftProductRepository implements ProductRepository {
  DriftProductRepository(this._db);

  final AppDatabase _db;

  /// Join con categorías para traer el nombre de la categoría junto a cada
  /// producto. El tipo de retorno explícito importa: con `dynamic` compila
  /// pero rompe en tiempo de ejecución al mapear el Stream.
  JoinedSelectStatement<HasResultSet, dynamic> _productJoin() {
    return _db.select(_db.productsTable).join([
      innerJoin(
        _db.categoriesTable,
        _db.categoriesTable.id.equalsExp(_db.productsTable.categoryId),
      ),
      innerJoin(
        _db.unitsTable,
        _db.unitsTable.id.equalsExp(_db.productsTable.unitId),
      ),
    ]);
  }

  @override
  Stream<List<Product>> watchAll() {
    return _productJoin().watch().map((rows) {
      return rows.map(_rowToModel).toList();
    });
  }

  @override
  Future<Product?> getById(String id) async {
    final query = _productJoin()..where(_db.productsTable.id.equals(id));
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    return _rowToModel(row);
  }

  @override
  Future<void> add(ProductsTableCompanion product) {
    return _db.into(_db.productsTable).insert(product);
  }

  @override
  Future<void> update(ProductsTableCompanion product) {
    return (_db.update(_db.productsTable)..where((row) => row.id.equals(product.id.value)))
        .write(product);
  }

  @override
  Future<void> delete(String id) {
    return (_db.delete(_db.productsTable)..where((row) => row.id.equals(id))).go();
  }

  @override
  Future<void> decreaseStock(String id, double quantity) async {
    final product = await getById(id);
    if (product == null) return;
    await update(
      ProductsTableCompanion(
        id: Value(id),
        stock: Value(product.stock - quantity),
      ),
    );
  }

  Product _rowToModel(TypedResult row) {
    final product = row.readTable(_db.productsTable);
    final category = row.readTable(_db.categoriesTable);
    final unit = row.readTable(_db.unitsTable);
    return _toModel(product, category, unit);
  }

  Product _toModel(ProductsTableData row, CategoriesTableData category, UnitsTableData unit) {
    final abbreviation = unit.abbreviation;
    return Product(
      id: row.id,
      name: row.name,
      categoryId: category.id,
      category: category.name,
      unitId: unit.id,
      unit: (abbreviation != null && abbreviation.isNotEmpty) ? abbreviation : unit.name,
      allowsDecimals: unit.allowsDecimals,
      price: row.price,
      cost: row.cost,
      stock: row.stock,
      minStock: row.minStock,
      barcode: row.barcode,
      tags: row.tags,
    );
  }
}
