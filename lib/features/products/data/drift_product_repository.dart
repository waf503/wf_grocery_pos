import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/id_generator.dart';
import '../../../core/text/product_tags.dart';
import '../../../models/product.dart';
import '../../../models/product_combo.dart';
import 'product_repository.dart';

/// Un renglón de la tabla con lo que hace falta para armar un [Product].
class _Raw {
  _Raw(this.row, this.category, this.unit);

  final ProductsTableData row;
  final CategoriesTableData category;
  final UnitsTableData unit;
  final List<ProductCombo> combos = [];
}

class DriftProductRepository implements ProductRepository {
  DriftProductRepository(this._db);

  final AppDatabase _db;

  /// Join con categorías y unidades para traer sus nombres, y con los combos
  /// (un producto sin combos aparece una vez; con combos, una vez por combo).
  /// El tipo de retorno explícito importa: con `dynamic` compila pero rompe
  /// en tiempo de ejecución al mapear el Stream.
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
      leftOuterJoin(
        _db.productCombosTable,
        _db.productCombosTable.productId.equalsExp(_db.productsTable.id),
      ),
    ]);
  }

  /// Agrupa los renglones del join por producto (conservando el orden) y
  /// junta sus combos.
  Map<String, _Raw> _group(List<TypedResult> rows) {
    final byId = <String, _Raw>{};
    for (final result in rows) {
      final product = result.readTable(_db.productsTable);
      final raw = byId.putIfAbsent(
        product.id,
        () => _Raw(product, result.readTable(_db.categoriesTable), result.readTable(_db.unitsTable)),
      );
      final combo = result.readTableOrNull(_db.productCombosTable);
      if (combo != null) {
        raw.combos.add(ProductCombo(quantity: combo.quantity, priceCents: combo.priceCents));
      }
    }
    for (final raw in byId.values) {
      raw.combos.sort((a, b) => a.quantity.compareTo(b.quantity));
    }
    return byId;
  }

  @override
  Stream<List<Product>> watchAll() {
    return _productJoin().watch().map((rows) {
      final raws = _group(rows);
      return [for (final raw in raws.values) _toModel(raw, raws)];
    });
  }

  @override
  Future<Product?> getById(String id) async {
    final query = _productJoin()..where(_db.productsTable.id.equals(id));
    final raws = _group(await query.get());
    final raw = raws[id];
    if (raw == null) return null;

    // Una presentación necesita a su producto base para saber cuánto hay.
    final baseId = raw.row.baseProductId;
    if (baseId != null) {
      final baseQuery = _productJoin()..where(_db.productsTable.id.equals(baseId));
      raws.addAll(_group(await baseQuery.get()));
    }
    return _toModel(raw, raws);
  }

  @override
  Future<String> add(ProductsTableCompanion product, {Uint8List? image}) {
    return _db.transaction(() async {
      final id = product.id.present ? product.id.value : generateId('p');
      await _db.into(_db.productsTable).insert(
            product.copyWith(id: Value(id), hasImage: Value(image != null)),
          );
      if (image != null) {
        await _db.into(_db.productImagesTable).insert(
              ProductImagesTableCompanion.insert(productId: id, bytes: image),
            );
      }
      return id;
    });
  }

  @override
  Future<void> update(ProductsTableCompanion product, {Uint8List? image, bool removeImage = false}) {
    final id = product.id.value;
    return _db.transaction(() async {
      await (_db.update(_db.productsTable)..where((row) => row.id.equals(id))).write(
        product.copyWith(
          updatedAt: Value(DateTime.now()),
          hasImage: image != null
              ? const Value(true)
              : (removeImage ? const Value(false) : const Value.absent()),
        ),
      );
      if (image != null) {
        await _db.into(_db.productImagesTable).insertOnConflictUpdate(
              ProductImagesTableCompanion.insert(productId: id, bytes: image),
            );
      } else if (removeImage) {
        await (_db.delete(_db.productImagesTable)..where((row) => row.productId.equals(id))).go();
      }
    });
  }

  @override
  Future<Uint8List?> getImage(String productId) async {
    final row = await (_db.select(_db.productImagesTable)..where((r) => r.productId.equals(productId)))
        .getSingleOrNull();
    return row?.bytes;
  }

  @override
  Future<void> addStock(String productId, double units) async {
    if (units <= 0) throw ArgumentError('Las existencias a agregar deben ser mayores a cero.');
    // La suma se hace en SQL (stock = stock + n), no leyendo y escribiendo, para
    // no perder una venta que ocurra al mismo tiempo.
    await (_db.update(_db.productsTable)..where((row) => row.id.equals(productId))).write(
      ProductsTableCompanion.custom(
        stock: _db.productsTable.stock + Constant(units),
        updatedAt: Constant(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> setCostFromPresentation(String presentationId, int costCents) {
    if (costCents <= 0) throw ArgumentError('El costo debe ser mayor a cero.');
    return _db.transaction(() async {
      final target = await (_db.select(_db.productsTable)..where((r) => r.id.equals(presentationId))).getSingle();
      final baseId = target.baseProductId ?? target.id;
      final targetUnits = target.unitsPerPack <= 0 ? 1.0 : target.unitsPerPack;
      final root = await (_db.select(_db.productsTable)..where((r) => r.id.equals(baseId))).getSingle();

      // Costo exacto de UNA unidad del pool (puede tener fracciones de centavo:
      // $25 ÷ 400 = 6.25¢). Cada presentación se calcula desde ese valor exacto,
      // no desde uno ya redondeado, para no arrastrar el error de redondeo.
      final perUnit = costCents / targetUnits;
      final now = DateTime.now();

      await (_db.update(_db.productsTable)..where((r) => r.id.equals(baseId))).write(
        ProductsTableCompanion(
          costCents: Value((perUnit * (root.unitsPerPack <= 0 ? 1 : root.unitsPerPack)).round()),
          updatedAt: Value(now),
        ),
      );
      final children = await (_db.select(_db.productsTable)..where((r) => r.baseProductId.equals(baseId))).get();
      for (final child in children) {
        await (_db.update(_db.productsTable)..where((r) => r.id.equals(child.id))).write(
          ProductsTableCompanion(costCents: Value((perUnit * child.unitsPerPack).round()), updatedAt: Value(now)),
        );
      }
    });
  }

  @override
  Future<void> setCombos(String productId, List<ProductCombo> combos) {
    return _db.transaction(() => _replaceCombos(productId, combos));
  }

  Future<void> _replaceCombos(String productId, List<ProductCombo> combos) async {
    await (_db.delete(_db.productCombosTable)..where((row) => row.productId.equals(productId))).go();
    for (final combo in combos) {
      await _db.into(_db.productCombosTable).insert(
            ProductCombosTableCompanion.insert(
              productId: productId,
              quantity: combo.quantity,
              priceCents: combo.priceCents,
            ),
          );
    }
  }

  @override
  Future<void> savePresentations(
    String baseId,
    List<PresentationDraft> drafts, {
    int? baseUnitsPerPack,
    double stockScale = 1,
  }) {
    return _db.transaction(() async {
      var base = await (_db.select(_db.productsTable)..where((row) => row.id.equals(baseId))).getSingle();

      // Al agregar una presentación MÁS PEQUEÑA que el base (ej. cigarro suelto
      // dentro de un paquete) la unidad del pool cambia: el base pasa a valer
      // más unidades y las existencias ya guardadas se multiplican.
      if (baseUnitsPerPack != null || stockScale != 1) {
        if (stockScale != 1) {
          // Las ventas anteriores recuerdan cuánto descontaron en la unidad
          // vieja: se reescriben (y las más antiguas se completan primero) para
          // que anularlas siga devolviendo lo correcto.
          await _db.customStatement(
            'UPDATE sale_items SET stock_product_id = product_id, stock_quantity = quantity '
            'WHERE stock_product_id IS NULL AND product_id = ?',
            [baseId],
          );
          await _db.customStatement(
            'UPDATE sale_items SET stock_quantity = stock_quantity * ? WHERE stock_product_id = ?',
            [stockScale, baseId],
          );
        }
        await (_db.update(_db.productsTable)..where((row) => row.id.equals(baseId))).write(
          ProductsTableCompanion(
            unitsPerPack: baseUnitsPerPack == null ? const Value.absent() : Value(baseUnitsPerPack.toDouble()),
            stock: Value(base.stock * stockScale),
            minStock: Value(base.minStock * stockScale),
          ),
        );
        base = await (_db.select(_db.productsTable)..where((row) => row.id.equals(baseId))).getSingle();
      }
      final rootFactor = base.unitsPerPack <= 0 ? 1.0 : base.unitsPerPack;
      final existing = await (_db.select(_db.productsTable)..where((row) => row.baseProductId.equals(baseId))).get();
      final keepIds = {for (final d in drafts) ?d.id};

      // Las presentaciones que ya no están en la lista se borran.
      for (final child in existing) {
        if (!keepIds.contains(child.id)) {
          await (_db.delete(_db.productsTable)..where((row) => row.id.equals(child.id))).go();
        }
      }

      final now = DateTime.now();
      for (final draft in drafts) {
        final isOwn = draft.id != null && existing.any((c) => c.id == draft.id);
        // La presentación sigue la categoría y la unidad de su producto base.
        final fields = ProductsTableCompanion(
          name: Value(draft.name.trim()),
          categoryId: Value(base.categoryId),
          unitId: Value(base.unitId),
          priceCents: Value(draft.priceCents),
          // Sin costo escrito, el de la presentación sale del costo del base repartido por tamaño.
          costCents: Value(draft.costCents ?? (draft.unitsPerPack * base.costCents / rootFactor).round()),
          barcode: Value(draft.barcode),
          tags: Value(buildTags(draft.name)),
          baseProductId: Value(baseId),
          unitsPerPack: Value(draft.unitsPerPack.toDouble()),
          updatedAt: Value(now),
        );
        final String id;
        if (isOwn) {
          id = draft.id!;
          await (_db.update(_db.productsTable)..where((row) => row.id.equals(id))).write(fields);
        } else {
          id = generateId('p');
          await _db.into(_db.productsTable).insert(fields.copyWith(id: Value(id)));
        }
        await _replaceCombos(id, draft.combos);
      }
    });
  }

  @override
  Future<void> delete(String id) {
    return _db.transaction(() async {
      // Borrar un producto base borra también sus presentaciones (que no
      // tienen existencias propias). Sus imágenes y combos se borran en cascada.
      await (_db.delete(_db.productsTable)..where((row) => row.baseProductId.equals(id))).go();
      await (_db.delete(_db.productsTable)..where((row) => row.id.equals(id))).go();
    });
  }

  /// Arma el producto. Las existencias viven en el pool (la fila base, en la
  /// unidad más pequeña del grupo); aquí se miden en las unidades de ESTA fila:
  /// cuántas completas caben (ej. 2,050 cigarros = 10 paquetes de 200).
  Product _toModel(_Raw raw, Map<String, _Raw> all) {
    final row = raw.row;
    final unit = raw.unit;
    final abbreviation = unit.abbreviation;

    final baseId = row.baseProductId;
    final poolRow = all[baseId ?? row.id]?.row ?? row;
    final factor = row.unitsPerPack <= 0 ? 1.0 : row.unitsPerPack;
    // Con factor 1 las existencias se muestran tal cual (pueden llevar
    // decimales: libras); con más de 1 solo cuentan las unidades completas.
    final stock = factor == 1 ? poolRow.stock : (poolRow.stock / factor).floorToDouble();
    final minStock = factor == 1 ? poolRow.minStock : (poolRow.minStock / factor).floorToDouble();
    final decimals = baseId == null && factor == 1 && unit.allowsDecimals;

    return Product(
      id: row.id,
      name: row.name,
      categoryId: raw.category.id,
      category: raw.category.name,
      unitId: unit.id,
      unit: (abbreviation != null && abbreviation.isNotEmpty) ? abbreviation : unit.name,
      allowsDecimals: decimals,
      quantityStep: decimals ? unit.saleStep : 1,
      priceCents: row.priceCents,
      costCents: row.costCents,
      stock: stock,
      minStock: minStock,
      barcode: row.barcode,
      tags: row.tags,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt ?? row.createdAt,
      // Una presentación comparte la miniatura de su producto base.
      hasImage: baseId == null ? row.hasImage : poolRow.hasImage,
      imageSourceId: baseId,
      baseProductId: baseId,
      unitsPerPack: factor,
      combos: List.unmodifiable(raw.combos),
      poolUnits: poolRow.stock,
    );
  }
}
