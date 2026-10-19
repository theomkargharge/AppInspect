import 'package:flutter/cupertino.dart' show CupertinoPageTransition, CupertinoRouteTransitionMixin;
import 'package:flutter/material.dart';

/// Colors, shadows and code colors for the inspector, in its light and dark
/// themes. Read them with `AppInspectTokens.of(context)`.
@immutable
class AppInspectTokens extends ThemeExtension<AppInspectTokens> {
  const AppInspectTokens({
    required this.canvas,
    required this.surface,
    required this.surfaceAlt,
    required this.raised,
    required this.border,
    required this.text,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentSoft,
    required this.onAccent,
    required this.ok,
    required this.okSoft,
    required this.warn,
    required this.warnSoft,
    required this.err,
    required this.errSoft,
    required this.info,
    required this.infoSoft,
    required this.violet,
    required this.violetSoft,
    required this.shadow,
    required this.ink,
    required this.onInk,
    required this.jsonKey,
    required this.jsonString,
    required this.jsonNumber,
    required this.jsonLiteral,
    required this.codeBg,
  });

  /// The page behind cards.
  final Color canvas;

  /// Cards and sheets.
  final Color surface;

  /// Inputs, segmented controls and quiet fills.
  final Color surfaceAlt;

  /// The selected thumb of a segmented control or tab bar. It sits on
  /// [surfaceAlt] and must look lifted, not pressed in.
  final Color raised;

  /// Hairlines.
  final Color border;

  final Color text;
  final Color textSecondary;
  final Color textMuted;

  final Color accent;
  final Color accentSoft;
  final Color onAccent;

  final Color ok, okSoft, warn, warnSoft, err, errSoft, info, infoSoft, violet, violetSoft;

  /// Shadow tint for cards and the bubble.
  final Color shadow;

  /// Dark surface for toasts and terminal blocks, in both themes.
  final Color ink;
  final Color onInk;

  final Color jsonKey, jsonString, jsonNumber, jsonLiteral;

  /// Behind JSON.
  final Color codeBg;

  static const light = AppInspectTokens(
    canvas: Color(0xFFF4F5F8),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEFF1F5),
    raised: Color(0xFFFFFFFF),
    border: Color(0xFFE5E7ED),
    text: Color(0xFF0F172A),
    textSecondary: Color(0xFF475569),
    textMuted: Color(0xFF94A3B8),
    accent: Color(0xFF4F46E5),
    accentSoft: Color(0xFFEEEFFE),
    onAccent: Color(0xFFFFFFFF),
    ok: Color(0xFF15803D),
    okSoft: Color(0xFFE8F7EE),
    warn: Color(0xFFB45309),
    warnSoft: Color(0xFFFFF3DD),
    err: Color(0xFFDC2626),
    errSoft: Color(0xFFFEEDED),
    info: Color(0xFF2563EB),
    infoSoft: Color(0xFFE9F1FF),
    violet: Color(0xFF7C3AED),
    violetSoft: Color(0xFFF2ECFE),
    shadow: Color(0x170F172A),
    ink: Color(0xFF111827),
    onInk: Color(0xFFF8FAFC),
    jsonKey: Color(0xFF4338CA),
    jsonString: Color(0xFF047857),
    jsonNumber: Color(0xFFB45309),
    jsonLiteral: Color(0xFF7C3AED),
    codeBg: Color(0xFFF8F9FC),
  );

  static const dark = AppInspectTokens(
    canvas: Color(0xFF0B0F17),
    surface: Color(0xFF131A26),
    surfaceAlt: Color(0xFF1B2333),
    raised: Color(0xFF2B3548),
    border: Color(0xFF253043),
    text: Color(0xFFE8EDF6),
    textSecondary: Color(0xFFA4AFC3),
    textMuted: Color(0xFF6B778D),
    accent: Color(0xFF8C8DF9),
    accentSoft: Color(0xFF23264B),
    onAccent: Color(0xFF0B0F17),
    ok: Color(0xFF4ADE80),
    okSoft: Color(0xFF12301F),
    warn: Color(0xFFFBBF24),
    warnSoft: Color(0xFF3A2A0C),
    err: Color(0xFFF87171),
    errSoft: Color(0xFF3B1618),
    info: Color(0xFF60A5FA),
    infoSoft: Color(0xFF13253F),
    violet: Color(0xFFC4B5FD),
    violetSoft: Color(0xFF2A2148),
    shadow: Color(0x66000000),
    ink: Color(0xFF020617),
    onInk: Color(0xFFF8FAFC),
    jsonKey: Color(0xFFA5B4FC),
    jsonString: Color(0xFF6EE7B7),
    jsonNumber: Color(0xFFFCD34D),
    jsonLiteral: Color(0xFFC4B5FD),
    codeBg: Color(0xFF0F1522),
  );

  static AppInspectTokens of(BuildContext context) => Theme.of(context).extension<AppInspectTokens>() ?? light;

  /// A soft, layered shadow for cards.
  List<BoxShadow> get cardShadow => [
        BoxShadow(color: shadow, blurRadius: 18, offset: const Offset(0, 6), spreadRadius: -4),
        BoxShadow(color: shadow.withValues(alpha: shadow.a * 0.7), blurRadius: 2, offset: const Offset(0, 1)),
      ];

  /// A deeper shadow for things that float, such as the bubble and toasts.
  List<BoxShadow> get floatShadow => [
        BoxShadow(
            color: shadow.withValues(alpha: shadow.a * 2.2),
            blurRadius: 28,
            offset: const Offset(0, 12),
            spreadRadius: -6),
        BoxShadow(color: shadow, blurRadius: 6, offset: const Offset(0, 2)),
      ];

  /// The color of an HTTP method's label.
  (Color, Color) method(String method) => switch (method) {
        'GET' => (info, infoSoft),
        'POST' => (ok, okSoft),
        'PUT' || 'PATCH' => (warn, warnSoft),
        'DELETE' => (err, errSoft),
        _ => (violet, violetSoft),
      };

  @override
  AppInspectTokens copyWith() => this;

  @override
  AppInspectTokens lerp(AppInspectTokens? other, double t) => t < 0.5 || other == null ? this : other;
}

/// Monospace text for URLs, headers and JSON.
const TextStyle appInspectMono = TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: ['Menlo', 'SF Mono', 'Courier New', 'Courier'],
  fontSize: 12.5,
  height: 1.5,
);

/// Radii used across the inspector.
abstract final class AppInspectRadius {
  static const double card = 18;
  static const double control = 12;
  static const double pill = 999;
}

ThemeData buildAppInspectTheme({required bool dark}) {
  final t = dark ? AppInspectTokens.dark : AppInspectTokens.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: t.accent,
    brightness: dark ? Brightness.dark : Brightness.light,
  ).copyWith(
    primary: t.accent,
    onPrimary: t.onAccent,
    surface: t.surface,
    onSurface: t.text,
    surfaceContainerHighest: t.surfaceAlt,
    outline: t.border,
    outlineVariant: t.border,
    error: t.err,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: scheme.brightness);
  final textTheme = base.textTheme.apply(bodyColor: t.text, displayColor: t.text);
  // Button labels in the platform's font, like the rest of the inspector.
  final buttonText = TextStyle(
    fontFamily: textTheme.labelLarge?.fontFamily,
    fontFamilyFallback: textTheme.labelLarge?.fontFamilyFallback,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );
  return base.copyWith(
    scaffoldBackgroundColor: t.canvas,
    canvasColor: t.canvas,
    splashFactory: InkRipple.splashFactory,
    textTheme: textTheme,
    extensions: [t],
    dividerTheme: DividerThemeData(color: t.border, space: 1, thickness: 1),
    iconTheme: IconThemeData(color: t.textSecondary, size: 20),
    appBarTheme: AppBarTheme(
      backgroundColor: t.canvas,
      foregroundColor: t.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      hintStyle: TextStyle(color: t.textMuted, fontSize: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppInspectRadius.control),
        borderSide: BorderSide(color: t.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppInspectRadius.control),
        borderSide: BorderSide(color: t.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppInspectRadius.control),
        borderSide: BorderSide(color: t.accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppInspectRadius.control),
        borderSide: BorderSide(color: t.err),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.accent,
        foregroundColor: t.onAccent,
        minimumSize: const Size(0, 50),
        textStyle: buttonText,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.text,
        backgroundColor: t.surface,
        minimumSize: const Size(0, 50),
        side: BorderSide(color: t.border),
        textStyle: buttonText,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: t.accent, textStyle: const TextStyle(fontWeight: FontWeight.w600)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.onAccent : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.accent : null),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.accent : t.border),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: t.border,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: t.ink, borderRadius: BorderRadius.circular(8)),
      textStyle: TextStyle(color: t.onInk, fontSize: 12),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: t.accent),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _SlidePageTransitionsBuilder(),
        TargetPlatform.iOS: _SlidePageTransitionsBuilder(),
        TargetPlatform.macOS: _SlidePageTransitionsBuilder(),
      },
    ),
  );
}

/// The iOS slide transition. `CupertinoPageTransitionsBuilder` moved from
/// `material.dart` to `cupertino.dart` in newer Flutter releases, so this
/// rebuilds it from the parts both old and new releases export.
class _SlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const _SlidePageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 500);

  @override
  DelegatedTransitionBuilder? get delegatedTransition => CupertinoPageTransition.delegatedTransition;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return CupertinoRouteTransitionMixin.buildPageTransitions<T>(route, context, animation, secondaryAnimation, child);
  }
}
