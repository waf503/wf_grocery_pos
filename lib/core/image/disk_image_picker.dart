import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

/// Peso máximo de una imagen elegida del disco: una foto de cámara de 12 MP
/// pesa unos 5 MB; más de esto casi seguro no es una foto de producto.
const maxPickedImageBytes = 25 * 1024 * 1024;

/// Abre el selector de archivos del sistema para escoger una imagen del disco
/// (JPG, PNG, WebP, BMP o GIF). Devuelve sus bytes sin procesar, o `null` si el
/// usuario cancela. Lanza [FormatException] si pesa demasiado.
///
/// Usa el cuadro de diálogo propio de cada sistema (Windows, Linux...), sin
/// programas externos.
Future<Uint8List?> pickImageFromDisk() async {
  const images = XTypeGroup(
    label: 'Imágenes',
    extensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif'],
  );
  final file = await openFile(acceptedTypeGroups: const [images]);
  if (file == null) return null;
  if (await file.length() > maxPickedImageBytes) {
    throw const FormatException('La imagen pesa demasiado.');
  }
  return file.readAsBytes();
}
