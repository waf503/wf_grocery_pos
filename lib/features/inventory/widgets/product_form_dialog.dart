import 'package:flutter/material.dart';

import '../../../core/text/product_tags.dart';
import '../../../models/category.dart';
import '../../../models/product.dart';
import '../../../models/unit.dart';

class ProductFormResult {
  ProductFormResult({
    required this.name,
    required this.categoryId,
    required this.unitId,
    required this.price,
    required this.cost,
    required this.stock,
    required this.minStock,
    this.barcode,
    this.extraTags = '',
  });

  final String name;
  final String categoryId;
  final String unitId;
  final double price;
  final double cost;
  final double stock;
  final double minStock;
  final String? barcode;
  final String extraTags;
}

/// [suggestionsFor] devuelve productos ya ingresados que coinciden con lo
/// que se está tecleando en el nombre (por sus tags), para no reescribir
/// "Coca-Cola ..." desde cero.
Future<ProductFormResult?> showProductFormDialog(
  BuildContext context, {
  required List<Category> categories,
  required List<Unit> units,
  required List<Product> Function(String text) suggestionsFor,
  required String Function() generateBarcode,
  required bool Function(String code, {String? exceptId}) isBarcodeTaken,
  Product? existing,
  String? initialBarcode,
}) async {
  if (units.isEmpty) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Falta crear una unidad'),
        content: const Text('Para registrar productos primero crea al menos una unidad en la sección Unidades.'),
        actions: [
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Entendido')),
        ],
      ),
    );
    return null;
  }
  if (!context.mounted) return null;
  return showDialog<ProductFormResult>(
    context: context,
    builder: (context) => _ProductFormDialog(
      categories: categories,
      units: units,
      suggestionsFor: suggestionsFor,
      generateBarcode: generateBarcode,
      isBarcodeTaken: isBarcodeTaken,
      existing: existing,
      initialBarcode: initialBarcode,
    ),
  );
}

class _ProductFormDialog extends StatefulWidget {
  const _ProductFormDialog({
    required this.categories,
    required this.units,
    required this.suggestionsFor,
    required this.generateBarcode,
    required this.isBarcodeTaken,
    this.existing,
    this.initialBarcode,
  });

  final List<Category> categories;
  final List<Unit> units;
  final List<Product> Function(String text) suggestionsFor;
  final String Function() generateBarcode;
  final bool Function(String code, {String? exceptId}) isBarcodeTaken;
  final Product? existing;
  final String? initialBarcode;

  @override
  State<_ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<_ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  final FocusNode _nameFocusNode = FocusNode();
  late final TextEditingController _price;
  late final TextEditingController _cost;
  late final TextEditingController _stock;
  late final TextEditingController _minStock;
  late final TextEditingController _barcode;
  late final TextEditingController _extraTags;
  late String _categoryId;
  late String _unitId;

  Unit get _selectedUnit => widget.units.firstWhere((u) => u.id == _unitId);

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _name = TextEditingController(text: p?.name ?? '');
    _price = TextEditingController(text: p != null ? p.price.toStringAsFixed(2) : '');
    _cost = TextEditingController(text: p != null ? p.cost.toStringAsFixed(2) : '');
    _stock = TextEditingController(text: p != null ? p.stock.toString() : '0');
    _minStock = TextEditingController(text: p != null ? p.minStock.toString() : '5');
    _barcode = TextEditingController(text: p?.barcode ?? widget.initialBarcode ?? '');
    _extraTags = TextEditingController(text: p != null ? _extraTagsOf(p) : '');
    _categoryId = p?.categoryId ?? widget.categories.first.id;
    _unitId = widget.units.any((u) => u.id == p?.unitId) ? p!.unitId : widget.units.first.id;
  }

  /// Tags guardados que NO vienen del nombre: son las etiquetas que escribió
  /// el usuario, y las que se vuelven a mostrar al editar.
  String _extraTagsOf(Product product) {
    final fromName = tokenize(product.name).toSet();
    return product.tags.split(' ').where((t) => t.isNotEmpty && !fromName.contains(t)).join(' ');
  }

  @override
  void dispose() {
    _name.dispose();
    _nameFocusNode.dispose();
    _price.dispose();
    _cost.dispose();
    _stock.dispose();
    _minStock.dispose();
    _barcode.dispose();
    _extraTags.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      ProductFormResult(
        name: _name.text.trim(),
        categoryId: _categoryId,
        unitId: _unitId,
        price: double.parse(_price.text),
        cost: double.parse(_cost.text),
        stock: double.parse(_stock.text),
        minStock: double.parse(_minStock.text),
        barcode: _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
        extraTags: _extraTags.text.trim(),
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

  /// Igual que [_numberValidator], pero además exige un número entero cuando
  /// la unidad elegida no permite decimales (ej. no existen 2.5 gaseosas).
  String? _quantityValidator(String? value) {
    final error = _numberValidator(value);
    if (error != null) return error;
    final number = double.parse(value!);
    if (!_selectedUnit.allowsDecimals && number != number.roundToDouble()) {
      return 'La unidad "${_selectedUnit.name}" no permite decimales';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    return AlertDialog(
      title: Text(isEditing ? 'Editar producto' : 'Nuevo producto'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // `Autocomplete` sugiere productos ya ingresados mientras
                // escribes ("coca" -> "Coca-Cola Lata 355ml"), buscando por
                // sus tags. Al elegir una sugerencia se copia el nombre y,
                // por comodidad, también su categoría y unidad.
                Autocomplete<Product>(
                  // Le pasamos NUESTRO controller y focusNode (los dos
                  // juntos o ninguno, lo exige Flutter) para leer el texto
                  // en `_submit()` sin sincronizar nada a mano.
                  textEditingController: _name,
                  focusNode: _nameFocusNode,
                  displayStringForOption: (product) => product.name,
                  optionsBuilder: (textValue) {
                    return widget
                        .suggestionsFor(textValue.text)
                        .where((p) => p.id != widget.existing?.id);
                  },
                  onSelected: (product) => setState(() {
                    _categoryId = product.categoryId;
                    if (widget.units.any((u) => u.id == product.unitId)) _unitId = product.unitId;
                  }),
                  fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                    return TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Nombre del producto',
                        hintText: 'Ej. Coca-Cola Lata 355ml',
                      ),
                      validator: _requiredValidator,
                    );
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: widget.categories.any((c) => c.id == _categoryId) ? _categoryId : null,
                        key: ValueKey('category-$_categoryId'),
                        decoration: const InputDecoration(labelText: 'Categoría'),
                        items: [
                          for (final c in widget.categories)
                            DropdownMenuItem(value: c.id, child: Text(_labelFor(c))),
                        ],
                        onChanged: (value) => setState(() => _categoryId = value!),
                        validator: (value) => value == null ? 'Requerido' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _unitId,
                        key: ValueKey('unit-$_unitId'),
                        decoration: const InputDecoration(labelText: 'Unidad'),
                        items: [
                          for (final u in widget.units) DropdownMenuItem(value: u.id, child: Text(u.name)),
                        ],
                        onChanged: (value) => setState(() => _unitId = value!),
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
                        validator: _quantityValidator,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _minStock,
                        decoration: const InputDecoration(labelText: 'Stock mínimo'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: _quantityValidator,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _barcode,
                  decoration: InputDecoration(
                    labelText: 'Código de barras (opcional)',
                    helperText: 'Si el producto no trae código, genera uno interno',
                    suffixIcon: TextButton.icon(
                      onPressed: () => setState(() => _barcode.text = widget.generateBarcode()),
                      icon: const Icon(Icons.auto_fix_high, size: 18),
                      label: const Text('Generar'),
                    ),
                  ),
                  validator: (value) {
                    final code = value?.trim() ?? '';
                    if (code.isNotEmpty &&
                        widget.isBarcodeTaken(code, exceptId: widget.existing?.id)) {
                      return 'Este código ya pertenece a otro producto';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _extraTags,
                  decoration: const InputDecoration(
                    labelText: 'Etiquetas adicionales (opcional)',
                    helperText: 'Palabras extra para encontrarlo, ej. refresco soda',
                  ),
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
