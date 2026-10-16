import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_inspect/app_inspect.dart';

Widget app() => AppInspect.wrap(
      MaterialApp(navigatorObservers: [AppInspect.navigatorObserver], home: const Scaffold(body: Text('Home'))),
    );

/// Opens the inspector on the call to [path].
Future<void> openCall(WidgetTester tester, String path) async {
  AppInspect.open();
  await tester.pumpAndSettle();
  await tester.tap(find.text(path));
  await tester.pumpAndSettle();
}

/// Captures another call. The open detail page rebuilds for it.
Future<void> captureAnother(WidgetTester tester) async {
  final call = AppInspect.store.startCall(method: 'GET', uri: Uri.parse('https://api.test/other'));
  AppInspect.store.completeCall(call, statusCode: 200, body: '{}');
  await tester.pumpAndSettle();
}

/// Work on another isolate takes real time, so let it run until [found]
/// shows up.
Future<void> waitFor(WidgetTester tester, Finder found) async {
  for (var i = 0; i < 300 && found.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
}

/// Counts how often it's written out as text on this isolate. Writing it
/// out on another isolate counts there instead.
class Counted {
  static int written = 0;

  @override
  String toString() {
    written++;
    return 'counted';
  }
}

void main() {
  setUp(() {
    AppInspect.close();
    AppInspect.store.clear();
    AppInspect.maskData.value = true;
  });

  testWidgets('JSON you unfold stays unfolded while new calls come in', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final call = AppInspect.store.startCall(method: 'GET', uri: Uri.parse('https://api.test/products'));
    AppInspect.store.completeCall(call, statusCode: 200, body: {
      'data': {'items': List.generate(25, (i) => i)},
    });
    await openCall(tester, '/products');
    await tester.tap(find.text('Response'));
    await tester.pumpAndSettle();

    // A long list deep in the tree starts folded.
    await tester.tap(find.text('25 items'));
    await tester.pumpAndSettle();
    expect(find.text('25 items'), findsNothing);

    await captureAnother(tester);
    await captureAnother(tester);
    expect(find.text('25 items'), findsNothing);
  });

  testWidgets('switching masking off and on masks the response again', (tester) async {
    addTearDown(() => AppInspect.maskData.value = true);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final call = AppInspect.store.startCall(method: 'POST', uri: Uri.parse('https://api.test/login'));
    AppInspect.store.completeCall(call, statusCode: 200, body: {'token': 'secret-123', 'name': 'Asha'});
    await openCall(tester, '/login');
    await tester.tap(find.text('Response'));
    await tester.pumpAndSettle();
    expect(find.textContaining('secret-123'), findsNothing);

    AppInspect.maskData.value = false;
    await tester.pumpAndSettle();
    expect(find.textContaining('secret-123'), findsOneWidget);

    AppInspect.maskData.value = true;
    await tester.pumpAndSettle();
    expect(find.textContaining('secret-123'), findsNothing);
  });

  testWidgets('the request size is worked out once, off the UI thread, in UTF-8 bytes', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final call = AppInspect.store.startCall(
      method: 'POST',
      uri: Uri.parse('https://api.test/reviews'),
      body: {'text': 'Crème brûlée', 'meta': Counted()},
    );
    AppInspect.store.completeCall(call, statusCode: 201, body: '{}');
    await openCall(tester, '/reviews');

    // Compact JSON, as most clients send it. The accents take two bytes each.
    final bytes = utf8.encode(jsonEncode({'text': 'Crème brûlée', 'meta': 'counted'})).length;
    final size = find.text('≈ $bytes B');
    await waitFor(tester, size);
    expect(size, findsOneWidget);

    // Opening the page writes the body out on this isolate once, for the
    // cURL command. New calls rebuild the page, and nothing writes it again.
    final written = Counted.written;
    await captureAnother(tester);
    await captureAnother(tester);
    expect(Counted.written, written);
    expect(size, findsOneWidget);
  });
}
