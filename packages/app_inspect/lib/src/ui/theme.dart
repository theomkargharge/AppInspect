import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoPageTransition, CupertinoRouteTransitionMixin;
import 'package:flutter/material.dart';

/// Colors, shadows and code colors for the inspector: its own light and dark
/// themes, or ones made from the app's theme. Read them with
/// `AppInspectTokens.of(context)`.
@immutable
class AppInspectTokens extends ThemeExtension<AppInspectTokens> {
  const AppInspectTokens({
    required this.brightness,
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
    required this.accentAlt,
    required this.accentAltSoft,
    required this.ok,
    required this.okSoft,
    required this.warn,
    required this.warnSoft,
    required this.err,
    required this.errSoft,
    required this.onErr,
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

  /// Whether these are light or dark colors.
  final Brightness brightness;

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

  /// A second accent, for the Logs page and for actions next to [accent]
  /// ones. Violet in AppInspect's own themes, the app's primary color in one
  /// made from the app's theme. Text and icons on it use [onAccent].
  final Color accentAlt;
  final Color accentAltSoft;

  final Color ok, okSoft, warn, warnSoft, err, errSoft, info, infoSoft, violet, violetSoft;

  /// Text and icons on [err].
  final Color onErr;

  /// Shadow tint for cards and the bubble.
  final Color shadow;

  /// Dark surface for toasts and terminal blocks, in both themes.
  final Color ink;
  final Color onInk;

  final Color jsonKey, jsonString, jsonNumber, jsonLiteral;

  /// Behind JSON.
  final Color codeBg;

  static const light = AppInspectTokens(
    brightness: Brightness.light,
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
    accentAlt: Color(0xFF7C3AED),
    accentAltSoft: Color(0xFFF2ECFE),
    ok: Color(0xFF15803D),
    okSoft: Color(0xFFE8F7EE),
    warn: Color(0xFFB45309),
    warnSoft: Color(0xFFFFF3DD),
    err: Color(0xFFDC2626),
    errSoft: Color(0xFFFEEDED),
    onErr: Color(0xFFFFFFFF),
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
    brightness: Brightness.dark,
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
    accentAlt: Color(0xFFC4B5FD),
    accentAltSoft: Color(0xFF2A2148),
    ok: Color(0xFF4ADE80),
    okSoft: Color(0xFF12301F),
    warn: Color(0xFFFBBF24),
    warnSoft: Color(0xFF3A2A0C),
    err: Color(0xFFF87171),
    errSoft: Color(0xFF3B1618),
    onErr: Color(0xFF0B0F17),
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

  /// Tokens made from the app's color scheme, so the inspector looks like
  /// part of the app: its primary color, surfaces, text and outlines, light or
  /// dark. [background] is the app's page color, `scaffoldBackgroundColor`.
  ///
  /// Status colors, such as red for a failed call or violet for a repeated
  /// one, stay AppInspect's own, so they read the same in every app.
  factory AppInspectTokens.fromScheme(ColorScheme scheme, {Color? background}) {
    final s = scheme;
    final dark = s.brightness == Brightness.dark;
    final base = dark ? AppInspectTokens.dark : AppInspectTokens.light;
    Color mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

    // Whether a color can be a surface here: light in a light scheme, dark in
    // a dark one. Some themes put a brand color in `surface`, such as a navy
    // in a light theme, and cards can't take that.
    bool fits(Color color) {
      final lum = color.computeLuminance();
      return color.a == 1 && (dark ? lum < 0.2 : lum > 0.5);
    }

    // Schemes from ColorScheme.fromSeed, and Material 3's default, have a
    // range of surface containers. Older schemes leave them all the same, so
    // AppInspect shades a surface itself.
    final tiered = s.surfaceContainerLowest != s.surfaceContainerHighest &&
        fits(s.surfaceContainerLowest) &&
        fits(s.surfaceContainerHighest);
    final paper =
        [s.surface, s.surfaceContainerLowest, s.surfaceContainerHighest].firstWhere(fits, orElse: () => base.surface);
    // Cards are the lightest surface in a light theme, as in AppInspect's own.
    final surface = tiered
        ? (dark ? s.surfaceContainerLow : s.surfaceContainerLowest)
        : (dark ? mix(paper, s.onSurface, 0.05) : paper);
    var canvas = tiered
        ? (dark ? s.surfaceContainerLowest : s.surfaceContainerLow)
        : (dark ? mix(paper, const Color(0xFF000000), 0.35) : mix(paper, s.onSurface, 0.045));
    // An app that picked its own page color gets it behind the cards too, as
    // long as it suits the brightness and the cards still stand out.
    if (background != null && background != s.surface && fits(background)) {
      if ((background.computeLuminance() - surface.computeLuminance()).abs() > 0.004) canvas = background;
    }
    final surfaceAlt = tiered ? s.surfaceContainer : mix(surface, s.onSurface, dark ? 0.07 : 0.06);
    final raised = dark ? (tiered ? s.surfaceContainerHighest : mix(surface, s.onSurface, 0.14)) : surface;
    // Roles a scheme doesn't set fall back to others, such as onBackground,
    // which is white in a light scheme made with ColorScheme.fromSwatch. So a
    // role is used only when its contrast on the cards suits its job.
    final textContrast = _contrast(s.onSurface, surface);
    bool suits(Color role, double min, double max) {
      final c = _contrast(role, surface);
      return role != s.onSurface && c >= min && c < max;
    }

    final border = suits(s.outlineVariant, 1.15, 3.5)
        ? mix(s.outlineVariant, surface, dark ? 0.45 : 0.55)
        : mix(s.onSurface, surface, dark ? 0.86 : 0.9);
    final textSecondary =
        suits(s.onSurfaceVariant, 4.5, textContrast) ? s.onSurfaceVariant : mix(s.onSurface, surface, 0.3);
    final textMuted = suits(s.outline, 2.5, textContrast) ? s.outline : mix(s.onSurface, surface, 0.5);
    final accentSoft = mix(surface, s.primary, dark ? 0.16 : 0.1);

    return AppInspectTokens(
      brightness: s.brightness,
      canvas: canvas,
      surface: surface,
      surfaceAlt: surfaceAlt,
      raised: raised,
      border: border,
      text: s.onSurface,
      textSecondary: textSecondary,
      textMuted: textMuted,
      accent: s.primary,
      accentSoft: accentSoft,
      onAccent: s.onPrimary,
      accentAlt: s.primary,
      accentAltSoft: accentSoft,
      ok: base.ok,
      okSoft: base.okSoft,
      warn: base.warn,
      warnSoft: base.warnSoft,
      err: base.err,
      errSoft: base.errSoft,
      onErr: base.onErr,
      info: base.info,
      infoSoft: base.infoSoft,
      violet: base.violet,
      violetSoft: base.violetSoft,
      shadow: base.shadow,
      ink: base.ink,
      onInk: base.onInk,
      jsonKey: base.jsonKey,
      jsonString: base.jsonString,
      jsonNumber: base.jsonNumber,
      jsonLiteral: base.jsonLiteral,
      codeBg: mix(surface, canvas, 0.5),
    );
  }

  /// The WCAG contrast ratio of two colors, from 1 to 21.
  static double _contrast(Color a, Color b) {
    final x = a.computeLuminance();
    final y = b.computeLuminance();
    return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
  }

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

/// The inspector's Material theme, from [t]. Material widgets the tokens don't
/// cover build on [scheme], the app's color scheme when [t] comes from it.
ThemeData buildAppInspectTheme(AppInspectTokens t, {ColorScheme? scheme}) {
  final colors = (scheme ?? ColorScheme.fromSeed(seedColor: t.accent, brightness: t.brightness)).copyWith(
    primary: t.accent,
    onPrimary: t.onAccent,
    surface: t.surface,
    onSurface: t.text,
    surfaceContainerHighest: t.surfaceAlt,
    outline: t.border,
    outlineVariant: t.border,
    error: t.err,
    onError: t.onErr,
  );
  final base = ThemeData(colorScheme: colors, useMaterial3: true, brightness: colors.brightness);
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
