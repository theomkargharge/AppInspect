/// Captures Dio requests for AppInspect, the QC-first network inspector.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:app_inspect/app_inspect.dart';

/// Records every Dio call in AppInspect.
///
/// Add it after your other interceptors, so AppInspect sees the headers they
/// add, such as the Authorization header:
///
/// ```dart
/// dio.interceptors
///   ..add(AuthInterceptor())
///   ..add(AppInspectDioInterceptor());
/// ```
///
/// It never changes or blocks a request. When AppInspect is off (production
/// builds), every method just passes the call on.
class AppInspectDioInterceptor extends Interceptor {
  /// Creates an interceptor that records the calls of the Dio it's added to.
  AppInspectDioInterceptor();

  static const String _callKey = 'app_inspect_call';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (AppInspect.isEnabled) {
      try {
        options.extra[_callKey] = AppInspect.store.startCall(
          method: options.method,
          uri: options.uri,
          headers: _flatten(options.headers),
          body: _requestBody(options.data),
          source: 'Dio',
        );
      } catch (_) {
        // Capturing must never break the request.
      }
    }
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    if (AppInspect.isEnabled) {
      try {
        _complete(response.requestOptions, response);
      } catch (_) {}
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (AppInspect.isEnabled) {
      try {
        final response = err.response;
        if (response != null) {
          // The server answered, with an error status. Keep its body.
          _complete(err.requestOptions, response);
        } else {
          final call = err.requestOptions.extra[_callKey];
          if (call is AppInspectCall) {
            AppInspect.store.failCall(
              call,
              error: plainError(err.type),
              detail: err.message ?? err.error?.toString(),
            );
          }
        }
      } catch (_) {}
    }
    handler.next(err);
  }

  void _complete(RequestOptions options, Response<dynamic> response) {
    final call = options.extra[_callKey];
    // Only the first completion counts. An interceptor after this one can
    // reject the response, which brings the same call back through onError.
    if (call is! AppInspectCall || !call.isPending) return;
    final headers = _flatten(response.headers.map);
    final data = response.data;
    // Compressed and chunked responses come without a Content-Length. For
    // decoded JSON, AppInspect then estimates the size when someone opens the
    // call, so capturing never has to encode the body.
    final size = int.tryParse(headers['content-length'] ?? '');
    AppInspect.store.completeCall(
      call,
      statusCode: response.statusCode ?? 0,
      headers: headers,
      body: _responseBody(data),
      size: size,
    );
    if (data is ResponseBody && size == null) {
      // The body is only a placeholder, so its length isn't the size.
      call.responseSize = null;
      _countBytes(call, data);
    }
  }

  /// Passes a streamed response on as it is, and counts its bytes as the app
  /// reads them. The size is filled in when the stream ends. It stays unknown
  /// if the stream fails or the app stops reading early.
  static void _countBytes(AppInspectCall call, ResponseBody body) {
    // A broadcast stream can have several listeners, some joining late, so no
    // single count is its size.
    if (body.stream.isBroadcast) return;
    var total = 0;
    var failed = false;
    body.stream = body.stream.transform(
      StreamTransformer<Uint8List, Uint8List>.fromHandlers(
        handleData: (chunk, sink) {
          total += chunk.length;
          sink.add(chunk);
        },
        handleError: (error, stack, sink) {
          failed = true;
          sink.addError(error, stack);
        },
        handleDone: (sink) {
          if (!failed) {
            try {
              call.responseSize = total;
              AppInspect.store.refresh();
            } catch (_) {}
          }
          sink.close();
        },
      ),
    );
  }

  /// Dio's error types in plain words, as shown to QC.
  static String plainError(DioExceptionType type) => switch (type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout =>
          'Timeout',
        DioExceptionType.connectionError => 'No connection',
        DioExceptionType.cancel => 'Cancelled',
        DioExceptionType.badCertificate => 'Bad certificate',
        DioExceptionType.badResponse => 'Bad response',
        // Newer Dio versions add types, such as transformTimeout.
        _ when type.name.contains('Timeout') => 'Timeout',
        _ => 'Request failed',
      };

  static Map<String, String> _flatten(Map<String, dynamic> headers) => {
        for (final e in headers.entries)
          if (e.value != null) e.key: e.value is List ? (e.value as List).join(', ') : '${e.value}',
      };

  static Object? _requestBody(Object? data) => switch (data) {
        null => null,
        FormData form => {
            'fields': {for (final f in form.fields) f.key: f.value},
            'files': [
              for (final f in form.files)
                {
                  'field': f.key,
                  'filename': f.value.filename,
                  'bytes': f.value.length,
                  'contentType': f.value.contentType?.toString(),
                },
            ],
          },
        Uint8List bytes => bytes,
        Stream<dynamic> _ => '<streamed body>',
        Map<dynamic, dynamic> _ || List<dynamic> _ || String _ || num _ || bool _ => data,
        _ => data.toString(),
      };

  static Object? _responseBody(Object? data) => switch (data) {
        ResponseBody _ => '<streamed response>',
        Uint8List bytes => bytes,
        _ => data,
      };
}

/// Parsing helpers for Dio responses, so AppInspect can point at the exact
/// field that broke when `fromJson` throws.
abstract final class AppInspectDio {
  /// The call AppInspect recorded for [options], if any.
  static AppInspectCall? callFor(RequestOptions options) {
    final call = options.extra[AppInspectDioInterceptor._callKey];
    return call is AppInspectCall ? call : null;
  }

  /// Parses [response] with [fromJson]. If it throws, AppInspect marks the call
  /// as a response the app couldn't read, names the field, and rethrows.
  ///
  /// ```dart
  /// final cart = AppInspectDio.parse(response, Cart.fromJson);
  /// ```
  ///
  /// In builds without AppInspect it just calls [fromJson].
  static T parse<T>(Response<dynamic> response, T Function(Map<String, dynamic> json) fromJson) => AppInspect.parse(
        response.data,
        fromJson,
        call: callFor(response.requestOptions),
        uri: response.requestOptions.uri,
      );

  /// Like [parse], for a response that's a JSON list of objects.
  static List<T> parseList<T>(Response<dynamic> response, T Function(Map<String, dynamic> json) fromJson) =>
      AppInspect.parseList(
        response.data,
        fromJson,
        call: callFor(response.requestOptions),
        uri: response.requestOptions.uri,
      );

  /// Links a parsing failure to its call when you parse responses yourself.
  /// With Retrofit, call it from your `ParseErrorLogger`:
  ///
  /// ```dart
  /// class AppInspectParseErrorLogger implements ParseErrorLogger {
  ///   @override
  ///   void logError(Object error, StackTrace stackTrace, RequestOptions options,
  ///           {Response<dynamic>? response}) =>
  ///       AppInspectDio.reportParseError(options, error, stackTrace);
  /// }
  /// ```
  static void reportParseError(RequestOptions options, Object error, StackTrace stackTrace) =>
      AppInspect.reportParseError(error, stackTrace, call: callFor(options), uri: options.uri);
}
