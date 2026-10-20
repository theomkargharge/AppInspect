## 0.2.2

* Fixed: a request the app cancelled, such as a search that was typed over, counted as a failure and turned the bubble red. It now shows as `Cancelled`.
* Fixed: when an interceptor before AppInspect sent a request again, such as after a token refresh, the first attempt stayed pending forever. It now shows as `Retried`, followed by the new call.
* Needs app_inspect 0.2.2.

## 0.2.1

* Added an example.
* Documented the AppInspectDioInterceptor constructor.

## 0.2.0

* Renamed from net_lens_dio. The interceptor is now AppInspectDioInterceptor.
* AppInspectDio.parse and parseList: parse a response and link a failure to its call, with the exact field.
* AppInspectDio.reportParseError, for Retrofit's ParseErrorLogger.
* Fixed: a streamed response (`ResponseType.stream`, such as a download) without a Content-Length showed "19 B", the length of its placeholder. AppInspect now counts the bytes as your app reads the stream and shows the size once it ends. The bytes your app gets are unchanged.

## 0.1.0

* First release.
