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

const Map<String, Size> screens = {
  'iPhone SE (1st gen)': Size(320, 568),
  'small Android': Size(360, 640),
  'iPhone SE (3rd gen)': Size(375, 667),
  'iPhone 16': Size(393, 852),
  'Pixel 8': Size(412, 915),
  'iPhone 16 Pro Max': Size(440, 956),
  'iPad mini': Size(744, 1133),
  'phone in landscape': Size(852, 393),
};

const List<double> textScales = [1, 1.3, 2];

/// Collects every Flutter error, such as an overflow, with the widget that
/// caused it.
class ErrorLog {
  ErrorLog() {
    _original = FlutterError.onError;
    FlutterError.onError = (details) {
      final where = RegExp(r'file:///\S+/lib/\S+').firstMatch(details.toString())?.group(0) ?? '';
      errors.add('[$step] ${details.exceptionAsString().split('\n').first} $where');
    };
  }

  late final FlutterExceptionHandler? _original;
  final List<String> errors = [];
  String step = 'start';

  void restore() => FlutterError.onError = _original;
}

/// Sends the system back button, the way the engine does.
Future<void> pressBack(WidgetTester tester) async {
  final message = const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute'));
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage('flutter/navigation', message, (_) {});
  await tester.pumpAndSettle();
}

/// Walks through every page of the inspector the way QC uses it.
Future<void> walkThrough(WidgetTester tester, ErrorLog log) async {
  Future<void> step(String name, Future<void> Function() action) async {
    log.step = name;
    await action();
  }

  /// The page's main vertical list. On the call page, that's the open tab,
  /// which comes after the summary at the top.
  Finder mainList() => find
      .byWidgetPredicate((w) => w is Scrollable && axisDirectionToAxis(w.axisDirection) == Axis.vertical)
      .hitTestable()
      .last;

  Future<void> tapAndSettle(Finder finder) async {
    // Lists build only what's on screen, so scroll down, then up, until it
    // shows.
    for (final delta in const [-200.0, 200.0]) {
      for (var i = 0; i < 60 && finder.evaluate().isEmpty; i++) {
        await tester.drag(mainList(), Offset(0, delta));
        await tester.pump();
      }
    }
    await tester.pumpAndSettle();
    final target = finder.first;
    if (target.hitTestable().evaluate().isEmpty) {
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      if (target.hitTestable().evaluate().isEmpty) {
        // Revealed under the pinned tabs: bring it further down.
        await tester.drag(mainList(), const Offset(0, 160));
        await tester.pumpAndSettle();
      }
    }
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// Text on screen containing [text], leaving out what's typed in fields.
  Finder label(String text) =>
      find.byWidgetPredicate((w) => w is Text && (w.data ?? w.textSpan?.toPlainText() ?? '').contains(text));

  Future<void> search(String text) async {
    // The search field sits above the list, so scroll back up to it.
    await tester.fling(find.byType(CustomScrollView).hitTestable().first, const Offset(0, 4000), 8000);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).hitTestable().first, text);
    await tester.pumpAndSettle();
  }

  /// Finds the call whose path contains [path] with the search field, then
  /// visits every tab and, with [copy], copies and shares from the floating bar.
  Future<void> visitCall(String path, {bool copy = false}) async {
    await step('open $path', () async {
      await search(path);
      await tapAndSettle(label(path));
    });
    for (final tab in ['Request', 'Response', 'cURL', 'Overview']) {
      await step('$path: $tab tab', () => tapAndSettle(find.text(tab)));
    }
    if (copy) {
      for (final (type, label) in [(FilledButton, 'cURL'), (OutlinedButton, 'JSON')]) {
        await step('$path: copy $label', () async {
          await tester.tap(find.widgetWithText(type, label));
          // Mid-animation, as the label turns into "Copied", and after.
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 60));
          }
          await tester.pump(const Duration(seconds: 3));
          await tester.pumpAndSettle();
        });
      }
      await step('$path: share sheet', () async {
        await tapAndSettle(find.widgetWithText(OutlinedButton, 'Share'));
        await tapAndSettle(find.text('Share as Markdown'));
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
      });
    }
    await step('$path: back to the list', () => pressBack(tester));
  }

  await step('bubble', () async {
    seedRealisticCalls();
    seedRealisticLogs();
    await tester.pumpAndSettle();
  });

  await step('open the inspector', () async {
    await tester.tap(find.byIcon(Icons.manage_search_rounded));
    await tester.pumpAndSettle();
  });

  for (final filter in ['Failed', 'Slow', 'Repeated']) {
    await step('filter $filter', () async {
      await tapAndSettle(find.text(filter));
      await tapAndSettle(find.text(filter));
    });
  }

  await step('switch to All', () => tapAndSettle(find.textContaining('All ·')));

  await step('scroll the list', () async {
    await tester.fling(find.byType(CustomScrollView).first, const Offset(0, -3000), 3000);
    await tester.pumpAndSettle();
    await tester.fling(find.byType(CustomScrollView).first, const Offset(0, 3000), 3000);
    await tester.pumpAndSettle();
  });

  await visitCall('/carts/add', copy: true);
  await visitCall('/v2/users/12345');
  await visitCall('/v2/profile');
  await visitCall('/banner.png');
  await visitCall('/terms');
  await visitCall('/auth/me');

  await step('JSON value actions', () async {
    await search('limit=12');
    await tapAndSettle(label('/products?limit=12'));
    await tapAndSettle(find.text('Response'));
    await tapAndSettle(find.textContaining('"id": 1,', findRichText: true));
    await tapAndSettle(find.text('Copy path'));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    await pressBack(tester);
  });

  await step('clear the search', () async {
    await tapAndSettle(find.byTooltip('Clear search'));
  });

  await step('settings', () async {
    await tapAndSettle(find.byTooltip('Settings'));
    await tapAndSettle(find.text('Mask sensitive data'));
    await tapAndSettle(find.text('Dark'));
    await tapAndSettle(find.text('2.0 s'));
    await tester.fling(find.byType(ListView).first, const Offset(0, -2000), 3000);
    await tester.pumpAndSettle();
    await tester.fling(find.byType(ListView).first, const Offset(0, 2000), 3000);
    await tester.pumpAndSettle();
    await tapAndSettle(find.text('Light'));
    await pressBack(tester);
  });

  await step('logs', () async {
    await tapAndSettle(find.byKey(const ValueKey('app_inspect_tab_logs')));
    for (final filter in ['Errors', 'Warnings', 'Info', 'All']) {
      await tapAndSettle(find.text(filter));
    }
    await tapAndSettle(find.text('This screen'));
    await tapAndSettle(find.text('This screen'));
    await tapAndSettle(find.textContaining('A RenderFlex overflowed'));
    await search('Server error');
    await tapAndSettle(find.text('View request'));
    await pressBack(tester);
    await tapAndSettle(find.byKey(const ValueKey('app_inspect_tab_network')));
  });

  await step('close', () async {
    await pressBack(tester);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Network'), findsNothing);
  });
}

void main() {
  setUpAll(loadRoboto);
  setUp(resetAppInspect);

  for (final MapEntry(key: name, value: size) in screens.entries) {
    for (final scale in textScales) {
      testWidgets('no layout errors on $name at ${scale}x text', (tester) async {
        setScreen(tester, size, textScale: scale);
        mockClipboard(tester);
        final log = ErrorLog();
        try {
          await tester.pumpWidget(testApp(const HomeScreen()));
          await tester.pumpAndSettle();
          await walkThrough(tester, log);
        } finally {
          log.restore();
        }
        expect(log.errors, isEmpty);
      });
    }
  }

  testWidgets('no layout errors in the dark theme on a small phone', (tester) async {
    setScreen(tester, screens['iPhone SE (1st gen)']!, textScale: 1.3);
    mockClipboard(tester);
    final log = ErrorLog();
    try {
      await tester.pumpWidget(testApp(const HomeScreen(), config: const AppInspectConfig(darkTheme: true)));
      await tester.pumpAndSettle();
      await walkThrough(tester, log);
    } finally {
      log.restore();
    }
    expect(log.errors, isEmpty);
  });

  for (final MapEntry(key: name, value: size) in screens.entries) {
    testWidgets('the PIN screen fits on $name', (tester) async {
      setScreen(tester, size, textScale: 1.3);
      final log = ErrorLog();
      try {
        await tester.pumpWidget(testApp(const HomeScreen(), config: const AppInspectConfig(pin: '2468')));
        AppInspect.open();
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '1111');
        await tester.ensureVisible(find.text('Unlock'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Unlock'));
        await tester.pumpAndSettle();
        expect(find.text('Wrong PIN. Try again.'), findsOneWidget);
      } finally {
        log.restore();
      }
      expect(log.errors, isEmpty);
    });
  }
}
