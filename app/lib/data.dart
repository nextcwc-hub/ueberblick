import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'i18n.dart';
import 'models.dart';
import 'translate.dart';

const feedBase = 'https://nextcwc-hub.github.io/ueberblick/v1/';

enum SortMode { newest, relevance, sources, timeline }

const sortLabels = {
  SortMode.newest: 'Neueste',
  SortMode.relevance: 'Wichtigste',
  SortMode.sources: 'Meistberichtet',
  SortMode.timeline: 'Zeitstrahl',
};

enum Mood { all, positive, noNegative, negative }

const moodLabels = {
  Mood.all: 'Alle Nachrichten',
  Mood.positive: 'Nur positive',
  Mood.noNegative: 'Ohne negative',
  Mood.negative: 'Nur negative',
};

const defaultPlace = Place('Berlin', '10115', 'Berlin', 52.532, 13.385);

/// Darstellung (Theme, Schriftgröße) – getrennt, damit nicht bei jeder Datenänderung die ganze App neu aufgebaut wird.
class Appearance extends ChangeNotifier {
  ThemeMode themeMode = ThemeMode.system;
  double textScale = 1.0;
  void changed() => notifyListeners();
}

class AppState extends ChangeNotifier {
  SharedPreferences? _prefs;
  Directory? _dir;
  final appearance = Appearance();

  List<Story> _orig = []; // Originalfassungen (Deutsch)
  List<Story>? _txMemo;
  int _txVer = 0, _memoVer = -1;
  List<Story>? _memoSrc;

  /// Meldungen in der eingestellten Sprache (übersetzt, sobald verfügbar)
  List<Story> get stories {
    if (lang == 'de') return _orig;
    if (_txMemo == null || _memoVer != _txVer || !identical(_memoSrc, _orig)) {
      _txMemo = [for (final s in _orig) tx(s)];
      _memoVer = _txVer;
      _memoSrc = _orig;
    }
    return _txMemo!;
  }

  set stories(List<Story> v) => _orig = v;

  // Sprache
  String lang = 'de';
  final translator = DeviceTranslator();
  bool _translating = false;
  List<Story> pending = []; // neu eingetroffen, noch nicht eingeblendet
  List<Story>? _pendingAll;
  DateTime? generated;
  bool loading = false;
  String? error;
  List<Market> markets = [];
  DateTime? marketsUpdated;
  DateTime _marketsFetched = DateTime(2000);
  final Map<String, Article> _articles = {};
  final Map<String, Future<Article?>> _inflight = {};
  final Map<String, MarketDetail> _details = {};
  final Map<String, List<Story>> _days = {};
  List<(String, int)> days = [];

  // Einstellungen
  bool detailed = false;
  SortMode sort = SortMode.newest;
  Mood mood = Mood.all;
  Place place = defaultPlace;
  List<Place> recentPlaces = [];
  Map<String, dynamic> saved = {}; // id -> {story, article}

  Timer? _timer;

  ThemeMode get themeMode => appearance.themeMode;
  double get textScale => appearance.textScale;

  Future<void> init() async {
    final p = _prefs = await SharedPreferences.getInstance();
    appearance.themeMode = ThemeMode.values[p.getInt('theme') ?? 0];
    appearance.textScale = p.getDouble('textScale') ?? 1.0;
    detailed = p.getBool('detailed') ?? false;
    sort = SortMode.values[min(p.getInt('sort') ?? 0, SortMode.values.length - 1)];
    mood = Mood.values[p.getInt('mood') ?? 0];
    lang = p.getString('lang') ?? 'de';
    uiEn = lang != 'de';
    try {
      final pl = p.getString('place');
      if (pl != null) place = Place.fromJson(jsonDecode(pl));
      recentPlaces = [for (final x in jsonDecode(p.getString('recentPlaces') ?? '[]')) Place.fromJson(x)];
    } catch (_) {}
    try {
      saved = Map<String, dynamic>.from(jsonDecode(p.getString('saved') ?? '{}'));
    } catch (_) {}
    try {
      _dir = await getApplicationSupportDirectory();
      final f = File('${_dir!.path}/index.json');
      if (await f.exists()) _applyIndex(jsonDecode(await f.readAsString()), applyNow: true);
      final m = File('${_dir!.path}/markets.json');
      if (await m.exists()) _applyMarkets(jsonDecode(await m.readAsString()));
    } catch (_) {}
    try {
      await translator.init(_dir, lang);
    } catch (_) {}
  }

  void _set(void Function(SharedPreferences p) f) {
    final p = _prefs;
    if (p != null) f(p);
  }

  void startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 90), (_) => refresh(silent: true));
  }

  void stopPolling() => _timer?.cancel();

  Future<Map<String, dynamic>?> _get(String path, {int cacheSec = 30}) async {
    final t = DateTime.now().millisecondsSinceEpoch ~/ (cacheSec * 1000);
    final r = await http.get(Uri.parse('$feedBase$path?t=$t')).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) return null;
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  Future<void> refresh({bool silent = false, bool applyNow = false}) async {
    if (loading) return;
    loading = true;
    if (!silent) notifyListeners();
    try {
      final idx = await _get('index.json');
      if (idx != null) {
        _applyIndex(idx, applyNow: applyNow || !silent);
        if (_dir != null) File('${_dir!.path}/index.json').writeAsString(jsonEncode(idx));
        error = null;
      }
      if (DateTime.now().difference(_marketsFetched).inMinutes >= 3) await refreshMarkets(notify: false);
    } catch (e) {
      if (stories.isEmpty) error = 'Keine Verbindung. Bitte später erneut versuchen.';
    }
    loading = false;
    notifyListeners();
  }

  Future<void> refreshMarkets({bool notify = true}) async {
    try {
      final m = await _get('markets.json', cacheSec: 60);
      if (m == null) return;
      _marketsFetched = DateTime.now();
      _applyMarkets(m);
      _details.clear();
      if (_dir != null) File('${_dir!.path}/markets.json').writeAsString(jsonEncode(m));
      if (notify) notifyListeners();
    } catch (_) {}
  }

  void _applyIndex(Map<String, dynamic> j, {bool applyNow = true}) {
    generated = DateTime.fromMillisecondsSinceEpoch(((j['generated'] ?? 0) as num).toInt() * 1000);
    final fresh = [for (final s in (j['stories'] ?? const [])) Story(Map<String, dynamic>.from(s))];
    final old = {for (final s in stories) s.id: s.ver};
    for (final s in fresh) {
      if (old.containsKey(s.id) && old[s.id] != s.ver) _articles.remove(s.id);
    }
    _days.remove(_dayKey(DateTime.now()));
    Future.microtask(_translateAll);
    if (applyNow || stories.isEmpty) {
      stories = fresh;
      pending = [];
      _pendingAll = null;
    } else {
      final known = {for (final s in stories) s.id};
      final byId = {for (final s in fresh) s.id: s};
      stories = [for (final s in stories) if (byId.containsKey(s.id)) byId[s.id]!];
      pending = fresh.where((s) => !known.contains(s.id)).toList();
      _pendingAll = pending.isEmpty ? null : fresh;
    }
  }

  void applyPending() {
    if (_pendingAll == null && pending.isEmpty) return;
    if (_pendingAll != null) stories = _pendingAll!;
    _pendingAll = null;
    pending = [];
    notifyListeners();
  }

  void _applyMarkets(Map<String, dynamic> j) {
    markets = [for (final m in (j['items'] ?? const [])) Market(m)];
    marketsUpdated = DateTime.fromMillisecondsSinceEpoch(((j['updated'] ?? 0) as num).toInt() * 1000);
  }

  bool moodOk(Story s) => switch (mood) {
        Mood.all => true,
        Mood.positive => s.tone == 'positiv',
        Mood.noNegative => s.tone != 'negativ',
        Mood.negative => s.tone == 'negativ',
      };

  List<Story> filtered(String? cat, {String query = '', List<Story>? from}) {
    var l = (from ?? stories).where((s) => (cat == null || s.cat == cat) && moodOk(s)).toList();
    if (query.isNotEmpty) {
      final q = query.toLowerCase();
      l = l
          .where((s) =>
              s.title.toLowerCase().contains(q) ||
              s.teaser.toLowerCase().contains(q) ||
              s.summary.any((x) => x.toLowerCase().contains(q)))
          .toList();
    }
    switch (sort) {
      case SortMode.newest:
        l.sort((a, b) => b.time.compareTo(a.time));
      case SortMode.relevance:
        l.sort((a, b) => b.relevance.compareTo(a.relevance));
      case SortMode.sources:
        l.sort((a, b) => b.srcn != a.srcn ? b.srcn.compareTo(a.srcn) : b.time.compareTo(a.time));
      case SortMode.timeline:
        l.sort((a, b) => b.created.compareTo(a.created));
    }
    return l;
  }

  // ---------- Zeitstrahl / Archiv
  static String _dayKey(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

  Future<void> loadDays() async {
    try {
      final j = await _get('days.json', cacheSec: 120);
      if (j == null) return;
      days = [for (final d in j['days']) (d['date'] as String, (d['n'] as num).toInt())];
      notifyListeners();
    } catch (_) {}
  }

  List<Story>? cachedDay(DateTime d) => _days[_dayKey(d)] == null ? null : [for (final s in _days[_dayKey(d)]!) tx(s)];

  Future<List<Story>> dayStories(DateTime d) async {
    final key = _dayKey(d);
    if (_days[key] != null) return [for (final s in _days[key]!) tx(s)];
    try {
      final j = await _get('days/$key.json', cacheSec: 120);
      final l = j == null ? <Story>[] : [for (final s in j['stories']) Story(Map<String, dynamic>.from(s))];
      // Aktuelle Fassungen aus dem Index bevorzugen
      final cur = {for (final s in _orig) s.id: s};
      final ids = {for (final s in l) s.id};
      _days[key] = [
        for (final s in l) cur[s.id] ?? s,
        for (final s in _orig) if (_dayKey(s.created) == key && !ids.contains(s.id)) s,
      ];
      _translateList(_days[key]!);
      return [for (final s in _days[key]!) tx(s)];
    } catch (_) {
      return [for (final s in _orig) if (_dayKey(s.created) == key) tx(s)];
    }
  }

  Story? byId(String id) {
    for (final s in _orig) {
      if (s.id == id) return tx(s);
    }
    final sv = saved[id];
    return sv == null ? null : Story(Map<String, dynamic>.from(sv['story']));
  }

  Article? cachedArticle(String id) => _articles[id];

  Future<Article?> article(String id) {
    if (_articles.containsKey(id)) return Future.value(_articles[id]);
    return _inflight[id] ??= () async {
      try {
        final j = await _get('a/$id.json');
        if (j != null) return _articles[id] = Article(j);
      } catch (_) {}
      final sv = saved[id];
      if (sv != null && sv['article'] != null) return _articles[id] = Article(Map<String, dynamic>.from(sv['article']));
      return null;
    }()
        .whenComplete(() => _inflight.remove(id));
  }

  void prefetch(Iterable<Story> l) {
    for (final s in l.take(4)) {
      if (!_articles.containsKey(s.id) && !_inflight.containsKey(s.id)) article(s.id);
    }
  }

  // ---------- Börse
  MarketDetail? cachedDetail(String sym) => _details[sym];

  Future<MarketDetail?> marketDetail(String sym) async {
    if (_details[sym] != null) return _details[sym];
    try {
      final j = await _get('m/${sym.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '_')}.json', cacheSec: 60);
      if (j != null) return _details[sym] = MarketDetail(j);
    } catch (_) {}
    return null;
  }

  /// Meldungen zu einem Börsenwert: von der KI zugeordnet oder per Stichwort gefunden.
  List<Story> relatedStories(Market m) {
    final pats = [
      for (final a in m.alias)
        // kurze Kürzel (DAX, Dow, Öl) nur als ganzes Wort, längere Namen auch als Wortanfang (Goldpreis)
        RegExp('(^|[^A-Za-zÄÖÜäöüß])${RegExp.escape(a)}${a.length <= 4 ? '(?![a-zäöüß])' : ''}',
            caseSensitive: a.length <= 4)
    ];
    final cats = {'boerse', 'wirtschaft', 'digital', 'ausland', 'inland'};
    final l = _orig.where((s) {
      if (s.assets.contains(m.sym)) return true;
      if (!cats.contains(s.cat) || pats.isEmpty) return false;
      final text = '${s.title} ${s.teaser} ${s.summary.join(' ')}';
      return pats.any((p) => p.hasMatch(text));
    }).toList()
      ..sort((a, b) => b.created.compareTo(a.created));
    return [for (final s in l) tx(s)];
  }

  // ---------- Orte
  List<Place>? _places;

  Future<List<Place>> places() async {
    if (_places != null) return _places!;
    final data = await rootBundle.load('assets/orte.tsv.gz');
    final txt = utf8.decode(gzip.decode(data.buffer.asUint8List()));
    return _places = [
      for (final line in txt.split('\n'))
        if (line.isNotEmpty)
          () {
            final f = line.split('\t');
            return Place(f[1], f[0], f[2], double.parse(f[3]), double.parse(f[4]));
          }()
    ];
  }

  Future<List<Place>> searchPlaces(String q) async {
    final all = await places();
    q = q.trim().toLowerCase();
    if (q.isEmpty) return [];
    if (RegExp(r'^\d+$').hasMatch(q)) {
      return all.where((p) => p.plz.startsWith(q)).take(60).toList();
    }
    final starts = <String, Place>{}, contains = <String, Place>{};
    for (final p in all) {
      final n = p.name.toLowerCase();
      final key = '${p.name}|${p.state}';
      if (n.startsWith(q)) {
        starts.putIfAbsent(key, () => p);
      } else if (n.contains(q)) {
        contains.putIfAbsent(key, () => p);
      }
    }
    final l = starts.values.toList()..sort((a, b) => a.name.length.compareTo(b.name.length));
    return [...l, ...contains.values].take(60).toList();
  }

  Future<Place> nearestPlace(double lat, double lon) async {
    final all = await places();
    Place best = all.first;
    var bd = double.infinity;
    for (final p in all) {
      final d = pow(p.lat - lat, 2) + pow((p.lon - lon) * cos(lat * pi / 180), 2);
      if (d < bd) {
        bd = d.toDouble();
        best = p;
      }
    }
    // auf ca. 1 km gerundet – genaue GPS-Koordinaten verlassen das Gerät nicht
    double r(double v) => (v * 100).roundToDouble() / 100;
    return Place(best.name, best.plz, best.state, r(lat), r(lon));
  }

  void setPlace(Place p) {
    place = p;
    recentPlaces = [p, ...recentPlaces.where((x) => x.label != p.label)].take(6).toList();
    _set((s) {
      s.setString('place', jsonEncode(p.toJson()));
      s.setString('recentPlaces', jsonEncode([for (final x in recentPlaces) x.toJson()]));
    });
    notifyListeners();
  }

  // ---------- Merkliste
  bool isSaved(String id) => saved.containsKey(id);

  Future<void> toggleSaved(Story s) async {
    if (saved.containsKey(s.id)) {
      saved.remove(s.id);
    } else {
      saved[s.id] = {'story': s.raw, 'article': null, 'at': DateTime.now().millisecondsSinceEpoch};
      notifyListeners();
      final a = await article(s.id);
      if (saved.containsKey(s.id)) saved[s.id]['article'] = a?.raw;
    }
    _set((p) => p.setString('saved', jsonEncode(saved)));
    notifyListeners();
  }

  List<Story> get savedStories {
    final e = saved.entries.toList()..sort((a, b) => (b.value['at'] as int).compareTo(a.value['at'] as int));
    return [for (final x in e) tx(Story(Map<String, dynamic>.from(x.value['story'])))];
  }

  // ---------- Übersetzung (auf dem Gerät)
  /// Übersetzte Fassung einer Meldung, falls schon vorhanden – sonst das Original.
  Story tx(Story s) {
    if (lang == 'de') return s;
    final c = translator.cached;
    final title = c(s.title), teaser = c(s.teaser);
    final summary = [for (final x in s.summary) c(x)];
    if (title == null || teaser == null || summary.contains(null)) return s;
    return Story({...s.raw, 'title': title, 'teaser': teaser, 'summary': summary, '_tx': true});
  }

  Future<void> _translateList(List<Story> l) async {
    if (lang == 'de' || !translator.active) return;
    var n = 0;
    for (final s in l) {
      if (lang == 'de') return;
      if (tx(s).raw['_tx'] == true) continue;
      await translator.text(s.title);
      await translator.text(s.teaser);
      for (final x in s.summary) {
        await translator.text(x);
      }
      if (++n % 6 == 0) {
        _txVer++;
        notifyListeners();
      }
    }
    if (n > 0) {
      _txVer++;
      notifyListeners();
      translator.save();
    }
  }

  void _translateAll() async {
    if (_translating) return;
    _translating = true;
    try {
      await _translateList(_orig);
    } finally {
      _translating = false;
    }
  }

  final Map<String, (Article, Article)> _articleTx = {};

  Article? cachedArticleFor(String id) {
    final a = _articles[id];
    if (a == null || lang == 'de') return a;
    final c = _articleTx[id];
    return c != null && identical(c.$1, a) ? c.$2 : null;
  }

  /// Artikel in der eingestellten Sprache (wird beim ersten Öffnen übersetzt).
  Future<Article?> articleFor(String id) async {
    final a = await article(id);
    if (a == null || lang == 'de' || !translator.active) return a;
    final c = _articleTx[id];
    if (c != null && identical(c.$1, a)) return c.$2;
    final tr = translator.text;
    final raw = {
      ...a.raw,
      'sections': [
        for (final sec in a.sections) {'h': await tr(sec.h), 'text': await _paragraphs(sec.text)}
      ],
      'facts': [for (final f in a.facts) {'k': await tr(f.key), 'v': await tr(f.value)}],
      'positions': [for (final p in a.positions) {'who': await tr(p.key), 'view': await tr(p.value)}],
      'outlook': await tr(a.outlook),
    };
    translator.save();
    final out = Article(raw);
    _articleTx[id] = (a, out);
    return out;
  }

  Future<String> _paragraphs(String text) async {
    final parts = text.split(RegExp(r'\n\s*\n'));
    return [for (final p in parts) await translator.text(p.trim())].join('\n\n');
  }

  /// Sprache wechseln – lädt bei Bedarf das Sprachpaket. Gibt false zurück, wenn das nicht klappt.
  Future<bool> setLang(String code) async {
    final ok = await translator.setLanguage(code, _dir);
    if (!ok) return false;
    lang = code;
    uiEn = code != 'de';
    _txVer++;
    _articleTx.clear();
    _set((p) => p.setString('lang', code));
    appearance.changed();
    notifyListeners();
    _translateAll();
    return true;
  }

  // ---------- Einstellungen
  void setDetailed(bool v) {
    if (detailed == v) return;
    detailed = v;
    _set((p) => p.setBool('detailed', v));
    notifyListeners();
  }

  void setSort(SortMode m) {
    if (sort == m) return;
    sort = m;
    _set((p) => p.setInt('sort', m.index));
    if (m == SortMode.timeline && days.isEmpty) loadDays();
    notifyListeners();
  }

  void setMood(Mood m) {
    mood = m;
    _set((p) => p.setInt('mood', m.index));
    notifyListeners();
  }

  void setTheme(ThemeMode m) {
    appearance.themeMode = m;
    _set((p) => p.setInt('theme', m.index));
    appearance.changed();
    notifyListeners();
  }

  void setTextScale(double v) {
    appearance.textScale = v;
    _set((p) => p.setDouble('textScale', v));
    appearance.changed();
    notifyListeners();
  }
}

final app = AppState();
