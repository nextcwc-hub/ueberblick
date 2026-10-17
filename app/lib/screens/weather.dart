import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../data.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'home.dart';

const cities = <String, (double, double)>{
  'Aachen': (50.776, 6.084), 'Augsburg': (48.371, 10.898), 'Berlin': (52.520, 13.405),
  'Bielefeld': (52.030, 8.532), 'Bochum': (51.482, 7.216), 'Bonn': (50.737, 7.098),
  'Braunschweig': (52.269, 10.521), 'Bremen': (53.079, 8.801), 'Chemnitz': (50.828, 12.921),
  'Cottbus': (51.756, 14.332), 'Darmstadt': (49.873, 8.651), 'Dortmund': (51.514, 7.468),
  'Dresden': (51.050, 13.737), 'Duisburg': (51.434, 6.762), 'Düsseldorf': (51.227, 6.773),
  'Erfurt': (50.978, 11.029), 'Essen': (51.456, 7.012), 'Flensburg': (54.794, 9.446),
  'Frankfurt am Main': (50.110, 8.682), 'Freiburg': (47.999, 7.842), 'Garmisch-Partenkirchen': (47.492, 11.096),
  'Göttingen': (51.541, 9.916), 'Hamburg': (53.551, 9.993), 'Hannover': (52.375, 9.732),
  'Heidelberg': (49.399, 8.672), 'Ingolstadt': (48.766, 11.426), 'Jena': (50.927, 11.586),
  'Karlsruhe': (49.007, 8.404), 'Kassel': (51.312, 9.479), 'Kiel': (54.323, 10.123),
  'Koblenz': (50.356, 7.588), 'Köln': (50.938, 6.960), 'Konstanz': (47.660, 9.175),
  'Leipzig': (51.340, 12.375), 'Lübeck': (53.866, 10.686), 'Magdeburg': (52.121, 11.628),
  'Mainz': (49.993, 8.247), 'Mannheim': (49.488, 8.466), 'München': (48.137, 11.576),
  'Münster': (51.961, 7.626), 'Nürnberg': (49.452, 11.077), 'Oldenburg': (53.143, 8.214),
  'Osnabrück': (52.279, 8.047), 'Passau': (48.575, 13.462), 'Potsdam': (52.391, 13.064),
  'Regensburg': (49.013, 12.102), 'Rostock': (54.092, 12.099), 'Saarbrücken': (49.240, 6.997),
  'Schwerin': (53.635, 11.401), 'Stuttgart': (48.778, 9.180), 'Trier': (49.750, 6.637),
  'Ulm': (48.401, 9.988), 'Wiesbaden': (50.078, 8.240), 'Würzburg': (49.792, 9.953),
  'Wuppertal': (51.256, 7.151), 'Sylt (Westerland)': (54.907, 8.308), 'Zugspitze': (47.421, 10.985),
};

const _cond = {
  'clear-day': ('Sonnig', Icons.wb_sunny_outlined),
  'clear-night': ('Klar', Icons.nightlight_outlined),
  'partly-cloudy-day': ('Teils bewölkt', Icons.wb_cloudy_outlined),
  'partly-cloudy-night': ('Teils bewölkt', Icons.cloud_queue),
  'cloudy': ('Bewölkt', Icons.cloud_outlined),
  'fog': ('Nebel', Icons.foggy),
  'wind': ('Windig', Icons.air),
  'rain': ('Regen', Icons.water_drop_outlined),
  'sleet': ('Schneeregen', Icons.ac_unit),
  'snow': ('Schnee', Icons.ac_unit),
  'hail': ('Hagel', Icons.grain),
  'thunderstorm': ('Gewitter', Icons.thunderstorm_outlined),
};

(String, IconData) cond(String? icon) => _cond[icon] ?? ('–', Icons.cloud_outlined);

Color iconColor(BuildContext c, String? icon) {
  if (icon == 'clear-day' || icon == 'partly-cloudy-day') return const Color(0xFFE59A0C);
  if (icon == 'thunderstorm') return const Color(0xFF7A5BB5);
  if (icon == 'rain' || icon == 'sleet') return const Color(0xFF2A84AE);
  return muted(c);
}

class _Wx {
  final Map current;
  final List<Map> hours;
  final List<Map> alerts;
  _Wx(this.current, this.hours, this.alerts);
}

Future<_Wx> _load(String city) async {
  final (lat, lon) = cities[city] ?? cities['Berlin']!;
  final now = DateTime.now();
  String d(DateTime t) => '${t.year}-${two(t.month)}-${two(t.day)}';
  Future<Map> get(String path, Map<String, String> q) async {
    final r = await http
        .get(Uri.https('api.brightsky.dev', path, {'lat': '$lat', 'lon': '$lon', ...q}))
        .timeout(const Duration(seconds: 15));
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  final res = await Future.wait([
    get('/current_weather', {'tz': 'Europe/Berlin'}),
    get('/weather', {'date': d(now), 'last_date': d(now.add(const Duration(days: 8))), 'tz': 'Europe/Berlin'}),
    get('/alerts', {'tz': 'Europe/Berlin'}),
  ]);
  return _Wx(
    Map.from(res[0]['weather'] ?? {}),
    [for (final h in (res[1]['weather'] ?? const [])) Map.from(h)],
    [for (final a in (res[2]['alerts'] ?? const [])) Map.from(a)],
  );
}

class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});
  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  late Future<_Wx> fut = _load(app.weatherCity);

  void _reload() => setState(() => fut = _load(app.weatherCity));

  Future<void> _pickCity() async {
    final c = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CityPicker(),
    );
    if (c != null) {
      app.setCity(c);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () async {
          _reload();
          await fut.catchError((_) => _Wx({}, [], []));
        },
        child: FutureBuilder<_Wx>(
          future: fut,
          builder: (context, snap) {
            return ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
                  child: Row(children: [
                    Expanded(child: Text('Wetter', style: serif(context, 26, w: FontWeight.w700))),
                    TextButton.icon(
                      onPressed: _pickCity,
                      icon: const Icon(Icons.place_outlined, size: 18),
                      label: Text(app.weatherCity),
                    ),
                  ]),
                ),
                if (snap.connectionState != ConnectionState.done)
                  const Padding(padding: EdgeInsets.all(60), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                else if (snap.hasError || snap.data == null)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(children: [
                      Text('Wetterdaten nicht erreichbar.', style: sans(context, 15, color: muted(context))),
                      TextButton(onPressed: _reload, child: const Text('Erneut versuchen')),
                    ]),
                  )
                else
                  ..._content(context, snap.data!),
                _reportCard(context),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: Text('Daten: Deutscher Wetterdienst (DWD), bereitgestellt über Bright Sky.',
                      style: sans(context, 11.5, color: muted(context))),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _reportCard(BuildContext context) {
    final list = app.stories.where((s) => s.cat == 'wetter').toList()
      ..sort((a, b) => b.updated.compareTo(a.updated));
    if (list.isEmpty) return const SizedBox();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionLabel('Wetterbericht Deutschland'),
      for (final (i, s) in list.take(4).indexed) ...[
        if (i > 0) const Divider(indent: 16, endIndent: 16),
        StoryTile(s, onTap: () => openStory(context, list, i)),
      ],
    ]);
  }

  List<Widget> _content(BuildContext context, _Wx w) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final hours = w.hours.where((h) {
      final t = DateTime.parse(h['timestamp']).toLocal();
      return t.isAfter(now.subtract(const Duration(hours: 1))) && t.isBefore(now.add(const Duration(hours: 36)));
    }).toList();
    final cur = w.current;
    final temp = (cur['temperature'] as num?)?.toDouble();
    final (label, icon) = cond(cur['icon']);
    final today = _days(w.hours).firstOrNull;

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Icon(icon, size: 64, color: iconColor(context, cur['icon'])),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(temp == null ? '–' : '${temp.round()}°', style: serif(context, 54, w: FontWeight.w600, h: 1.0)),
              Text(label, style: sans(context, 16, w: FontWeight.w500)),
              if (today != null)
                Text('Heute ${today.min.round()}° bis ${today.max.round()}°', style: sans(context, 13.5, color: muted(context))),
            ]),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Wrap(spacing: 18, runSpacing: 6, children: [
          _stat(context, Icons.air, '${((cur['wind_speed_10'] ?? cur['wind_speed_30'] ?? 0) as num).round()} km/h Wind'),
          _stat(context, Icons.water_drop_outlined, '${cur['relative_humidity'] ?? '–'} % Feuchte'),
          _stat(context, Icons.umbrella_outlined, '${((cur['precipitation_60'] ?? 0) as num).toStringAsFixed(1)} mm/h'),
        ]),
      ),
      for (final a in w.alerts) _AlertCard(a),
      const SectionLabel('Nächste 36 Stunden'),
      if (hours.length > 2) _HourlyChart(hours),
      const SectionLabel('Die nächsten Tage'),
      for (final d in _days(w.hours)) _DayRow(d, _days(w.hours)),
      Container(height: 1, color: cs.outlineVariant, margin: const EdgeInsets.symmetric(horizontal: 16)),
    ];
  }

  Widget _stat(BuildContext context, IconData i, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i, size: 16, color: muted(context)),
        const SizedBox(width: 5),
        Text(t, style: sans(context, 13.5, color: muted(context))),
      ]);
}

class _Day {
  final DateTime date;
  final double min, max, rain;
  final String? icon;
  _Day(this.date, this.min, this.max, this.rain, this.icon);
}

List<_Day> _days(List<Map> hours) {
  final by = <String, List<Map>>{};
  for (final h in hours) {
    by.putIfAbsent((h['timestamp'] as String).substring(0, 10), () => []).add(h);
  }
  final out = <_Day>[];
  for (final e in by.entries) {
    final temps = [for (final h in e.value) if (h['temperature'] != null) (h['temperature'] as num).toDouble()];
    if (temps.length < 12) continue;
    final icons = <String, int>{};
    for (final h in e.value) {
      final hr = int.parse((h['timestamp'] as String).substring(11, 13));
      if (hr >= 8 && hr <= 19 && h['icon'] != null) {
        final i = (h['icon'] as String).replaceAll('-night', '-day').replaceAll('clear-day', 'clear-day');
        icons[i] = (icons[i] ?? 0) + 1;
      }
    }
    String? icon = icons.isEmpty ? null : icons.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    final rain = e.value.fold<double>(0, (s, h) => s + ((h['precipitation'] ?? 0) as num).toDouble());
    if (rain > 3 && icon != 'thunderstorm' && icon != 'snow' && icon != 'sleet') icon = 'rain';
    out.add(_Day(DateTime.parse(e.key), temps.reduce(min), temps.reduce(max), rain, icon));
  }
  return out;
}

class _DayRow extends StatelessWidget {
  final _Day d;
  final List<_Day> all;
  const _DayRow(this.d, this.all);
  static const _wd = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

  @override
  Widget build(BuildContext context) {
    final lo = all.map((x) => x.min).reduce(min), hi = all.map((x) => x.max).reduce(max);
    final now = DateTime.now();
    final isToday = d.date.year == now.year && d.date.month == now.month && d.date.day == now.day;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(children: [
        SizedBox(
            width: 64,
            child: Text(isToday ? 'Heute' : '${_wd[d.date.weekday - 1]} ${d.date.day}.',
                style: sans(context, 14.5, w: FontWeight.w600))),
        Icon(cond(d.icon).$2, size: 22, color: iconColor(context, d.icon)),
        SizedBox(
          width: 58,
          child: Text(d.rain >= 0.1 ? '${d.rain.toStringAsFixed(1)} mm' : '',
              textAlign: TextAlign.right, style: sans(context, 12, color: const Color(0xFF2A84AE))),
        ),
        const SizedBox(width: 10),
        SizedBox(width: 30, child: Text('${d.min.round()}°', textAlign: TextAlign.right, style: sans(context, 14, color: muted(context)))),
        const SizedBox(width: 8),
        Expanded(
          child: LayoutBuilder(builder: (context, bc) {
            final span = max(1.0, hi - lo);
            final l = (d.min - lo) / span * bc.maxWidth, r = (d.max - lo) / span * bc.maxWidth;
            return Stack(children: [
              Container(height: 5, decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(3))),
              Positioned(
                left: l,
                width: max(6, r - l),
                child: Container(
                  height: 5,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    gradient: const LinearGradient(colors: [Color(0xFF4F9FCF), Color(0xFFE5A23A)]),
                  ),
                ),
              ),
            ]);
          }),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 30, child: Text('${d.max.round()}°', style: sans(context, 14, w: FontWeight.w600))),
      ]),
    );
  }
}

class _HourlyChart extends StatelessWidget {
  final List<Map> hours;
  const _HourlyChart(this.hours);
  static const colW = 54.0;

  @override
  Widget build(BuildContext context) {
    final temps = [for (final h in hours) ((h['temperature'] ?? 0) as num).toDouble()];
    final rain = [for (final h in hours) ((h['precipitation'] ?? 0) as num).toDouble()];
    final width = colW * hours.length;
    return SizedBox(
      height: 168,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          SizedBox(
            width: width,
            child: Column(children: [
              SizedBox(
                height: 92,
                child: CustomPaint(
                  size: Size(width, 92),
                  painter: _TempPainter(temps, rain, Theme.of(context).colorScheme.onSurface, muted(context)),
                ),
              ),
              Row(children: [
                for (final h in hours)
                  SizedBox(
                    width: colW,
                    child: Column(children: [
                      const SizedBox(height: 8),
                      Icon(cond(h['icon']).$2, size: 20, color: iconColor(context, h['icon'])),
                      const SizedBox(height: 6),
                      Text('${two(DateTime.parse(h['timestamp']).toLocal().hour)} Uhr',
                          style: sans(context, 11.5, color: muted(context))),
                    ]),
                  ),
              ]),
            ]),
          ),
        ],
      ),
    );
  }
}

class _TempPainter extends CustomPainter {
  final List<double> t, rain;
  final Color fg, mut;
  _TempPainter(this.t, this.rain, this.fg, this.mut);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width / t.length;
    final lo = t.reduce(min) - 1, hi = t.reduce(max) + 1;
    const top = 22.0, bottom = 18.0;
    final h = size.height - top - bottom;
    Offset at(int i) => Offset(w * i + w / 2, top + h - (t[i] - lo) / (hi - lo) * h);
    // Regenbalken
    final rp = Paint()..color = const Color(0xFF2A84AE).withValues(alpha: 0.35);
    for (var i = 0; i < rain.length; i++) {
      if (rain[i] <= 0.05) continue;
      final bh = min(rain[i] / 4, 1.0) * (size.height * 0.45);
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(w * i + w * 0.3, size.height - bh, w * 0.4, bh), const Radius.circular(2)), rp);
    }
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < t.length; i++) {
      final p0 = at(i - 1), p1 = at(i);
      final mx = (p0.dx + p1.dx) / 2;
      path.cubicTo(mx, p0.dy, mx, p1.dy, p1.dx, p1.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFFE5A23A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2);
    for (var i = 0; i < t.length; i++) {
      final o = at(i);
      canvas.drawCircle(o, 2.6, Paint()..color = const Color(0xFFE5A23A));
      final tp = TextPainter(
        text: TextSpan(text: '${t[i].round()}°', style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(o.dx - tp.width / 2, o.dy - 20));
    }
  }

  @override
  bool shouldRepaint(covariant _TempPainter old) => old.t != t;
}

class _AlertCard extends StatelessWidget {
  final Map a;
  const _AlertCard(this.a);
  @override
  Widget build(BuildContext context) {
    final sev = a['severity'];
    final color = switch (sev) {
      'extreme' => const Color(0xFF8E1B5A),
      'severe' => const Color(0xFFC62828),
      'moderate' => const Color(0xFFE07B00),
      _ => const Color(0xFFC9A400),
    };
    final exp = a['expires'] == null ? null : DateTime.tryParse(a['expires'])?.toLocal();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(Icons.warning_amber_rounded, color: color),
          title: Text(a['headline_de'] ?? a['event_de'] ?? 'Unwetterwarnung', style: sans(context, 14.5, w: FontWeight.w600)),
          subtitle: exp == null ? null : Text('gültig bis ${clock(exp)}', style: sans(context, 12, color: muted(context))),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          children: [
            Text(a['description_de'] ?? '', style: sans(context, 14, h: 1.5)),
            if ((a['instruction_de'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(a['instruction_de'], style: sans(context, 13, color: muted(context), h: 1.5)),
            ],
          ],
        ),
      ),
    );
  }
}

class _CityPicker extends StatefulWidget {
  const _CityPicker();
  @override
  State<_CityPicker> createState() => _CityPickerState();
}

class _CityPickerState extends State<_CityPicker> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    final list = cities.keys.where((c) => c.toLowerCase().contains(q.toLowerCase())).toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            autofocus: false,
            decoration: InputDecoration(
              hintText: 'Stadt suchen',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
            onChanged: (v) => setState(() => q = v),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) => ListTile(
              title: Text(list[i]),
              trailing: list[i] == app.weatherCity ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, list[i]),
            ),
          ),
        ),
      ]),
    );
  }
}
