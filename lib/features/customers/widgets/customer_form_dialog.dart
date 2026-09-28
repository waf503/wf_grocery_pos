import 'package:flutter/material.dart';

import '../../../models/customer.dart';

Future<Customer?> showCustomerFormDialog(
  BuildContext context, {
  Customer? existing,
  required String Function() nextId,
}) {
  return showDialog<Customer>(
    context: context,
    builder: (context) => _CustomerFormDialog(existing: existing, nextId: nextId),
  );
}

class _CustomerFormDialog extends StatefulWidget {
  const _CustomerFormDialog({this.existing, required this.nextId});

  final Customer? existing;
  final String Function() nextId;

  @override
  State<_CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends State<_CustomerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _name = TextEditingController(text: c?.name ?? '');
    _phone = TextEditingController(text: c?.phone ?? '');
    _email = TextEditingController(text: c?.email ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final customer = Customer(
      id: widget.existing?.id ?? widget.nextId(),
      name: _name.text.trim(),
      phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      email: _email.text.trim().isEmpty ? null : _email.text.trim(),
      balance: widget.existing?.balance ?? 0,
    );
    Navigator.of(context).pop(customer);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing != null ? 'Editar cliente' : 'Nuevo cliente'),
      content: SizedBox(
        width: 380,
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
                controller: _phone,
                decoration: const InputDecoration(labelText: 'Teléfono (opcional)'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Correo (opcional)'),
                keyboardType: TextInputType.emailAddress,
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
