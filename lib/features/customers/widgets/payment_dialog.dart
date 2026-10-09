import 'package:flutter/material.dart';

import '../../../core/format/formatters.dart';
import '../../../core/money.dart';
import '../../../models/customer.dart';

/// Abono capturado: monto en centavos y si se cobró en efectivo (entra a caja).
typedef PaymentData = ({int amountCents, bool inCash});

Future<PaymentData?> showPaymentDialog(
  BuildContext context, {
  required Customer customer,
  required bool cashOpen,
}) {
  return showDialog<PaymentData>(
    context: context,
    builder: (context) => _PaymentDialog(customer: customer, cashOpen: cashOpen),
  );
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.customer, required this.cashOpen});

  final Customer customer;
  final bool cashOpen;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late bool _inCash;

  @override
  void initState() {
    super.initState();
    // Por defecto se propone liquidar toda la deuda.
    _amount = TextEditingController(text: widget.customer.balance.toStringAsFixed(2));
    _inCash = widget.cashOpen;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop((amountCents: toCents(double.parse(_amount.text)), inCash: _inCash));
  }

  @override
  Widget build(BuildContext context) {
    final balanceCents = widget.customer.balanceCents;
    return AlertDialog(
      title: Text('Abono de ${widget.customer.name}'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Saldo pendiente: ${formatCurrency(widget.customer.balance)}'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amount,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Monto del abono', prefixText: r'$ '),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onFieldSubmitted: (_) => _submit(),
                validator: (v) {
                  final value = double.tryParse((v ?? '').trim());
                  if (value == null || toCents(value) <= 0) return 'Ingresa un monto válido';
                  if (toCents(value) > balanceCents) return 'Excede el saldo pendiente';
                  return null;
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Cobrado en efectivo'),
                subtitle: Text(
                  widget.cashOpen
                      ? 'Se registra como ingreso en la caja abierta.'
                      : 'La caja está cerrada: se registrará sin mover efectivo.',
                ),
                value: _inCash,
                onChanged: widget.cashOpen ? (value) => setState(() => _inCash = value) : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: _submit, child: const Text('Registrar abono')),
      ],
    );
  }
}
