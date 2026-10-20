// Renders inspector screens to PNG files for a person to look at. Skipped
// unless SHOTS_DIR is set:
//
//   flutter test test/visual_review_test.dart --dart-define=SHOTS_DIR=/tmp/shots
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_inspect/app_inspect.dart';

import 'helpers.dart';

const String shotsDir = String.fromEnvironment('SHOTS_DIR');

final GlobalKey _screen = GlobalKey();

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Kartly')),
        body: ListView(children: [
          for (var i = 0; i < 8; i++) ListTile(title: Text('Product $i'), subtitle: const Text('beauty · 4.9 rating')),
        ]),
      );
}

/// Loads the font files that exist. Missing ones, such as macOS fonts on
/// Linux, are skipped.
Future<void> loadFont(String family, List<String> paths) async {
  final files = paths.map(File.new).where((f) => f.existsSync()).toList();
  if (files.isEmpty) return;
  final loader = FontLoader(family);
  for (final file in files) {
    loader.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
  }
  await loader.load();
}

Future<void> loadIcons() async {
  final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
  await loadFont('MaterialIcons', ['${artifacts.path}/material_fonts/MaterialIcons-Regular.otf']);
  // Real glyphs for monospace text, which flutter test otherwise draws as
  // boxes. SF Mono ships with macOS.
  await loadFont('monospace', ['/System/Library/Fonts/SFNSMono.ttf']);
}

Future<void> shot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary = _screen.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$shotsDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> pressBack(WidgetTester tester) async {
  final message = const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute'));
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage('flutter/navigation', message, (_) {});
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await loadRoboto();
    await loadIcons();
  });
  setUp(resetAppInspect);

  const sizes = {
    'phone': (Size(393, 852), 1.0),
    'small': (Size(320, 568), 1.0),
    'small_2x': (Size(320, 568), 2.0),
    'landscape': (Size(852, 393), 1.0),
  };

  for (final MapEntry(key: name, value: (size, scale)) in sizes.entries) {
    testWidgets('screens on $name', (tester) async {
      setScreen(tester, size, textScale: scale, ratio: 1);
      mockClipboard(tester);
      await tester.pumpWidget(RepaintBoundary(key: _screen, child: testApp(const HomeScreen())));
      await tester.pumpAndSettle();
      seedRealisticCalls();
      seedRealisticLogs();
      await tester.pumpAndSettle();
      await shot(tester, '${name}_1_bubble');

      AppInspect.open();
      await tester.pumpAndSettle();
      await shot(tester, '${name}_2_list');

      await tester.enterText(find.byType(TextField).first, 'sho');
      await tester.pumpAndSettle();
      await shot(tester, '${name}_2b_search');
      await tester.enterText(find.byType(TextField).first, 'carts');
      await tester.pumpAndSettle();
      await tester.tap(find.byWidgetPredicate((w) => w is Text && (w.data ?? '').contains('/carts/add')).first);
      await tester.pumpAndSettle();
      await shot(tester, '${name}_3_detail');
      await tester.tap(find.text('Response'));
      await tester.pumpAndSettle();
      await shot(tester, '${name}_4_response');
      await tester.drag(find.byType(NestedScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();
      await shot(tester, '${name}_4b_response_scrolled');
      await tester.tap(find.widgetWithText(OutlinedButton, 'JSON'));
      await tester.pump(const Duration(milliseconds: 300));
      await shot(tester, '${name}_5_copied');
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await tester.tap(find.text('cURL').first);
      await tester.pumpAndSettle();
      await shot(tester, '${name}_6_curl');
      await tester.tap(find.widgetWithText(OutlinedButton, 'Share'));
      await tester.pumpAndSettle();
      await shot(tester, '${name}_7_share');
      await pressBack(tester);
      await pressBack(tester);

      await tester.tap(find.byKey(const ValueKey('app_inspect_tab_logs')));
      await tester.pumpAndSettle();
      await shot(tester, '${name}_8_logs');
      AppInspect.close();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    }, skip: shotsDir.isEmpty);
  }
}
