# app_inspect_dio

Captures [Dio](https://pub.dev/packages/dio) requests for [AppInspect](../app_inspect), the network inspector QC can use on their own.

```dart
dio.interceptors.add(AppInspectDioInterceptor());
```

Add it after your other interceptors, so AppInspect sees the headers they add, such as `Authorization`.

- It never changes, delays or blocks a request.
- Error responses keep their body, so QC can see what the server said.
- Failures without a response get plain words: `Timeout`, `No connection`, `Cancelled`.
- File uploads are described by name and size. The file itself isn't kept.
- In builds without AppInspect, every method just passes the call on.

## Parse errors

Parse responses through AppInspect, and a failure is linked to its call with the exact field:

```dart
final cart = AppInspectDio.parse(response, Cart.fromJson);
final items = AppInspectDio.parseList(response, Item.fromJson);
```

With Retrofit, report from its `ParseErrorLogger`:

```dart
class AppInspectParseErrorLogger implements ParseErrorLogger {
  @override
  void logError(Object error, StackTrace stackTrace, RequestOptions options, {Response<dynamic>? response}) =>
      AppInspectDio.reportParseError(options, error, stackTrace);
}
```

See the [AppInspect README](../app_inspect/README.md) for setup.
