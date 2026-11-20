import '../app_inspect.dart';
import '../export.dart';
import '../format.dart';
import '../models.dart';
import '../sharing.dart';
import '../timeline.dart';
import 'detail_page.dart';
import 'kit.dart';
import 'kit_controls.dart';
import 'material.dart';
import 'share_sheet.dart';
import 'theme.dart';
import 'widgets.dart';

enum _Show { all, screens, calls, problems }

/// The whole session in one list, newest first: the screens people moved to,
/// the calls each made and what the logs said. QC reads it to see what led
/// to a bug, and shares it as the steps to reproduce.
class TimelinePage extends StatefulWidget {
  const TimelinePage({super.key});

  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
  _Show _show = _Show.all;
  String _query = '';
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _passes(TimelineEntry entry, _Show show, Duration slow) => switch (show) {
        _Show.all => true,
        _Show.screens => entry is ScreenEntry,
        _Show.calls => entry is CallEntry,
        _Show.problems => entry.isProblem(slow),
      };

  bool _matches(TimelineEntry entry, Duration slow, AppInspectMasker masker) {
    if (!_passes(entry, _show, slow)) return false;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final text = switch (entry) {
      ScreenEntry(:final change) => change.visit.name,
      CallEntry(:final call) => '${callTitle(call, masker)} ${call.statusLabel} ${call.visit.name}',
      LogEntry(:final log) => '${log.message} ${log.source} ${log.visit.name}',
    };
    return text.toLowerCase().contains(q);
  }

  void _pick(_Show show) => setState(() => _show = _show == show ? _Show.all : show);

  void _share(AppInspectMasker masker) {
    final store = AppInspect.store;
    shareItem(
      context,
      AppInspectShareItem(
        text: buildTimelineMarkdown(
          screens: store.screenChanges,
          calls: store.calls,
          logs: store.logs,
          masker: masker,
          slowThreshold: AppInspect.slowThreshold.value,
        ),
        subject: 'Session timeline',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppInspectTokens.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([AppInspect.store, AppInspect.slowThreshold, AppInspect.maskData]),
      builder: (context, _) {
        final store = AppInspect.store;
        final slow = AppInspect.slowThreshold.value;
        final masker = currentMasker();
        final all = buildTimeline(screens: store.screenChanges, calls: store.calls, logs: store.logs);
        final shown = all.where((e) => _matches(e, slow, masker)).toList().reversed.toList();
        int count(_Show show) => all.where((e) => _passes(e, show, slow)).length;

        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _Header(
                    subtitle: all.isEmpty ? 'Nothing yet' : 'Since ${formatTime(all.first.time)}',
                    onShare: all.isEmpty ? null : () => _share(masker),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        for (final (i, (show, label, color)) in [
                          (_Show.all, 'Steps', t.accent),
                          (_Show.screens, 'Screens', t.accentAlt),
                          (_Show.calls, 'Calls', t.info),
                          (_Show.problems, 'Problems', t.err),
                        ].indexed) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(
                            child: NlStatTile(
                              label: label,
                              value: show == _Show.all ? all.length : count(show),
                              color: color,
                              selected: _show == show,
                              onTap: () => _pick(show),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                  sliver: SliverToBoxAdapter(
                    child: NlSearchField(
                      controller: _search,
                      hint: 'Search screens, calls and logs',
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                ),
                if (shown.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: NlEmptyState(
                      icon: all.isEmpty ? Icons.timeline_rounded : Icons.filter_alt_off_rounded,
                      title: all.isEmpty ? 'Nothing yet' : 'Nothing matches',
                      message: all.isEmpty
                          ? 'The screens you open, the calls they make and the logs show up here, in order.'
                          : 'Try another search, or tap Steps to clear the filter.',
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.only(top: 6, bottom: 136),
                    sliver: SliverList.builder(
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final entry = shown[i];
                        final older = i + 1 < shown.length ? shown[i + 1] : null;
                        return _TimelineRow(
                          key: ObjectKey(_subject(entry)),
                          entry: entry,
                          gap: older == null ? null : formatGap(entry.time.difference(older.time)),
                          first: i == 0,
                          last: i == shown.length - 1,
                          masker: masker,
                          slow: slow,
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Object _subject(TimelineEntry entry) => switch (entry) {
        ScreenEntry(:final change) => change,
        CallEntry(:final call) => call,
        LogEntry(:final log) => log,
      };
}

class _Header extends StatelessWidget {
  const _Header({required this.subtitle, required this.onShare});

  final String subtitle;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final t = AppInspectTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 0),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: t.accent,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(color: t.accent.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4)),
              ],
            ),
            child: Icon(Icons.timeline_rounded, color: t.onAccent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Timeline',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.7, color: t.text)),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: appInspectMono.copyWith(fontSize: 12, color: t.textSecondary, height: 1.3),
                ),
              ],
            ),
          ),
          NlIconButton(icon: Icons.ios_share_rounded, tooltip: 'Share the steps', onPressed: onShare),
          const SizedBox(width: 8),
          const NlIconButton(icon: Icons.close_rounded, tooltip: 'Close AppInspect', onPressed: AppInspect.close),
        ],
      ),
    );
  }
}

/// One step, on a line that runs down the left side.
class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    super.key,
    required this.entry,
    required this.gap,
    required this.first,
    required this.last,
    required this.masker,
    required this.slow,
  });

  final TimelineEntry entry;

  /// The time since the step below, the one before it.
  final String? gap;
  final bool first;
  final bool last;
  final AppInspectMasker masker;
  final Duration slow;

  /// Where the middle of a dot sits, from the top of the row.
  static const double _dotCenter = 22;
  static const double _rail = 28;

  @override
  Widget build(BuildContext context) {
    final t = AppInspectTokens.of(context);
    final fresh = DateTime.now().difference(entry.time) < const Duration(seconds: 2);
    return NlAppear(
      animate: fresh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Stack(
          children: [
            if (!(first && last))
              Positioned(
                left: _rail / 2 - 1,
                width: 2,
                top: first ? _dotCenter : 0,
                bottom: last ? null : 0,
                height: last ? _dotCenter : null,
                child: ColoredBox(color: t.border),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: _rail, child: _dot(t)),
                const SizedBox(width: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: switch (entry) {
                      ScreenEntry(:final change) => _ScreenStep(change: change, meta: _meta()),
                      CallEntry(:final call) => _CallStep(call: call, masker: masker, meta: _meta()),
                      LogEntry(:final log) => _LogStep(log: log, meta: _meta()),
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _meta() {
    final where = entry is ScreenEntry ? '' : ' · ${entry.visit.name}';
    return '${formatTime(entry.time)}${gap == null || gap!.isEmpty ? '' : ' · $gap'}$where';
  }

  Widget _dot(AppInspectTokens t) {
    if (entry case ScreenEntry(:final change)) {
      return Padding(
        padding: const EdgeInsets.only(top: _dotCenter - 13),
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: t.accent,
            shape: BoxShape.circle,
            border: Border.all(color: t.canvas, width: 2),
          ),
          child: Icon(
            change.returned ? Icons.keyboard_return_rounded : Icons.layers_rounded,
            size: 13,
            color: t.onAccent,
          ),
        ),
      );
    }
    final color = switch (entry) {
      CallEntry(:final call) when call.isError => t.err,
      CallEntry(:final call) when call.isSlow(slow) => t.warn,
      CallEntry(:final call) when call.isPending || call.cancelled => t.textMuted,
      CallEntry() => t.ok,
      LogEntry(:final log) => switch (log.level) {
          AppInspectLogLevel.debug => t.textMuted,
          AppInspectLogLevel.info => t.info,
          AppInspectLogLevel.warning => t.warn,
          AppInspectLogLevel.error => t.err,
        },
      ScreenEntry() => t.accent,
    };
    return Padding(
      padding: const EdgeInsets.only(top: _dotCenter - 7),
      child: Center(
        child: Container(
          width: 14,
          height: 14,
          decoration:
              BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: t.canvas, width: 3)),
        ),
      ),
    );
  }
}

/// The time, the gap to the step before and the screen, under a step.
class _Meta extends StatelessWidget {
  const _Meta(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = AppInspectTokens.of(context);
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11.5,
        color: t.textMuted,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

class _ScreenStep extends StatelessWidget {
  const _ScreenStep({required this.change, required this.meta});

  final AppInspectScreenChange change;
  final String meta;

  @override
  Widget build(BuildContext context) {
    final t = AppInspectTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 0, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(text: change.returned ? 'Back to ' : 'Opened ', style: TextStyle(color: t.textSecondary)),
              TextSpan(
                text: change.visit.name,
                style: appInspectMono.copyWith(fontWeight: FontWeight.w700, color: t.text),
              ),
            ]),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, height: 1.35),
          ),
          const SizedBox(height: 2),
          _Meta(meta),
        ],
      ),
    );
  }
}

class _CallStep extends StatelessWidget {
  const _CallStep({required this.call, required this.masker, required this.meta});

  final AppInspectCall call;
  final AppInspectMasker masker;
  final String meta;

  @override
  Widget build(BuildContext context) {
    final t = AppInspectTokens.of(context);
    return NlPressable(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CallDetailPage(call: call))),
      onLongPress: () => showCallActions(context, call),
      semanticLabel: '${callTitle(call, masker)}, ${call.statusLabel}',
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: call.isError ? t.err.withValues(alpha: 0.35) : t.border),
          boxShadow: t.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                NlOperationPill(call),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    callHeadline(call, masker),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: appInspectMono.copyWith(fontSize: 13, fontWeight: FontWeight.w600, color: t.text),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                NlStatusPill(call),
                if (!call.isPending)
                  NlPill(label: formatDuration(call.duration), foreground: t.textSecondary, background: t.surfaceAlt),
                ...flagPills(context, call),
              ],
            ),
            const SizedBox(height: 6),
            _Meta(meta),
          ],
        ),
      ),
    );
  }
}

class _LogStep extends StatefulWidget {
  const _LogStep({required this.log, required this.meta});

  final AppInspectLog log;
  final String meta;

  @override
  State<_LogStep> createState() => _LogStepState();
}

class _LogStepState extends State<_LogStep> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final t = AppInspectTokens.of(context);
    final log = widget.log;
    final error = log.level == AppInspectLogLevel.error;
    final details = log.details;
    return NlPressable(
      pressedScale: 0.99,
      onTap: () => setState(() => _open = !_open),
      onLongPress: () =>
          copyText(context, details == null ? log.message : '${log.message}\n$details', 'Log entry copied'),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: error ? t.errSoft : t.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              log.source,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: error ? t.err : t.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              log.message,
              maxLines: _open ? null : 3,
              overflow: _open ? TextOverflow.visible : TextOverflow.ellipsis,
              style: appInspectMono.copyWith(fontSize: 12.5, height: 1.45, color: error ? t.err : t.text),
            ),
            if (_open && details != null) ...[
              const SizedBox(height: 8),
              CodeBlock(details),
            ],
            const SizedBox(height: 6),
            _Meta(widget.meta),
          ],
        ),
      ),
    );
  }
}
