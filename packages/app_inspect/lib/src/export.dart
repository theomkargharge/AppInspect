import 'dart:convert';

import 'format.dart';
import 'models.dart';
import 'timeline.dart';
import 'version.dart';

const JsonEncoder _pretty = JsonEncoder.withIndent('  ');

String _text(Object? body, AppInspectMasker masker) {
  final decoded = decodeBody(body);
  if (decoded == null) return '';
  return decoded is String ? decoded : encodeBody(masker.json(decoded), pretty: false);
}

String _mimeOf(Map<String, String> headers, String fallback) {
  for (final e in headers.entries) {
    if (e.key.toLowerCase() == 'content-type') return e.value;
  }
  return fallback;
}

/// [calls] as a HAR 1.2 file, which opens in Chrome DevTools, Charles,
/// Proxyman and Postman. Masked values stay masked. Pending calls are skipped.
///
/// Each entry also carries the screen name in `_screen`, and the problem in
/// plain words in `_issue` when there is one.
String buildHar(List<AppInspectCall> calls, AppInspectMasker masker) {
  List<Map<String, String>> headerList(Map<String, String> h) => [
        for (final e in h.entries) {'name': e.key, 'value': masker.header(e.key, e.value)},
      ];
  final entries = [
    for (final c in calls.where((c) => !c.isPending))
      () {
        final requestText = _text(c.requestBody, masker);
        final responseText = _text(c.responseBody, masker);
        return {
          'startedDateTime': c.startedAt.toUtc().toIso8601String(),
          'time': c.duration?.inMilliseconds ?? 0,
          'request': {
            'method': c.method,
            'url': masker.url(c.uri),
            'httpVersion': 'HTTP/1.1',
            'cookies': <Object>[],
            'headers': headerList(c.requestHeaders),
            'queryString': [
              for (final e in c.uri.queryParametersAll.entries)
                for (final v in e.value) {'name': e.key, 'value': masker.isMaskedKey(e.key) ? appInspectMask : v},
            ],
            if (requestText.isNotEmpty)
              'postData': {'mimeType': _mimeOf(c.requestHeaders, 'application/json'), 'text': requestText},
            'headersSize': -1,
            'bodySize': requestText.length,
          },
          'response': {
            'status': c.statusCode ?? 0,
            'statusText': c.statusCode == null || c.statusCode == 0
                ? (c.error ?? '')
                : AppInspectCall.describeStatus(c.statusCode!),
            'httpVersion': 'HTTP/1.1',
            'cookies': <Object>[],
            'headers': headerList(c.responseHeaders),
            'content': {
              'size': c.responseSize ?? responseText.length,
              'mimeType': _mimeOf(c.responseHeaders, 'application/json'),
              'text': responseText,
            },
            'redirectURL': '',
            'headersSize': -1,
            'bodySize': c.responseSize ?? responseText.length,
          },
          'cache': <String, Object>{},
          'timings': {'send': 0, 'wait': c.duration?.inMilliseconds ?? 0, 'receive': 0},
          '_screen': c.visit.name,
          if (c.graphQL case final graphQL?) '_graphql': graphQL.label,
          if (c.isError) '_issue': _issue(c),
        };
      }(),
  ];
  return _pretty.convert({
    'log': {
      'version': '1.2',
      'creator': {'name': 'AppInspect', 'version': appInspectVersion},
      'entries': entries,
    },
  });
}

/// The problem with a failed call in plain words.
String _issue(AppInspectCall c) {
  if (c.parseError case final error?) return describeParseError(c, error);
  if (c.graphQLErrors.isNotEmpty) return '${c.statusLabel}, GraphQL errors: ${describeGraphQLErrors(c.graphQLErrors)}';
  return c.statusLabel;
}

/// [calls] as a Postman collection (v2.1), so the backend team can send the
/// same requests. Masked values stay masked. A GraphQL operation opens in
/// Postman's GraphQL editor, with its variables.
String buildPostmanCollection(List<AppInspectCall> calls, AppInspectMasker masker, {required String name}) {
  Map<String, Object?> body(AppInspectCall c) {
    final graphQL = c.graphQL;
    final query = graphQL?.query;
    if (graphQL != null && query != null && graphQL.batchSize == 1) {
      final variables = graphQL.variables;
      return {
        'mode': 'graphql',
        'graphql': {
          'query': query,
          'variables': variables == null ? '' : encodeBody(masker.json(variables)),
        },
      };
    }
    return {
      'mode': 'raw',
      'raw': _text(c.requestBody, masker),
      'options': {
        'raw': {'language': 'json'},
      },
    };
  }

  return _pretty.convert({
    'info': {
      'name': name,
      'schema': 'https://schema.getpostman.com/json/collection/v2.1.0/collection.json',
    },
    'item': [
      for (final c in calls)
        {
          'name': callTitle(c, masker),
          'request': {
            'method': c.method,
            'header': [
              for (final e in c.requestHeaders.entries) {'key': e.key, 'value': masker.header(e.key, e.value)},
            ],
            'url': masker.url(c.uri),
            if (c.requestBody != null) 'body': body(c),
          },
        },
    ],
  });
}

String _levelLetter(AppInspectLogLevel level) => switch (level) {
      AppInspectLogLevel.debug => 'D',
      AppInspectLogLevel.info => 'I',
      AppInspectLogLevel.warning => 'W',
      AppInspectLogLevel.error => 'E',
    };

/// [logs] as plain text, one entry per line, with stack traces indented.
String logsToText(List<AppInspectLog> logs) {
  final out = StringBuffer();
  for (final l in logs) {
    out.writeln('${formatTime(l.time)} ${_levelLetter(l.level)} [${l.source}] ${l.visit.name}: ${l.message}');
    final details = l.details;
    if (details != null && details.isNotEmpty) {
      for (final line in const LineSplitter().convert(details)) {
        out.writeln('    $line');
      }
    }
  }
  return out.toString();
}

/// A bug report in Markdown, ready for Jira, Slack or WhatsApp.
String buildReportMarkdown({
  required AppInspectVisit screen,
  required String note,
  required List<AppInspectCall> calls,
  required List<AppInspectLog> logs,
  required Map<String, String> info,
  required AppInspectMasker masker,
  required Duration slowThreshold,
  DateTime? now,
}) {
  final out = StringBuffer('## Bug on ${screen.name}\n');
  final trimmed = note.trim();
  if (trimmed.isNotEmpty) out.write('\n$trimmed\n');

  if (info.isNotEmpty) {
    out.write('\n');
    info.forEach((k, v) => out.writeln('- **$k:** $v'));
  }
  out.writeln('- **Reported:** ${(now ?? DateTime.now()).toIso8601String().substring(0, 19).replaceFirst('T', ' ')}');

  if (calls.isNotEmpty) {
    out
      ..writeln('\n### API calls on this screen')
      ..writeln('| Call | Status | Time | Issue |')
      ..writeln('| --- | --- | --- | --- |');
    for (final c in calls) {
      final issues = insightsFor(c, slowThreshold: slowThreshold).map((i) => i.title).join(', ');
      out.writeln('| `${callTitle(c, masker)}` | ${c.statusLabel} | ${formatDuration(c.duration)} | '
          '${issues.isEmpty ? '—' : issues} |');
    }
    for (final c in calls.where((c) => c.isError)) {
      out
        ..writeln('\n#### ${callTitle(c, masker)} · ${c.statusLabel}')
        ..writeln(c.parseError != null || c.graphQLErrors.isNotEmpty ? _issue(c) : '')
        ..writeln('```bash')
        ..writeln(buildCurl(c, masker))
        ..writeln('```');
      final body = _text(c.responseBody, masker);
      if (body.isNotEmpty) {
        out
          ..writeln('Response:')
          ..writeln('```json')
          ..writeln(body.length > 2000 ? '${body.substring(0, 2000)}…' : body)
          ..writeln('```');
      }
    }
  }

  if (logs.isNotEmpty) {
    out
      ..writeln('\n### Errors and warnings')
      ..writeln('```')
      ..write(logsToText(logs))
      ..writeln('```');
  }
  return out.toString();
}

/// The session as numbered steps in Markdown, oldest first: the screens
/// people moved to, the calls each made and what the logs said, with failed
/// and slow calls marked. Paste it into a bug report as the steps that led to
/// the bug. Masked values stay masked.
///
/// Only the last [maxEntries] steps are kept, so the text stays short enough
/// for a chat message.
String buildTimelineMarkdown({
  required List<AppInspectScreenChange> screens,
  required List<AppInspectCall> calls,
  required List<AppInspectLog> logs,
  required AppInspectMasker masker,
  required Duration slowThreshold,
  int maxEntries = 200,
}) {
  final all = buildTimeline(screens: screens, calls: calls, logs: logs);
  final shown = all.length > maxEntries ? all.sublist(all.length - maxEntries) : all;
  final out = StringBuffer('## Session timeline\n\n');
  if (shown.isEmpty) return '${out}Nothing happened yet.\n';
  if (shown.length < all.length) out.write('_The last ${shown.length} of ${all.length} steps._\n\n');
  for (final (i, entry) in shown.indexed) {
    out.write('${i + 1}. ${formatTime(entry.time)} ');
    switch (entry) {
      case ScreenEntry(:final change):
        out.write('${change.returned ? 'Back to' : 'Opened'} **${change.visit.name}**');
      case CallEntry(:final call):
        out.write('`${callTitle(call, masker)}` → ${call.statusLabel}');
        if (!call.isPending) out.write(', ${formatDuration(call.duration)}');
        final problems = [
          if (call.parseError != null) 'parse error',
          if (call.graphQLErrors.isNotEmpty) 'GraphQL error: ${describeGraphQLErrors(call.graphQLErrors)}',
          if (call.isError && call.parseError == null && call.graphQLErrors.isEmpty) 'failed',
          if (call.isSlow(slowThreshold)) 'slow',
        ];
        if (problems.isNotEmpty) out.write(' · **${problems.join(', ')}**');
      case LogEntry(:final log):
        final line = log.message.split('\n').first.trim();
        final level = switch (log.level) {
          AppInspectLogLevel.debug => 'Debug',
          AppInspectLogLevel.info => 'Log',
          AppInspectLogLevel.warning => '**Warning**',
          AppInspectLogLevel.error => '**Error**',
        };
        out.write('$level (${log.source}): ${line.length > 160 ? '${line.substring(0, 160)}…' : line}');
    }
    out.writeln();
  }
  return out.toString();
}
