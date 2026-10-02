import 'package:flutter/material.dart';

import '../../../core/theme/category_colors.dart';
import '../../../models/category.dart';
import '../category_icon_options.dart';

class CategoryFormResult {
  CategoryFormResult({required this.name, this.description, this.parentId, this.icon, this.color});

  final String name;
  final String? description;
  final String? parentId;
  final String? icon;

  /// Color ARGB elegido; nulo = hereda el de la categoría padre.
  final int? color;
}

/// [selectableParents] ya debe venir filtrada por quien llama (sin la
/// categoría que se está editando ni sus descendientes), para no permitir
/// crear un ciclo en el árbol.
Future<CategoryFormResult?> showCategoryFormDialog(
  BuildContext context, {
  required List<Category> selectableParents,
  Category? existing,
  String? initialParentId,
  int? suggestedColor,
}) {
  return showDialog<CategoryFormResult>(
    context: context,
    builder: (context) => _CategoryFormDialog(
      selectableParents: selectableParents,
      existing: existing,
      initialParentId: initialParentId,
      suggestedColor: suggestedColor,
    ),
  );
}

class _CategoryFormDialog extends StatefulWidget {
  const _CategoryFormDialog({
    required this.selectableParents,
    this.existing,
    this.initialParentId,
    this.suggestedColor,
  });

  final List<Category> selectableParents;
  final Category? existing;
  final String? initialParentId;
  final int? suggestedColor;

  @override
  State<_CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends State<_CategoryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  final TextEditingController _iconSearch = TextEditingController();
  String? _parentId;
  String? _iconId;
  int? _color;
  final TextEditingController _hex = TextEditingController();

  /// Mientras el usuario no haya tocado el selector a mano, cada letra que
  /// escribe en "Nombre" puede seguir actualizando la sugerencia — en
  /// cuanto elige un ícono el mismo, dejamos de sugerir para no pisotear
  /// su elección.
  bool _iconChosenManually = false;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _name = TextEditingController(text: c?.name ?? '');
    _description = TextEditingController(text: c?.description ?? '');
    _parentId = c?.parentId ?? widget.initialParentId;
    _iconId = c?.icon;
    // Al crear una categoría raíz se sugiere un color libre de la paleta; una
    // subcategoría nueva arranca heredando el de su padre.
    _color = c != null ? c.color : (widget.initialParentId == null ? widget.suggestedColor : null);
    if (_color != null) _hex.text = toHexColor(_color!);
    _iconChosenManually = c?.icon != null;
    _name.addListener(_onNameChanged);
  }

  void _onNameChanged() {
    if (_iconChosenManually) return;
    final suggestion = suggestIconFor(_name.text);
    if (suggestion != null && suggestion != _iconId) {
      setState(() => _iconId = suggestion);
    }
  }

  @override
  void dispose() {
    _name.removeListener(_onNameChanged);
    _name.dispose();
    _description.dispose();
    _iconSearch.dispose();
    _hex.dispose();
    super.dispose();
  }

  void _chooseColor(int? value) {
    setState(() {
      _color = value;
      _hex.text = value == null ? '' : toHexColor(value);
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      CategoryFormResult(
        name: _name.text.trim(),
        description: _description.text.trim().isEmpty ? null : _description.text.trim(),
        parentId: _parentId,
        icon: _iconId,
        color: _color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final query = _iconSearch.text.trim().toLowerCase();
    final visibleIcons = query.isEmpty
        ? categoryIconOptions
        : categoryIconOptions.where((o) => o.keywords.any((k) => k.contains(query))).toList();

    return AlertDialog(
      title: Text(widget.existing != null ? 'Editar categoría' : 'Nueva categoría'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nombre'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _parentId,
                decoration: const InputDecoration(labelText: 'Categoría padre (opcional)'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('— Ninguna (raíz) —')),
                  for (final c in widget.selectableParents)
                    DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
                ],
                onChanged: (value) => setState(() => _parentId = value),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Color', style: Theme.of(context).textTheme.labelLarge),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 132,
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Tooltip(
                        message: 'Heredar del padre',
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => _chooseColor(null),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _color == null ? scheme.primary : scheme.outline,
                                width: _color == null ? 3 : 1,
                              ),
                            ),
                            child: Icon(Icons.block, size: 16, color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ),
                      for (final value in categoryColorPalette)
                        InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => _chooseColor(value),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(value),
                              border: _color == value ? Border.all(color: scheme.onSurface, width: 3) : null,
                            ),
                            child: _color == value
                                ? const Icon(Icons.check, size: 18, color: Colors.white)
                                : null,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _color != null ? Color(_color!) : null,
                      border: Border.all(color: scheme.outline),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _hex,
                      decoration: const InputDecoration(
                        labelText: 'Color personalizado',
                        hintText: '#43A047',
                        isDense: true,
                      ),
                      onChanged: (text) {
                        final parsed = parseHexColor(text);
                        if (parsed != null) setState(() => _color = parsed);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Ícono', style: Theme.of(context).textTheme.labelLarge),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _iconSearch,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search, size: 20),
                  hintText: 'Buscar ícono (ej. bebida, limpieza...)',
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 140,
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _IconChoice(
                        icon: defaultCategoryIcon.icon,
                        selected: _iconId == null,
                        color: scheme.primary,
                        tooltip: 'Sin ícono (genérico)',
                        onTap: () => setState(() {
                          _iconId = null;
                          _iconChosenManually = true;
                        }),
                      ),
                      for (final option in visibleIcons)
                        _IconChoice(
                          icon: option.icon,
                          selected: option.id == _iconId,
                          color: scheme.primary,
                          onTap: () => setState(() {
                            _iconId = option.id;
                            _iconChosenManually = true;
                          }),
                        ),
                    ],
                  ),
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

class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? color.withValues(alpha: 0.15) : null,
          border: Border.all(color: selected ? color : Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Icon(icon, color: selected ? color : null, size: 20),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}
