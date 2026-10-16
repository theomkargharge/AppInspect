## 0.2.0

* Renamed from net_lens_dio. The interceptor is now AppInspectDioInterceptor.
* AppInspectDio.parse and parseList: parse a response and link a failure to its call, with the exact field.
* AppInspectDio.reportParseError, for Retrofit's ParseErrorLogger.
* Fixed: a streamed response (`ResponseType.stream`, such as a download) without a Content-Length showed "19 B", the length of its placeholder. AppInspect now counts the bytes as your app reads the stream and shows the size once it ends. The bytes your app gets are unchanged.

## 0.1.0

* First release.
