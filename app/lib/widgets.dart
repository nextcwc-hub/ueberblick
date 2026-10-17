import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'data.dart';
import 'models.dart';
import 'theme.dart';

/// Bild oder – falls keins vorhanden – eine ruhige, typografische Kategorie-Fläche.
class StoryImage extends StatelessWidget {
  final Story s;
  final double radius;
  final bool large;
  const StoryImage(this.s, {super.key, this.radius = 6, this.large = false});

  @override
  Widget build(BuildContext context) {
    final child = s.img == null
        ? CatArt(s.cat, large: large, seed: s.id.hashCode)
        : CachedNetworkImage(
            imageUrl: s.img!.url,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 180),
            placeholder: (_, _) => Container(color: Theme.of(context).colorScheme.surfaceContainer),
            errorWidget: (_, _, _) => CatArt(s.cat, large: large, seed: s.id.hashCode),
          );
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: child);
  }
}

class CatArt extends StatelessWidget {
  final String cat;
  final bool large;
  final int seed;
  const CatArt(this.cat, {super.key, this.large = false, this.seed = 0});

  @override
  Widget build(BuildContext context) {
    final c = catOf(cat);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = Color.lerp(c.color, dark ? Colors.black : Colors.white, dark ? 0.55 : 0.82)!;
    return Container(
      color: bg,
      child: CustomPaint(
        painter: _LinesPainter(c.color.withValues(alpha: dark ? 0.35 : 0.22), seed),
        child: Center(
          child: Icon(c.icon, size: large ? 56 : 28, color: c.color.withValues(alpha: dark ? 0.9 : 0.75)),
        ),
      ),
    );
  }
}

class _LinesPainter extends CustomPainter {
  final Color color;
  final int seed;
  _LinesPainter(this.color, this.seed);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final r = Random(seed);
    final phase = r.nextDouble() * pi * 2;
    for (var k = 0; k < 7; k++) {
      final path = Path();
      final y0 = size.height * (0.15 + k * 0.12);
      for (var x = 0.0; x <= size.width; x += 4) {
        final y = y0 + sin(x / size.width * pi * 2 + phase + k * 0.5) * size.height * 0.06;
        x == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(covariant _LinesPainter old) => old.color != color || old.seed != seed;
}

class Kicker extends StatelessWidget {
  final Story s;
  final bool showTime;
  const Kicker(this.s, {super.key, this.showTime = true});

  @override
  Widget build(BuildContext context) {
    final c = catOf(s.cat);
    final style = sans(context, 11.5, w: FontWeight.w600, ls: 0.6, color: c.color);
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
      if (s.isBreaking)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          decoration: BoxDecoration(color: breaking, borderRadius: BorderRadius.circular(3)),
          child: Text('EILMELDUNG', style: sans(context, 10, w: FontWeight.w700, ls: 0.6, color: Colors.white)),
        ),
      Text(c.name.toUpperCase(), style: Theme.of(context).brightness == Brightness.dark
          ? style.copyWith(color: Color.lerp(c.color, Colors.white, 0.35)) : style),
      if (showTime) ...[
        Text('·', style: sans(context, 12, color: muted(context))),
        Text(s.wasUpdated ? 'aktualisiert ${ago(s.updated)}' : ago(s.created),
            style: sans(context, 12, color: muted(context))),
      ],
    ]);
  }
}

class HeroCard extends StatelessWidget {
  final Story s;
  final VoidCallback onTap;
  const HeroCard(this.s, {super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(aspectRatio: 16 / 9, child: StoryImage(s, large: true, radius: 8)),
          const SizedBox(height: 12),
          Kicker(s),
          const SizedBox(height: 6),
          Text(s.title, style: serif(context, 25, w: FontWeight.w700, h: 1.18)),
          const SizedBox(height: 8),
          Text(s.teaser, style: sans(context, 15, color: muted(context), h: 1.45)),
          const SizedBox(height: 8),
          SourceLine(s),
        ]),
      ),
    );
  }
}

class SourceLine extends StatelessWidget {
  final Story s;
  const SourceLine(this.s, {super.key});
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(Icons.layers_outlined, size: 14, color: muted(context)),
        const SizedBox(width: 4),
        Text(s.srcn == 1 ? '1 Quelle' : '${s.srcn} Quellen', style: sans(context, 12, color: muted(context))),
        if (s.loc.isNotEmpty) ...[
          const SizedBox(width: 10),
          Icon(Icons.place_outlined, size: 14, color: muted(context)),
          const SizedBox(width: 2),
          Flexible(child: Text(s.loc, overflow: TextOverflow.ellipsis, style: sans(context, 12, color: muted(context)))),
        ],
      ]);
}

class StoryTile extends StatelessWidget {
  final Story s;
  final VoidCallback onTap;
  const StoryTile(this.s, {super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Kicker(s),
              const SizedBox(height: 5),
              Text(s.title, style: serif(context, 18, h: 1.25)),
              const SizedBox(height: 5),
              Text(s.teaser,
                  maxLines: app.detailed ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: sans(context, 13.5, color: muted(context), h: 1.4)),
            ]),
          ),
          const SizedBox(width: 14),
          SizedBox(width: 92, height: 92, child: StoryImage(s)),
        ]),
      ),
    );
  }
}

/// Kurz/Ausführlich-Umschalter
class ModeSwitch extends StatelessWidget {
  final bool detailed;
  final ValueChanged<bool> onChanged;
  const ModeSwitch({super.key, required this.detailed, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget seg(String label, bool value) {
      final sel = detailed == value;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: sel ? cs.surfaceContainerLowest : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
              boxShadow: sel ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4, offset: const Offset(0, 1))] : null,
            ),
            child: Text(label,
                style: sans(context, 13.5, w: sel ? FontWeight.w600 : FontWeight.w500, color: sel ? cs.onSurface : muted(context))),
          ),
        ),
      );
    }

    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(9)),
      child: Row(children: [seg('Kurz', false), seg('Ausführlich', true)]),
    );
  }
}

class Sparkline extends StatelessWidget {
  final List<List<double>> pts;
  final double? baseline;
  final Color color;
  final bool fill;
  final bool interactive;
  final String Function(double t, double v)? label;
  const Sparkline(this.pts,
      {super.key, this.baseline, required this.color, this.fill = false, this.interactive = false, this.label});

  @override
  Widget build(BuildContext context) {
    if (pts.length < 2) return const SizedBox();
    if (!interactive) return CustomPaint(painter: _SparkPainter(pts, baseline, color, fill, null, context));
    return _InteractiveSpark(this);
  }
}

class _InteractiveSpark extends StatefulWidget {
  final Sparkline w;
  const _InteractiveSpark(this.w);
  @override
  State<_InteractiveSpark> createState() => _InteractiveSparkState();
}

class _InteractiveSparkState extends State<_InteractiveSpark> {
  int? sel;
  @override
  Widget build(BuildContext context) {
    final w = widget.w;
    return LayoutBuilder(builder: (context, bc) {
      void pick(Offset o) =>
          setState(() => sel = (o.dx / bc.maxWidth * (w.pts.length - 1)).round().clamp(0, w.pts.length - 1));
      return GestureDetector(
        onHorizontalDragStart: (d) => pick(d.localPosition),
        onHorizontalDragUpdate: (d) => pick(d.localPosition),
        onHorizontalDragEnd: (_) => setState(() => sel = null),
        onTapDown: (d) => pick(d.localPosition),
        onTapUp: (_) => setState(() => sel = null),
        child: Stack(children: [
          Positioned.fill(child: CustomPaint(painter: _SparkPainter(w.pts, w.baseline, w.color, w.fill, sel, context))),
          if (sel != null && w.label != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.onSurface, borderRadius: BorderRadius.circular(6)),
                  child: Text(w.label!(w.pts[sel!][0], w.pts[sel!][1]),
                      style: sans(context, 12.5, w: FontWeight.w600, color: Theme.of(context).colorScheme.surface)),
                ),
              ),
            ),
        ]),
      );
    });
  }
}

class _SparkPainter extends CustomPainter {
  final List<List<double>> pts;
  final double? baseline;
  final Color color;
  final bool fill;
  final int? sel;
  final Color lineCol;
  _SparkPainter(this.pts, this.baseline, this.color, this.fill, this.sel, BuildContext c)
      : lineCol = Theme.of(c).colorScheme.outline;

  @override
  void paint(Canvas canvas, Size size) {
    var lo = pts.map((p) => p[1]).reduce(min), hi = pts.map((p) => p[1]).reduce(max);
    if (baseline != null) {
      lo = min(lo, baseline!);
      hi = max(hi, baseline!);
    }
    if (hi == lo) hi = lo + 1;
    final pad = (hi - lo) * 0.08;
    lo -= pad;
    hi += pad;
    final top = sel != null ? 30.0 : 0.0;
    final h = size.height - top;
    Offset at(int i) =>
        Offset(i / (pts.length - 1) * size.width, top + h - (pts[i][1] - lo) / (hi - lo) * h);
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    if (baseline != null) {
      final y = top + h - (baseline! - lo) / (hi - lo) * h;
      final dash = Paint()
        ..color = lineCol
        ..strokeWidth = 1;
      for (var x = 0.0; x < size.width; x += 6) {
        canvas.drawLine(Offset(x, y), Offset(min(x + 3, size.width), y), dash);
      }
    }
    if (fill) {
      final area = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
          area,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.0)],
            ).createShader(Offset.zero & size));
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = fill ? 2 : 1.6
          ..strokeJoin = StrokeJoin.round);
    if (sel != null) {
      final o = at(sel!);
      canvas.drawLine(Offset(o.dx, top), Offset(o.dx, size.height), Paint()..color = lineCol);
      canvas.drawCircle(o, 4.5, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.pts != pts || old.sel != sel || old.color != color;
}

class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionLabel(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 8),
        child: Row(children: [
          Expanded(child: Text(text.toUpperCase(), style: sans(context, 12, w: FontWeight.w700, ls: 1.1, color: muted(context)))),
          ?trailing,
        ]),
      );
}
