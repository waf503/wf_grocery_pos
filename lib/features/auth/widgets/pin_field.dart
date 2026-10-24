import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Campo de PIN: solo dígitos (hasta 6), oculto con puntos.
class PinField extends StatelessWidget {
  const PinField({
    super.key,
    required this.controller,
    this.label = 'PIN',
    this.autofocus = false,
    this.errorText,
    this.onSubmitted,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final String? errorText;
  final VoidCallback? onSubmitted;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      obscureText: true,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      maxLength: 6,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(letterSpacing: 8),
      decoration: InputDecoration(labelText: label, counterText: '', errorText: errorText),
      onChanged: (_) => onChanged?.call(),
      onSubmitted: (_) => onSubmitted?.call(),
    );
  }
}

/// Teclado numérico en pantalla, para pantallas táctiles.
class PinKeypad extends StatelessWidget {
  const PinKeypad({super.key, required this.controller, this.onChanged, this.onSubmit});

  final TextEditingController controller;
  final VoidCallback? onChanged;
  final VoidCallback? onSubmit;

  void _digit(String d) {
    if (controller.text.length >= 6) return;
    controller.text += d;
    onChanged?.call();
  }

  void _backspace() {
    if (controller.text.isEmpty) return;
    controller.text = controller.text.substring(0, controller.text.length - 1);
    onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    Widget key(String label, VoidCallback onTap, {IconData? icon}) => Padding(
          padding: const EdgeInsets.all(4),
          child: SizedBox(
            width: 64,
            height: 48,
            child: OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
              child: icon != null ? Icon(icon) : Text(label, style: Theme.of(context).textTheme.titleLarge),
            ),
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [for (final d in row) key(d, () => _digit(d))],
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            key('', _backspace, icon: Icons.backspace_outlined),
            key('0', () => _digit('0')),
            key('', () => onSubmit?.call(), icon: Icons.check),
          ],
        ),
      ],
    );
  }
}
