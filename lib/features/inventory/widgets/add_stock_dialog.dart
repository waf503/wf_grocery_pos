import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/format/formatters.dart';
import '../../../core/format/money_input.dart';
import '../../../core/money.dart';
import '../../../models/product.dart';

/// Lo que se va a agregar: en qué presentación se cuenta, cuántas y, si se
/// escribió, lo que cuesta UNA de ellas (en centavos).
typedef StockEntry = ({Product target, double quantity, int? costCents});

/// "Agregar inventario": se escribe cuántas unidades, cajetillas o paquetes
/// llegaron y se SUMAN a las existencias del producto (no las reemplaza).
///
/// [product] es la fila desde la que se abrió: esa presentación queda elegida
/// (desde una cajetilla se esperan cajetillas, desde un paquete paquetes y
/// desde la unidad, unidades), pero se puede cambiar. [base] es el producto
/// que lleva las existencias y [presentations] sus presentaciones.
Future<StockEntry?> showAddStockDialog(
  BuildContext context, {
  required Product product,
  required Product base,
  required List<Product> presentations,
}) {
  return showDialog<StockEntry>(
    context: context,
    builder: (context) => _AddStockDialog(product: product, base: base, presentations: presentations),
  );
}

class _AddStockDialog extends StatefulWidget {
  const _AddStockDialog({required this.product, required this.base, required this.presentations});

  final Product product;
  final Product base;
  final List<Product> presentations;

  @override
  State<_AddStockDialog> createState() => _AddStockDialogState();
}

class _AddStockDialogState extends State<_AddStockDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantity = TextEditingController();
  final _cost = TextEditingController();
  late Product _selected;

  /// De la unidad base a la presentación que más contiene.
  late final List<Product> _options;

  @override
  void initState() {
    super.initState();
    // De la más pequeña a la más grande: el producto base puede ser cualquiera
    // (incluso el paquete) y las presentaciones, más chicas o más grandes.
    _options = [widget.base, ...widget.presentations]
      ..sort((a, b) => a.poolFactor.compareTo(b.poolFactor));
    _selected = _options.firstWhere((p) => p.id == widget.product.id, orElse: () => widget.base);
  }

  @override
  void dispose() {
    _quantity.dispose();
    _cost.dispose();
    super.dispose();
  }

  /// Solo se admiten decimales al contar la unidad mínima de un producto por
  /// peso (libras, kilos...). Las presentaciones son empaques completos.
  bool get _allowsDecimals => _selected.poolFactor == 1 && widget.base.allowsDecimals;

  /// Cómo se llama la unidad en la que se cuentan las existencias del grupo: la
  /// unidad del producto si él es la más pequeña, o simplemente "u".
  String get _poolLabel {
    final smallest = _options.first;
    return (!smallest.isPresentation && smallest.poolFactor == 1) ? widget.base.unit : 'u';
  }

  double? get _parsed => double.tryParse(_quantity.text.trim().replaceAll(',', '.'));

  /// Unidades base que suma la cantidad escrita.
  double? get _addedUnits => _parsed == null ? null : _parsed! * _selected.poolFactor;

  /// Las presentaciones y el producto base que contiene varias unidades se
  /// llaman por su nombre; la unidad mínima de un producto normal, "Unidades".
  String _label(Product option) =>
      (option.isPresentation || option.poolFactor > 1) ? option.name : 'Unidades (${widget.base.unit})';

  /// Dinero con las fracciones de centavo que haga falta ($0.0625), mínimo 2 decimales.
  String _perUnitText(double dollars) {
    var text = dollars.toStringAsFixed(4);
    // Quita los ceros de sobra, pero deja al menos dos decimales ($0.06, $0.003, $0.0625).
    while (text.endsWith('0') && text.length - text.indexOf('.') - 1 > 2) {
      text = text.substring(0, text.length - 1);
    }
    return '\$$text';
  }

  String _unitsText(double units) => '${formatQuantity(units)} $_poolLabel';

  /// Cuántas presentaciones completas caben en [units] unidades.
  String _packsText(double units) {
    final parts = <String>[];
    for (final option in _options.where((o) => o.poolFactor > 1)) {
      parts.add('${formatQuantity((units / option.poolFactor).floorToDouble())} ${option.name}');
    }
    return parts.join(' · ');
  }

  String? _validate(String? value) {
    final number = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
    if (number == null || number <= 0) return 'Ingresa una cantidad mayor a cero';
    if (!_allowsDecimals && number != number.roundToDouble()) return 'Debe ser un número entero';
    return null;
  }

  /// Costo de UNA de la presentación elegida, o nulo si se dejó vacío.
  double? get _parsedCost => double.tryParse(_cost.text.trim().replaceAll(',', '.'));

  /// Costo exacto de una unidad (puede traer fracciones de centavo).
  double? get _costPerUnit {
    final cost = _parsedCost;
    if (cost == null || cost <= 0) return null;
    return cost / _selected.poolFactor;
  }

  String? _validateCost(String? value) {
    if (value == null || value.trim().isEmpty) return null; // opcional
    final number = double.tryParse(value.trim().replaceAll(',', '.'));
    return (number == null || number <= 0) ? 'Ingresa un costo mayor a cero' : null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final cost = _parsedCost;
    Navigator.of(context).pop((
      target: _selected,
      quantity: _parsed!,
      costCents: (cost == null || cost <= 0) ? null : toCents(cost),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Existencias de TODO el grupo, en su unidad más pequeña.
    final current = widget.base.poolUnits;
    final added = _addedUnits;
    final valid = _validate(_quantity.text) == null;

    return AlertDialog(
      title: const Text('Agregar inventario'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.base.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Hay ahora: ${_unitsText(current)}', style: theme.textTheme.bodyMedium),
                if (_options.length > 1 && current > 0)
                  Text(_packsText(current), style: theme.textTheme.bodySmall),
                if (_options.length > 1) ...[
                  const SizedBox(height: 16),
                  const Text('¿En qué presentación llegó?'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final option in _options)
                        ChoiceChip(
                          label: Text(_label(option)),
                          selected: option.id == _selected.id,
                          onSelected: (_) => setState(() => _selected = option),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  controller: _quantity,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Cantidad de ${_label(_selected).toLowerCase()}',
                    helperText: _selected.poolFactor > 1
                        ? 'Cada una trae ${formatQuantity(_selected.poolFactor)} $_poolLabel'
                        : null,
                  ),
                  keyboardType: TextInputType.numberWithOptions(decimal: _allowsDecimals),
                  inputFormatters: [
                    _allowsDecimals
                        ? FilteringTextInputFormatter.allow(RegExp(r'^\d{0,7}([.,]\d{0,3})?'))
                        : FilteringTextInputFormatter.digitsOnly,
                  ],
                  onChanged: (_) => setState(() {}),
                  onFieldSubmitted: (_) => _submit(),
                  validator: _validate,
                ),
                const SizedBox(height: 12),
                // Opcional: con el costo de la presentación se calcula solo el
                // de cada unidad (el usuario no tiene que dividir).
                TextFormField(
                  controller: _cost,
                  decoration: InputDecoration(
                    labelText: 'Costo por ${_label(_selected).toLowerCase()} (opcional)',
                    prefixText: r'$ ',
                    helperText: 'Si lo escribes, se calcula el costo de cada unidad',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: const [MoneyInputFormatter()],
                  onChanged: (_) => setState(() {}),
                  onFieldSubmitted: (_) => _submit(),
                  validator: _validateCost,
                ),
                if (_costPerUnit != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Costo por $_poolLabel: ${_perUnitText(_costPerUnit!)}',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
                if (added != null && valid) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_selected.poolFactor > 1)
                          Text('Se agregan ${_unitsText(added)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          'Hay ${_unitsText(current)} → quedarán ${_unitsText(current + added)}',
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (_options.length > 1) Text(_packsText(current + added), style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ],
            ),
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
