import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'id_generator.dart';
import 'tables/categories_table.dart';
import 'tables/products_table.dart';
import 'tables/units_table.dart';

part 'app_database.g.dart';

/// La base de datos local de la app (un archivo `.sqlite` en el disco del
/// dispositivo). Es el equivalente a la conexión de base de datos que
/// configuras en `config/database.php` en Laravel, solo que aquí vive
/// embebida dentro de la propia app — no hay servidor de base de datos
/// separado.
///
/// `@DriftDatabase(tables: [...])` le dice a Drift qué tablas generar código
/// para. Cuando agreguemos el módulo de Caja, Ventas, etc., cada tabla nueva
/// se agrega a esta lista.
@DriftDatabase(tables: [CategoriesTable, UnitsTable, ProductsTable])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Constructor alterno para pruebas: usa una base en memoria que
  /// desaparece al terminar el test, en vez de escribir un archivo real.
  AppDatabase.forTesting(super.executor);

  /// `schemaVersion` es el equivalente a "en qué migración va tu base de
  /// datos". Cuando en el futuro agreguemos una columna o tabla nueva, se
  /// sube este número y se describe el cambio en [migration] — eso es
  /// literalmente una migración nueva de Laravel, solo que escrita como
  /// código Dart en vez de un archivo `2026_09_29_add_column.php`.
  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          // Todavía no hay usuarios reales usando versiones anteriores del
          // esquema (solo datos de desarrollo/seed), así que la migración
          // más simple y honesta es recrear todo desde cero. Una vez en
          // producción, esto se reemplazaría por pasos que preserven los
          // datos (m.addColumn, m.createTable puntuales, etc.).
          await m.deleteTable('product_variants');
          await m.deleteTable('products');
          await m.deleteTable('units');
          await m.deleteTable('categories');
          await m.createAll();
        },
      );
}

LazyDatabase _openConnection() {
  // LazyDatabase pospone abrir el archivo hasta que realmente se necesite,
  // porque encontrar la carpeta correcta (path_provider) es una operación
  // asíncrona y el constructor de arriba no puede serlo.
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'wf_grocery_pos.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
