import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/app_user.dart';
import '../../models/cash_session.dart';
import '../../models/customer.dart';
import '../text/product_tags.dart';
import '../../models/sale.dart';
import 'id_generator.dart';
import 'tables/cash_movements_table.dart';
import 'tables/cash_sessions_table.dart';
import 'tables/catalog_items_table.dart';
import 'tables/categories_table.dart';
import 'tables/customer_movements_table.dart';
import 'tables/customers_table.dart';
import 'tables/product_combos_table.dart';
import 'tables/product_images_table.dart';
import 'tables/products_table.dart';
import 'tables/sale_items_table.dart';
import 'tables/sales_table.dart';
import 'tables/settings_table.dart';
import 'tables/units_table.dart';
import 'tables/users_table.dart';

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
    CustomersTable,
    CustomerMovementsTable,
    ProductImagesTable,
    CatalogItemsTable,
    ProductCombosTable,
    UsersTable,
    SettingsTable,
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
  int get schemaVersion => 21;

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
                newColumns: [
                  productsTable.priceCents,
                  productsTable.costCents,
                  productsTable.updatedAt,
                  productsTable.hasImage,
                  productsTable.baseProductId,
                  productsTable.unitsPerPack,
                ],
                columnTransformer: {
                  productsTable.priceCents:
                      const CustomExpression<int>('CAST(ROUND(price * 100) AS INTEGER)'),
                  productsTable.costCents:
                      const CustomExpression<int>('CAST(ROUND(cost * 100) AS INTEGER)'),
                },
              ),
            );
          }
          if (from < 10) {
            // Clientes con estado de cuenta persistente y anulación de ventas.
            await m.createTable(customersTable);
            await m.createTable(customerMovementsTable);
            await m.create(idxCustomerMovementsCustomerId);
            if (from >= 8) {
              // (Desde la v7 la tabla `sales` se acaba de crear arriba con
              // estas columnas ya incluidas.)
              await m.addColumn(salesTable, salesTable.status);
              await m.addColumn(salesTable, salesTable.voidedAt);
              await m.addColumn(salesTable, salesTable.voidReason);
            }
          }
          if (from < 11) {
            // Fecha de última actualización de cada producto (nula hasta la
            // primera edición).
            // (Antes de la v9 la tabla se reconstruye arriba ya con la columna.)
            if (from >= 9) await m.addColumn(productsTable, productsTable.updatedAt);
          }
          if (from < 12) {
            // Los abonos de clientes y las anulaciones se guardaban como
            // ingreso/retiro genéricos (solo la nota los distinguía): se les
            // asigna su tipo propio. Los datos no cambian, solo la etiqueta.
            await customStatement(
              "UPDATE cash_movements SET type = 'customerPayment' "
              "WHERE type = 'deposit' AND note LIKE 'Abono de %'",
            );
            await customStatement(
              "UPDATE cash_movements SET type = 'saleVoid' "
              "WHERE type = 'withdrawal' AND note LIKE 'Anulación V-%'",
            );
          }
          if (from < 13) {
            // Incremento de venta por unidad: las unidades que ya permitían
            // decimales pasan a venderse de media en media.
            await m.addColumn(unitsTable, unitsTable.saleStep);
            await customStatement('UPDATE units SET sale_step = 0.5 WHERE allows_decimals = 1');
          }
          if (from < 14) {
            // Miniaturas de producto y catálogo de consulta (datos buscados
            // por código de barras). Antes de la v9 la tabla de productos se
            // reconstruye arriba ya con la columna `has_image`.
            await m.createTable(productImagesTable);
            await m.createTable(catalogItemsTable);
            await m.create(idxCatalogItemsBarcode);
            if (from >= 9) await m.addColumn(productsTable, productsTable.hasImage);
          }
          if (from < 15) {
            // Los tags son solo texto: se quitan los guardados con números
            // ("355ml", "2l") o letras sueltas. Solo cambia `products.tags`.
            final rows = await customSelect('SELECT id, tags FROM products').get();
            for (final row in rows) {
              final old = row.read<String>('tags');
              final clean = tagWords(old).toSet().join(' ');
              if (clean == old) continue;
              await customUpdate(
                'UPDATE products SET tags = ? WHERE id = ?',
                variables: [Variable<String>(clean), Variable<String>(row.read<String>('id'))],
                updates: {productsTable},
                updateKind: UpdateKind.update,
              );
            }
          }
          if (from < 16) {
            // Con cuánto pagó el cliente y el vuelto (ventas en efectivo).
            // Desde la v7 la tabla `sales` se acaba de crear arriba, ya con
            // estas columnas.
            if (from >= 8) {
              await m.addColumn(salesTable, salesTable.tenderedCents);
              await m.addColumn(salesTable, salesTable.changeCents);
            }
          }
          if (from < 17) {
            // Presentaciones (cajetilla, paquete...) que comparten existencias
            // y combos por cantidad. Antes de la v9 la tabla de productos se
            // reconstruye arriba ya con las columnas nuevas; y desde la v7 los
            // renglones de venta se crean con las suyas.
            await m.createTable(productCombosTable);
            await m.create(idxProductCombosProductId);
            if (from >= 9) {
              await m.addColumn(productsTable, productsTable.baseProductId);
              await m.addColumn(productsTable, productsTable.unitsPerPack);
            }
            if (from >= 8) {
              await m.addColumn(saleItemsTable, saleItemsTable.stockProductId);
              await m.addColumn(saleItemsTable, saleItemsTable.stockQuantity);
            }
          }
          if (from < 18) {
            // Usuarios con PIN (admin / cajero) y quién cobró / anuló cada venta.
            await m.createTable(usersTable);
            // Antes de la v8 la tabla de ventas se crea arriba ya con estas columnas.
            if (from >= 8) {
              await m.addColumn(salesTable, salesTable.cashierName);
              await m.addColumn(salesTable, salesTable.voidedBy);
            }
          }
          if (from < 21) {
            // Quién recibió cada abono. Antes de la v10 la tabla de clientes se
            // crea arriba ya con esta columna.
            if (from >= 10) {
              await m.addColumn(customerMovementsTable, customerMovementsTable.receivedBy);
            }
          }
          if (from < 20) {
            // Quién abrió / cerró cada turno y quién hizo cada retiro o ingreso.
            // Antes de la v8 las tablas de caja se crean arriba ya con estas columnas.
            if (from >= 8) {
              await m.addColumn(cashSessionsTable, cashSessionsTable.openedBy);
              await m.addColumn(cashSessionsTable, cashSessionsTable.closedBy);
              await m.addColumn(cashMovementsTable, cashMovementsTable.createdBy);
            }
          }
          if (from < 19) {
            // Datos del negocio (nombre...), clave por clave.
            await m.createTable(settingsTable);
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
