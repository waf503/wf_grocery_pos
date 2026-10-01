import 'package:flutter/material.dart';

import '../../../models/category.dart';
import '../../../models/product.dart';
import '../../../models/product_family.dart';

class ProductFormResult {
  ProductFormResult({
    required this.familyName,
    required this.categoryId,
    required this.presentation,
    required this.unit,
    required this.price,
    required this.cost,
    required this.stock,
    required this.minStock,
    this.barcode,
  });

  final String familyName;
  final String categoryId;
  final String presentation;
  final String unit;
  final double price;
  final double cost;
  final double stock;
  final double minStock;
  final String? barcode;
}

Future<ProductFormResult?> showProductFormDialog(
  BuildContext context, {
  required List<ProductFamily> families,
  required List<Category> categories,
  Product? existing,
}) {
  return showDialog<ProductFormResult>(
    context: context,
    builder: (context) => _ProductFormDialog(
      families: families,
      categories: categories,
      existing: existing,
    ),
  );
}

class _ProductFormDialog extends StatefulWidget {
  const _ProductFormDialog({required this.families, required this.categories, this.existing});

  final List<ProductFamily> families;
  final List<Category> categories;
  final Product? existing;

  @override
  State<_ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<_ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _familyName;
  final FocusNode _familyFocusNode = FocusNode();
  late final TextEditingController _presentation;
  late final TextEditingController _price;
  late final TextEditingController _cost;
  late final TextEditingController _stock;
  late final TextEditingController _minStock;
  late final TextEditingController _barcode;
  late String _categoryId;
  late String _unit;

  static const _units = ['pieza', 'kg', 'paquete', 'litro'];

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _familyName = TextEditingController(text: p?.familyName ?? '');
    _presentation = TextEditingController(text: p?.presentation ?? '');
    _price = TextEditingController(text: p != null ? p.price.toStringAsFixed(2) : '');
    _cost = TextEditingController(text: p != null ? p.cost.toStringAsFixed(2) : '');
    _stock = TextEditingController(text: p != null ? p.stock.toString() : '0');
    _minStock = TextEditingController(text: p != null ? p.minStock.toString() : '5');
    _barcode = TextEditingController(text: p?.barcode ?? '');
    _categoryId = p?.categoryId ?? widget.categories.first.id;
    _unit = p?.unit ?? _units.first;
  }

  @override
  void dispose() {
    _familyName.dispose();
    _familyFocusNode.dispose();
    _presentation.dispose();
    _price.dispose();
    _cost.dispose();
    _stock.dispose();
    _minStock.dispose();
    _barcode.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      ProductFormResult(
        familyName: _familyName.text.trim(),
        categoryId: _categoryId,
        presentation: _presentation.text.trim(),
        unit: _unit,
        price: double.parse(_price.text),
        cost: double.parse(_cost.text),
        stock: double.parse(_stock.text),
        minStock: double.parse(_minStock.text),
        barcode: _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
      ),
    );
  }

  /// Prefijo visual simple para mostrar la jerarquía en el dropdown (ej.
  /// "— Gaseosas" debajo de "Bebidas"), calculado localmente siguiendo la
  /// cadena de `parentId` dentro de la lista ya recibida.
  String _labelFor(Category category) {
    var depth = 0;
    String? parentId = category.parentId;
    while (parentId != null) {
      Category? parent;
      for (final c in widget.categories) {
        if (c.id == parentId) {
          parent = c;
          break;
        }
      }
      if (parent == null) break;
      depth++;
      parentId = parent.parentId;
    }
    return depth == 0 ? category.name : '${'—  ' * depth}${category.name}';
  }

  String? _requiredValidator(String? value) =>
      (value == null || value.trim().isEmpty) ? 'Requerido' : null;

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
                // `Autocomplete` sugiere familias ya existentes mientras
                // escribes ("Coca" -> te sugiere "Coca-Cola" si ya existe),
                // pero también acepta texto nuevo: si no coincide con
                // ninguna, el Provider crea una familia nueva al guardar.
                Autocomplete<ProductFamily>(
                  // Le pasamos NUESTRO controller (`_familyName`, el mismo
                  // que leemos en `_submit()`) en vez de dejar que
                  // Autocomplete cree el suyo propio — así no hay que
                  // sincronizar nada a mano entre los dos. Si le pasas tu
                  // propio controller, Flutter EXIGE que también le pases
                  // tu propio focusNode (los dos juntos o ninguno).
                  textEditingController: _familyName,
                  focusNode: _familyFocusNode,
                  displayStringForOption: (family) => family.name,
                  optionsBuilder: (textValue) {
                    if (textValue.text.trim().isEmpty) return const Iterable.empty();
                    final query = textValue.text.toLowerCase();
                    return widget.families.where((f) => f.name.toLowerCase().contains(query));
                  },
                  onSelected: (family) => setState(() => _categoryId = family.categoryId),
                  fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                    return TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                      enabled: !isEditing,
                      decoration: InputDecoration(
                        labelText: 'Producto',
                        helperText: isEditing ? 'No se puede cambiar de familia al editar' : null,
                      ),
                      validator: _requiredValidator,
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _presentation,
                  decoration: const InputDecoration(
                    labelText: 'Presentación',
                    hintText: 'Ej. Lata 355ml, 2L, Fardo 24pz',
                  ),
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: widget.categories.any((c) => c.id == _categoryId) ? _categoryId : null,
                        decoration: InputDecoration(
                          labelText: 'Categoría',
                          helperText: isEditing ? 'Pertenece a la familia' : null,
                        ),
                        items: [
                          for (final c in widget.categories)
                            DropdownMenuItem(value: c.id, child: Text(_labelFor(c))),
                        ],
                        onChanged: isEditing ? null : (value) => setState(() => _categoryId = value!),
                        validator: (value) => value == null ? 'Requerido' : null,
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
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: _numberValidator,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _minStock,
                        decoration: const InputDecoration(labelText: 'Stock mínimo'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
