import 'package:flutter/material.dart';

import '../data.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'home.dart';

String fmtPrice(Market m) {
  final d = m.kind == 'fx' ? 4 : 2;
  final unit = switch (m.kind) { 'index' => ' Pkt.', 'fx' => ' \$', _ => m.cur == 'USD' ? ' \$' : ' €' };
  return '${fmtNum(m.price, digits: d)}$unit';
}

Color chgColor(double pct) => pct > 0 ? up : (pct < 0 ? down : Colors.grey);

String fmtPct(double p) => '${p > 0 ? '+' : ''}${fmtNum(p)} %';

class MarketsScreen extends StatelessWidget {
  const MarketsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final news = app.stories.where((s) => s.cat == 'boerse').toList()
            ..sort((a, b) => b.updated.compareTo(a.updated));
          return RefreshIndicator(
            onRefresh: () => app.refresh(applyNow: true),
            child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(child: Text('Börse', style: serif(context, 26, w: FontWeight.w700))),
                  if (app.marketsUpdated != null && app.marketsUpdated!.year > 2000)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('Stand ${clock(app.marketsUpdated!)}', style: sans(context, 12, color: muted(context))),
                    ),
                ]),
              ),
              const SizedBox(height: 10),
              if (app.markets.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: Center(child: Text('Kursdaten werden geladen …', style: sans(context, 14, color: muted(context)))),
                )
              else ...[
                _Overview(app.markets.take(4).toList()),
                const SectionLabel('Märkte'),
                for (final (i, m) in app.markets.indexed) ...[
                  if (i > 0) const Divider(indent: 16, endIndent: 16),
                  _MarketRow(m),
                ],
              ],
              if (news.isNotEmpty) ...[
                const SectionLabel('Börsen-Nachrichten'),
                for (final (i, s) in news.take(15).indexed) ...[
                  if (i > 0) const Divider(indent: 16, endIndent: 16),
                  StoryTile(s, onTap: () => openStory(context, news, i)),
                ],
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: Text('Kurse verzögert, ohne Gewähr. Keine Anlageberatung.',
                    style: sans(context, 11.5, color: muted(context))),
              ),
            ]),
          );
        },
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  final List<Market> ms;
  const _Overview(this.ms);
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 128,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: ms.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final m = ms[i];
          final cs = Theme.of(context).colorScheme;
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _openDetail(context, m),
            child: Container(
              width: 156,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.name, style: sans(context, 13, w: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(fmtNum(m.price, digits: m.kind == 'fx' ? 4 : 0), style: serif(context, 19, w: FontWeight.w700)),
                Text(fmtPct(m.pct), style: sans(context, 12.5, w: FontWeight.w600, color: chgColor(m.pct))),
                const Spacer(),
                SizedBox(height: 28, child: Sparkline(m.intraday, baseline: m.prev, color: chgColor(m.pct))),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class _MarketRow extends StatelessWidget {
  final Market m;
  const _MarketRow(this.m);
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _openDetail(context, m),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Expanded(
            flex: 5,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.name, style: sans(context, 15, w: FontWeight.w600)),
              Text(fmtPrice(m), style: sans(context, 13, color: muted(context))),
            ]),
          ),
          Expanded(
            flex: 4,
            child: SizedBox(height: 30, child: Sparkline(m.intraday, baseline: m.prev, color: chgColor(m.pct))),
          ),
          const SizedBox(width: 12),
          Container(
            width: 78,
            padding: const EdgeInsets.symmetric(vertical: 5),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: chgColor(m.pct).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(fmtPct(m.pct), style: sans(context, 13, w: FontWeight.w700, color: chgColor(m.pct))),
          ),
        ]),
      ),
    );
  }
}

void _openDetail(BuildContext context, Market m) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _MarketDetail(m),
  );
}

class _MarketDetail extends StatefulWidget {
  final Market m;
  const _MarketDetail(this.m);
  @override
  State<_MarketDetail> createState() => _MarketDetailState();
}

class _MarketDetailState extends State<_MarketDetail> {
  int range = 0; // 0=1T, 1=1M, 2=6M, 3=1J
  static const labels = ['1T', '1M', '6M', '1J'];

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    List<List<double>> pts;
    double? base;
    if (range == 0) {
      pts = m.intraday;
      base = m.prev;
    } else {
      final days = [0, 31, 183, 366][range];
      final cutoff = DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch / 1000;
      pts = m.history.where((p) => p[0] >= cutoff).toList();
    }
    final first = pts.isNotEmpty ? (base ?? pts.first[1]) : m.prev;
    final pct = pts.isEmpty ? 0.0 : (pts.last[1] - first) / first * 100;
    final col = chgColor(pct);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(context).padding.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(m.name, style: sans(context, 15, w: FontWeight.w600, color: muted(context))),
        const SizedBox(height: 2),
        Text(fmtPrice(m), style: serif(context, 32, w: FontWeight.w700)),
        Text('${fmtPct(pct)} ${['heute', 'seit 1 Monat', 'seit 6 Monaten', 'seit 1 Jahr'][range]}',
            style: sans(context, 14, w: FontWeight.w600, color: col)),
        const SizedBox(height: 16),
        SizedBox(
          height: 220,
          child: pts.length < 2
              ? Center(child: Text('Keine Daten', style: sans(context, 13, color: muted(context))))
              : Sparkline(pts,
                  baseline: base,
                  color: col,
                  fill: true,
                  interactive: true,
                  label: (t, v) {
                    final d = DateTime.fromMillisecondsSinceEpoch((t * 1000).toInt());
                    final when = range == 0 ? '${two(d.hour)}:${two(d.minute)}' : '${two(d.day)}.${two(d.month)}.${d.year}';
                    return '$when  ·  ${fmtNum(v, digits: m.kind == 'fx' ? 4 : 2)}';
                  }),
        ),
        const SizedBox(height: 16),
        Row(children: [
          for (var i = 0; i < 4; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: ChoiceChip(
                  label: SizedBox(width: double.infinity, child: Text(labels[i], textAlign: TextAlign.center)),
                  selected: range == i,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => range = i),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 14),
        Text('Vortag: ${fmtNum(m.prev, digits: m.kind == 'fx' ? 4 : 2)}'
            '${m.time != null ? '  ·  Kurszeit: ${clock(m.time!)}' : ''}',
            style: sans(context, 12.5, color: muted(context))),
      ]),
    );
  }
}
