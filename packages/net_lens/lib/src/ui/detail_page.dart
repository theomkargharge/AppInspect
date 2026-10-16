import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../net_lens.dart';
import 'json_view.dart';
import 'kit.dart';
import 'kit_controls.dart';
import 'share_sheet.dart';
import 'theme.dart';
import 'widgets.dart';

/// Everything about one call: what was sent, what came back, and a cURL
/// command that repeats it.
class CallDetailPage extends StatefulWidget {
  const CallDetailPage({super.key, required this.call});

  final NetLensCall call;

  @override
  State<CallDetailPage> createState() => _CallDetailPageState();
}

class _CallDetailPageState extends State<CallDetailPage> with SingleTickerProviderStateMixin {
  // A response the app couldn't read opens on the Response tab, where the
  // field that broke is highlighted.
  late final TabController _tabs =
      TabController(length: 4, vsync: this, initialIndex: widget.call.parseError != null ? 2 : 0);
  final Set<String> _revealed = {};

  /// The request never changes, so its size is worked out once. Decoded JSON
  /// is measured on another isolate, so its size fills in a moment later.
  late final Future<String> _requestSize = formatRequestSize(call.requestBody);

  /// The cURL command and the masker it was built with. Building it writes
  /// out the whole request body, so it's built again only when masking
  /// changes, not on every rebuild.
  ({NetLensMasker masker, String text})? _curl;

  NetLensCall get call => widget.call;

  @override
  void initState() {
    super.initState();
    NetLens.store.addListener(_estimateSize);
    _estimateSize();
  }

  /// Decoded JSON, such as a Dio response without a Content-Length header,
  /// comes without a size. Work one out off the UI thread once the call is
  /// done.
  void _estimateSize() {
    if (call.isPending) return;
    NetLens.store.removeListener(_estimateSize);
    NetLens.store.estimateResponseSize(call).ignore();
  }

  @override
  void dispose() {
    NetLens.store.removeListener(_estimateSize);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = NetLensTokens.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([NetLens.store, NetLens.maskData, NetLens.slowThreshold]),
      builder: (context, _) {
        final masker = currentMasker();
        final insights = insightsFor(call, slowThreshold: NetLens.slowThreshold.value);
        return Scaffold(
          extendBody: true,
          body: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Row(
                    children: [
                      NlIconButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 12),
                      NlMethodPill(call.method),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          call.path,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: netLensMono.copyWith(fontSize: 13.5, fontWeight: FontWeight.w700, color: t.text),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const NlIconButton(icon: Icons.close_rounded, tooltip: 'Close NetLens', onPressed: NetLens.close),
                    ],
                  ),
                ),
                // Natural height, but never more than about half the screen,
                // so the tabs always have room.
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.42),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _HeroCard(call: call),
                        for (final insight in insights) InsightCard(insight),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: _PillTabs(controller: _tabs),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _overview(),
                      _requestTab(masker),
                      _responseTab(masker),
                      _curlTab(masker),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: NlFloatingBar(
            child: Row(
              children: [
                Expanded(
                  child: NlCopyButton(
                    primary: true,
                    label: 'cURL',
                    icon: Icons.terminal_rounded,
                    onPressed: () => copyText(context, _curlFor(masker), 'cURL copied'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: call.responseBody == null
                      ? OutlinedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.data_object_rounded, size: 18),
                          label: const Text('JSON'),
                        )
                      : NlCopyButton(
                          label: 'JSON',
                          icon: Icons.data_object_rounded,
                          onPressed: () => copyText(context, _responseText(masker), 'Response copied'),
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => showCallActions(context, call),
                    icon: const Icon(Icons.ios_share_rounded, size: 18),
                    label: const Text('Share'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _curlFor(NetLensMasker masker) {
    final kept = _curl;
    if (kept != null && _sameMasking(kept.masker, masker)) return kept.text;
    final text = buildCurl(call, masker);
    _curl = (masker: masker, text: text);
    return text;
  }

  String _responseText(NetLensMasker masker) {
    final decoded = decodeBody(call.responseBody);
    return decoded is String ? decoded : encodeBody(masker.json(decoded));
  }

  /// Every tab scrolls under the floating bar, so they end with room for it.
  Widget _tab(List<Widget> slivers) => CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            sliver: SliverMainAxisGroup(slivers: slivers),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 140)),
        ],
      );

  Widget _overview() {
    final t = NetLensTokens.of(context);
    return _tab([
      SliverToBoxAdapter(
        child: FutureBuilder<String>(
          future: _requestSize,
          builder: (context, requestSize) => KeyValueCard(
            [
              ('URL', call.uri.toString()),
              ('Method', call.method),
              ('Status', call.statusLabel),
              ('Screen', call.visit.name),
              ('Started', formatTime(call.startedAt)),
              ('Duration', formatDuration(call.duration)),
              ('Request size', requestSize.data ?? '…'),
              ('Response size', formatResponseSize(call)),
              ('Captured by', call.source),
              if (call.errorDetail != null) ('Error', call.errorDetail!),
            ],
            trailing: {
              'URL': IconButton(
                tooltip: 'Copy URL',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.copy_rounded, size: 17, color: t.accent),
                onPressed: () => copyText(context, call.uri.toString(), 'URL copied'),
              ),
            },
          ),
        ),
      ),
    ]);
  }

  Widget _headers(Map<String, String> headers, NetLensMasker masker) {
    final t = NetLensTokens.of(context);
    if (headers.isEmpty) return const NlCard(child: Text('No headers'));
    final trailing = <String, Widget>{};
    final rows = <(String, String)>[];
    for (final e in headers.entries) {
      final masked = masker.isMaskedHeader(e.key) && !_revealed.contains(e.key);
      rows.add((e.key, masked ? masker.header(e.key, e.value) : e.value));
      if (masked) {
        trailing[e.key] = NlPressable(
          onTap: () => setState(() => _revealed.add(e.key)),
          child: NlPill(label: 'Reveal', foreground: t.accent, background: t.accentSoft, icon: Icons.visibility_rounded),
        );
      }
    }
    return KeyValueCard(rows, trailing: trailing);
  }

  Widget _requestTab(NetLensMasker masker) {
    final query = call.uri.queryParametersAll;
    return _tab([
      const SliverToBoxAdapter(child: NlSectionLabel('Headers, after every interceptor', padding: EdgeInsets.fromLTRB(4, 8, 4, 8))),
      SliverToBoxAdapter(child: _headers(call.requestHeaders, masker)),
      if (query.isNotEmpty) ...[
        const SliverToBoxAdapter(child: NlSectionLabel('Query parameters')),
        SliverToBoxAdapter(child: KeyValueCard([for (final e in query.entries) (e.key, e.value.join(', '))])),
      ],
      const SliverToBoxAdapter(child: NlSectionLabel('Body')),
      _BodySliver(body: call.requestBody, masker: masker),
    ]);
  }

  Widget _responseTab(NetLensMasker masker) {
    if (call.isPending) {
      return const NlEmptyState(
        icon: Icons.hourglass_top_rounded,
        title: 'Waiting for the response',
        message: 'It shows up here as soon as the server answers.',
      );
    }
    // The body is what QC needs, so it comes first. Response headers are
    // often long, so they start folded.
    return _tab([
      const SliverToBoxAdapter(child: NlSectionLabel('Raw body, before the app parses it', padding: EdgeInsets.fromLTRB(4, 8, 4, 8))),
      _BodySliver(body: call.responseBody, masker: masker, highlight: {...?call.parseError?.highlightPaths}),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 14),
          child: _Foldable(
            title: 'Headers · ${call.responseHeaders.length}',
            child: _headers(call.responseHeaders, masker),
          ),
        ),
      ),
    ]);
  }

  Widget _curlTab(NetLensMasker masker) {
    final t = NetLensTokens.of(context);
    return _tab([
      SliverToBoxAdapter(child: CodeBlock(_curlFor(masker))),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(masker.enabled ? Icons.shield_rounded : Icons.shield_outlined, size: 16, color: t.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  masker.enabled
                      ? 'Masked values stay masked when you copy or share. Turn off masking in Settings to include real tokens.'
                      : 'Masking is off, so real tokens are included.',
                  style: TextStyle(fontSize: 12.5, height: 1.4, color: t.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    ]);
  }
}

/// The outcome at a glance: a status orb, the timing, and the flags.
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.call});

  final NetLensCall call;

  @override
  Widget build(BuildContext context) {
    final t = NetLensTokens.of(context);
    final httpFailed = call.state == NetLensCallState.failed || (call.statusCode ?? 0) >= 400;
    final (fg, bg, icon) = call.isPending
        ? (t.textSecondary, t.surfaceAlt, Icons.hourglass_top_rounded)
        : call.isError
            ? (t.err, t.errSoft, call.parseError != null ? Icons.data_object_rounded : Icons.close_rounded)
            : (t.ok, t.okSoft, Icons.check_rounded);
    final flags = flagPills(context, call);
    return NlCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.6, end: 1),
                duration: const Duration(milliseconds: 500),
                curve: Curves.elasticOut,
                builder: (context, s, child) => Transform.scale(scale: s, child: child),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                  child: Icon(icon, color: fg, size: 26),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      call.statusLabel,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: call.isPending ? t.textSecondary : (httpFailed ? t.err : t.ok),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        formatDuration(call.duration),
                        if (call.responseSize != null) formatResponseSize(call),
                        call.visit.name,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: t.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _TimingBar(call: call),
          if (flags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: flags),
          ],
        ],
      ),
    );
  }
}

/// How long the call took, against the slow-call limit.
class _TimingBar extends StatelessWidget {
  const _TimingBar({required this.call});

  final NetLensCall call;

  @override
  Widget build(BuildContext context) {
    final t = NetLensTokens.of(context);
    final duration = call.duration;
    if (duration == null) {
      return Text('Waiting for the response…', style: TextStyle(fontSize: 12.5, color: t.textSecondary));
    }
    final limit = NetLens.slowThreshold.value;
    final scaleMs = [limit.inMilliseconds * 2, (duration.inMilliseconds * 1.15).round()].reduce((a, b) => a > b ? a : b);
    final fraction = (duration.inMilliseconds / scaleMs).clamp(0.02, 1.0);
    final limitAt = limit.inMilliseconds / scaleMs;
    final slow = call.isSlow(limit);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 10,
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              clipBehavior: Clip.none,
              children: [
                Container(decoration: BoxDecoration(color: t.surfaceAlt, borderRadius: BorderRadius.circular(5))),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: fraction),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutCubic,
                  builder: (context, f, _) => Container(
                    width: constraints.maxWidth * f,
                    decoration: BoxDecoration(
                      color: slow ? t.warn : t.ok,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
                Positioned(
                  left: constraints.maxWidth * limitAt - 1,
                  top: -3,
                  bottom: -3,
                  child: Container(width: 2, decoration: BoxDecoration(color: t.textMuted, borderRadius: BorderRadius.circular(1))),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              formatDuration(duration),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: slow ? t.warn : t.ok),
            ),
            const Spacer(),
            Text('Slow after ${formatDuration(limit)}', style: TextStyle(fontSize: 11.5, color: t.textMuted)),
          ],
        ),
      ],
    );
  }
}

/// iOS-style tabs: a white pill slides behind the chosen tab.
class _PillTabs extends StatelessWidget {
  const _PillTabs({required this.controller});

  final TabController controller;

  @override
  Widget build(BuildContext context) {
    final t = NetLensTokens.of(context);
    return Container(
      height: 42,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: t.surfaceAlt, borderRadius: BorderRadius.circular(13)),
      child: TabBar(
        controller: controller,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(color: t.raised, borderRadius: BorderRadius.circular(10), boxShadow: t.cardShadow),
        labelColor: t.text,
        unselectedLabelColor: t.textSecondary,
        labelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
        labelPadding: EdgeInsets.zero,
        splashFactory: NoSplash.splashFactory,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        tabs: const [Tab(text: 'Overview'), Tab(text: 'Request'), Tab(text: 'Response'), Tab(text: 'cURL')],
      ),
    );
  }
}

/// A card whose content folds away behind its title.
class _Foldable extends StatefulWidget {
  const _Foldable({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  State<_Foldable> createState() => _FoldableState();
}

class _FoldableState extends State<_Foldable> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final t = NetLensTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NlPressable(
          onTap: () => setState(() => _open = !_open),
          pressedScale: 0.99,
          child: NlCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title.toUpperCase(),
                    style: TextStyle(fontSize: 11, letterSpacing: 0.9, fontWeight: FontWeight.w700, color: t.textMuted),
                  ),
                ),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 220),
                  child: Icon(Icons.expand_more_rounded, color: t.textMuted),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _open ? Padding(padding: const EdgeInsets.only(top: 8), child: widget.child) : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// Decodes a body off the UI thread when it's large, then shows it as a JSON
/// tree in a card, or as text.
class _BodySliver extends StatefulWidget {
  const _BodySliver({required this.body, required this.masker, this.highlight = const {}});

  final Object? body;
  final NetLensMasker masker;
  final Set<String> highlight;

  @override
  State<_BodySliver> createState() => _BodySliverState();
}

class _BodySliverState extends State<_BodySliver> {
  late Future<Object?> _decoded;

  /// The decoded tree with sensitive values masked, and what it was made
  /// from. Masking copies the whole tree, and the page rebuilds for every new
  /// call, so the copy is kept until the body or the masking changes. That
  /// also keeps the JSON view's folds, which reset when its data changes.
  ({Object? source, NetLensMasker masker, Object? masked})? _masked;

  @override
  void initState() {
    super.initState();
    _decoded = decodeBodyAsync(widget.body);
  }

  @override
  void didUpdateWidget(_BodySliver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.body, widget.body)) _decoded = decodeBodyAsync(widget.body);
  }

  Object? _maskedJson(Object? value) {
    final kept = _masked;
    if (kept != null && identical(kept.source, value) && _sameMasking(kept.masker, widget.masker)) {
      return kept.masked;
    }
    final masked = widget.masker.json(value);
    _masked = (source: value, masker: widget.masker, masked: masked);
    return masked;
  }

  @override
  Widget build(BuildContext context) {
    final t = NetLensTokens.of(context);
    if (widget.body == null) {
      return SliverToBoxAdapter(
        child: NlCard(child: Text('No body', style: TextStyle(color: t.textSecondary))),
      );
    }
    return FutureBuilder<Object?>(
      future: _decoded,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return SliverToBoxAdapter(
            child: NlCard(child: Text('Formatting…', style: TextStyle(color: t.textSecondary))),
          );
        }
        final value = snap.data;
        if (value is Map || value is List) {
          return DecoratedSliver(
            decoration: BoxDecoration(
              color: t.codeBg,
              borderRadius: BorderRadius.circular(NetLensRadius.card),
              border: Border.all(color: t.border),
            ),
            sliver: SliverPadding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              sliver: JsonSliver(data: _maskedJson(value), highlight: widget.highlight),
            ),
          );
        }
        final text = value?.toString() ?? '';
        return SliverToBoxAdapter(
          child: NlCard(
            color: t.codeBg,
            shadow: false,
            child: SelectableText(
              text.isEmpty ? '(empty)' : (text.length > 100000 ? '${text.substring(0, 100000)}…' : text),
              style: netLensMono.copyWith(fontSize: 12, color: t.text),
            ),
          ),
        );
      },
    );
  }
}

/// Whether [a] and [b] mask the same values. The page makes a new masker on
/// every build, so this tells it when masked output it already made still
/// holds.
bool _sameMasking(NetLensMasker a, NetLensMasker b) => a.enabled == b.enabled && identical(a.config, b.config);
