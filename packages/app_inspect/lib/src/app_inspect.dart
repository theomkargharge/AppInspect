import 'dart:async' as zones;
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'config.dart';
import 'models.dart';
import 'parse_errors.dart';
import 'platform/platform_info.dart';
import 'schedule.dart';
import 'screens.dart';
import 'store.dart';
import 'ui/overlay.dart';

/// The navigator for the inspector's own pages. Never the app's navigator.
final GlobalKey<NavigatorState> appInspectNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'AppInspect');

/// The app without AppInspect on top. Bug-report screenshots are taken from it.
final GlobalKey appInspectAppKey = GlobalKey(debugLabel: 'AppInspectApp');

/// Names the screen that's showing when it isn't a route, such as a tab, and
/// returns its visit. With [resume], a screen that shows again, like a tab
/// you come back to, keeps its earlier calls instead of starting from zero.
AppInspectVisit? appInspectShowScreen(String name, {AppInspectVisit? resume}) =>
    AppInspect.isEnabled ? AppInspect._observer.tagScreen(name, resume: resume) : null;

/// Entry point for AppInspect, the QC-first network inspector.
///
/// ```dart
/// void main() => runApp(AppInspect.wrap(const MyApp()));
///
/// MaterialApp(navigatorObservers: [AppInspect.navigatorObserver]);
/// dio.interceptors.add(AppInspectDioInterceptor()); // package:app_inspect_dio
/// ```
///
/// AppInspect is on in debug builds. In profile and release builds it is on only
/// with `--dart-define=APP_INSPECT=true`, so a production build doesn't contain
/// it at all: [isEnabled] is a compile-time constant and the compiler removes
/// every code path behind it.
abstract final class AppInspect {
  /// Whether AppInspect is compiled into this build.
  static const bool isEnabled = bool.fromEnvironment('APP_INSPECT', defaultValue: kDebugMode);

  /// Captured calls, logs and screen visits. Adapters write to it.
  static final AppInspectStore store = AppInspectStore();

  static final AppInspectNavigatorObserver _observer = AppInspectNavigatorObserver(store);

  /// Whether the inspector is showing.
  static final ValueNotifier<bool> isOpen = ValueNotifier<bool>(false);

  /// Mask sensitive headers and keys. People can turn this off in Settings.
  static final ValueNotifier<bool> maskData = ValueNotifier<bool>(true);

  /// The inspector's own theme, separate from the app's.
  static final ValueNotifier<bool> darkTheme = ValueNotifier<bool>(false);

  /// Calls slower than this are flagged. People can change it in Settings.
  static final ValueNotifier<Duration> slowThreshold = ValueNotifier<Duration>(const Duration(seconds: 1));

  static bool _unlocked = false;
  static bool _backHandlerInstalled = false;
  static _LogHooks? _hooks;
  static bool _inFlutterError = false;
  static AppInspectConfig? _wrapped;

  /// Lines debugPrint is about to print. debugPrint prints through `print`,
  /// so the zone skips these instead of logging them twice.
  static final ListQueue<String> _debugPrinted = ListQueue<String>();

  /// Remembers the lines debugPrint will hand to `print`. With a wrap width,
  /// such as for Flutter's error reports, long lines are printed in pieces.
  static void _rememberPrinted(String message, int? wrapWidth) {
    void remember(String line) {
      _debugPrinted.addLast(line);
      if (_debugPrinted.length > 1000) _debugPrinted.removeFirst();
    }

    for (final line in message.split('\n')) {
      if (wrapWidth == null) {
        remember(line);
      } else {
        debugWordWrap(line, wrapWidth).forEach(remember);
      }
    }
  }

  /// Whether every line of [text] is one debugPrint just printed. Throttled
  /// debugPrint prints line by line, the synchronous one all lines at once.
  static bool _takePrinted(String text) {
    final lines = text.split('\n');
    if (!lines.every(_debugPrinted.contains)) return false;
    lines.forEach(_debugPrinted.remove);
    return true;
  }

  static AppInspectConfig get config => store.config;

  /// Wraps the app with the floating bubble and the inspector.
  ///
  /// Call it where you call `runApp`, so AppInspect can handle the back button
  /// before the app does while the inspector is open.
  static Widget wrap(Widget app, {AppInspectConfig config = const AppInspectConfig()}) {
    if (!isEnabled) return app;
    store.config = config;
    // A rebuild that wraps the app again keeps what people picked in
    // Settings. Only a new starting value in the config changes it.
    final previous = _wrapped;
    _wrapped = config;
    if (previous == null || previous.darkTheme != config.darkTheme) {
      runWhenSafe(() => darkTheme.value = config.darkTheme);
    }
    if (previous == null || previous.slowThreshold != config.slowThreshold) {
      runWhenSafe(() => slowThreshold.value = config.slowThreshold);
    }
    _installBackHandler();
    // flutter test checks that debugPrint and the error handlers are left
    // alone, so AppInspect doesn't hook them there.
    if (config.captureLogs && !isFlutterTest) _installLogHooks();
    return AppInspectOverlay(child: app);
  }

  /// Runs [body], usually your `runApp` call, in a zone that also sends
  /// `print` output to the logs console.
  ///
  /// Call it first thing in `main`, before `WidgetsFlutterBinding.ensureInitialized`,
  /// so the binding and the app share the zone:
  ///
  /// ```dart
  /// void main() => AppInspect.runZoned(() => runApp(AppInspect.wrap(const MyApp())));
  /// ```
  static R runZoned<R>(R Function() body) {
    if (!isEnabled) return body();
    return zones.runZoned(
      body,
      zoneSpecification: zones.ZoneSpecification(
        print: (self, parent, zone, line) {
          if (!_takePrinted(line)) store.addLog(AppInspectLogLevel.info, line, source: 'print');
          parent.print(zone, line);
        },
      ),
    );
  }

  /// Add this to `MaterialApp.navigatorObservers` (or your router's
  /// observers) so every call is tagged with the screen that made it.
  static NavigatorObserver get navigatorObserver => isEnabled ? _observer : NavigatorObserver();

  /// Names the current screen when there's no route change, such as a tab
  /// switch. The `AppInspectScreen` widget calls this for you.
  static void markScreen(String name) {
    if (isEnabled) _observer.tagScreen(name);
  }

  /// Adds a line to the logs console, tagged with the current screen.
  static void log(
    String message, {
    AppInspectLogLevel level = AppInspectLogLevel.info,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!isEnabled) return;
    store.addLog(level, error == null ? message : '$message: $error', source: 'App', details: stackTrace?.toString());
  }

  /// Parses [json] with [fromJson]. If it throws, AppInspect links the error to
  /// the response it came from, names the exact field that broke, and
  /// rethrows.
  ///
  /// Pass the [call], or the request's [uri] so AppInspect can find it.
  /// `AppInspectDio.parse` does this for Dio responses.
  static T parse<T>(
    Object? json,
    T Function(Map<String, dynamic> json) fromJson, {
    AppInspectCall? call,
    Uri? uri,
  }) {
    if (!isEnabled) return fromJson(json as Map<String, dynamic>);
    final tracker = JsonReadTracker();
    try {
      return fromJson(trackJson(json, '', tracker) as Map<String, dynamic>);
    } catch (error, stack) {
      reportParseError(error, stack, call: call, uri: uri, field: tracker.lastPath);
      rethrow;
    }
  }

  /// Like [parse], for a JSON list of objects.
  static List<T> parseList<T>(
    Object? json,
    T Function(Map<String, dynamic> json) fromJson, {
    AppInspectCall? call,
    Uri? uri,
  }) {
    if (!isEnabled) return [for (final e in json as List<dynamic>) fromJson(e as Map<String, dynamic>)];
    final tracker = JsonReadTracker();
    try {
      final list = trackJson(json, '', tracker) as List<dynamic>;
      return [for (final e in list) fromJson(e as Map<String, dynamic>)];
    } catch (error, stack) {
      reportParseError(error, stack, call: call, uri: uri, field: tracker.lastPath);
      rethrow;
    }
  }

  /// Links a parsing failure to the response it came from. Use it when you
  /// parse responses yourself, for example from Retrofit's
  /// `ParseErrorLogger`. Without [field], AppInspect guesses the likely fields.
  static void reportParseError(
    Object error,
    StackTrace stack, {
    AppInspectCall? call,
    Uri? uri,
    String? field,
  }) {
    if (!isEnabled) return;
    try {
      var target = call;
      if (target == null && uri != null) {
        final calls = store.calls;
        for (var i = calls.length - 1; i >= 0; i--) {
          if (calls[i].uri == uri && !calls[i].isPending) {
            target = calls[i];
            break;
          }
        }
      }
      final parsed = buildParseError(error, stack, field: field, responseBody: target?.responseBody);
      if (target != null) {
        store.attachParseError(target, parsed);
      } else {
        store.addLog(AppInspectLogLevel.error, 'Couldn\'t read a response: ${parsed.message}',
            source: 'Parse error', details: parsed.stack);
      }
    } catch (_) {
      // Reporting must never break the app.
    }
  }

  /// Opens the inspector on the current screen's calls.
  ///
  /// Safe to call at any time. Called while Flutter builds a frame, it opens
  /// right after that frame.
  static void open() {
    if (!isEnabled) return;
    runWhenSafe(() {
      store.markErrorsSeen();
      isOpen.value = true;
    });
  }

  /// Bug reports are turned off for now, so this opens the inspector.
  @Deprecated('Bug reports are turned off for now. This opens the inspector, like open().')
  static void openReport() => open();

  /// Closes the inspector. Safe to call at any time, like [open].
  static void close() {
    if (!isEnabled) return;
    runWhenSafe(() => isOpen.value = false);
  }

  /// False until the right PIN is entered, when `AppInspectConfig.pin` is set.
  static bool get isUnlocked => _unlocked || config.pin == null;

  /// Returns whether [pin] was right. A right PIN unlocks until the app restarts.
  static bool unlock(String pin) {
    if (pin == config.pin) _unlocked = true;
    return isUnlocked;
  }

  /// A PNG of the app as it is now, without the bubble or the inspector.
  static Future<Uint8List?> captureScreenshot() async {
    if (!isEnabled) return null;
    final context = appInspectAppKey.currentContext;
    final boundary = context?.findRenderObject();
    if (context == null || boundary is! RenderRepaintBoundary) return null;
    try {
      final ratio = math.min(View.maybeOf(context)?.devicePixelRatio ?? 2.0, 2.0);
      final image = await boundary.toImage(pixelRatio: ratio);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return bytes?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// Hooks `debugPrint`, Flutter errors and uncaught errors, for tests.
  @visibleForTesting
  static void debugInstallLogHooks() => _installLogHooks();

  /// Undoes [debugInstallLogHooks].
  @visibleForTesting
  static void debugRemoveLogHooks() {
    final hooks = _hooks;
    if (hooks == null) return;
    debugPrint = hooks.debugPrint;
    FlutterError.onError = hooks.flutterError;
    ui.PlatformDispatcher.instance.onError = hooks.platformError;
    _hooks = null;
  }

  static void _installLogHooks() {
    if (_hooks != null) return;
    final dispatcher = ui.PlatformDispatcher.instance;
    final hooks = _LogHooks(debugPrint, FlutterError.onError, dispatcher.onError);
    _hooks = hooks;

    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        // Flutter prints each error through debugPrint too. That error is
        // already logged once, so skip the copy.
        if (!_inFlutterError) store.addLog(AppInspectLogLevel.info, message, source: 'debugPrint');
        _rememberPrinted(message, wrapWidth);
      }
      hooks.debugPrint(message, wrapWidth: wrapWidth);
    };

    FlutterError.onError = (details) {
      _inFlutterError = true;
      try {
        try {
          store.addLog(AppInspectLogLevel.error, details.exceptionAsString(),
              source: 'Flutter error', details: details.stack?.toString());
        } catch (_) {
          // Logging must never stop the app's own error handler below.
        }
        hooks.flutterError?.call(details);
      } finally {
        _inFlutterError = false;
      }
    };

    dispatcher.onError = (error, stack) {
      try {
        store.addLog(AppInspectLogLevel.error, '$error', source: 'Uncaught error', details: stack.toString());
      } catch (_) {
        // Same here: the app's handler still runs.
      }
      return hooks.platformError?.call(error, stack) ?? false;
    };
  }

  static void _installBackHandler() {
    if (_backHandlerInstalled) return;
    _backHandlerInstalled = true;
    WidgetsFlutterBinding.ensureInitialized().addObserver(_BackHandler());
  }

  /// Back goes to the inspector first: it pops an inspector page, or closes
  /// the inspector, and the app's own screens stay where they are.
  static bool _handleBack() {
    if (!isOpen.value) return false;
    final nav = appInspectNavigatorKey.currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
    } else {
      close();
    }
    return true;
  }
}

/// Device and app details for bug reports.
Map<String, String> appInspectReportInfo() {
  final info = <String, String>{};
  try {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final os = operatingSystemDescription;
    final platform = os.isEmpty ? defaultTargetPlatform.name : os;
    final views = dispatcher.views;
    if (views.isNotEmpty) {
      final view = views.first;
      final size = view.physicalSize / view.devicePixelRatio;
      info['Device'] = '$platform · ${size.width.round()}×${size.height.round()} '
          '@${view.devicePixelRatio.toStringAsFixed(view.devicePixelRatio % 1 == 0 ? 0 : 1)}x';
    } else {
      info['Device'] = platform;
    }
    info['Locale'] = dispatcher.locale.toLanguageTag();
    // ignore: deprecated_member_use_from_same_package
    info.addAll(AppInspect.config.reportInfo?.call() ?? const {});
  } catch (_) {
    // Whatever was gathered before the failure still helps.
  }
  return info;
}

class _LogHooks {
  _LogHooks(this.debugPrint, this.flutterError, this.platformError);

  final DebugPrintCallback debugPrint;
  final FlutterExceptionHandler? flutterError;
  final ui.ErrorCallback? platformError;
}

class _BackHandler with WidgetsBindingObserver {
  @override
  Future<bool> didPopRoute() => SynchronousFuture<bool>(AppInspect._handleBack());

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) => AppInspect.isOpen.value;

  @override
  void handleCommitBackGesture() => AppInspect._handleBack();
}
