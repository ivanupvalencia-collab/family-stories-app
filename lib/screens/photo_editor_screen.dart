import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../design/aritoria_design.dart';
import '../services/photo_crop_service.dart';
import '../services/profile_image_picker.dart';

class PhotoEditorScreen extends StatefulWidget {
  const PhotoEditorScreen({
    required this.image,
    this.service = const PhotoCropService(),
    super.key,
  });
  final PickedProfileImage image;
  final PhotoCropService service;

  @override
  State<PhotoEditorScreen> createState() => _PhotoEditorScreenState();
}

class _PhotoEditorScreenState extends State<PhotoEditorScreen> {
  ui.Image? _image;
  SquarePhotoCrop? _crop;
  bool _failed = false, _saving = false;
  double _startZoom = 1;
  Offset _anchor = Offset.zero;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    try {
      final image = await widget.service.decode(widget.image);
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() {
        _image = image;
        _crop = SquarePhotoCrop(
          Size(image.width.toDouble(), image.height.toDouble()),
        );
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _save() async {
    final image = _image;
    final crop = _crop;
    if (_saving || image == null || crop == null) return;
    setState(() => _saving = true);
    try {
      // Keep an independent image handle alive if this route is removed externally.
      final retained = image.clone();
      late final PickedProfileImage result;
      try {
        result = await widget.service.crop(retained, crop.source);
      } finally {
        retained.dispose();
      }
      if (mounted) Navigator.of(context).pop(result);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo ajustar la foto. Inténtalo de nuevo.'),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: AritoriaDesign.theme(),
    child: PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
          ),
        ),
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, viewport) => Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AritoriaSpace.maxWidth,
                ),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Ajusta la foto',
                          textAlign: TextAlign.center,
                          style: AritoriaType.brand,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Mueve y amplía la imagen para elegir el encuadre.',
                          textAlign: TextAlign.center,
                          style: AritoriaType.body.copyWith(
                            color: AritoriaColors.muted,
                          ),
                        ),
                        const SizedBox(height: 24),
                        LayoutBuilder(
                          builder: (context, area) {
                            final side = math.min(
                              area.maxWidth,
                              math.max(180.0, viewport.maxHeight * .54),
                            );
                            return Center(
                              child: SizedBox.square(
                                dimension: side,
                                child: _image == null
                                    ? Center(
                                        child: _failed
                                            ? const Text(
                                                'No se pudo abrir esta imagen. Prueba con otra foto.',
                                                textAlign: TextAlign.center,
                                              )
                                            : const CircularProgressIndicator(),
                                      )
                                    : GestureDetector(
                                        key: const ValueKey('photo-crop-area'),
                                        behavior: HitTestBehavior.opaque,
                                        onScaleStart: _saving
                                            ? null
                                            : (details) {
                                                _startZoom = _crop!.zoom;
                                                _anchor = _crop!.imagePoint(
                                                  details.localFocalPoint,
                                                  side,
                                                );
                                              },
                                        onScaleUpdate: _saving
                                            ? null
                                            : (details) => setState(() {
                                                _crop!.gesture(
                                                  _startZoom * details.scale,
                                                  _anchor,
                                                  details.localFocalPoint,
                                                  side,
                                                );
                                              }),
                                        child: CustomPaint(
                                          painter: _CropPreview(
                                            _image!,
                                            _crop!.source,
                                          ),
                                        ),
                                      ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            const Icon(
                              Icons.zoom_out,
                              color: AritoriaColors.olive,
                            ),
                            Expanded(
                              child: Slider(
                                key: const ValueKey('photo-crop-zoom'),
                                min: 1,
                                max: SquarePhotoCrop.maxZoom,
                                value: _crop?.zoom ?? 1,
                                semanticFormatterCallback: (value) =>
                                    '${value.toStringAsFixed(1)} aumentos',
                                onChanged: _crop == null || _saving
                                    ? null
                                    : (value) =>
                                          setState(() => _crop!.update(value)),
                              ),
                            ),
                            const Icon(
                              Icons.zoom_in,
                              color: AritoriaColors.olive,
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: _saving
                                    ? null
                                    : () => Navigator.pop(context),
                                style: TextButton.styleFrom(
                                  backgroundColor: AritoriaColors.softOlive,
                                  minimumSize: const Size(0, 52),
                                ),
                                child: const Text('Cancelar'),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: FilledButton(
                                key: const ValueKey('photo-crop-save'),
                                onPressed: _image == null || _saving
                                    ? null
                                    : _save,
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(0, 52),
                                ),
                                child: Text(_saving ? 'Guardando…' : 'Guardar'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _CropPreview extends CustomPainter {
  const _CropPreview(this.image, this.source);
  final ui.Image image;
  final Rect source;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawImageRect(
      image,
      source,
      bounds,
      Paint()..filterQuality = FilterQuality.medium,
    );
    final frame = Paint()
      ..color = AritoriaColors.onPhoto
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    // Straight square output; these corner guides are only a preview overlay.
    final edge = size.shortestSide * .07;
    final inset = 3.0;
    for (final corner in [
      Offset(inset, inset),
      Offset(size.width - inset, inset),
      Offset(inset, size.height - inset),
      Offset(size.width - inset, size.height - inset),
    ]) {
      final dx = corner.dx < size.width / 2 ? edge : -edge;
      final dy = corner.dy < size.height / 2 ? edge : -edge;
      canvas.drawPath(
        Path()
          ..moveTo(corner.dx + dx, corner.dy)
          ..lineTo(corner.dx, corner.dy)
          ..lineTo(corner.dx, corner.dy + dy),
        frame,
      );
    }
  }

  @override
  bool shouldRepaint(_CropPreview oldDelegate) =>
      image != oldDelegate.image || source != oldDelegate.source;
}
