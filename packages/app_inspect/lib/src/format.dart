import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'config.dart';
import 'models.dart';

/// What a masked value looks like on screen and in exports.
const String appInspectMask = '••••••••';

/// Masks sensitive headers and JSON keys. Masking happens when a call is
/// shown or exported, never at capture time, so a developer can still reveal
/// a value on the device.
class AppInspectMasker {
  const AppInspectMasker(this.config, {this.enabled = true});

  final AppInspectConfig config;
  final bool enabled;

  bool isMaskedHeader(String name) =>
      enabled && config.maskedHeaders.contains(name.toLowerCase());

  bool isMaskedKey(String key) => enabled && config.maskedBodyKeys.contains(key.toLowerCase());

  /// Keeps the scheme and the first characters of a bearer token, so people
  /// can tell tokens apart without seeing them.
  String header(String name, String value) {
    if (!isMaskedHeader(name)) return value;
    if (value.toLowerCase().startsWith('bearer ') && value.length > 11) {
      return '${value.substring(0, 11)}$appInspectMask';
    }
    return appInspectMask;
  }

  Map<String, String> headers(Map<String, String> headers) => {
        for (final e in headers.entries) e.key: header(e.key, e.value),
      };

  /// Masks the values of sensitive keys anywhere in decoded JSON.
  Object? json(Object? value) {
    if (!enabled) return value;
    if (value is Map) {
      return {
        for (final e in value.entries)
          e.key: e.key is String && isMaskedKey(e.key as String) ? appInspectMask : json(e.value),
      };
    }
    if (value is List) return [for (final v in value) json(v)];
    return value;
  }
}

/// Turns a stored body into something to show: decoded JSON when the text is
/// JSON, the text otherwise, and a short note for binary data.
Object? decodeBody(Object? body) {
  if (body is String) {
    final start = body.trimLeft();
    if (start.startsWith('{') || start.startsWith('[')) {
      try {
        return jsonDecode(body);
      } on FormatException {
        return body;
      }
    }
    return body;
  }
  if (body is List<int>) return '<${body.length} bytes of binary data>';
  return body;
}

/// Same as [decodeBody], but large text is decoded on another isolate so the
/// inspector never janks on a big response.
Future<Object?> decodeBodyAsync(Object? body) {
  if (body is String && body.length > 100000) return compute(decodeBody, body);
  return SynchronousFuture<Object?>(decodeBody(body));
}

/// The size in bytes of decoded JSON, written as compact UTF-8 JSON the way
/// most servers send it. Worked out on another isolate, so a big body never
/// janks the inspector. Null for a body that isn't a JSON map or list, or one
/// that can't be sent to an isolate.
Future<int?> jsonSizeAsync(Object? decoded) async {
  if (decoded is! Map && decoded is! List) return null;
  try {
    return await compute(_jsonByteCount, decoded, debugLabel: 'AppInspect body size');
  } catch (_) {
    return null;
  }
}

int _jsonByteCount(Object? decoded) {
  final counter = _ByteCounter();
  JsonUtf8Encoder(null, (o) => o.toString()).startChunkedConversion(counter)
    ..add(decoded)
    ..close();
  return counter.count;
}

/// How many bytes [text] takes as UTF-8, counted without keeping them.
int _utf8Length(String text) {
  final counter = _ByteCounter();
  utf8.encoder.startChunkedConversion(counter)
    ..add(text)
    ..close();
  return counter.count;
}

/// Counts the bytes written to it, without keeping them.
class _ByteCounter extends ByteConversionSink {
  int count = 0;

  @override
  void add(List<int> chunk) => count += chunk.length;

  @override
  void addSlice(List<int> chunk, int start, int end, bool isLast) => count += end - start;

  @override
  void close() {}
}

/// Pretty JSON for decoded bodies, the text itself for text bodies.
String encodeBody(Object? decoded, {bool pretty = true}) {
  if (decoded == null) return '';
  if (decoded is String) return decoded;
  final encoder = pretty
      ? JsonEncoder.withIndent('  ', (o) => o.toString())
      : JsonEncoder((o) => o.toString());
  return encoder.convert(decoded);
}

/// A cURL command that repeats [call]. Masked values stay masked.
String buildCurl(AppInspectCall call, AppInspectMasker masker) {
  final out = StringBuffer("curl -X ${call.method} '${_quote(call.uri.toString())}'");
  call.requestHeaders.forEach((name, value) {
    out.write(" \\\n  -H '${_quote('$name: ${masker.header(name, value)}')}'");
  });
  final body = call.requestBody;
  if (body != null) {
    final decoded = decodeBody(body);
    final text = decoded is String ? decoded : encodeBody(masker.json(decoded), pretty: false);
    out.write(" \\\n  --data-raw '${_quote(text)}'");
  }
  return out.toString();
}

String _quote(String s) => s.replaceAll("'", r"'\''");

String formatDuration(Duration? d) {
  if (d == null) return '…';
  final ms = d.inMilliseconds;
  return ms >= 1000 ? '${(ms / 1000).toStringAsFixed(1)} s' : '$ms ms';
}

String formatSize(int? bytes) {
  if (bytes == null) return '—';
  if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '$bytes B';
}

/// The response size, such as `12.3 KB`, or `≈ 12.3 KB` when AppInspect
/// estimated it.
String formatResponseSize(AppInspectCall call) {
  final size = formatSize(call.responseSize);
  return call.responseSizeEstimated && call.responseSize != null ? '≈ $size' : size;
}

/// The request size, such as `312 B`. Text is counted in UTF-8 bytes and
/// binary data as it is. Decoded JSON is written out as compact UTF-8 JSON on
/// another isolate, like [jsonSizeAsync], and shown as an estimate, such as
/// `≈ 1.2 KB`. Any other value is written out the same way, right away. The
/// future completes at once when no isolate is needed.
Future<String> formatRequestSize(Object? body) => switch (body) {
      null => SynchronousFuture(formatSize(null)),
      final String text => SynchronousFuture(formatSize(_utf8Length(text))),
      final List<int> bytes => SynchronousFuture(formatSize(bytes.length)),
      Map() || List() => jsonSizeAsync(body).then(_estimatedSize),
      _ => SynchronousFuture(_estimatedSize(_jsonByteCount(body))),
    };

String _estimatedSize(int? bytes) => bytes == null ? formatSize(null) : '≈ ${formatSize(bytes)}';

String formatTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

/// How serious an insight is.
enum AppInspectInsightLevel { error, warning, info }

/// A plain-language note about a call, shown above its details.
@immutable
class AppInspectInsight {
  const AppInspectInsight(this.level, this.title, this.detail);

  final AppInspectInsightLevel level;
  final String title;
  final String detail;
}

/// What QC and developers should know about [call], most serious first.
List<AppInspectInsight> insightsFor(AppInspectCall call, {required Duration slowThreshold}) {
  final out = <AppInspectInsight>[];
  final code = call.statusCode ?? 0;
  final parseError = call.parseError;
  if (parseError != null) {
    out.add(AppInspectInsight(
      AppInspectInsightLevel.error,
      'The app couldn\'t read this response',
      describeParseError(call, parseError),
    ));
  }
  if (call.state == AppInspectCallState.failed && code == 0) {
    out.add(switch (call.error) {
      'Timeout' => AppInspectInsight(AppInspectInsightLevel.error, 'No response in time',
          'The app stopped waiting after ${formatDuration(call.duration)}.'),
      'No connection' => const AppInspectInsight(AppInspectInsightLevel.error, 'Couldn\'t reach the server',
          'Check the internet connection and the base URL. Nothing reached the backend.'),
      'Cancelled' => const AppInspectInsight(AppInspectInsightLevel.info, 'Cancelled by the app',
          'The app cancelled this request before it finished.'),
      _ => AppInspectInsight(AppInspectInsightLevel.error, 'Request failed',
          call.errorDetail ?? call.error ?? 'No details.'),
    });
  } else if (code >= 500) {
    out.add(const AppInspectInsight(AppInspectInsightLevel.error, 'Server error',
        'The problem is on the backend. Copy the cURL and send it to them.'));
  } else if (code == 401 || code == 403) {
    out.add(const AppInspectInsight(AppInspectInsightLevel.warning, 'Not allowed',
        'The token may be missing or expired. Check the Authorization header.'));
  } else if (code >= 400) {
    out.add(const AppInspectInsight(AppInspectInsightLevel.warning, 'The server rejected this request',
        'Check the URL, the body and the headers.'));
  }
  if (call.isSlow(slowThreshold)) {
    out.add(AppInspectInsight(AppInspectInsightLevel.warning, 'Slow call',
        'Took ${formatDuration(call.duration)}. Your limit is ${formatDuration(slowThreshold)}.'));
  }
  if (call.isRepeated) {
    out.add(AppInspectInsight(AppInspectInsightLevel.info, 'Called ${call.repeatCount} times in a row',
        'Look for an API call inside build(), or a FutureBuilder that creates a new future on every rebuild.'));
  }
  if (call.bodyTruncated) {
    out.add(const AppInspectInsight(AppInspectInsightLevel.info, 'Body cut short',
        'The response was longer than the size limit, so only the start is kept.'));
  }
  return out;
}

/// The call as Markdown, ready for Slack, Jira or WhatsApp.
String callToMarkdown(AppInspectCall call, AppInspectMasker masker, {required Duration slowThreshold}) {
  final issues = insightsFor(call, slowThreshold: slowThreshold);
  final response = decodeBody(call.responseBody);
  final responseText = response is String ? response : encodeBody(masker.json(response));
  final parseError = call.parseError;
  return [
    '**${call.method} ${call.path}** · ${call.statusLabel} · ${formatDuration(call.duration)}',
    'Screen: ${call.visit.name} · ${formatTime(call.startedAt)} · captured by ${call.source}',
    'Issue: ${issues.isEmpty ? 'No issues found' : issues.map((i) => i.title).join(', ')}',
    if (parseError != null) 'Details: ${describeParseError(call, parseError)}',
    '',
    '```bash',
    buildCurl(call, masker),
    '```',
    '',
    'Response:',
    '```json',
    responseText.isEmpty ? '(empty)' : responseText,
    '```',
  ].join('\n');
}

/// A parse error in one plain sentence or two, for QC and the backend team.
String describeParseError(AppInspectCall call, AppInspectParseError error) {
  final out = StringBuffer('The server answered ${call.statusLabel}, but the app failed');
  if (error.field != null) out.write(' at ${error.field}');
  if (error.expected != null && error.got != null) {
    out.write(': expected ${error.expected}, got ${error.got}.');
  } else {
    out.write(': ${error.message}');
    if (!error.message.endsWith('.')) out.write('.');
  }
  if (error.field == null && error.likelyFields.isNotEmpty) {
    out.write(' Likely field: ${error.likelyFields.join(', ')}.');
  }
  if (error.where != null) out.write(' In ${error.where}.');
  return out.toString();
}

final RegExp _simpleKey = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');

/// Adds [key] to a JSON path: `data` + `price` gives `data.price`. Keys that
/// aren't simple names use brackets, such as `data["first name"]`.
String joinJsonPath(String path, String key) {
  if (!_simpleKey.hasMatch(key)) return '$path["${key.replaceAll('"', r'\"')}"]';
  return path.isEmpty ? key : '$path.$key';
}
