import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../data.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'home.dart';



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
  final List<(DateTime, double)> radar; // mm pro Stunde
  final String region;
  _Wx(this.current, this.hours, this.alerts, this.radar, this.region);
}

Future<_Wx> _load(Place p) async {
  final now = DateTime.now();
  String d(DateTime t) => '${t.year}-${two(t.month)}-${two(t.day)}';
  Future<Map> get(String path, Map<String, String> q) async {
    final r = await http
        .get(Uri.https('api.brightsky.dev', path, {'lat': '${p.lat}', 'lon': '${p.lon}', ...q}))
        .timeout(const Duration(seconds: 15));
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  final res = await Future.wait([
    get('/current_weather', {'tz': 'Europe/Berlin'}),
    get('/weather', {'date': d(now), 'last_date': d(now.add(const Duration(days: 9))), 'tz': 'Europe/Berlin'}),
    get('/alerts', {'tz': 'Europe/Berlin'}).catchError((_) => <String, dynamic>{}),
    get('/radar', {'distance': '0', 'format': 'plain', 'tz': 'Europe/Berlin'}).catchError((_) => <String, dynamic>{}),
  ]);
  final radar = <(DateTime, double)>[];
  for (final r in (res[3]['radar'] ?? const [])) {
    try {
      final v = (r['precipitation_5'][0][0] as num).toDouble() / 100 * 12; // 0,01 mm / 5 min -> mm/h
      radar.add((DateTime.parse(r['timestamp']).toLocal(), v));
    } catch (_) {}
  }
  final loc = res[2]['location'];
  return _Wx(
    Map.from(res[0]['weather'] ?? {}),
    [for (final h in (res[1]['weather'] ?? const [])) Map.from(h)],
    [for (final a in (res[2]['alerts'] ?? const [])) Map.from(a)],
    radar,
    loc == null ? '' : '${loc['name'] ?? ''}${loc['district'] != null ? ', ${loc['district']}' : ''}',
  );
}

class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});
  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  late Future<_Wx> fut = _load(app.place);

  void _reload() => setState(() => fut = _load(app.place));

  Future<void> _pickCity() async {
    final p = await showModalBottomSheet<Place>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _PlacePicker(),
    );
    if (p != null) {
      app.setPlace(p);
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
          await fut.catchError((_) => _Wx({}, [], [], [], ''));
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
                      label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 200),
                        child: Text(app.place.name, overflow: TextOverflow.ellipsis),
                      ),
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
      if (w.region.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text('Warnregion: ${w.region}', style: sans(context, 12, color: muted(context))),
        ),
      for (final a in w.alerts) _AlertCard(a),
      if (w.radar.length > 3) _Nowcast(w.radar),
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

class _PlacePicker extends StatefulWidget {
  const _PlacePicker();
  @override
  State<_PlacePicker> createState() => _PlacePickerState();
}

class _PlacePickerState extends State<_PlacePicker> {
  List<Place> results = [];
  bool locating = false;
  String? gpsError;
  int _q = 0;

  Future<void> _search(String q) async {
    final n = ++_q;
    final r = await app.searchPlaces(q);
    if (mounted && n == _q) setState(() => results = r);
  }

  Future<void> _gps() async {
    setState(() {
      locating = true;
      gpsError = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) throw 'Standortdienst ist ausgeschaltet.';
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw 'Kein Zugriff auf den Standort erlaubt.';
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 15)));
      final p = await app.nearestPlace(pos.latitude, pos.longitude);
      if (mounted) Navigator.pop(context, p);
    } catch (e) {
      if (mounted) {
        setState(() {
          locating = false;
          gpsError = e is String ? e : 'Standort konnte nicht ermittelt werden.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget tile(Place p, {IconData icon = Icons.place_outlined}) => ListTile(
          leading: Icon(icon, color: muted(context)),
          title: Text(p.name, style: sans(context, 15, w: FontWeight.w600)),
          subtitle: Text('${p.plz.isEmpty ? '' : '${p.plz} · '}${p.state}', style: sans(context, 12.5, color: muted(context))),
          trailing: p.label == app.place.label ? Icon(Icons.check, color: cs.primary) : null,
          onTap: () => Navigator.pop(context, p),
        );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text('Ort wählen', style: serif(context, 21, w: FontWeight.w700)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Ort oder Postleitzahl',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: cs.surfaceContainer,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onChanged: _search,
            ),
          ),
          const SizedBox(height: 6),
          ListTile(
            leading: locating
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.my_location, color: cs.primary),
            title: Text('Aktuellen Standort verwenden', style: sans(context, 15, w: FontWeight.w600, color: cs.primary)),
            subtitle: gpsError == null ? null : Text(gpsError!, style: sans(context, 12.5, color: breaking)),
            onTap: locating ? null : _gps,
          ),
          const Divider(),
          Expanded(
            child: ListView(children: [
              if (results.isEmpty && app.recentPlaces.isNotEmpty) ...[
                const SectionLabel('Zuletzt verwendet'),
                for (final p in app.recentPlaces) tile(p, icon: Icons.history),
              ],
              for (final p in results) tile(p),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Regenradar-Vorhersage für die nächsten zwei Stunden am gewählten Ort.
class _Nowcast extends StatelessWidget {
  final List<(DateTime, double)> radar;
  const _Nowcast(this.radar);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final future = radar.where((r) => r.$1.isAfter(now.subtract(const Duration(minutes: 5)))).toList();
    if (future.length < 3) return const SizedBox();
    final wet = [for (final r in future) r.$2 >= 0.1];
    final rainNow = wet.first;
    final firstRain = future.where((r) => r.$2 >= 0.1).firstOrNull;
    final lastRainIdx = wet.lastIndexOf(true);
    final peak = future.map((r) => r.$2).fold<double>(0, max);
    final kind = peak < 1 ? 'Leichter Regen' : (peak < 4 ? 'Regen' : 'Starker Regen');
    String hm(DateTime t) => '${two(t.hour)}:${two(t.minute)}';
    final String text;
    if (firstRain == null) {
      text = 'Kein Niederschlag in den nächsten zwei Stunden';
    } else if (rainNow && wet.every((x) => x)) {
      text = '$kind hält an';
    } else if (rainNow && !wet.sublist(wet.indexOf(false)).contains(true)) {
      text = '$kind endet voraussichtlich gegen ${hm(future[wet.indexOf(false)].$1)} Uhr';
    } else if (!rainNow && wet.sublist(wet.indexOf(true)).every((x) => x)) {
      text = '$kind ab etwa ${hm(firstRain.$1)} Uhr';
    } else {
      text = 'Zeitweise ${kind.replaceFirst('L', 'l').replaceFirst('S', 's')} bis etwa ${hm(future[lastRainIdx].$1)} Uhr';
    }
    final maxV = future.map((r) => r.$2).fold<double>(1.0, max);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.radar, size: 18, color: const Color(0xFF2A84AE)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: sans(context, 14, w: FontWeight.w600))),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          height: 44,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final r in future)
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  height: r.$2 < 0.05 ? 2 : 4 + 40 * min(1.0, r.$2 / maxV),
                  decoration: BoxDecoration(
                    color: r.$2 < 0.05 ? cs.outlineVariant : const Color(0xFF2A84AE),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 4),
        Row(children: [
          Text('jetzt', style: sans(context, 11, color: muted(context))),
          const Spacer(),
          Text('+1 Std.', style: sans(context, 11, color: muted(context))),
          const Spacer(),
          Text('${two(future.last.$1.hour)}:${two(future.last.$1.minute)}', style: sans(context, 11, color: muted(context))),
        ]),
      ]),
    );
  }
}
