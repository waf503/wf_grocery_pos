import 'package:flutter/material.dart';

import '../../../core/format/formatters.dart';
import '../../../models/product.dart';

/// `true` si [quantity] es un múltiplo exacto de [step] (con tolerancia para
/// el error de punto flotante: 1.5 / 0.5 no da justo 3.0 en todos los casos).
bool isMultipleOfStep(double quantity, double step) {
  final ratio = quantity / step;
  return (ratio - ratio.roundToDouble()).abs() < 1e-6;
}

/// Pide la cantidad de un producto que se vende por peso o medida (libras,
/// kilos, litros). Muestra atajos (½, 1, 1½, 2...) según el incremento de la
/// unidad, el total en vivo y valida que sea múltiplo del incremento y que
/// no exceda las existencias. Devuelve la cantidad o `null` si se cancela.
///
/// [available] es lo que se puede poner en total (existencias; al editar un
/// renglón ya incluye lo que tiene en el carrito). [initial] es el valor
/// propuesto.
Future<double?> showQuantityDialog(
  BuildContext context, {
  required Product product,
  required double available,
  double? initial,
  String confirmLabel = 'Agregar',
}) {
  return showDialog<double>(
    context: context,
    builder: (context) => _QuantityDialog(
      product: product,
      available: available,
      initial: initial,
      confirmLabel: confirmLabel,
    ),
  );
}

class _QuantityDialog extends StatefulWidget {
  const _QuantityDialog({
    required this.product,
    required this.available,
    required this.initial,
    required this.confirmLabel,
  });

  final Product product;
  final double available;
  final double? initial;
  final String confirmLabel;

  @override
  State<_QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<_QuantityDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  double get _step => widget.product.quantityStep;

  @override
  void initState() {
    super.initState();
    // Propuesta: lo indicado, o 1 si es válido, o el incremento mínimo. El
    // texto queda seleccionado para que al escribir se reemplace.
    final fallback = (isMultipleOfStep(1, _step) && widget.available >= 1) ? 1.0 : _step;
    final text = formatQuantity(widget.initial ?? fallback);
    _controller = TextEditingController(text: text)
      ..selection = TextSelection(baseOffset: 0, extentOffset: text.length);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double? get _parsed => double.tryParse(_controller.text.trim().replaceAll(',', '.'));

  /// Atajos: múltiplos del incremento que existan entre los valores típicos.
  List<double> get _presets {
    final candidates = <double>{_step, 1, 1.5, 2, 3, 5};
    return [
      for (final v in candidates)
        if (isMultipleOfStep(v, _step) && v <= widget.available + 1e-9) v,
    ]..sort();
  }

  String? _validate(String? raw) {
    final value = double.tryParse((raw ?? '').trim().replaceAll(',', '.'));
    if (value == null || value <= 0) return 'Ingresa una cantidad válida';
    if (!isMultipleOfStep(value, _step)) {
      return 'Se vende de ${formatQuantity(_step)} en ${formatQuantity(_step)} ${widget.product.unit}';
    }
    if (value > widget.available + 1e-9) {
      return 'Solo hay ${formatQuantity(widget.available)} ${widget.product.unit}';
    }
    return null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    // Se redondea a milésimas para no arrastrar ruido de punto flotante.
    Navigator.of(context).pop((_parsed! * 1000).round() / 1000);
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final value = _parsed;
    final totalCents = value == null ? null : (product.priceCents * value).round();

    return AlertDialog(
      title: Text(product.name),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${formatCurrency(product.price)} por ${product.unit}'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in _presets)
                    ActionChip(
                      label: Text(formatQuantity(preset)),
                      onPressed: () => setState(() {
                        _controller.text = formatQuantity(preset);
                        _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _controller,
                autofocus: true,
                decoration: InputDecoration(labelText: 'Cantidad (${product.unit})'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                onFieldSubmitted: (_) => _submit(),
                validator: _validate,
              ),
              const SizedBox(height: 12),
              Text(
                totalCents == null ? '' : 'Total: ${formatCurrency(totalCents / 100)}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
