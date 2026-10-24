import 'package:flutter/foundation.dart';

import '../features/settings/data/settings_repository.dart';

/// Por dónde se conecta la impresora de tickets.
enum PrinterMode {
  /// Sin impresora: el ticket solo se puede ver en pantalla.
  none,

  /// Instalada en Windows (USB, por ejemplo); se elige por su nombre.
  windows,

  /// En red (Ethernet o WiFi); se elige por su dirección IP.
  network,

  /// Instalada en Linux (CUPS); se elige por el nombre de la cola.
  cups,
}

/// Datos y reglas del negocio: nombre, datos del ticket, impresora y topes.
class SettingsProvider extends ChangeNotifier {
  SettingsProvider(this._repository);

  final SettingsRepository _repository;

  static const String _nameKey = 'business_name';
  static const String _cashLimitKey = 'cash_movement_limit_cents';
  static const String _skipReviewKey = 'skip_review_limit_cents';
  static const String _addressKey = 'ticket_address';
  static const String _phoneKey = 'ticket_phone';
  static const String _footerKey = 'ticket_footer';
  static const String _printerModeKey = 'printer_mode';
  static const String _printerTargetKey = 'printer_target';
  static const String _printerColumnsKey = 'printer_columns';
  static const String _printerAccentsKey = 'printer_accents';
  static const String _printerAutoKey = 'printer_auto';
  static const String _printerDrawerKey = 'printer_drawer';

  /// Caracteres por renglón de una térmica de 80 mm (las de 58 mm usan 32).
  static const int defaultPaperColumns = 48;

  /// Hasta cuánto (en centavos) se puede cobrar sin revisar el ticket, mientras
  /// no se configure otro tope.
  static const int defaultSkipReviewLimitCents = 500;

  /// Hasta cuánto (en centavos) puede un cajero retirar o ingresar sin el PIN
  /// de un administrador, mientras no se configure otro tope.
  static const int defaultCashMovementLimitCents = 2000;

  /// Nombre que se muestra mientras no se haya configurado uno.
  static const String defaultBusinessName = 'Mi Tienda';
  static const int maxNameLength = 40;

  String? _businessName;
  int? _cashLimitCents;
  int? _skipReviewLimitCents;
  String? _address;
  String? _phone;
  String? _footer;
  PrinterMode _printerMode = PrinterMode.none;
  String _printerTarget = '';
  int _paperColumns = defaultPaperColumns;
  bool _printAccents = false;
  bool _autoPrint = true;
  bool _openDrawer = false;

  /// Nombre del negocio, o [defaultBusinessName] si aún no se configura.
  String get businessName => _businessName ?? defaultBusinessName;

  bool get hasBusinessName => _businessName != null;

  /// Tope (centavos) de retiros e ingresos que un cajero hace sin autorización.
  int get cashMovementLimitCents => _cashLimitCents ?? defaultCashMovementLimitCents;

  /// Las ventas de hasta este monto (centavos) se pueden cobrar sin revisar.
  /// Nulo = la opción está desactivada (tope en 0).
  int? get skipReviewLimitCents {
    final limit = _skipReviewLimitCents ?? defaultSkipReviewLimitCents;
    return limit > 0 ? limit : null;
  }

  /// Valor configurado del tope (0 = desactivado), para mostrarlo en pantalla.
  int get skipReviewSetting => _skipReviewLimitCents ?? defaultSkipReviewLimitCents;

  /// Dirección, teléfono y mensaje de pie que van en el ticket.
  String? get ticketAddress => _address;
  String? get ticketPhone => _phone;
  String? get ticketFooter => _footer;

  PrinterMode get printerMode => _printerMode;

  /// Nombre de la impresora (Windows / Linux) o dirección IP (red).
  String get printerTarget => _printerTarget;

  /// Hay una impresora configurada (tipo de conexión y destino).
  bool get hasPrinter => _printerMode != PrinterMode.none && _printerTarget.trim().isNotEmpty;

  /// Caracteres por renglón del papel (48 en 80 mm, 32 en 58 mm).
  int get paperColumns => _paperColumns;

  /// Enviar acentos y ñ (si la impresora los imprime bien); si no, se imprimen sin acento.
  bool get printAccents => _printAccents;

  /// Imprimir el ticket solo al registrar cada venta.
  bool get autoPrint => _autoPrint;

  /// Abrir el cajón de dinero al cobrar en efectivo.
  bool get openDrawer => _openDrawer;

  Future<void> load() async {
    final values = await _repository.all();
    final name = values[_nameKey]?.trim();
    _businessName = (name == null || name.isEmpty) ? null : name;
    _cashLimitCents = int.tryParse(values[_cashLimitKey] ?? '');
    _skipReviewLimitCents = int.tryParse(values[_skipReviewKey] ?? '');
    String? text(String key) {
      final value = values[key]?.trim();
      return (value == null || value.isEmpty) ? null : value;
    }

    _address = text(_addressKey);
    _phone = text(_phoneKey);
    _footer = text(_footerKey);
    _printerMode = PrinterMode.values.firstWhere(
      (m) => m.name == values[_printerModeKey],
      orElse: () => PrinterMode.none,
    );
    _printerTarget = values[_printerTargetKey]?.trim() ?? '';
    _paperColumns = int.tryParse(values[_printerColumnsKey] ?? '') ?? defaultPaperColumns;
    _printAccents = values[_printerAccentsKey] == '1';
    _autoPrint = values[_printerAutoKey] != '0';
    _openDrawer = values[_printerDrawerKey] == '1';
    notifyListeners();
  }

  /// Guarda el nombre (sin espacios sobrantes). Lanza [ArgumentError] si está
  /// vacío o es demasiado largo.
  Future<void> setBusinessName(String name) async {
    final clean = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty) throw ArgumentError('Escribe el nombre del negocio');
    if (clean.length > maxNameLength) {
      throw ArgumentError('El nombre admite hasta $maxNameLength caracteres');
    }
    await _repository.set(_nameKey, clean);
    _businessName = clean;
    notifyListeners();
  }

  /// Cambia el tope de retiros e ingresos que un cajero hace sin autorización
  /// (0 = todos necesitan el PIN de un administrador).
  Future<void> setCashMovementLimitCents(int cents) async {
    if (cents < 0) throw ArgumentError('El tope no puede ser negativo');
    await _repository.set(_cashLimitKey, cents.toString());
    _cashLimitCents = cents;
    notifyListeners();
  }

  /// Cambia hasta cuánto se puede cobrar sin revisar el ticket (0 = siempre se
  /// revisa).
  Future<void> setSkipReviewLimitCents(int cents) async {
    if (cents < 0) throw ArgumentError('El tope no puede ser negativo');
    await _repository.set(_skipReviewKey, cents.toString());
    _skipReviewLimitCents = cents;
    notifyListeners();
  }

  /// Guarda dirección, teléfono y mensaje de pie del ticket (vacío = sin ese dato).
  Future<void> setTicketInfo({String? address, String? phone, String? footer}) async {
    Future<String?> save(String key, String? value) async {
      final clean = value?.trim() ?? '';
      await _repository.set(key, clean);
      return clean.isEmpty ? null : clean;
    }

    _address = await save(_addressKey, address);
    _phone = await save(_phoneKey, phone);
    _footer = await save(_footerKey, footer);
    notifyListeners();
  }

  /// Guarda la configuración de la impresora de tickets.
  Future<void> setPrinter({
    required PrinterMode mode,
    required String target,
    required int columns,
    required bool accents,
    required bool autoPrint,
    required bool openDrawer,
  }) async {
    if (columns < 24 || columns > 80) throw ArgumentError('El ancho del papel debe estar entre 24 y 80 caracteres');
    await _repository.set(_printerModeKey, mode.name);
    await _repository.set(_printerTargetKey, target.trim());
    await _repository.set(_printerColumnsKey, columns.toString());
    await _repository.set(_printerAccentsKey, accents ? '1' : '0');
    await _repository.set(_printerAutoKey, autoPrint ? '1' : '0');
    await _repository.set(_printerDrawerKey, openDrawer ? '1' : '0');
    _printerMode = mode;
    _printerTarget = target.trim();
    _paperColumns = columns;
    _printAccents = accents;
    _autoPrint = autoPrint;
    _openDrawer = openDrawer;
    notifyListeners();
  }
}
