import 'package:flutter/material.dart';

import '../../../core/format/formatters.dart';
import '../../../core/format/money_input.dart';
import '../../../core/money.dart';
import 'package:provider/provider.dart';

import '../../../models/sale.dart';
import '../../printing/print_service.dart';
import '../../printing/ticket_preview_dialog.dart';

/// Lo que el cajero eligió al cobrar: la forma de pago y, si es efectivo, lo
/// que entregó el cliente en centavos (nulo = pagó exacto).
typedef PaymentChoice = ({PaymentMethod method, int? tenderedCents});

/// Atajos de efectivo recibido, en centavos: las monedas y billetes típicos.
const _denominations = [25, 50, 75, 100, 500, 1000, 2000];

/// Billetes grandes: solo se ofrecen cuando la venta supera los $20.
const _largeBills = [5000, 10000];

/// Texto del atajo: monedas en centavos ("25¢") y el resto en dólares ("\$5").
String _denominationLabel(int cents) => cents < 100 ? '$cents¢' : '\$${cents ~/ 100}';

/// Resultado del cobro con la opción de saltarse la revisión: la forma de pago
/// elegida y si el vendedor pidió registrar la venta SIN revisarla.
typedef PaymentOutcome = ({PaymentChoice choice, bool skipReview});

/// [initial] reabre el cobro con la forma de pago y el efectivo que ya se había
/// escrito (cuando el vendedor vuelve desde la revisión a corregirlos).
Future<PaymentChoice?> showPaymentMethodDialog(
  BuildContext context, {
  required double total,
  String? customerName,
  PaymentChoice? initial,
}) async {
  final outcome = await showPaymentDialog(context, total: total, customerName: customerName, initial: initial);
  return outcome?.choice;
}

/// Igual que [showPaymentMethodDialog], pero si [skipReviewUpToCents] no es
/// nulo y la venta no lo supera, ofrece también "Cobrar sin revisar": para
/// ventas pequeñas donde revisar el ticket no hace falta.
Future<PaymentOutcome?> showPaymentDialog(
  BuildContext context, {
  required double total,
  String? customerName,
  PaymentChoice? initial,
  int? skipReviewUpToCents,
}) {
  return showDialog<PaymentOutcome>(
    context: context,
    builder: (context) => _PaymentMethodDialog(
      total: total,
      customerName: customerName,
      initial: initial,
      skipReviewUpToCents: skipReviewUpToCents,
    ),
  );
}

class _PaymentMethodDialog extends StatefulWidget {
  const _PaymentMethodDialog({
    required this.total,
    this.customerName,
    this.initial,
    this.skipReviewUpToCents,
  });

  final double total;
  final String? customerName;
  final PaymentChoice? initial;
  final int? skipReviewUpToCents;

  @override
  State<_PaymentMethodDialog> createState() => _PaymentMethodDialogState();
}

class _PaymentMethodDialogState extends State<_PaymentMethodDialog> {
  late PaymentMethod _selected;
  final _received = TextEditingController();

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _selected = (initial != null && initial.method.isAvailable) ? initial.method : PaymentMethod.cash;
    if (initial?.tenderedCents != null) {
      _received.text = (initial!.tenderedCents! / 100).toStringAsFixed(2);
      _received.selection = TextSelection(baseOffset: 0, extentOffset: _received.text.length);
    }
  }

  int get _totalCents => toCents(widget.total);

  /// Lo escrito en "Efectivo recibido", en centavos; nulo si está vacío o no
  /// es un número (se toma como pago exacto).
  int? get _receivedCents {
    final value = double.tryParse(_received.text.trim().replaceAll(',', '.'));
    return value == null ? null : toCents(value);
  }

  bool get _isCash => _selected == PaymentMethod.cash;

  /// En efectivo, lo recibido no alcanza para pagar.
  bool get _insufficient => _isCash && _receivedCents != null && _receivedCents! < _totalCents;

  @override
  void dispose() {
    _received.dispose();
    super.dispose();
  }

  /// "Cobrar sin revisar" solo se ofrece en ventas pequeñas (hasta el tope).
  bool get _canSkipReview => widget.skipReviewUpToCents != null && _totalCents <= widget.skipReviewUpToCents!;

  void _confirm({bool skipReview = false}) {
    if (_insufficient) return;
    Navigator.of(context).pop((
      choice: (
        method: _selected,
        // Vacío o igual al total = pagó exacto: no se guarda un monto aparte.
        tenderedCents: _isCash ? _receivedCents : null,
      ),
      skipReview: skipReview,
    ));
  }

  void _setReceived(int cents) {
    setState(() {
      _received.text = (cents / 100).toStringAsFixed(2);
      _received.selection = TextSelection.collapsed(offset: _received.text.length);
    });
  }

  Widget _cashSection(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final received = _receivedCents;
    final shortcuts = [..._denominations, if (_totalCents > 2000) ..._largeBills];

    final String resultText;
    final Color resultColor;
    if (received == null) {
      resultText = 'Pago exacto, sin vuelto';
      resultColor = scheme.onSurfaceVariant;
    } else if (received < _totalCents) {
      resultText = 'Faltan ${formatCurrency((_totalCents - received) / 100)}';
      resultColor = scheme.error;
    } else {
      resultText = 'Vuelto: ${formatCurrency((received - _totalCents) / 100)}';
      resultColor = Colors.green.shade700;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _received,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Efectivo recibido',
            prefixText: r'$ ',
            helperText: 'Déjalo vacío si pagó exacto',
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          // Solo números con hasta dos decimales: nada de letras ni signos.
          inputFormatters: const [MoneyInputFormatter()],
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _confirm(),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            ActionChip(
              label: const Text('Exacto'),
              onPressed: () => setState(_received.clear),
            ),
            // Siempre en el mismo orden (para acostumbrarse a su lugar); los que
            // no alcanzan para pagar la venta salen deshabilitados.
            for (final cents in shortcuts)
              ActionChip(
                label: Text(_denominationLabel(cents)),
                onPressed: cents >= _totalCents ? () => _setReceived(cents) : null,
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          resultText,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: resultColor,
              ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cobrar venta'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                formatCurrency(widget.total),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text('Forma de pago'),
              const SizedBox(height: 8),
              RadioGroup<PaymentMethod>(
                groupValue: _selected,
                onChanged: (value) => setState(() => _selected = value!),
                child: Column(
                  children: [
                    for (final method in PaymentMethod.values)
                      RadioListTile<PaymentMethod>(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(method.label),
                        enabled: method.isAvailable,
                        subtitle: !method.isAvailable
                            ? const Text('Próximamente')
                            : method == PaymentMethod.credit && widget.customerName == null
                                ? const Text('Requiere seleccionar un cliente')
                                : null,
                        value: method,
                      ),
                  ],
                ),
              ),
              if (_isCash) ...[
                const SizedBox(height: 8),
                _cashSection(context),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        if (_canSkipReview)
          OutlinedButton(
            onPressed: _insufficient ? null : () => _confirm(skipReview: true),
            child: const Text('Cobrar sin revisar'),
          ),
        FilledButton(
          onPressed: _insufficient ? null : _confirm,
          child: const Text('Revisar venta'),
        ),
      ],
    );
  }
}

Future<void> showReceiptDialog(BuildContext context, Sale sale) {
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Venta registrada'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 32),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(sale.receiptNumber, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(dateTimeFormat.format(sale.date)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...sale.items.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(child: Text('${formatQuantity(item.quantity)}x ${item.productName}')),
                    Text(formatCurrency(item.subtotal)),
                  ],
                ),
              ),
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  formatCurrency(sale.total),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Pago: ${sale.paymentMethod.label}'),
            if (sale.tenderedCents != null) ...[
              Text('Recibido: ${formatCurrency(sale.tendered!)}'),
              if ((sale.changeCents ?? 0) > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Vuelto: ${formatCurrency(sale.change!)}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                  ),
                ),
            ],
            if (sale.customerName != null) Text('Cliente: ${sale.customerName}'),
          ],
        ),
      ),
      actions: [
        if (context.read<PrintService?>() != null)
          TextButton.icon(
            onPressed: () => showSaleTicket(context, sale),
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('Ver ticket'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Listo'),
        ),
      ],
    ),
  );
}
