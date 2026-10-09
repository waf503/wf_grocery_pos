import 'package:flutter/material.dart';

import '../../../core/format/formatters.dart';
import '../../../core/money.dart';

/// Venta genérica capturada: descripción, precio unitario en centavos y
/// cantidad (de piezas).
typedef GenericItemData = ({String name, int priceCents, int quantity});

/// Pide los datos de algo que se vende y no está en el inventario. Solo el
/// precio es obligatorio: sin descripción se registra como "Varios".
Future<GenericItemData?> showGenericItemDialog(BuildContext context) {
  return showDialog<GenericItemData>(
    context: context,
    builder: (context) => const _GenericItemDialog(),
  );
}

class _GenericItemDialog extends StatefulWidget {
  const _GenericItemDialog();

  @override
  State<_GenericItemDialog> createState() => _GenericItemDialogState();
}

class _GenericItemDialogState extends State<_GenericItemDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _quantity = TextEditingController(text: '1');

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _quantity.dispose();
    super.dispose();
  }

  double? get _parsedPrice => double.tryParse(_price.text.trim().replaceAll(',', '.'));
  int? get _parsedQuantity => int.tryParse(_quantity.text.trim());

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final name = _name.text.trim();
    Navigator.of(context).pop((
      name: name.isEmpty ? 'Varios' : name,
      priceCents: toCents(_parsedPrice!),
      quantity: _parsedQuantity!,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final price = _parsedPrice;
    final quantity = _parsedQuantity;
    final totalCents = (price == null || price <= 0 || quantity == null || quantity < 1)
        ? null
        : toCents(price) * quantity;

    return AlertDialog(
      title: const Text('Venta genérica'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Para vender algo que no está en el inventario.'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _price,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Precio', prefixText: r'$ '),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                onFieldSubmitted: (_) => _submit(),
                validator: (v) {
                  final value = double.tryParse((v ?? '').trim().replaceAll(',', '.'));
                  if (value == null || toCents(value) <= 0) return 'Ingresa un precio válido';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Descripción (opcional)',
                  hintText: 'Varios',
                ),
                textCapitalization: TextCapitalization.sentences,
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _quantity,
                decoration: const InputDecoration(labelText: 'Cantidad'),
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                onFieldSubmitted: (_) => _submit(),
                validator: (v) {
                  final value = int.tryParse((v ?? '').trim());
                  return (value == null || value < 1) ? 'Ingresa una cantidad válida' : null;
                },
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
        FilledButton(onPressed: _submit, child: const Text('Agregar')),
      ],
    );
  }
}
