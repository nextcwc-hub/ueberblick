import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class Cat {
  final String id;
  final String name;
  final Color color;
  final IconData icon;
  const Cat(this.id, this.name, this.color, this.icon);
}

const cats = <Cat>[
  Cat('inland', 'Inland', Color(0xFF2E5C8A), Icons.account_balance_outlined),
  Cat('ausland', 'Ausland', Color(0xFF2F7468), Icons.public),
  Cat('wirtschaft', 'Wirtschaft', Color(0xFF8A5A2E), Icons.factory_outlined),
  Cat('boerse', 'Börse', Color(0xFF2F7D4F), Icons.show_chart),
  Cat('wissen', 'Wissen', Color(0xFF6B4FA0), Icons.science_outlined),
  Cat('digital', 'Digital', Color(0xFF3F5F8C), Icons.memory),
  Cat('investigativ', 'Investigativ', Color(0xFF9E3B3B), Icons.manage_search),
  Cat('sport', 'Sport', Color(0xFFB85A26), Icons.sports_soccer),
  Cat('wetter', 'Wetter', Color(0xFF2A84AE), Icons.wb_cloudy_outlined),
];

Cat catOf(String id) => cats.firstWhere((c) => c.id == id, orElse: () => cats.first);

const brand = Color(0xFF0E2A47);
const breaking = Color(0xFFC62828);
const up = Color(0xFF1E7A46);
const down = Color(0xFFB3261E);

TextStyle serif(BuildContext c, double size, {FontWeight w = FontWeight.w600, Color? color, double h = 1.22}) =>
    GoogleFonts.sourceSerif4(
        fontSize: size, fontWeight: w, height: h, color: color ?? Theme.of(c).colorScheme.onSurface, letterSpacing: -0.2);

TextStyle sans(BuildContext c, double size,
        {FontWeight w = FontWeight.w400, Color? color, double h = 1.4, double ls = 0}) =>
    GoogleFonts.inter(
        fontSize: size, fontWeight: w, height: h, letterSpacing: ls, color: color ?? Theme.of(c).colorScheme.onSurface);

Color muted(BuildContext c) => Theme.of(c).colorScheme.onSurfaceVariant;
Color line(BuildContext c) => Theme.of(c).colorScheme.outlineVariant;

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme(
    brightness: b,
    primary: dark ? const Color(0xFF9DBBE0) : brand,
    onPrimary: dark ? const Color(0xFF0B1A2C) : Colors.white,
    secondary: dark ? const Color(0xFF9DBBE0) : brand,
    onSecondary: dark ? const Color(0xFF0B1A2C) : Colors.white,
    error: breaking,
    onError: Colors.white,
    surface: dark ? const Color(0xFF121416) : const Color(0xFFF7F6F3),
    onSurface: dark ? const Color(0xFFE9EAEC) : const Color(0xFF15181C),
    onSurfaceVariant: dark ? const Color(0xFF9AA1AA) : const Color(0xFF5E6772),
    surfaceContainerLowest: dark ? const Color(0xFF0D0F11) : Colors.white,
    surfaceContainerLow: dark ? const Color(0xFF181B1E) : Colors.white,
    surfaceContainer: dark ? const Color(0xFF1D2024) : const Color(0xFFEFEDE8),
    surfaceContainerHigh: dark ? const Color(0xFF24282C) : const Color(0xFFE8E6E0),
    outline: dark ? const Color(0xFF3A3F45) : const Color(0xFFCFCCC4),
    outlineVariant: dark ? const Color(0xFF2A2E33) : const Color(0xFFE2DFD8),
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: b);
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: GoogleFonts.interTextTheme(base.textTheme),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primary.withValues(alpha: 0.12),
      height: 64,
      labelTextStyle: WidgetStatePropertyAll(GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w500)),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
    splashFactory: InkSparkle.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
    }),
  );
}
