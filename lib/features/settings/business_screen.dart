import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../shared/widgets/feedback_alert.dart';
import '../../shared/widgets/section_header.dart';
import '../../state/settings_provider.dart';
import '../printing/print_service.dart';
import '../printing/printer_transport.dart';
import '../printing/ticket_preview_dialog.dart';

/// Datos y reglas del negocio (solo administrador): nombre, datos del ticket,
/// impresora y los topes de la caja y del cobro.
class BusinessScreen extends StatefulWidget {
  const BusinessScreen({super.key});

  @override
  State<BusinessScreen> createState() => _BusinessScreenState();
}

class _BusinessScreenState extends State<BusinessScreen> {
  late final SettingsProvider _settings = context.read<SettingsProvider>();

  late final _name = TextEditingController(text: _settings.businessName);
  late final _limit = TextEditingController(text: (_settings.cashMovementLimitCents / 100).toStringAsFixed(2));
  late final _skipReview = TextEditingController(text: (_settings.skipReviewSetting / 100).toStringAsFixed(2));
  late final _address = TextEditingController(text: _settings.ticketAddress ?? '');
  late final _phone = TextEditingController(text: _settings.ticketPhone ?? '');
  late final _footer = TextEditingController(text: _settings.ticketFooter ?? '');
  late final _printerTarget = TextEditingController(text: _settings.printerTarget);

  late PrinterMode _mode = _settings.printerMode;
  late int _columns = _settings.paperColumns;
  late bool _accents = _settings.printAccents;
  late bool _autoPrint = _settings.autoPrint;
  late bool _openDrawer = _settings.openDrawer;

  String? _error;
  String? _limitError;
  String? _skipReviewError;

  @override
  void dispose() {
    for (final c in [_name, _limit, _skipReview, _address, _phone, _footer, _printerTarget]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Guarda todo (nombre, reglas, ticket e impresora). Devuelve si se guardó.
  Future<bool> _save({bool announce = true}) async {
    final limit = double.tryParse(_limit.text.trim());
    if (limit == null || limit < 0) {
      setState(() => _limitError = 'Escribe un monto válido (0 = siempre pedir autorización)');
      return false;
    }
    final skipReview = double.tryParse(_skipReview.text.trim());
    if (skipReview == null || skipReview < 0) {
      setState(() => _skipReviewError = 'Escribe un monto válido (0 = siempre revisar)');
      return false;
    }
    try {
      await _settings.setBusinessName(_name.text);
    } on ArgumentError catch (e) {
      setState(() => _error = e.message.toString());
      return false;
    }
    await _settings.setCashMovementLimitCents(toCents(limit));
    await _settings.setSkipReviewLimitCents(toCents(skipReview));
    await _settings.setTicketInfo(address: _address.text, phone: _phone.text, footer: _footer.text);
    await _settings.setPrinter(
      mode: _mode,
      target: _printerTarget.text,
      columns: _columns,
      accents: _accents,
      autoPrint: _autoPrint,
      openDrawer: _openDrawer,
    );
    if (!mounted) return true;
    setState(() {
      _error = null;
      _limitError = null;
      _skipReviewError = null;
    });
    _name.text = _settings.businessName;
    if (announce) {
      FeedbackAlert.show(context, type: FeedbackType.success, title: 'Datos del negocio guardados');
    }
    return true;
  }

  /// Guarda y manda el ticket de prueba a la impresora.
  Future<void> _printTest() async {
    if (!await _save(announce: false) || !mounted) return;
    final service = context.read<PrintService>();
    try {
      await service.printTest();
      if (mounted) {
        FeedbackAlert.show(
          context,
          type: FeedbackType.success,
          title: 'Prueba enviada',
          message: 'Revisa que el ticket salga completo, cortado y con los acentos bien.',
        );
      }
    } on PrintException catch (e) {
      if (mounted) {
        FeedbackAlert.show(
          context,
          type: FeedbackType.error,
          title: 'No se pudo imprimir',
          message: e.message,
          duration: const Duration(seconds: 6),
        );
      }
    }
  }

  Future<void> _previewTest() async {
    if (!await _save(announce: false) || !mounted) return;
    final service = context.read<PrintService>();
    await showTicketDialog(
      context,
      title: 'Vista previa del ticket',
      lines: service.testLines(),
      columns: service.columns,
    );
  }

  String get _targetLabel => switch (_mode) {
        PrinterMode.windows => 'Nombre de la impresora en Windows',
        PrinterMode.network => 'Dirección IP de la impresora (ej. 192.168.1.50)',
        PrinterMode.cups => 'Nombre de la impresora (CUPS)',
        PrinterMode.none => '',
      };

  String get _targetHelp => switch (_mode) {
        PrinterMode.windows =>
          'Tal como aparece en Configuración → Impresoras y escáneres. La impresora debe estar instalada.',
        PrinterMode.network => 'La impresora y esta computadora deben estar en la misma red. Puerto 9100.',
        PrinterMode.cups => 'El nombre de la cola, como lo muestra el comando lpstat -p.',
        PrinterMode.none => '',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Negocio', subtitle: 'Los datos y reglas de tu tienda'),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        maxLength: SettingsProvider.maxNameLength,
                        decoration: InputDecoration(labelText: 'Nombre del negocio', errorText: _error),
                        onChanged: (_) => setState(() => _error = null),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _limit,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Retiros e ingresos del cajero sin autorización, hasta',
                          prefixText: r'$ ',
                          helperText: 'Arriba de este monto el cajero necesita el PIN de un administrador.',
                          helperMaxLines: 2,
                          errorText: _limitError,
                        ),
                        onChanged: (_) => setState(() => _limitError = null),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _skipReview,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Cobrar sin revisar la venta, hasta',
                          prefixText: r'$ ',
                          helperText:
                              'En ventas de este monto o menos aparece el botón "Cobrar sin revisar". 0 = siempre revisar.',
                          helperMaxLines: 2,
                          errorText: _skipReviewError,
                        ),
                        onChanged: (_) => setState(() => _skipReviewError = null),
                      ),
                      const SizedBox(height: 28),
                      Text('Ticket', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text('Lo que va en el encabezado y el pie de cada ticket.', style: theme.textTheme.bodySmall),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _address,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(labelText: 'Dirección (opcional)'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Teléfono (opcional)'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _footer,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Mensaje al pie (opcional)',
                          helperText: 'Si lo dejas vacío dice "Gracias por su compra".',
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text('Impresora de tickets', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<PrinterMode>(
                        initialValue: _mode,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Conexión'),
                        items: const [
                          DropdownMenuItem(value: PrinterMode.none, child: Text('Sin impresora (solo ver el ticket)')),
                          DropdownMenuItem(value: PrinterMode.windows, child: Text('Instalada en Windows (USB)')),
                          DropdownMenuItem(value: PrinterMode.network, child: Text('En red (IP)')),
                          DropdownMenuItem(value: PrinterMode.cups, child: Text('Instalada en Linux (CUPS)')),
                        ],
                        onChanged: (value) => setState(() => _mode = value ?? PrinterMode.none),
                      ),
                      if (_mode != PrinterMode.none) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _printerTarget,
                          decoration: InputDecoration(
                            labelText: _targetLabel,
                            helperText: _targetHelp,
                            helperMaxLines: 3,
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          initialValue: const [32, 42, 48].contains(_columns) ? _columns : 48,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Ancho del papel'),
                          items: const [
                            DropdownMenuItem(value: 48, child: Text('80 mm (48 caracteres)')),
                            DropdownMenuItem(value: 42, child: Text('80 mm, letra más grande (42 caracteres)')),
                            DropdownMenuItem(value: 32, child: Text('58 mm (32 caracteres)')),
                          ],
                          onChanged: (value) => setState(() => _columns = value ?? 48),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Imprimir el ticket al registrar cada venta'),
                          value: _autoPrint,
                          onChanged: (value) => setState(() => _autoPrint = value),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Abrir el cajón de dinero en ventas en efectivo'),
                          subtitle: const Text('Solo si el cajón está conectado a la impresora.'),
                          value: _openDrawer,
                          onChanged: (value) => setState(() => _openDrawer = value),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Imprimir acentos y ñ'),
                          subtitle: const Text(
                            'Actívalo si en el ticket de prueba se leen bien. Si salen símbolos raros, déjalo apagado.',
                          ),
                          value: _accents,
                          onChanged: (value) => setState(() => _accents = value),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: _save,
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('Guardar'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _previewTest,
                            icon: const Icon(Icons.receipt_long_outlined),
                            label: const Text('Ver ticket de prueba'),
                          ),
                          if (_mode != PrinterMode.none)
                            OutlinedButton.icon(
                              onPressed: _printTest,
                              icon: const Icon(Icons.print_outlined),
                              label: const Text('Imprimir prueba'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
