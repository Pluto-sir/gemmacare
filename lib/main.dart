import 'package:flutter/material.dart';

import 'ui/health_dashboard.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GemmaCareApp());
}

/// Larger tap targets and type for older adults; calm, high-contrast palette.
final ThemeData kGemmaCareTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF0D47A1),
    brightness: Brightness.light,
    primary: const Color(0xFF0D47A1),
    onPrimary: Colors.white,
    surface: const Color(0xFFF7F9FC),
    onSurface: const Color(0xFF1A1A1A),
  ),
  scaffoldBackgroundColor: const Color(0xFFF0F4FA),
  visualDensity: VisualDensity.standard,
  materialTapTargetSize: MaterialTapTargetSize.padded,
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(double.infinity, 56),
      textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(double.infinity, 56),
      textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  ),
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      fontSize: 34,
      fontWeight: FontWeight.bold,
      height: 1.15,
      color: Color(0xFF1A1A1A),
    ),
    titleLarge: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      height: 1.2,
      color: Color(0xFF1A1A1A),
    ),
    titleMedium: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: Color(0xFF1A1A1A),
    ),
    bodyLarge: TextStyle(
      fontSize: 19,
      height: 1.35,
      color: Color(0xFF2C2C2C),
    ),
    bodyMedium: TextStyle(
      fontSize: 17,
      height: 1.35,
      color: Color(0xFF2C2C2C),
    ),
    labelLarge: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
    ),
  ),
  appBarTheme: const AppBarTheme(
    centerTitle: true,
    elevation: 0,
    scrolledUnderElevation: 0,
    titleTextStyle: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: Color(0xFF1A1A1A),
    ),
    backgroundColor: Color(0xFFF0F4FA),
    foregroundColor: Color(0xFF1A1A1A),
  ),
  cardTheme: CardThemeData(
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    color: Colors.white,
    margin: EdgeInsets.zero,
  ),
  sliderTheme: const SliderThemeData(
    trackHeight: 6,
    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 14),
    overlayShape: RoundSliderOverlayShape(overlayRadius: 22),
  ),
);

class GemmaCareApp extends StatelessWidget {
  const GemmaCareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Gemma Care',
      theme: kGemmaCareTheme,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(
              media.textScaler.scale(1.0).clamp(1.0, 1.25),
            ),
          ),
          child: child!,
        );
      },
      home: const HealthDashboard(),
    );
  }
}
