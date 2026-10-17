import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chart.dart';
import '../data.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'home.dart';

String unitOf(Market m) => switch (m.kind) {
      'index' => ' Pkt.',
      'fx' => '',
      'bond' => ' %',
      _ => m.cur == 'USD' ? ' \$' : ' €',
    };

String fmtPrice(Market m) => '${fmtNum(m.price, digits: m.digits)}${unitOf(m)}';

Color chgColor(BuildContext c, double pct) {
  final dark = Theme.of(c).brightness == Brightness.dark;
  if (pct > 0) return dark ? const Color(0xFF5CC48A) : up;
  if (pct < 0) return dark ? const Color(0xFFF07A70) : down;
  return muted(c);
}

String fmtPct(double p) => '${p > 0 ? '+' : ''}${fmtNum(p)} %';

const _groups = [
  ('index', 'Indizes'),
  ('stock', 'Aktien'),
  ('fx', 'Devisen'),
  ('commodity', 'Rohstoffe'),
  ('crypto', 'Krypto'),
  ('bond', 'Anleihen'),
];

void openMarket(BuildContext context, Market m) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => MarketPage(m)));
}

class MarketsScreen extends StatefulWidget {
  const MarketsScreen({super.key});
  @override
  State<MarketsScreen> createState() => _MarketsScreenState();
}

class _MarketsScreenState extends State<MarketsScreen> {
  String group = 'index';
  bool byChange = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final ms = app.markets;
          final dax = ms.where((m) => m.sym == '^GDAXI').firstOrNull;
          final stocks = ms.where((m) => m.kind == 'stock').toList();
          var list = ms.where((m) => m.kind == group).toList();
          if (byChange) list.sort((a, b) => b.pct.compareTo(a.pct));
          final news = app.stories.where((s) => s.cat == 'boerse').toList()
            ..sort((a, b) => b.updated.compareTo(a.updated));
          return RefreshIndicator(
            onRefresh: () => app.refreshMarkets(),
            child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(child: Text('Börse', style: serif(context, 28, w: FontWeight.w700))),
                  if (app.marketsUpdated != null && app.marketsUpdated!.year > 2000)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('Stand ${clock(app.marketsUpdated!)}', style: sans(context, 12, color: muted(context))),
                    ),
                ]),
              ),
              if (ms.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: Center(child: Text('Kursdaten werden geladen …', style: sans(context, 14, color: muted(context)))),
                )
              else ...[
                if (dax != null) _DaxCard(dax),
                const SectionLabel('Weltweit'),
                _Overview([
                  for (final s in ['^STOXX50E', '^DJI', '^GSPC', '^NDX', '^N225', 'EURUSD=X', 'GC=F', 'BZ=F', 'BTC-EUR'])
                    ...ms.where((m) => m.sym == s)
                ]),
                if (stocks.length >= 6) ...[
                  const SectionLabel('Deutsche Aktien heute'),
                  _MoversCard(stocks),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final (id, label) in _groups)
                        if (ms.any((m) => m.kind == id))
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(label),
                              selected: group == id,
                              showCheckmark: false,
                              onSelected: (_) {
                                HapticFeedback.selectionClick();
                                setState(() => group = id);
                              },
                            ),
                          ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 8, 0),
                  child: Row(children: [
                    Text('${list.length} Werte', style: sans(context, 12.5, color: muted(context))),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => setState(() => byChange = !byChange),
                      icon: Icon(byChange ? Icons.trending_up : Icons.sort_by_alpha, size: 16),
                      label: Text(byChange ? 'nach Veränderung' : 'Standard'),
                    ),
                  ]),
                ),
                for (final (i, m) in list.indexed) ...[
                  if (i > 0) const Divider(indent: 16, endIndent: 16),
                  _MarketRow(m),
                ],
              ],
              if (news.isNotEmpty) ...[
                const SectionLabel('Börsen-Nachrichten'),
                for (final (i, s) in news.take(12).indexed) ...[
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

List<List<double>> _sparkPts(List<double> v) => [for (final (i, x) in v.indexed) [i.toDouble(), x]];

class _DaxCard extends StatelessWidget {
  final Market m;
  const _DaxCard(this.m);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final col = chgColor(context, m.pct);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Material(
        color: cs.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: cs.outlineVariant)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => openMarket(context, m),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('DAX', style: sans(context, 14, w: FontWeight.w700)),
                const SizedBox(width: 8),
                Text('Deutscher Leitindex', style: sans(context, 12.5, color: muted(context))),
                const Spacer(),
                Icon(Icons.chevron_right, color: muted(context)),
              ]),
              const SizedBox(height: 6),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(fmtNum(m.price), style: serif(context, 32, w: FontWeight.w700, h: 1.0)),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text('${fmtPct(m.pct)}  (${m.price - m.prev >= 0 ? '+' : ''}${fmtNum(m.price - m.prev)})',
                      style: sans(context, 14, w: FontWeight.w700, color: col)),
                ),
              ]),
              const SizedBox(height: 12),
              SizedBox(height: 70, child: Sparkline(_sparkPts(m.spark), baseline: m.prev, color: col, fill: true)),
              const SizedBox(height: 8),
              Row(children: [
                _mini(context, 'Hoch', m.high, m.digits),
                _mini(context, 'Tief', m.low, m.digits),
                _mini(context, 'Vortag', m.prev, m.digits),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _mini(BuildContext context, String k, double? v, int d) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: sans(context, 11.5, color: muted(context))),
          Text(v == null ? '–' : fmtNum(v, digits: d), style: sans(context, 13.5, w: FontWeight.w600)),
        ]),
      );
}

class _Overview extends StatelessWidget {
  final List<Market> ms;
  const _Overview(this.ms);
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 122,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: ms.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final m = ms[i];
          final cs = Theme.of(context).colorScheme;
          final col = chgColor(context, m.pct);
          return Material(
            color: cs.surfaceContainerLowest,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: cs.outlineVariant)),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => openMarket(context, m),
              child: SizedBox(
                width: 148,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(context, 12.5, w: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(fmtNum(m.price, digits: m.kind == 'index' ? 0 : m.digits),
                        style: serif(context, 18, w: FontWeight.w700)),
                    Text(fmtPct(m.pct), style: sans(context, 12, w: FontWeight.w700, color: col)),
                    const Spacer(),
                    SizedBox(height: 24, child: Sparkline(_sparkPts(m.spark), baseline: m.prev, color: col)),
                  ]),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MoversCard extends StatelessWidget {
  final List<Market> stocks;
  const _MoversCard(this.stocks);
  @override
  Widget build(BuildContext context) {
    final s = [...stocks]..sort((a, b) => b.pct.compareTo(a.pct));
    final top = s.take(3).toList(), flop = s.reversed.take(3).toList();
    final upN = stocks.where((m) => m.pct > 0).length;
    final cs = Theme.of(context).colorScheme;
    Widget col(String title, List<Market> l) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: sans(context, 12, w: FontWeight.w700, color: muted(context))),
            const SizedBox(height: 6),
            for (final m in l)
              InkWell(
                onTap: () => openMarket(context, m),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Expanded(
                        child: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: sans(context, 13.5, w: FontWeight.w500))),
                    Text(fmtPct(m.pct), style: sans(context, 13, w: FontWeight.w700, color: chgColor(context, m.pct))),
                  ]),
                ),
              ),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(children: [
          Row(children: [
            Expanded(
              flex: upN == 0 ? 1 : upN,
              child: Container(height: 6, decoration: BoxDecoration(color: chgColor(context, 1), borderRadius: const BorderRadius.horizontal(left: Radius.circular(3)))),
            ),
            const SizedBox(width: 2),
            Expanded(
              flex: stocks.length - upN == 0 ? 1 : stocks.length - upN,
              child: Container(height: 6, decoration: BoxDecoration(color: chgColor(context, -1), borderRadius: const BorderRadius.horizontal(right: Radius.circular(3)))),
            ),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Text('$upN im Plus', style: sans(context, 12, color: muted(context))),
            const Spacer(),
            Text('${stocks.length - upN} im Minus', style: sans(context, 12, color: muted(context))),
          ]),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            col('GEWINNER', top),
            const SizedBox(width: 20),
            col('VERLIERER', flop),
          ]),
        ]),
      ),
    );
  }
}

class _MarketRow extends StatelessWidget {
  final Market m;
  const _MarketRow(this.m);
  @override
  Widget build(BuildContext context) {
    final col = chgColor(context, m.pct);
    return InkWell(
      onTap: () => openMarket(context, m),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Expanded(
            flex: 5,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(context, 15, w: FontWeight.w600)),
              Text(fmtPrice(m), style: sans(context, 13, color: muted(context))),
            ]),
          ),
          Expanded(flex: 3, child: SizedBox(height: 30, child: Sparkline(_sparkPts(m.spark), baseline: m.prev, color: col))),
          const SizedBox(width: 12),
          Container(
            width: 80,
            padding: const EdgeInsets.symmetric(vertical: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: col.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
            child: Text(fmtPct(m.pct), style: sans(context, 13, w: FontWeight.w700, color: col)),
          ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ Detailseite

class MarketPage extends StatefulWidget {
  final Market m;
  const MarketPage(this.m, {super.key});
  @override
  State<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends State<MarketPage> {
  int range = 0;
  static const labels = ['1T', '1W', '1M', '6M', '1J'];
  late Future<MarketDetail?> fut = app.marketDetail(widget.m.sym);

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    final related = app.relatedStories(m);
    return Scaffold(
      appBar: AppBar(
        title: Text(m.name, style: serif(context, 20, w: FontWeight.w700)),
      ),
      body: FutureBuilder<MarketDetail?>(
        future: fut,
        initialData: app.cachedDetail(m.sym),
        builder: (context, snap) {
          final d = snap.data;
          List<List<double>> pts = [];
          TimeFmt fmt = TimeFmt.intraday;
          double? base;
          if (d != null) {
            switch (range) {
              case 0:
                pts = d.intraday;
                base = m.prev;
              case 1:
                pts = d.week;
                fmt = TimeFmt.week;
              default:
                final days = [0, 0, 31, 183, 366][range];
                final cut = DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch / 1000;
                pts = d.history.where((p) => p[0] >= cut).toList();
                fmt = TimeFmt.days;
            }
          }
          final first = range == 0 ? m.prev : (pts.isNotEmpty ? pts.first[1] : m.prev);
          final last = range == 0 ? m.price : (pts.isNotEmpty ? pts.last[1] : m.price);
          final pct = (last - first) / first * 100;
          final col = chgColor(context, pct);
          final markers = [for (final s in related) ChartMarker(s.created, s)];
          return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(fmtPrice(m), style: serif(context, 34, w: FontWeight.w700, h: 1.1)),
                const SizedBox(height: 4),
                Text(
                  '${last - first >= 0 ? '+' : ''}${fmtNum(last - first, digits: m.digits)}  (${fmtPct(pct)})  '
                  '${['heute', 'in 1 Woche', 'in 1 Monat', 'in 6 Monaten', 'in 1 Jahr'][range]}',
                  style: sans(context, 14.5, w: FontWeight.w700, color: col),
                ),
                if (m.time != null)
                  Text('Kurszeit: ${fmtTime(m.time!, TimeFmt.intraday, long: true)}',
                      style: sans(context, 12.5, color: muted(context))),
              ]),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: SizedBox(
                height: 280,
                child: d == null
                    ? (snap.connectionState == ConnectionState.done
                        ? Center(child: Text('Daten nicht verfügbar', style: sans(context, 13, color: muted(context))))
                        : const Center(child: CircularProgressIndicator(strokeWidth: 2)))
                    : PriceChart(
                        key: ValueKey(range),
                        pts: pts,
                        baseline: base,
                        color: col,
                        digits: m.digits,
                        fmt: fmt,
                        markers: markers,
                        onMarker: (s) => openStory(context, related, related.indexOf(s)),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Row(children: [
                for (var i = 0; i < labels.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: ChoiceChip(
                        label: SizedBox(width: double.infinity, child: Text(labels[i], textAlign: TextAlign.center)),
                        selected: range == i,
                        showCheckmark: false,
                        onSelected: (_) {
                          HapticFeedback.selectionClick();
                          setState(() => range = i);
                        },
                      ),
                    ),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Text(
                'Zum Ablesen genauer Werte über das Diagramm wischen.${markers.isNotEmpty ? ' „N“ markiert passende Nachrichten – antippen zum Lesen.' : ''}',
                style: sans(context, 12, color: muted(context)),
              ),
            ),
            const SectionLabel('Kennzahlen'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _StatsGrid([
                ('Eröffnung', m.open),
                ('Vortag', m.prev),
                ('Tageshoch', m.high),
                ('Tagestief', m.low),
                ('52 Wochen Hoch', m.yhigh),
                ('52 Wochen Tief', m.ylow),
              ], m.digits),
            ),
            SectionLabel(related.isEmpty ? 'Nachrichten' : 'Nachrichten zu ${m.name}'),
            if (related.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('Aktuell keine Meldungen, die sich direkt auf ${m.name} beziehen.',
                    style: sans(context, 14, color: muted(context))),
              ),
            for (final (i, s) in related.take(15).indexed) ...[
              if (i > 0) const Divider(indent: 16, endIndent: 16),
              StoryTile(s, onTap: () => openStory(context, related, i)),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: Text('Kurse verzögert, ohne Gewähr. Keine Anlageberatung.',
                  style: sans(context, 11.5, color: muted(context))),
            ),
          ]);
        },
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final List<(String, double?)> items;
  final int digits;
  const _StatsGrid(this.items, this.digits);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(children: [
        for (var r = 0; r < items.length; r += 2)
          Container(
            decoration: BoxDecoration(border: r == 0 ? null : Border(top: BorderSide(color: cs.outlineVariant))),
            child: Row(children: [
              for (final (k, v) in items.sublist(r, r + 2))
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(k, style: sans(context, 12, color: muted(context))),
                      const SizedBox(height: 2),
                      Text(v == null ? '–' : fmtNum(v, digits: digits), style: sans(context, 15, w: FontWeight.w600)),
                    ]),
                  ),
                ),
            ]),
          ),
      ]),
    );
  }
}
