import 'dart:ui' as ui;

import '../app_inspect.dart';
import '../config.dart';
import '../schedule.dart';
import 'cupertino.dart';
import 'material.dart';
import 'theme.dart';

/// The inspector's colors, and the color scheme its Material widgets build on
/// when the colors come from the app.
typedef AppInspectLook = ({AppInspectTokens tokens, ColorScheme? scheme});

/// The look for the theme picked in Settings or in `AppInspectConfig`.
AppInspectLook currentAppInspectLook() => switch (AppInspect.themeMode.value) {
      AppInspectThemeMode.light => (tokens: AppInspectTokens.light, scheme: null),
      AppInspectThemeMode.dark => (tokens: AppInspectTokens.dark, scheme: null),
      // An app without a theme AppInspect can find gets the light theme.
      AppInspectThemeMode.app => AppInspectAppTheme.look.value ?? (tokens: AppInspectTokens.light, scheme: null),
    };

/// Notifies when [currentAppInspectLook] may have changed.
final Listenable appInspectLookChanges = Listenable.merge([AppInspect.themeMode, AppInspectAppTheme.look]);

/// Follows the app's own theme, for [AppInspectThemeMode.app].
///
/// AppInspect sits above the app's MaterialApp, so it can't depend on the
/// app's Theme the usual way. It finds the Theme the app builds above its
/// navigator once, and after each frame checks whether the theme changed.
/// When nothing changed that's one comparison, so it costs nothing worth
/// measuring. A change, such as the app switching to dark mode, shows in the
/// bubble and the inspector on the next frame.
abstract final class AppInspectAppTheme {
  /// The app's theme as an inspector look, or null until AppInspect finds one.
  static final ValueNotifier<AppInspectLook?> look = ValueNotifier<AppInspectLook?>(null);

  static bool _installed = false;

  /// The Theme or CupertinoTheme element the app's theme comes from.
  static Element? _source;

  /// What [_source] held when last read, to tell when it changes.
  static Object? _lastData;
  static Brightness? _lastPlatformBrightness;
  static (ColorScheme, Color?)? _lastColors;

  /// Frames to wait before looking for a theme again, after a search of a
  /// big tree found none.
  static int _skipFrames = 0;

  /// Starts following the app's theme. Safe to call more than once.
  static void install() {
    if (_installed) return;
    _installed = true;
    // Runs after Flutter has built, laid out and painted each frame, so the
    // app's widgets are up to date and the tree can be read.
    WidgetsFlutterBinding.ensureInitialized().addPersistentFrameCallback((_) => _check());
    AppInspect.themeMode.addListener(() {
      // Switching to the app's theme shouldn't wait for the next frame.
      _skipFrames = 0;
      runWhenSafe(_check);
    });
  }

  static void _check() {
    if (AppInspect.themeMode.value != AppInspectThemeMode.app) return;
    try {
      var source = _source;
      if (source == null || !source.mounted) {
        _source = source = null;
        if (_skipFrames > 0) {
          _skipFrames--;
          return;
        }
        final root = appInspectAppKey.currentContext;
        if (root is! Element) return;
        final (theme, visited) = _findTheme(root);
        source = _source = theme;
        if (source == null) {
          // No theme yet, such as on a splash screen before the app builds
          // its MaterialApp, so look again next frame. That's cheap for a
          // small tree. A big one without a theme likely never gets one.
          if (visited > 1000) _skipFrames = 30;
          _lastData = null;
          _publish(null);
          return;
        }
      }
      final widget = source.widget;
      final Object? data = switch (widget) {
        Theme(:final data) => data,
        CupertinoTheme(:final data) => data,
        // A theme from the material_ui or cupertino_ui package.
        _ => (widget as dynamic).data,
      };
      // A Cupertino theme without a brightness follows the platform's.
      final platformBrightness = ui.PlatformDispatcher.instance.platformBrightness;
      if (identical(data, _lastData) && platformBrightness == _lastPlatformBrightness) return;
      _lastData = data;
      _lastPlatformBrightness = platformBrightness;
      _publish(switch (data) {
        ThemeData() => (_materialScheme(data), data.scaffoldBackgroundColor),
        CupertinoThemeData() => _cupertinoColors(data, platformBrightness),
        null => null,
        _ when _isPackageTheme(widget, _materialThemeName) => _packageMaterialColors(data),
        _ => _packageCupertinoColors(data, platformBrightness),
      });
    } catch (_) {
      // Following the app's theme must never break the app's frame.
    }
  }

  /// Makes the look for [colors], unless it's the one showing already. An app
  /// that rebuilds its MaterialApp makes a new ThemeData with the same colors.
  static void _publish((ColorScheme, Color?)? colors) {
    if (colors == _lastColors) return;
    _lastColors = colors;
    final next = colors == null
        ? null
        : (tokens: AppInspectTokens.fromScheme(colors.$1, background: colors.$2), scheme: colors.$1);
    // Changing the look rebuilds the bubble, which waits for the frame to end.
    runWhenSafe(() => look.value = next);
  }

  /// The names of the Theme and CupertinoTheme classes. From Flutter 3.47,
  /// apps can build their theme with the material_ui and cupertino_ui
  /// packages instead of the framework's libraries. Their classes are other
  /// classes with the same names and fields, so AppInspect knows them by name
  /// and reads their colors by name. In a build made with `--obfuscate` the
  /// names are scrambled, and AppInspect uses its own light theme for them.
  static const String _materialThemeName = 'Theme';
  static const String _cupertinoThemeName = 'CupertinoTheme';

  /// Whether [widget] is the Theme or CupertinoTheme of one of those packages.
  static bool _isPackageTheme(Widget widget, String name) => widget.runtimeType.toString() == name;

  static bool _isMaterialTheme(Widget? widget) =>
      widget is Theme || (widget != null && _isPackageTheme(widget, _materialThemeName));

  static bool _isCupertinoTheme(Widget widget) =>
      widget is CupertinoTheme || _isPackageTheme(widget, _cupertinoThemeName);

  /// The app's theme: the deepest Theme above its navigator, which is the one
  /// MaterialApp builds, or one the app adds around all its screens. Themes
  /// below the navigator belong to single screens. A CupertinoApp has a
  /// CupertinoTheme instead.
  ///
  /// Also returns how many elements it looked at.
  static (Element?, int) _findTheme(Element root) {
    Element? found;
    Element? firstTheme;
    var visited = 0;
    var done = false;
    void visit(Element element, Element? theme) {
      if (done || visited++ >= 3000) return;
      final widget = element.widget;
      // A Material Theme has a CupertinoTheme below it, built from its colors.
      if (_isMaterialTheme(widget) || (_isCupertinoTheme(widget) && !_isMaterialTheme(theme?.widget))) {
        theme = element;
        firstTheme ??= element;
      }
      if (widget is Navigator || widget is Router) {
        found = theme;
        done = true;
        return;
      }
      element.visitChildElements((child) => visit(child, theme));
    }

    visit(root, null);
    // No navigator, such as an app that is a single widget: its first theme.
    return (found ?? firstTheme, visited);
  }

  /// The app's color scheme, with its main color as `primary`.
  ///
  /// That's `colorScheme.primary`, unless the theme leaves it at one of
  /// Flutter's defaults, such as a theme made with `ColorScheme.fromSwatch()`.
  /// Those themes usually keep the app's color in `primaryColor` or the app
  /// bar's color instead, so AppInspect takes it from there.
  static ColorScheme _materialScheme(ThemeData theme) =>
      _brandScheme(theme.colorScheme, [theme.primaryColor, theme.appBarTheme.backgroundColor]);

  /// [scheme], with its primary color taken from [candidates] when [scheme]
  /// leaves it at one of Flutter's defaults.
  static ColorScheme _brandScheme(ColorScheme scheme, List<Color?> candidates) {
    if (!_defaultPrimaries.contains(scheme.primary)) return scheme;
    for (final color in candidates) {
      if (color != null && color != scheme.primary && _isBrandColor(color)) {
        final onColor = ThemeData.estimateBrightnessForColor(color) == Brightness.dark
            ? const Color(0xFFFFFFFF)
            : const Color(0xFF000000);
        return scheme.copyWith(primary: color, onPrimary: onColor);
      }
    }
    return scheme;
  }

  /// The primary colors Flutter picks when a theme doesn't pick one.
  static final Set<Color> _defaultPrimaries = {
    for (final brightness in Brightness.values) ...[
      ThemeData(useMaterial3: true, brightness: brightness).colorScheme.primary,
      ThemeData(useMaterial3: false, brightness: brightness).colorScheme.primary,
      ColorScheme.fromSwatch(brightness: brightness).primary,
    ],
    const ColorScheme.light().primary,
    const ColorScheme.dark().primary,
  };

  /// A color that can stand for an app: opaque and colorful, not white, black
  /// or gray.
  static bool _isBrandColor(Color color) {
    final hsv = HSVColor.fromColor(color);
    return color.a == 1 && hsv.saturation > 0.3 && hsv.value > 0.2;
  }

  static (ColorScheme, Color?) _cupertinoColors(CupertinoThemeData data, Brightness platformBrightness) =>
      _cupertinoScheme(
        brightness: data.brightness ?? platformBrightness,
        primary: data.primaryColor,
        onPrimary: data.primaryContrastingColor,
        background: data.scaffoldBackgroundColor,
      );

  static (ColorScheme, Color?) _cupertinoScheme({
    required Brightness brightness,
    required Color primary,
    required Color onPrimary,
    required Color background,
  }) {
    final dark = brightness == Brightness.dark;
    Color resolve(Color color) {
      if (color is CupertinoDynamicColor) return dark ? color.darkColor : color.color;
      // cupertino_ui's CupertinoDynamicColor.
      if (color.runtimeType.toString() == 'CupertinoDynamicColor') {
        final dynamic dynamicColor = color;
        return (dark ? dynamicColor.darkColor : dynamicColor.color) as Color;
      }
      return color;
    }

    final seed = resolve(primary);
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness)
        .copyWith(primary: seed, onPrimary: resolve(onPrimary));
    return (scheme, resolve(background));
  }

  /// The colors of a ThemeData from the material_ui package, read by name.
  static (ColorScheme, Color?) _packageMaterialColors(dynamic theme) {
    final dynamic s = theme.colorScheme;
    final scheme = ColorScheme(
      brightness: s.brightness as Brightness,
      primary: s.primary as Color,
      onPrimary: s.onPrimary as Color,
      secondary: s.secondary as Color,
      onSecondary: s.onSecondary as Color,
      error: s.error as Color,
      onError: s.onError as Color,
      surface: s.surface as Color,
      onSurface: s.onSurface as Color,
      onSurfaceVariant: s.onSurfaceVariant as Color,
      outline: s.outline as Color,
      outlineVariant: s.outlineVariant as Color,
      surfaceContainerLowest: s.surfaceContainerLowest as Color,
      surfaceContainerLow: s.surfaceContainerLow as Color,
      surfaceContainer: s.surfaceContainer as Color,
      surfaceContainerHigh: s.surfaceContainerHigh as Color,
      surfaceContainerHighest: s.surfaceContainerHighest as Color,
    );
    return (
      _brandScheme(scheme, [theme.primaryColor as Color?, theme.appBarTheme.backgroundColor as Color?]),
      theme.scaffoldBackgroundColor as Color?,
    );
  }

  /// The colors of a CupertinoThemeData from the cupertino_ui package, read
  /// by name.
  static (ColorScheme, Color?) _packageCupertinoColors(dynamic data, Brightness platformBrightness) => _cupertinoScheme(
        brightness: data.brightness as Brightness? ?? platformBrightness,
        primary: data.primaryColor as Color,
        onPrimary: data.primaryContrastingColor as Color,
        background: data.scaffoldBackgroundColor as Color,
      );

  /// Forgets the app's theme, for tests that start a new app.
  @visibleForTesting
  static void debugReset() {
    _source = null;
    _lastData = null;
    _lastPlatformBrightness = null;
    _lastColors = null;
    _skipFrames = 0;
    look.value = null;
  }
}
