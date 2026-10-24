import 'dart:typed_data';

import '../../models/sale.dart';
import '../../state/settings_provider.dart';
import 'escpos_encoder.dart';
import 'printer_transport.dart';
import 'ticket_builder.dart';

/// Crea la conexión a la impresora según la configuración (las pruebas
/// entregan una falsa).
typedef TransportFactory = PrinterTransport Function(PrinterMode mode, String target);

PrinterTransport _defaultTransport(PrinterMode mode, String target) {
  switch (mode) {
    case PrinterMode.windows:
      return WindowsSpoolerTransport(target);
    case PrinterMode.network:
      return NetworkPrinterTransport.parse(target);
    case PrinterMode.cups:
      return CupsTransport(target);
    case PrinterMode.none:
      throw PrintException('No hay una impresora configurada');
  }
}

/// Arma los tickets con los datos del negocio y la impresora configurada, y
/// los envía. Una falla al imprimir lanza [PrintException]: quien llama decide
/// qué hacer (la venta NUNCA debe perderse por un problema de la impresora).
class PrintService {
  PrintService(this._settings, {TransportFactory? transportFactory}) : _transportFactory = transportFactory ?? _defaultTransport;

  final SettingsProvider _settings;
  final TransportFactory _transportFactory;

  bool get isConfigured => _settings.hasPrinter;

  /// Caracteres por renglón del papel.
  int get columns => _settings.paperColumns;

  /// Se imprime solo al registrar cada venta (no hace falta pedirlo).
  bool get autoPrint => isConfigured && _settings.autoPrint;

  TicketHeader get _header => TicketHeader(
        name: _settings.businessName,
        address: _settings.ticketAddress,
        phone: _settings.ticketPhone,
        footer: _settings.ticketFooter,
      );

  /// El ticket de [sale] tal como saldrá (para verlo en pantalla).
  List<TicketLine> saleLines(Sale sale, {bool reprint = false}) =>
      buildSaleTicket(sale, _header, columns: _settings.paperColumns, reprint: reprint);

  List<TicketLine> testLines() => buildTestTicket(_header, columns: _settings.paperColumns);

  EscPosEncoder get _encoder => EscPosEncoder(accents: _settings.printAccents);

  Future<void> _send(Uint8List bytes) async {
    if (!isConfigured) throw PrintException('No hay una impresora configurada');
    final transport = _transportFactory(_settings.printerMode, _settings.printerTarget);
    try {
      await transport.send(bytes);
    } on PrintException {
      rethrow;
    } catch (e) {
      throw PrintException('No se pudo imprimir: $e');
    }
  }

  /// Imprime el ticket de una venta; en efectivo y si está activado, abre el cajón.
  Future<void> printSale(Sale sale, {bool reprint = false}) {
    final openDrawer = _settings.openDrawer && !reprint && sale.paymentMethod == PaymentMethod.cash && !sale.isVoided;
    return _send(_encoder.encode(saleLines(sale, reprint: reprint), openDrawer: openDrawer));
  }

  /// Imprime el ticket de prueba.
  Future<void> printTest() => _send(_encoder.encode(testLines()));
}
