import 'package:flutter/material.dart';

import '../../catalog/catalog_item.dart';

/// Muestra "Buscando información del producto..." mientras se consulta un
/// código de barras. Se cierra sola al terminar y devuelve el resultado; si
/// el usuario pulsa "Omitir" devuelve `null` y sigue con el formulario vacío
/// (la consulta no debe bloquear el registro si internet va lento).
Future<LookupResult?> runLookupWithDialog(BuildContext context, Future<LookupResult> lookup) {
  return showDialog<LookupResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _LookupProgressDialog(lookup: lookup),
  );
}

class _LookupProgressDialog extends StatefulWidget {
  const _LookupProgressDialog({required this.lookup});

  final Future<LookupResult> lookup;

  @override
  State<_LookupProgressDialog> createState() => _LookupProgressDialogState();
}

class _LookupProgressDialogState extends State<_LookupProgressDialog> {
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    widget.lookup.then(_finish, onError: (_) => _finish(const LookupResult()));
  }

  void _finish(LookupResult? result) {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
          SizedBox(width: 16),
          Flexible(child: Text('Buscando información del producto...')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => _finish(null), child: const Text('Omitir')),
      ],
    );
  }
}
