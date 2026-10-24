import 'package:flutter/services.dart';

/// Filtro para campos donde se escribe dinero: solo dígitos y un separador
/// decimal (punto o coma), con un máximo de dos decimales (centavos) y siete
/// dígitos enteros. Cualquier otra tecla (letras, signos, un segundo punto, un
/// tercer decimal) se ignora y el campo conserva lo que ya tenía.
class MoneyInputFormatter extends TextInputFormatter {
  const MoneyInputFormatter();

  static final _valid = RegExp(r'^\d{0,7}([.,]\d{0,2})?$');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return _valid.hasMatch(newValue.text) ? newValue : oldValue;
  }
}
