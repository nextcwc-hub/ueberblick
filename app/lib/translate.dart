import 'dart:convert';
import 'dart:io';

import 'package:google_mlkit_translation/google_mlkit_translation.dart';

/// Sprachen für die Artikelübersetzung (Übersetzung läuft komplett auf dem Gerät, Google ML Kit).
const languageNames = <String, String>{
  'de': 'Deutsch', 'en': 'English', 'fr': 'Français', 'es': 'Español', 'it': 'Italiano', 'pt': 'Português',
  'nl': 'Nederlands', 'pl': 'Polski', 'tr': 'Türkçe', 'ru': 'Русский', 'uk': 'Українська', 'ar': 'العربية',
  'fa': 'فارسی', 'zh': '中文', 'ja': '日本語', 'ko': '한국어', 'hi': 'हिन्दी', 'bn': 'বাংলা', 'ur': 'اردو',
  'sv': 'Svenska', 'da': 'Dansk', 'no': 'Norsk', 'fi': 'Suomi', 'is': 'Íslenska', 'cs': 'Čeština', 'sk': 'Slovenčina',
  'hu': 'Magyar', 'ro': 'Română', 'bg': 'Български', 'hr': 'Hrvatski', 'sl': 'Slovenščina', 'el': 'Ελληνικά',
  'he': 'עברית', 'sq': 'Shqip', 'mk': 'Македонски', 'be': 'Беларуская', 'lt': 'Lietuvių', 'lv': 'Latviešu',
  'et': 'Eesti', 'ga': 'Gaeilge', 'cy': 'Cymraeg', 'mt': 'Malti', 'ca': 'Català', 'gl': 'Galego', 'eo': 'Esperanto',
  'ka': 'ქართული', 'id': 'Bahasa Indonesia', 'ms': 'Bahasa Melayu', 'vi': 'Tiếng Việt', 'th': 'ไทย',
  'tl': 'Tagalog', 'sw': 'Kiswahili', 'af': 'Afrikaans', 'ta': 'தமிழ்', 'te': 'తెలుగు', 'mr': 'मराठी',
  'gu': 'ગુજરાતી', 'kn': 'ಕನ್ನಡ', 'ht': 'Kreyòl ayisyen',
};

/// Nur Sprachen, die ML Kit tatsächlich unterstützt.
List<String> get availableLanguages {
  final supported = {for (final l in TranslateLanguage.values) l.bcpCode};
  return [for (final c in languageNames.keys) if (c == 'de' || supported.contains(c)) c];
}

TranslateLanguage? _lang(String code) {
  for (final l in TranslateLanguage.values) {
    if (l.bcpCode == code) return l;
  }
  return null;
}

class DeviceTranslator {
  String target = 'de';
  OnDeviceTranslator? _tr;
  final _mm = OnDeviceTranslatorModelManager();
  Map<String, String> _cache = {};
  File? _file;
  bool _dirty = false;

  bool get active => target != 'de' && _tr != null;

  Future<void> init(Directory? dir, String lang) async {
    if (dir != null) {
      _file = File('${dir.path}/translations_$lang.json');
      try {
        if (await _file!.exists()) _cache = Map<String, String>.from(jsonDecode(await _file!.readAsString()));
      } catch (_) {}
    }
    target = lang;
    if (lang != 'de' && await _mm.isModelDownloaded(TranslateLanguage.german.bcpCode) &&
        (lang == 'en' || await _mm.isModelDownloaded(lang))) {
      _open(lang);
    }
  }

  void _open(String lang) {
    _tr?.close();
    final l = _lang(lang);
    _tr = l == null ? null : OnDeviceTranslator(sourceLanguage: TranslateLanguage.german, targetLanguage: l);
  }

  /// Lädt die benötigten Sprachpakete (Deutsch als Quelle + Zielsprache) und entfernt nicht mehr benötigte.
  Future<bool> setLanguage(String lang, Directory? dir) async {
    final old = target;
    try {
      if (lang != 'de') {
        await _mm.downloadModel(TranslateLanguage.german.bcpCode, isWifiRequired: false);
        if (lang != 'en') await _mm.downloadModel(lang, isWifiRequired: false);
      }
      if (old != 'de' && old != 'en' && old != lang) await _mm.deleteModel(old);
      if (lang == 'de') await _mm.deleteModel(TranslateLanguage.german.bcpCode);
    } catch (_) {
      if (lang != 'de') return false;
    }
    target = lang;
    _cache = {};
    if (dir != null) {
      for (final f in dir.listSync().whereType<File>()) {
        if (f.path.contains('translations_') && !f.path.endsWith('translations_$lang.json')) f.deleteSync();
      }
      _file = File('${dir.path}/translations_$lang.json');
    }
    if (lang == 'de') {
      _tr?.close();
      _tr = null;
    } else {
      _open(lang);
    }
    return true;
  }

  String? cached(String text) => target == 'de' ? text : _cache[text];

  Future<String> text(String s) async {
    if (!active || s.trim().isEmpty) return s;
    final c = _cache[s];
    if (c != null) return c;
    try {
      final r = await _tr!.translateText(s);
      _cache[s] = r;
      _dirty = true;
      return r;
    } catch (_) {
      return s;
    }
  }

  Future<void> save() async {
    if (!_dirty || _file == null) return;
    _dirty = false;
    if (_cache.length > 6000) _cache = Map.fromEntries(_cache.entries.skip(_cache.length - 4000));
    try {
      await _file!.writeAsString(jsonEncode(_cache));
    } catch (_) {}
  }
}
