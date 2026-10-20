// Walks the example app to each screen shown on pub.dev and prints SHOT:<name>
// when it's ready. tool/take_store_screenshots.sh captures the simulator
// screen on each one.
//
//   flutter run -t tool/store_screenshots.dart
import 'package:app_inspect/app_inspect.dart';
import 'package:app_inspect_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final LiveWidgetController app = LiveWidgetController(WidgetsBinding.instance);

Future<void> wait(double seconds) => app.pump(Duration(milliseconds: (seconds * 1000).round()));

Future<void> waitFor(Finder finder) async {
  final end = DateTime.now().add(const Duration(seconds: 20));
  while (WidgetsBinding.instance.rootElement == null || finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) throw StateError('Timed out waiting for $finder');
    await wait(0.1);
  }
}

Future<void> tap(Finder finder) async {
  await waitFor(finder);
  await app.tap(finder.first);
  await wait(1.2);
}

/// Holds still long enough for the screenshot.
Future<void> shot(String name) async {
  await wait(0.8);
  // ignore: avoid_print
  print('SHOT:$name');
  await wait(2.0);
}

Future<void> main() async {
  runApp(AppInspect.wrap(
    const ShopApp(),
    config: const AppInspectConfig(slowThreshold: Duration(milliseconds: 800)),
  ));
  try {
    await waitFor(find.text('Essence Mascara Lash Princess'));
    await wait(2.5);
    await shot('bubble');

    await tap(find.text('Essence Mascara Lash Princess'));
    await waitFor(find.text('3 reviews'));
    await wait(2.0);
    await tap(find.text('Add to cart'));
    await waitFor(find.text('Something went wrong'));
    await wait(4.5);
    await tap(find.byIcon(Icons.manage_search_rounded));
    await shot('calls');

    await tap(find.text('/carts/add'));
    await app.timedDrag(find.byType(NestedScrollView), const Offset(0, -170), const Duration(milliseconds: 600));
    await wait(0.8);
    await shot('parse_error');

    await tap(find.descendant(of: find.byType(TabBar), matching: find.text('cURL')));
    await shot('curl');

    await tap(find.widgetWithText(OutlinedButton, 'Share'));
    await shot('export');
    AppInspect.close();
    await wait(1.0);
    AppInspect.open();
    await wait(1.0);

    await tap(find.byKey(const ValueKey('app_inspect_tab_logs')));
    await shot('logs');
    // ignore: avoid_print
    print('SHOTS_DONE');
  } catch (error, stack) {
    // ignore: avoid_print
    print('SHOTS_FAILED $error\n$stack');
  }
}
