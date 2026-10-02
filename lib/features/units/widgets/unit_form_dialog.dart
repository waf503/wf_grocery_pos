import 'package:flutter/material.dart';

import '../../../models/unit.dart';

class UnitFormResult {
  UnitFormResult({required this.name, this.abbreviation, required this.allowsDecimals});

  final String name;
  final String? abbreviation;
  final bool allowsDecimals;
}

/// [nameTaken] avisa si el nombre ya lo usa OTRA unidad, para no duplicar.
Future<UnitFormResult?> showUnitFormDialog(
  BuildContext context, {
  required bool Function(String name, {String? exceptId}) nameTaken,
  Unit? existing,
}) {
  return showDialog<UnitFormResult>(
    context: context,
    builder: (context) => _UnitFormDialog(nameTaken: nameTaken, existing: existing),
  );
}

class _UnitFormDialog extends StatefulWidget {
  const _UnitFormDialog({required this.nameTaken, this.existing});

  final bool Function(String name, {String? exceptId}) nameTaken;
  final Unit? existing;

  @override
  State<_UnitFormDialog> createState() => _UnitFormDialogState();
}

class _UnitFormDialogState extends State<_UnitFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _abbreviation;
  late bool _allowsDecimals;

  @override
  void initState() {
    super.initState();
    final u = widget.existing;
    _name = TextEditingController(text: u?.name ?? '');
    _abbreviation = TextEditingController(text: u?.abbreviation ?? '');
    _allowsDecimals = u?.allowsDecimals ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _abbreviation.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final abbreviation = _abbreviation.text.trim();
    Navigator.of(context).pop(
      UnitFormResult(
        name: _name.text.trim(),
        abbreviation: abbreviation.isEmpty ? null : abbreviation,
        allowsDecimals: _allowsDecimals,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing != null ? 'Editar unidad' : 'Nueva unidad'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Ej. Libra'),
                validator: (value) {
                  final name = value?.trim() ?? '';
                  if (name.isEmpty) return 'Requerido';
                  if (widget.nameTaken(name, exceptId: widget.existing?.id)) {
                    return 'Ya existe una unidad con ese nombre';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _abbreviation,
                decoration: const InputDecoration(
                  labelText: 'Abreviatura (opcional)',
                  hintText: 'Ej. lb',
                  helperText: 'Se muestra junto a las cantidades',
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Permite decimales'),
                subtitle: const Text('Para productos que se pesan o miden, ej. 1.5 lb'),
                value: _allowsDecimals,
                onChanged: (value) => setState(() => _allowsDecimals = value),
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
