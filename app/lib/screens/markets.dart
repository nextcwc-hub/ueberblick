import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chart.dart';
import '../data.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'home.dart';
import '../i18n.dart';

String fmtPrice(Market m) => '${fmtNum(m.price, digits: m.digits)}${m.unit}';

Color chgColor(BuildContext c, double pct, {bool neutral = false}) {
  final dark = Theme.of(c).brightness == Brightness.dark;
  if (neutral || pct == 0) return muted(c);
  if (pct > 0) return dark ? const Color(0xFF5CC48A) : up;
  return dark ? const Color(0xFFF07A70) : down;
}

/// Zinsen und Inflation sind weder „gut“ noch „schlecht“ – dort neutral färben.
Color mColor(BuildContext c, Market m, [double? v]) => chgColor(c, v ?? m.pct, neutral: m.pp);

String fmtChg(Market m, [double? v]) {
  final x = v ?? m.pct;
  return '${x > 0 ? '+' : ''}${fmtNum(x)}${m.pp ? (uiEn ? ' pp' : ' Pp.') : ' %'}';
}

String sinceLabel(Market m) => t(m.kind == 'crypto' ? '24 Std.' : (m.monthly ? 'zum Vormonat' : 'zum Vortag'));

const _groups = [('fx', 'Devisen'), ('rate', 'Zinsen'), ('inflation', 'Inflation'), ('crypto', 'Krypto')];

void openMarket(BuildContext context, Market m) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => MarketPage(m)));
}

class MarketsScreen extends StatefulWidget {
  const MarketsScreen({super.key});
  @override
  State<MarketsScreen> createState() => _MarketsScreenState();
}

class _MarketsScreenState extends State<MarketsScreen> {
  String group = 'fx';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final ms = app.markets;
          Market? by(String s) => ms.where((m) => m.sym == s).firstOrNull;
          final key = [by('USD'), by('DFR'), by('HICP_DE'), by('BTC')].whereType<Market>().toList();
          final list = ms.where((m) => m.kind == group).toList();
          final news = app.stories.where((s) => s.cat == 'boerse' || s.cat == 'wirtschaft').toList()
            ..sort((a, b) => b.time.compareTo(a.time));
          return RefreshIndicator(
            onRefresh: () => app.refreshMarkets(),
            child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Text(t('Börse & Märkte'), style: serif(context, 28, w: FontWeight.w700)),
              ),
              if (ms.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: Center(child: Text('Daten werden geladen …', style: sans(context, 14, color: muted(context)))),
                )
              else ...[
                SectionLabel(t('Auf einen Blick')),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.25,
                    children: [for (final m in key) _KeyCard(m)],
                  ),
                ),
              ],
              if (news.isNotEmpty) ...[
                SectionLabel(t('Börsen- & Wirtschaftsnachrichten')),
                for (final (i, s) in news.take(6).indexed) ...[
                  if (i > 0) const Divider(indent: 16, endIndent: 16),
                  StoryTile(s, onTap: () => openStory(context, news, i)),
                ],
              ],
              if (ms.isNotEmpty) ...[
                SectionLabel(t('Alle Werte')),
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
                              label: Text(t(label)),
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
                const SizedBox(height: 6),
                for (final (i, m) in list.indexed) ...[
                  if (i > 0) const Divider(indent: 16, endIndent: 16),
                  _MarketRow(m),
                ],
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                child: Text(
                  '${t('Devisen und Zinsen: Europäische Zentralbank (Referenzkurse, werktäglich ca. 16 Uhr). ')}'
                  '${t('Inflation: Eurostat. Ohne Gewähr, keine Anlageberatung.')}',
                  style: sans(context, 11.5, color: muted(context), h: 1.5),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Text('Krypto-Kurse: Powered by CoinGecko',
                    style: sans(context, 12, w: FontWeight.w600, color: muted(context))),
              ),
            ]),
          );
        },
      ),
    );
  }
}

List<List<double>> _sparkPts(List<double> v) => [for (final (i, x) in v.indexed) [i.toDouble(), x]];

class _KeyCard extends StatelessWidget {
  final Market m;
  const _KeyCard(this.m);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final col = mColor(context, m);
    return Material(
      color: cs.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: cs.outlineVariant)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => openMarket(context, m),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t(m.name), maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(context, 12.5, w: FontWeight.w600)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(fmtPrice(m), style: serif(context, 21, w: FontWeight.w700)),
            ),
            Text('${fmtChg(m)} ${sinceLabel(m)}', style: sans(context, 11.5, w: FontWeight.w600, color: col)),
            const Spacer(),
            SizedBox(height: 26, child: Sparkline(_sparkPts(m.spark), color: m.pp ? cs.primary : col)),
          ]),
        ),
      ),
    );
  }
}

class _MarketRow extends StatelessWidget {
  final Market m;
  const _MarketRow(this.m);
  @override
  Widget build(BuildContext context) {
    final col = mColor(context, m);
    return InkWell(
      onTap: () => openMarket(context, m),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Expanded(
            flex: 5,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t(m.name), maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(context, 15, w: FontWeight.w600)),
              Text(fmtPrice(m), style: sans(context, 13, color: muted(context))),
            ]),
          ),
          Expanded(
            flex: 3,
            child: SizedBox(
                height: 30,
                child: Sparkline(_sparkPts(m.spark), color: m.pp ? Theme.of(context).colorScheme.primary : col)),
          ),
          const SizedBox(width: 12),
          Container(
            width: 84,
            padding: const EdgeInsets.symmetric(vertical: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: col.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
            child: Text(fmtChg(m), style: sans(context, 12.5, w: FontWeight.w700, color: col)),
          ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ Detailseite

class _Range {
  final String label, since;
  final int days; // 0 = letzte 24 Std., -1 = Woche aus Stundenwerten
  const _Range(this.label, this.since, this.days);
}

class MarketPage extends StatefulWidget {
  final Market m;
  const MarketPage(this.m, {super.key});
  @override
  State<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends State<MarketPage> {
  int range = 0;
  late Future<MarketDetail?> fut = app.marketDetail(widget.m.sym);

  List<_Range> _ranges(MarketDetail? d) {
    final m = widget.m;
    if (m.monthly) {
      return [_Range('1J', t('in 1 Jahr'), 366), _Range('5J', t('in 5 Jahren'), 1830), _Range('10J', t('in 10 Jahren'), 3660)];
    }
    return [
      if (d != null && d.intraday.length > 2) _Range(t('24 Std.'), t('in 24 Std.'), 0),
      if (d != null && d.week.length > 2) _Range('1W', t('in 1 Woche'), -1),
      _Range('1M', t('in 1 Monat'), 31),
      _Range('6M', t('in 6 Monaten'), 183),
      _Range('1J', t('in 1 Jahr'), 366),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    final related = app.relatedStories(m);
    return Scaffold(
      appBar: AppBar(title: Text(t(m.name), style: serif(context, 20, w: FontWeight.w700))),
      body: FutureBuilder<MarketDetail?>(
        future: fut,
        initialData: app.cachedDetail(m.sym),
        builder: (context, snap) {
          final d = snap.data;
          final ranges = _ranges(d);
          final r = ranges[range.clamp(0, ranges.length - 1)];
          List<List<double>> pts = [];
          TimeFmt fmt = m.monthly ? TimeFmt.months : TimeFmt.days;
          if (d != null) {
            if (r.days == 0) {
              pts = d.intraday;
              fmt = TimeFmt.intraday;
            } else if (r.days == -1) {
              pts = d.week;
              fmt = TimeFmt.week;
            } else {
              final cut = DateTime.now().subtract(Duration(days: r.days)).millisecondsSinceEpoch / 1000;
              pts = d.history.where((p) => p[0] >= cut).toList();
            }
          }
          final first = pts.isNotEmpty ? pts.first[1] : m.prev;
          final last = pts.isNotEmpty ? pts.last[1] : m.price;
          final chg = m.pp ? last - first : (first == 0 ? 0.0 : (last - first) / first * 100);
          final col = mColor(context, m, chg);
          final markers = [for (final s in related) ChartMarker(s.created, s)];
          return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(fmtPrice(m), style: serif(context, 34, w: FontWeight.w700, h: 1.1)),
                const SizedBox(height: 4),
                Text('${fmtChg(m, chg)} ${r.since}', style: sans(context, 14.5, w: FontWeight.w700, color: col)),
                if (m.time != null)
                  Text(
                    'Stand: ${fmtTime(m.time!, m.kind == 'crypto' ? TimeFmt.intraday : (m.monthly ? TimeFmt.months : TimeFmt.days), long: true)}',
                    style: sans(context, 12.5, color: muted(context)),
                  ),
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
                        key: ValueKey(r.label),
                        pts: pts,
                        color: m.pp ? Theme.of(context).colorScheme.primary : col,
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
                for (var i = 0; i < ranges.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: ChoiceChip(
                        label: SizedBox(
                            width: double.infinity,
                            child: FittedBox(fit: BoxFit.scaleDown, child: Text(ranges[i].label))),
                        selected: ranges[i] == r,
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
            SectionLabel(t('Kennzahlen')),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _StatsGrid([
                (t(m.monthly ? 'Vormonat' : (m.kind == 'crypto' ? 'vor 24 Std.' : 'Vortag')), m.prev),
                (t('Aktuell'), m.price),
                if (m.high != null) (t('24-Std.-Hoch'), m.high),
                if (m.low != null) (t('24-Std.-Tief'), m.low),
                (t('12-Monats-Hoch'), m.yhigh),
                (t('12-Monats-Tief'), m.ylow),
              ], m),
            ),
            SectionLabel(related.isEmpty ? t('Nachrichten') : '${t('Nachrichten zu')} ${t(m.name)}'),
            if (related.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('Aktuell keine Meldungen, die sich direkt darauf beziehen.',
                    style: sans(context, 14, color: muted(context))),
              ),
            for (final (i, s) in related.take(15).indexed) ...[
              if (i > 0) const Divider(indent: 16, endIndent: 16),
              StoryTile(s, onTap: () => openStory(context, related, i)),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: Text(
                m.kind == 'crypto'
                    ? 'Powered by CoinGecko. Ohne Gewähr, keine Anlageberatung.'
                    : (m.kind == 'inflation'
                        ? 'Quelle: Eurostat (HICP, Veränderung zum Vorjahresmonat).'
                        : t('Quelle: Europäische Zentralbank. Ohne Gewähr.')),
                style: sans(context, 12, w: FontWeight.w600, color: muted(context)),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final List<(String, double?)> items;
  final Market m;
  const _StatsGrid(this.items, this.m);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = items.where((e) => e.$2 != null).toList();
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(children: [
        for (var r = 0; r < l.length; r += 2)
          Container(
            decoration: BoxDecoration(border: r == 0 ? null : Border(top: BorderSide(color: cs.outlineVariant))),
            child: Row(children: [
              for (final (k, v) in l.sublist(r, r + 2 > l.length ? l.length : r + 2))
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(k, style: sans(context, 12, color: muted(context))),
                      const SizedBox(height: 2),
                      Text('${fmtNum(v!, digits: m.digits)}${m.unit}', style: sans(context, 15, w: FontWeight.w600)),
                    ]),
                  ),
                ),
              if (r + 1 >= l.length) const Expanded(child: SizedBox()),
            ]),
          ),
      ]),
    );
  }
}
