# AppInspect

A network inspector for Flutter that QC can use on their own.

Tap the floating bubble and AppInspect shows the API calls of the screen you're on: the URL, status in plain words, time, size, headers and the raw response. Copy any call as cURL for the backend team, or export it as HAR or Postman. No cable, no debug console, no "sit beside me".

<p>
  <img src="https://raw.githubusercontent.com/theomkargharge/NetLense/main/packages/app_inspect/screenshots/calls.webp" width="240" alt="Calls grouped by screen, with failed, slow and repeated calls flagged">
  <img src="https://raw.githubusercontent.com/theomkargharge/NetLense/main/packages/app_inspect/screenshots/parse_error.webp" width="240" alt="A parse error that names the exact field the app couldn't read">
  <img src="https://raw.githubusercontent.com/theomkargharge/NetLense/main/packages/app_inspect/screenshots/logs.webp" width="240" alt="Logs console tagged by screen">
</p>

## What it does

- **Calls grouped by screen.** Every request is tagged with the screen that made it. The inspector opens on "This screen", with "All" one tap away.
- **A bubble that turns red.** Its badge counts the API calls on the current screen, and it turns red when something fails, even when the app shows nothing. A tab you come back to keeps its count.
- **Plain-language status.** `500 Server error`, `404 Not found`, `Timeout`, `No connection`. A request the app cancels shows as `Cancelled` and isn't counted as a failure.
- **Parse errors linked to the response.** When the server answers 200 but the app can't read it, AppInspect says so, names the field and highlights it: "The server answered 201 Created, but the app failed at total: expected int, got double. In CartResult.fromJson (cart.dart:42)."
- **Insights.** Server errors, rejected requests, slow calls and calls repeated in a row (often an API call inside `build()`).
- **Request and response details.** The final URL, the headers after every interceptor, the request body, and the raw response before your app parses it.
- **JSON viewer.** Fold and unfold nodes. Tap a value to copy it or its path, such as `data.items[0].price`.
- **Logs console.** `debugPrint`, `print`, Flutter errors, uncaught errors, failed calls and parse errors, each tagged with its screen and linked to its call.
- **Exports.** cURL, JSON, Markdown, HAR (Chrome DevTools, Charles, Proxyman) and Postman collections.
- **Masking.** Authorization headers, cookies, passwords and tokens are masked on screen and in every export, in the body and in the URL's query parameters too. A developer can reveal one header when needed.
- **Safe for production.** On in debug builds. In profile and release builds it's on only with `--dart-define=APP_INSPECT=true`, so production builds don't contain it.
- **PIN for UAT builds.** Lock the inspector in builds you hand to people outside the team.
- **Easy on the eyes.** A light, touch-first inspector: tap a stat tile to filter, haptics on every tap, smooth transitions and a frosted action bar. Drag the bubble anywhere and it springs to the nearest edge. Dark theme in Settings.

## Setup

```yaml
dependencies:
  app_inspect: ^0.2.2
  app_inspect_dio: ^0.2.2   # if you use Dio
  app_inspect_http: ^0.2.2  # if you use package:http
```

1. Wrap your app where you call `runApp`:

   ```dart
   void main() => runApp(AppInspect.wrap(const MyApp()));
   ```

   To capture `print` in the logs too, run the app in AppInspect's zone, first thing in `main`:

   ```dart
   void main() => AppInspect.runZoned(() => runApp(AppInspect.wrap(const MyApp())));
   ```

2. Add the observer, so calls are tagged with their screen:

   ```dart
   MaterialApp(
     navigatorObservers: [AppInspect.navigatorObserver],
     // ...
   );
   ```

   With go_router, pass it to `GoRouter(observers: [AppInspect.navigatorObserver])`.

3. Capture your client's calls:

   ```dart
   // Dio: add it last, so it sees the headers other interceptors add.
   dio.interceptors.add(AppInspectDioInterceptor());

   // package:http
   final client = AppInspectHttpClient(); // or AppInspectHttpClient(yourClient)
   ```

That's it. Run the app in debug mode and the bubble appears.

## Parse errors

Parse through AppInspect and a failure names the exact field:

```dart
// Dio
final cart = AppInspectDio.parse(response, Cart.fromJson);
final items = AppInspectDio.parseList(response, Item.fromJson);

// Anything else: pass the request's URL so AppInspect can find the call.
final cart = AppInspect.parse(json, Cart.fromJson, uri: response.request!.url);
```

They return what `fromJson` returns and rethrow what it throws, so your error handling doesn't change. In builds without AppInspect they just call `fromJson`.

With Retrofit, plug AppInspect into its parse-error logger instead:

```dart
class AppInspectParseErrorLogger implements ParseErrorLogger {
  @override
  void logError(Object error, StackTrace stackTrace, RequestOptions options, {Response<dynamic>? response}) =>
      AppInspectDio.reportParseError(options, error, stackTrace);
}

final client = RestClient(dio, errorLogger: AppInspectParseErrorLogger());
```

Retrofit parses the response itself, so AppInspect can't see which field it read last. It lists the likely fields instead: values of the type the app got, such as every number with decimals when the app expected an `int`.

## Sharing

Without any setup, Share copies text to the clipboard. To send files, connect your share sheet:

```dart
AppInspect.wrap(
  const MyApp(),
  config: AppInspectConfig(
    // Markdown, or a file's contents when item.fileName is set (such as
    // ProductScreen.har). Hand it to share_plus or your own share sheet.
    onShare: (item) async { /* ... */ },
  ),
);
```

## Logs

The Logs tab shows, newest first and tagged with the screen:

- `debugPrint` output, and `print` output when the app runs in `AppInspect.runZoned`
- Flutter errors and uncaught errors, with stack traces
- failed calls and parse errors, linked to their call
- your own lines: `AppInspect.log('Checkout started', level: AppInspectLogLevel.info)`

AppInspect chains to the error handlers that are already set when you call `AppInspect.wrap`. If you set `FlutterError.onError` later (for example for Crashlytics), set it before `AppInspect.wrap` so both run.

## QA builds

QC usually tests release or profile builds. Turn AppInspect on for those with a compile-time flag:

```sh
flutter build apk --release --dart-define=APP_INSPECT=true
```

Builds without the flag don't contain AppInspect. `AppInspect.isEnabled` is a constant, so the compiler drops every code path behind it. Turn it off in debug with `--dart-define=APP_INSPECT=false`.

To lock the inspector in a build you share with clients:

```dart
AppInspect.wrap(const MyApp(), config: const AppInspectConfig(pin: '2468'));
```

## Screens that aren't routes

Bottom tabs and `PageView` pages don't push routes. Wrap them so their calls get their own name:

```dart
IndexedStack(
  index: tab,
  children: const [
    AppInspectScreen(name: 'ShopTab', child: ShopTab()),
    AppInspectScreen(name: 'AccountTab', child: AccountTab()),
  ],
);
```

Or call `AppInspect.markScreen('CartTab')` yourself.

Screens pushed without a route name are named after their widget, such as `ProductDetailsScreen`. AppInspect looks for the first widget on the route whose type ends in `Screen`, `Page` or `View`.

## Settings

```dart
AppInspectConfig(
  maxCalls: 300,                         // oldest calls are dropped first
  maxLogs: 1000,                         // oldest log entries are dropped first
  maxBodyChars: 500000,                  // longer bodies are cut
  slowThreshold: Duration(seconds: 1),   // slower calls are flagged
  maskedHeaders: {'authorization', 'cookie', 'x-session'},
  maskedBodyKeys: {'password', 'token', 'otp'}, // in JSON bodies and URL query parameters
  showBubble: true,                      // false: open with AppInspect.open()
  captureLogs: true,                     // debugPrint, Flutter and uncaught errors
  darkTheme: false,                      // true: start in the dark theme
);
```

AppInspect has no plugin dependencies, so it can't cause version conflicts in your app.

## Performance

- Capturing appends to a fixed-size list. Bodies are stored as they arrive and formatted only when someone opens a call.
- Large bodies are decoded on another isolate. The JSON viewer builds only the lines on screen.
- The UI updates at most once per frame, however many calls or log lines arrive. While the inspector is closed, only the bubble rebuilds.
- The `http` adapter copies the response as it streams to your code, up to `maxBodyChars`, so large downloads aren't held in memory twice.
- `AppInspect.parse` tracks which field `fromJson` reads, only in builds with AppInspect.

## What it captures

| Source | How |
| --- | --- |
| Dio | `AppInspectDioInterceptor` from `app_inspect_dio` |
| package:http | `AppInspectHttpClient` from `app_inspect_http` |
| Anything else | Call `AppInspect.store.startCall`, then `completeCall`, `failCall` or `cancelCall` |

Not captured: traffic from native SDKs (Firebase, payment SDKs) and clients that don't go through Dio or package:http.

## Known limits

- On Android, if your app opts in to predictive back (`android:enableOnBackInvokedCallback="true"`), a back gesture while the inspector is open can also pop your app's screen. The classic back button is handled correctly.
- `AppInspect.navigatorObserver` tracks one navigator: give it to your root navigator.
- With Dio, an interceptor before AppInspect that sends a request again, such as a token refresh, handles the first answer itself. AppInspect shows that attempt as `Retried`, followed by the new call.
- The inspector follows the system text size up to 1.3x, so it stays usable on small phones with very large text.

## Coming next

- Session timeline and GraphQL operation names.
- Fault injection, slow network and offline mode, edit and resend, compare two calls.
- Environment switcher, WebSocket frames, analytics events, and viewing a phone's session on a laptop.
