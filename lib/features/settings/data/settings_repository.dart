import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

abstract class SettingsRepository {
  Future<Map<String, String>> all();

  Future<void> set(String key, String value);
}

class DriftSettingsRepository implements SettingsRepository {
  DriftSettingsRepository(this._db);

  final AppDatabase _db;

  @override
  Future<Map<String, String>> all() async {
    final rows = await _db.select(_db.settingsTable).get();
    return {for (final row in rows) row.key: row.value};
  }

  @override
  Future<void> set(String key, String value) async {
    await _db
        .into(_db.settingsTable)
        .insertOnConflictUpdate(
          SettingsTableCompanion(key: Value(key), value: Value(value)),
        );
  }
}
