import 'package:flutter/material.dart';

import 'paper.dart';

enum PaperGlyph {
  shuffle,
  tag,
  filter,
  play,
  horizontal,
  vertical,
  grid,
  settings,
  history,
  more,
  expand,
}

/// Paper's outlined tool shapes; button labels own their accessibility names.
class PaperIcon extends StatelessWidget {
  const PaperIcon(this.glyph, {super.key, this.size = 21, this.color});
  final PaperGlyph glyph;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size.square(size),
      painter: _PaperIconPainter(
        glyph,
        color ?? IconTheme.of(context).color ?? Paper.of(context).olive,
      ),
    ),
  );
}

class _PaperIconPainter extends CustomPainter {
  const _PaperIconPainter(this.glyph, this.color);
  final PaperGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    switch (glyph) {
      case PaperGlyph.grid:
        for (final y in [3.0, 14.0]) {
          for (final x in [3.0, 14.0]) {
            path.addRRect(
              RRect.fromRectAndRadius(
                Rect.fromLTWH(x, y, 7, 7),
                const Radius.circular(1),
              ),
            );
          }
        }
      case PaperGlyph.settings:
        path
          ..moveTo(4, 7)
          ..lineTo(20, 7)
          ..moveTo(4, 17)
          ..lineTo(20, 17)
          ..addOval(Rect.fromCircle(center: const Offset(9, 7), radius: 3))
          ..addOval(Rect.fromCircle(center: const Offset(16, 17), radius: 3));
      case PaperGlyph.history:
        path
          ..moveTo(4, 5)
          ..lineTo(4, 10)
          ..lineTo(9, 10)
          ..moveTo(4, 10)
          ..arcToPoint(
            const Offset(5, 18),
            radius: const Radius.circular(8),
            largeArc: true,
          )
          ..moveTo(12, 7)
          ..lineTo(12, 13)
          ..lineTo(16, 15);
      case PaperGlyph.more:
        for (final x in [5.0, 12.0, 19.0]) {
          path.addOval(Rect.fromCircle(center: Offset(x, 12), radius: 1));
        }
      case PaperGlyph.expand:
        path
          ..moveTo(8, 3)
          ..lineTo(3, 3)
          ..lineTo(3, 8)
          ..moveTo(16, 3)
          ..lineTo(21, 3)
          ..lineTo(21, 8)
          ..moveTo(3, 16)
          ..lineTo(3, 21)
          ..lineTo(8, 21)
          ..moveTo(16, 21)
          ..lineTo(21, 21)
          ..lineTo(21, 16);
      case PaperGlyph.horizontal:
        path
          ..addRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(5, 3, 14, 18),
              const Radius.circular(1),
            ),
          )
          ..moveTo(1, 12)
          ..lineTo(6, 12)
          ..moveTo(18, 12)
          ..lineTo(23, 12);
      case PaperGlyph.vertical:
        path
          ..addRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(5, 2, 14, 8),
              const Radius.circular(1),
            ),
          )
          ..addRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(5, 14, 14, 8),
              const Radius.circular(1),
            ),
          );
      case PaperGlyph.shuffle:
        path
          ..moveTo(3, 6)
          ..lineTo(6, 6)
          ..lineTo(18, 18)
          ..lineTo(21, 18)
          ..moveTo(17, 14)
          ..lineTo(21, 18)
          ..lineTo(17, 22)
          ..moveTo(3, 18)
          ..lineTo(6, 18)
          ..lineTo(18, 6)
          ..lineTo(21, 6)
          ..moveTo(17, 2)
          ..lineTo(21, 6)
          ..lineTo(17, 10);
      case PaperGlyph.tag:
        path
          ..moveTo(3, 3)
          ..lineTo(12, 3)
          ..lineTo(21, 12)
          ..lineTo(12, 21)
          ..lineTo(3, 12)
          ..close()
          ..addOval(Rect.fromCircle(center: const Offset(8, 8), radius: 1.5));
      case PaperGlyph.play:
        path
          ..addRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(3, 3, 18, 18),
              const Radius.circular(3),
            ),
          )
          ..moveTo(10, 8)
          ..lineTo(16, 12)
          ..lineTo(10, 16)
          ..close();
      case PaperGlyph.filter:
        path
          ..moveTo(3, 6)
          ..lineTo(21, 6)
          ..moveTo(6, 12)
          ..lineTo(18, 12)
          ..moveTo(9, 18)
          ..lineTo(15, 18);
    }
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    if (glyph == PaperGlyph.settings) {
      final fill = Paint()..color = color;
      canvas.drawCircle(const Offset(9, 7), 3, fill);
      canvas.drawCircle(const Offset(16, 17), 3, fill);
    }
    canvas.drawPath(path, stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PaperIconPainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.color != color;
}
