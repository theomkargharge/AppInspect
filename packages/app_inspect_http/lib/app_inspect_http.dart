/// Captures package:http requests for AppInspect, the QC-first network inspector.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:app_inspect/app_inspect.dart';

/// An `http.Client` that records every call in AppInspect.
///
/// ```dart
/// final client = AppInspectHttpClient();            // wraps http.Client()
/// final client = AppInspectHttpClient(myClient);    // wraps your own client
/// ```
///
/// The response body is copied as it streams to your code, up to
/// `AppInspectConfig.maxBodyChars`, so a large download isn't held in memory.
/// When AppInspect is off (production builds), calls go straight to the inner
/// client.
class AppInspectHttpClient extends http.BaseClient {
  /// Wraps [inner], or a new `http.Client()` when it's null. Closing this
  /// client closes [inner].
  AppInspectHttpClient([http.Client? inner]) : _inner = inner ?? http.Client();

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!AppInspect.isEnabled) return _inner.send(request);

    AppInspectCall? call;
    try {
      call = AppInspect.store.startCall(
        method: request.method,
        uri: request.url,
        headers: request.headers,
        body: _requestBody(request),
        source: 'http',
      );
    } catch (_) {
      // Capturing must never break the request.
    }

    final http.StreamedResponse response;
    try {
      response = await _inner.send(request);
    } catch (e) {
      if (call != null) _fail(call, e);
      rethrow;
    }
    if (call == null) return response;
    return _tee(call, response);
  }

  http.StreamedResponse _tee(AppInspectCall call, http.StreamedResponse response) {
    final limit = AppInspect.config.maxBodyChars;
    final kept = BytesBuilder(copy: false);
    var total = 0;
    var cut = false;
    var finished = false;

    // Records the response once: when the body has all arrived, or when the
    // app stops reading it early, which would otherwise leave the call
    // pending forever.
    void finish({required bool early}) {
      if (finished) return;
      finished = true;
      try {
        AppInspect.store.completeCall(
          call,
          statusCode: response.statusCode,
          headers: response.headers,
          body: _decode(kept.takeBytes(), response.headers['content-type']),
          size: early ? response.contentLength : total,
        );
        if (cut || early) call.bodyTruncated = true;
      } catch (_) {}
    }

    late final StreamSubscription<List<int>> source;
    final controller = StreamController<List<int>>(sync: true);
    controller
      ..onListen = () {
        source = response.stream.listen(
          (chunk) {
            total += chunk.length;
            final room = limit - kept.length;
            if (room > 0) {
              kept.add(chunk.length <= room ? chunk : chunk.sublist(0, room));
            }
            if (chunk.length > room) cut = true;
            controller.add(chunk);
          },
          onError: (Object error, StackTrace stack) {
            if (!finished) {
              finished = true;
              _fail(call, error);
            }
            controller.addError(error, stack);
          },
          onDone: () {
            finish(early: false);
            controller.close();
          },
        );
      }
      ..onPause = (() => source.pause())
      ..onResume = (() => source.resume())
      ..onCancel = () {
        finish(early: true);
        return source.cancel();
      };
    return http.StreamedResponse(
      controller.stream,
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  static void _fail(AppInspectCall call, Object error) {
    try {
      AppInspect.store.failCall(call, error: plainError(error), detail: error.toString());
    } catch (_) {}
  }

  /// Common failures in plain words, as shown to QC.
  static String plainError(Object error) {
    if (error is TimeoutException) return 'Timeout';
    final text = error.toString();
    if (text.contains('SocketException') ||
        text.contains('Failed host lookup') ||
        text.contains('Connection refused') ||
        text.contains('Network is unreachable') ||
        text.contains('XMLHttpRequest error')) {
      return 'No connection';
    }
    if (text.contains('HandshakeException') || text.contains('CERTIFICATE_VERIFY_FAILED')) {
      return 'Bad certificate';
    }
    return 'Request failed';
  }

  static Object? _requestBody(http.BaseRequest request) => switch (request) {
        http.Request r when r.bodyBytes.isEmpty => null,
        http.Request r => _decode(r.bodyBytes, r.headers['content-type']),
        http.MultipartRequest r => {
            'fields': r.fields,
            'files': [
              for (final f in r.files)
                {'field': f.field, 'filename': f.filename, 'bytes': f.length, 'contentType': '${f.contentType}'},
            ],
          },
        _ => '<streamed body>',
      };

  /// Text for text types, the bytes otherwise.
  static Object? _decode(Uint8List bytes, String? contentType) {
    if (bytes.isEmpty) return null;
    final type = (contentType ?? '').toLowerCase();
    final isText = type.isEmpty ||
        type.startsWith('text/') ||
        type.contains('json') ||
        type.contains('xml') ||
        type.contains('javascript') ||
        type.contains('x-www-form-urlencoded') ||
        type.contains('charset');
    return isText ? utf8.decode(bytes, allowMalformed: true) : bytes;
  }

  @override
  void close() => _inner.close();
}
