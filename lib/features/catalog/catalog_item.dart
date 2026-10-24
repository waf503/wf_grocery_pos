import 'dart:typed_data';

import '../../core/text/product_tags.dart';

/// Datos de referencia de un producto (no es un producto del negocio): lo
/// que una fuente externa sabe de un código de barras o de una marca. Se usa
/// para SUGERIR el llenado del formulario; el usuario siempre lo revisa.
class CatalogItem {
  const CatalogItem({
    required this.source,
    required this.name,
    this.barcode,
    this.brand,
    this.quantity,
    this.categoryHint,
    this.description,
    this.imageUrl,
    this.imageBytes,
  });

  /// De dónde salió, ej. "Open Beauty Facts". Se muestra como crédito.
  final String source;

  /// Nombre como lo publica la fuente, sin marca ni presentación.
  final String name;
  final String? barcode;
  final String? brand;

  /// Presentación en texto libre, ej. "275 ml".
  final String? quantity;
  final String? categoryHint;
  final String? description;
  final String? imageUrl;
  final Uint8List? imageBytes;

  CatalogItem withBarcode(String code) => CatalogItem(
        source: source,
        name: name,
        barcode: code,
        brand: brand,
        quantity: quantity,
        categoryHint: categoryHint,
        description: description,
        imageUrl: imageUrl,
        imageBytes: imageBytes,
      );

  /// Nombre listo para el formulario, con el formato del inventario (el
  /// nombre ya incluye marca y presentación): "Pantene Champú 275 ml".
  /// No repite la marca ni la presentación si el nombre ya las trae, y
  /// convierte los nombres en MAYÚSCULAS a formato de título.
  String get suggestedName {
    final cleanName = _prettify(name);
    final parts = <String>[];

    final cleanBrand = brand == null ? '' : _prettify(brand!);
    if (cleanBrand.isNotEmpty && !_mentions(cleanName, cleanBrand)) parts.add(cleanBrand);

    parts.add(cleanName);

    final amount = quantity?.trim() ?? '';
    if (amount.isNotEmpty) {
      final compact = normalizeText(amount).replaceAll(' ', '');
      if (!normalizeText(cleanName).replaceAll(' ', '').contains(compact)) parts.add(amount);
    }
    return parts.join(' ');
  }

  /// `true` si [text] ya contiene alguna palabra significativa de [brand]
  /// (así "Coca-Cola Original" no se vuelve "Coca-Cola Services SA/NV Coca-Cola...").
  static bool _mentions(String text, String brand) {
    final normalized = normalizeText(text);
    return tokenize(brand).any((token) => token.length >= 3 && normalized.contains(token));
  }

  static String _prettify(String value) {
    final text = value.trim();
    final letters = text.replaceAll(RegExp(r'[^A-Za-zÁÉÍÓÚÜÑáéíóúüñ]'), '');
    if (letters.isEmpty || text != text.toUpperCase()) return text;
    return text
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0]}${w.substring(1).toLowerCase()}')
        .join(' ');
  }
}

/// Resultado de buscar información de un código de barras.
class LookupResult {
  const LookupResult({this.item, this.offline = false, this.fromCache = false});

  /// Lo encontrado, o `null` si no hay información.
  final CatalogItem? item;

  /// `true` si no se pudo consultar ninguna fuente (sin internet).
  final bool offline;

  /// `true` si salió de la memoria local, sin consultar internet.
  final bool fromCache;
}
