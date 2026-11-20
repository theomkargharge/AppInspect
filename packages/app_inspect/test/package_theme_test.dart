import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_inspect/app_inspect.dart';
import 'package:app_inspect/src/ui/app_theme.dart';
import 'package:app_inspect/src/ui/theme.dart';

import 'fake_design_packages.dart' as pkg;
import 'helpers.dart';

/// An app built with the material_ui or cupertino_ui package: its theme sits
/// above its navigator, like the one their MaterialApp and CupertinoApp build.
Widget packageApp(Widget Function(Widget navigator) theme) => AppInspect.wrap(WidgetsApp(
      color: const Color(0xFF000000),
      navigatorObservers: [AppInspect.navigatorObserver],
      builder: (context, navigator) => theme(navigator!),
      pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
          PageRouteBuilder<T>(settings: settings, pageBuilder: (context, _, __) => builder(context)),
      home: const Center(child: Text('Home')),
    ));

AppInspectTokens? appLook() => AppInspectAppTheme.look.value?.tokens;

void main() {
  setUp(() {
    resetAppInspect();
    AppInspectAppTheme.debugReset();
  });

  testWidgets('takes the colors of an app built with material_ui', (tester) async {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal, brightness: Brightness.dark);
    await tester.pumpWidget(packageApp((navigator) => pkg.Theme(
          data: pkg.ThemeData(
            colorScheme: scheme,
            primaryColor: scheme.primary,
            scaffoldBackgroundColor: scheme.surface,
          ),
          child: navigator,
        )));
    await tester.pumpAndSettle();
    final t = appLook()!;
    expect(t.accent, scheme.primary);
    expect(t.onAccent, scheme.onPrimary);
    expect(t.text, scheme.onSurface);
    expect(t.brightness, Brightness.dark);
  });

  testWidgets('a material_ui theme that leaves primary at the default gets its app bar color', (tester) async {
    const navy = Color(0xff16469d);
    final scheme = ColorScheme.fromSwatch();
    await tester.pumpWidget(packageApp((navigator) => pkg.Theme(
          data: pkg.ThemeData(
            colorScheme: scheme,
            primaryColor: scheme.primary,
            appBarTheme: const pkg.AppBarTheme(backgroundColor: navy),
            scaffoldBackgroundColor: scheme.surface,
          ),
          child: navigator,
        )));
    await tester.pumpAndSettle();
    expect(appLook()!.accent, navy);
  });

  testWidgets('takes the colors of an app built with cupertino_ui', (tester) async {
    final green = pkg.CupertinoDynamicColor(const Color(0xFF34C759), const Color(0xFF30D158));
    await tester.pumpWidget(packageApp((navigator) => pkg.CupertinoTheme(
          data: pkg.CupertinoThemeData(
            brightness: Brightness.dark,
            primaryColor: green,
            primaryContrastingColor: const Color(0xFF000000),
            scaffoldBackgroundColor: const Color(0xFF000000),
          ),
          child: navigator,
        )));
    await tester.pumpAndSettle();
    final t = appLook()!;
    expect(t.accent, const Color(0xFF30D158));
    expect(t.brightness, Brightness.dark);
  });

  testWidgets('the inspector opens in the colors of a material_ui app', (tester) async {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.deepOrange);
    await tester.pumpWidget(packageApp((navigator) => pkg.Theme(
          data: pkg.ThemeData(
            colorScheme: scheme,
            primaryColor: scheme.primary,
            scaffoldBackgroundColor: scheme.surface,
          ),
          child: navigator,
        )));
    await tester.pumpAndSettle();
    AppInspect.open();
    await tester.pumpAndSettle();
    final inspector = Theme.of(tester.element(find.byKey(const ValueKey('app_inspect_tab_network'))));
    expect(inspector.extension<AppInspectTokens>()!.accent, scheme.primary);
  });
}
