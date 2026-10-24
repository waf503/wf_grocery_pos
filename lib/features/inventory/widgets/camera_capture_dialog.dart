import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../core/image/photo_processing.dart';

/// Abre la cámara web, deja encuadrar el producto y tomar la foto. Devuelve la
/// foto ya lista para guardar (cuadrada, reducida y comprimida) o `null` si
/// se cancela. Sirve para productos que no aparecen en internet.
Future<Uint8List?> showCameraCaptureDialog(BuildContext context) {
  return showDialog<Uint8List>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const _CameraCaptureDialog(),
  );
}

class _CameraCaptureDialog extends StatefulWidget {
  const _CameraCaptureDialog();

  @override
  State<_CameraCaptureDialog> createState() => _CameraCaptureDialogState();
}

class _CameraCaptureDialogState extends State<_CameraCaptureDialog> {
  List<CameraDescription> _cameras = const [];
  CameraDescription? _selected;
  CameraController? _controller;

  bool _busy = true; // abriendo la cámara o procesando la foto
  String? _error;
  Uint8List? _captured;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      _cameras = await availableCameras();
    } on CameraException catch (e) {
      _fail('No se pudo acceder a las cámaras: ${e.description ?? e.code}');
      return;
    } catch (_) {
      _fail('No se pudo acceder a las cámaras.');
      return;
    }
    if (_cameras.isEmpty) {
      _fail('No se detectó ninguna cámara. Conecta una cámara web y vuelve a intentarlo.');
      return;
    }
    await _start(_cameras.first);
  }

  Future<void> _start(CameraDescription camera) async {
    setState(() {
      _busy = true;
      _error = null;
      _selected = camera;
    });
    final old = _controller;
    _controller = null;
    await old?.dispose();

    // Resolución media (640x480): de sobra para una miniatura de 300 px.
    final controller = CameraController(camera, ResolutionPreset.medium, enableAudio: false);
    try {
      await controller.initialize();
    } on CameraException catch (e) {
      await controller.dispose();
      _fail('No se pudo abrir la cámara: ${e.description ?? e.code}. '
          'Revisa que otra aplicación no la esté usando.');
      return;
    } catch (_) {
      await controller.dispose();
      _fail('No se pudo abrir la cámara.');
      return;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {
      _controller = controller;
      _busy = false;
    });
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _busy = false;
    });
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _busy) return;
    setState(() => _busy = true);
    try {
      final file = await controller.takePicture();
      final photo = await prepareProductPhotoAsync(await file.readAsBytes());
      if (!mounted) return;
      setState(() {
        _captured = photo;
        _busy = false;
      });
    } on CameraException catch (e) {
      _fail('No se pudo tomar la foto: ${e.description ?? e.code}');
    } on FormatException {
      _fail('La foto no se pudo procesar. Inténtalo de nuevo.');
    } catch (_) {
      _fail('No se pudo tomar la foto.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final captured = _captured;
    return AlertDialog(
      title: const Text('Tomar foto del producto'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_cameras.length > 1 && captured == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DropdownButtonFormField<CameraDescription>(
                  initialValue: _selected,
                  decoration: const InputDecoration(labelText: 'Cámara'),
                  items: [
                    for (final camera in _cameras)
                      DropdownMenuItem(value: camera, child: Text(camera.name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: _busy ? null : (camera) => camera == null ? null : _start(camera),
                ),
              ),
            AspectRatio(aspectRatio: 1, child: _buildViewport(context, captured)),
            const SizedBox(height: 8),
            Text(
              captured == null
                  ? 'Centra el producto en el cuadro. Se guarda solo esa parte.'
                  : 'Así se verá la miniatura del producto.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        if (captured != null) ...[
          TextButton(onPressed: () => setState(() => _captured = null), child: const Text('Repetir')),
          FilledButton(onPressed: () => Navigator.of(context).pop(captured), child: const Text('Usar foto')),
        ] else
          FilledButton.icon(
            onPressed: (_controller == null || _busy) ? null : _capture,
            icon: const Icon(Icons.photo_camera),
            label: const Text('Capturar'),
          ),
      ],
    );
  }

  Widget _buildViewport(BuildContext context, Uint8List? captured) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(12);

    if (captured != null) {
      return ClipRRect(borderRadius: radius, child: Image.memory(captured, fit: BoxFit.cover));
    }
    if (_error != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: radius),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_off_outlined, size: 40, color: scheme.onErrorContainer),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: scheme.onErrorContainer)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: () { _init(); }, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return Container(
        decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: radius),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    // Vista previa recortada a un cuadrado: lo que se ve es lo que se guarda.
    final size = controller.value.previewSize ?? const Size(640, 480);
    return ClipRRect(
      borderRadius: radius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(width: size.width, height: size.height, child: CameraPreview(controller)),
          ),
          if (_busy) const ColoredBox(color: Colors.black38, child: Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }
}
