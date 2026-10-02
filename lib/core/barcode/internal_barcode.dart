// Códigos de barras internos (para productos o packs sin código físico).
//
// Se generan en formato EAN-13 con el prefijo "200": los prefijos 20–29 de
// GS1 están reservados para uso interno de cada tienda, así que nunca chocan
// con el código de un producto de fábrica. El resto es un consecutivo, y el
// último dígito es el verificador estándar (el lector de códigos lo valida).

const internalBarcodePrefix = '200';

/// Dígito verificador EAN-13 para los 12 primeros dígitos.
int ean13CheckDigit(String twelveDigits) {
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    final digit = int.parse(twelveDigits[i]);
    sum += i.isEven ? digit : digit * 3;
  }
  return (10 - sum % 10) % 10;
}

/// EAN-13 interno para el consecutivo [sequence] (1 → `2000000000015`).
String buildInternalBarcode(int sequence) {
  final body = '$internalBarcodePrefix${sequence.toString().padLeft(9, '0')}';
  return '$body${ean13CheckDigit(body)}';
}

/// Siguiente consecutivo libre dado los códigos que ya existen: toma el
/// mayor consecutivo interno usado y suma 1.
int nextInternalSequence(Iterable<String?> existingBarcodes) {
  var max = 0;
  for (final code in existingBarcodes) {
    if (code == null || code.length != 13 || !code.startsWith(internalBarcodePrefix)) continue;
    final sequence = int.tryParse(code.substring(3, 12));
    if (sequence != null && sequence > max) max = sequence;
  }
  return max + 1;
}
