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
