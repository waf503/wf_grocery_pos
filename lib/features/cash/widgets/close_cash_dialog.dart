import 'package:flutter/material.dart';

import '../../../models/cash_session.dart';
import 'session_breakdown.dart';

/// Pide el efectivo contado físicamente. Devuelve el monto en dólares o
/// `null` si se cancela.
///
/// Con [blind] (cierre a ciegas, el estándar para el cajero) NO se muestra el
/// total esperado ni la diferencia y el campo empieza vacío: se cuenta el
/// efectivo de verdad, sin ver cuánto "debería" haber. El administrador, en
/// cambio, ve el desglose y la diferencia ANTES de confirmar.
Future<double?> showCloseCashDialog(
  BuildContext context,
  CashSession session, {
  bool blind = false,
}) {
  return showDialog<double>(
    context: context,
    builder: (context) => _CloseCashDialog(session: session, blind: blind),
  );
}

class _CloseCashDialog extends StatefulWidget {
  const _CloseCashDialog({required this.session, required this.blind});

  final CashSession session;
  final bool blind;

  @override
  State<_CloseCashDialog> createState() => _CloseCashDialogState();
}

class _CloseCashDialogState extends State<_CloseCashDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _counted;

  @override
  void initState() {
    super.initState();
    _counted = TextEditingController(
      text: widget.blind
          ? ''
          : widget.session.expectedAmount.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _counted.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(double.parse(_counted.text.trim()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final counted = double.tryParse(_counted.text.trim());
    final difference = widget.blind || counted == null
        ? null
        : counted - session.expectedAmount;
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Cerrar caja'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.blind)
                const Text(
                  'Cuenta el efectivo que hay en la caja y escribe el total.',
                )
              else
                SessionBreakdown(session: session),
              const SizedBox(height: 16),
              TextFormField(
                controller: _counted,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Monto contado físicamente',
                  prefixText: r'$ ',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                onFieldSubmitted: (_) => _submit(),
                validator: (v) {
                  final value = double.tryParse((v ?? '').trim());
                  if (value == null || value < 0) {
                    return 'Ingresa un monto válido';
                  }
                  return null;
                },
              ),
              if (difference != null) ...[
                const SizedBox(height: 8),
                Text(
                  difference.abs() < 0.005
                      ? 'La caja cuadra.'
                      : difference > 0
                      ? 'Sobran \$${difference.toStringAsFixed(2)} respecto al total en caja.'
                      : 'Faltan \$${(-difference).toStringAsFixed(2)} respecto al total en caja.',
                  style: TextStyle(
                    color: difference.abs() < 0.005
                        ? Colors.green.shade700
                        : (difference > 0
                              ? Colors.orange.shade800
                              : scheme.error),
                  ),
                ),
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
        FilledButton(onPressed: _submit, child: const Text('Cerrar caja')),
      ],
    );
  }
}
