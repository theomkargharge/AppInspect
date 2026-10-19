import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_inspect/app_inspect.dart';

import 'helpers.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Home')));
}

class DetailsScreen extends StatelessWidget {
  const DetailsScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Details')));
}

class CheckoutScreen extends StatelessWidget {
  const CheckoutScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Checkout')));
}

/// Opens the inspector on the call to [path].
Future<void> openCall(WidgetTester tester, String path) async {
  AppInspect.open();
  await tester.pumpAndSettle();
  await tester.tap(find.text(path));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadRoboto);
  setUp(resetAppInspect);

  group('logs', () {
    test('a long debugPrint inside runZoned is logged once, not again as print', () {
      AppInspect.debugInstallLogHooks();
      try {
        AppInspect.runZoned(() => debugPrint('Cart\n${'a long line that wraps ' * 8}', wrapWidth: 40));
      } finally {
        AppInspect.debugRemoveLogHooks();
      }

      expect(AppInspect.store.logs.map((l) => l.source), ['debugPrint']);
    });

    test('throttled debugPrint, the default in apps, is logged once too', () {
      final testPrint = debugPrint;
      debugPrint = debugPrintThrottled;
      AppInspect.debugInstallLogHooks();
      try {
        AppInspect.runZoned(() => debugPrint('Cart\n${'a long line that wraps ' * 8}', wrapWidth: 40));
      } finally {
        AppInspect.debugRemoveLogHooks();
        debugPrint = testPrint;
      }

      expect(AppInspect.store.logs.map((l) => l.source), ['debugPrint']);
    });

    test('a Flutter error printed to the console inside runZoned is logged once', () {
      final testHandler = FlutterError.onError;
      // What an app has by default: errors are printed to the console.
      FlutterError.onError = FlutterError.dumpErrorToConsole;
      FlutterError.resetErrorCount();
      AppInspect.debugInstallLogHooks();
      try {
        AppInspect.runZoned(() => FlutterError.reportError(FlutterErrorDetails(
              exception: StateError('Cart total is missing ${'and this explains why at length ' * 6}'),
              stack: StackTrace.current,
              library: 'cart',
            )));
      } finally {
        AppInspect.debugRemoveLogHooks();
        FlutterError.onError = testHandler;
        FlutterError.resetErrorCount();
      }

      expect(AppInspect.store.logs.map((l) => l.source), ['Flutter error']);
    });
  });

  group('screens', () {
    testWidgets('a route replaced below the top screen doesn\'t take over its calls', (tester) async {
      await tester.pumpWidget(testApp(const HomeScreen()));
      await tester.pumpAndSettle();
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      final details = MaterialPageRoute<void>(builder: (_) => const DetailsScreen());
      nav.push(details);
      await tester.pumpAndSettle();
      expect(AppInspect.store.currentVisit.name, 'DetailsScreen');

      nav.replaceRouteBelow(
          anchorRoute: details, newRoute: MaterialPageRoute<void>(builder: (_) => const CheckoutScreen()));
      await tester.pumpAndSettle();
      expect(AppInspect.store.currentVisit.name, 'DetailsScreen');

      nav.pop();
      await tester.pumpAndSettle();
      expect(AppInspect.store.currentVisit.name, 'CheckoutScreen');
    });

    testWidgets('a route that is an AppInspectScreen is named by it, never "AppInspectScreen"', (tester) async {
      await tester.pumpWidget(testApp(const HomeScreen()));
      await tester.pumpAndSettle();
      tester.state<NavigatorState>(find.byType(Navigator).first).push(MaterialPageRoute<void>(
            builder: (_) => const AppInspectScreen(name: 'Checkout', child: Text('Pay now')),
          ));
      await tester.pumpAndSettle();

      expect(AppInspect.store.currentVisit.name, 'Checkout');
      expect(AppInspect.store.visits.map((v) => v.name), isNot(contains('AppInspectScreen')));
    });
  });

  testWidgets('wrapping the app again keeps what people picked in Settings', (tester) async {
    await tester.pumpWidget(testApp(const HomeScreen()));
    await tester.pumpAndSettle();
    // Picked in Settings.
    AppInspect.darkTheme.value = true;
    AppInspect.slowThreshold.value = const Duration(seconds: 3);

    // The app rebuilds and wraps itself again with the same config.
    await tester.pumpWidget(testApp(const HomeScreen()));
    await tester.pumpAndSettle();
    expect(AppInspect.darkTheme.value, isTrue);
    expect(AppInspect.slowThreshold.value, const Duration(seconds: 3));

    // A new starting value in the config still applies.
    await tester.pumpWidget(
        testApp(const HomeScreen(), config: const AppInspectConfig(slowThreshold: Duration(milliseconds: 800))));
    await tester.pumpAndSettle();
    expect(AppInspect.slowThreshold.value, const Duration(milliseconds: 800));
    expect(AppInspect.darkTheme.value, isTrue);
  });

  testWidgets('copying JSON on a 360-wide phone shows "Copied" without overflowing', (tester) async {
    setScreen(tester, const Size(360, 740));
    final copied = mockClipboard(tester);
    await tester.pumpWidget(testApp(const HomeScreen()));
    await tester.pumpAndSettle();
    finishedCall('GET', 'https://api.test/products', responseBody: '{"items":[1,2,3]}');
    await openCall(tester, '/products');

    await tester.tap(find.widgetWithText(OutlinedButton, 'JSON'));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Copied'), findsOneWidget);
    expect(copied.single, contains('"items"'));
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Copied'), findsNothing);
  });

  testWidgets('when copying fails, the button doesn\'t claim it worked', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') throw PlatformException(code: 'denied', message: 'No clipboard');
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(testApp(const HomeScreen()));
    await tester.pumpAndSettle();
    finishedCall('GET', 'https://api.test/products', responseBody: '{}');
    await openCall(tester, '/products');

    await tester.tap(find.widgetWithText(FilledButton, 'cURL'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Couldn\'t copy'), findsOneWidget);
    expect(find.text('Copied'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('the HAR file for a screen gets a safe name, even from a route name', (tester) async {
    final copied = mockClipboard(tester);
    await tester.pumpWidget(testApp(const HomeScreen()));
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator).first).push(MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/product/42'),
          builder: (_) => const DetailsScreen(),
        ));
    await tester.pumpAndSettle();
    finishedCall('GET', 'https://api.test/products/42', responseBody: '{}');
    await openCall(tester, '/products/42');

    await tester.tap(find.widgetWithText(OutlinedButton, 'Share'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export HAR: all 1 calls on /product/42'));
    await tester.pumpAndSettle();

    expect(copied.single, contains('"entries"'));
    expect(find.textContaining('a file named product_42.har'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('an instant call with a zero slow-call limit opens without errors', (tester) async {
    await tester.pumpWidget(testApp(const HomeScreen(), config: const AppInspectConfig(slowThreshold: Duration.zero)));
    await tester.pumpAndSettle();
    finishedCall('GET', 'https://api.test/cached', responseBody: '{}', took: Duration.zero);
    await openCall(tester, '/cached');

    expect(tester.takeException(), isNull);
    expect(find.text('200 OK'), findsWidgets);
  });

  testWidgets('a failure with a long error message fits its pill', (tester) async {
    setScreen(tester, const Size(360, 740));
    await tester.pumpWidget(testApp(const HomeScreen()));
    await tester.pumpAndSettle();
    final call = AppInspect.store.startCall(method: 'GET', uri: Uri.parse('https://api.test/profile'));
    AppInspect.store.failCall(call, error: 'SocketException: Connection reset by peer (OS Error: errno = 54) ' * 3);
    AppInspect.open();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('SocketException'), findsOneWidget);
  });
}
