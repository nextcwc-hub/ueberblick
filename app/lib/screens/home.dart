import 'package:flutter/material.dart';

import '../data.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'article.dart';
import 'settings.dart';

const _weekdays = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];
const _months = [
  'Januar',
  'Februar',
  'März',
  'April',
  'Mai',
  'Juni',
  'Juli',
  'August',
  'September',
  'Oktober',
  'November',
  'Dezember',
];

void openStory(BuildContext context, List<Story> list, int index) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ArticlePager(stories: list, initial: index),
    ),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final scroll = ScrollController();
  String? cat;

  void scrollToTop() {
    if (scroll.hasClients) scroll.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final list = app.filtered(cat);
        if (app.pending.isNotEmpty && (!scroll.hasClients || scroll.offset < 120)) {
          WidgetsBinding.instance.addPostFrameCallback((_) => app.applyPending());
        }
        app.prefetch(list);
        final newCount = app.pending.where((s) => cat == null || s.cat == cat).length;
        return Stack(
          children: [
            RefreshIndicator(
              onRefresh: () => app.refresh(applyNow: true),
              edgeOffset: 150,
              child: CustomScrollView(
                controller: scroll,
                slivers: [
                  SliverAppBar(
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
                        icon: const Icon(Icons.tune),
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
                      onCat: (c) {
                        setState(() => cat = c);
                        scrollToTop();
                      },
                      onSort: (m) {
                        app.setSort(m);
                        scrollToTop();
                      },
                    ),
                  ),
                  if (list.isEmpty)
                    SliverFillRemaining(hasScrollBody: false, child: _Empty(cat: cat))
                  else
                    SliverList.builder(
                      itemCount: list.length + 1,
                      itemBuilder: (context, i) {
                        if (i == list.length) return _Footer();
                        final s = list[i];
                        if (i == 0) return HeroCard(s, onTap: () => openStory(context, list, 0));
                        return Column(
                          children: [
                            const Divider(indent: 16, endIndent: 16),
                            StoryTile(s, onTap: () => openStory(context, list, i)),
                          ],
                        );
                      },
                    ),
                ],
              ),
            ),
            if (newCount > 0)
              Positioned(
                top: MediaQuery.of(context).padding.top + 118,
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
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_upward, size: 16, color: Theme.of(context).colorScheme.onPrimary),
                            const SizedBox(width: 6),
                            Text(
                              newCount == 1 ? '1 neue Meldung' : '$newCount neue Meldungen',
                              style: sans(
                                context,
                                13,
                                w: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Masthead extends StatelessWidget {
  const _Masthead();
  @override
  Widget build(BuildContext context) {
    final d = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text('Überblick', style: serif(context, 26, w: FontWeight.w700, h: 1.0)),
            const SizedBox(width: 6),
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(top: 10),
              decoration: const BoxDecoration(color: breaking, shape: BoxShape.circle),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          '${_weekdays[d.weekday - 1]}, ${d.day}. ${_months[d.month - 1]}',
          style: sans(context, 12, color: muted(context), w: FontWeight.w500),
        ),
      ],
    );
  }
}

class _FilterHeader extends SliverPersistentHeaderDelegate {
  final String? cat;
  final SortMode sort;
  final ValueChanged<String?> onCat;
  final ValueChanged<SortMode> onSort;
  _FilterHeader({required this.cat, required this.sort, required this.onCat, required this.onSort});

  @override
  double get minExtent => 94;
  @override
  double get maxExtent => 94;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final cs = Theme.of(context).colorScheme;
    Widget chip(String? id, String label, Color color) {
      final sel = cat == id;
      final dark = Theme.of(context).brightness == Brightness.dark;
      final c = dark && id != null ? Color.lerp(color, Colors.white, 0.25)! : color;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => onCat(id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: sel ? c : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: sel ? c : cs.outline),
            ),
            child: Text(
              label,
              style: sans(
                context,
                13.5,
                w: sel ? FontWeight.w600 : FontWeight.w500,
                color: sel ? (dark && id == null ? cs.onPrimary : Colors.white) : cs.onSurface,
              ),
            ),
          ),
        ),
      );
    }

    Widget sortBtn(SortMode m, String label) {
      final sel = sort == m;
      return InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => onSort(m),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(
            label,
            style: sans(
              context,
              13,
              w: sel ? FontWeight.w700 : FontWeight.w500,
              color: sel ? cs.onSurface : muted(context),
            ),
          ),
        ),
      );
    }

    return Container(
      color: cs.surface,
      child: Column(
        children: [
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [chip(null, 'Alle', cs.primary), for (final c in cats) chip(c.id, c.name, c.color)],
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      sortBtn(SortMode.newest, 'Neueste'),
                      sortBtn(SortMode.relevance, 'Relevanz'),
                      sortBtn(SortMode.sources, 'Meistberichtet'),
                    ]),
                  ),
                ),
                if (app.loading)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.8)),
                  ),
                _MoodButton(),
              ],
            ),
          ),
          const Spacer(),
          const Divider(height: 1),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _FilterHeader old) => true;
}

class _Empty extends StatelessWidget {
  final String? cat;
  const _Empty({this.cat});
  @override
  Widget build(BuildContext context) {
    final String msg;
    if (app.loading && app.stories.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    } else if (app.error != null) {
      msg = app.error!;
    } else if (app.stories.isEmpty) {
      msg = 'Noch keine Meldungen verfügbar.';
    } else if (app.mood != Mood.all) {
      msg =
          'Gerade keine passenden Meldungen für „${moodLabels[app.mood]}“${cat == null ? '' : ' in „${catOf(cat!).name}“'}.';
    } else {
      msg = 'Gerade keine Meldungen in „${catOf(cat!).name}“.';
    }
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 40, color: muted(context)),
          const SizedBox(height: 12),
          Text(
            msg,
            textAlign: TextAlign.center,
            style: sans(context, 15, color: muted(context)),
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: () => app.refresh(applyNow: true), child: const Text('Neu laden')),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
    child: Text(
      '${app.generated != null && app.generated!.year > 2000 ? 'Stand: ${clock(app.generated!)}\n\n' : ''}'
      'Alle Texte werden automatisch von einer KI aus mehreren unabhängigen Quellen zusammengestellt und laufend aktualisiert.',
      textAlign: TextAlign.center,
      style: sans(context, 12, color: muted(context), h: 1.5),
    ),
  );
}

class _MoodButton extends StatelessWidget {
  static const icons = {
    Mood.all: Icons.tune,
    Mood.positive: Icons.sentiment_satisfied_alt,
    Mood.noNegative: Icons.wb_twilight,
    Mood.negative: Icons.sentiment_dissatisfied,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = app.mood != Mood.all;
    final label = switch (app.mood) {
      Mood.all => 'Stimmung',
      Mood.positive => 'Positiv',
      Mood.noNegative => 'Ohne negative',
      Mood.negative => 'Negativ',
    };
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showMoodSheet(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active ? cs.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: active ? cs.primary : cs.outline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icons[app.mood], size: 15, color: active ? cs.onPrimary : muted(context)),
              const SizedBox(width: 5),
              Text(
                label,
                style: sans(context, 12.5, w: FontWeight.w600, color: active ? cs.onPrimary : cs.onSurface),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void showMoodSheet(BuildContext context) {
  const desc = {
    Mood.all: 'Alle Meldungen anzeigen',
    Mood.positive: 'Fortschritte, Erfolge, gute Entwicklungen',
    Mood.noNegative: 'Belastende Meldungen ausblenden',
    Mood.negative: 'Krisen, Konflikte und Probleme',
  };
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Welche Nachrichten?', style: serif(context, 20, w: FontWeight.w700)),
            ),
            for (final m in Mood.values)
              ListTile(
                leading: Icon(_MoodButton.icons[m]),
                title: Text(moodLabels[m]!, style: sans(context, 15, w: FontWeight.w600)),
                subtitle: Text(desc[m]!, style: sans(context, 13, color: muted(context))),
                trailing: app.mood == m ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary) : null,
                onTap: () {
                  app.setMood(m);
                  Navigator.pop(context);
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ),
  );
}

class _Search extends SearchDelegate<void> {
  _Search() : super(searchFieldLabel: 'Meldungen durchsuchen');

  @override
  ThemeData appBarTheme(BuildContext context) {
    final t = Theme.of(context);
    return t.copyWith(
      inputDecorationTheme: const InputDecorationTheme(border: InputBorder.none),
      appBarTheme: t.appBarTheme.copyWith(backgroundColor: t.colorScheme.surface),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) => [
    if (query.isNotEmpty) IconButton(icon: const Icon(Icons.close), onPressed: () => query = ''),
  ];

  @override
  Widget? buildLeading(BuildContext context) =>
      IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));

  @override
  Widget buildResults(BuildContext context) => buildSuggestions(context);

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.trim().length < 2) {
      return Center(
        child: Text('Suchbegriff eingeben', style: sans(context, 14, color: muted(context))),
      );
    }
    final l = app.filtered(null, query: query.trim());
    if (l.isEmpty)
      return Center(
        child: Text('Keine Treffer', style: sans(context, 14, color: muted(context))),
      );
    return ListView.separated(
      itemCount: l.length,
      separatorBuilder: (_, _) => const Divider(indent: 16, endIndent: 16),
      itemBuilder: (context, i) => StoryTile(l[i], onTap: () => openStory(context, l, i)),
    );
  }
}
