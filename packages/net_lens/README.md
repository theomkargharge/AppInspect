# NetLens

A network inspector for Flutter that QC can use on their own.

Tap the floating bubble and NetLens shows the API calls of the screen you're on: the URL, status in plain words, time, size, headers and the raw response. Copy any call as cURL for the backend team, export it as HAR or Postman, or hold the bubble to send a complete bug report. No cable, no debug console, no "sit beside me".

## What it does

- **Calls grouped by screen.** Every request is tagged with the screen that made it. The inspector opens on "This screen", with "All" one tap away.
- **A bubble that turns red.** It counts the calls on the current screen and turns red when something fails, even when the app shows nothing.
- **Plain-language status.** `500 Server error`, `404 Not found`, `Timeout`, `No connection`.
- **Parse errors linked to the response.** When the server answers 200 but the app can't read it, NetLens says so, names the field and highlights it: "The server answered 201 Created, but the app failed at total: expected int, got double. In CartResult.fromJson (cart.dart:42)."
- **Insights.** Server errors, rejected requests, slow calls and calls repeated in a row (often an API call inside `build()`).
- **Request and response details.** The final URL, the headers after every interceptor, the request body, and the raw response before your app parses it.
- **JSON viewer.** Fold and unfold nodes. Tap a value to copy it or its path, such as `data.items[0].price`.
- **Logs console.** `debugPrint`, `print`, Flutter errors, uncaught errors, failed calls and parse errors, each tagged with its screen and linked to its call.
- **One-tap bug report.** Hold the bubble: a screenshot of the app without NetLens on top, this screen's calls with cURL for the failures, its errors and warnings, and device info, as Markdown with a HAR file attached.
- **Exports.** cURL, JSON, Markdown, HAR (Chrome DevTools, Charles, Proxyman) and Postman collections.
- **Masking.** Authorization headers, cookies, passwords and tokens are masked on screen and in every export. A developer can reveal one header when needed.
- **Safe for production.** On in debug builds. In profile and release builds it's on only with `--dart-define=NET_LENS=true`, so production builds don't contain it.
- **PIN for UAT builds.** Lock the inspector in builds you hand to people outside the team.
- **Easy on the eyes.** A light, touch-first inspector: tap a stat tile to filter, haptics on every tap, smooth transitions and a frosted action bar. Drag the bubble anywhere and it springs to the nearest edge. Dark theme in Settings.

## Setup

```yaml
dependencies:
  net_lens: ^0.2.0
  net_lens_dio: ^0.2.0   # if you use Dio
  net_lens_http: ^0.2.0  # if you use package:http
```

1. Wrap your app where you call `runApp`:

   ```dart
   void main() => runApp(NetLens.wrap(const MyApp()));
   ```

   To capture `print` in the logs too, run the app in NetLens's zone, first thing in `main`:

   ```dart
   void main() => NetLens.runZoned(() => runApp(NetLens.wrap(const MyApp())));
   ```

2. Add the observer, so calls are tagged with their screen:

   ```dart
   MaterialApp(
     navigatorObservers: [NetLens.navigatorObserver],
     // ...
   );
   ```

   With go_router, pass it to `GoRouter(observers: [NetLens.navigatorObserver])`.

3. Capture your client's calls:

   ```dart
   // Dio: add it last, so it sees the headers other interceptors add.
   dio.interceptors.add(NetLensDioInterceptor());

   // package:http
   final client = NetLensHttpClient(); // or NetLensHttpClient(yourClient)
   ```

That's it. Run the app in debug mode and the bubble appears.

## Parse errors

Parse through NetLens and a failure names the exact field:

```dart
// Dio
final cart = NetLensDio.parse(response, Cart.fromJson);
final items = NetLensDio.parseList(response, Item.fromJson);

// Anything else: pass the request's URL so NetLens can find the call.
final cart = NetLens.parse(json, Cart.fromJson, uri: response.request!.url);
```

They return what `fromJson` returns and rethrow what it throws, so your error handling doesn't change. In builds without NetLens they just call `fromJson`.

With Retrofit, plug NetLens into its parse-error logger instead:

```dart
class NetLensParseErrorLogger implements ParseErrorLogger {
  @override
  void logError(Object error, StackTrace stackTrace, RequestOptions options, {Response<dynamic>? response}) =>
      NetLensDio.reportParseError(options, error, stackTrace);
}

final client = RestClient(dio, errorLogger: NetLensParseErrorLogger());
```

Retrofit parses the response itself, so NetLens can't see which field it read last. It lists the likely fields instead: values of the type the app got, such as every number with decimals when the app expected an `int`.

## Bug reports and sharing

Without any setup, Share and "Copy report" copy text to the clipboard. To send files and screenshots, connect your share sheet or tracker:

```dart
NetLens.wrap(
  const MyApp(),
  config: NetLensConfig(
    // Extra lines for every bug report.
    reportInfo: () => {'App': '2.3.1 (231)', 'Flavor': 'staging', 'User': currentUserId},

    // Markdown, or a file's contents when item.fileName is set (such as
    // ProductScreen.har). Hand it to share_plus or your own share sheet.
    onShare: (item) async { /* ... */ },

    // report.markdown, report.screenshot (PNG), report.har and
    // report.logsText. Send them to Jira, Slack or a share sheet.
    onReport: (report) async { /* ... */ },
  ),
);
```

## Logs

The Logs tab shows, newest first and tagged with the screen:

- `debugPrint` output, and `print` output when the app runs in `NetLens.runZoned`
- Flutter errors and uncaught errors, with stack traces
- failed calls and parse errors, linked to their call
- your own lines: `NetLens.log('Checkout started', level: NetLensLogLevel.info)`

NetLens chains to the error handlers that are already set when you call `NetLens.wrap`. If you set `FlutterError.onError` later (for example for Crashlytics), set it before `NetLens.wrap` so both run.

## QA builds

QC usually tests release or profile builds. Turn NetLens on for those with a compile-time flag:

```sh
flutter build apk --release --dart-define=NET_LENS=true
```

Builds without the flag don't contain NetLens. `NetLens.isEnabled` is a constant, so the compiler drops every code path behind it. Turn it off in debug with `--dart-define=NET_LENS=false`.

To lock the inspector in a build you share with clients:

```dart
NetLens.wrap(const MyApp(), config: const NetLensConfig(pin: '2468'));
```

## Screens that aren't routes

Bottom tabs and `PageView` pages don't push routes. Wrap them so their calls get their own name:

```dart
IndexedStack(
  index: tab,
  children: const [
    NetLensScreen(name: 'ShopTab', child: ShopTab()),
    NetLensScreen(name: 'AccountTab', child: AccountTab()),
  ],
);
```

Or call `NetLens.markScreen('CartTab')` yourself.

Screens pushed without a route name are named after their widget, such as `ProductDetailsScreen`. NetLens looks for the first widget on the route whose type ends in `Screen`, `Page` or `View`.

## Settings

```dart
NetLensConfig(
  maxCalls: 300,                         // oldest calls are dropped first
  maxLogs: 1000,                         // oldest log entries are dropped first
  maxBodyChars: 500000,                  // longer bodies are cut
  slowThreshold: Duration(seconds: 1),   // slower calls are flagged
  maskedHeaders: {'authorization', 'cookie', 'x-session'},
  maskedBodyKeys: {'password', 'token', 'otp'},
  showBubble: true,                      // false: open with NetLens.open()
  captureLogs: true,                     // debugPrint, Flutter and uncaught errors
  darkTheme: false,                      // true: start in the dark theme
);
```

NetLens has no plugin dependencies, so it can't cause version conflicts in your app.

## Performance

- Capturing appends to a fixed-size list. Bodies are stored as they arrive and formatted only when someone opens a call.
- Large bodies are decoded on another isolate. The JSON viewer builds only the lines on screen.
- The UI updates at most once per frame, however many calls or log lines arrive. While the inspector is closed, only the bubble rebuilds.
- The `http` adapter copies the response as it streams to your code, up to `maxBodyChars`, so large downloads aren't held in memory twice.
- `NetLens.parse` tracks which field `fromJson` reads, only in builds with NetLens.

## What it captures

| Source | How |
| --- | --- |
| Dio | `NetLensDioInterceptor` from `net_lens_dio` |
| package:http | `NetLensHttpClient` from `net_lens_http` |
| Anything else | Call `NetLens.store.startCall`, then `completeCall` or `failCall` |

Not captured: traffic from native SDKs (Firebase, payment SDKs) and clients that don't go through Dio or package:http.

## Known limits

- On Android, if your app opts in to predictive back (`android:enableOnBackInvokedCallback="true"`), a back gesture while the inspector is open can also pop your app's screen. The classic back button is handled correctly.
- `NetLens.navigatorObserver` tracks one navigator: give it to your root navigator.
- On Android, the OS line in bug reports comes from the kernel version. Add the Android version with `reportInfo` if you need it.

## Coming next

- Session timeline and GraphQL operation names.
- Fault injection, slow network and offline mode, edit and resend, compare two calls.
- Environment switcher, WebSocket frames, analytics events, and viewing a phone's session on a laptop.
