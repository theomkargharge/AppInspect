// Stand-ins for the theme classes of the material_ui and cupertino_ui
// packages. They have the names and fields of Flutter's classes but are other
// classes, as the packages' are.
import 'package:flutter/material.dart' as flutter show ColorScheme;
import 'package:flutter/widgets.dart';

class AppBarTheme {
  const AppBarTheme({this.backgroundColor});

  final Color? backgroundColor;
}

class ThemeData {
  const ThemeData({
    required this.colorScheme,
    required this.primaryColor,
    this.appBarTheme = const AppBarTheme(),
    required this.scaffoldBackgroundColor,
  });

  // The package's ColorScheme has the same fields as Flutter's.
  final flutter.ColorScheme colorScheme;
  final Color primaryColor;
  final AppBarTheme appBarTheme;
  final Color scaffoldBackgroundColor;
}

class Theme extends StatelessWidget {
  const Theme({super.key, required this.data, required this.child});

  final ThemeData data;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class CupertinoDynamicColor extends Color {
  CupertinoDynamicColor(this.color, this.darkColor)
      : super.from(alpha: color.a, red: color.r, green: color.g, blue: color.b);

  final Color color;
  final Color darkColor;
}

class CupertinoThemeData {
  const CupertinoThemeData({
    this.brightness,
    required this.primaryColor,
    required this.primaryContrastingColor,
    required this.scaffoldBackgroundColor,
  });

  final Brightness? brightness;
  final Color primaryColor;
  final Color primaryContrastingColor;
  final Color scaffoldBackgroundColor;
}

class CupertinoTheme extends StatelessWidget {
  const CupertinoTheme({super.key, required this.data, required this.child});

  final CupertinoThemeData data;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
