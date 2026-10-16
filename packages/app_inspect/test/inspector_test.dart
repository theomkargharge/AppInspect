import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_inspect/app_inspect.dart';

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

class TabsScreen extends StatefulWidget {
  const TabsScreen({super.key});

  @override
  State<TabsScreen> createState() => TabsScreenState();
}

class TabsScreenState extends State<TabsScreen> {
  int tab = 0;

  void selectTab(int i) => setState(() => tab = i);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: tab, children: const [
        AppInspectScreen(name: 'ShopTab', child: Text('Shop')),
        AppInspectScreen(name: 'AccountTab', child: Text('Account')),
      ]),
    );
  }
}

Widget app(Widget home) => AppInspect.wrap(
      MaterialApp(navigatorObservers: [AppInspect.navigatorObserver], home: home),
    );

/// Sends the Android back button, the way the engine does.
Future<void> pressBack(WidgetTester tester) async {
  final message = const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute'));
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage('flutter/navigation', message, (_) {});
  await tester.pumpAndSettle();
}

/// Records what AppInspect copies to the clipboard.
List<String> mockClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return copied;
}

void main() {
  setUp(() {
    AppInspect.close();
    AppInspect.store.clear();
  });

  testWidgets('names screens from routes', (tester) async {
    await tester.pumpWidget(app(const HomeScreen()));
    await tester.pumpAndSettle();
    expect(AppInspect.store.currentVisit.name, 'HomeScreen');

    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.push(MaterialPageRoute<void>(builder: (_) => const DetailsScreen()));
    await tester.pumpAndSettle();
    expect(AppInspect.store.currentVisit.name, 'DetailsScreen');

    nav.pop();
    await tester.pumpAndSettle();
    expect(AppInspect.store.currentVisit.name, 'HomeScreen');
  });

  testWidgets('names tabs with AppInspectScreen', (tester) async {
    await tester.pumpWidget(app(const TabsScreen()));
    await tester.pumpAndSettle();
    expect(AppInspect.store.currentVisit.name, 'ShopTab');

    tester.state<TabsScreenState>(find.byType(TabsScreen)).selectTab(1);
    await tester.pumpAndSettle();
    expect(AppInspect.store.currentVisit.name, 'AccountTab');
  });

  testWidgets('the bubble opens the current screen\'s calls', (tester) async {
    await tester.pumpWidget(app(const HomeScreen()));
    await tester.pumpAndSettle();

    final call = AppInspect.store.startCall(method: 'GET', uri: Uri.parse('https://api.test/products'));
    AppInspect.store.completeCall(call, statusCode: 500, body: '{"error":"down"}');
    await tester.pumpAndSettle();

    // The bubble shows the failure count.
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.manage_search_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Network'), findsWidgets);
    expect(find.text('HomeScreen'), findsWidgets);
    expect(find.text('/products'), findsOneWidget);
    expect(find.text('500 Server error'), findsOneWidget);

    await tester.tap(find.text('/products'));
    await tester.pumpAndSettle();
    expect(find.textContaining('The problem is on the backend'), findsOneWidget);
    expect(find.text('Request'), findsOneWidget);
  });

  testWidgets('opening a call sizes its decoded JSON, and the list shows it too', (tester) async {
    await tester.pumpWidget(app(const HomeScreen()));
    await tester.pumpAndSettle();
    final call = AppInspect.store.startCall(method: 'GET', uri: Uri.parse('https://api.test/products'));
    // How Dio hands over a compressed JSON response: decoded, with no size.
    AppInspect.store.completeCall(call, statusCode: 200, body: {'products': <Object>[], 'total': 0});
    AppInspect.open();
    await tester.pumpAndSettle();
    expect(find.textContaining('≈'), findsNothing);

    await tester.tap(find.text('/products'));
    await tester.pumpAndSettle();
    // The size is worked out on another isolate, which takes real time.
    for (var i = 0; i < 300 && call.responseSize == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    // {"products":[],"total":0} is 25 bytes: in the hero line and the Overview tab.
    expect(find.textContaining('≈ 25 B'), findsNWidgets(2));

    await pressBack(tester);
    expect(find.text('≈ 25 B'), findsOneWidget);
  });

  testWidgets('back closes the inspector and leaves the app screen alone', (tester) async {
    await tester.pumpWidget(app(const HomeScreen()));
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator)).push(
          MaterialPageRoute<void>(builder: (_) => const DetailsScreen()),
        );
    await tester.pumpAndSettle();

    AppInspect.open();
    await tester.pumpAndSettle();
    expect(find.text('Network'), findsWidgets);

    await pressBack(tester);

    expect(find.text('Network'), findsNothing);
    expect(find.text('Details'), findsOneWidget);
  });

  testWidgets('the Logs tab shows log entries', (tester) async {
    await tester.pumpWidget(app(const HomeScreen()));
    await tester.pumpAndSettle();
    AppInspect.log('Checkout started');
    AppInspect.open();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('app_inspect_tab_logs')));
    await tester.pumpAndSettle();

    expect(find.text('Checkout started'), findsOneWidget);
  });

  testWidgets('a parse error is explained on the call', (tester) async {
    await tester.pumpWidget(app(const HomeScreen()));
    await tester.pumpAndSettle();
    final call = AppInspect.store.startCall(method: 'POST', uri: Uri.parse('https://api.test/carts/add'));
    AppInspect.store.completeCall(call, statusCode: 201, body: '{"total":9.99}');
    expect(
      () => AppInspect.parse(decodeBody(call.responseBody), (j) => j['total'] as int, call: call),
      throwsA(isA<TypeError>()),
    );

    AppInspect.open();
    await tester.pumpAndSettle();
    expect(find.text('Parse error'), findsOneWidget);
    expect(find.text('201 Created'), findsOneWidget);

    await tester.tap(find.text('/carts/add'));
    await tester.pumpAndSettle();
    expect(find.textContaining('The app couldn\'t read this response'), findsOneWidget);
    expect(find.textContaining('failed at total: expected int, got double'), findsOneWidget);
  });

  testWidgets('Share exports a HAR file', (tester) async {
    final copied = mockClipboard(tester);
    await tester.pumpWidget(app(const HomeScreen()));
    await tester.pumpAndSettle();
    final call = AppInspect.store.startCall(method: 'GET', uri: Uri.parse('https://api.test/products'));
    AppInspect.store.completeCall(call, statusCode: 200, body: '{"items":[]}');
    AppInspect.open();
    await tester.pumpAndSettle();
    await tester.tap(find.text('/products'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export HAR: this call'));
    await tester.pumpAndSettle();

    expect(copied.last, contains('"version": "1.2"'));
    expect(find.textContaining('get_products.har'), findsOneWidget);
  });

  testWidgets('holding the bubble opens the bug report', (tester) async {
    final copied = mockClipboard(tester);
    await tester.pumpWidget(app(const HomeScreen()));
    await tester.pumpAndSettle();
    final call = AppInspect.store.startCall(method: 'GET', uri: Uri.parse('https://api.test/cart'));
    AppInspect.store.completeCall(call, statusCode: 500, body: '{"error":"down"}');
    await tester.pump();

    await tester.longPress(find.byIcon(Icons.manage_search_rounded));
    // Not pumpAndSettle: the screenshot spinner keeps animating in tests.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Report a bug'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Cart shows an error');
    await tester.pump();
    await tester.tap(find.text('Copy report'));
    await tester.pump();

    expect(copied.last, contains('## Bug on HomeScreen'));
    expect(copied.last, contains('Cart shows an error'));
    expect(copied.last, contains('| `GET /cart` | 500 Server error |'));
  });

  testWidgets('asks for the PIN when one is set', (tester) async {
    await tester.pumpWidget(AppInspect.wrap(
      MaterialApp(navigatorObservers: [AppInspect.navigatorObserver], home: const HomeScreen()),
      config: const AppInspectConfig(pin: '2468'),
    ));
    AppInspect.open();
    await tester.pumpAndSettle();
    expect(find.text('Enter the AppInspect PIN'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '1111');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Wrong PIN. Try again.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '2468');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Network'), findsWidgets);
  });
}
