import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../catalog_item.dart';
import 'image_download.dart';
import 'open_facts_client.dart';

/// Una tienda en línea que usa VTEX (plataforma de comercio electrónico).
class VtexStore {
  const VtexStore({required this.name, required this.host});

  /// Nombre que se muestra como fuente, ej. "Walmart El Salvador".
  final String name;
  final String host;
}

/// Busca un código de barras en el catálogo público de tiendas VTEX de la
/// región. Es la fuente que mejor conoce los productos locales (nombres en
/// español y con presentación, marca, categoría e imagen), a diferencia de
/// las bases abiertas, que casi no tienen productos centroamericanos.
///
/// OJO: no es una API oficial para terceros. Se usa con muy pocas consultas
/// (solo cuando el código no está en la memoria local ni en las bases
/// abiertas, y cada resultado se guarda) y nunca debe ser la única fuente:
/// la tienda puede cambiar o bloquear el acceso sin aviso.
class VtexRetailClient implements RemoteLookup {
  VtexRetailClient({
    http.Client? client,
    this.stores = defaultStores,
    this.timeout = const Duration(seconds: 4),
    this.maxImageBytes = 400 * 1024,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final List<VtexStore> stores;
  final Duration timeout;
  final int maxImageBytes;

  static const defaultStores = [
    VtexStore(name: 'Walmart El Salvador', host: 'www.walmart.com.sv'),
  ];

  static const _headers = {'User-Agent': 'wf-grocery-pos/1.0 (punto de venta para tiendas)'};

  @override
  Future<LookupResult> fetch(String barcode) async {
    var allFailed = true;
    for (final store in stores) {
      final outcome = await _query(store, barcode);
      if (!outcome.failed) allFailed = false;
      final item = outcome.item;
      if (item != null) return LookupResult(item: item);
    }
    return LookupResult(offline: allFailed);
  }

  Future<({CatalogItem? item, bool failed})> _query(VtexStore store, String barcode) async {
    try {
      final uri = Uri.https(store.host, '/api/catalog_system/pub/products/search', {
        'fq': 'alternateIds_Ean:$barcode',
      });
      final response = await _client.get(uri, headers: _headers).timeout(timeout);
      // VTEX responde 200, o 206 cuando pagina; cualquier otra cosa es un fallo.
      if (response.statusCode != 200 && response.statusCode != 206) return (item: null, failed: true);

      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! List) return (item: null, failed: true);

      for (final product in body) {
        if (product is! Map) continue;
        final item = await _parse(store, product, barcode);
        if (item != null) return (item: item, failed: false);
      }
      return (item: null, failed: false);
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

  Future<CatalogItem?> _parse(VtexStore store, Map product, String barcode) async {
    final name = _text(product['productName']);
    if (name == null) return null;

    // Solo se acepta un producto cuyo SKU lleve exactamente este código.
    final items = product['items'];
    if (items is! List) return null;
    final sku = items.whereType<Map>().where((i) => _text(i['ean']) == barcode).firstOrNull;
    if (sku == null) return null;

    final imageUrl = _firstImageUrl(sku);
    return CatalogItem(
      source: store.name,
      name: name,
      barcode: barcode,
      brand: _text(product['brand']),
      categoryHint: _lastCategory(product['categories']),
      description: _shorten(_text(product['description'])),
      imageUrl: imageUrl,
      imageBytes: imageUrl == null ? null : await _downloadThumbnail(imageUrl),
    );
  }

  /// Primero la versión de 300 px (pesa unos 8 KB en vez de cientos); si la
  /// tienda no la ofrece, la imagen original.
  Future<Uint8List?> _downloadThumbnail(String url) async {
    final small = url.replaceFirstMapped(
      RegExp(r'/arquivos/ids/(\d+)/'),
      (m) => '/arquivos/ids/${m[1]}-300-300/',
    );
    final bytes = await downloadImage(_client, small, timeout: timeout, maxBytes: maxImageBytes, headers: _headers);
    if (bytes != null || small == url) return bytes;
    return downloadImage(_client, url, timeout: timeout, maxBytes: maxImageBytes, headers: _headers);
  }

  static String? _firstImageUrl(Map sku) {
    final images = sku['images'];
    if (images is! List) return null;
    for (final image in images) {
      if (image is Map) {
        final url = _text(image['imageUrl']);
        if (url != null) return url;
      }
    }
    return null;
  }

  /// De `['/Higiene y Belleza/Cuidado Corporal/Desodorantes/', ...]` toma la
  /// categoría más específica: "Desodorantes".
  static String? _lastCategory(Object? categories) {
    if (categories is! List || categories.isEmpty) return null;
    final first = _text(categories.first);
    if (first == null) return null;
    final parts = first.split('/').where((s) => s.trim().isNotEmpty).toList();
    return parts.isEmpty ? null : parts.last.trim();
  }

  static String? _shorten(String? text) {
    if (text == null) return null;
    return text.length <= 400 ? text : '${text.substring(0, 400)}...';
  }

  static String? _text(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  @override
  void close() => _client.close();
}

/// Consulta varias fuentes A LA VEZ y devuelve la de mayor prioridad (la
/// primera de la lista) que conozca el código. Así la espera es la de la
/// fuente más lenta que haga falta, no la suma de todas: una base abierta con
/// un pico de lentitud no retrasa a las demás. Solo se marca "sin internet"
/// si NINGUNA pudo responder.
class ChainedLookup implements RemoteLookup {
  ChainedLookup(this._sources);

  final List<RemoteLookup> _sources;

  @override
  Future<LookupResult> fetch(String barcode) async {
    // Todas arrancan ya. Una fuente que falle de forma inesperada cuenta como
    // "sin respuesta" y nunca deja un error suelto.
    final pending = [
      for (final source in _sources)
        source.fetch(barcode).catchError((Object _) => const LookupResult(offline: true)),
    ];

    var allOffline = true;
    for (final future in pending) {
      final result = await future;
      if (result.item != null) return result;
      if (!result.offline) allOffline = false;
    }
    return LookupResult(offline: allOffline);
  }

  @override
  void close() {
    for (final source in _sources) {
      source.close();
    }
  }
}
