import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../app_inspect.dart';
import 'detail_page.dart';
import 'kit.dart';
import 'kit_controls.dart';
import 'settings_page.dart';
import 'share_sheet.dart';
import 'theme.dart';
import 'widgets.dart';

enum _Filter { errors, slow, repeated }

/// The call list. Opens on the current screen's calls, newest first.
class CallListPage extends StatefulWidget {
  const CallListPage({super.key});

  @override
  State<CallListPage> createState() => _CallListPageState();
}

class _CallListPageState extends State<CallListPage> {
  bool _allScreens = false;
  String _query = '';
  final Set<_Filter> _filters = {};
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _passes(AppInspectCall c, _Filter f) => switch (f) {
        _Filter.errors => c.isError,
        _Filter.slow => c.isSlow(AppInspect.slowThreshold.value),
        _Filter.repeated => c.isRepeated,
      };

  bool _matches(AppInspectCall c) {
    if (_filters.isNotEmpty && !_filters.any((f) => _passes(c, f))) return false;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return '${c.method} ${c.uri} ${c.statusLabel} ${c.visit.name}'.toLowerCase().contains(q);
  }

  void _toggle(_Filter f) => setState(() => _filters.contains(f) ? _filters.remove(f) : _filters.add(f));

  @override
  Widget build(BuildContext context) {
    final t = AppInspectTokens.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([AppInspect.store, AppInspect.slowThreshold, AppInspect.maskData]),
      builder: (context, _) {
        final store = AppInspect.store;
        final visit = store.currentVisit;
        final mine = store.callsFor(visit);
        final all = store.calls;
        final source = _allScreens ? all : mine;
        final shown = source.where(_matches).toList().reversed.toList();

        // In "All", group calls under the screen that made them.
        final items = <Object>[];
        if (_allScreens) {
          AppInspectVisit? last;
          for (final c in shown) {
            if (!identical(c.visit, last)) items.add(c.visit);
            last = c.visit;
            items.add(c);
          }
        } else {
          items.addAll(shown);
        }

        int count(_Filter f) => source.where((c) => _passes(c, f)).length;

        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _Header(screen: visit.name)),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        Expanded(
                          child: NlStatTile(
                            label: 'Calls',
                            value: source.length,
                            color: t.accent,
                            selected: _filters.isEmpty,
                            onTap: () => setState(_filters.clear),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: NlStatTile(
                            label: 'Failed',
                            value: count(_Filter.errors),
                            color: t.err,
                            selected: _filters.contains(_Filter.errors),
                            onTap: () => _toggle(_Filter.errors),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: NlStatTile(
                            label: 'Slow',
                            value: count(_Filter.slow),
                            color: t.warn,
                            selected: _filters.contains(_Filter.slow),
                            onTap: () => _toggle(_Filter.slow),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: NlStatTile(
                            label: 'Repeated',
                            value: count(_Filter.repeated),
                            color: t.violet,
                            selected: _filters.contains(_Filter.repeated),
                            onTap: () => _toggle(_Filter.repeated),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: NlSegmented<bool>(
                      value: _allScreens,
                      onChanged: (v) => setState(() => _allScreens = v),
                      options: [(false, 'This screen · ${mine.length}'), (true, 'All · ${all.length}')],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  sliver: SliverToBoxAdapter(
                    child: NlSearchField(
                      controller: _search,
                      hint: 'Search URL, status or screen',
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                ),
                if (items.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: NlEmptyState(
                      icon: source.isEmpty ? Icons.wifi_tethering_rounded : Icons.filter_alt_off_rounded,
                      title: source.isEmpty
                          ? (_allScreens ? 'No calls yet' : 'No calls on this screen yet')
                          : 'Nothing matches',
                      message: source.isEmpty
                          ? (_allScreens
                              ? 'Calls show up here as the app makes them.'
                              : 'Calls this screen makes show up here as they happen. Switch to All to see other screens.')
                          : 'Try another search, or tap Calls to clear the filters.',
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.only(top: 4, bottom: 136),
                    sliver: SliverList.builder(
                      itemCount: items.length,
                      itemBuilder: (context, i) => switch (items[i]) {
                        AppInspectVisit v => _VisitHeader(v),
                        final AppInspectCall c => _CallCard(c, key: ValueKey(c.id)),
                        _ => const SizedBox.shrink(),
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
}

class _Header extends StatelessWidget {
  const _Header({required this.screen});

  final String screen;

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
                BoxShadow(color: t.accent.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))
              ],
            ),
            child: Icon(Icons.manage_search_rounded, color: t.onAccent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Network',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.7, color: t.text)),
                Row(
                  children: [
                    Icon(Icons.layers_rounded, size: 13, color: t.textMuted),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        screen,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: appInspectMono.copyWith(fontSize: 12, color: t.textSecondary, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          NlIconButton(
            icon: Icons.tune_rounded,
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsPage())),
          ),
          const SizedBox(width: 8),
          const NlIconButton(icon: Icons.close_rounded, tooltip: 'Close AppInspect', onPressed: AppInspect.close),
        ],
      ),
    );
  }
}

class _VisitHeader extends StatelessWidget {
  const _VisitHeader(this.visit);

  final AppInspectVisit visit;

  @override
  Widget build(BuildContext context) {
    final t = AppInspectTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 6),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              visit.name,
              overflow: TextOverflow.ellipsis,
              style: appInspectMono.copyWith(fontSize: 12.5, fontWeight: FontWeight.w700, color: t.text),
            ),
          ),
          Text(formatTime(visit.startedAt), style: TextStyle(fontSize: 11.5, color: t.textMuted)),
        ],
      ),
    );
  }
}

class _CallCard extends StatelessWidget {
  const _CallCard(this.call, {super.key});

  final AppInspectCall call;

  @override
  Widget build(BuildContext context) {
    final t = AppInspectTokens.of(context);
    final fresh = DateTime.now().difference(call.startedAt) < const Duration(seconds: 2);
    final path = currentMasker().path(call);
    return NlAppear(
      animate: fresh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        child: NlPressable(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => CallDetailPage(call: call)),
          ),
          onLongPress: () => showCallActions(context, call),
          semanticLabel: '${call.method} $path, ${call.statusLabel}',
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: call.isError ? t.err.withValues(alpha: 0.35) : t.border),
              boxShadow: t.cardShadow,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          NlMethodPill(call.method),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              path,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  appInspectMono.copyWith(fontSize: 13.5, fontWeight: FontWeight.w600, color: t.text),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          NlStatusPill(call),
                          _Meta(Icons.schedule_rounded, formatDuration(call.duration)),
                          if (call.responseSize != null) _Meta(Icons.download_rounded, formatResponseSize(call)),
                          ...flagPills(context, call),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: t.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = AppInspectTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: t.textMuted),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: t.textSecondary,
            fontWeight: FontWeight.w500,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
