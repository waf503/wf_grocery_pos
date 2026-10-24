import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import '../core/barcode/internal_barcode.dart';
import '../core/database/app_database.dart';
import '../core/text/product_tags.dart';
import '../features/products/data/product_repository.dart';
import '../models/product.dart';
import '../models/product_combo.dart';

/// Estado de la sección de Inventario.
///
/// Delega todo al [ProductRepository] (inyectado por constructor) y
/// mantiene una copia local sincronizada — actualizada sola cada vez que
/// la base de datos cambia, gracias a `watchAll()`.
class InventoryProvider extends ChangeNotifier {
  InventoryProvider(this._repository) {
    _subscription = _repository.watchAll().listen((rows) {
      _products = rows;
      notifyListeners();
    });
  }

  final ProductRepository _repository;
  late final StreamSubscription<List<Product>> _subscription;

  List<Product> _products = [];

  List<Product> get products => List.unmodifiable(_products);

  /// Productos reales (sin contar las presentaciones, que son otra forma de
  /// vender el mismo producto y no tienen existencias propias).
  List<Product> get baseProducts => _products.where((p) => !p.isPresentation).toList();

  /// Solo productos base: el stock bajo de una presentación es el del base.
  List<Product> get lowStockProducts =>
      _products.where((p) => !p.isPresentation && p.isLowStock).toList();

  /// Las presentaciones de un producto base (cajetilla, paquete...), de la
  /// que contiene menos a la que contiene más.
  List<Product> presentationsOf(String baseId) {
    return _products.where((p) => p.baseProductId == baseId).toList()
      ..sort((a, b) => a.unitsPerPack.compareTo(b.unitsPerPack));
  }

  /// Existencias del pool del que descuenta [product]: las del propio producto
  /// o, si es una presentación, las de su producto base (en unidades base).
  double poolStock(Product product) => byId(product.poolId)?.poolUnits ?? product.poolUnits;

  /// Búsqueda por nombre, tags o código de barras (sin importar mayúsculas
  /// ni acentos).
  List<Product> search({String query = '', String? category}) {
    return _products.where((p) {
      final matchesCategory = category == null || category == 'Todas' || p.category == category;
      return matchesCategory &&
          matchesProductQuery(query, name: p.name, tags: p.tags, barcode: p.barcode);
    }).toList();
  }

  /// Productos ya ingresados que coinciden con lo que el usuario está
  /// escribiendo: cada palabra tecleada debe ser el comienzo de algún tag
  /// ("coca" → "Coca-Cola Lata 355ml"). Como los tags viven en el propio
  /// producto, al borrar un producto desaparece su sugerencia.
  List<Product> suggestionsFor(String text, {int limit = 6}) {
    final typed = tagWords(text);
    if (typed.isEmpty) return const [];
    final matches = _products.where((p) {
      final tags = p.tags.split(' ');
      return typed.every((word) => tags.any((tag) => tag.startsWith(word)));
    }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return matches.take(limit).toList();
  }

  /// Código EAN-13 interno libre, para productos o packs sin código físico.
  String generateInternalBarcode() {
    return buildInternalBarcode(nextInternalSequence(_products.map((p) => p.barcode)));
  }

  /// `true` si otro producto (distinto de [exceptId]) ya usa ese código.
  bool isBarcodeTaken(String code, {String? exceptId}) {
    return _products.any((p) => p.barcode == code && p.id != exceptId);
  }

  /// Miniaturas ya pedidas. La clave incluye `updatedAt`, así que al editar
  /// un producto se vuelve a leer su imagen; el mapa se limpia si crece mucho.
  final Map<String, Future<Uint8List?>> _imageCache = {};

  /// La miniatura del producto (`null` si no tiene), con caché en memoria.
  ///
  /// Las presentaciones comparten la miniatura de su producto base: se pide la
  /// de éste, y la clave de la caché usa SU fecha de edición, así que al cambiar
  /// la imagen del base todas sus presentaciones la ven actualizada.
  Future<Uint8List?> imageFor(Product product) {
    if (!product.hasImage) return Future.value(null);
    if (_imageCache.length > 300) _imageCache.clear();
    final sourceId = product.imageSourceId ?? product.id;
    final version = byId(sourceId)?.updatedAt ?? product.updatedAt;
    final key = '$sourceId@${version.millisecondsSinceEpoch}';
    return _imageCache.putIfAbsent(key, () => _repository.getImage(sourceId));
  }

  Product? byId(String id) {
    for (final p in _products) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<String> addProduct({
    required String name,
    required String categoryId,
    required String unitId,
    required int priceCents,
    required int costCents,
    required double stock,
    required double minStock,
    String? barcode,
    String extraTags = '',
    Uint8List? image,
  }) {
    return _repository.add(
      ProductsTableCompanion.insert(
        name: name.trim(),
        categoryId: categoryId,
        unitId: unitId,
        priceCents: priceCents,
        costCents: costCents,
        stock: Value(stock),
        minStock: Value(minStock),
        barcode: Value(barcode),
        tags: Value(buildTags(name, extra: extraTags)),
      ),
      image: image,
    );
  }

  Future<void> updateProduct({
    required String id,
    required String name,
    required String categoryId,
    required String unitId,
    required int priceCents,
    required int costCents,
    required double stock,
    required double minStock,
    String? barcode,
    String extraTags = '',
    Uint8List? image,
    bool removeImage = false,
  }) async {
    await _repository.update(
      ProductsTableCompanion(
        id: Value(id),
        name: Value(name.trim()),
        categoryId: Value(categoryId),
        unitId: Value(unitId),
        priceCents: Value(priceCents),
        costCents: Value(costCents),
        stock: Value(stock),
        minStock: Value(minStock),
        barcode: Value(barcode),
        tags: Value(buildTags(name, extra: extraTags)),
      ),
      image: image,
      removeImage: removeImage,
    );
    // La fecha de edición solo tiene precisión de segundos: si la imagen cambió
    // se olvida la que había en la caché (y la de sus presentaciones, que la
    // comparten) en vez de depender de esa fecha.
    if (image != null || removeImage) _imageCache.removeWhere((key, _) => key.startsWith('$id@'));
  }

  /// Agrega inventario: [quantity] unidades, cajetillas o paquetes de [target]
  /// (la presentación elegida) se SUMAN a las existencias del producto base.
  /// Devuelve cuántas unidades base se agregaron.
  ///
  /// Si se da [costCents] (lo que cuesta UNA de [target]), se actualiza el
  /// costo del producto y de todas sus presentaciones calculando el de cada
  /// unidad: el usuario escribe el costo del paquete y no tiene que dividir.
  Future<double> addStock(Product target, double quantity, {int? costCents}) async {
    final units = quantity * target.poolFactor;
    await _repository.addStock(target.poolId, units);
    if (costCents != null) await _repository.setCostFromPresentation(target.id, costCents);
    return units;
  }

  /// Promociones por cantidad del producto (reemplaza las que tenía).
  Future<void> setCombos(String productId, List<ProductCombo> combos) =>
      _repository.setCombos(productId, combos);

  /// Presentaciones del producto base (reemplaza las que tenía).
  Future<void> savePresentations(
    String baseId,
    List<PresentationDraft> drafts, {
    int? baseUnitsPerPack,
    double stockScale = 1,
  }) =>
      _repository.savePresentations(
        baseId,
        drafts,
        baseUnitsPerPack: baseUnitsPerPack,
        stockScale: stockScale,
      );

  Future<void> deleteProduct(String id) => _repository.delete(id);

  Future<void> deleteProducts(Iterable<String> ids) async {
    for (final id in ids) {
      await _repository.delete(id);
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
