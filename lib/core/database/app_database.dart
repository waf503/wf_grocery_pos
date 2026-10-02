import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/cash_session.dart';
import '../../models/sale.dart';
import 'id_generator.dart';
import 'tables/cash_movements_table.dart';
import 'tables/cash_sessions_table.dart';
import 'tables/categories_table.dart';
import 'tables/products_table.dart';
import 'tables/sale_items_table.dart';
import 'tables/sales_table.dart';
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
@DriftDatabase(
  tables: [
    CategoriesTable,
    UnitsTable,
    ProductsTable,
    CashSessionsTable,
    SalesTable,
    SaleItemsTable,
    CashMovementsTable,
  ],
)
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
  int get schemaVersion => 9;

  /// Migraciones. REGLA: desde la versión 8 hay datos reales de negocio
  /// (ventas y caja), así que cada cambio de esquema debe escribirse como un
  /// paso que CONSERVE los datos (`createTable`, `addColumn`...) y subir
  /// `schemaVersion`. Nunca volver a borrar tablas.
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 7) {
            // Esquemas de desarrollo anteriores, sin datos reales: se
            // recrea todo desde cero.
            await m.deleteTable('product_variants');
            await m.deleteTable('products');
            await m.deleteTable('units');
            await m.deleteTable('categories');
            await m.createAll();
            return;
          }
          if (from < 8) {
            // Ventas y caja persistidas.
            await m.createTable(cashSessionsTable);
            await m.createTable(salesTable);
            await m.createTable(saleItemsTable);
            await m.createTable(cashMovementsTable);
            await m.create(idxSalesCreatedAt);
            await m.create(idxSaleItemsSaleId);
            await m.create(idxCashMovementsSessionId);
          }
          if (from < 9) {
            // Precio y costo de productos: de decimales (REAL) a centavos
            // enteros. Se reconstruye la tabla convirtiendo cada valor.
            await m.alterTable(
              TableMigration(
                productsTable,
                newColumns: [productsTable.priceCents, productsTable.costCents],
                columnTransformer: {
                  productsTable.priceCents:
                      const CustomExpression<int>('CAST(ROUND(price * 100) AS INTEGER)'),
                  productsTable.costCents:
                      const CustomExpression<int>('CAST(ROUND(cost * 100) AS INTEGER)'),
                },
              ),
            );
          }
        },
        beforeOpen: (details) async {
          // SQLite no hace cumplir las llaves foráneas a menos que se pida.
          await customStatement('PRAGMA foreign_keys = ON');
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
