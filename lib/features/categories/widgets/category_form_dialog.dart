import 'package:flutter/material.dart';

import '../../../models/category.dart';
import '../category_icon_options.dart';

class CategoryFormResult {
  CategoryFormResult({required this.name, this.description, this.parentId, this.icon});

  final String name;
  final String? description;
  final String? parentId;
  final String? icon;
}

/// [selectableParents] ya debe venir filtrada por quien llama (sin la
/// categoría que se está editando ni sus descendientes), para no permitir
/// crear un ciclo en el árbol.
Future<CategoryFormResult?> showCategoryFormDialog(
  BuildContext context, {
  required List<Category> selectableParents,
  Category? existing,
  String? initialParentId,
}) {
  return showDialog<CategoryFormResult>(
    context: context,
    builder: (context) => _CategoryFormDialog(
      selectableParents: selectableParents,
      existing: existing,
      initialParentId: initialParentId,
    ),
  );
}

class _CategoryFormDialog extends StatefulWidget {
  const _CategoryFormDialog({
    required this.selectableParents,
    this.existing,
    this.initialParentId,
  });

  final List<Category> selectableParents;
  final Category? existing;
  final String? initialParentId;

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
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      CategoryFormResult(
        name: _name.text.trim(),
        description: _description.text.trim().isEmpty ? null : _description.text.trim(),
        parentId: _parentId,
        icon: _iconId,
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
