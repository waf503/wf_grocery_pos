import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/image/disk_image_picker.dart';
import '../../../core/image/photo_processing.dart';
import '../../../core/money.dart';
import '../../../core/text/product_tags.dart';
import '../../../models/category.dart';
import '../../catalog/catalog_item.dart';
import 'camera_capture_dialog.dart';
import 'presentations_editor.dart';
import '../../../models/product.dart';
import '../../../models/product_combo.dart';
import '../../../models/unit.dart';
import '../../../shared/widgets/feedback_alert.dart';

class ProductFormResult {
  ProductFormResult({
    required this.name,
    required this.categoryId,
    required this.unitId,
    required this.priceCents,
    required this.costCents,
    required this.stock,
    required this.minStock,
    this.barcode,
    this.extraTags = '',
    this.image,
    this.imageChanged = false,
    this.presentations = const [],
    this.combos = const [],
    this.rootUnitsPerPack = 1,
    this.stockScale = 1,
  });

  /// Cuántas unidades de la unidad MÁS PEQUEÑA del grupo vale el producto (1 si
  /// él es la más pequeña; 200 si es un paquete con 200 cigarros sueltos).
  final int rootUnitsPerPack;

  /// Cuánto se multiplican las existencias ya guardadas porque la unidad más
  /// pequeña cambió (de paquetes a cigarros: ×200). 1 si no cambia.
  final double stockScale;

  /// Presentaciones del producto (cajetilla, paquete...): la lista COMPLETA,
  /// no solo las nuevas. Vacía = el producto no tiene presentaciones.
  final List<PresentationDraft> presentations;

  /// Promociones por cantidad del producto (ej. 2 por $0.25).
  final List<ProductCombo> combos;

  /// Miniatura final del producto (`null` = sin imagen).
  final Uint8List? image;

  /// `true` si el usuario cambió o quitó la imagen que ya tenía.
  final bool imageChanged;

  final String name;
  final String categoryId;
  final String unitId;
  final int priceCents;
  final int costCents;
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
  CatalogItem? suggested,
  Uint8List? existingImage,
  List<Product> existingPresentations = const [],
  bool startWithNewPresentation = false,
  Future<Uint8List?> Function()? pickImageFile,
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
      suggested: suggested,
      existingImage: existingImage,
      existingPresentations: existingPresentations,
      startWithNewPresentation: startWithNewPresentation,
      pickImageFile: pickImageFile ?? pickImageFromDisk,
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
    this.suggested,
    this.existingImage,
    this.existingPresentations = const [],
    this.startWithNewPresentation = false,
    required this.pickImageFile,
  });

  /// Cómo se elige una imagen del disco (el selector de archivos del sistema).
  final Future<Uint8List?> Function() pickImageFile;

  /// Abre la lista de presentaciones con una nueva en blanco (para "Agregar
  /// presentación" desde la fila del producto).
  final bool startWithNewPresentation;

  /// Presentaciones que ya tiene el producto que se edita.
  final List<Product> existingPresentations;
  final CatalogItem? suggested;
  final Uint8List? existingImage;

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
  late final PresentationsController _presentations;
  List<ProductCombo> _combos = [];
  bool _showPresentations = false;
  late String _categoryId;

  /// Unidad elegida. Nula en un producto nuevo: el usuario debe escogerla
  /// (no se deja una por defecto para que no se guarde una equivocada).
  String? _unitId;
  late final Uint8List? _initialImage;
  Uint8List? _image;

  Unit? get _selectedUnit {
    for (final u in widget.units) {
      if (u.id == _unitId) return u;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _name = TextEditingController(text: p?.name ?? widget.suggested?.suggestedName ?? '');
    // La imagen sugerida solo se usa en altas; al editar manda la que ya tenía.
    _initialImage = widget.existingImage;
    _image = widget.existingImage ?? (p == null ? widget.suggested?.imageBytes : null);
    _price = TextEditingController(text: p != null ? p.price.toStringAsFixed(2) : '');
    _cost = TextEditingController(text: p != null ? p.cost.toStringAsFixed(2) : '');
    // Las existencias se editan en la unidad más pequeña del grupo (el pool).
    _stock = TextEditingController(text: p != null ? p.poolUnits.toString() : '');
    _minStock = TextEditingController(text: p != null ? p.minStock.toString() : '5');
    _barcode = TextEditingController(text: p?.barcode ?? widget.initialBarcode ?? '');
    _extraTags = TextEditingController(text: p != null ? _extraTagsOf(p) : '');
    _combos = [...?p?.combos];
    final rootFactor = (p?.unitsPerPack ?? 1).round();
    _presentations = PresentationsController(
      [for (final child in widget.existingPresentations) _entryFor(child, p, rootFactor)],
      currentRootFactor: rootFactor < 1 ? 1 : rootFactor,
    );
    _showPresentations = !_presentations.isEmpty;
    if (widget.startWithNewPresentation) {
      _presentations.add();
      _showPresentations = true;
    }
    _categoryId = p?.categoryId ?? widget.categories.first.id;
    _unitId = widget.units.any((u) => u.id == p?.unitId) ? p!.unitId : null;
  }

  /// Tags guardados que NO vienen del nombre: son las etiquetas que escribió
  /// el usuario, y las que se vuelven a mostrar al editar.
  String _extraTagsOf(Product product) {
    final fromName = tagWords(product.name).toSet();
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
    _presentations.dispose();
    super.dispose();
  }

  /// Abre la cámara web para fotografiar el producto.
  Future<void> _takePhoto() async {
    final photo = await showCameraCaptureDialog(context);
    if (photo != null && mounted) setState(() => _image = photo);
  }

  /// Sube una imagen del disco como miniatura: se recorta al centro en
  /// cuadrado, se reduce y se comprime, igual que las fotos de la cámara.
  Future<void> _uploadImage() async {
    try {
      final raw = await widget.pickImageFile();
      if (raw == null) return; // el usuario canceló
      final photo = await prepareProductPhotoAsync(raw);
      if (mounted) setState(() => _image = photo);
    } on FormatException {
      if (!mounted) return;
      FeedbackAlert.show(
        context,
        type: FeedbackType.warning,
        title: 'No se pudo usar esa imagen',
        message: 'Elige una foto JPG, PNG o WebP de menos de 25 MB',
      );
    } catch (_) {
      if (!mounted) return;
      FeedbackAlert.show(context, type: FeedbackType.error, title: 'No se pudo abrir el archivo');
    }
  }

  /// Reconstruye cómo se relaciona una presentación que ya existe con el
  /// producto base: si contiene un número entero de bases ("contiene 20"), o si
  /// el base contiene un número entero de ella ("viene dentro, 200 por cada
  /// uno"). Si ninguna de las dos cuadra, conserva su medida tal cual.
  PresentationEntry _entryFor(Product child, Product? root, int rootFactor) {
    final f = child.unitsPerPack.round();
    final fb = rootFactor < 1 ? 1 : rootFactor;
    var inside = false;
    int? count;
    int? fixed;
    if (f % fb == 0) {
      count = f ~/ fb;
    } else if (fb % f == 0) {
      inside = true;
      count = fb ~/ f;
    } else {
      fixed = f;
    }
    return PresentationEntry(
      id: child.id,
      name: child.name,
      count: count == null ? '' : count.toString(),
      inside: inside,
      fixedPoolUnits: fixed,
      price: (child.priceCents / 100).toStringAsFixed(2),
      barcode: child.barcode ?? '',
      combos: child.combos,
      // Si el costo es el calculado desde el del base (repartido por tamaño) se
      // sigue calculando solo; si se fijó a mano, se respeta.
      explicitCostCents:
          (root != null && child.costCents == (child.unitsPerPack * root.costCents / root.unitsPerPack).round())
              ? null
              : child.costCents,
    );
  }

  void _submit() {
    final formOk = _formKey.currentState!.validate();
    // La unidad más pequeña del grupo y cuántas de ellas vale cada presentación.
    final layout = _presentations.computeLayout().layout;
    final drafts = layout == null ? null : _presentations.buildDrafts(layout);
    if (!formOk || drafts == null || layout == null) {
      // Si el problema está en las presentaciones y están ocultas, se abren
      // para que se vean los errores.
      if (drafts == null && !_showPresentations) {
        setState(() => _showPresentations = true);
        WidgetsBinding.instance.addPostFrameCallback((_) => _formKey.currentState?.validate());
      }
      return;
    }
    Navigator.of(context).pop(
      ProductFormResult(
        name: _name.text.trim(),
        categoryId: _categoryId,
        unitId: _unitId!,
        priceCents: toCents(double.parse(_price.text)),
        // Vacío = se calcula después, al agregar inventario con el costo por paquete.
        costCents: toCents(double.tryParse(_cost.text.trim().replaceAll(',', '.')) ?? 0),
        // Vacío = todavía no se sabe cuánto hay: se crea en cero y después se usa "Agregar inventario".
        stock: double.tryParse(_stock.text.trim().replaceAll(',', '.')) ?? 0,
        minStock: double.parse(_minStock.text),
        barcode: _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
        extraTags: _extraTags.text.trim(),
        image: _image,
        imageChanged: !identical(_image, _initialImage),
        presentations: drafts,
        combos: _combos,
        rootUnitsPerPack: layout.rootUnitsPerPack,
        stockScale: layout.stockScale,
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

  /// Costo: se puede dejar vacío; si se escribe debe ser un número.
  String? _optionalNumberValidator(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return _numberValidator(value);
  }

  /// Existencias: se puede dejar vacío (aún no se sabe cuánto hay).
  String? _optionalStockValidator(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return _quantityValidator(value);
  }

  /// Igual que [_numberValidator], pero además exige un número entero cuando
  /// la unidad elegida no permite decimales (ej. no existen 2.5 gaseosas).
  String? _quantityValidator(String? value) {
    final error = _numberValidator(value);
    if (error != null) return error;
    final number = double.parse(value!);
    final unit = _selectedUnit;
    // Sin unidad elegida todavía no se puede saber si admite decimales: el
    // propio campo de unidad avisará que falta.
    if (unit != null && !unit.allowsDecimals && number != number.roundToDouble()) {
      return 'La unidad "${unit.name}" no permite decimales';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    return AlertDialog(
      title: Text(isEditing ? 'Editar producto' : 'Nuevo producto'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.suggested != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.auto_awesome, size: 18, color: Theme.of(context).colorScheme.onSecondaryContainer),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Datos sugeridos de ${widget.suggested!.source}. '
                            'Revisa el nombre, la categoría y el precio antes de guardar.',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSecondaryContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                // Imagen del producto: la sugerida de internet, o una foto tomada
                // con la cámara web (para productos que no están en internet).
                Row(
                  children: [
                    if (_image != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(_image!, width: 120, height: 120, fit: BoxFit.cover),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _takePhoto,
                            icon: const Icon(Icons.photo_camera_outlined, size: 18),
                            label: const Text('Tomar foto'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _uploadImage,
                            icon: const Icon(Icons.upload_file_outlined, size: 18),
                            label: const Text('Subir imagen'),
                          ),
                          if (_image != null)
                            TextButton.icon(
                              onPressed: () => setState(() => _image = null),
                              icon: const Icon(Icons.delete_outline, size: 18),
                              label: const Text('Quitar'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
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
                // Los tags se generan solos con las palabras del TÍTULO del
                // producto (más las etiquetas extra que escriba el usuario); se
                // muestran para ver con qué palabras se va a poder encontrar.
                ListenableBuilder(
                  listenable: Listenable.merge([_name, _extraTags]),
                  builder: (context, _) {
                    final tags = buildTags(_name.text, extra: _extraTags.text)
                        .split(' ')
                        .where((t) => t.isNotEmpty)
                        .toList();
                    if (tags.isEmpty) return const SizedBox(height: 12);
                    return Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text('Etiquetas:', style: Theme.of(context).textTheme.bodySmall),
                            for (final tag in tags)
                              Chip(
                                label: Text(tag),
                                visualDensity: VisualDensity.compact,
                                labelStyle: Theme.of(context).textTheme.bodySmall,
                                padding: EdgeInsets.zero,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
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
                        hint: const Text('Selecciona'),
                        items: [
                          for (final u in widget.units) DropdownMenuItem(value: u.id, child: Text(u.name)),
                        ],
                        onChanged: (value) => setState(() => _unitId = value),
                        validator: (value) => value == null ? 'Requerido' : null,
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
                        decoration: InputDecoration(
                          labelText: 'Costo (opcional)',
                          helperText: widget.existing == null ? 'Se calcula al agregar inventario' : null,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: _optionalNumberValidator,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ComboListField(
                    combos: _combos,
                    onChanged: (combos) => setState(() => _combos = combos),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ListenableBuilder(
                        listenable: _presentations,
                        builder: (context, _) {
                          // Con presentaciones, las existencias se llevan en la
                          // unidad más pequeña. Se puede dejar vacío: después
                          // se agrega con "Agregar inventario" (por cajetillas,
                          // paquetes, etc.).
                          final hasPacks = !_presentations.isEmpty || _presentations.currentRootFactor > 1;
                          return TextFormField(
                            controller: _stock,
                            decoration: InputDecoration(
                              labelText: hasPacks ? 'Existencias (en unidades)' : 'Existencias',
                              hintText: '0',
                              helperText: widget.existing == null ? 'Déjalo vacío si aún no sabes cuánto hay' : null,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            validator: _optionalStockValidator,
                          );
                        },
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
                    if (code.isNotEmpty && _presentations.entries.any((e) => e.barcode.text.trim() == code)) {
                      return 'Este código ya lo usa una presentación';
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
                const SizedBox(height: 12),
                // Presentaciones: la misma mercancía en otros empaques (cajetilla,
                // paquete...), cada una con su precio y código.
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => _showPresentations = !_showPresentations),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.inventory_2_outlined, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ListenableBuilder(
                            listenable: _presentations,
                            builder: (context, _) => Text(
                              _presentations.isEmpty
                                  ? 'Presentaciones (cajetilla, paquete...)'
                                  : 'Presentaciones (${_presentations.entries.length})',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                        ),
                        Icon(_showPresentations ? Icons.expand_less : Icons.expand_more),
                      ],
                    ),
                  ),
                ),
                if (_showPresentations)
                  PresentationsEditor(
                    controller: _presentations,
                    baseName: () => _name.text,
                    baseBarcode: () => _barcode.text,
                    isBarcodeTaken: widget.isBarcodeTaken,
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
