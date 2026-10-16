import 'package:flutter/foundation.dart';

import 'models.dart';

/// Something to share: Markdown, or the contents of a file such as a HAR
/// export.
@immutable
class AppInspectShareItem {
  const AppInspectShareItem({
    required this.text,
    required this.subject,
    this.fileName,
    this.mimeType = 'text/plain',
  });

  /// The text, or the file's contents when [fileName] is set.
  final String text;

  /// A short title, such as `GET /products/1`.
  final String subject;

  /// A file name such as `ProductScreen.har`, when [text] is a file's contents.
  final String? fileName;

  final String mimeType;

  bool get isFile => fileName != null;
}

/// Called when someone shares a call or an export.
///
/// Plug in `share_plus` or your own share sheet here. When it's not set,
/// AppInspect copies the text to the clipboard.
typedef AppInspectShareCallback = Future<void> Function(AppInspectShareItem item);

/// A bug report, built when QC taps "Send report".
@immutable
class AppInspectReport {
  const AppInspectReport({
    required this.title,
    required this.note,
    required this.markdown,
    required this.screen,
    required this.calls,
    required this.logs,
    required this.har,
    required this.logsText,
    this.screenshot,
  });

  /// Such as `Bug on ProductScreen`.
  final String title;

  /// What QC typed.
  final String note;

  /// The whole report, ready to paste into Jira, Slack or WhatsApp.
  final String markdown;

  /// The screen the report is about.
  final AppInspectVisit screen;

  /// The calls included in the report.
  final List<AppInspectCall> calls;

  /// The log entries included in the report.
  final List<AppInspectLog> logs;

  /// [calls] as a HAR file, for Chrome DevTools, Charles or Proxyman.
  final String har;

  /// [logs] as plain text.
  final String logsText;

  /// A PNG of the app, without AppInspect on top.
  final Uint8List? screenshot;
}

/// Called when QC sends a bug report. Send it to Jira, Slack or a share sheet.
/// When it's not set, AppInspect copies the report's Markdown to the clipboard.
typedef AppInspectReportCallback = Future<void> Function(AppInspectReport report);
