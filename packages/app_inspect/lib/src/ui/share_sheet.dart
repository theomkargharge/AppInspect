import 'package:flutter/material.dart';

import '../export.dart';
import '../format.dart';
import '../models.dart';
import '../app_inspect.dart';
import '../sharing.dart';
import 'kit_controls.dart';
import 'theme.dart';
import 'widgets.dart';

String _slug(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '').toLowerCase();

/// Share and export options for one call: Markdown for chat, HAR for
/// browser tools, Postman for the backend team, and cURL.
Future<void> showCallActions(BuildContext context, AppInspectCall call) {
  final masker = currentMasker();
  final screen = call.visit.name;
  final screenCalls = AppInspect.store.callsFor(call.visit).where((c) => !c.isPending).toList();
  final title = '${call.method} ${call.path}';
  final slug = _slug('${call.method} ${call.uri.path}');
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) {
      final t = AppInspectTokens.of(sheet);
      void pick(AppInspectShareItem item) {
        Navigator.pop(sheet);
        shareItem(context, item);
      }

      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.85),
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Text('Share or export',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: t.text)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Row(
                    children: [
                      NlMethodPill(call.method),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(call.path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: appInspectMono.copyWith(color: t.textSecondary)),
                      ),
                    ],
                  ),
                ),
                NlActionTile(
                  icon: Icons.notes_rounded,
                  color: t.info,
                  background: t.infoSoft,
                  title: 'Share as Markdown',
                  subtitle: 'For Slack, Jira or WhatsApp',
                  onTap: () => pick(AppInspectShareItem(
                    text: callToMarkdown(call, masker, slowThreshold: AppInspect.slowThreshold.value),
                    subject: title,
                  )),
                ),
                NlActionTile(
                  icon: Icons.description_rounded,
                  color: t.ok,
                  background: t.okSoft,
                  title: 'Export HAR: this call',
                  subtitle: 'Opens in Chrome DevTools, Charles and Proxyman',
                  enabled: !call.isPending,
                  onTap: () => pick(AppInspectShareItem(
                    text: buildHar([call], masker),
                    subject: title,
                    fileName: '$slug.har',
                    mimeType: 'application/json',
                  )),
                ),
                NlActionTile(
                  icon: Icons.folder_copy_rounded,
                  color: t.violet,
                  background: t.violetSoft,
                  title: 'Export HAR: all ${screenCalls.length} calls on $screen',
                  subtitle: 'Every finished call on this screen',
                  enabled: screenCalls.isNotEmpty,
                  onTap: () => pick(AppInspectShareItem(
                    text: buildHar(screenCalls, masker),
                    subject: 'Calls on $screen',
                    fileName: '$screen.har',
                    mimeType: 'application/json',
                  )),
                ),
                NlActionTile(
                  icon: Icons.send_rounded,
                  color: t.warn,
                  background: t.warnSoft,
                  title: 'Export Postman collection',
                  subtitle: 'The backend team can send the same request',
                  onTap: () => pick(AppInspectShareItem(
                    text: buildPostmanCollection([call], masker, name: title),
                    subject: title,
                    fileName: '$slug.postman_collection.json',
                    mimeType: 'application/json',
                  )),
                ),
                NlActionTile(
                  icon: Icons.terminal_rounded,
                  color: t.accent,
                  background: t.accentSoft,
                  title: 'Copy cURL',
                  subtitle: 'Paste it into a terminal to repeat the call',
                  onTap: () {
                    Navigator.pop(sheet);
                    copyText(context, buildCurl(call, masker), 'cURL copied');
                  },
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
