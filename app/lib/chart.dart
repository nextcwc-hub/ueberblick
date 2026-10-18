import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'theme.dart';
import 'i18n.dart';

enum TimeFmt { intraday, week, days, months }


List<String> get _wd => weekdaysShort;
List<String> get _mo => monthsLong;

String fmtTime(DateTime d, TimeFmt f, {bool long = false}) => switch (f) {
      TimeFmt.intraday => long ? '${_wd[d.weekday - 1]}, ${two(d.day)}.${two(d.month)}., ${two(d.hour)}:${two(d.minute)}${uiEn ? '' : ' Uhr'}' : '${two(d.hour)}:${two(d.minute)}',
      TimeFmt.week => long ? '${_wd[d.weekday - 1]}, ${two(d.day)}.${two(d.month)}., ${two(d.hour)}:${two(d.minute)}${uiEn ? '' : ' Uhr'}' : '${_wd[d.weekday - 1]} ${two(d.hour)}h',
      TimeFmt.days => long ? '${_wd[d.weekday - 1]}, ${two(d.day)}.${two(d.month)}.${d.year}' : '${two(d.day)}.${two(d.month)}.',
      TimeFmt.months => long ? '${_mo[d.month - 1]} ${d.year}' : '${two(d.month)}/${d.year % 100}',
    };

class ChartMarker {
  final DateTime time;
  final Story story;
  ChartMarker(this.time, this.story);
}

/// Kursdiagramm mit Achsen, Fadenkreuz (exakte Zeit + Wert) und antippbaren Nachrichten-Markierungen.
class PriceChart extends StatefulWidget {
  final List<List<double>> pts; // [unix-sek, wert]
  final double? baseline;
  final Color color;
  final int digits;
  final TimeFmt fmt;
  final List<ChartMarker> markers;
  final ValueChanged<Story>? onMarker;
  const PriceChart(
      {super.key,
      required this.pts,
      required this.color,
      required this.digits,
      required this.fmt,
      this.baseline,
      this.markers = const [],
      this.onMarker});

  @override
  State<PriceChart> createState() => _PriceChartState();
}

class _PriceChartState extends State<PriceChart> {
  int? sel;
  static const axisW = 64.0, axisH = 22.0, tipH = 40.0;

  List<(int, ChartMarker)> _placed() {
    final p = widget.pts;
    if (p.length < 2) return [];
    final out = <(int, ChartMarker)>[];
    for (final m in widget.markers) {
      final t = m.time.millisecondsSinceEpoch / 1000;
      if (t < p.first[0] || t > p.last[0] + 3600) continue;
      var i = p.indexWhere((x) => x[0] >= t);
      if (i < 0) i = p.length - 1;
      out.add((i, m));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pts;
    if (p.length < 2) {
      return Center(child: Text('Keine Daten für diesen Zeitraum', style: sans(context, 13, color: muted(context))));
    }
    final placed = _placed();
    return LayoutBuilder(builder: (context, bc) {
      final plotW = bc.maxWidth - axisW;
      double xOf(int i) => i / (p.length - 1) * plotW;
      int idxAt(double dx) => (dx / plotW * (p.length - 1)).round().clamp(0, p.length - 1);

      void pick(Offset o) {
        final i = idxAt(o.dx);
        if (i != sel) HapticFeedback.selectionClick();
        setState(() => sel = i);
      }

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (d) => pick(d.localPosition),
        onHorizontalDragUpdate: (d) => pick(d.localPosition),
        onHorizontalDragEnd: (_) => setState(() => sel = null),
        onLongPressStart: (d) => pick(d.localPosition),
        onLongPressMoveUpdate: (d) => pick(d.localPosition),
        onLongPressEnd: (_) => setState(() => sel = null),
        onTapUp: (d) {
          // Nachrichtenmarker antippen?
          for (final (i, m) in placed) {
            if ((xOf(i) - d.localPosition.dx).abs() < 18 && d.localPosition.dy > bc.maxHeight - axisH - 34) {
              widget.onMarker?.call(m.story);
              return;
            }
          }
          pick(d.localPosition);
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) setState(() => sel = null);
          });
        },
        child: Stack(children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _ChartPainter(
                pts: p,
                baseline: widget.baseline,
                color: widget.color,
                digits: widget.digits,
                fmt: widget.fmt,
                sel: sel,
                markers: placed.map((e) => e.$1).toList(),
                fg: Theme.of(context).colorScheme.onSurface,
                mut: muted(context),
                grid: Theme.of(context).colorScheme.outlineVariant,
                surface: Theme.of(context).colorScheme.surface,
              ),
            ),
          ),
          if (sel != null)
            Positioned(
              top: 0,
              left: 0,
              right: axisW,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.onSurface, borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    '${fmtNum(p[sel!][1], digits: widget.digits)}   ·   '
                    '${fmtTime(DateTime.fromMillisecondsSinceEpoch((p[sel!][0] * 1000).toInt()), widget.fmt, long: true)}',
                    style: sans(context, 12.5, w: FontWeight.w600, color: Theme.of(context).colorScheme.surface),
                  ),
                ),
              ),
            ),
        ]),
      );
    });
  }
}

class _ChartPainter extends CustomPainter {
  final List<List<double>> pts;
  final double? baseline;
  final Color color, fg, mut, grid, surface;
  final int digits;
  final TimeFmt fmt;
  final int? sel;
  final List<int> markers;
  _ChartPainter(
      {required this.pts,
      required this.baseline,
      required this.color,
      required this.digits,
      required this.fmt,
      required this.sel,
      required this.markers,
      required this.fg,
      required this.mut,
      required this.grid,
      required this.surface});

  static (double, double, double) niceRange(double lo, double hi, int ticks) {
    final span = max(hi - lo, hi.abs() * 1e-4 + 1e-9);
    final raw = span / ticks;
    final mag = pow(10, (log(raw) / ln10).floor()).toDouble();
    final norm = raw / mag;
    final step = (norm < 1.5 ? 1 : norm < 3 ? 2 : norm < 7 ? 5 : 10) * mag;
    return ((lo / step).floor() * step, (hi / step).ceil() * step, step);
  }

  void _text(Canvas c, String s, Offset o, Color col, {double size = 11, bool right = false, bool center = false}) {
    final tp = TextPainter(
        text: TextSpan(text: s, style: TextStyle(color: col, fontSize: size, fontFeatures: const [FontFeature.tabularFigures()])),
        textDirection: TextDirection.ltr)
      ..layout();
    var dx = o.dx;
    if (right) dx -= tp.width;
    if (center) dx -= tp.width / 2;
    tp.paint(c, Offset(dx, o.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    const axisW = _PriceChartState.axisW, axisH = _PriceChartState.axisH, top = _PriceChartState.tipH;
    final w = size.width - axisW, h = size.height - axisH - top;
    var lo = pts.map((p) => p[1]).reduce(min), hi = pts.map((p) => p[1]).reduce(max);
    if (baseline != null) {
      lo = min(lo, baseline!);
      hi = max(hi, baseline!);
    }
    final (nlo, nhi, step) = niceRange(lo, hi, 4);
    lo = nlo;
    hi = nhi;
    double y(double v) => top + h - (v - lo) / (hi - lo) * h;
    double x(int i) => i / (pts.length - 1) * w;

    // Raster + Y-Achse
    final gp = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final yd = step >= 1 ? 0 : (step >= 0.1 ? 1 : (step >= 0.01 ? 2 : 4));
    for (var v = lo; v <= hi + step / 2; v += step) {
      canvas.drawLine(Offset(0, y(v)), Offset(w, y(v)), gp);
      _text(canvas, fmtNum(v, digits: min(yd, digits)), Offset(w + 8, y(v)), mut);
    }
    // X-Achse: 4 Zeitmarken
    for (var k = 0; k < 4; k++) {
      final i = ((pts.length - 1) * (k + 0.5) / 4).round();
      final d = DateTime.fromMillisecondsSinceEpoch((pts[i][0] * 1000).toInt());
      canvas.drawLine(Offset(x(i), top + h), Offset(x(i), top + h + 4), gp);
      _text(canvas, fmtTime(d, fmt), Offset(x(i), top + h + 13), mut, center: true);
    }
    // Vortageslinie
    if (baseline != null) {
      final by = y(baseline!);
      final dash = Paint()
        ..color = mut
        ..strokeWidth = 1;
      for (var dx = 0.0; dx < w; dx += 7) {
        canvas.drawLine(Offset(dx, by), Offset(min(dx + 3.5, w), by), dash);
      }
    }
    // Linie + Fläche
    final path = Path()..moveTo(x(0), y(pts[0][1]));
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(x(i), y(pts[i][1]));
    }
    final area = Path.from(path)
      ..lineTo(w, top + h)
      ..lineTo(0, top + h)
      ..close();
    canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.20), color.withValues(alpha: 0.0)],
          ).createShader(Rect.fromLTWH(0, top, w, h)));
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round);
    // Nachrichtenmarker
    for (final i in markers) {
      final o = Offset(x(i), top + h - 12);
      canvas.drawLine(Offset(x(i), y(pts[i][1])), o, Paint()
        ..color = fg.withValues(alpha: 0.35)
        ..strokeWidth = 1);
      canvas.drawCircle(o, 7.5, Paint()..color = fg);
      _text(canvas, 'N', o, surface, size: 9.5, center: true);
    }
    // Fadenkreuz
    if (sel != null) {
      final o = Offset(x(sel!), y(pts[sel!][1]));
      canvas.drawLine(Offset(o.dx, top), Offset(o.dx, top + h), Paint()
        ..color = fg.withValues(alpha: 0.5)
        ..strokeWidth = 1);
      canvas.drawCircle(o, 6, Paint()..color = surface);
      canvas.drawCircle(o, 4.5, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.pts != pts || old.sel != sel || old.color != color || old.markers.length != markers.length || old.fg != fg;
}
