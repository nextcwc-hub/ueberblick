import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

const feedBase = 'https://nextcwc-hub.github.io/ueberblick/v1/';

enum SortMode { newest, relevance, sources }

class AppState extends ChangeNotifier {
  late SharedPreferences _p;
  Directory? _dir;

  List<Story> stories = [];
  List<Story> pending = []; // neu eingetroffen, noch nicht eingeblendet
  DateTime? generated;
  bool loading = false;
  String? error;
  List<Market> markets = [];
  DateTime? marketsUpdated;
  final Map<String, Article> _articles = {};
  final Map<String, Future<Article?>> _inflight = {};

  // Einstellungen
  ThemeMode themeMode = ThemeMode.system;
  double textScale = 1.0;
  bool detailed = false;
  SortMode sort = SortMode.newest;
  String weatherCity = 'Berlin';
  Map<String, dynamic> saved = {}; // id -> {story, article}

  Timer? _timer;

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    themeMode = ThemeMode.values[_p.getInt('theme') ?? 0];
    textScale = _p.getDouble('textScale') ?? 1.0;
    detailed = _p.getBool('detailed') ?? false;
    sort = SortMode.values[_p.getInt('sort') ?? 0];
    weatherCity = _p.getString('city') ?? 'Berlin';
    saved = jsonDecode(_p.getString('saved') ?? '{}');
    try {
      _dir = await getApplicationSupportDirectory();
      final f = File('${_dir!.path}/index.json');
      if (await f.exists()) _applyIndex(jsonDecode(await f.readAsString()), initial: true);
      final m = File('${_dir!.path}/markets.json');
      if (await m.exists()) _applyMarkets(jsonDecode(await m.readAsString()));
    } catch (_) {}
  }

  void startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 90), (_) => refresh(silent: true));
  }

  void stopPolling() => _timer?.cancel();

  Future<Map<String, dynamic>?> _get(String path) async {
    final t = DateTime.now().millisecondsSinceEpoch ~/ 30000;
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
      final m = await _get('markets.json');
      if (m != null) {
        _applyMarkets(m);
        if (_dir != null) File('${_dir!.path}/markets.json').writeAsString(jsonEncode(m));
      }
    } catch (e) {
      if (stories.isEmpty) error = 'Keine Verbindung. Bitte später erneut versuchen.';
    }
    loading = false;
    notifyListeners();
  }

  void _applyIndex(Map<String, dynamic> j, {bool initial = false, bool applyNow = true}) {
    generated = DateTime.fromMillisecondsSinceEpoch(((j['generated'] ?? 0) as num).toInt() * 1000);
    final fresh = [for (final s in (j['stories'] ?? const [])) Story(Map<String, dynamic>.from(s))];
    // geänderte Artikel neu laden
    final old = {for (final s in stories) s.id: s.ver};
    for (final s in fresh) {
      if (old.containsKey(s.id) && old[s.id] != s.ver) _articles.remove(s.id);
    }
    if (initial || applyNow || stories.isEmpty) {
      stories = fresh;
      pending = [];
    } else {
      final known = {for (final s in stories) s.id};
      final newOnes = fresh.where((s) => !known.contains(s.id)).toList();
      // Aktualisierungen bekannter Meldungen sofort übernehmen, neue als Hinweis
      final byId = {for (final s in fresh) s.id: s};
      stories = [for (final s in stories) if (byId.containsKey(s.id)) byId[s.id]!];
      pending = newOnes;
      if (newOnes.isNotEmpty) _pendingAll = fresh;
    }
  }

  List<Story>? _pendingAll;

  void applyPending() {
    if (_pendingAll != null) stories = _pendingAll!;
    _pendingAll = null;
    pending = [];
    notifyListeners();
  }

  void _applyMarkets(Map<String, dynamic> j) {
    markets = [for (final m in (j['items'] ?? const [])) Market(m)];
    marketsUpdated = DateTime.fromMillisecondsSinceEpoch(((j['updated'] ?? 0) as num).toInt() * 1000);
  }

  List<Story> filtered(String? cat, {String query = ''}) {
    var l = stories.where((s) => cat == null || s.cat == cat).toList();
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
        l.sort((a, b) => b.updated.compareTo(a.updated));
      case SortMode.relevance:
        l.sort((a, b) => b.relevance.compareTo(a.relevance));
      case SortMode.sources:
        l.sort((a, b) => b.srcn != a.srcn ? b.srcn.compareTo(a.srcn) : b.updated.compareTo(a.updated));
    }
    return l;
  }

  Story? byId(String id) {
    for (final s in stories) {
      if (s.id == id) return s;
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
    for (final s in l.take(6)) {
      if (!_articles.containsKey(s.id)) article(s.id);
    }
  }

  // ---------- Merkliste
  bool isSaved(String id) => saved.containsKey(id);

  Future<void> toggleSaved(Story s) async {
    if (saved.containsKey(s.id)) {
      saved.remove(s.id);
    } else {
      final a = await article(s.id);
      saved[s.id] = {'story': s.raw, 'article': a?.raw, 'at': DateTime.now().millisecondsSinceEpoch};
    }
    _p.setString('saved', jsonEncode(saved));
    notifyListeners();
  }

  List<Story> get savedStories {
    final e = saved.entries.toList()..sort((a, b) => (b.value['at'] as int).compareTo(a.value['at'] as int));
    return [for (final x in e) Story(Map<String, dynamic>.from(x.value['story']))];
  }

  // ---------- Einstellungen
  void setDetailed(bool v) {
    if (detailed == v) return;
    detailed = v;
    _p.setBool('detailed', v);
    notifyListeners();
  }

  void setSort(SortMode m) {
    sort = m;
    _p.setInt('sort', m.index);
    notifyListeners();
  }

  void setTheme(ThemeMode m) {
    themeMode = m;
    _p.setInt('theme', m.index);
    notifyListeners();
  }

  void setTextScale(double v) {
    textScale = v;
    _p.setDouble('textScale', v);
    notifyListeners();
  }

  void setCity(String c) {
    weatherCity = c;
    _p.setString('city', c);
    notifyListeners();
  }
}

final app = AppState();
