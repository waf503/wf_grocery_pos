// Utilidades de texto para las etiquetas (tags) de producto.
//
// Los tags se derivan del nombre ("Coca-Cola Lata 355ml" → `coca cola lata
// 355ml`) más las etiquetas extra que escriba el usuario, siempre en
// minúsculas y sin acentos. Se guardan como texto separado por espacios en
// `products.tags` y sirven para sugerir nombres mientras se escribe.
//
// Los tags son SOLO TEXTO: las palabras con números ("355ml", "2l", "154")
// y las letras sueltas ("g") no sirven para encontrar un producto, así que
// no se guardan como tags (siguen formando parte del nombre).

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

/// `true` si [token] sirve como tag: texto de al menos dos letras, sin números.
bool isTagWord(String token) => token.length >= 2 && !RegExp(r'\d').hasMatch(token);

/// Palabras de [value] que sirven como tags (ver [isTagWord]).
List<String> tagWords(String value) => tokenize(value).where(isTagWord).toList();

/// Tags de un producto: palabras de texto del nombre + etiquetas extra, sin
/// repetir, unidas por espacios.
String buildTags(String name, {String extra = ''}) {
  final tags = <String>{...tagWords(name), ...tagWords(extra)};
  return tags.join(' ');
}

/// ¿El producto coincide con lo que el usuario escribió en el buscador?
///
/// Cada palabra escrita debe ser el COMIENZO de alguna palabra del nombre o
/// de las etiquetas (sin importar mayúsculas ni acentos): "pan" encuentra
/// "Pan de caja" y "Panadería", pero NO "Company" (que solo lo trae por dentro).
/// El orden de las palabras no importa ("cola coca" encuentra "Coca-Cola").
///
/// Si lo escrito son solo dígitos, también coincide con una parte del código
/// de barras (para buscar por los últimos números).
bool matchesProductQuery(String query, {required String name, String tags = '', String? barcode}) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return true;

  if (barcode != null && RegExp(r'^\d+$').hasMatch(trimmed) && barcode.contains(trimmed)) return true;

  final typed = tokenize(trimmed);
  if (typed.isEmpty) return true; // solo signos: no se filtra nada

  final words = <String>{...tokenize(name), ...tokenize(tags)};
  return typed.every((word) => words.any((candidate) => candidate.startsWith(word)));
}
