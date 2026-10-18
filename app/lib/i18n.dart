/// Oberflächensprache: Deutsch (Standard) oder Englisch (für alle anderen gewählten Sprachen).
/// Artikelinhalte werden separat auf dem Gerät übersetzt (siehe translate.dart).
library;

bool uiEn = false;

String t(String de) => uiEn ? (_en[de] ?? de) : de;

const _en = <String, String>{
  // Navigation & Allgemeines
  'Nachrichten': 'News', 'Wetter': 'Weather', 'Börse': 'Markets', 'Gemerkt': 'Saved',
  'Suchen': 'Search', 'Einstellungen': 'Settings', 'Alle': 'All', 'Neu laden': 'Reload',
  'Erneut versuchen': 'Try again', 'Keine Treffer': 'No results', 'Suchbegriff eingeben': 'Enter a search term',
  'Meldungen durchsuchen': 'Search stories',
  // Kategorien
  'Inland': 'Germany', 'Ausland': 'World', 'Wirtschaft': 'Business', 'Wissen': 'Science',
  'Digital': 'Tech', 'Investigativ': 'Investigative', 'Sport': 'Sports',
  // Sortierung & Stimmung
  'Neueste': 'Latest', 'Wichtigste': 'Top', 'Meistberichtet': 'Most covered', 'Zeitstrahl': 'Timeline',
  'Alle Nachrichten': 'All news', 'Nur positive': 'Positive only', 'Ohne negative': 'No negative',
  'Nur negative': 'Negative only', 'Welche Nachrichten?': 'Which news?', 'Alle Meldungen anzeigen': 'Show all stories',
  'Fortschritte, Erfolge, gute Entwicklungen': 'Progress, success, good developments',
  'Belastende Meldungen ausblenden': 'Hide distressing stories', 'Krisen, Konflikte und Probleme': 'Crises, conflicts and problems',
  'Alle Nachrichten zeigen': 'Show all news',
  // Startseite
  'Noch keine Meldungen verfügbar.': 'No stories available yet.',
  'Keine Verbindung. Bitte später erneut versuchen.': 'No connection. Please try again later.',
  'Für diesen Tag gibt es keine passenden Meldungen.': 'No matching stories for this day.',
  'Alle Texte werden automatisch von einer KI aus mehreren unabhängigen Quellen zusammengestellt und laufend aktualisiert.':
      'All texts are compiled automatically by an AI from several independent sources and updated continuously.',
  'Heute': 'Today', 'Gestern': 'Yesterday', 'heute': 'today', 'gestern': 'yesterday',
  'EILMELDUNG': 'BREAKING', 'aktualisiert': 'updated', 'gerade eben': 'just now',
  '1 Quelle': '1 source', 'Quellen': 'sources', '1 neue Meldung': '1 new story', 'neue Meldungen': 'new stories',
  // Artikel
  'Kurz': 'Short', 'Ausführlich': 'Detailed', 'DAS WICHTIGSTE': 'KEY POINTS', 'Ausführlich lesen': 'Read in detail',
  'IN ZAHLEN': 'IN NUMBERS', 'Positionen': 'Positions', 'Wie es weitergeht': "What's next",
  'Die ausführliche Fassung konnte nicht geladen werden. Bitte Verbindung prüfen.':
      'The detailed version could not be loaded. Please check your connection.',
  'Berichte, auf denen diese Meldung beruht': 'Reports this story is based on',
  'Links zu den Originalberichten. Die Medien haben diesen Text weder verfasst noch geprüft.':
      'Links to the original reports. These outlets neither wrote nor reviewed this text.',
  'Dieser Text wurde von einer KI eigenständig auf Basis der genannten Berichte verfasst und wird bei neuen Entwicklungen aktualisiert.':
      'This text was written independently by an AI based on the reports listed and is updated as the story develops.',
  ' Ein zweites KI-Modell hat ihn gegen die Quellen geprüft.': ' A second AI model checked it against the sources.',
  ' Trotz Sorgfalt sind Fehler möglich.': ' Despite all care, errors are possible.',
  'Fehler melden': 'Report an error', 'Stand': 'As of', 'Fassung': 'version', 'Korrektur': 'Correction',
  'Der Text wurde nach einer Prüfung berichtigt.': 'The text was corrected after a review.',
  'Übersetzt auf dem Gerät': 'Translated on device', 'Original anzeigen': 'Show original',
  'Übersetzung anzeigen': 'Show translation',
  // Bildnachweis
  'Foto: ': 'Photo: ', 'Foto: gemeinfrei': 'Photo: public domain', 'gemeinfrei': 'public domain', ', via ': ', via ',
  ' (Ausschnitt)': ' (cropped)', ' (Ausschnitt, unter gleicher Lizenz)': ' (cropped, same license)',
  'Bildnachweis': 'Image credit', 'Titel': 'Title', 'Urheber': 'Author', 'Lizenz': 'License', 'Quelle': 'Source',
  'Bearbeitung': 'Modification', 'Bildausschnitt für die Darstellung in der App': 'Cropped for display in the app',
  'Lizenztext': 'License text', 'Originalbild': 'Original image',
  // Wetter
  'Ort wählen': 'Choose location', 'Ort oder Postleitzahl': 'Town or postcode', 'Aktuellen Standort verwenden': 'Use current location',
  'Zuletzt verwendet': 'Recently used', 'Standortdienst ist ausgeschaltet.': 'Location services are turned off.',
  'Kein Zugriff auf den Standort erlaubt.': 'Location access was not granted.',
  'Standort konnte nicht ermittelt werden.': 'Location could not be determined.',
  'Wetterdaten nicht erreichbar.': 'Weather data unavailable.', 'Nächste 36 Stunden': 'Next 36 hours',
  'Die nächsten Tage': 'Next days', 'Wetterbericht Deutschland': 'Weather report Germany',
  'Daten: Deutscher Wetterdienst (DWD), bereitgestellt über Bright Sky.': 'Data: German Weather Service (DWD), via Bright Sky.',
  'Sonnig': 'Sunny', 'Klar': 'Clear', 'Teils bewölkt': 'Partly cloudy', 'Bewölkt': 'Cloudy', 'Nebel': 'Fog',
  'Windig': 'Windy', 'Regen': 'Rain', 'Schneeregen': 'Sleet', 'Schnee': 'Snow', 'Hagel': 'Hail', 'Gewitter': 'Thunderstorm',
  'Unwetterwarnung': 'Weather warning', 'Wind': 'wind', 'Feuchte': 'humidity', 'Uhr': '', 'bis': 'to',
  'Warnregion': 'Warning area', 'gültig bis': 'valid until', 'jetzt': 'now', '+1 Std.': '+1 h',
  'Kein Niederschlag in den nächsten zwei Stunden': 'No precipitation in the next two hours',
  'Leichter Regen': 'Light rain', 'Starker Regen': 'Heavy rain', 'hält an': 'continues',
  'endet voraussichtlich gegen': 'expected to stop around', 'ab etwa': 'from around', 'Zeitweise': 'Intermittent',
  'bis etwa': 'until around',
  // Börse
  'Börse & Märkte': 'Markets', 'Auf einen Blick': 'At a glance', 'Börsen- & Wirtschaftsnachrichten': 'Business & markets news',
  'Alle Werte': 'All values', 'Devisen': 'Currencies', 'Zinsen': 'Rates', 'Inflation': 'Inflation', 'Krypto': 'Crypto',
  'Daten werden geladen …': 'Loading data …', 'Daten nicht verfügbar': 'Data unavailable',
  'Keine Daten für diesen Zeitraum': 'No data for this period', 'Kennzahlen': 'Key figures',
  'Vortag': 'Previous day', 'Vormonat': 'Previous month', 'vor 24 Std.': '24 h ago', 'Aktuell': 'Current',
  '24-Std.-Hoch': '24 h high', '24-Std.-Tief': '24 h low', '12-Monats-Hoch': '12-month high', '12-Monats-Tief': '12-month low',
  'zum Vortag': 'vs. previous day', 'zum Vormonat': 'vs. previous month', '24 Std.': '24 h',
  'in 24 Std.': 'in 24 h', 'in 1 Woche': 'in 1 week', 'in 1 Monat': 'in 1 month', 'in 6 Monaten': 'in 6 months',
  'in 1 Jahr': 'in 1 year', 'in 5 Jahren': 'in 5 years', 'in 10 Jahren': 'in 10 years',
  'Nachrichten zu': 'News on', 'Aktuell keine Meldungen, die sich direkt darauf beziehen.': 'No stories directly related right now.',
  'Zum Ablesen genauer Werte über das Diagramm wischen.': 'Swipe across the chart to read exact values.',
  ' „N“ markiert passende Nachrichten – antippen zum Lesen.': ' “N” marks related news – tap to read.',
  'Devisen und Zinsen: Europäische Zentralbank (Referenzkurse, werktäglich ca. 16 Uhr). ':
      'Currencies and rates: European Central Bank (reference rates, weekdays around 4 pm CET). ',
  'Inflation: Eurostat. Ohne Gewähr, keine Anlageberatung.': 'Inflation: Eurostat. No guarantee, not investment advice.',
  'Krypto-Kurse: Powered by CoinGecko': 'Crypto prices: Powered by CoinGecko',
  'Powered by CoinGecko. Ohne Gewähr, keine Anlageberatung.': 'Powered by CoinGecko. No guarantee, not investment advice.',
  'Quelle: Europäische Zentralbank. Ohne Gewähr.': 'Source: European Central Bank. No guarantee.',
  'Quelle: Eurostat (HICP, Veränderung zum Vorjahresmonat).': 'Source: Eurostat (HICP, change vs. same month last year).',
  // Marktnamen
  'Euro / US-Dollar': 'Euro / US dollar', 'Euro / Pfund': 'Euro / Pound', 'Euro / Franken': 'Euro / Swiss franc',
  'Euro / Yen': 'Euro / Yen', 'Euro / Yuan': 'Euro / Yuan', 'Euro / Złoty': 'Euro / Złoty', 'Euro / Lira': 'Euro / Lira',
  'EZB-Einlagenzins': 'ECB deposit rate', '€STR (Tagesgeld)': '€STR (overnight rate)',
  'Rendite 10 J. (Euroraum, AAA)': '10-year yield (euro area, AAA)', 'Rendite Bundesanleihe 10 J.': '10-year Bund yield',
  'Inflation Deutschland': 'Inflation Germany', 'Inflation Euroraum': 'Inflation euro area', 'Bitcoin': 'Bitcoin',
  // Gemerkt
  'Tippe in einem Artikel auf das Lesezeichen, um ihn hier offline zu speichern.':
      'Tap the bookmark in an article to save it here for offline reading.',
  // Einstellungen
  'Lesen': 'Reading', 'Artikel standardmäßig': 'Default article view', 'Schriftgröße': 'Text size',
  'Darstellung': 'Appearance', 'System': 'System', 'Hell': 'Light', 'Dunkel': 'Dark', 'Nachrichtenauswahl': 'News filter',
  'Sprache': 'Language', 'So funktioniert Überblick': 'How Überblick works', 'Rechtliches': 'Legal',
  'Impressum': 'Legal notice (Impressum)', 'Anbieter, Quellen und Lizenzen': 'Provider, sources and licenses',
  'Datenschutzerklärung': 'Privacy policy', 'Datenschutz': 'Privacy',
  'Sprachpaket wird geladen …': 'Downloading language pack …',
  'Sprachpaket konnte nicht geladen werden. Bitte Internetverbindung prüfen.':
      'The language pack could not be downloaded. Please check your connection.',
  'Artikel werden auf dem Gerät übersetzt. Das Sprachpaket (ca. 30 MB) wird einmalig geladen.':
      'Articles are translated on your device. The language pack (approx. 30 MB) is downloaded once.',
  'Rund um die Uhr wertet eine KI alle paar Minuten Meldungen von über 30 Medien und Behörden aus, '
          'bündelt Berichte zum selben Ereignis und schreibt daraus einen eigenen, möglichst neutralen Artikel '
          '– als Kurzfassung und ausführlich. Behauptungen werden der jeweiligen Seite zugeordnet, bei Kontroversen '
          'werden die wichtigsten Positionen gegenübergestellt. Neue Entwicklungen fließen automatisch in den Artikel ein.\n\n'
          'Unter jedem Artikel stehen die Berichte, auf denen er beruht. KI kann Fehler machen – '
          'bei wichtigen Entscheidungen bitte die Originalquellen prüfen.':
      'Around the clock, an AI analyses reports from more than 30 outlets and authorities every few minutes, groups '
          'reports on the same event and writes its own article that is as neutral as possible – as a summary and in '
          'detail. Claims are attributed to their source; for controversial topics the main positions are presented side '
          'by side. New developments are added automatically.\n\nThe reports each article is based on are listed below '
          'it. AI can make mistakes – please check the original sources for important decisions.',
  'Rechtliche Angaben gelten nach deutschem Recht und sind daher auf Deutsch.':
      'Legal information is governed by German law and is therefore provided in German.',
};

const _wdDe = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];
const _wdEn = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _wdsDe = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
const _wdsEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _moDe = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];
const _moEn = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

List<String> get weekdaysLong => uiEn ? _wdEn : _wdDe;
List<String> get weekdaysShort => uiEn ? _wdsEn : _wdsDe;
List<String> get monthsLong => uiEn ? _moEn : _moDe;

/// „Montag, 17. Oktober“ bzw. „Monday, 17 October“
String longDate(DateTime d) => '${weekdaysLong[d.weekday - 1]}, ${d.day}. ${monthsLong[d.month - 1]}'
    .replaceFirst(uiEn ? '. ' : '\u0000', ' ');

String minutesAgo(int m) => uiEn ? '$m min ago' : 'vor $m Min.';
String hoursAgo(int h) => uiEn ? '$h h ago' : 'vor $h Std.';
String nSources(int n) => n == 1 ? t('1 Quelle') : (uiEn ? '$n sources' : '$n Quellen');
String nNew(int n) => n == 1 ? t('1 neue Meldung') : (uiEn ? '$n new stories' : '$n neue Meldungen');
