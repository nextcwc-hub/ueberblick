import 'dart:math';

class Img {
  final String url, credit, license, src;
  final double ratio;
  Img(Map j)
      : url = j['url'] ?? '',
        credit = j['credit'] ?? '',
        license = j['license'] ?? '',
        src = j['src'] ?? '',
        ratio = ((j['w'] ?? 16) as num) / max(1, ((j['h'] ?? 9) as num));
}

class Source {
  final String name, url;
  Source(Map j)
      : name = j['n'] ?? '',
        url = j['u'] ?? '';
}

class Story {
  final Map<String, dynamic> raw;
  final String id, cat, title, teaser, loc, tone;
  final List<String> summary;
  final Img? img;
  final DateTime created, updated;
  final int imp, srcn, ver;
  final List<Source> sources;

  Story(this.raw)
      : id = raw['id'],
        cat = raw['cat'] ?? 'inland',
        title = raw['title'] ?? '',
        teaser = raw['teaser'] ?? '',
        loc = raw['loc'] ?? '',
        tone = raw['tone'] ?? 'neutral',
        summary = List<String>.from(raw['summary'] ?? const []),
        img = raw['img'] == null ? null : Img(raw['img']),
        created = DateTime.fromMillisecondsSinceEpoch((raw['created'] as num).toInt() * 1000),
        updated = DateTime.fromMillisecondsSinceEpoch((raw['updated'] as num).toInt() * 1000),
        imp = (raw['imp'] ?? 5) as int,
        srcn = (raw['srcn'] ?? 1) as int,
        ver = (raw['ver'] ?? 1) as int,
        sources = [for (final s in (raw['sources'] ?? const [])) Source(s)];

  bool get isBreaking => imp >= 9 && DateTime.now().difference(created).inHours < 3;
  bool get wasUpdated => ver > 1 && updated.difference(created).inMinutes > 10;

  /// Relevanz: Bedeutung + Anzahl unabhängiger Quellen, abnehmend mit dem Alter.
  double get relevance {
    final ageH = DateTime.now().difference(updated).inMinutes / 60.0;
    return imp * 10 + 7 * log(1 + srcn) - 1.6 * ageH;
  }
}

class Section {
  final String h, text;
  Section(Map j)
      : h = j['h'] ?? '',
        text = j['text'] ?? '';
}

class Article {
  final Map<String, dynamic> raw;
  final List<Section> sections;
  final List<MapEntry<String, String>> facts;
  final List<MapEntry<String, String>> positions;
  final String outlook;
  Article(this.raw)
      : sections = [for (final s in (raw['sections'] ?? const [])) Section(s)],
        facts = [for (final f in (raw['facts'] ?? const [])) MapEntry(f['k'] ?? '', f['v'] ?? '')],
        positions = [for (final p in (raw['positions'] ?? const [])) MapEntry(p['who'] ?? '', p['view'] ?? '')],
        outlook = raw['outlook'] ?? '';
}

class Market {
  final String sym, name, kind, cur;
  final double price, prev, pct;
  final DateTime? time;
  final List<List<double>> intraday, history;
  Market(Map j)
      : sym = j['sym'],
        name = j['name'],
        kind = j['kind'] ?? 'index',
        cur = j['cur'] ?? '',
        price = (j['price'] as num).toDouble(),
        prev = (j['prev'] as num).toDouble(),
        pct = (j['pct'] as num).toDouble(),
        time = j['time'] == null ? null : DateTime.fromMillisecondsSinceEpoch((j['time'] as num).toInt() * 1000),
        intraday = _pts(j['intraday']),
        history = _pts(j['history']);

  static List<List<double>> _pts(dynamic l) =>
      [for (final p in (l ?? const [])) [(p[0] as num).toDouble(), (p[1] as num).toDouble()]];
}

String ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'gerade eben';
  if (d.inMinutes < 60) return 'vor ${d.inMinutes} Min.';
  if (d.inHours < 6) return 'vor ${d.inHours} Std.';
  return clock(t);
}

String two(int n) => n.toString().padLeft(2, '0');

String clock(DateTime t) {
  final now = DateTime.now();
  final hm = '${two(t.hour)}:${two(t.minute)}';
  final day = DateTime(t.year, t.month, t.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'heute, $hm';
  if (diff == 1) return 'gestern, $hm';
  return '${two(t.day)}.${two(t.month)}., $hm';
}

String fmtNum(double v, {int digits = 2}) {
  final s = v.toStringAsFixed(digits);
  final parts = s.split('.');
  final neg = parts[0].startsWith('-');
  var intPart = neg ? parts[0].substring(1) : parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write('.');
    buf.write(intPart[i]);
  }
  return '${neg ? '−' : ''}$buf${digits > 0 ? ',${parts[1]}' : ''}';
}
