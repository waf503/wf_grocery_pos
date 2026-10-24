import 'dart:typed_data';

import 'ticket_builder.dart';

/// Traduce un ticket a comandos ESC/POS, el lenguaje de casi todas las
/// impresoras térmicas de tickets.
///
/// Los acentos dependen de la tabla de caracteres de la impresora: con
/// [accents] en falso se imprimen sin acento (á → a, ñ → n), que funciona en
/// cualquier impresora; en verdadero se selecciona la tabla CP858 (la de
/// español/Europa occidental) y se envían los acentos y la ñ.
class EscPosEncoder {
  const EscPosEncoder({this.accents = false});

  final bool accents;

  /// Número de la tabla CP858 en el comando `ESC t` (el mismo en Epson y en la
  /// mayoría de las compatibles).
  static const int cp858Table = 19;

  Uint8List encode(
    List<TicketLine> lines, {
    bool cut = true,
    bool openDrawer = false,
    int feedLines = 4,
  }) {
    final out = BytesBuilder();
    out.add(const [0x1B, 0x40]); // ESC @: reinicia la impresora
    if (accents) out.add(const [0x1B, 0x74, cp858Table]); // ESC t n: tabla de caracteres
    // ESC p m t1 t2: pulso al cajón de dinero (abre el cajón).
    if (openDrawer) out.add(const [0x1B, 0x70, 0x00, 0x19, 0xFA]);

    for (final line in lines) {
      out.add([0x1B, 0x61, switch (line.align) { TicketAlign.left => 0, TicketAlign.center => 1, TicketAlign.right => 2 }]);
      out.add([0x1B, 0x45, line.bold ? 1 : 0]); // negrita
      out.add([0x1D, 0x21, line.large ? 0x11 : 0x00]); // doble ancho y alto
      out.add(encodeText(line.text));
      out.addByte(0x0A);
    }

    // Deja todo como estaba, avanza el papel y corta.
    out.add(const [0x1B, 0x61, 0x00, 0x1B, 0x45, 0x00, 0x1D, 0x21, 0x00]);
    out.add([0x1B, 0x64, feedLines]); // ESC d n: avanza n renglones
    if (cut) out.add(const [0x1D, 0x56, 0x42, 0x00]); // GS V B 0: avanza y corta
    return out.toBytes();
  }

  /// Texto en los bytes de la impresora (sin el salto de renglón).
  Uint8List encodeText(String text) {
    final bytes = <int>[];
    for (final rune in text.runes) {
      if (rune < 0x80) {
        bytes.add(rune);
      } else if (accents && _cp858[rune] != null) {
        bytes.add(_cp858[rune]!);
      } else {
        bytes.addAll((_ascii[rune] ?? '?').codeUnits);
      }
    }
    return Uint8List.fromList(bytes);
  }
}

/// Letras del español (y algunas comunes) en la tabla CP858.
const Map<int, int> _cp858 = {
  0x00E1: 0xA0, // á
  0x00E9: 0x82, // é
  0x00ED: 0xA1, // í
  0x00F3: 0xA2, // ó
  0x00FA: 0xA3, // ú
  0x00F1: 0xA4, // ñ
  0x00D1: 0xA5, // Ñ
  0x00FC: 0x81, // ü
  0x00DC: 0x9A, // Ü
  0x00C1: 0xB5, // Á
  0x00C9: 0x90, // É
  0x00CD: 0xD6, // Í
  0x00D3: 0xE0, // Ó
  0x00DA: 0xE9, // Ú
  0x00BF: 0xA8, // ¿
  0x00A1: 0xAD, // ¡
  0x00B0: 0xF8, // °
  0x00E0: 0x85, // à
  0x00E8: 0x8A, // è
  0x00EC: 0x8D, // ì
  0x00F2: 0x95, // ò
  0x00F9: 0x97, // ù
  0x00E7: 0x87, // ç
  0x00C7: 0x80, // Ç
  0x20AC: 0xD5, // €
};

/// Reemplazo sin acentos para cuando no se usa la tabla de caracteres.
const Map<int, String> _ascii = {
  0x00E1: 'a', 0x00E0: 'a', 0x00E4: 'a', 0x00E2: 'a',
  0x00E9: 'e', 0x00E8: 'e', 0x00EB: 'e', 0x00EA: 'e',
  0x00ED: 'i', 0x00EC: 'i', 0x00EF: 'i', 0x00EE: 'i',
  0x00F3: 'o', 0x00F2: 'o', 0x00F6: 'o', 0x00F4: 'o',
  0x00FA: 'u', 0x00F9: 'u', 0x00FC: 'u', 0x00FB: 'u',
  0x00F1: 'n', 0x00E7: 'c',
  0x00C1: 'A', 0x00C0: 'A', 0x00C4: 'A', 0x00C2: 'A',
  0x00C9: 'E', 0x00C8: 'E', 0x00CB: 'E', 0x00CA: 'E',
  0x00CD: 'I', 0x00CC: 'I', 0x00CF: 'I', 0x00CE: 'I',
  0x00D3: 'O', 0x00D2: 'O', 0x00D6: 'O', 0x00D4: 'O',
  0x00DA: 'U', 0x00D9: 'U', 0x00DC: 'U', 0x00DB: 'U',
  0x00D1: 'N', 0x00C7: 'C',
  0x00BF: '?', 0x00A1: '!', 0x00B0: 'o', 0x20AC: 'EUR',
  0x2018: "'", 0x2019: "'", 0x201C: '"', 0x201D: '"', 0x2013: '-', 0x2014: '-',
};
