import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_inspect/app_inspect.dart';
import 'package:app_inspect/src/timeline.dart';

import 'helpers.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              settings: const RouteSettings(name: '/cart'),
              builder: (_) => const Scaffold(body: Text('Cart')),
            )),
            child: const Text('Open cart'),
          ),
        ),
      );
}

final DateTime t0 = DateTime(2026, 11, 20, 14, 0, 0);
final AppInspectVisit home = AppInspectVisit(id: 1, name: 'HomeScreen', startedAt: t0);
final AppInspectVisit cart = AppInspectVisit(id: 2, name: 'CartScreen', startedAt: t0.add(const Duration(seconds: 5)));

AppInspectCall call(String method, String url, AppInspectVisit visit, int second,
    {int status = 200, int tookMs = 120, Object? body}) {
  final started = t0.add(Duration(seconds: second));
  return AppInspectCall(
    id: second,
    method: method,
    uri: Uri.parse(url),
    requestHeaders: const {},
    startedAt: started,
    visit: visit,
    source: 'test',
    requestBody: body,
  )
    ..state = AppInspectCallState.completed
    ..statusCode = status
    ..endedAt = started.add(Duration(milliseconds: tookMs));
}

AppInspectLog log(String message, AppInspectVisit visit, int second,
        {AppInspectLogLevel level = AppInspectLogLevel.info, AppInspectCall? about}) =>
    AppInspectLog(
      id: 100 + second,
      time: t0.add(Duration(seconds: second)),
      level: level,
      message: message,
      source: 'App',
      visit: visit,
      call: about,
    );

void main() {
  final screens = [
    AppInspectScreenChange(visit: home, time: t0),
    AppInspectScreenChange(visit: cart, time: t0.add(const Duration(seconds: 5))),
    AppInspectScreenChange(visit: home, time: t0.add(const Duration(seconds: 9)), returned: true),
  ];
  final products = call('GET', 'https://shop.com/products?token=abc', home, 1);
  final addToCart = call('POST', 'https://shop.com/carts', cart, 6, status: 500);
  final reviews = call('GET', 'https://shop.com/reviews', cart, 7, tookMs: 2400);
  final calls = [products, addToCart, reviews];
  final logs = [
    log('Loading products', home, 1),
    log('POST /carts → 500 Server error', cart, 6, level: AppInspectLogLevel.warning, about: addToCart),
    log('Cart total looks wrong', cart, 8, level: AppInspectLogLevel.warning),
  ];

  group('buildTimeline', () {
    test('merges screens, calls and logs in order, screens first at the same moment', () {
      final entries = buildTimeline(screens: screens, calls: calls, logs: logs);
      expect(
        [
          for (final e in entries)
            switch (e) {
              ScreenEntry(:final change) => '${change.returned ? 'back' : 'open'} ${change.visit.name}',
              CallEntry(:final call) => '${call.method} ${call.uri.path}',
              LogEntry(:final log) => 'log ${log.message}',
            },
        ],
        [
          'open HomeScreen',
          'GET /products',
          'log Loading products',
          'open CartScreen',
          'POST /carts',
          'GET /reviews',
          'log Cart total looks wrong',
          'back HomeScreen',
        ],
      );
    });

    test('leaves out log lines about a call: the call shows it', () {
      final entries = buildTimeline(screens: const [], calls: const [], logs: logs);
      expect(entries.whereType<LogEntry>().map((e) => e.log.message), isNot(contains(startsWith('POST'))));
    });

    test('problems are failed and slow calls, warnings and errors', () {
      final entries = buildTimeline(screens: screens, calls: calls, logs: logs);
      final problems = entries.where((e) => e.isProblem(const Duration(seconds: 1))).toList();
      expect(problems, hasLength(3));
    });

    test('formatGap', () {
      expect(formatGap(const Duration(milliseconds: 120)), '+120 ms');
      expect(formatGap(const Duration(milliseconds: 1450)), '+1.4 s');
      expect(formatGap(const Duration(minutes: 3, seconds: 5)), '+3 min');
      expect(formatGap(const Duration(hours: 2)), '+2 h');
      expect(formatGap(Duration.zero), '');
      expect(formatGap(const Duration(milliseconds: -5)), '');
    });
  });

  group('buildTimelineMarkdown', () {
    test('numbers the steps, oldest first, and marks problems', () {
      final markdown = buildTimelineMarkdown(
        screens: screens,
        calls: calls,
        logs: logs,
        masker: const AppInspectMasker(AppInspectConfig()),
        slowThreshold: const Duration(seconds: 1),
      );
      expect(
        markdown,
        '## Session timeline\n'
        '\n'
        '1. 14:00:00 Opened **HomeScreen**\n'
        '2. 14:00:01 `GET /products?token=••••••••` → 200 OK, 120 ms\n'
        '3. 14:00:01 Log (App): Loading products\n'
        '4. 14:00:05 Opened **CartScreen**\n'
        '5. 14:00:06 `POST /carts` → 500 Server error, 120 ms · **failed**\n'
        '6. 14:00:07 `GET /reviews` → 200 OK, 2.4 s · **slow**\n'
        '7. 14:00:08 **Warning** (App): Cart total looks wrong\n'
        '8. 14:00:09 Back to **HomeScreen**\n',
      );
    });

    test('keeps the last steps of a long session', () {
      final markdown = buildTimelineMarkdown(
        screens: screens,
        calls: calls,
        logs: logs,
        masker: const AppInspectMasker(AppInspectConfig()),
        slowThreshold: const Duration(seconds: 1),
        maxEntries: 2,
      );
      expect(markdown, contains('_The last 2 of 8 steps._'));
      expect(markdown, contains('1. 14:00:08'));
      expect(markdown, isNot(contains('HomeScreen**\n2. 14:00:01')));
    });

    test('an empty session', () {
      expect(
        buildTimelineMarkdown(
          screens: const [],
          calls: const [],
          logs: const [],
          masker: const AppInspectMasker(AppInspectConfig()),
          slowThreshold: const Duration(seconds: 1),
        ),
        '## Session timeline\n\nNothing happened yet.\n',
      );
    });
  });

  group('the Timeline tab', () {
    setUp(resetAppInspect);

    testWidgets('records the screens people open and go back to', (tester) async {
      await tester.pumpWidget(testApp(const HomeScreen()));
      await tester.pumpAndSettle();
      final before = AppInspect.store.screenChanges.length;
      await tester.tap(find.text('Open cart'));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.text('Cart'))).pop();
      await tester.pumpAndSettle();
      final changes = AppInspect.store.screenChanges.sublist(before);
      expect([for (final c in changes) '${c.returned ? 'back' : 'open'} ${c.visit.name}'],
          ['open /cart', 'back HomeScreen']);
    });

    testWidgets('shows the session, filters problems, opens a call and shares the steps', (tester) async {
      final copied = mockClipboard(tester);
      await tester.pumpWidget(testApp(const HomeScreen()));
      await tester.pumpAndSettle();
      finishedCall('GET', 'https://shop.com/products');
      finishedCall('POST', 'https://shop.com/carts', status: 500);
      AppInspect.log('Cart total looks wrong', level: AppInspectLogLevel.warning);
      AppInspect.open();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('app_inspect_tab_timeline')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Opened', findRichText: true), findsWidgets);
      expect(find.text('/products'), findsOneWidget);
      expect(find.text('/carts'), findsOneWidget);
      expect(find.text('Cart total looks wrong'), findsOneWidget);

      await tester.tap(find.text('Problems'));
      await tester.pumpAndSettle();
      expect(find.text('/products'), findsNothing);
      expect(find.text('/carts'), findsOneWidget);
      expect(find.text('Cart total looks wrong'), findsOneWidget);

      await tester.tap(find.byTooltip('Share the steps'));
      await tester.pumpAndSettle();
      expect(copied.single, startsWith('## Session timeline'));
      expect(copied.single, contains('`POST /carts` → 500 Server error'));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      await tester.tap(find.text('/carts'));
      await tester.pumpAndSettle();
      expect(find.text('Overview'), findsOneWidget);
    });
  });
}
