import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../app_inspect.dart';
import 'detail_page.dart';
import 'kit.dart';
import 'kit_controls.dart';
import 'report_page.dart';
import 'theme.dart';
import 'widgets.dart';

/// print, debugPrint, Flutter errors, failed calls and parse errors, newest
/// first, each tagged with its screen.
class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  AppInspectLogLevel? _level;
  bool _thisScreen = false;
  String _query = '';
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(AppInspectLog log, AppInspectVisit visit) {
    if (_level != null && log.level != _level) return false;
    if (_thisScreen && !identical(log.visit, visit)) return false;
    final q = _query.trim().toLowerCase();
    return q.isEmpty || '${log.message} ${log.source} ${log.visit.name}'.toLowerCase().contains(q);
  }

  void _pick(AppInspectLogLevel? level) => setState(() => _level = _level == level ? null : level);

  @override
  Widget build(BuildContext context) {
    final t = AppInspectTokens.of(context);
    return ListenableBuilder(
      listenable: AppInspect.store,
      builder: (context, _) {
        final store = AppInspect.store;
        final visit = store.currentVisit;
        final logs = store.logs.where((l) => _matches(l, visit)).toList().reversed.toList();
        int count(AppInspectLogLevel level) => store.logs.where((l) => l.level == level).length;
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 16, 0),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: t.violet,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                  color: t.violet.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4)),
                            ],
                          ),
                          child: Icon(Icons.notes_rounded, color: t.onAccent, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Logs',
                                  style: TextStyle(
                                      fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.7, color: t.text)),
                              Text('${store.logs.length} entries',
                                  style: appInspectMono.copyWith(fontSize: 12, color: t.textSecondary, height: 1.3)),
                            ],
                          ),
                        ),
                        NlIconButton(
                          icon: Icons.bug_report_outlined,
                          tooltip: 'Report a bug',
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(builder: (_) => const ReportPage()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        NlIconButton(
                          icon: Icons.delete_sweep_outlined,
                          tooltip: 'Clear logs',
                          onPressed: store.logs.isEmpty ? null : store.clearLogs,
                        ),
                        const SizedBox(width: 8),
                        const NlIconButton(
                            icon: Icons.close_rounded, tooltip: 'Close AppInspect', onPressed: AppInspect.close),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        Expanded(
                          child: NlStatTile(
                              label: 'All',
                              value: store.logs.length,
                              color: t.accent,
                              selected: _level == null,
                              onTap: () => _pick(null)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: NlStatTile(
                            label: 'Errors',
                            value: count(AppInspectLogLevel.error),
                            color: t.err,
                            selected: _level == AppInspectLogLevel.error,
                            onTap: () => _pick(AppInspectLogLevel.error),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: NlStatTile(
                            label: 'Warnings',
                            value: count(AppInspectLogLevel.warning),
                            color: t.warn,
                            selected: _level == AppInspectLogLevel.warning,
                            onTap: () => _pick(AppInspectLogLevel.warning),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: NlStatTile(
                            label: 'Info',
                            value: count(AppInspectLogLevel.info),
                            color: t.info,
                            selected: _level == AppInspectLogLevel.info,
                            onTap: () => _pick(AppInspectLogLevel.info),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        Expanded(
                          child: NlSearchField(
                            controller: _search,
                            hint: 'Search logs',
                            onChanged: (v) => setState(() => _query = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        NlPressable(
                          onTap: () => setState(() => _thisScreen = !_thisScreen),
                          semanticLabel: 'Only this screen',
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: 46,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: _thisScreen ? t.accent : t.surface,
                              borderRadius: BorderRadius.circular(AppInspectRadius.control),
                              border: Border.all(color: _thisScreen ? t.accent : t.border),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.layers_rounded, size: 17, color: _thisScreen ? t.onAccent : t.textSecondary),
                                const SizedBox(width: 6),
                                Text(
                                  'This screen',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _thisScreen ? t.onAccent : t.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (logs.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: NlEmptyState(
                      icon: store.logs.isEmpty ? Icons.notes_rounded : Icons.filter_alt_off_rounded,
                      title: store.logs.isEmpty ? 'No logs yet' : 'Nothing matches',
                      message: store.logs.isEmpty
                          ? 'debugPrint output, Flutter errors and failed calls show up here.'
                          : 'Try another search, or tap All to clear the filter.',
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.only(top: 4, bottom: 136),
                    sliver: SliverList.builder(
                      itemCount: logs.length,
                      itemBuilder: (context, i) => _LogCard(logs[i], key: ValueKey(logs[i].id)),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LogCard extends StatefulWidget {
  const _LogCard(this.log, {super.key});

  final AppInspectLog log;

  @override
  State<_LogCard> createState() => _LogCardState();
}

class _LogCardState extends State<_LogCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    final t = AppInspectTokens.of(context);
    final (fg, bg, icon) = switch (log.level) {
      AppInspectLogLevel.debug => (t.textSecondary, t.surfaceAlt, Icons.code_rounded),
      AppInspectLogLevel.info => (t.info, t.infoSoft, Icons.info_rounded),
      AppInspectLogLevel.warning => (t.warn, t.warnSoft, Icons.warning_rounded),
      AppInspectLogLevel.error => (t.err, t.errSoft, Icons.error_rounded),
    };
    final details = log.details;
    final call = log.call;
    final fresh = DateTime.now().difference(log.time) < const Duration(seconds: 2);
    return NlAppear(
      animate: fresh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        child: NlPressable(
          pressedScale: 0.99,
          onTap: () => setState(() => _open = !_open),
          onLongPress: () =>
              copyText(context, details == null ? log.message : '${log.message}\n$details', 'Log entry copied'),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: log.level == AppInspectLogLevel.error ? t.err.withValues(alpha: 0.35) : t.border),
              boxShadow: t.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    NlIconBadge(icon, color: fg, background: bg, size: 30),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(log.source, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.text)),
                          Text(
                            '${formatTime(log.time)} · ${log.visit.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11.5, color: t.textMuted),
                          ),
                        ],
                      ),
                    ),
                    if (details != null)
                      AnimatedRotation(
                        turns: _open ? 0.5 : 0,
                        duration: const Duration(milliseconds: 220),
                        child: Icon(Icons.expand_more_rounded, color: t.textMuted),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  log.message,
                  maxLines: _open ? null : 4,
                  overflow: _open ? TextOverflow.visible : TextOverflow.ellipsis,
                  style: appInspectMono.copyWith(
                      fontSize: 12.5, color: log.level == AppInspectLogLevel.error ? t.err : t.text),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _open && details != null
                      ? Padding(padding: const EdgeInsets.only(top: 10), child: CodeBlock(details))
                      : const SizedBox(width: double.infinity),
                ),
                if (call != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: NlPressable(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => CallDetailPage(call: call)),
                      ),
                      child: NlPill(
                        label: 'View request',
                        icon: Icons.open_in_new_rounded,
                        foreground: t.accent,
                        background: t.accentSoft,
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
