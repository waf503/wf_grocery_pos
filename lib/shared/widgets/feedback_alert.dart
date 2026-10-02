import 'dart:async';

import 'package:flutter/material.dart';

enum FeedbackType { success, warning, error }

/// Alerta de retroalimentación centrada en pantalla (estilo SweetAlert):
/// una tarjeta con un ícono grande animado, un título y un mensaje, que se
/// cierra sola.
///
/// A diferencia de un `AlertDialog`, NO es modal ni roba el foco: se dibuja
/// en el `Overlay` y no intercepta clics ni teclado. Así, al escanear
/// productos en caja una tras otra, el campo de escaneo sigue activo y cada
/// alerta nueva reemplaza a la anterior sin acumularse.
class FeedbackAlert {
  FeedbackAlert._();

  static OverlayEntry? _entry;

  static void show(
    BuildContext context, {
    required FeedbackType type,
    required String title,
    String? message,
    Duration? duration,
  }) {
    _removeCurrent();
    final overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _FeedbackOverlay(
        type: type,
        title: title,
        message: message,
        visibleFor: duration ??
            (type == FeedbackType.success
                ? const Duration(milliseconds: 1300)
                : const Duration(milliseconds: 2800)),
        onDone: () {
          if (_entry == entry) _removeCurrent();
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  static void _removeCurrent() {
    final entry = _entry;
    if (entry == null) return;
    _entry = null;
    entry.remove();
    entry.dispose();
  }
}

class _FeedbackOverlay extends StatefulWidget {
  const _FeedbackOverlay({
    required this.type,
    required this.title,
    required this.message,
    required this.visibleFor,
    required this.onDone,
  });

  final FeedbackType type;
  final String title;
  final String? message;
  final Duration visibleFor;
  final VoidCallback onDone;

  @override
  State<_FeedbackOverlay> createState() => _FeedbackOverlayState();
}

class _FeedbackOverlayState extends State<_FeedbackOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _scale = CurvedAnimation(parent: _controller, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
    _hideTimer = Timer(widget.visibleFor, () {
      if (mounted) _controller.reverse().whenComplete(widget.onDone);
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  (IconData, Color) _style(ColorScheme scheme) {
    switch (widget.type) {
      case FeedbackType.success:
        return (Icons.check_rounded, const Color(0xFF2E7D32));
      case FeedbackType.warning:
        return (Icons.priority_high_rounded, const Color(0xFFEF6C00));
      case FeedbackType.error:
        return (Icons.close_rounded, scheme.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final (icon, color) = _style(scheme);

    return IgnorePointer(
      child: Center(
        child: FadeTransition(
          opacity: _opacity,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.7, end: 1).animate(_scale),
            child: Material(
              color: scheme.surface,
              elevation: 16,
              shadowColor: Colors.black54,
              borderRadius: BorderRadius.circular(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 420, maxWidth: 620),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(48, 40, 48, 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 132,
                        height: 132,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withValues(alpha: 0.14),
                          border: Border.all(color: color, width: 5),
                        ),
                        child: Icon(icon, size: 84, color: color),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        widget.title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (widget.message != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          widget.message!,
                          textAlign: TextAlign.center,
                          style: textTheme.headlineSmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
