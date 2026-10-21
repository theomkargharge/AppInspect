import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_inspect/app_inspect.dart';
import 'package:app_inspect/src/ui/app_theme.dart';
import 'package:app_inspect/src/ui/theme.dart';

import 'helpers.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Home')));
}

/// An app that switches between its light and dark theme, like one with a
/// dark mode setting.
class SwitchingApp extends StatelessWidget {
  const SwitchingApp({super.key, required this.mode, required this.light, required this.dark});

  final ValueNotifier<ThemeMode> mode;
  final ThemeData light;
  final ThemeData dark;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
        valueListenable: mode,
        builder: (context, mode, _) => MaterialApp(
          theme: light,
          darkTheme: dark,
          themeMode: mode,
          navigatorObservers: [AppInspect.navigatorObserver],
          home: const HomeScreen(),
        ),
      );
}

/// The inspector's tokens, read inside the open inspector.
AppInspectTokens inspectorTokens(WidgetTester tester) =>
    Theme.of(tester.element(find.byKey(const ValueKey('app_inspect_tab_network')))).extension<AppInspectTokens>()!;

/// The bubble's circle.
BoxDecoration bubble(WidgetTester tester) => tester
    .widget<AnimatedContainer>(
      find.ancestor(of: find.byIcon(Icons.manage_search_rounded), matching: find.byType(AnimatedContainer)).first,
    )
    .decoration! as BoxDecoration;

Color ring(WidgetTester tester) => (bubble(tester).border! as Border).top.color;

Future<void> openInspector(WidgetTester tester) async {
  AppInspect.open();
  await tester.pumpAndSettle();
}

Future<void> closeInspector(WidgetTester tester) async {
  AppInspect.close();
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    resetAppInspect();
    AppInspectAppTheme.debugReset();
  });

  testWidgets('the inspector and the bubble take the app\'s colors', (tester) async {
    final theme = ThemeData(colorSchemeSeed: Colors.teal);
    await tester.pumpWidget(testApp(const HomeScreen(), theme: theme));
    await tester.pumpAndSettle();
    expect(ring(tester), theme.colorScheme.primary);

    await openInspector(tester);
    final t = inspectorTokens(tester);
    expect(t.accent, theme.colorScheme.primary);
    expect(t.accentAlt, theme.colorScheme.primary);
    expect(t.onAccent, theme.colorScheme.onPrimary);
    expect(t.text, theme.colorScheme.onSurface);
    expect(t.brightness, Brightness.light);
    // Material widgets in the inspector build on the app's scheme too.
    final inspector = Theme.of(tester.element(find.byKey(const ValueKey('app_inspect_tab_network'))));
    expect(inspector.colorScheme.secondary, theme.colorScheme.secondary);
  });

  testWidgets('follows the app when it switches to dark mode and back', (tester) async {
    final mode = ValueNotifier(ThemeMode.light);
    addTearDown(mode.dispose);
    final light = ThemeData(colorSchemeSeed: Colors.indigo);
    final dark = ThemeData(colorSchemeSeed: Colors.indigo, brightness: Brightness.dark);
    await tester.pumpWidget(AppInspect.wrap(SwitchingApp(mode: mode, light: light, dark: dark)));
    await tester.pumpAndSettle();
    expect(ring(tester), light.colorScheme.primary);

    mode.value = ThemeMode.dark;
    await tester.pumpAndSettle();
    expect(ring(tester), dark.colorScheme.primary);
    expect(bubble(tester).color, dark.colorScheme.surfaceContainerLow);

    // While the inspector is open too.
    await openInspector(tester);
    expect(inspectorTokens(tester).brightness, Brightness.dark);
    mode.value = ThemeMode.light;
    await tester.pumpAndSettle();
    expect(inspectorTokens(tester).brightness, Brightness.light);
    expect(inspectorTokens(tester).accent, light.colorScheme.primary);
  });

  testWidgets('Light and Dark in Settings keep AppInspect\'s own theme', (tester) async {
    final theme = ThemeData(colorSchemeSeed: Colors.teal);
    await tester.pumpWidget(testApp(const HomeScreen(), theme: theme));
    await tester.pumpAndSettle();

    AppInspect.themeMode.value = AppInspectThemeMode.dark;
    await tester.pumpAndSettle();
    expect(ring(tester), AppInspectTokens.dark.accent);
    await openInspector(tester);
    expect(inspectorTokens(tester), same(AppInspectTokens.dark));

    AppInspect.themeMode.value = AppInspectThemeMode.light;
    await tester.pumpAndSettle();
    expect(inspectorTokens(tester), same(AppInspectTokens.light));

    AppInspect.themeMode.value = AppInspectThemeMode.app;
    await tester.pumpAndSettle();
    expect(inspectorTokens(tester).accent, theme.colorScheme.primary);
  });

  testWidgets('Settings has App, Light and Dark', (tester) async {
    await tester.pumpWidget(testApp(const HomeScreen()));
    await tester.pumpAndSettle();
    await openInspector(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Follows your app\'s colors and dark mode.'), findsOneWidget);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(AppInspect.themeMode.value, AppInspectThemeMode.dark);
    expect(find.text('AppInspect only. Your app keeps its own theme.'), findsOneWidget);

    await tester.tap(find.text('App'));
    await tester.pumpAndSettle();
    expect(AppInspect.themeMode.value, AppInspectThemeMode.app);
  });

  testWidgets('a theme around a single screen isn\'t the app\'s theme', (tester) async {
    final theme = ThemeData(colorSchemeSeed: Colors.teal);
    await tester.pumpWidget(testApp(
      Theme(data: ThemeData(colorSchemeSeed: Colors.pink), child: const HomeScreen()),
      theme: theme,
    ));
    await tester.pumpAndSettle();
    expect(ring(tester), theme.colorScheme.primary);
  });

  testWidgets('a theme the app puts around all its screens is', (tester) async {
    final outer = ThemeData(colorSchemeSeed: Colors.teal);
    final inner = ThemeData(colorSchemeSeed: Colors.amber);
    await tester.pumpWidget(AppInspect.wrap(MaterialApp(
      theme: outer,
      builder: (context, child) => Theme(data: inner, child: child!),
      home: const HomeScreen(),
    )));
    await tester.pumpAndSettle();
    expect(ring(tester), inner.colorScheme.primary);
  });

  testWidgets('a theme that leaves primary at Flutter\'s default gets its app bar color', (tester) async {
    // Like an app whose brand color is only in its app bar, and in surface.
    const navy = Color(0xff16469d);
    final theme = ThemeData(
      useMaterial3: false,
      appBarTheme: const AppBarTheme(backgroundColor: navy),
      colorScheme: ColorScheme.fromSwatch().copyWith(surface: navy),
    );
    expect(theme.colorScheme.primary, isNot(navy));
    await tester.pumpWidget(testApp(const HomeScreen(), theme: theme));
    await tester.pumpAndSettle();
    expect(ring(tester), navy);

    await openInspector(tester);
    final t = inspectorTokens(tester);
    expect(t.accent, navy);
    expect(t.onAccent, const Color(0xFFFFFFFF));
    // The navy surface isn't used for cards in a light theme.
    expect(t.surface.computeLuminance(), greaterThan(0.5));
    expect(t.surfaceAlt, isNot(t.surface));
  });

  testWidgets('a theme that leaves primary at Flutter\'s default gets its primaryColor', (tester) async {
    const plum = Color(0xff8e24aa);
    await tester.pumpWidget(testApp(const HomeScreen(), theme: ThemeData(useMaterial3: false, primaryColor: plum)));
    await tester.pumpAndSettle();
    expect(ring(tester), plum);
  });

  testWidgets('a primary color the app picked wins over its app bar color', (tester) async {
    final theme =
        ThemeData(colorSchemeSeed: Colors.teal, appBarTheme: const AppBarTheme(backgroundColor: Colors.orange));
    await tester.pumpWidget(testApp(const HomeScreen(), theme: theme));
    await tester.pumpAndSettle();
    expect(ring(tester), theme.colorScheme.primary);
  });

  testWidgets('Flutter\'s default theme keeps its default primary', (tester) async {
    await tester.pumpWidget(testApp(const HomeScreen()));
    await tester.pumpAndSettle();
    expect(ring(tester), ThemeData().colorScheme.primary);
  });

  testWidgets('takes a CupertinoApp\'s colors', (tester) async {
    await tester.pumpWidget(AppInspect.wrap(const CupertinoApp(
      theme: CupertinoThemeData(primaryColor: CupertinoColors.systemGreen, brightness: Brightness.dark),
      home: Center(child: Text('Home')),
    )));
    await tester.pumpAndSettle();
    expect(ring(tester), CupertinoColors.systemGreen.darkColor);

    await openInspector(tester);
    expect(inspectorTokens(tester).brightness, Brightness.dark);
  });

  testWidgets('an app whose color is red gets a red bubble when something fails', (tester) async {
    final theme = ThemeData(colorScheme: const ColorScheme.light(primary: Color(0xFFD32F2F)));
    await tester.pumpWidget(testApp(const HomeScreen(), theme: theme));
    await tester.pumpAndSettle();
    expect(ring(tester), theme.colorScheme.primary);
    expect(bubble(tester).color, isNot(AppInspectTokens.light.err));

    final call = AppInspect.store.startCall(method: 'GET', uri: Uri.parse('https://api.test/cart'));
    AppInspect.store.completeCall(call, statusCode: 500, body: '{}');
    await tester.pumpAndSettle();
    expect(bubble(tester).color, AppInspectTokens.light.err);
  });

  testWidgets('a teal app keeps its outlined bubble when something fails', (tester) async {
    await tester.pumpWidget(testApp(const HomeScreen(), theme: ThemeData(colorSchemeSeed: Colors.teal)));
    await tester.pumpAndSettle();
    final call = AppInspect.store.startCall(method: 'GET', uri: Uri.parse('https://api.test/cart'));
    AppInspect.store.completeCall(call, statusCode: 500, body: '{}');
    await tester.pumpAndSettle();
    expect(ring(tester), AppInspectTokens.light.err);
    expect(bubble(tester).color, isNot(AppInspectTokens.light.err));
  });

  testWidgets('the deprecated darkTheme still picks the dark theme', (tester) async {
    // ignore: deprecated_member_use
    await tester.pumpWidget(testApp(const HomeScreen(), config: const AppInspectConfig(darkTheme: true)));
    await tester.pumpAndSettle();
    expect(AppInspect.themeMode.value, AppInspectThemeMode.dark);
    // ignore: deprecated_member_use
    expect(AppInspect.darkTheme.value, isTrue);

    // ignore: deprecated_member_use
    AppInspect.darkTheme.value = false;
    expect(AppInspect.themeMode.value, AppInspectThemeMode.light);
  });

  group('tokens from a color scheme', () {
    test('an older scheme without surface containers still has cards that stand out', () {
      for (final scheme in [const ColorScheme.light(primary: Color(0xFF00897B)), const ColorScheme.dark()]) {
        final t = AppInspectTokens.fromScheme(scheme);
        expect(t.brightness, scheme.brightness);
        expect(t.canvas, isNot(t.surface));
        expect(t.surfaceAlt, isNot(t.surface));
        expect(t.border, isNot(t.text));
        expect(t.textSecondary, isNot(t.text));
        expect(t.textMuted, isNot(t.text));
        expect(t.accentSoft, isNot(t.accent));
      }
    });

    test('roles a scheme leaves unset don\'t hide text or borders', () {
      // fromSwatch leaves outline and outlineVariant at onBackground, which
      // is white for a dark primary such as blue.
      final scheme = ColorScheme.fromSwatch(primarySwatch: Colors.blue);
      expect(scheme.outline, Colors.white);
      final t = AppInspectTokens.fromScheme(scheme);
      double contrast(Color a, Color b) {
        final x = a.computeLuminance(), y = b.computeLuminance();
        return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
      }

      expect(contrast(t.textMuted, t.surface), greaterThan(2.5));
      expect(contrast(t.textSecondary, t.surface), greaterThan(4.5));
      expect(contrast(t.border, t.surface), greaterThan(1.1));
    });

    test('a page color the app picked goes behind the cards', () {
      const cream = Color(0xFFF7F1E8);
      final scheme = ColorScheme.fromSeed(seedColor: Colors.brown);
      expect(AppInspectTokens.fromScheme(scheme, background: cream).canvas, cream);
      // A dark page color in a light theme would hide the text, so it's left out.
      expect(AppInspectTokens.fromScheme(scheme, background: const Color(0xFF101010)).canvas,
          isNot(const Color(0xFF101010)));
    });

    test('status colors stay AppInspect\'s own', () {
      final t = AppInspectTokens.fromScheme(ColorScheme.fromSeed(seedColor: Colors.purple));
      expect(t.ok, AppInspectTokens.light.ok);
      expect(t.err, AppInspectTokens.light.err);
      expect(t.warn, AppInspectTokens.light.warn);
      // Violet marks repeated calls.
      expect(t.violet, AppInspectTokens.light.violet);
    });

    test('the second accent, as on the Logs page, takes the app\'s color', () {
      final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
      final t = AppInspectTokens.fromScheme(scheme);
      expect(t.accentAlt, scheme.primary);
      expect(t.accentAltSoft, t.accentSoft);
      // AppInspect's own themes keep violet.
      expect(AppInspectTokens.light.accentAlt, AppInspectTokens.light.violet);
      expect(AppInspectTokens.dark.accentAlt, AppInspectTokens.dark.violet);
    });
  });
}
