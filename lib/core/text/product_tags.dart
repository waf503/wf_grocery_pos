// Utilidades de texto para las etiquetas (tags) de producto.
//
// Los tags se derivan del nombre ("Coca-Cola Lata 355ml" → `coca cola lata
// 355ml`) más las etiquetas extra que escriba el usuario, siempre en
// minúsculas y sin acentos. Se guardan como texto separado por espacios en
// `products.tags` y sirven para sugerir nombres mientras se escribe.

const _accents = {
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
  'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
  'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
  'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
  'ñ': 'n',
};

/// Minúsculas y sin acentos (para comparar "Azúcar" con "azucar").
String normalizeText(String value) {
  final lower = value.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_accents[char] ?? char);
  }
  return buffer.toString();
}

/// Palabras normalizadas de [value] (separa por cualquier cosa que no sea
/// letra o número: "Coca-Cola 355ml" → `[coca, cola, 355ml]`).
List<String> tokenize(String value) {
  return normalizeText(value)
      .split(RegExp(r'[^a-z0-9]+'))
      .where((token) => token.isNotEmpty)
      .toList();
}

/// Tags de un producto: palabras del nombre + etiquetas extra, sin repetir,
/// unidas por espacios.
String buildTags(String name, {String extra = ''}) {
  final tags = <String>{...tokenize(name), ...tokenize(extra)};
  return tags.join(' ');
}
