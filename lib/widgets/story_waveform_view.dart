import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/aritoria_design.dart';

/// Real, uniformly spaced RMS samples; progress/gestures use the existing player.
class StoryWaveformView extends StatelessWidget {
  const StoryWaveformView({
    required this.samples,
    required this.progress,
    required this.onChanged,
    required this.onChangeEnd,
    this.onCancel,
    super.key,
  });
  final List<double> samples;
  final double progress;
  final ValueChanged<double>? onChanged, onChangeEnd;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: LayoutBuilder(
      builder: (context, constraints) {
        double fraction(Offset offset) =>
            (offset.dx / constraints.maxWidth).clamp(0.0, 1.0);
        return Semantics(
          label: 'Posición del audio',
          value: '${(progress * 100).round()} %',
          increasedValue: '${((progress + .05).clamp(0, 1) * 100).round()} %',
          decreasedValue: '${((progress - .05).clamp(0, 1) * 100).round()} %',
          slider: true,
          onIncrease: onChangeEnd == null
              ? null
              : () => onChangeEnd!((progress + .05).clamp(0, 1)),
          onDecrease: onChangeEnd == null
              ? null
              : () => onChangeEnd!((progress - .05).clamp(0, 1)),
          child: GestureDetector(
            key: const ValueKey('story-waveform'),
            behavior: HitTestBehavior.opaque,
            onTapUp: onChangeEnd == null
                ? null
                : (event) => onChangeEnd!(fraction(event.localPosition)),
            onHorizontalDragStart: onChanged == null
                ? null
                : (event) => onChanged!(fraction(event.localPosition)),
            onHorizontalDragUpdate: onChanged == null
                ? null
                : (event) => onChanged!(fraction(event.localPosition)),
            onHorizontalDragEnd: onChangeEnd == null
                ? null
                : (event) => onChangeEnd!(fraction(event.localPosition)),
            onHorizontalDragCancel: onCancel,
            child: CustomPaint(
              size: Size.infinite,
              painter: _WaveformPainter(samples, progress),
            ),
          ),
        );
      },
    ),
  );
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter(this.samples, this.progress);
  final List<double> samples;
  final double progress;
  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty || size.width <= 0) return;
    final bars = math.min(
      samples.length,
      math.max(1, (size.width / 5).floor()),
    );
    final paint = Paint()
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (var bar = 0; bar < bars; bar++) {
      final start = bar * samples.length ~/ bars;
      final end = (bar + 1) * samples.length ~/ bars;
      var peak = 0.0;
      for (var i = start; i < end; i++) {
        peak = math.max(peak, samples[i]);
      }
      final x = (bar + .5) * size.width / bars;
      final half = math.max(1.0, peak * (size.height - 4) / 2);
      paint.color = (bar + .5) / bars <= progress
          ? AritoriaColors.olive
          : AritoriaColors.sage.withValues(alpha: .55);
      canvas.drawLine(
        Offset(x, size.height / 2 - half),
        Offset(x, size.height / 2 + half),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      oldDelegate.samples != samples || oldDelegate.progress != progress;
}
