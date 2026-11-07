import 'package:flutter/material.dart';

import '../design/aritoria_design.dart';

class AritoriaFooterWave extends CustomPainter {
  const AritoriaFooterWave();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height * 0.35)
      ..cubicTo(
        size.width * 0.25,
        -size.height * 0.55,
        size.width * 0.42,
        size.height * 1.1,
        size.width * 0.65,
        size.height * 0.6,
      )
      ..cubicTo(
        size.width * 0.82,
        size.height * 0.1,
        size.width * 0.87,
        0,
        size.width,
        size.height * 0.25,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      path,
      Paint()..color = AritoriaColors.sand.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(AritoriaFooterWave oldDelegate) => false;
}
