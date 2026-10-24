import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../shared/widgets/feedback_alert.dart';
import '../../shared/widgets/section_header.dart';
import '../../state/auth_provider.dart';
import 'data/user_repository.dart';
import 'widgets/pin_field.dart';

/// Administración de usuarios (solo administrador): crear cajeros y
/// administradores, cambiar nombre o rol, restablecer el PIN y desactivar.
class UsersScreen extends StatelessWidget {
  const UsersScreen({super.key});

  Future<void> _run(BuildContext context, Future<void> Function() action, {String? success}) async {
    try {
      await action();
      if (success != null && context.mounted) {
        FeedbackAlert.show(context, type: FeedbackType.success, title: success);
      }
    } on LastAdminException catch (e) {
      if (context.mounted) FeedbackAlert.show(context, type: FeedbackType.error, title: e.toString());
    } on DuplicateUserNameException catch (e) {
      if (context.mounted) FeedbackAlert.show(context, type: FeedbackType.error, title: e.toString());
    }
  }

  Future<void> _add(BuildContext context, AuthProvider auth) async {
    final result = await showDialog<_UserFormResult>(
      context: context,
      builder: (_) => const _UserFormDialog(),
    );
    if (result == null || !context.mounted) return;
    await _run(
      context,
      () => auth.addUser(name: result.name, role: result.role, pin: result.pin!),
      success: 'Usuario creado',
    );
  }

  Future<void> _edit(BuildContext context, AuthProvider auth, AppUser user) async {
    final result = await showDialog<_UserFormResult>(
      context: context,
      builder: (_) => _UserFormDialog(user: user),
    );
    if (result == null || !context.mounted) return;
    await _run(
      context,
      () => auth.updateUser(user.id, name: result.name, role: result.role),
      success: 'Usuario actualizado',
    );
  }

  Future<void> _resetPin(BuildContext context, AuthProvider auth, AppUser user) async {
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => _NewPinDialog(userName: user.name),
    );
    if (pin == null || !context.mounted) return;
    await _run(context, () => auth.resetPin(user.id, pin), success: 'PIN actualizado');
  }

  Future<void> _delete(BuildContext context, AuthProvider auth, AppUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Eliminar a ${user.name}?'),
        content: const Text(
          'Ya no podrá entrar al sistema. Sus ventas anteriores se conservan con su nombre. '
          'Si solo quieres impedir que entre por un tiempo, mejor desactívalo.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _run(context, () => auth.deleteUser(user.id), success: 'Usuario eliminado');
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);
    final me = auth.currentUser;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Usuarios',
            subtitle: 'Quién puede entrar al sistema y qué puede hacer',
            actions: [
              FilledButton.icon(
                onPressed: () => _add(context, auth),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Nuevo usuario'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Administrador: ve y cambia todo. Cajero: cobra, maneja la caja y atiende clientes; '
            'para anular una venta necesita el PIN de un administrador.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                for (final user in auth.users)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Icon(user.isAdmin ? Icons.admin_panel_settings : Icons.point_of_sale),
                      ),
                      title: Text(user.id == me?.id ? '${user.name} (tú)' : user.name),
                      subtitle: Text(user.active ? user.role.label : '${user.role.label} · desactivado'),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: 'Editar',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _edit(context, auth, user),
                          ),
                          IconButton(
                            tooltip: 'Cambiar PIN',
                            icon: const Icon(Icons.password),
                            onPressed: () => _resetPin(context, auth, user),
                          ),
                          // Nadie se desactiva ni se elimina a sí mismo (se quedaría fuera).
                          if (user.id != me?.id) ...[
                            IconButton(
                              tooltip: user.active ? 'Desactivar' : 'Reactivar',
                              icon: Icon(user.active ? Icons.person_off_outlined : Icons.person_outline),
                              onPressed: () => _run(
                                context,
                                () => auth.updateUser(user.id, active: !user.active),
                                success: user.active ? 'Usuario desactivado' : 'Usuario reactivado',
                              ),
                            ),
                            IconButton(
                              tooltip: 'Eliminar',
                              icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                              onPressed: () => _delete(context, auth, user),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UserFormResult {
  _UserFormResult(this.name, this.role, this.pin);

  final String name;
  final UserRole role;

  /// Solo al crear.
  final String? pin;
}

class _UserFormDialog extends StatefulWidget {
  const _UserFormDialog({this.user});

  final AppUser? user;

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  late final _name = TextEditingController(text: widget.user?.name ?? '');
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  late UserRole _role = widget.user?.role ?? UserRole.cashier;
  String? _error;

  bool get _creating => widget.user == null;

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    final String? error;
    if (_name.text.trim().isEmpty) {
      error = 'Escribe el nombre';
    } else if (_creating && !isValidPin(_pin.text)) {
      error = 'El PIN debe tener de 4 a 6 dígitos';
    } else if (_creating && _pin.text != _confirm.text) {
      error = 'Los PIN no coinciden';
    } else {
      error = null;
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(_UserFormResult(_name.text, _role, _creating ? _pin.text : null));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_creating ? 'Nuevo usuario' : 'Editar usuario'),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: 12),
              SegmentedButton<UserRole>(
                segments: [
                  for (final role in UserRole.values) ButtonSegment(value: role, label: Text(role.label)),
                ],
                selected: {_role},
                onSelectionChanged: (selection) => setState(() => _role = selection.single),
              ),
              if (_creating) ...[
                const SizedBox(height: 12),
                PinField(controller: _pin, label: 'PIN (4 a 6 dígitos)'),
                const SizedBox(height: 12),
                PinField(controller: _confirm, label: 'Repite el PIN', onSubmitted: _submit),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: _submit, child: Text(_creating ? 'Crear' : 'Guardar')),
      ],
    );
  }
}

class _NewPinDialog extends StatefulWidget {
  const _NewPinDialog({required this.userName});

  final String userName;

  @override
  State<_NewPinDialog> createState() => _NewPinDialogState();
}

class _NewPinDialogState extends State<_NewPinDialog> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    if (!isValidPin(_pin.text)) {
      setState(() => _error = 'El PIN debe tener de 4 a 6 dígitos');
    } else if (_pin.text != _confirm.text) {
      setState(() => _error = 'Los PIN no coinciden');
    } else {
      Navigator.of(context).pop(_pin.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Nuevo PIN para ${widget.userName}'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PinField(controller: _pin, label: 'PIN nuevo', autofocus: true),
            const SizedBox(height: 12),
            PinField(controller: _confirm, label: 'Repite el PIN', errorText: _error, onSubmitted: _submit),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: _submit, child: const Text('Guardar')),
      ],
    );
  }
}
