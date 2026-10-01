import 'dart:math';

final Random _random = Random();

/// Generador simple de identificador único (suficiente para un solo
/// dispositivo). Combina hora + un número aleatorio porque el reloj de
/// Windows no siempre tiene resolución de microsegundo real: insertar
/// varias filas en el mismo instante (como hace el seeder) puede repetir
/// el mismo `microsecondsSinceEpoch` sin la parte aleatoria — esto ya nos
/// pasó una vez con el seed de productos. Cuando conectemos con el
/// backend, esto se reemplaza por un UUID v4 real de la librería `uuid`.
String generateId(String prefix) {
  final now = DateTime.now().microsecondsSinceEpoch;
  final randomSuffix = _random.nextInt(1 << 32);
  return '${prefix}_${now}_$randomSuffix';
}
