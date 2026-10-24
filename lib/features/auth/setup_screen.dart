import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../state/auth_provider.dart';
import '../../state/settings_provider.dart';
import 'widgets/pin_field.dart';

/// Primer arranque: se crea al administrador (dueño) con su PIN. Es el único
/// usuario que se puede crear sin haber entrado antes.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _business = TextEditingController();
  final _name = TextEditingController();
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _business.dispose();
    _name.dispose();
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final String? error;
    if (_business.text.trim().isEmpty) {
      error = 'Escribe el nombre de tu negocio';
    } else if (_business.text.trim().length > SettingsProvider.maxNameLength) {
      error = 'El nombre del negocio admite hasta ${SettingsProvider.maxNameLength} caracteres';
    } else if (_name.text.trim().isEmpty) {
      error = 'Escribe tu nombre';
    } else if (!isValidPin(_pin.text)) {
      error = 'El PIN debe tener de 4 a 6 dígitos';
    } else if (_pin.text != _confirm.text) {
      error = 'Los PIN no coinciden';
    } else {
      error = null;
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    // Al crearse el admin la sesión queda abierta y el router cambia de pantalla.
    await context.read<SettingsProvider>().setBusinessName(_business.text);
    if (!mounted) return;
    await context.read<AuthProvider>().createFirstAdmin(name: _name.text, pin: _pin.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                    Icon(Icons.admin_panel_settings, size: 40, color: theme.colorScheme.primary),
                    const SizedBox(height: 8),
                    Text('Configuración inicial', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    const Text(
                      'Escribe el nombre de tu negocio y crea al administrador. Con su PIN se entra al sistema '
                      'y se crean los cajeros. Anótalo en un lugar seguro: si se olvida, '
                      'no se puede recuperar.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _business,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Nombre del negocio'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Nombre del administrador'),
                    ),
                    const SizedBox(height: 12),
                    PinField(controller: _pin, label: 'PIN (4 a 6 dígitos)'),
                    const SizedBox(height: 12),
                    PinField(
                      controller: _confirm,
                      label: 'Repite el PIN',
                      errorText: _error,
                      onSubmitted: _submit,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _busy ? null : _submit, child: const Text('Crear y entrar')),
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
