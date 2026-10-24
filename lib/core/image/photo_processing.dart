import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Prepara una foto para usarla como miniatura de producto: la recorta a un
/// CUADRADO centrado, la reduce a [size] px (sin ampliarla si ya es más
/// pequeña) y la guarda como JPEG comprimido. Una foto de webcam de varios
/// cientos de KB queda en unos 15–30 KB, parecida a las miniaturas que se
/// descargan de internet, y se guarda igual en la base de datos.
///
/// Lanza [FormatException] si [source] no es una imagen que se pueda leer.
Uint8List prepareProductPhoto(Uint8List source, {int size = 300, int quality = 85}) {
  // El decodificador puede fallar de varias formas con datos corruptos: todas
  // se reportan igual, como una imagen ilegible.
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(source);
  } catch (_) {
    throw const FormatException('No se pudo leer la imagen.');
  }
  if (decoded == null) throw const FormatException('No se pudo leer la imagen.');

  final side = math.min(decoded.width, decoded.height);
  final square = img.copyCrop(
    decoded,
    x: (decoded.width - side) ~/ 2,
    y: (decoded.height - side) ~/ 2,
    width: side,
    height: side,
  );
  final resized = side > size
      ? img.copyResize(square, width: size, height: size, interpolation: img.Interpolation.average)
      : square;
  return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
}

/// Igual que [prepareProductPhoto], pero en otro hilo para no congelar la
/// pantalla mientras se decodifica la foto.
Future<Uint8List> prepareProductPhotoAsync(Uint8List source) => compute(prepareProductPhoto, source);
