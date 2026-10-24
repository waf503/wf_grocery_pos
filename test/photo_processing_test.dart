import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:wf_grocery_pos/core/image/photo_processing.dart';

/// Foto sintética con un degradado (parecida a una foto real: no se comprime a nada).
Uint8List _photo(int width, int height, {bool png = false}) {
  final image = img.Image(width: width, height: height);
  for (final pixel in image) {
    pixel
      ..r = (pixel.x * 255 / width).round()
      ..g = (pixel.y * 255 / height).round()
      ..b = ((pixel.x + pixel.y) % 256);
  }
  return Uint8List.fromList(png ? img.encodePng(image) : img.encodeJpg(image, quality: 95));
}

void main() {
  test('una foto de webcam 640x480 queda cuadrada de 300 px y ligera', () {
    final source = _photo(640, 480);
    final result = prepareProductPhoto(source);

    final decoded = img.decodeJpg(result)!;
    expect(decoded.width, 300);
    expect(decoded.height, 300);
    expect(result.length, lessThan(source.length));
    expect(result.length, lessThan(100 * 1024));
  });

  test('recorta el centro: una foto vertical también queda cuadrada', () {
    final result = prepareProductPhoto(_photo(480, 640));
    final decoded = img.decodeJpg(result)!;
    expect((decoded.width, decoded.height), (300, 300));
  });

  test('no amplía una foto más pequeña que el tamaño pedido', () {
    final result = prepareProductPhoto(_photo(200, 100));
    final decoded = img.decodeJpg(result)!;
    expect((decoded.width, decoded.height), (100, 100)); // recorte cuadrado, sin ampliar
  });

  test('acepta PNG y devuelve JPEG', () {
    final result = prepareProductPhoto(_photo(640, 480, png: true));
    expect(img.decodeJpg(result), isNotNull);
  });

  test('un archivo que no es imagen lanza FormatException', () {
    expect(
      () => prepareProductPhoto(Uint8List.fromList([1, 2, 3, 4, 5])),
      throwsA(isA<FormatException>()),
    );
  });

  test('la versión asíncrona da el mismo resultado', () async {
    final source = _photo(640, 480);
    expect(await prepareProductPhotoAsync(source), prepareProductPhoto(source));
  });
}
