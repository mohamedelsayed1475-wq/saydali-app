import 'package:flutter/material.dart';

class PharmacyLogo extends StatelessWidget {
  final double size;
  final List<Color>? colors;

  const PharmacyLogo({
    super.key,
    this.size = 24,
    this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final gradientColors = colors ?? [const Color(0xFF00D4B4), const Color(0xFF00A07A)];
    
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PharmacyLogoPainter(colors: gradientColors),
      ),
    );
  }
}

class _PharmacyLogoPainter extends CustomPainter {
  final List<Color> colors;

  _PharmacyLogoPainter({required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = LinearGradient(
        colors: colors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect)
      ..style = PaintingStyle.fill;

    // 1. Draw Crescent Moon (C shape opening to the right)
    final outerCircle = Path()..addOval(Rect.fromLTWH(0, 0, size.width, size.height));
    final innerCircle = Path()..addOval(Rect.fromLTWH(
      size.width * 0.22,
      size.height * 0.08,
      size.width * 0.84,
      size.height * 0.84,
    ));
    final crescentPath = Path.combine(PathOperation.difference, outerCircle, innerCircle);
    canvas.drawPath(crescentPath, paint);

    // 2. Draw a stylized Leaf inside the crescent opening
    final leafPaint = Paint()
      ..shader = LinearGradient(
        colors: [colors.last, colors.first], // reverse gradient for contrast
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
      ).createShader(rect)
      ..style = PaintingStyle.fill;

    final leafPath = Path();
    // Start at bottom of leaf (around center-right)
    leafPath.moveTo(size.width * 0.58, size.height * 0.58);
    // Right curve of leaf to the top-right tip
    leafPath.quadraticBezierTo(
      size.width * 0.82, size.height * 0.42,
      size.width * 0.72, size.height * 0.25,
    );
    // Left curve of leaf back to bottom
    leafPath.quadraticBezierTo(
      size.width * 0.48, size.height * 0.38,
      size.width * 0.58, size.height * 0.58,
    );
    
    // Draw leaf stem
    final stemPaint = Paint()
      ..shader = paint.shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.04
      ..strokeCap = StrokeCap.round;

    final stemPath = Path();
    stemPath.moveTo(size.width * 0.58, size.height * 0.58);
    stemPath.quadraticBezierTo(
      size.width * 0.52, size.height * 0.65,
      size.width * 0.45, size.height * 0.68,
    );

    canvas.drawPath(leafPath, leafPaint);
    canvas.drawPath(stemPath, stemPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
