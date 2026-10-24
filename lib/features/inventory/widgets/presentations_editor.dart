import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/format/formatters.dart';
import '../../../core/format/money_input.dart';
import '../../../core/money.dart';
import '../../../models/product_combo.dart';

/// Fracción exacta (para comparar tamaños de empaques sin errores de punto
/// flotante: un cigarro suelto es 1/200 de un paquete).
class _Frac {
  const _Frac(this.n, this.d);

  factory _Frac.of(int n, int d) {
    final g = n.gcd(d);
    return _Frac(n ~/ g, d ~/ g);
  }

  final int n;
  final int d;

  _Frac times(int k) => _Frac.of(n * k, d);
  _Frac dividedBy(int k) => _Frac.of(n, d * k);
  bool operator <(_Frac other) => n * other.d < other.n * d;

  /// `this ÷ other` si es un número entero exacto; si no, `null`.
  int? integerRatioTo(_Frac other) {
    final num = n * other.d;
    final den = d * other.n;
    return num % den == 0 ? num ~/ den : null;
  }
}

/// Una presentación tal como se edita en el formulario: nombre, cómo se
/// relaciona con otra (contiene N de ella, o viene dentro de ella N veces),
/// precio, código de barras y promociones.
class PresentationEntry {
  PresentationEntry({
    this.id,
    String name = '',
    String count = '',
    this.ofIndex = -1,
    this.inside = false,
    String price = '',
    String barcode = '',
    this.combos = const [],
    this.explicitCostCents,
    this.fixedPoolUnits,
  })  : name = TextEditingController(text: name),
        count = TextEditingController(text: count),
        price = TextEditingController(text: price),
        barcode = TextEditingController(text: barcode);

  /// Nulo si es nueva; si ya existe, su id (para actualizarla).
  final String? id;
  final TextEditingController name;

  /// El número "N" de la relación.
  final TextEditingController count;
  final TextEditingController price;
  final TextEditingController barcode;

  /// Con QUÉ se relaciona: -1 = el producto base; k = la presentación número k
  /// de la lista (solo una anterior a esta).
  int ofIndex;

  /// `false`: esta presentación CONTIENE [count] de la otra (es más grande).
  /// `true`: la otra contiene [count] de esta (es más pequeña: "viene dentro").
  bool inside;
  List<ProductCombo> combos;

  /// Costo fijado a mano; nulo = se calcula desde el costo del producto base.
  int? explicitCostCents;

  /// Tamaño de una presentación que ya existía y no se puede expresar como una
  /// relación entera con el base: se conserva tal cual (en unidades del pool)
  /// hasta que se vuelva a crear.
  final int? fixedPoolUnits;

  void dispose() {
    name.dispose();
    count.dispose();
    price.dispose();
    barcode.dispose();
  }
}

/// El resultado de acomodar todas las presentaciones: la unidad MÁS PEQUEÑA
/// del grupo (en la que se guardan las existencias) y cuántas de esas unidades
/// vale el producto base y cada presentación.
class PresentationLayout {
  const PresentationLayout({
    required this.rootUnitsPerPack,
    required this.unitsPerEntry,
    required this.stockScale,
  });

  /// Lo que vale el producto base en la unidad más pequeña (1 si él es la más
  /// pequeña; 200 si es un paquete de 200 cigarros sueltos).
  final int rootUnitsPerPack;

  /// Lo mismo para cada presentación, en el orden de la lista.
  final List<int> unitsPerEntry;

  /// Cuánto se multiplican las existencias ya guardadas porque la unidad cambió
  /// (de paquetes a cigarros: ×200). 1 si no cambia.
  final double stockScale;
}

/// Estado de la lista de presentaciones del formulario.
class PresentationsController extends ChangeNotifier {
  PresentationsController(Iterable<PresentationEntry> initial, {this.currentRootFactor = 1})
      : entries = [...initial];

  final List<PresentationEntry> entries;

  /// Cuánto vale hoy el producto base en la unidad del pool (1 en uno nuevo).
  final int currentRootFactor;

  bool get isEmpty => entries.isEmpty;

  void add() {
    entries.add(PresentationEntry());
    notifyListeners();
  }

  void removeAt(int index) {
    entries.removeAt(index).dispose();
    // Las que se relacionaban con la borrada (o con una posterior) se reajustan.
    for (final entry in entries) {
      if (entry.ofIndex == index) {
        entry.ofIndex = -1;
      } else if (entry.ofIndex > index) {
        entry.ofIndex -= 1;
      }
    }
    notifyListeners();
  }

  /// Avisa que algo cambió (para recalcular lo que se muestra en pantalla).
  void touch() => notifyListeners();

  /// Tamaño de cada presentación medido en "productos base" (el base vale 1):
  /// un paquete de 20 cajetillas de 20 es 20 × (cajetilla); un cigarro dentro
  /// de un paquete base de 200 es 1/200. Nulo si faltan datos.
  List<_Frac?> _sizes() {
    final result = <_Frac?>[];
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final fixed = entry.fixedPoolUnits;
      if (fixed != null) {
        result.add(_Frac.of(fixed, currentRootFactor));
        continue;
      }
      final count = int.tryParse(entry.count.text.trim());
      if (count == null || count < 1) {
        result.add(null);
        continue;
      }
      final ref = (entry.ofIndex < 0 || entry.ofIndex >= i) ? const _Frac(1, 1) : result[entry.ofIndex];
      if (ref == null) {
        result.add(null);
        continue;
      }
      result.add(entry.inside ? ref.dividedBy(count) : ref.times(count));
    }
    return result;
  }

  /// Acomoda todas las presentaciones: elige la unidad más pequeña del grupo y
  /// calcula cuántas de ellas vale cada una. Devuelve `layout` nulo si faltan
  /// datos (sin error) o si las cantidades no cuadran (con [error]).
  ({PresentationLayout? layout, String? error}) computeLayout() {
    final sizes = _sizes();
    if (sizes.any((s) => s == null)) return (layout: null, error: null);

    // La unidad del pool es la más pequeña de todas (incluido el base).
    var smallest = const _Frac(1, 1);
    for (final size in sizes) {
      if (size! < smallest) smallest = size;
    }

    final root = const _Frac(1, 1).integerRatioTo(smallest);
    final units = <int>[];
    for (var i = 0; i < sizes.length; i++) {
      final ratio = sizes[i]!.integerRatioTo(smallest);
      if (ratio == null) {
        final name = entries[i].name.text.trim();
        return (
          layout: null,
          error: '"${name.isEmpty ? 'Presentación ${i + 1}' : name}" no es un múltiplo exacto de la '
              'unidad más pequeña. Revisa las cantidades.',
        );
      }
      units.add(ratio);
    }
    if (root == null) {
      return (layout: null, error: 'Las cantidades no cuadran. Revisa las presentaciones.');
    }
    if (root > 1000000 || units.any((u) => u > 1000000)) {
      return (layout: null, error: 'Las cantidades son demasiado grandes.');
    }
    return (
      layout: PresentationLayout(
        rootUnitsPerPack: root,
        unitsPerEntry: units,
        stockScale: root / currentRootFactor,
      ),
      error: null,
    );
  }

  /// Las presentaciones listas para guardar, o `null` si algo es inválido.
  /// [layout] es el que devolvió [computeLayout].
  List<PresentationDraft>? buildDrafts(PresentationLayout layout) {
    final drafts = <PresentationDraft>[];
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final price = double.tryParse(entry.price.text.trim().replaceAll(',', '.'));
      if (price == null || entry.name.text.trim().isEmpty) return null;
      final barcode = entry.barcode.text.trim();
      drafts.add(
        PresentationDraft(
          id: entry.id,
          name: entry.name.text.trim(),
          unitsPerPack: layout.unitsPerEntry[i],
          priceCents: toCents(price),
          costCents: entry.explicitCostCents,
          barcode: barcode.isEmpty ? null : barcode,
          combos: entry.combos,
        ),
      );
    }
    return drafts;
  }

  @override
  void dispose() {
    for (final entry in entries) {
      entry.dispose();
    }
    super.dispose();
  }
}

/// Lista editable de presentaciones del producto (cajetilla, paquete...). No
/// hay una presentación "principal": cada una se relaciona con otra, de mayor a
/// menor ("el paquete contiene 200 cigarros") o de menor a mayor ("la cajetilla
/// contiene 20 cigarros").
class PresentationsEditor extends StatelessWidget {
  const PresentationsEditor({
    super.key,
    required this.controller,
    required this.baseName,
    required this.baseBarcode,
    required this.isBarcodeTaken,
  });

  final PresentationsController controller;

  /// Nombre que tiene escrito el producto base en el formulario.
  final String Function() baseName;

  /// Código de barras que tiene escrito el producto base en el formulario.
  final String Function() baseBarcode;
  final bool Function(String code, {String? exceptId}) isBarcodeTaken;

  String _rootName() {
    final text = baseName().trim();
    return text.isEmpty ? 'Producto base' : text;
  }

  String _entryName(int index) {
    final text = controller.entries[index].name.text.trim();
    return text.isEmpty ? 'Presentación ${index + 1}' : text;
  }

  String _refName(int ofIndex, int index) =>
      (ofIndex < 0 || ofIndex >= index) ? _rootName() : _entryName(ofIndex);

  String? _barcodeError(PresentationEntry entry, String? value) {
    final code = value?.trim() ?? '';
    if (code.isEmpty) return null;
    if (isBarcodeTaken(code, exceptId: entry.id)) return 'Este código ya pertenece a otro producto';
    if (code == baseBarcode().trim()) return 'Es el mismo código del producto base';
    final repeated = controller.entries.where((e) => e != entry && e.barcode.text.trim() == code);
    return repeated.isNotEmpty ? 'Código repetido en otra presentación' : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final result = controller.computeLayout();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Cada presentación se vende por separado (con su precio y su código), '
              'pero todas descuentan de las mismas existencias. Se relacionan entre sí: '
              'de mayor a menor ("el paquete contiene 200 cigarros") o de menor a mayor.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < controller.entries.length; i++) ...[
              _buildEntry(context, i, result.layout),
              const SizedBox(height: 8),
            ],
            if (result.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(result.error!, style: TextStyle(color: theme.colorScheme.error)),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: controller.add,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Agregar presentación'),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEntry(BuildContext context, int index, PresentationLayout? layout) {
    final entry = controller.entries[index];
    final theme = Theme.of(context);
    final fixed = entry.fixedPoolUnits != null;
    final validOf = (entry.ofIndex >= 0 && entry.ofIndex < index) ? entry.ofIndex : -1;

    final refDropdown = DropdownButtonFormField<int>(
      isExpanded: true,
      key: ValueKey('of-$index-${entry.ofIndex}-${entry.inside}'),
      initialValue: validOf,
      decoration: InputDecoration(labelText: entry.inside ? 'Producto que la trae' : 'Cuenta de'),
      items: [
        DropdownMenuItem(value: -1, child: Text('${_rootName()} (producto base)', overflow: TextOverflow.ellipsis)),
        for (var j = 0; j < index; j++)
          DropdownMenuItem(value: j, child: Text(_entryName(j), overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (value) {
        entry.ofIndex = value ?? -1;
        controller.touch();
      },
    );

    final countField = SizedBox(
      width: 100,
      child: TextFormField(
        controller: entry.count,
        decoration: InputDecoration(labelText: entry.inside ? 'Trae' : 'Contiene'),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (_) => controller.touch(),
        validator: (v) {
          final n = int.tryParse((v ?? '').trim());
          if (n == null || n < 1) return 'Requerido';
          if (n < 2) return 'Debe ser 2 o más';
          return null;
        },
      ),
    );

    final String? summary;
    if (fixed) {
      summary = null;
    } else {
      final n = int.tryParse(entry.count.text.trim());
      final self = _entryName(index);
      final other = _refName(entry.ofIndex, index);
      summary = (n == null || n < 2)
          ? null
          : entry.inside
              ? '1 $other trae $n de $self'
              : '1 $self contiene $n de $other';
    }
    final total = layout?.unitsPerEntry[index];

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: entry.name,
                    decoration: const InputDecoration(
                      labelText: 'Nombre de la presentación',
                      hintText: 'Ej. Cajetilla de 20 cigarros',
                    ),
                    onChanged: (_) => controller.touch(),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                ),
                IconButton(
                  tooltip: 'Quitar presentación',
                  icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                  onPressed: () => controller.removeAt(index),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (fixed)
              Text(
                'Contiene ${formatQuantity(entry.fixedPoolUnits!.toDouble())} unidades mínimas '
                '(medida que ya tenía; para cambiarla, quítala y créala de nuevo).',
                style: theme.textTheme.bodySmall,
              )
            else ...[
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Contiene')),
                  ButtonSegment(value: true, label: Text('Viene dentro de')),
                ],
                selected: {entry.inside},
                onSelectionChanged: (value) {
                  entry.inside = value.first;
                  controller.touch();
                },
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: entry.inside
                    // "Cada [paquete] trae [200] de ésta"
                    ? [
                        Expanded(child: refDropdown),
                        const SizedBox(width: 8),
                        countField,
                      ]
                    // "Contiene [20] de [cigarros]"
                    : [
                        countField,
                        const Padding(
                          padding: EdgeInsets.only(top: 16, left: 8, right: 8),
                          child: Text('de'),
                        ),
                        Expanded(child: refDropdown),
                      ],
              ),
              if (summary != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    summary,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
            if (total != null)
              Text(
                'Equivale a ${formatQuantity(total.toDouble())} ${total == 1 ? 'unidad mínima' : 'unidades mínimas'} del grupo',
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: entry.price,
                    decoration: const InputDecoration(labelText: 'Precio de venta', prefixText: r'$ '),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: const [MoneyInputFormatter()],
                    validator: (v) {
                      final value = double.tryParse((v ?? '').trim().replaceAll(',', '.'));
                      return (value == null || value <= 0) ? 'Requerido' : null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: entry.barcode,
                    decoration: const InputDecoration(labelText: 'Código de barras (opcional)'),
                    validator: (v) => _barcodeError(entry, v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ComboListField(
              combos: entry.combos,
              onChanged: (combos) {
                entry.combos = combos;
                controller.touch();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Promociones por cantidad de un producto o presentación ("2 por $0.25"),
/// con su botón para agregar más.
class ComboListField extends StatelessWidget {
  const ComboListField({super.key, required this.combos, required this.onChanged});

  final List<ProductCombo> combos;
  final ValueChanged<List<ProductCombo>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Promociones:', style: Theme.of(context).textTheme.bodySmall),
        for (final combo in combos)
          InputChip(
            label: Text('${combo.quantity} por ${formatCurrency(combo.priceCents / 100)}'),
            visualDensity: VisualDensity.compact,
            onDeleted: () => onChanged([...combos]..remove(combo)),
          ),
        ActionChip(
          avatar: const Icon(Icons.add, size: 16),
          label: const Text('Promoción'),
          visualDensity: VisualDensity.compact,
          onPressed: () async {
            final combo = await showComboDialog(context);
            if (combo == null) return;
            // Una sola promoción por cantidad: la nueva reemplaza a la anterior.
            final next = [...combos.where((c) => c.quantity != combo.quantity), combo]
              ..sort((a, b) => a.quantity.compareTo(b.quantity));
            onChanged(next);
          },
        ),
      ],
    );
  }
}

/// Pide una promoción por cantidad: cuántas unidades y cuánto cuestan en total.
Future<ProductCombo?> showComboDialog(BuildContext context) {
  return showDialog<ProductCombo>(
    context: context,
    builder: (context) => const _ComboDialog(),
  );
}

class _ComboDialog extends StatefulWidget {
  const _ComboDialog();

  @override
  State<_ComboDialog> createState() => _ComboDialogState();
}

class _ComboDialogState extends State<_ComboDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantity = TextEditingController(text: '2');
  final _price = TextEditingController();

  @override
  void dispose() {
    _quantity.dispose();
    _price.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      ProductCombo(
        quantity: int.parse(_quantity.text.trim()),
        priceCents: toCents(double.parse(_price.text.trim().replaceAll(',', '.'))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final quantity = int.tryParse(_quantity.text.trim());
    final price = double.tryParse(_price.text.trim().replaceAll(',', '.'));
    return AlertDialog(
      title: const Text('Promoción por cantidad'),
      content: SizedBox(
        width: 340,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(r'Ej. 2 bolsas por $0.25 aunque cada una cueste más.'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _quantity,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Cantidad que lleva el combo'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim());
                  return (n == null || n < 2) ? 'Debe ser 2 o más' : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _price,
                decoration: const InputDecoration(labelText: 'Precio de TODO el combo', prefixText: r'$ '),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: const [MoneyInputFormatter()],
                onChanged: (_) => setState(() {}),
                onFieldSubmitted: (_) => _submit(),
                validator: (v) {
                  final value = double.tryParse((v ?? '').trim().replaceAll(',', '.'));
                  return (value == null || value <= 0) ? 'Ingresa un precio válido' : null;
                },
              ),
              if (quantity != null && quantity >= 2 && price != null && price > 0) ...[
                const SizedBox(height: 12),
                Text(
                  '$quantity por ${formatCurrency(price)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
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
