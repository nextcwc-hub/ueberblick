import 'dart:math';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data.dart';
import '../legal.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

class ArticlePager extends StatefulWidget {
  final List<Story> stories;
  final int initial;
  const ArticlePager({super.key, required this.stories, required this.initial});
  @override
  State<ArticlePager> createState() => _ArticlePagerState();
}

class _ArticlePagerState extends State<ArticlePager> {
  late final PageController pc = PageController(initialPage: widget.initial);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView.builder(
        controller: pc,
        itemCount: widget.stories.length,
        onPageChanged: (i) => app.prefetch(widget.stories.skip(i)),
        itemBuilder: (context, i) => ArticleView(widget.stories[i]),
      ),
    );
  }
}

class ArticleView extends StatelessWidget {
  final Story s;
  const ArticleView(this.s, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final w = MediaQuery.of(context).size.width;
    final imgH = s.img != null ? min(w / max(s.img!.ratio, 1.3), 320.0) : 0.0;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: s.img != null ? imgH : null,
          leading: _RoundBtn(icon: Icons.arrow_back, onTap: () => Navigator.pop(context), overImage: s.img != null),
          actions: [
            _RoundBtn(
              icon: app.isSaved(s.id) ? Icons.bookmark : Icons.bookmark_border,
              overImage: s.img != null,
              onTap: () => app.toggleSaved(s),
            ),
            _RoundBtn(icon: Icons.ios_share, overImage: s.img != null, onTap: () => _share(s)),
            const SizedBox(width: 6),
          ],
          flexibleSpace: s.img == null
              ? null
              : FlexibleSpaceBar(
                  collapseMode: CollapseMode.parallax,
                  background: StoryImage(s, radius: 0, large: true),
                ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (s.img != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: s.img!.src.isEmpty ? null : () => _open(s.img!.src),
                    child: Text('Foto: ${s.img!.credit}, ${s.img!.license}',
                        textAlign: TextAlign.right, style: sans(context, 10.5, color: muted(context))),
                  ),
                ),
              const SizedBox(height: 14),
              Kicker(s, showTime: false),
              const SizedBox(height: 8),
              Text(s.title, style: serif(context, 28, w: FontWeight.w700, h: 1.15)),
              const SizedBox(height: 12),
              Text(s.teaser, style: sans(context, 16.5, w: FontWeight.w500, h: 1.45)),
              const SizedBox(height: 14),
              Text(
                'Stand: ${clock(s.updated)}${s.ver > 1 ? ' · ${s.ver}. Fassung' : ''} · ${s.srcn == 1 ? '1 Quelle' : '${s.srcn} Quellen'}',
                style: sans(context, 12.5, color: muted(context)),
              ),
            ]),
          ),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _SwitchHeader(cs.surface),
        ),
        SliverToBoxAdapter(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOut,
            transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
            layoutBuilder: (cur, prev) => Stack(alignment: Alignment.topCenter, children: [...prev, ?cur]),
            child: app.detailed ? _Detailed(s, key: const ValueKey('d')) : _Short(s, key: const ValueKey('k')),
          ),
        ),
        SliverToBoxAdapter(child: _Sources(s)),
      ]),
    );
  }
}

void _share(Story s) {
  final text = '${s.title}\n\n${s.summary.map((x) => '• $x').join('\n')}\n\n– via Überblick';
  SharePlus.instance.share(ShareParams(text: text, subject: s.title));
}

Future<void> _open(String url) async {
  final u = Uri.tryParse(url);
  if (u != null) await launchUrl(u, mode: LaunchMode.externalApplication);
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool overImage;
  const _RoundBtn({required this.icon, required this.onTap, required this.overImage});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Material(
        color: overImage ? Colors.black.withValues(alpha: 0.35) : Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(icon, size: 21, color: overImage ? Colors.white : Theme.of(context).colorScheme.onSurface)),
        ),
      ),
    );
  }
}

class _SwitchHeader extends SliverPersistentHeaderDelegate {
  final Color bg;
  _SwitchHeader(this.bg);
  @override
  double get minExtent => 62;
  @override
  double get maxExtent => 62;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => Container(
        color: bg,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: ModeSwitch(detailed: app.detailed, onChanged: app.setDetailed),
      );
  @override
  bool shouldRebuild(covariant _SwitchHeader old) => true;
}

class _Short extends StatelessWidget {
  final Story s;
  const _Short(this.s, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = catOf(s.cat).color;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('DAS WICHTIGSTE', style: sans(context, 12, w: FontWeight.w700, ls: 1.1, color: muted(context))),
        const SizedBox(height: 12),
        for (final b in s.summary)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                  width: 7, height: 7, margin: const EdgeInsets.only(top: 9, right: 12), color: c),
              Expanded(child: Text(b, style: serif(context, 17.5, w: FontWeight.w400, h: 1.5))),
            ]),
          ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: () => app.setDetailed(true),
          icon: const Icon(Icons.subject, size: 18),
          label: const Text('Ausführlich lesen'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ]),
    );
  }
}

class _Detailed extends StatelessWidget {
  final Story s;
  const _Detailed(this.s, {super.key});

  @override
  Widget build(BuildContext context) {
    final cached = app.cachedArticle(s.id);
    if (cached != null) return _body(context, cached);
    return FutureBuilder<Article?>(
      future: app.article(s.id),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
              padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
        }
        if (snap.data == null) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Die ausführliche Fassung konnte nicht geladen werden. Bitte Verbindung prüfen.',
                style: sans(context, 14, color: muted(context))),
          );
        }
        return _body(context, snap.data!);
      },
    );
  }

  Widget _body(BuildContext context, Article a) {
    final cs = Theme.of(context).colorScheme;
    final c = catOf(s.cat).color;
    final body = serif(context, 17.5, w: FontWeight.w400, h: 1.6);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final (i, sec) in a.sections.indexed) ...[
          if (sec.h.isNotEmpty) ...[
            SizedBox(height: i == 0 ? 4 : 18),
            Text(sec.h, style: serif(context, 20.5, w: FontWeight.w700)),
            const SizedBox(height: 8),
          ],
          for (final p in sec.text.split(RegExp(r'\n\s*\n')).where((p) => p.trim().isNotEmpty))
            Padding(padding: const EdgeInsets.only(bottom: 14), child: Text(p.trim(), style: body)),
          if (i == 0 && a.facts.isNotEmpty) _facts(context, a, c, cs),
        ],
        if (a.sections.isEmpty && a.facts.isNotEmpty) _facts(context, a, c, cs),
        if (a.positions.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('Positionen', style: serif(context, 20.5, w: FontWeight.w700)),
          const SizedBox(height: 10),
          for (final p in a.positions)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.fromLTRB(14, 10, 12, 12),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: c, width: 3)),
                color: cs.surfaceContainerLowest,
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.key, style: sans(context, 13.5, w: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(p.value, style: sans(context, 15, h: 1.5)),
              ]),
            ),
        ],
        if (a.outlook.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.event_note_outlined, size: 18, color: muted(context)),
                const SizedBox(width: 8),
                Text('Wie es weitergeht', style: sans(context, 14, w: FontWeight.w700)),
              ]),
              const SizedBox(height: 8),
              Text(a.outlook, style: sans(context, 15, h: 1.5)),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _facts(BuildContext context, Article a, Color c, ColorScheme cs) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 4, bottom: 18),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.16 : 0.07),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('IN ZAHLEN', style: sans(context, 11.5, w: FontWeight.w700, ls: 1.1, color: muted(context))),
          const SizedBox(height: 10),
          for (final f in a.facts)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(f.value, style: serif(context, 20, w: FontWeight.w700)),
                Text(f.key, style: sans(context, 13, color: muted(context))),
              ]),
            ),
        ]),
      );
}

class _Sources extends StatelessWidget {
  final Story s;
  const _Sources(this.s);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 48),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Divider(),
        const SizedBox(height: 16),
        Text('Berichte, auf denen diese Meldung beruht', style: sans(context, 13, w: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Links zu den Originalberichten. Die Medien haben diesen Text weder verfasst noch geprüft.',
            style: sans(context, 12, color: muted(context), h: 1.45)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final src in s.sources)
            ActionChip(
              label: Text(src.name),
              labelStyle: sans(context, 12.5, w: FontWeight.w500),
              avatar: Icon(Icons.open_in_new, size: 14, color: muted(context)),
              side: BorderSide(color: cs.outline),
              backgroundColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              onPressed: src.url.isEmpty ? null : () => _open(src.url),
            ),
        ]),
        const SizedBox(height: 18),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.auto_awesome_outlined, size: 16, color: muted(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Dieser Text wurde von einer KI eigenständig auf Basis der genannten Berichte verfasst und wird bei neuen Entwicklungen aktualisiert. Trotz Sorgfalt sind Fehler möglich.',
              style: sans(context, 12, color: muted(context), h: 1.5),
            ),
          ),
        ]),
        if (operatorSet) ...[
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: () => _open(Uri(
              scheme: 'mailto',
              path: operatorEmail,
              query: 'subject=${Uri.encodeComponent('Fehler in: ${s.title}')}'
                  '&body=${Uri.encodeComponent('Artikel-ID: ${s.id}\n\nWas ist falsch?\n')}',
            ).toString()),
            icon: const Icon(Icons.flag_outlined, size: 18),
            label: const Text('Fehler melden'),
          ),
        ],
      ]),
    );
  }
}
