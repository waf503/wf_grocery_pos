import 'package:flutter/material.dart';

Future<double?> showOpenCashDialog(BuildContext context) {
  final controller = TextEditingController(text: '0');
  final formKey = GlobalKey<FormState>();
  return showDialog<double>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Abrir caja'),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Fondo inicial'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (v) => double.tryParse(v ?? '') == null ? 'Ingresa un monto válido' : null,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.of(context).pop(double.parse(controller.text));
            }
          },
          child: const Text('Abrir caja'),
        ),
      ],
    ),
  );
}
