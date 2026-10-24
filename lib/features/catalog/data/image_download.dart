import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Descarga una miniatura. Devuelve `null` si falla, tarda demasiado, es muy
/// grande o no es una imagen: en esos casos el producto se sugiere sin imagen
/// (no es un error). Solo se aceptan direcciones https.
Future<Uint8List?> downloadImage(
  http.Client client,
  String url, {
  required Duration timeout,
  required int maxBytes,
  Map<String, String> headers = const {},
}) async {
  try {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https') return null;
    final response = await client.get(uri, headers: headers).timeout(timeout);
    if (response.statusCode != 200) return null;
    if (!(response.headers['content-type'] ?? '').startsWith('image/')) return null;
    if (response.bodyBytes.isEmpty || response.bodyBytes.length > maxBytes) return null;
    return response.bodyBytes;
  } on TimeoutException {
    return null;
  } on SocketException {
    return null;
  } on http.ClientException {
    return null;
  } on FormatException {
    return null;
  }
}
