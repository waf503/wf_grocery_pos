import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

/// No se pudo imprimir (impresora apagada, sin conexión, nombre incorrecto...).
class PrintException implements Exception {
  PrintException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Por dónde viajan los bytes hasta la impresora.
abstract class PrinterTransport {
  Future<void> send(Uint8List data);
}

/// Impresora en red (Ethernet o WiFi): se envían los comandos directo al
/// puerto 9100, el estándar de las térmicas.
class NetworkPrinterTransport implements PrinterTransport {
  NetworkPrinterTransport(this.host, {this.port = 9100, this.timeout = const Duration(seconds: 4)});

  /// Acepta "192.168.1.50" o "192.168.1.50:9100".
  factory NetworkPrinterTransport.parse(String target) {
    final parts = target.trim().split(':');
    final port = parts.length > 1 ? int.tryParse(parts[1]) : null;
    return NetworkPrinterTransport(parts.first, port: port ?? 9100);
  }

  final String host;
  final int port;
  final Duration timeout;

  @override
  Future<void> send(Uint8List data) async {
    if (host.isEmpty) throw PrintException('Escribe la dirección IP de la impresora');
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      socket.add(data);
      await socket.flush();
    } on SocketException {
      throw PrintException('No se pudo conectar con la impresora en $host:$port');
    } on TimeoutException {
      throw PrintException('La impresora en $host:$port no responde');
    } finally {
      await socket?.close();
    }
  }
}

/// Impresora instalada en Windows (por USB, por ejemplo): se envían los
/// comandos "crudos" (RAW) a la cola de impresión, sin pasar por el driver
/// gráfico. [printerName] es el nombre tal como aparece en Windows en
/// Configuración → Impresoras y escáneres.
class WindowsSpoolerTransport implements PrinterTransport {
  WindowsSpoolerTransport(this.printerName);

  final String printerName;

  @override
  Future<void> send(Uint8List data) async {
    if (!Platform.isWindows) throw PrintException('Este tipo de conexión solo existe en Windows');
    if (printerName.trim().isEmpty) throw PrintException('Escribe el nombre de la impresora');

    final arena = Arena();
    try {
      final handlePtr = arena<Pointer>();
      final opened = OpenPrinter(arena.pcwstr(printerName.trim()), handlePtr, null);
      if (!opened.value) {
        throw PrintException('Windows no encuentra la impresora "${printerName.trim()}". Revisa el nombre.');
      }
      final printer = PRINTER_HANDLE(handlePtr.value);
      try {
        final doc = arena<DOC_INFO_1>();
        doc.ref.pDocName = PWSTR(arena.pcwstr('Ticket'));
        doc.ref.pOutputFile = PWSTR(nullptr);
        doc.ref.pDatatype = PWSTR(arena.pcwstr('RAW'));

        if (StartDocPrinter(printer, 1, doc) == 0) {
          throw PrintException('La impresora "${printerName.trim()}" no acepta trabajos (¿apagada o sin conexión?)');
        }
        try {
          StartPagePrinter(printer);
          final buffer = arena<Uint8>(data.length);
          buffer.asTypedList(data.length).setAll(0, data);
          final written = arena<Uint32>();
          final ok = WritePrinter(printer, buffer, data.length, written);
          EndPagePrinter(printer);
          if (!ok || written.value != data.length) {
            throw PrintException('No se pudo enviar el ticket a la impresora');
          }
        } finally {
          EndDocPrinter(printer);
        }
      } finally {
        ClosePrinter(printer);
      }
    } finally {
      arena.releaseAll();
    }
  }
}

/// Impresora instalada en Linux (CUPS): se envían los comandos crudos con
/// `lp -o raw`. [printerName] es el nombre de la cola (`lpstat -p`).
class CupsTransport implements PrinterTransport {
  CupsTransport(this.printerName);

  final String printerName;

  @override
  Future<void> send(Uint8List data) async {
    if (printerName.trim().isEmpty) throw PrintException('Escribe el nombre de la impresora');
    final dir = await Directory.systemTemp.createTemp('ticket_');
    try {
      final file = File(p.join(dir.path, 'ticket.bin'));
      await file.writeAsBytes(data);
      final result = await Process.run('lp', ['-d', printerName.trim(), '-o', 'raw', file.path]);
      if (result.exitCode != 0) {
        throw PrintException('No se pudo imprimir en "${printerName.trim()}": ${result.stderr}'.trim());
      }
    } on ProcessException {
      throw PrintException('No se encontró el comando de impresión (lp) en este equipo');
    } finally {
      await dir.delete(recursive: true);
    }
  }
}
