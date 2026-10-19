import 'package:flutter/material.dart';
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

class TabsScreen extends StatefulWidget {
  const TabsScreen({super.key});

  @override
  State<TabsScreen> createState() => TabsScreenState();
}

class TabsScreenState extends State<TabsScreen> {
  int tab = 0;

  void selectTab(int i) => setState(() => tab = i);

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: tab, children: const [
          AppInspectScreen(name: 'ShopTab', child: Text('Shop')),
          AppInspectScreen(name: 'AccountTab', child: Text('Account')),
        ]),
      );
}

/// Throws while it builds, like a bug in an app screen.
class BrokenWidget extends StatelessWidget {
  const BrokenWidget({super.key});

  @override
  Widget build(BuildContext context) => throw StateError('broken build');
}

void call(String path, {int status = 200}) {
  final call = AppInspect.store.startCall(method: 'GET', uri: Uri.parse('https://api.test$path'));
  AppInspect.store.completeCall(call, statusCode: status, body: '{}');
}

/// The text on the bubble's badge, or null when there's no badge.
String? badge(WidgetTester tester) {
  final found = find.byKey(const ValueKey('app_inspect_bubble_badge'));
  return found.evaluate().isEmpty ? null : tester.widget<Text>(found).data;
}

/// The color of the bubble's ring.
Color ring(WidgetTester tester) {
  final container = tester.widget<AnimatedContainer>(
    find.ancestor(of: find.byIcon(Icons.manage_search_rounded), matching: find.byType(AnimatedContainer)).first,
  );
  final border = (container.decoration! as BoxDecoration).border! as Border;
  return border.top.color;
}

void main() {
  setUp(resetAppInspect);

  testWidgets('counts the API calls on this screen', (tester) async {
    await tester.pumpWidget(testApp(const HomeScreen()));
    await tester.pumpAndSettle();
    expect(badge(tester), isNull);

    call('/products');
    call('/offers');
    await tester.pumpAndSettle();
    expect(badge(tester), '2');

    // A call that's still waiting counts too.
    AppInspect.store.startCall(method: 'GET', uri: Uri.parse('https://api.test/me'));
    await tester.pumpAndSettle();
    expect(badge(tester), '3');
  });

  testWidgets('keeps counting calls when one fails, and turns red', (tester) async {
    await tester.pumpWidget(testApp(const HomeScreen()));
    await tester.pumpAndSettle();
    final accent = ring(tester);
    call('/products');
    call('/categories');
    call('/banners');
    call('/offers', status: 500);
    await tester.pumpAndSettle();

    // Four calls, one failed: the badge says 4, not 1.
    expect(badge(tester), '4');
    expect(ring(tester), isNot(accent));
    final semantics = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel('AppInspect. 4 calls on this screen. 1 new error. Opens the network inspector.'),
      findsOneWidget,
    );
    semantics.dispose();

    // Opening the inspector marks the failure seen.
    AppInspect.open();
    await tester.pumpAndSettle();
    AppInspect.close();
    await tester.pumpAndSettle();
    expect(badge(tester), '4');
    expect(ring(tester), accent);
  });

  testWidgets('shows ! when something failed but this screen made no call', (tester) async {
    await tester.pumpWidget(testApp(const HomeScreen()));
    await tester.pumpAndSettle();
    AppInspect.log('Checkout crashed', level: AppInspectLogLevel.error);
    await tester.pumpAndSettle();
    expect(badge(tester), '!');
  });

  testWidgets('shows 99+ for more than 99 calls', (tester) async {
    await tester.pumpWidget(testApp(const HomeScreen()));
    await tester.pumpAndSettle();
    for (var i = 0; i < 120; i++) {
      call('/items/$i');
    }
    await tester.pumpAndSettle();
    expect(badge(tester), '99+');
  });

  testWidgets('follows the screen: a new route starts at zero, going back restores the count', (tester) async {
    await tester.pumpWidget(testApp(const HomeScreen()));
    await tester.pumpAndSettle();
    call('/products');
    call('/offers');
    await tester.pumpAndSettle();
    expect(badge(tester), '2');

    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute<void>(builder: (_) => const DetailsScreen()));
    await tester.pumpAndSettle();
    expect(badge(tester), isNull);
    call('/products/1');
    await tester.pumpAndSettle();
    expect(badge(tester), '1');

    nav.pop();
    await tester.pumpAndSettle();
    expect(badge(tester), '2');
  });

  testWidgets('a tab you come back to keeps its calls', (tester) async {
    await tester.pumpWidget(testApp(const TabsScreen()));
    await tester.pumpAndSettle();
    call('/products');
    call('/offers');
    await tester.pumpAndSettle();
    expect(AppInspect.store.currentVisit.name, 'ShopTab');
    expect(badge(tester), '2');

    final tabs = tester.state<TabsScreenState>(find.byType(TabsScreen));
    tabs.selectTab(1);
    await tester.pumpAndSettle();
    expect(AppInspect.store.currentVisit.name, 'AccountTab');
    expect(badge(tester), isNull);
    call('/me');
    await tester.pumpAndSettle();
    expect(badge(tester), '1');

    tabs.selectTab(0);
    await tester.pumpAndSettle();
    expect(AppInspect.store.currentVisit.name, 'ShopTab');
    expect(badge(tester), '2');

    tabs.selectTab(1);
    await tester.pumpAndSettle();
    expect(badge(tester), '1');
  });

  testWidgets('holding the bubble opens the inspector, not a bug report', (tester) async {
    await tester.pumpWidget(testApp(const HomeScreen()));
    await tester.pumpAndSettle();
    call('/cart', status: 500);
    await tester.pumpAndSettle();

    await tester.longPress(find.byIcon(Icons.manage_search_rounded));
    await tester.pumpAndSettle();
    expect(AppInspect.isOpen.value, isTrue);
    expect(find.text('Report a bug'), findsNothing);
    expect(find.byTooltip('Report a bug'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('app_inspect_tab_logs')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Report a bug'), findsNothing);
  });

  testWidgets('an error thrown while the app builds is logged once and still reaches the app', (tester) async {
    final seen = <FlutterErrorDetails>[];
    final testHandler = FlutterError.onError;
    FlutterError.onError = seen.add;
    AppInspect.debugInstallLogHooks();
    try {
      await tester.pumpWidget(testApp(const HomeScreen()));
      await tester.pumpAndSettle();
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav.push(MaterialPageRoute<void>(builder: (_) => const BrokenWidget()));
      await tester.pumpAndSettle();
    } finally {
      AppInspect.debugRemoveLogHooks();
      FlutterError.onError = testHandler;
    }

    // The app's own handler saw the real error, and nothing else.
    expect(seen.map((d) => d.exception.toString()), ['Bad state: broken build']);
    expect(AppInspect.store.logs.where((l) => l.source == 'Flutter error'), hasLength(1));
    // The bubble caught up after the frame.
    expect(badge(tester), '!');
  });

  testWidgets('open and close are safe to call while Flutter builds', (tester) async {
    await tester.pumpWidget(testApp(Builder(builder: (context) {
      AppInspect.open();
      return const HomeScreen();
    })));
    await tester.pumpAndSettle();
    expect(AppInspect.isOpen.value, isTrue);
    expect(find.text('Network'), findsWidgets);
  });
}
