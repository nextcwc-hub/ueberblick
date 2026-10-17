import 'package:flutter/material.dart';

import 'theme.dart';

// Angaben der verantwortlichen Person (Pflicht für Nachrichtenangebote nach § 18 Abs. 2 MStV).
const operatorName = '[Vor- und Nachname]';
const operatorAddress = '[Straße und Hausnummer, PLZ Ort]';
const operatorEmail = '[E-Mail-Adresse]';

bool get operatorSet => !operatorEmail.startsWith('[');

const _impressum = [
  ('Angaben gemäß § 18 Abs. 2 MStV', '$operatorName\n$operatorAddress\nE-Mail: $operatorEmail'),
  ('Verantwortlich für den Inhalt', '$operatorName (Anschrift wie oben)'),
  (
    'Über dieses Angebot',
    'Überblick ist ein privates, nicht-kommerzielles Angebot ohne Werbung und ohne Bezahlinhalte. '
        'Die Nachrichtentexte werden automatisch von einer künstlichen Intelligenz auf Grundlage der unter jedem '
        'Artikel genannten Berichte erstellt und als solche gekennzeichnet. Trotz sorgfältiger Vorgaben können '
        'Fehler enthalten sein. Hinweise auf Fehler bitte über „Fehler melden“ im Artikel oder per E-Mail.'
  ),
  (
    'Quellen und Lizenzen',
    'Fotos: Wikimedia Commons, jeweilige Urheber und Lizenzen am Bild.\n'
        'Wetter: Deutscher Wetterdienst (CC BY 4.0), abgerufen über Bright Sky.\n'
        'Devisen und Zinsen: Europäische Zentralbank. Inflation: Eurostat.\n'
        'Krypto-Kurse: Powered by CoinGecko.\n'
        'Ortsdaten: GeoNames (CC BY 4.0).\n'
        'Schriften: Source Serif 4 und Inter (SIL Open Font License).'
  ),
  (
    'Haftung für Links',
    'Die Artikel verlinken auf Berichte anderer Medien. Für deren Inhalte sind ausschließlich die jeweiligen '
        'Anbieter verantwortlich. Die verlinkten Medien haben die Texte dieser App weder verfasst noch geprüft.'
  ),
];

const _datenschutz = [
  ('Verantwortlicher', '$operatorName\n$operatorAddress\nE-Mail: $operatorEmail'),
  (
    'Kurzfassung',
    'Die App kommt ohne Registrierung, Werbung, Tracking und Analyse-Werkzeuge aus. Es werden keine Nutzerprofile '
        'erstellt. Einstellungen und Merkliste bleiben auf deinem Gerät.'
  ),
  (
    'Abruf der Inhalte',
    'Nachrichten, Archiv und Marktdaten werden von GitHub Pages (GitHub Inc., USA) geladen. Dabei verarbeitet der '
        'Anbieter technisch notwendige Daten wie IP-Adresse, Zeitpunkt und Gerätetyp, um die Inhalte auszuliefern '
        '(Art. 6 Abs. 1 lit. f DSGVO). Die Übermittlung in die USA erfolgt auf Grundlage des EU-US Data Privacy '
        'Framework. Fotos werden direkt von Wikimedia Commons (Wikimedia Foundation, USA) geladen.'
  ),
  (
    'Wetter und Standort',
    'Für die Wetteranzeige werden die Koordinaten des gewählten Orts an Bright Sky (brightsky.dev) übermittelt, '
        'das die Daten des Deutschen Wetterdienstes bereitstellt. Die Standortfunktion wird nur genutzt, wenn du '
        '„Aktuellen Standort verwenden“ antippst und die Berechtigung erteilst. Die GPS-Position wird auf dem Gerät '
        'auf etwa einen Kilometer gerundet; genaue Koordinaten verlassen das Gerät nicht.'
  ),
  (
    'Speicherung auf dem Gerät',
    'Einstellungen, gewählter Ort, Merkliste und ein Zwischenspeicher der Nachrichten werden nur lokal auf dem '
        'Gerät gespeichert und beim Deinstallieren der App gelöscht.'
  ),
  (
    'Externe Links und E-Mail',
    'Beim Öffnen von Quellen-Links wird der jeweilige Artikel im Browser geladen; dort gelten die '
        'Datenschutzbestimmungen des Anbieters. Wenn du über „Fehler melden“ eine E-Mail schreibst, wird diese nur '
        'zur Bearbeitung deines Hinweises verwendet (Art. 6 Abs. 1 lit. f DSGVO).'
  ),
  (
    'Deine Rechte',
    'Du hast das Recht auf Auskunft, Berichtigung, Löschung, Einschränkung der Verarbeitung, Datenübertragbarkeit '
        'und Widerspruch sowie das Recht auf Beschwerde bei einer Datenschutz-Aufsichtsbehörde.'
  ),
  ('Stand', 'Oktober 2026'),
];

class LegalScreen extends StatelessWidget {
  final bool privacy;
  const LegalScreen({super.key, this.privacy = false});

  @override
  Widget build(BuildContext context) {
    final items = privacy ? _datenschutz : _impressum;
    return Scaffold(
      appBar: AppBar(title: Text(privacy ? 'Datenschutz' : 'Impressum', style: serif(context, 21, w: FontWeight.w700))),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
        for (final (h, t) in items) ...[
          Text(h, style: sans(context, 15, w: FontWeight.w700)),
          const SizedBox(height: 6),
          SelectableText(t, style: sans(context, 14.5, h: 1.55, color: muted(context))),
          const SizedBox(height: 20),
        ],
      ]),
    );
  }
}
