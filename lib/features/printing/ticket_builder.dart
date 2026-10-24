import '../../core/format/formatters.dart';
import '../../core/money.dart';
import '../../models/sale.dart';

enum TicketAlign { left, center, right }

/// Un renglón del ticket. Los renglones de dos columnas (producto ... precio)
/// ya vienen armados con espacios; la alineación solo sirve para centrar o
/// alinear a la derecha textos sueltos.
class TicketLine {
  const TicketLine(this.text, {this.align = TicketAlign.left, this.bold = false, this.large = false});

  final String text;
  final TicketAlign align;
  final bool bold;

  /// Doble ancho y alto (en la impresora caben la mitad de caracteres).
  final bool large;
}

/// Datos del negocio que van en el encabezado y el pie del ticket.
class TicketHeader {
  const TicketHeader({required this.name, this.address, this.phone, this.footer});

  final String name;
  final String? address;
  final String? phone;
  final String? footer;
}

/// Parte [text] en renglones de a lo más [width] caracteres, sin cortar
/// palabras (salvo que una sola palabra exceda el ancho).
List<String> wrapText(String text, int width) {
  final lines = <String>[];
  var current = '';
  for (final rawWord in text.trim().split(RegExp(r'\s+'))) {
    if (rawWord.isEmpty) continue;
    var word = rawWord;
    while (word.length > width) {
      if (current.isNotEmpty) {
        lines.add(current);
        current = '';
      }
      lines.add(word.substring(0, width));
      word = word.substring(width);
    }
    if (current.isEmpty) {
      current = word;
    } else if (current.length + 1 + word.length <= width) {
      current = '$current $word';
    } else {
      lines.add(current);
      current = word;
    }
  }
  if (current.isNotEmpty) lines.add(current);
  return lines;
}

/// "izquierda ........ derecha" en exactamente [width] caracteres. Si no caben,
/// la izquierda se recorta (la derecha, normalmente un monto, nunca).
String twoColumns(String left, String right, int width) {
  final room = width - right.length - 1;
  final l = left.length > room ? left.substring(0, room < 0 ? 0 : room) : left;
  return l + ' ' * (width - l.length - right.length) + right;
}

String _money(int cents) => formatCurrency(fromCents(cents));

/// Arma el ticket de una venta para papel de [columns] caracteres de ancho
/// (48 en una térmica de 80 mm). Es una función pura: la misma venta da el
/// mismo ticket, así se puede probar sin impresora y mostrar en pantalla.
List<TicketLine> buildSaleTicket(
  Sale sale,
  TicketHeader header, {
  int columns = 48,
  bool reprint = false,
}) {
  final divider = TicketLine('-' * columns);
  final lines = <TicketLine>[];

  // --- Encabezado
  final fitsLarge = header.name.length <= columns ~/ 2;
  if (fitsLarge) {
    lines.add(TicketLine(header.name, align: TicketAlign.center, bold: true, large: true));
  } else {
    for (final l in wrapText(header.name, columns)) {
      lines.add(TicketLine(l, align: TicketAlign.center, bold: true));
    }
  }
  for (final extra in [header.address, header.phone]) {
    if (extra == null || extra.trim().isEmpty) continue;
    for (final l in wrapText(extra, columns)) {
      lines.add(TicketLine(l, align: TicketAlign.center));
    }
  }
  if (reprint) lines.add(const TicketLine('*** REIMPRESION ***', align: TicketAlign.center, bold: true));
  lines.add(divider);

  // --- Datos de la venta
  lines.add(TicketLine(twoColumns(sale.receiptNumber, dateTimeFormat.format(sale.date), columns)));
  for (final text in ['Cajero: ${sale.cashierName}', 'Cliente: ${sale.customerName}']) {
    if (text.endsWith(': null')) continue;
    for (final l in wrapText(text, columns)) {
      lines.add(TicketLine(l));
    }
  }
  lines.add(divider);

  // --- Productos: nombre completo (en las líneas que haga falta) y debajo
  // "cantidad x precio ........ subtotal".
  for (final item in sale.items) {
    for (final l in wrapText(item.productName, columns)) {
      lines.add(TicketLine(l));
    }
    final qty = formatQuantity(item.quantity);
    lines.add(TicketLine(twoColumns('  $qty x ${_money(item.unitPriceCents)}', _money(item.subtotalCents), columns)));
  }
  lines.add(divider);

  // --- Total (en grande: la mitad de columnas)
  final articles = sale.items.fold<double>(0, (sum, item) => sum + item.quantity);
  lines.add(TicketLine('${formatQuantity(articles)} articulos'));
  lines.add(TicketLine(twoColumns('TOTAL', _money(sale.totalCents), columns ~/ 2), bold: true, large: true));
  lines.add(const TicketLine(''));

  // --- Pago
  lines.add(TicketLine('Pago: ${sale.paymentMethod.label}'));
  if (sale.tenderedCents != null) {
    lines.add(TicketLine(twoColumns('Recibido', _money(sale.tenderedCents!), columns)));
    if ((sale.changeCents ?? 0) > 0) {
      lines.add(TicketLine(twoColumns('Vuelto', _money(sale.changeCents!), columns), bold: true));
    }
  }
  if (sale.paymentMethod == PaymentMethod.credit) {
    lines.add(const TicketLine('Se cargo a la cuenta del cliente'));
  }
  if (sale.isVoided) {
    lines.add(divider);
    lines.add(const TicketLine('*** VENTA ANULADA ***', align: TicketAlign.center, bold: true));
  }

  // --- Pie
  lines.add(divider);
  final footer = (header.footer == null || header.footer!.trim().isEmpty) ? 'Gracias por su compra' : header.footer!;
  for (final l in wrapText(footer, columns)) {
    lines.add(TicketLine(l, align: TicketAlign.center));
  }
  return lines;
}

/// Ticket de prueba: sirve para ver el ancho, el corte y si salen bien los
/// acentos y la ñ en la impresora.
List<TicketLine> buildTestTicket(TicketHeader header, {int columns = 48}) {
  return [
    TicketLine(header.name, align: TicketAlign.center, bold: true, large: header.name.length <= columns ~/ 2),
    const TicketLine('PRUEBA DE IMPRESION', align: TicketAlign.center, bold: true),
    TicketLine('=' * columns),
    TicketLine('Ancho: $columns caracteres'),
    TicketLine('1234567890' * (columns ~/ 10) + '1234567890'.substring(0, columns % 10)),
    const TicketLine('Acentos: áéíóú ÁÉÍÓÚ ñ Ñ ü ¿? ¡!'),
    TicketLine(twoColumns('Total de ejemplo', _money(12345), columns)),
    const TicketLine('Si lees bien los acentos, activa "Imprimir acentos".'),
    TicketLine('=' * columns),
    const TicketLine('Si ves este ticket completo y cortado,', align: TicketAlign.center),
    const TicketLine('la impresora esta lista.', align: TicketAlign.center),
  ];
}
