import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Masir brand mark — minimal curved route ending at destination.
/// Recommended primary logo for map / navigation surfaces.
class MasirLogo extends StatelessWidget {
  const MasirLogo({
    super.key,
    this.size = 36,
    this.showWordmark = false,
    this.compact = false,
  });

  final double size;
  final bool showWordmark;
  final bool compact;

  static const brandGreen = Color(0xFF16A36A);
  static const brandDeep = Color(0xFF0F766E);

  @override
  Widget build(BuildContext context) {
    final mark = SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(size * 0.28),
          border: Border.all(
            color: brandGreen.withValues(alpha: 0.18),
            width: 1,
          ),
          boxShadow: compact
              ? null
              : const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
        ),
        child: Padding(
          padding: EdgeInsets.all(size * 0.18),
          child: CustomPaint(painter: _MasirMarkPainter()),
        ),
      ),
    );

    if (!showWordmark) return mark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        SizedBox(width: size * 0.28),
        Text(
          'مسیر',
          style: TextStyle(
            fontSize: size * 0.58,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
            height: 1,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : brandDeep,
          ),
        ),
      ],
    );
  }
}

class _MasirMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = MasirLogo.brandGreen
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.4, size.shortestSide * 0.14)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final start = Offset(size.width * 0.12, size.height * 0.78);
    final end = Offset(size.width * 0.78, size.height * 0.22);
    final c1 = Offset(size.width * 0.18, size.height * 0.28);
    final c2 = Offset(size.width * 0.62, size.height * 0.82);

    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
    canvas.drawPath(path, stroke);

    // Destination node
    final fill = Paint()..color = MasirLogo.brandGreen;
    canvas.drawCircle(end, size.shortestSide * 0.13, fill);

    // Subtle origin node (hollow)
    final hollow = Paint()
      ..color = MasirLogo.brandGreen
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.6, size.shortestSide * 0.08);
    canvas.drawCircle(start, size.shortestSide * 0.09, hollow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
