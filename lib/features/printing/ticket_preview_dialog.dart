import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/sale.dart';
import '../../shared/widgets/feedback_alert.dart';
import 'print_service.dart';
import 'printer_transport.dart';
import 'ticket_builder.dart';

/// Muestra el ticket tal como saldrá. Con impresora configurada ofrece
/// "Imprimir" ([onPrint]); sin ella, sirve para consultarlo en pantalla.
Future<void> showTicketDialog(
  BuildContext context, {
  required String title,
  required List<TicketLine> lines,
  required int columns,
  Future<void> Function()? onPrint,
  String printLabel = 'Imprimir',
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: _TicketPaper(lines: lines, columns: columns),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cerrar')),
        if (onPrint != null)
          FilledButton.icon(
            onPressed: () async {
              await onPrint();
            },
            icon: const Icon(Icons.print_outlined),
            label: Text(printLabel),
          ),
      ],
    ),
  );
}

/// El ticket dibujado como papel: letra de ancho fijo, para que se vea igual
/// que en la impresora.
class _TicketPaper extends StatelessWidget {
  const _TicketPaper({required this.lines, required this.columns});

  final List<TicketLine> lines;
  final int columns;

  @override
  Widget build(BuildContext context) {
    const fontSize = 13.0;
    final base = const TextStyle(fontFamily: 'Consolas', fontFamilyFallback: ['Courier New', 'monospace'], fontSize: fontSize, height: 1.25, color: Colors.black87);
    // Cada carácter mide ~0.6 del tamaño de la letra.
    final width = columns * fontSize * 0.6 + 24;

    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black26),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final line in lines)
            Text(
              line.text.isEmpty ? ' ' : line.text,
              textAlign: switch (line.align) {
                TicketAlign.left => TextAlign.left,
                TicketAlign.center => TextAlign.center,
                TicketAlign.right => TextAlign.right,
              },
              softWrap: false,
              overflow: TextOverflow.clip,
              style: base.copyWith(
                fontWeight: line.bold ? FontWeight.bold : FontWeight.normal,
                fontSize: line.large ? fontSize * 1.6 : fontSize,
              ),
            ),
        ],
      ),
    );
  }
}

/// Imprime el ticket de [sale] avisando el resultado. Una falla de la
/// impresora NO afecta la venta (ya está guardada): solo se avisa y queda la
/// opción de reimprimir desde Ventas.
Future<void> printSaleWithFeedback(
  BuildContext context,
  PrintService service,
  Sale sale, {
  bool reprint = false,
}) async {
  try {
    await service.printSale(sale, reprint: reprint);
    if (context.mounted) {
      FeedbackAlert.show(context, type: FeedbackType.success, title: 'Ticket impreso', message: sale.receiptNumber);
    }
  } on PrintException catch (e) {
    if (context.mounted) {
      FeedbackAlert.show(
        context,
        type: FeedbackType.warning,
        title: 'No se pudo imprimir el ticket',
        message: '${e.message}\nLa venta quedó registrada: puedes reimprimirlo desde Ventas.',
        duration: const Duration(seconds: 6),
      );
    }
  }
}

/// Ver el ticket de [sale] y, con impresora configurada, (re)imprimirlo.
Future<void> showSaleTicket(BuildContext context, Sale sale, {bool reprint = false}) {
  final service = context.read<PrintService?>();
  if (service == null) return Future.value();
  return showTicketDialog(
    context,
    title: 'Ticket ${sale.receiptNumber}',
    lines: service.saleLines(sale, reprint: reprint),
    columns: service.columns,
    onPrint: service.isConfigured ? () => printSaleWithFeedback(context, service, sale, reprint: reprint) : null,
    printLabel: reprint ? 'Reimprimir' : 'Imprimir',
  );
}
