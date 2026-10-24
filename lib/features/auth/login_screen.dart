import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../state/auth_provider.dart';
import '../../state/settings_provider.dart';
import 'data/user_repository.dart';
import 'widgets/pin_field.dart';

/// Acceso con PIN: se elige el usuario y se escribe su PIN.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _pin = TextEditingController();
  String? _selectedId;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit(AuthProvider auth) async {
    final id = _selectedId;
    if (id == null || _busy) return;
    if (!isValidPin(_pin.text)) {
      setState(() => _error = 'El PIN tiene de 4 a 6 dígitos');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await auth.login(id, _pin.text);
      // El router redirige solo al detectar la sesión.
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
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);
    final users = auth.activeUsers;
    // Con un solo usuario se elige solo.
    final selected = _selectedId ?? (users.length == 1 ? users.single.id : null);
    _selectedId = selected;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.storefront, size: 40, color: theme.colorScheme.primary),
                    const SizedBox(height: 8),
                    Text(context.watch<SettingsProvider>().businessName, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text(
                      selected == null ? '¿Quién va a usar el sistema?' : 'Escribe tu PIN',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final user in users)
                          ChoiceChip(
                            avatar: Icon(user.isAdmin ? Icons.admin_panel_settings : Icons.point_of_sale, size: 18),
                            label: Text('${user.name} · ${user.role.label}'),
                            selected: user.id == selected,
                            onSelected: (_) => setState(() {
                              _selectedId = user.id;
                              _error = null;
                              _pin.clear();
                            }),
                          ),
                      ],
                    ),
                    if (selected != null) ...[
                      const SizedBox(height: 16),
                      PinField(
                        controller: _pin,
                        autofocus: true,
                        errorText: _error,
                        onSubmitted: () => _submit(auth),
                        onChanged: () => setState(() => _error = null),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: PinKeypad(
                          controller: _pin,
                          onChanged: () => setState(() => _error = null),
                          onSubmit: () => _submit(auth),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _busy ? null : () => _submit(auth),
                        child: const Text('Entrar'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
