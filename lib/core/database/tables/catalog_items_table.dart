import 'package:drift/drift.dart';

import '../id_generator.dart';

/// Tabla `catalog_items`: catálogo de CONSULTA (solo información de
/// referencia para sugerir datos al registrar productos). NO son productos
/// del negocio: no aparecen en el POS ni en los reportes.
///
/// Hoy guarda lo que se encontró en bases abiertas al escanear un código
/// (Open Food/Beauty/Products Facts), para no volver a consultar internet
/// por el mismo código. Más adelante también recibirá catálogos de marcas
/// (por nombre, sin código de barras): por eso `barcode` es opcional.
@TableIndex(name: 'idx_catalog_items_barcode', columns: {#barcode}, unique: true)
class CatalogItemsTable extends Table {
  @override
  String get tableName => 'catalog_items';

  TextColumn get id => text().clientDefault(() => generateId('g'))();

  /// De dónde salió ("Open Beauty Facts", "Diana"...). Sirve para dar crédito.
  TextColumn get source => text()();

  /// Código de barras (EAN/UPC), si se conoce. Único cuando existe.
  TextColumn get barcode => text().nullable()();

  /// Nombre tal como lo publica la fuente (sin marca ni presentación).
  TextColumn get name => text()();
  TextColumn get brand => text().nullable()();

  /// Presentación como texto libre, ej. "275 ml".
  TextColumn get quantity => text().nullable()();
  TextColumn get categoryHint => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get imageUrl => text().nullable()();

  /// Miniatura descargada (pequeña), para mostrarla sin internet.
  BlobColumn get imageBytes => blob().nullable()();

  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
