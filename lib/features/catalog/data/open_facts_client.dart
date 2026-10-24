import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../catalog_item.dart';
import 'image_download.dart';

/// Fuente remota de información por código de barras (separada de la
/// implementación para poder probar el flujo sin internet).
abstract class RemoteLookup {
  Future<LookupResult> fetch(String barcode);

  /// Libera la conexión de red.
  void close();
}

/// Cliente de las bases abiertas hermanas Open Food Facts (alimentos),
/// Open Beauty Facts (cosméticos) y Open Products Facts (otros). Son gratis,
/// no piden clave y responden igual a una consulta por código de barras.
///
/// Se consultan las tres a la vez y gana la primera de la lista que conozca
/// el código. Si ninguna responde (sin internet) se avisa con `offline`.
/// Solo se envía el código de barras: nunca datos del negocio.
///
/// Datos: Open Database License (ODbL); imágenes: Creative Commons con
/// atribución. Por eso cada resultado lleva su `source` para dar crédito.
class OpenFactsClient implements RemoteLookup {
  OpenFactsClient({
    http.Client? client,
    this.timeout = const Duration(seconds: 4),
    this.maxImageBytes = 400 * 1024,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;
  final int maxImageBytes;

  /// Orden de prioridad si más de una base conoce el código.
  static const _sources = [
    (name: 'Open Food Facts', host: 'world.openfoodfacts.org'),
    (name: 'Open Beauty Facts', host: 'world.openbeautyfacts.org'),
    (name: 'Open Products Facts', host: 'world.openproductsfacts.org'),
  ];

  static const _fields = 'code,product_name,product_name_es,generic_name,generic_name_es,'
      'brands,quantity,categories,image_front_small_url,image_small_url,image_front_url,image_url';

  // Open Food Facts pide identificar la aplicación en el User-Agent.
  static const _headers = {'User-Agent': 'wf-grocery-pos/1.0 (punto de venta para tiendas)'};

  @override
  Future<LookupResult> fetch(String barcode) async {
    final outcomes = await Future.wait([
      for (final source in _sources) _query(source.name, source.host, barcode),
    ]);

    for (final outcome in outcomes) {
      final item = outcome.item;
      if (item == null) continue;
      final bytes = item.imageUrl == null ? null : await _downloadImage(item.imageUrl!);
      return LookupResult(
        item: CatalogItem(
          source: item.source,
          name: item.name,
          barcode: barcode,
          brand: item.brand,
          quantity: item.quantity,
          categoryHint: item.categoryHint,
          description: item.description,
          imageUrl: item.imageUrl,
          imageBytes: bytes,
        ),
      );
    }
    // Sin resultado: si NINGUNA fuente respondió, es falta de conexión.
    return LookupResult(offline: outcomes.every((o) => o.failed));
  }

  Future<({CatalogItem? item, bool failed})> _query(String sourceName, String host, String barcode) async {
    try {
      final uri = Uri.https(host, '/api/v2/product/$barcode.json', {'fields': _fields});
      final response = await _client.get(uri, headers: _headers).timeout(timeout);
      // Código desconocido: 404 con un JSON "status: 0". No es un fallo.
      if (response.statusCode == 404) return (item: null, failed: false);
      if (response.statusCode != 200) return (item: null, failed: true);
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map || body['status'] != 1 || body['product'] is! Map) {
        return (item: null, failed: false);
      }
      return (item: _parse(sourceName, body['product'] as Map), failed: false);
    } on TimeoutException {
      return (item: null, failed: true);
    } on SocketException {
      return (item: null, failed: true);
    } on http.ClientException {
      return (item: null, failed: true);
    } on FormatException {
      return (item: null, failed: true);
    }
  }

  CatalogItem? _parse(String sourceName, Map product) {
    final name = _text(product['product_name_es']) ??
        _text(product['product_name']) ??
        _text(product['generic_name_es']) ??
        _text(product['generic_name']);
    final brandsText = _text(product['brands']);
    final brand = brandsText?.split(',').first.trim();
    // Sin nombre ni marca no hay nada útil que sugerir.
    if (name == null && (brand == null || brand.isEmpty)) return null;

    final description = _text(product['generic_name_es']) ?? _text(product['generic_name']);
    final categories = _text(product['categories']);
    return CatalogItem(
      source: sourceName,
      name: name ?? brand!,
      brand: (brand == null || brand.isEmpty) ? null : brand,
      quantity: _text(product['quantity']),
      categoryHint: categories?.split(',').first.trim(),
      description: description == name ? null : description,
      imageUrl: _text(product['image_front_small_url']) ??
          _text(product['image_small_url']) ??
          _text(product['image_front_url']) ??
          _text(product['image_url']),
    );
  }

  static String? _text(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  Future<Uint8List?> _downloadImage(String url) =>
      downloadImage(_client, url, timeout: timeout, maxBytes: maxImageBytes, headers: _headers);

  @override
  void close() => _client.close();
}
