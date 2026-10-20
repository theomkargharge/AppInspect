import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../export.dart';
import '../models.dart';
import '../app_inspect.dart';
import '../sharing.dart';
import 'kit.dart';
import 'kit_controls.dart';
import 'theme.dart';
import 'widgets.dart';

enum _SendState { idle, sending, done }

/// One-tap bug report: a screenshot, this screen's calls, its errors and
/// warnings, and device info, as Markdown with files attached.
///
/// Turned off for now: nothing in the inspector opens this page.
class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  final TextEditingController _note = TextEditingController();
  late final AppInspectVisit _screen = AppInspect.store.currentVisit;
  late final Future<Uint8List?> _screenshot = AppInspect.captureScreenshot();
  late final Map<String, String> _info = appInspectReportInfo();
  bool _withCalls = true;
  bool _withLogs = true;
  bool _withInfo = true;
  bool _previewOpen = false;
  _SendState _state = _SendState.idle;
  Timer? _reset;

  @override
  void dispose() {
    _note.dispose();
    _reset?.cancel();
    super.dispose();
  }

  List<AppInspectCall> get _allCalls => AppInspect.store.callsFor(_screen);

  List<AppInspectLog> get _problems => AppInspect.store.logs
      .where((l) => identical(l.visit, _screen) && l.level.index >= AppInspectLogLevel.warning.index)
      .toList();

  String _markdown() => buildReportMarkdown(
        screen: _screen,
        note: _note.text,
        calls: _withCalls ? _allCalls : const [],
        logs: _withLogs ? _problems : const [],
        info: _withInfo ? _info : const {},
        masker: currentMasker(),
        slowThreshold: AppInspect.slowThreshold.value,
      );

  Future<void> _send() async {
    final markdown = _markdown();
    // ignore: deprecated_member_use_from_same_package
    final onReport = AppInspect.config.onReport;
    setState(() => _state = _SendState.sending);
    try {
      if (onReport == null) {
        await copyText(context, markdown, 'Report copied. Paste it into Jira, Slack or WhatsApp.');
      } else {
        final calls = _withCalls ? _allCalls : const <AppInspectCall>[];
        final logs = _withLogs ? _problems : const <AppInspectLog>[];
        await onReport(AppInspectReport(
          title: 'Bug on ${_screen.name}',
          note: _note.text.trim(),
          markdown: markdown,
          screen: _screen,
          calls: calls,
          logs: logs,
          har: buildHar(calls, currentMasker()),
          logsText: logsToText(logs),
          screenshot: await _screenshot,
        ));
        if (mounted) showNlToast(context, 'Report shared');
      }
      if (!mounted) return;
      setState(() => _state = _SendState.done);
      _reset?.cancel();
      _reset = Timer(const Duration(milliseconds: 1800), () {
        if (mounted) setState(() => _state = _SendState.idle);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _state = _SendState.idle);
      showNlToast(context, 'Couldn\'t send the report: $e', icon: Icons.error_rounded);
    }
  }

  void _zoom(Uint8List bytes) {
    Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: false,
      // Fades to fully dark, like a photo viewer, while the screenshot flies in.
      barrierColor: const Color(0xFF070A11),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, _) => FadeTransition(opacity: animation, child: _ScreenshotViewer(bytes)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppInspectTokens.of(context);
    final calls = _allCalls;
    final failed = calls.where((c) => c.isError).length;
    final problems = _problems.length;
    // ignore: deprecated_member_use_from_same_package
    final hasHandler = AppInspect.config.onReport != null;
    return Scaffold(
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 130),
          children: [
            Row(
              children: [
                NlIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Report a bug',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: t.text)),
                ),
                const NlIconButton(icon: Icons.close_rounded, tooltip: 'Close AppInspect', onPressed: AppInspect.close),
              ],
            ),
            const SizedBox(height: 16),
            NlCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FutureBuilder<Uint8List?>(
                    future: _screenshot,
                    builder: (context, snap) => _Thumbnail(
                      bytes: snap.data,
                      loading: snap.connectionState != ConnectionState.done,
                      onTap: snap.data == null ? null : () => _zoom(snap.data!),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('SCREEN',
                            style: TextStyle(
                                fontSize: 11, letterSpacing: 0.9, fontWeight: FontWeight.w700, color: t.textMuted)),
                        const SizedBox(height: 2),
                        Text(_screen.name,
                            style: appInspectMono.copyWith(fontSize: 15, fontWeight: FontWeight.w700, color: t.text)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            NlPill(
                              label: '${calls.length} calls',
                              foreground: t.accent,
                              background: t.accentSoft,
                              icon: Icons.sync_alt_rounded,
                            ),
                            if (failed > 0)
                              NlPill(
                                  label: '$failed failed',
                                  foreground: t.err,
                                  background: t.errSoft,
                                  icon: Icons.error_rounded),
                            if (problems > 0)
                              NlPill(
                                label: '$problems in logs',
                                foreground: t.warn,
                                background: t.warnSoft,
                                icon: Icons.warning_rounded,
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(Icons.verified_rounded, size: 16, color: t.ok),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'AppInspect and its bubble aren\'t in the screenshot. Tap it to zoom.',
                                style: TextStyle(fontSize: 12.5, height: 1.4, color: t.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const NlSectionLabel('What went wrong?'),
            TextField(
              controller: _note,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              style: TextStyle(fontSize: 14.5, height: 1.4, color: t.text),
              decoration: const InputDecoration(
                hintText: 'For example: Add to cart shows "Something went wrong".',
              ),
            ),
            const NlSectionLabel('Include'),
            NlCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  NlSwitchRow(
                    icon: Icons.sync_alt_rounded,
                    color: t.accent,
                    background: t.accentSoft,
                    title: 'API calls on this screen (${calls.length})',
                    subtitle: failed == 0 ? 'No failures' : '$failed failed, with cURL and response',
                    value: _withCalls,
                    onChanged: (v) => setState(() => _withCalls = v),
                  ),
                  Divider(height: 1, indent: 60, color: t.border),
                  NlSwitchRow(
                    icon: Icons.warning_rounded,
                    color: t.warn,
                    background: t.warnSoft,
                    title: 'Errors and warnings ($problems)',
                    value: _withLogs,
                    onChanged: (v) => setState(() => _withLogs = v),
                  ),
                  Divider(height: 1, indent: 60, color: t.border),
                  NlSwitchRow(
                    icon: Icons.smartphone_rounded,
                    color: t.violet,
                    background: t.violetSoft,
                    title: 'Device and app info',
                    subtitle: _info.values.join(' · '),
                    value: _withInfo,
                    onChanged: (v) => setState(() => _withInfo = v),
                  ),
                ],
              ),
            ),
            const NlSectionLabel('Preview'),
            NlPressable(
              pressedScale: 0.99,
              onTap: () => setState(() => _previewOpen = !_previewOpen),
              child: NlCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.article_rounded, size: 18, color: t.textSecondary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _previewOpen ? 'Hide the Markdown' : 'Show the Markdown that gets sent',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: t.text),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _previewOpen ? 0.5 : 0,
                      duration: const Duration(milliseconds: 220),
                      child: Icon(Icons.expand_more_rounded, color: t.textMuted),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _previewOpen
                  ? Padding(padding: const EdgeInsets.only(top: 10), child: CodeBlock(_markdown()))
                  : const SizedBox(width: double.infinity),
            ),
            if (!hasHandler)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: t.infoSoft, borderRadius: BorderRadius.circular(14)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_rounded, size: 18, color: t.info),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'This copies the report as text. To send the screenshot and files too, '
                          'a developer can set onReport in AppInspectConfig.',
                          style: TextStyle(fontSize: 13, height: 1.45, color: t.info),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: NlFloatingBar(
        child: FilledButton(
          onPressed: _state == _SendState.idle ? _send : null,
          style: FilledButton.styleFrom(
            disabledBackgroundColor: _state == _SendState.done ? t.ok : t.accent.withValues(alpha: 0.7),
            disabledForegroundColor: t.onAccent,
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: Tween(begin: 0.8, end: 1.0).animate(animation),
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: switch (_state) {
              _SendState.idle => Row(
                  key: const ValueKey('idle'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(hasHandler ? Icons.send_rounded : Icons.copy_rounded, size: 18),
                    const SizedBox(width: 8),
                    Text(hasHandler ? 'Send report' : 'Copy report'),
                  ],
                ),
              _SendState.sending => const SizedBox(
                  key: ValueKey('sending'),
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                ),
              _SendState.done => Row(
                  key: const ValueKey('done'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_rounded, size: 19),
                    const SizedBox(width: 8),
                    Text(hasHandler ? 'Sent' : 'Copied'),
                  ],
                ),
            },
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.bytes, required this.loading, required this.onTap});

  final Uint8List? bytes;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppInspectTokens.of(context);
    final image = bytes;
    return NlPressable(
      onTap: onTap,
      semanticLabel: 'Screenshot. Tap to zoom.',
      child: Container(
        width: 100,
        height: 200,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: t.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.border),
          boxShadow: t.cardShadow,
        ),
        child: loading
            ? const Center(child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.2)))
            : image == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text('No screenshot',
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: t.textMuted)),
                    ),
                  )
                : Hero(
                    tag: 'app_inspect_screenshot',
                    child: Image.memory(image, fit: BoxFit.cover, alignment: Alignment.topCenter),
                  ),
      ),
    );
  }
}

/// The screenshot full screen. Pinch to zoom, tap to close.
class _ScreenshotViewer extends StatelessWidget {
  const _ScreenshotViewer(this.bytes);

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    // Light status bar icons on the dark backdrop.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Material(
          color: Colors.transparent,
          child: SafeArea(
            child: Column(
              children: [
                // Above the screenshot, never on top of it.
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 12, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Pinch to zoom',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white70),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.14),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: InteractiveViewer(
                    maxScale: 5,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                        child: Hero(
                          tag: 'app_inspect_screenshot',
                          child: ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.memory(bytes)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
