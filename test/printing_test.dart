import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:wf_grocery_pos/core/database/app_database.dart';
import 'package:wf_grocery_pos/features/printing/escpos_encoder.dart';
import 'package:wf_grocery_pos/features/printing/print_service.dart';
import 'package:wf_grocery_pos/features/printing/printer_transport.dart';
import 'package:wf_grocery_pos/features/printing/ticket_builder.dart';
import 'package:wf_grocery_pos/features/settings/data/settings_repository.dart';
import 'package:wf_grocery_pos/models/sale.dart';
import 'package:wf_grocery_pos/state/settings_provider.dart';

Sale _sale({
  PaymentMethod method = PaymentMethod.cash,
  int? tendered = 500,
  int? change = 430,
  String? cashier = 'Ana',
  String? customer,
  bool voided = false,
  List<SaleItem>? items,
}) {
  return Sale(
    id: 'v1',
    number: 123,
    date: DateTime(2026, 3, 5, 14, 30),
    totalCents: 70,
    paymentMethod: method,
    tenderedCents: tendered,
    changeCents: change,
    cashierName: cashier,
    customerName: customer,
    status: voided ? SaleStatus.voided : SaleStatus.completed,
    items: items ??
        [
          SaleItem(productName: 'Galleta Oreo 54 g', quantity: 2, unitPriceCents: 35, unitCostCents: 20, subtotalCents: 70),
        ],
  );
}

const _header = TicketHeader(
  name: 'Tienda Doña Rosa',
  address: 'Calle Principal #12, Santa Ana',
  phone: 'Tel. 2222-3333',
  footer: 'Vuelva pronto',
);

/// Impresora falsa: guarda lo que le llegó, o falla.
class _FakeTransport implements PrinterTransport {
  _FakeTransport({this.error});

  final Object? error;
  final List<Uint8List> sent = [];

  @override
  Future<void> send(Uint8List data) async {
    if (error != null) throw error!;
    sent.add(data);
  }
}

List<int> _find(Uint8List bytes, List<int> pattern) {
  final hits = <int>[];
  for (var i = 0; i <= bytes.length - pattern.length; i++) {
    var match = true;
    for (var j = 0; j < pattern.length; j++) {
      if (bytes[i + j] != pattern[j]) {
        match = false;
        break;
      }
    }
    if (match) hits.add(i);
  }
  return hits;
}

void main() {
  setUpAll(() => initializeDateFormatting('es_MX'));

  group('armado del ticket', () {
    test('ningún renglón se pasa del ancho del papel (80 mm = 48 y 58 mm = 32)', () {
      for (final columns in [48, 42, 32]) {
        final sale = _sale(
          customer: 'María Fernanda de los Ángeles',
          items: [
            SaleItem(
              productName: 'Desodorante Nivea Derma Control tono uniforme roll on femenino - 50 ml',
              quantity: 12.5,
              unitPriceCents: 1999,
              unitCostCents: 1000,
              subtotalCents: 24988,
            ),
          ],
        );
        for (final line in buildSaleTicket(sale, _header, columns: columns)) {
          final limit = line.large ? columns ~/ 2 : columns;
          expect(line.text.length, lessThanOrEqualTo(limit), reason: '"${line.text}" con $columns columnas');
        }
      }
    });

    test('muestra el nombre COMPLETO del producto, en varios renglones si hace falta', () {
      const name = 'Desodorante Nivea Derma Control tono uniforme roll on femenino - 50 ml';
      final lines = buildSaleTicket(
        _sale(items: [SaleItem(productName: name, quantity: 1, unitPriceCents: 500, unitCostCents: 1, subtotalCents: 500)]),
        _header,
        columns: 32,
      ).map((l) => l.text).toList();

      // Los renglones del producto, unidos, dan el nombre completo.
      final start = lines.indexWhere((l) => l.startsWith('Desodorante'));
      final productLines = lines.sublist(start, lines.indexWhere((l) => l.trimLeft().startsWith('1 x')));
      expect(productLines.length, greaterThan(1));
      expect(productLines.join(' '), name);
    });

    test('lleva folio, fecha, cajero, productos, total, pago, recibido y vuelto', () {
      final text = buildSaleTicket(_sale(), _header).map((l) => l.text).join('\n');
      expect(text, contains('V-000123'));
      expect(text, contains('05/03/2026 14:30'));
      expect(text, contains('Cajero: Ana'));
      expect(text, contains('Galleta Oreo 54 g'));
      expect(text, contains(r'2 x $0.35'));
      expect(text, contains(r'$0.70'));
      expect(text, contains('Pago: Efectivo'));
      expect(text, contains(r'Recibido'));
      expect(text, contains(r'$5.00'));
      expect(text, contains('Vuelto'));
      expect(text, contains(r'$4.30'));
      expect(text, contains('Vuelva pronto'));
      expect(text, isNot(contains('REIMPRESION')));
    });

    test('encabezado con nombre, dirección y teléfono; pie por defecto si no hay mensaje', () {
      final text = buildSaleTicket(_sale(), const TicketHeader(name: 'Mi Tienda')).map((l) => l.text).join('\n');
      expect(text, contains('Mi Tienda'));
      expect(text, contains('Gracias por su compra'));

      final withInfo = buildSaleTicket(_sale(), _header).map((l) => l.text).join('\n');
      expect(withInfo, contains('Calle Principal #12, Santa Ana'));
      expect(withInfo, contains('Tel. 2222-3333'));
    });

    test('el pago exacto no muestra vuelto; el fiado indica a quién se cargó', () {
      final exact = buildSaleTicket(_sale(tendered: 70, change: 0), _header).map((l) => l.text).join('\n');
      expect(exact, isNot(contains('Vuelto')));

      final credit = buildSaleTicket(
        _sale(method: PaymentMethod.credit, tendered: null, change: null, customer: 'Carmen'),
        _header,
      ).map((l) => l.text).join('\n');
      expect(credit, contains('Cliente: Carmen'));
      expect(credit, contains('Pago: Fiado'));
      expect(credit, contains('Se cargo a la cuenta del cliente'));
      expect(credit, isNot(contains('Recibido')));
    });

    test('reimpresión y venta anulada quedan marcadas', () {
      final reprint = buildSaleTicket(_sale(), _header, reprint: true).map((l) => l.text).join('\n');
      expect(reprint, contains('*** REIMPRESION ***'));

      final voided = buildSaleTicket(_sale(voided: true), _header).map((l) => l.text).join('\n');
      expect(voided, contains('*** VENTA ANULADA ***'));
    });

    test('la cantidad por peso se muestra sin ceros sobrantes', () {
      final text = buildSaleTicket(
        _sale(items: [SaleItem(productName: 'Frijoles', quantity: 2.5, unitPriceCents: 80, unitCostCents: 50, subtotalCents: 200)]),
        _header,
      ).map((l) => l.text).join('\n');
      expect(text, contains(r'2.5 x $0.80'));
    });

    test('wrapText no corta palabras y parte las que no caben; twoColumns alinea a la derecha', () {
      expect(wrapText('uno dos tres cuatro', 9), ['uno dos', 'tres', 'cuatro']);
      expect(wrapText('abcdefghij', 4), ['abcd', 'efgh', 'ij']);
      expect(wrapText('   ', 10), isEmpty);
      expect(twoColumns('Total', r'$1.00', 12), r'Total  $1.00');
      expect(twoColumns('Un nombre muy largo', r'$1.00', 12), r'Un nom $1.00');
    });
  });

  group('comandos ESC/POS', () {
    final simple = [const TicketLine('Hola'), const TicketLine('TOTAL', bold: true, large: true, align: TicketAlign.center)];

    test('reinicia la impresora al empezar y avanza y corta al terminar', () {
      final bytes = const EscPosEncoder().encode(simple);
      expect(bytes.sublist(0, 2), [0x1B, 0x40]); // ESC @
      expect(_find(bytes, [0x1D, 0x56, 0x42, 0x00]), isNotEmpty); // corte
      expect(bytes.sublist(bytes.length - 4), [0x1D, 0x56, 0x42, 0x00]);
      expect(_find(bytes, [0x1B, 0x64, 4]), isNotEmpty); // avanza 4 renglones
    });

    test('sin cortar no manda el comando de corte', () {
      final bytes = const EscPosEncoder().encode(simple, cut: false);
      expect(_find(bytes, [0x1D, 0x56]), isEmpty);
    });

    test('negrita, tamaño doble y alineación se aplican por renglón y se restablecen', () {
      final bytes = const EscPosEncoder().encode(simple);
      expect(_find(bytes, [0x1D, 0x21, 0x11]), isNotEmpty); // doble ancho y alto
      expect(_find(bytes, [0x1B, 0x45, 1]), isNotEmpty); // negrita
      expect(_find(bytes, [0x1B, 0x61, 1]), isNotEmpty); // centrado
      expect(_find(bytes, [0x1D, 0x21, 0x00]), isNotEmpty); // tamaño normal
    });

    test('sin acentos: á→a, ñ→n, ¿→? y nunca bytes fuera de ASCII', () {
      final bytes = const EscPosEncoder().encodeText('Año ¿Qué? ÁÉÍÓÚ ü');
      expect(String.fromCharCodes(bytes), 'Ano ?Que? AEIOU u');
      expect(bytes.every((b) => b < 0x80), isTrue);
      // Ni siquiera se selecciona tabla de caracteres.
      expect(_find(const EscPosEncoder().encode(simple), [0x1B, 0x74]), isEmpty);
    });

    test('con acentos: selecciona la tabla CP858 y manda los bytes de á é í ó ú ñ Ñ ¿ ¡', () {
      const encoder = EscPosEncoder(accents: true);
      expect(_find(encoder.encode(simple), [0x1B, 0x74, 19]), isNotEmpty);
      expect(encoder.encodeText('áéíóúñÑ¿¡'), [0xA0, 0x82, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA8, 0xAD]);
      expect(encoder.encodeText('ÁÉÍÓÚÜ'), [0xB5, 0x90, 0xD6, 0xE0, 0xE9, 0x9A]);
      // Lo que no existe en la tabla cae a su letra base o "?".
      expect(String.fromCharCodes(encoder.encodeText('ÿ')), '?');
    });

    test('abrir el cajón manda el pulso ESC p al principio', () {
      final withDrawer = const EscPosEncoder().encode(simple, openDrawer: true);
      expect(_find(withDrawer, [0x1B, 0x70, 0x00]), isNotEmpty);
      expect(_find(const EscPosEncoder().encode(simple), [0x1B, 0x70]), isEmpty);
    });
  });

  group('servicio de impresión', () {
    late AppDatabase db;
    late SettingsProvider settings;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      settings = SettingsProvider(DriftSettingsRepository(db));
      await settings.load();
    });
    tearDown(() async {
      settings.dispose();
      await db.close();
    });

    Future<void> configure({
      PrinterMode mode = PrinterMode.network,
      bool accents = false,
      bool autoPrint = true,
      bool drawer = false,
    }) =>
        settings.setPrinter(mode: mode, target: '192.168.1.50', columns: 48, accents: accents, autoPrint: autoPrint, openDrawer: drawer);

    test('sin impresora configurada no imprime y avisa', () async {
      final service = PrintService(settings, transportFactory: (_, _) => _FakeTransport());
      expect(service.isConfigured, isFalse);
      expect(service.autoPrint, isFalse);
      await expectLater(service.printSale(_sale()), throwsA(isA<PrintException>()));
    });

    test('imprime el ticket de la venta con los datos del negocio', () async {
      await settings.setBusinessName('Abarrotes Rosa');
      await settings.setTicketInfo(address: 'Calle 1', phone: '2222', footer: 'Gracias!');
      await configure();
      final printer = _FakeTransport();
      PrinterMode? usedMode;
      String? usedTarget;
      final service = PrintService(settings, transportFactory: (mode, target) {
        usedMode = mode;
        usedTarget = target;
        return printer;
      });

      await service.printSale(_sale());

      expect(usedMode, PrinterMode.network);
      expect(usedTarget, '192.168.1.50');
      expect(printer.sent, hasLength(1));
      final text = String.fromCharCodes(printer.sent.single);
      expect(text, contains('Abarrotes Rosa'));
      expect(text, contains('Calle 1'));
      expect(text, contains('V-000123'));
      expect(text, contains('Gracias!'));
    });

    test('el cajón solo se abre en ventas en efectivo (no en fiado, anuladas ni reimpresiones)', () async {
      await configure(drawer: true);
      final printer = _FakeTransport();
      final service = PrintService(settings, transportFactory: (_, _) => printer);
      const pulse = [0x1B, 0x70, 0x00];

      await service.printSale(_sale());
      await service.printSale(_sale(method: PaymentMethod.credit, tendered: null, change: null, customer: 'Carmen'));
      await service.printSale(_sale(voided: true));
      await service.printSale(_sale(), reprint: true);

      expect(_find(printer.sent[0], pulse), isNotEmpty);
      expect(_find(printer.sent[1], pulse), isEmpty);
      expect(_find(printer.sent[2], pulse), isEmpty);
      expect(_find(printer.sent[3], pulse), isEmpty);
    });

    test('con el cajón apagado nunca lo abre', () async {
      await configure(drawer: false);
      final printer = _FakeTransport();
      await PrintService(settings, transportFactory: (_, _) => printer).printSale(_sale());
      expect(_find(printer.sent.single, [0x1B, 0x70]), isEmpty);
    });

    test('respeta "imprimir acentos" y "imprimir automáticamente"', () async {
      await configure(accents: true, autoPrint: false);
      final printer = _FakeTransport();
      final service = PrintService(settings, transportFactory: (_, _) => printer);
      expect(service.isConfigured, isTrue);
      expect(service.autoPrint, isFalse); // hay impresora, pero no se imprime sola

      await service.printSale(_sale(items: [SaleItem(productName: 'Piña', quantity: 1, unitPriceCents: 70, unitCostCents: 1, subtotalCents: 70)]));
      expect(_find(printer.sent.single, [0x1B, 0x74, 19]), isNotEmpty);
      expect(_find(printer.sent.single, [0x50, 0x69, 0xA4, 0x61]), isNotEmpty); // "Piña" con ñ = 0xA4
    });

    test('una falla de la impresora llega como PrintException con un mensaje claro', () async {
      await configure();
      final failing = PrintService(
        settings,
        transportFactory: (_, _) => _FakeTransport(error: PrintException('No se pudo conectar con la impresora')),
      );
      await expectLater(
        failing.printSale(_sale()),
        throwsA(isA<PrintException>().having((e) => e.message, 'mensaje', contains('No se pudo conectar'))),
      );

      // Un error inesperado también se vuelve PrintException (nunca revienta la app).
      final weird = PrintService(settings, transportFactory: (_, _) => _FakeTransport(error: StateError('boom')));
      await expectLater(weird.printSale(_sale()), throwsA(isA<PrintException>()));
    });

    test('el ticket de prueba imprime el ancho y una línea con acentos', () async {
      await configure();
      final printer = _FakeTransport();
      await PrintService(settings, transportFactory: (_, _) => printer).printTest();
      final text = String.fromCharCodes(printer.sent.single);
      expect(text, contains('PRUEBA DE IMPRESION'));
      expect(text, contains('Ancho: 48 caracteres'));
    });
  });

  group('ajustes del ticket y la impresora', () {
    test('se guardan y se recuperan', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final settings = SettingsProvider(DriftSettingsRepository(db));
      addTearDown(settings.dispose);
      await settings.load();

      // De fábrica: sin impresora, 80 mm, sin acentos, imprime solo, sin cajón.
      expect(settings.hasPrinter, isFalse);
      expect(settings.printerMode, PrinterMode.none);
      expect(settings.paperColumns, 48);
      expect(settings.printAccents, isFalse);
      expect(settings.autoPrint, isTrue);
      expect(settings.openDrawer, isFalse);
      expect(settings.ticketAddress, isNull);

      await settings.setTicketInfo(address: ' Calle 1 ', phone: '2222', footer: '');
      await settings.setPrinter(
        mode: PrinterMode.windows,
        target: ' AON PR-200 ',
        columns: 42,
        accents: true,
        autoPrint: false,
        openDrawer: true,
      );

      final reloaded = SettingsProvider(DriftSettingsRepository(db));
      addTearDown(reloaded.dispose);
      await reloaded.load();
      expect(reloaded.ticketAddress, 'Calle 1');
      expect(reloaded.ticketPhone, '2222');
      expect(reloaded.ticketFooter, isNull); // vacío = sin dato
      expect(reloaded.printerMode, PrinterMode.windows);
      expect(reloaded.printerTarget, 'AON PR-200');
      expect(reloaded.hasPrinter, isTrue);
      expect(reloaded.paperColumns, 42);
      expect(reloaded.printAccents, isTrue);
      expect(reloaded.autoPrint, isFalse);
      expect(reloaded.openDrawer, isTrue);
    });

    test('un modo con destino vacío no cuenta como impresora configurada', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final settings = SettingsProvider(DriftSettingsRepository(db));
      addTearDown(settings.dispose);
      await settings.load();
      await settings.setPrinter(
        mode: PrinterMode.windows,
        target: '  ',
        columns: 48,
        accents: false,
        autoPrint: true,
        openDrawer: false,
      );
      expect(settings.hasPrinter, isFalse);
      expect(() => settings.setPrinter(mode: PrinterMode.network, target: 'x', columns: 5, accents: false, autoPrint: true, openDrawer: false), throwsArgumentError);
    });
  });

  group('impresora en red', () {
    test('envía los bytes al puerto de la impresora', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final received = Completer<List<int>>();
      server.listen((socket) {
        final data = <int>[];
        socket.listen(data.addAll, onDone: () => received.complete(data));
      });

      await NetworkPrinterTransport('127.0.0.1', port: server.port).send(Uint8List.fromList([1, 2, 3, 0x1B, 0x40]));
      expect(await received.future.timeout(const Duration(seconds: 5)), [1, 2, 3, 0x1B, 0x40]);
    });

    test('"ip:puerto" se separa bien', () {
      final transport = NetworkPrinterTransport.parse(' 192.168.1.50:9101 ');
      expect(transport.host, '192.168.1.50');
      expect(transport.port, 9101);
      expect(NetworkPrinterTransport.parse('192.168.1.50').port, 9100);
    });

    test('impresora apagada o IP equivocada: PrintException, no una excepción rara', () async {
      // Un puerto donde nadie escucha.
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();

      await expectLater(
        NetworkPrinterTransport('127.0.0.1', port: port).send(Uint8List.fromList([1])),
        throwsA(isA<PrintException>().having((e) => e.message, 'mensaje', contains('No se pudo conectar'))),
      );
      await expectLater(NetworkPrinterTransport('').send(Uint8List.fromList([1])), throwsA(isA<PrintException>()));
    });

    test('Windows: un nombre vacío o inexistente da un error claro', () async {
      await expectLater(WindowsSpoolerTransport('   ').send(Uint8List.fromList([1])), throwsA(isA<PrintException>()));
      if (Platform.isWindows) {
        await expectLater(
          WindowsSpoolerTransport('Impresora que no existe 12345').send(Uint8List.fromList([1])),
          throwsA(isA<PrintException>().having((e) => e.message, 'mensaje', contains('no encuentra'))),
        );
      }
    });
  });
}
