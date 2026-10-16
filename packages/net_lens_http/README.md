# net_lens_http

Captures [package:http](https://pub.dev/packages/http) requests for [NetLens](../net_lens), the network inspector QC can use on their own.

```dart
final client = NetLensHttpClient();          // wraps http.Client()
final client = NetLensHttpClient(myClient);  // wraps your own client
```

- The response body is copied as it streams to your code, up to `NetLensConfig.maxBodyChars`, so large downloads aren't held in memory twice.
- Failures get plain words, such as `No connection` and `Timeout`, and are rethrown unchanged.
- Multipart uploads are described by field, file name and size.
- In builds without NetLens, calls go straight to the inner client.

See the [NetLens README](../net_lens/README.md) for setup.
