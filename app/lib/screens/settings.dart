import 'package:flutter/material.dart';

import '../data.dart';
import '../legal.dart';
import '../theme.dart';
import '../widgets.dart';
import '../i18n.dart';
import '../translate.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('Einstellungen'), style: serif(context, 21, w: FontWeight.w700))),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) => ListView(padding: const EdgeInsets.only(bottom: 32), children: [
          SectionLabel(t('Lesen')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Artikel standardmäßig', style: sans(context, 15, w: FontWeight.w500)),
              const SizedBox(height: 8),
              ModeSwitch(detailed: app.detailed, onChanged: app.setDetailed),
              const SizedBox(height: 22),
              Row(children: [
                Expanded(child: Text('Schriftgröße', style: sans(context, 15, w: FontWeight.w500))),
                Text('${(app.textScale * 100).round()} %', style: sans(context, 13, color: muted(context))),
              ]),
              Slider(
                value: app.textScale,
                min: 0.85,
                max: 1.4,
                divisions: 11,
                onChanged: app.setTextScale,
              ),
            ]),
          ),
          SectionLabel(t('Nachrichtenauswahl')),
          RadioGroup<Mood>(
            groupValue: app.mood,
            onChanged: (v) => app.setMood(v!),
            child: Column(children: [
              for (final m in Mood.values)
                RadioListTile<Mood>(value: m, title: Text(t(moodLabels[m]!), style: sans(context, 15)), dense: true),
            ]),
          ),
          SectionLabel(t('Sprache')),
          ListTile(
            leading: const Icon(Icons.translate),
            title: Text(languageNames[app.lang] ?? app.lang),
            subtitle: app.lang == 'de'
                ? null
                : Text(t('Artikel werden auf dem Gerät übersetzt. Das Sprachpaket (ca. 30 MB) wird einmalig geladen.')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickLanguage(context),
          ),
          SectionLabel(t('Darstellung')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('System')),
                ButtonSegment(value: ThemeMode.light, label: Text('Hell')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dunkel')),
              ],
              selected: {app.themeMode},
              onSelectionChanged: (s) => app.setTheme(s.first),
            ),
          ),
          SectionLabel(t('So funktioniert Überblick')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              t('Rund um die Uhr wertet eine KI alle paar Minuten Meldungen von über 30 Medien und Behörden aus, '
                  'bündelt Berichte zum selben Ereignis und schreibt daraus einen eigenen, möglichst neutralen Artikel '
                  '– als Kurzfassung und ausführlich. Behauptungen werden der jeweiligen Seite zugeordnet, bei Kontroversen '
                  'werden die wichtigsten Positionen gegenübergestellt. Neue Entwicklungen fließen automatisch in den Artikel ein.\n\n'
                  'Unter jedem Artikel stehen die Berichte, auf denen er beruht. KI kann Fehler machen – '
                  'bei wichtigen Entscheidungen bitte die Originalquellen prüfen.'),
              style: sans(context, 14, h: 1.55, color: muted(context)),
            ),
          ),
          SectionLabel(t('Rechtliches')),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(t('Impressum')),
            subtitle: const Text('Anbieter, Quellen und Lizenzen'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LegalScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(t('Datenschutzerklärung')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LegalScreen(privacy: true))),
          ),
          const SizedBox(height: 16),
          Center(child: Text('Überblick 1.0', style: sans(context, 12, color: muted(context)))),
        ]),
      ),
    );
  }
}


Future<void> _pickLanguage(BuildContext context) async {
  final code = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(t('Sprache'), style: serif(context, 21, w: FontWeight.w700)),
        ),
        Expanded(
          child: ListView(children: [
            for (final c in availableLanguages)
              ListTile(
                title: Text(languageNames[c] ?? c),
                trailing: c == app.lang ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary) : null,
                onTap: () => Navigator.pop(context, c),
              ),
          ]),
        ),
      ]),
    ),
  );
  if (code == null || code == app.lang || !context.mounted) return;
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      content: Row(children: [
        const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 16),
        Expanded(child: Text(code == 'de' ? '…' : t('Sprachpaket wird geladen …'))),
      ]),
    ),
  );
  final ok = await app.setLang(code);
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();
  if (!ok) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('Sprachpaket konnte nicht geladen werden. Bitte Internetverbindung prüfen.'))));
  }
}
