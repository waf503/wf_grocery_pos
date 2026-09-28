import 'package:flutter/material.dart';

import '../../../data/mock_data.dart';
import '../../../models/product.dart';

Future<Product?> showProductFormDialog(
  BuildContext context, {
  Product? existing,
  required String Function() nextId,
}) {
  return showDialog<Product>(
    context: context,
    builder: (context) => _ProductFormDialog(existing: existing, nextId: nextId),
  );
}

class _ProductFormDialog extends StatefulWidget {
  const _ProductFormDialog({this.existing, required this.nextId});

  final Product? existing;
  final String Function() nextId;

  @override
  State<_ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<_ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _cost;
  late final TextEditingController _stock;
  late final TextEditingController _minStock;
  late final TextEditingController _barcode;
  late String _category;
  late String _unit;

  static const _units = ['pieza', 'kg', 'paquete', 'litro'];

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _name = TextEditingController(text: p?.name ?? '');
    _price = TextEditingController(text: p != null ? p.price.toStringAsFixed(2) : '');
    _cost = TextEditingController(text: p != null ? p.cost.toStringAsFixed(2) : '');
    _stock = TextEditingController(text: p != null ? p.stock.toString() : '0');
    _minStock = TextEditingController(text: p != null ? p.minStock.toString() : '5');
    _barcode = TextEditingController(text: p?.barcode ?? '');
    _category = p?.category ?? productCategories.first;
    _unit = p?.unit ?? _units.first;
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _cost.dispose();
    _stock.dispose();
    _minStock.dispose();
    _barcode.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final product = Product(
      id: widget.existing?.id ?? widget.nextId(),
      name: _name.text.trim(),
      category: _category,
      unit: _unit,
      price: double.parse(_price.text),
      cost: double.parse(_cost.text),
      stock: int.parse(_stock.text),
      minStock: int.parse(_minStock.text),
      barcode: _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
    );
    Navigator.of(context).pop(product);
  }

  String? _requiredValidator(String? value) => (value == null || value.trim().isEmpty) ? 'Requerido' : null;

  String? _numberValidator(String? value) {
    if (value == null || value.trim().isEmpty) return 'Requerido';
    if (double.tryParse(value) == null) return 'Número inválido';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    return AlertDialog(
      title: Text(isEditing ? 'Editar producto' : 'Nuevo producto'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _category,
                        decoration: const InputDecoration(labelText: 'Categoría'),
                        items: [
                          for (final c in productCategories) DropdownMenuItem(value: c, child: Text(c)),
                        ],
                        onChanged: (value) => setState(() => _category = value!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _unit,
                        decoration: const InputDecoration(labelText: 'Unidad'),
                        items: [
                          for (final u in _units) DropdownMenuItem(value: u, child: Text(u)),
                        ],
                        onChanged: (value) => setState(() => _unit = value!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _price,
                        decoration: const InputDecoration(labelText: 'Precio de venta'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: _numberValidator,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _cost,
                        decoration: const InputDecoration(labelText: 'Costo'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: _numberValidator,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _stock,
                        decoration: const InputDecoration(labelText: 'Existencias'),
                        keyboardType: TextInputType.number,
                        validator: _numberValidator,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _minStock,
                        decoration: const InputDecoration(labelText: 'Stock mínimo'),
                        keyboardType: TextInputType.number,
                        validator: _numberValidator,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _barcode,
                  decoration: const InputDecoration(labelText: 'Código de barras (opcional)'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: _submit, child: const Text('Guardar')),
      ],
    );
  }
}
