import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/app_user.dart';
import '../../../state/auth_provider.dart';
import '../data/user_repository.dart';
import 'pin_field.dart';

/// Pide el PIN de un administrador para autorizar una acción (por ejemplo,
/// anular una venta desde una sesión de cajero). Devuelve el administrador que
/// autorizó, o null si se canceló.
Future<AppUser?> showAdminPinDialog(
  BuildContext context, {
  String title = 'Autorización del administrador',
  String message = 'Esta acción necesita el PIN de un administrador.',
}) {
  return showDialog<AppUser>(
    context: context,
    builder: (context) => _AdminPinDialog(title: title, message: message),
  );
}

class _AdminPinDialog extends StatefulWidget {
  const _AdminPinDialog({required this.title, required this.message});

  final String title;
  final String message;

  @override
  State<_AdminPinDialog> createState() => _AdminPinDialogState();
}

class _AdminPinDialogState extends State<_AdminPinDialog> {
  final _pin = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!isValidPin(_pin.text)) {
      setState(() => _error = 'El PIN tiene de 4 a 6 dígitos');
      return;
    }
    setState(() => _busy = true);
    try {
      final admin = await context.read<AuthProvider>().authorizeWithAdminPin(_pin.text);
      if (mounted) Navigator.of(context).pop(admin);
      return;
    } on LockedOutException catch (e) {
      _error = e.toString();
    } on InvalidCredentialsException {
      _error = 'PIN incorrecto';
    }
    if (!mounted) return;
    _pin.clear();
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.message),
            const SizedBox(height: 12),
            PinField(
              controller: _pin,
              label: 'PIN del administrador',
              autofocus: true,
              errorText: _error,
              onSubmitted: _submit,
              onChanged: () => setState(() => _error = null),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: _busy ? null : _submit, child: const Text('Autorizar')),
      ],
    );
  }
}
