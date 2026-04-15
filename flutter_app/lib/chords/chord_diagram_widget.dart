import 'package:flutter/material.dart';

import 'chord_models.dart';

/// 吉他和弦指法小图（6→1 弦：-1 闷音、0 空弦、>0 品位），与 Web 端 [ChordDiagram.vue] 布局思路一致。
class ChordDiagramWidget extends StatelessWidget {
  const ChordDiagramWidget({
    super.key,
    required this.frets,
    this.fingers,
    this.baseFret = 1,
    this.barre,
    this.width = 168,
    this.color,
  });

  final List<int> frets;
  final List<int?>? fingers;
  final int baseFret;
  final ChordBarre? barre;
  final double width;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurface;
    final h = width * 168 / 200;
    return CustomPaint(
      size: Size(width, h),
      painter: _ChordDiagramPainter(
        frets: frets,
        fingers: fingers,
        baseFret: baseFret,
        barre: barre,
        color: c,
      ),
    );
  }
}

/// 计算指板显示区间：避免高把位和弦挤在左上角。
@visibleForTesting
({int base, int rows, int maxF}) chordDiagramLayout(
  List<int> frets, {
  int baseFret = 1,
}) {
  var base = baseFret < 1 ? 1 : baseFret;
  final pressed = frets.where((f) => f > 0).toList();
  if (pressed.isNotEmpty) {
    final mn = pressed.reduce((a, b) => a < b ? a : b);
    if (base > mn) base = mn;
  }
  final maxF = pressed.isEmpty ? base : pressed.reduce((a, b) => a > b ? a : b);
  final span = (maxF - base + 1).clamp(1, 12);
  final rows = span.clamp(4, 5);
  return (base: base, rows: rows, maxF: maxF);
}

class _ChordDiagramPainter extends CustomPainter {
  _ChordDiagramPainter({
    required this.frets,
    required this.fingers,
    required this.baseFret,
    required this.barre,
    required this.color,
  });

  final List<int> frets;
  final List<int?>? fingers;
  final int baseFret;
  final ChordBarre? barre;
  final Color color;

  static const double _w = 200;
  static const double _h = 168;
  static const double _nutY = 32;
  static const double _fretH = 26;
  static const double _leftX = 22;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / _w;
    final sy = size.height / _h;
    canvas.save();
    canvas.scale(sx, sy);

    final layout = chordDiagramLayout(frets, baseFret: baseFret);
    final base = layout.base;
    final rows = layout.rows;

    double stringX(int i) => _leftX + (i * (_w - 2 * _leftX)) / 5;
    double dotY(int absFret) {
      final row = absFret - base + 1;
      return _nutY + (row - 0.5) * _fretH;
    }

    final openRing = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final faint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final nutPaint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    final stringPaint = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final tp = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    for (var i = 0; i < 6; i++) {
      final x = stringX(i);
      final f = frets[i];
      if (f < 0) {
        tp.text = TextSpan(
          text: '×',
          style: TextStyle(
            color: color.withValues(alpha: 0.7),
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        );
        tp.layout();
        tp.paint(canvas, Offset(x - tp.width / 2, 4));
      } else if (f == 0) {
        canvas.drawCircle(Offset(x, 14), 5, openRing);
      }
    }

    canvas.drawLine(
      Offset(_leftX - 4, _nutY),
      Offset(_w - _leftX + 4, _nutY),
      nutPaint,
    );

    for (var r = 1; r <= rows; r++) {
      canvas.drawLine(
        Offset(_leftX - 4, _nutY + r * _fretH),
        Offset(_w - _leftX + 4, _nutY + r * _fretH),
        faint,
      );
    }

    for (var i = 0; i < 6; i++) {
      canvas.drawLine(
        Offset(stringX(i), _nutY),
        Offset(stringX(i), _nutY + rows * _fretH),
        stringPaint,
      );
    }

    final b = barre;
    if (b != null && b.fret >= base && b.fret <= base + rows - 1) {
      final iLo = (6 - b.fromString).clamp(0, 5);
      final iHi = (6 - b.toString_).clamp(0, 5);
      final x1 = stringX(iLo < iHi ? iLo : iHi);
      final x2 = stringX(iLo > iHi ? iLo : iHi);
      final y = dotY(b.fret);
      canvas.drawLine(
        Offset(x1, y),
        Offset(x2, y),
        Paint()
          ..color = color.withValues(alpha: 0.85)
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round,
      );
    }

    final dotFill = Paint()
      ..color = color.withValues(alpha: 0.92)
      ..style = PaintingStyle.fill;

    for (var i = 0; i < 6; i++) {
      final f = frets[i];
      if (f <= 0) continue;
      final cx = stringX(i);
      final cy = dotY(f);
      canvas.drawCircle(Offset(cx, cy), 9, dotFill);

      final fi = fingers != null && i < fingers!.length ? fingers![i] : null;
      if (fi != null && fi > 0) {
        final dotLum = color.computeLuminance();
        final fg = dotLum > 0.55 ? Colors.black87 : Colors.white;
        tp.text = TextSpan(
          text: '$fi',
          style: TextStyle(
            color: fg,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        );
        tp.layout();
        tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2 + 1));
      }
    }

    if (base > 1) {
      tp.text = TextSpan(
        text: '${base}fr',
        style: TextStyle(
          color: color.withValues(alpha: 0.65),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      );
      tp.layout();
      tp.paint(canvas, Offset(4, _nutY + _fretH * 0.75 - tp.height / 2));
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ChordDiagramPainter oldDelegate) {
    return oldDelegate.frets != frets ||
        oldDelegate.fingers != fingers ||
        oldDelegate.baseFret != baseFret ||
        oldDelegate.barre != barre ||
        oldDelegate.color != color;
  }
}
