import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Guarda el PIN como un hash con sal (PBKDF2-HMAC-SHA256), nunca en claro.
/// Un PIN corto se puede adivinar por fuerza bruta si alguien copia el archivo
/// de la base de datos; la sal y las iteraciones lo encarecen, y el bloqueo por
/// intentos fallidos (ver `AuthProvider`) cubre el uso normal en pantalla.
class PinHasher {
  const PinHasher({this.iterations = 30000});

  final int iterations;

  static final Random _random = Random.secure();

  String newSalt() => base64Url.encode(List<int>.generate(16, (_) => _random.nextInt(256)));

  String hash(String pin, String salt) {
    final hmac = Hmac(sha256, utf8.encode(pin));
    final saltBytes = base64Url.decode(salt);
    // PBKDF2 con un solo bloque de 32 bytes (el largo de SHA-256).
    var u = hmac.convert([...saltBytes, 0, 0, 0, 1]).bytes;
    final result = List<int>.from(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < result.length; j++) {
        result[j] ^= u[j];
      }
    }
    return base64Url.encode(result);
  }

  /// Comparación en tiempo constante.
  bool verify(String pin, String salt, String expectedHash) {
    final actual = hash(pin, salt);
    if (actual.length != expectedHash.length) return false;
    var diff = 0;
    for (var i = 0; i < actual.length; i++) {
      diff |= actual.codeUnitAt(i) ^ expectedHash.codeUnitAt(i);
    }
    return diff == 0;
  }
}
