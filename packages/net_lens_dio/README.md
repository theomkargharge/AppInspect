# net_lens_dio

Captures [Dio](https://pub.dev/packages/dio) requests for [NetLens](../net_lens), the network inspector QC can use on their own.

```dart
dio.interceptors.add(NetLensDioInterceptor());
```

Add it after your other interceptors, so NetLens sees the headers they add, such as `Authorization`.

- It never changes, delays or blocks a request.
- Error responses keep their body, so QC can see what the server said.
- Failures without a response get plain words: `Timeout`, `No connection`, `Cancelled`.
- File uploads are described by name and size. The file itself isn't kept.
- In builds without NetLens, every method just passes the call on.

## Parse errors

Parse responses through NetLens, and a failure is linked to its call with the exact field:

```dart
final cart = NetLensDio.parse(response, Cart.fromJson);
final items = NetLensDio.parseList(response, Item.fromJson);
```

With Retrofit, report from its `ParseErrorLogger`:

```dart
class NetLensParseErrorLogger implements ParseErrorLogger {
  @override
  void logError(Object error, StackTrace stackTrace, RequestOptions options, {Response<dynamic>? response}) =>
      NetLensDio.reportParseError(options, error, stackTrace);
}
```

See the [NetLens README](../net_lens/README.md) for setup.
