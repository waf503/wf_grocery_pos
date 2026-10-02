import 'package:flutter_test/flutter_test.dart';
import 'package:wf_grocery_pos/core/barcode/internal_barcode.dart';

void main() {
  test('el dígito verificador coincide con EAN-13 conocidos', () {
    expect(ean13CheckDigit('400638133393'), 1); // 4006381333931
    expect(ean13CheckDigit('590123412345'), 7); // 5901234123457
  });

  test('genera EAN-13 internos consecutivos con prefijo 200', () {
    expect(buildInternalBarcode(1), '2000000000015');
    expect(buildInternalBarcode(1).length, 13);
    expect(nextInternalSequence([]), 1);
    expect(nextInternalSequence([null, '7501055300075', buildInternalBarcode(41)]), 42);
  });
}
