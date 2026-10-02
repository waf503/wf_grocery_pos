import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../models/unit.dart';
import 'unit_repository.dart';

class DriftUnitRepository implements UnitRepository {
  DriftUnitRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<List<Unit>> watchAll() {
    return (_db.select(_db.unitsTable)
          ..orderBy([(row) => OrderingTerm.asc(row.createdAt), (row) => OrderingTerm.asc(row.name)]))
        .watch()
        .map((rows) => rows.map(_toModel).toList());
  }

  @override
  Future<void> add({
    required String name,
    String? abbreviation,
    required bool allowsDecimals,
  }) async {
    await _db.into(_db.unitsTable).insert(
          UnitsTableCompanion.insert(
            name: name,
            abbreviation: Value(abbreviation),
            allowsDecimals: Value(allowsDecimals),
          ),
        );
  }

  @override
  Future<void> update(Unit unit) {
    return (_db.update(_db.unitsTable)..where((row) => row.id.equals(unit.id))).write(
      UnitsTableCompanion(
        name: Value(unit.name),
        abbreviation: Value(unit.abbreviation),
        allowsDecimals: Value(unit.allowsDecimals),
      ),
    );
  }

  @override
  Future<DeleteUnitResult> delete(String id) async {
    final usedByProducts = await (_db.select(_db.productsTable)
          ..where((row) => row.unitId.equals(id))
          ..limit(1))
        .get();
    if (usedByProducts.isNotEmpty) {
      return const DeleteUnitResult.failure(DeleteUnitError.hasProducts);
    }
    await (_db.delete(_db.unitsTable)..where((row) => row.id.equals(id))).go();
    return const DeleteUnitResult.success();
  }

  Unit _toModel(UnitsTableData row) {
    return Unit(
      id: row.id,
      name: row.name,
      abbreviation: row.abbreviation,
      allowsDecimals: row.allowsDecimals,
    );
  }
}
