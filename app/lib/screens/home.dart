import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'article.dart';
import 'settings.dart';
import '../i18n.dart';

const monthsLong = [
  'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
];

void openStory(BuildContext context, List<Story> list, int index) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ArticlePager(stories: list, initial: index)));
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final scroll = ScrollController();
  String? cat;
  DateTime day = DateTime.now();

  void scrollToTop() {
    if (scroll.hasClients) scroll.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final timeline = app.sort == SortMode.timeline;
        final list = app.filtered(cat);
        if (app.pending.isNotEmpty && (!scroll.hasClients || scroll.offset < 120)) {
          WidgetsBinding.instance.addPostFrameCallback((_) => app.applyPending());
        }
        if (!timeline) app.prefetch(list);
        final newCount = app.pending.where((s) => cat == null || s.cat == cat).length;
        // SafeArea: Kopfzeile darf beim Scrollen nicht unter die Statusleiste rutschen
        return SafeArea(bottom: false, child: Stack(children: [
          RefreshIndicator(
            onRefresh: () async {
              await app.refresh(applyNow: true);
              if (timeline) await app.loadDays();
            },
            edgeOffset: 160,
            child: CustomScrollView(
              controller: scroll,
              slivers: [
                SliverAppBar(
                  primary: false,
                  floating: true,
                  snap: true,
                  toolbarHeight: 64,
                  titleSpacing: 16,
                  title: const _Masthead(),
                  actions: [
                    IconButton(
                      tooltip: 'Suchen',
                      icon: const Icon(Icons.search),
                      onPressed: () => showSearch(context: context, delegate: _Search()),
                    ),
                    IconButton(
                      tooltip: 'Einstellungen',
                      icon: const Icon(Icons.settings_outlined),
                      onPressed: () =>
                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _FilterHeader(
                    cat: cat,
                    sort: app.sort,
                    mood: app.mood,
                    loading: app.loading,
                    onCat: (c) {
                      HapticFeedback.selectionClick();
                      setState(() => cat = c);
                      scrollToTop();
                    },
                    onSort: (m) {
                      HapticFeedback.selectionClick();
                      app.setSort(m);
                      scrollToTop();
                    },
                  ),
                ),
                if (timeline)
                  ..._timeline(context)
                else if (list.isEmpty)
                  SliverFillRemaining(hasScrollBody: false, child: _Empty(cat: cat))
                else
                  SliverList.builder(
                    itemCount: list.length + 1,
                    itemBuilder: (context, i) {
                      if (i == list.length) return const _Footer();
                      final s = list[i];
                      if (i == 0) return HeroCard(s, onTap: () => openStory(context, list, 0));
                      return Column(children: [
                        const Divider(indent: 16, endIndent: 16),
                        StoryTile(s, onTap: () => openStory(context, list, i)),
                      ]);
                    },
                  ),
              ],
            ),
          ),
          if (newCount > 0 && !timeline)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Material(
                  color: Theme.of(context).colorScheme.primary,
                  elevation: 3,
                  shape: const StadiumBorder(),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () {
                      app.applyPending();
                      scrollToTop();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.arrow_upward, size: 16, color: Theme.of(context).colorScheme.onPrimary),
                        const SizedBox(width: 6),
                        Text(nNew(newCount),
                            style: sans(context, 13, w: FontWeight.w600, color: Theme.of(context).colorScheme.onPrimary)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
        ]));
      },
    );
  }

  // ---------------- Zeitstrahl
  List<Widget> _timeline(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dates = <DateTime>{
      today,
      for (final s in app.stories) DateTime(s.created.year, s.created.month, s.created.day),
      for (final (d, _) in app.days) DateTime.parse(d),
    }.toList()
      ..sort((a, b) => b.compareTo(a));
    final sel = DateTime(day.year, day.month, day.day);
    return [
      SliverToBoxAdapter(
        child: SizedBox(
          height: 74,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            itemCount: dates.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) => _DayChip(
              date: dates[i],
              selected: dates[i] == sel,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => day = dates[i]);
              },
            ),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(_longDate(sel), style: serif(context, 21, w: FontWeight.w700)),
        ),
      ),
      FutureBuilder<List<Story>>(
        key: ValueKey('${sel.toIso8601String()}-${app.generated}'),
        future: app.dayStories(sel),
        initialData: app.cachedDay(sel),
        builder: (context, snap) {
          if (snap.data == null) {
            return const SliverToBoxAdapter(
              child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
            );
          }
          final l = app.filtered(cat, from: snap.data);
          if (l.isEmpty) {
            return SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Text('Für diesen Tag gibt es keine passenden Meldungen.',
                    textAlign: TextAlign.center, style: sans(context, 14.5, color: muted(context))),
              ),
            );
          }
          return SliverList.builder(
            itemCount: l.length + 1,
            itemBuilder: (context, i) {
              if (i == l.length) return const SizedBox(height: 40);
              final s = l[i];
              final showHour = i == 0 || l[i - 1].created.hour != s.created.hour;
              return _TimelineRow(s, first: i == 0, last: i == l.length - 1, showHour: showHour,
                  onTap: () => openStory(context, l, i));
            },
          );
        },
      ),
    ];
  }
}

String _longDate(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(DateTime(d.year, d.month, d.day)).inDays;
  final base = longDate(d);
  return diff == 0 ? '${t('Heute')} · $base' : (diff == 1 ? '${t('Gestern')} · $base' : base);
}

class _DayChip extends StatelessWidget {
  final DateTime date;
  final bool selected;
  final VoidCallback onTap;
  const _DayChip({required this.date, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day).difference(date).inDays;
    final top = diff == 0 ? t('Heute') : (diff == 1 ? t('Gestern') : weekdaysShort[date.weekday - 1]);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 64,
        decoration: BoxDecoration(
          color: selected ? cs.onSurface : cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? cs.onSurface : cs.outlineVariant),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(top, style: sans(context, 11.5, w: FontWeight.w600, color: selected ? cs.surface : muted(context))),
          const SizedBox(height: 2),
          Text('${date.day}.${date.month}.',
              style: sans(context, 15, w: FontWeight.w700, color: selected ? cs.surface : cs.onSurface)),
        ]),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final Story s;
  final bool first, last, showHour;
  final VoidCallback onTap;
  const _TimelineRow(this.s, {required this.first, required this.last, required this.showHour, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = catColor(context, s.cat);
    final big = s.imp >= 8;
    return InkWell(
      onTap: onTap,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: 62,
            child: Padding(
              padding: const EdgeInsets.only(top: 14, left: 16),
              child: Text('${two(s.created.hour)}:${two(s.created.minute)}',
                  style: sans(context, 13, w: FontWeight.w700, color: showHour ? null : muted(context))),
            ),
          ),
          SizedBox(
            width: 26,
            child: Stack(alignment: Alignment.topCenter, children: [
              Positioned(
                top: first ? 18 : 0,
                bottom: last ? null : 0,
                height: last ? 18 : null,
                child: Container(width: 2, color: line(context)),
              ),
              Positioned(
                top: big ? 13 : 15,
                child: Container(
                  width: big ? 12 : 8,
                  height: big ? 12 : 8,
                  decoration: BoxDecoration(
                    color: big ? c : Theme.of(context).colorScheme.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: c, width: 2),
                  ),
                ),
              ),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 10, 16, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Kicker(s, showTime: false),
                const SizedBox(height: 4),
                Text(s.title, style: serif(context, big ? 18 : 16.5, w: FontWeight.w600, h: 1.25)),
                const SizedBox(height: 4),
                Text(s.teaser,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: sans(context, 13, color: muted(context), h: 1.4)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Masthead extends StatelessWidget {
  const _Masthead();
  @override
  Widget build(BuildContext context) {
    final d = DateTime.now();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Text('Überblick', style: serif(context, 26, w: FontWeight.w700, h: 1.0)),
        const SizedBox(width: 5),
        Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(top: 10),
            decoration: const BoxDecoration(color: breaking, shape: BoxShape.circle)),
      ]),
      const SizedBox(height: 3),
      Text(longDate(d),
          style: sans(context, 12, color: muted(context), w: FontWeight.w500)),
    ]);
  }
}

class _FilterHeader extends SliverPersistentHeaderDelegate {
  final String? cat;
  final SortMode sort;
  final Mood mood;
  final bool loading;
  final ValueChanged<String?> onCat;
  final ValueChanged<SortMode> onSort;
  _FilterHeader(
      {required this.cat,
      required this.sort,
      required this.mood,
      required this.loading,
      required this.onCat,
      required this.onSort});

  @override
  double get minExtent => 100;
  @override
  double get maxExtent => 100;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final cs = Theme.of(context).colorScheme;

    Widget tab(String? id, String label) {
      final sel = cat == id;
      final c = id == null ? cs.onSurface : catColor(context, id);
      return InkWell(
        onTap: () => onCat(id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
            Text(label,
                style: sans(context, 14.5,
                    w: sel ? FontWeight.w700 : FontWeight.w500, color: sel ? cs.onSurface : muted(context))),
            const SizedBox(height: 7),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 3,
              width: sel ? 28 : 0,
              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
            ),
          ]),
        ),
      );
    }

    Widget seg(SortMode m) {
      final sel = sort == m;
      return Expanded(
        flex: t(sortLabels[m]!).length + 4,
        child: Material(
          color: sel ? cs.surfaceContainerLowest : Colors.transparent,
          elevation: sel ? 1 : 0,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => onSort(m),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (m == SortMode.timeline) ...[
                      Icon(Icons.timeline, size: 14, color: sel ? cs.onSurface : muted(context)),
                      const SizedBox(width: 3),
                    ],
                    Text(t(sortLabels[m]!),
                        style: sans(context, 12.5,
                            w: sel ? FontWeight.w700 : FontWeight.w500, color: sel ? cs.onSurface : muted(context))),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      color: cs.surface,
      child: Column(children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            children: [tab(null, t('Alle')), for (final c in cats) tab(c.id, t(c.name))],
          ),
        ),
        const Divider(height: 1),
        const SizedBox(height: 9),
        Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Row(children: [
            Expanded(
              child: Container(
                height: 36,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(10)),
                child: Row(children: [for (final m in SortMode.values) seg(m)]),
              ),
            ),
            _MoodButton(mood),
          ]),
        ),
        const Spacer(),
        SizedBox(
          height: 2,
          child: loading ? const LinearProgressIndicator(minHeight: 2) : const Divider(height: 1),
        ),
      ]),
    );
  }

  @override
  bool shouldRebuild(covariant _FilterHeader old) =>
      old.cat != cat || old.sort != sort || old.mood != mood || old.loading != loading;
}

class _Empty extends StatelessWidget {
  final String? cat;
  const _Empty({this.cat});
  @override
  Widget build(BuildContext context) {
    final String msg;
    if (app.loading && app.stories.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    } else if (app.error != null && app.stories.isEmpty) {
      msg = app.error!;
    } else if (app.stories.isEmpty) {
      msg = t('Noch keine Meldungen verfügbar.');
    } else if (app.mood != Mood.all) {
      msg = uiEn
          ? 'No stories for “${t(moodLabels[app.mood]!)}”${cat == null ? '' : ' in “${t(catOf(cat!).name)}”'} right now.'
          : 'Gerade keine Meldungen für „${moodLabels[app.mood]}“${cat == null ? '' : ' in „${catOf(cat!).name}“'}.';
    } else {
      msg = uiEn ? 'No stories in “${t(catOf(cat!).name)}” right now.' : 'Gerade keine Meldungen in „${catOf(cat!).name}“.';
    }
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.inbox_outlined, size: 40, color: muted(context)),
        const SizedBox(height: 12),
        Text(msg, textAlign: TextAlign.center, style: sans(context, 15, color: muted(context))),
        const SizedBox(height: 12),
        if (app.mood != Mood.all)
          TextButton(onPressed: () => app.setMood(Mood.all), child: const Text('Alle Nachrichten zeigen'))
        else
          TextButton(onPressed: () => app.refresh(applyNow: true), child: const Text('Neu laden')),
      ]),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Text(
          '${app.generated != null && app.generated!.year > 2000 ? '${t('Stand')}: ${clock(app.generated!)}\n\n' : ''}'
          '${t('Alle Texte werden automatisch von einer KI aus mehreren unabhängigen Quellen zusammengestellt und laufend aktualisiert.')}',
          textAlign: TextAlign.center,
          style: sans(context, 12, color: muted(context), h: 1.5),
        ),
      );
}

const moodIcons = {
  Mood.all: Icons.filter_list,
  Mood.positive: Icons.sentiment_satisfied_alt,
  Mood.noNegative: Icons.wb_twilight,
  Mood.negative: Icons.sentiment_dissatisfied,
};

class _MoodButton extends StatelessWidget {
  final Mood mood;
  const _MoodButton(this.mood);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = mood != Mood.all;
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 12),
      child: Material(
        color: active ? cs.primary : cs.surfaceContainer,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => showMoodSheet(context),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(moodIcons[mood], size: 19, color: active ? cs.onPrimary : cs.onSurface),
          ),
        ),
      ),
    );
  }
}

void showMoodSheet(BuildContext context) {
  final desc = {
    Mood.all: t('Alle Meldungen anzeigen'),
    Mood.positive: t('Fortschritte, Erfolge, gute Entwicklungen'),
    Mood.noNegative: t('Belastende Meldungen ausblenden'),
    Mood.negative: t('Krisen, Konflikte und Probleme'),
  };
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Welche Nachrichten?', style: serif(context, 20, w: FontWeight.w700)),
          ),
          for (final m in Mood.values)
            ListTile(
              leading: Icon(moodIcons[m]),
              title: Text(t(moodLabels[m]!), style: sans(context, 15, w: FontWeight.w600)),
              subtitle: Text(desc[m]!, style: sans(context, 13, color: muted(context))),
              trailing: app.mood == m ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary) : null,
              onTap: () {
                HapticFeedback.selectionClick();
                app.setMood(m);
                Navigator.pop(context);
              },
            ),
          const SizedBox(height: 12),
        ]),
      ),
    ),
  );
}

class _Search extends SearchDelegate<void> {
  _Search() : super(searchFieldLabel: t('Meldungen durchsuchen'));

  @override
  ThemeData appBarTheme(BuildContext context) {
    final t = Theme.of(context);
    return t.copyWith(
      inputDecorationTheme: const InputDecorationTheme(border: InputBorder.none),
      appBarTheme: t.appBarTheme.copyWith(backgroundColor: t.colorScheme.surface),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) =>
      [if (query.isNotEmpty) IconButton(icon: const Icon(Icons.close), onPressed: () => query = '')];

  @override
  Widget? buildLeading(BuildContext context) =>
      IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));

  @override
  Widget buildResults(BuildContext context) => buildSuggestions(context);

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.trim().length < 2) {
      return Center(child: Text('Suchbegriff eingeben', style: sans(context, 14, color: muted(context))));
    }
    final l = app.filtered(null, query: query.trim());
    if (l.isEmpty) return Center(child: Text('Keine Treffer', style: sans(context, 14, color: muted(context))));
    return ListView.separated(
      itemCount: l.length,
      separatorBuilder: (_, _) => const Divider(indent: 16, endIndent: 16),
      itemBuilder: (context, i) => StoryTile(l[i], onTap: () => openStory(context, l, i)),
    );
  }
}
