## 0.2.2

* Fixed: the bubble showed the number of failures instead of the number of API calls once something failed. It now always counts this screen's calls, and turns red when something fails.
* Fixed: a tab you came back to started again from zero calls. It now keeps its calls, the way a screen you go back to does.
* Fixed: copying JSON or cURL on a phone overflowed the button ("Copied" didn't fit), and on narrow phones the labels overflowed even before copying. The bar buttons now fit any width and text size, and only say "Copied" when copying worked.
* Fixed: a failed call with a long error message overflowed its status pill.
* Fixed: an error thrown while the app built a screen could make AppInspect change its bubble in the middle of the build, which broke that frame and hid the error from the app's own handler. AppInspect now waits for the frame to end. `AppInspect.open` and `close` are safe to call at any time too.
* Fixed: in landscape and on small phones, the call details hid the response under the action bar. The summary now scrolls away and the tabs stay pinned.
* Fixed: long debugPrint output and Flutter error reports were logged twice, once more as `print`, when the app ran in `AppInspect.runZoned`.
* Fixed: a route replaced below the top screen took over the calls of the screen on top. A route whose page is an `AppInspectScreen` was named "AppInspectScreen".
* Fixed: wrapping the app again, for example when it rebuilds, reset the theme and slow-call limit picked in Settings.
* Fixed: a zero slow-call limit and an instant call broke the timing bar. The HAR file for a screen named by a route, such as `/product/42`, got an invalid file name.
* Masking now covers URL query parameters too, such as `?token=` or `?api_key=`, on screen, in cURL, HAR, Postman, Markdown and the logs. It uses `maskedBodyKeys`.
* New: `AppInspectStore.cancelCall`, for a request the app cancels on purpose. It shows as `Cancelled` and doesn't count as a failure. `AppInspectCall.cancelled` tells them apart.
* The Logs tiles add up: Info covers debug entries too.
* The inspector follows the system text size up to 1.3x, so it stays usable on small phones with very large text.
* Bug reports are turned off for now: holding the bubble opens the inspector, and there's no bug button. `AppInspect.openReport` opens the inspector, and `AppInspectConfig.onReport` and `reportInfo` are deprecated and not called.

## 0.2.1

* Fixed: the package didn't compile with Flutter 3.47, where `CupertinoPageTransitionsBuilder` moved out of `material.dart`.
* Screenshots on the pub.dev page.
* Formatted the code with `dart format`, at 120 columns.

## 0.2.0

* Renamed from NetLens to AppInspect: the packages are app_inspect, app_inspect_dio and app_inspect_http, the classes start with AppInspect (such as AppInspectConfig), and the build flag is `--dart-define=APP_INSPECT=true`.
* Logs console: debugPrint, print (with AppInspect.runZoned), Flutter errors, uncaught errors and failed calls, tagged by screen.
* Parse errors linked to the response that caused them, with the exact field when parsing goes through AppInspect.parse.
* One-tap bug report: screenshot without AppInspect on top, this screen's calls, errors and device info. Hold the bubble to start one.
* Export calls as HAR files and Postman collections.
* Response sizes for decoded JSON that comes without one, such as Dio responses sent compressed or in chunks with no Content-Length. AppInspect works the size out off the UI thread when you open the call, and shows it as an estimate, like "≈ 12.3 KB", on the call list too. Capturing stays as cheap as before. New: `AppInspectStore.estimateResponseSize` and `AppInspectCall.responseSizeEstimated`.
* An open call stays smooth while the app keeps making calls. Its masked JSON and its cURL command are made once, not again for every new call, so JSON you unfold stays unfolded. The request size is worked out once, in UTF-8 bytes. Decoded JSON is measured off the UI thread and shown as an estimate, like "≈ 1.2 KB".
* Redesigned inspector, light by default: stat tiles that filter, sliding tabs, haptics, smooth page transitions, a frosted action bar and toasts. The dark theme is one tap away in Settings.
* The bubble springs to the nearest edge when you let go and pulses once for each new failure.
* JSON viewer: indent guides, and the field that broke parsing is marked "failed here".
* Breaking: onShare now receives a AppInspectShareItem.
* Changed: the inspector starts in its light theme. Pass `darkTheme: true` to start in the dark one.

## 0.1.0

* First release.
