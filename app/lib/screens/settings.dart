import 'package:flutter/material.dart';

import '../data.dart';
import '../theme.dart';
import '../widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Einstellungen', style: serif(context, 21, w: FontWeight.w700))),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) => ListView(padding: const EdgeInsets.only(bottom: 32), children: [
          const SectionLabel('Lesen'),
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
          const SectionLabel('Darstellung'),
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
          const SectionLabel('So funktioniert Überblick'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Rund um die Uhr wertet eine KI alle paar Minuten Meldungen von über 30 Medien und Behörden aus, '
              'bündelt Berichte zum selben Ereignis und schreibt daraus einen eigenen, möglichst neutralen Artikel '
              '– als Kurzfassung und ausführlich. Behauptungen werden der jeweiligen Seite zugeordnet, bei Kontroversen '
              'werden die wichtigsten Positionen gegenübergestellt. Neue Entwicklungen fließen automatisch in den Artikel ein.\n\n'
              'Unter jedem Artikel stehen die Berichte, auf denen er beruht. KI kann Fehler machen – '
              'bei wichtigen Entscheidungen bitte die Originalquellen prüfen.',
              style: sans(context, 14, h: 1.55, color: muted(context)),
            ),
          ),
          const SectionLabel('Daten & Lizenzen'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Fotos: Wikimedia Commons (freie Lizenzen, Urheber jeweils am Bild).\n'
              'Wetter: Deutscher Wetterdienst über Bright Sky.\n'
              'Kurse: verzögert, ohne Gewähr.',
              style: sans(context, 13.5, h: 1.6, color: muted(context)),
            ),
          ),
          const SizedBox(height: 16),
          Center(child: Text('Überblick 1.0', style: sans(context, 12, color: muted(context)))),
        ]),
      ),
    );
  }
}
