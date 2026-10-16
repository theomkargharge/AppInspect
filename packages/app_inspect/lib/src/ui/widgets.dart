import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../models.dart';
import '../app_inspect.dart';
import '../sharing.dart';
import 'kit.dart';
import 'kit_controls.dart';
import 'theme.dart';

/// The masker for what's on screen right now, following the Settings switch.
AppInspectMasker currentMasker() => AppInspectMasker(AppInspect.config, enabled: AppInspect.maskData.value);

/// Copies [text] and confirms with a toast and a light haptic.
Future<void> copyText(BuildContext context, String text, String message) async {
  await Clipboard.setData(ClipboardData(text: text));
  await HapticFeedback.lightImpact();
  if (context.mounted) showNlToast(context, message);
}

/// Uses `AppInspectConfig.onShare` when the app set one, and the clipboard
/// otherwise.
Future<void> shareItem(BuildContext context, AppInspectShareItem item) async {
  final onShare = AppInspect.config.onShare;
  if (onShare != null) {
    try {
      await onShare(item);
    } catch (e) {
      if (context.mounted) showNlToast(context, 'Couldn\'t share: $e', icon: Icons.error_rounded);
    }
    return;
  }
  final name = item.fileName;
  await copyText(
    context,
    item.text,
    name == null ? 'Copied. Paste it into Slack, Jira or WhatsApp.' : 'Copied. Paste it into a file named $name.',
  );
}

/// The HTTP method in its color, such as a blue GET.
class NlMethodPill extends StatelessWidget {
  const NlMethodPill(this.method, {super.key});

  final String method;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = AppInspectTokens.of(context).method(method);
    return NlPill(label: method, foreground: fg, background: bg, mono: true);
  }
}

/// Status in plain words with a colored dot. A parse error gets its own pill.
class NlStatusPill extends StatelessWidget {
  const NlStatusPill(this.call, {super.key});

  final AppInspectCall call;

  @override
  Widget build(BuildContext context) {
    final t = AppInspectTokens.of(context);
    if (call.isPending) {
      return NlPill(label: 'Pending', foreground: t.textSecondary, background: t.surfaceAlt, icon: Icons.more_horiz_rounded);
    }
    final failed = call.state == AppInspectCallState.failed || (call.statusCode ?? 0) >= 400;
    return NlPill(
      label: call.statusLabel,
      foreground: failed ? t.err : t.ok,
      background: failed ? t.errSoft : t.okSoft,
      dot: true,
    );
  }
}

/// The warning labels a call can carry.
List<Widget> flagPills(BuildContext context, AppInspectCall call) {
  final t = AppInspectTokens.of(context);
  return [
    if (call.parseError != null)
      NlPill(label: 'Parse error', foreground: t.err, background: t.errSoft, icon: Icons.data_object_rounded),
    if (call.isSlow(AppInspect.slowThreshold.value))
      NlPill(label: 'Slow', foreground: t.warn, background: t.warnSoft, icon: Icons.schedule_rounded),
    if (call.isRepeated)
      NlPill(label: 'Repeated ${call.repeatCount}×', foreground: t.violet, background: t.violetSoft, icon: Icons.repeat_rounded),
  ];
}

/// A plain-language note about a call, in its severity color.
class InsightCard extends StatelessWidget {
  const InsightCard(this.insight, {super.key});

  final AppInspectInsight insight;

  @override
  Widget build(BuildContext context) {
    final t = AppInspectTokens.of(context);
    final (fg, bg, icon) = switch (insight.level) {
      AppInspectInsightLevel.error => (t.err, t.errSoft, Icons.error_rounded),
      AppInspectInsightLevel.warning => (t.warn, t.warnSoft, Icons.warning_rounded),
      AppInspectInsightLevel.info => (t.info, t.infoSoft, Icons.lightbulb_rounded),
    };
    return NlAppear(
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: fg.withValues(alpha: 0.18)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: fg),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${insight.title}. ', style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: insight.detail),
                ]),
                style: TextStyle(color: fg, fontSize: 13.5, height: 1.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Label and value rows in a card, with hairlines between them. Values can
/// be selected and copied.
class KeyValueCard extends StatelessWidget {
  const KeyValueCard(this.rows, {super.key, this.trailing = const {}});

  final List<(String, String)> rows;

  /// Optional widgets after a value, keyed by label, such as a Reveal button.
  final Map<String, Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final t = AppInspectTokens.of(context);
    return NlCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        children: [
          for (final (i, (label, value)) in rows.indexed) ...[
            if (i > 0) Divider(height: 1, color: t.border),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 118,
                    child: Text(label, style: TextStyle(fontSize: 13, color: t.textSecondary, fontWeight: FontWeight.w500)),
                  ),
                  Expanded(child: SelectableText(value, style: appInspectMono.copyWith(fontSize: 12.5, color: t.text))),
                  if (trailing[label] case final Widget extra) extra,
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A dark, terminal-style block for commands such as cURL.
class CodeBlock extends StatelessWidget {
  const CodeBlock(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = AppInspectTokens.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(color: t.ink, borderRadius: BorderRadius.circular(16), boxShadow: t.cardShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final c in const [Color(0xFFFF5F57), Color(0xFFFEBC2E), Color(0xFF28C840)])
                Container(
                  width: 9,
                  height: 9,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SelectableText(text, style: appInspectMono.copyWith(fontSize: 12, height: 1.6, color: t.onInk)),
        ],
      ),
    );
  }
}
