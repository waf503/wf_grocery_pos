import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../models/category.dart';
import 'category_repository.dart';

class DriftCategoryRepository implements CategoryRepository {
  DriftCategoryRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<List<Category>> watchAll() {
    return _db.select(_db.categoriesTable).watch().map(
          (rows) => rows.map(_toModel).toList(),
        );
  }

  @override
  Future<Category> add({
    required String name,
    String? description,
    String? parentId,
    String? icon,
    int? color,
  }) async {
    final row = await _db.into(_db.categoriesTable).insertReturning(
          CategoriesTableCompanion.insert(
            name: name,
            description: Value(description),
            parentId: Value(parentId),
            icon: Value(icon),
            color: Value(color),
          ),
        );
    return _toModel(row);
  }

  @override
  Future<void> update(Category category) {
    return (_db.update(_db.categoriesTable)
          ..where((row) => row.id.equals(category.id)))
        .write(
      CategoriesTableCompanion(
        name: Value(category.name),
        description: Value(category.description),
        parentId: Value(category.parentId),
        icon: Value(category.icon),
        color: Value(category.color),
      ),
    );
  }

  @override
  Future<DeleteCategoryResult> delete(String id) async {
    final hasChildren = await (_db.select(_db.categoriesTable)
          ..where((row) => row.parentId.equals(id)))
        .get();
    if (hasChildren.isNotEmpty) {
      return const DeleteCategoryResult.failure(DeleteCategoryError.hasChildren);
    }

    final usedByProducts = await (_db.select(_db.productsTable)
          ..where((row) => row.categoryId.equals(id)))
        .get();
    if (usedByProducts.isNotEmpty) {
      return const DeleteCategoryResult.failure(DeleteCategoryError.hasProducts);
    }

    await (_db.delete(_db.categoriesTable)..where((row) => row.id.equals(id))).go();
    return const DeleteCategoryResult.success();
  }

  Category _toModel(CategoriesTableData row) {
    return Category(
      id: row.id,
      name: row.name,
      description: row.description,
      parentId: row.parentId,
      icon: row.icon,
      color: row.color,
    );
  }
}
