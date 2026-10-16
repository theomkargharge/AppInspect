/// Captures package:http requests for NetLens, the QC-first network inspector.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:net_lens/net_lens.dart';

/// An `http.Client` that records every call in NetLens.
///
/// ```dart
/// final client = NetLensHttpClient();            // wraps http.Client()
/// final client = NetLensHttpClient(myClient);    // wraps your own client
/// ```
///
/// The response body is copied as it streams to your code, up to
/// `NetLensConfig.maxBodyChars`, so a large download isn't held in memory.
/// When NetLens is off (production builds), calls go straight to the inner
/// client.
class NetLensHttpClient extends http.BaseClient {
  NetLensHttpClient([http.Client? inner]) : _inner = inner ?? http.Client();

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!NetLens.isEnabled) return _inner.send(request);

    NetLensCall? call;
    try {
      call = NetLens.store.startCall(
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

  http.StreamedResponse _tee(NetLensCall call, http.StreamedResponse response) {
    final limit = NetLens.config.maxBodyChars;
    final kept = BytesBuilder(copy: false);
    var total = 0;
    var cut = false;
    final stream = response.stream.transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (chunk, sink) {
          total += chunk.length;
          final room = limit - kept.length;
          if (room > 0) {
            kept.add(chunk.length <= room ? chunk : chunk.sublist(0, room));
          }
          if (chunk.length > room) cut = true;
          sink.add(chunk);
        },
        handleError: (error, stack, sink) {
          _fail(call, error);
          sink.addError(error, stack);
        },
        handleDone: (sink) {
          try {
            NetLens.store.completeCall(
              call,
              statusCode: response.statusCode,
              headers: response.headers,
              body: _decode(kept.takeBytes(), response.headers['content-type']),
              size: total,
            );
            if (cut) call.bodyTruncated = true;
          } catch (_) {}
          sink.close();
        },
      ),
    );
    return http.StreamedResponse(
      stream,
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  static void _fail(NetLensCall call, Object error) {
    try {
      NetLens.store.failCall(call, error: plainError(error), detail: error.toString());
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
