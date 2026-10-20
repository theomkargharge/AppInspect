// The demo video: a tester finds the failing API call herself, while the
// developer stays on a P0 fix. It runs the real example app against
// dummyjson.com, shows the story above the app, and taps through it on its
// own.
//
// Record it with tool/record_linkedin_demo.sh, or just watch it:
//
//   flutter run -t tool/linkedin_demo.dart
//
// It prints DEMO_START and DEMO_END, which the script uses to start and stop
// the screen recording.
import 'package:app_inspect/app_inspect.dart';
import 'package:app_inspect_example/main.dart';
import 'package:flutter/material.dart';
// LiveWidgetController and the finders work in a running app too: they're
// what flutter_driver uses.
import 'package:flutter_test/flutter_test.dart';

import 'demo/stage.dart';

/// Taps, waits and drags in real time, and shows the finger doing it.
class Script {
  Script(this.director);

  final DemoDirector director;
  final LiveWidgetController app = LiveWidgetController(WidgetsBinding.instance);

  /// Lets the app run for [seconds].
  Future<void> wait(double seconds) => app.pump(Duration(milliseconds: (seconds * 1000).round()));

  /// Waits until [finder] shows up, such as after a network call.
  Future<void> waitFor(Finder finder, {double timeout = 20}) async {
    final end = DateTime.now().add(Duration(milliseconds: (timeout * 1000).round()));
    // Before the first frame there's no widget tree to look in yet.
    while (WidgetsBinding.instance.rootElement == null || finder.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) throw StateError('Timed out waiting for $finder');
      await wait(0.1);
    }
  }

  /// Glides the finger to [finder], then taps it.
  Future<void> tap(Finder finder) async {
    await waitFor(finder);
    await tapAt(app.getCenter(finder.first));
  }

  /// Glides the finger to [at], then taps there.
  Future<void> tapAt(Offset at) async {
    director.moveFinger(at);
    await wait(0.55);
    director.press();
    await app.tapAt(at);
    await wait(0.3);
  }

  /// Rests the finger on [finder] without tapping, to point something out.
  Future<void> point(Finder finder) async {
    await waitFor(finder);
    director.moveFinger(app.getCenter(finder.first));
    await wait(0.55);
  }

  /// Drags from the middle of [finder] by [by], slowly enough to follow.
  Future<void> drag(Finder finder, Offset by, {double seconds = 0.8}) async {
    await waitFor(finder);
    final from = app.getCenter(finder.first);
    final duration = Duration(milliseconds: (seconds * 1000).round());
    director.moveFinger(from);
    await wait(0.5);
    director.moveFinger(from + by, over: duration);
    await app.timedDragFrom(from, by, duration);
    await wait(0.3);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final director = DemoDirector()..showCard(const IntroCard());
  runApp(DemoStage(
    director: director,
    app: AppInspect.wrap(
      const ShopApp(),
      config: const AppInspectConfig(slowThreshold: Duration(milliseconds: 800)),
    ),
  ));
  try {
    await play(Script(director));
  } catch (error, stack) {
    // ignore: avoid_print
    print('DEMO_FAILED $error\n$stack');
  }
}

Future<void> play(Script script) async {
  final director = script.director;

  // The shop loads behind the opening card.
  await script.waitFor(find.text('Essence Mascara Lash Princess'));
  await script.wait(1.5);
  // ignore: avoid_print
  print('DEMO_START');
  await script.wait(4.2);
  director.hideCard();
  await script.wait(0.9);

  // The ask.
  director.say(Speaker.qa, 'Add to cart is broken 😩 Can you send me the API + response? It\'s urgent!');
  await script.wait(3.6);
  director.say(Speaker.dev, 'Deep in a P0 fix 🔥 Tap the bubble in the app. It\'s all there 👇');
  await script.wait(3.4);

  // The tester reproduces the bug.
  director.narrate('She opens a product and taps "Add to cart"');
  await script.tap(find.text('Essence Mascara Lash Princess'));
  await script.waitFor(find.text('3 reviews'));
  await script.wait(0.8);
  await script.tap(find.text('Add to cart'));
  await script.waitFor(find.text('Something went wrong'));
  await script.wait(1.6);

  // The bubble.
  director.narrate('The bubble counts this screen\'s API calls.\nRed means something failed.');
  await script.point(find.byIcon(Icons.manage_search_rounded));
  await script.wait(2.6);

  director.narrate('Every call this screen made, problems flagged');
  await script.tap(find.byIcon(Icons.manage_search_rounded));
  await script.wait(3.0);

  // The call.
  director.narrate('201 Created… but the app couldn\'t read it');
  await script.tap(find.text('/carts/add'));
  await script.wait(3.6);

  director.narrate('It names the exact field: total, expected int, got double');
  await script.drag(find.byType(NestedScrollView), const Offset(0, -300));
  director.moveFinger(null);
  await script.wait(3.2);

  // What QA asked for.
  director.narrate('Copy it as cURL. Tokens and passwords stay masked 🔒');
  await script.tap(find.descendant(of: find.byType(TabBar), matching: find.text('cURL')));
  await script.wait(1.2);
  await script.tap(find.widgetWithText(FilledButton, 'cURL'));
  await script.wait(2.6);

  director.narrate('Or share it for Jira and Slack, or as HAR and Postman');
  await script.tap(find.widgetWithText(OutlinedButton, 'Share'));
  await script.wait(2.8);
  // Close the sheet by tapping above it.
  final appTop = script.app.getTopLeft(find.byType(ShopApp)).dy;
  final sheetTop = script.app.getTopLeft(find.text('Share or export')).dy - 40;
  await script.tapAt(Offset(script.app.getCenter(find.byType(ShopApp)).dx, (appTop + sheetTop) / 2));
  director.moveFinger(null);
  await script.wait(0.8);

  // The answer.
  director.say(Speaker.qa, 'Found it! total comes back as 9.99 but the app expects an int. cURL is in Jira ✅');
  await script.wait(3.8);
  director.say(Speaker.dev, 'Fixed in 2 minutes. Never left my P0 🙌');
  await script.wait(3.0);

  director.showCard(const OutroCard());
  await script.wait(5.0);
  // ignore: avoid_print
  print('DEMO_END');
}
