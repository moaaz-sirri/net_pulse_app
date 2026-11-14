import 'package:flutter/material.dart';

ThemeData netPulseTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  const blue = Color(0xff0061fe);
  const cream = Color(0xfff7f5f2);
  final canvas = dark ? Colors.black : cream;
  final ink = dark ? cream : const Color(0xff1e1919);
  final muted = dark ? const Color(0xffbbb7b3) : const Color(0xff524a3e);
  final line = dark ? const Color(0xff55585e) : const Color(0xffd3cec9);
  final colors = ColorScheme.fromSeed(seedColor: blue, brightness: brightness)
      .copyWith(
        primary: blue,
        onPrimary: Colors.white,
        surface: canvas,
        onSurface: ink,
        onSurfaceVariant: muted,
        surfaceContainer: dark
            ? const Color(0xff292c31)
            : const Color(0xffeee9e2),
        outlineVariant: line,
      );

  return ThemeData(
    colorScheme: colors,
    scaffoldBackgroundColor: canvas,
    appBarTheme: AppBarTheme(
      backgroundColor: canvas,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 36,
        height: 1.12,
        fontWeight: FontWeight.w500,
      ),
      titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
      bodyMedium: TextStyle(fontSize: 15, height: 1.45),
    ).apply(bodyColor: ink, displayColor: ink),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return null;
          return states.contains(WidgetState.pressed)
              ? const Color(0xff0044af)
              : blue;
        }),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        foregroundColor: ink,
        side: BorderSide(color: line),
        shape: const StadiumBorder(),
      ),
    ),
  );
}
