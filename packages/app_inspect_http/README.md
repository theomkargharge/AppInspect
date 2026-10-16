# app_inspect_http

Captures [package:http](https://pub.dev/packages/http) requests for [AppInspect](../app_inspect), the network inspector QC can use on their own.

```dart
final client = AppInspectHttpClient();          // wraps http.Client()
final client = AppInspectHttpClient(myClient);  // wraps your own client
```

- The response body is copied as it streams to your code, up to `AppInspectConfig.maxBodyChars`, so large downloads aren't held in memory twice.
- Failures get plain words, such as `No connection` and `Timeout`, and are rethrown unchanged.
- Multipart uploads are described by field, file name and size.
- In builds without AppInspect, calls go straight to the inner client.

See the [AppInspect README](../app_inspect/README.md) for setup.
