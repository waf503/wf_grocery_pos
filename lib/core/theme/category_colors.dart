import 'package:flutter/material.dart';

/// Paleta amplia de colores para identificar categorías (valores ARGB):
/// 17 tonos de Material en tres intensidades, 51 colores en total. Van
/// ordenados para que los primeros sean los más distintos entre sí (primero
/// los 17 matices en tono medio, luego los claros y al final los oscuros);
/// así las primeras categorías que se crean no se parecen entre ellas.
final List<int> categoryColorPalette = [
  for (final shade in const [600, 400, 800])
    for (final swatch in _swatches) swatch[shade]!.toARGB32(),
];

const List<MaterialColor> _swatches = [
  Colors.red,
  Colors.orange,
  Colors.amber,
  Colors.lime,
  Colors.lightGreen,
  Colors.green,
  Colors.teal,
  Colors.cyan,
  Colors.lightBlue,
  Colors.blue,
  Colors.indigo,
  Colors.deepPurple,
  Colors.purple,
  Colors.pink,
  Colors.deepOrange,
  Colors.brown,
  Colors.blueGrey,
];

/// Color neutro para categorías sin color asignado.
const int defaultCategoryColor = 0xFF78909C;

Color categoryColorOf(int? value) => Color(value ?? defaultCategoryColor);

/// Convierte "#43A047" / "43a047" a ARGB opaco; `null` si no es un hex válido.
int? parseHexColor(String text) {
  final hex = text.trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
  return 0xFF000000 | int.parse(hex, radix: 16);
}

String toHexColor(int value) =>
    '#${(value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
