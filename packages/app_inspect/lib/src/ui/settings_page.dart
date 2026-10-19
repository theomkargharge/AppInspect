import 'package:flutter/material.dart';

import '../format.dart';
import '../app_inspect.dart';
import '../version.dart';
import 'kit.dart';
import 'kit_controls.dart';
import 'theme.dart';

/// Masking, theme, slow-call limit and storage.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable:
          Listenable.merge([AppInspect.store, AppInspect.maskData, AppInspect.darkTheme, AppInspect.slowThreshold]),
      builder: (context, _) {
        final t = AppInspectTokens.of(context);
        final config = AppInspect.config;
        final limit = AppInspect.slowThreshold.value;
        final limits = {
          const Duration(milliseconds: 500),
          const Duration(seconds: 1),
          const Duration(seconds: 2),
          const Duration(seconds: 3),
          limit,
        }.toList()
          ..sort();
        return Scaffold(
          // Scrolls under the home indicator instead of stopping above it.
          body: SafeArea(
            bottom: false,
            child: ListView(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 40 + MediaQuery.paddingOf(context).bottom),
              children: [
                Row(
                  children: [
                    NlIconButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      tooltip: 'Back',
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 12),
                    Text('Settings',
                        style:
                            TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: t.text)),
                  ],
                ),
                const NlSectionLabel('Privacy'),
                NlCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: NlSwitchRow(
                    icon: Icons.shield_rounded,
                    color: t.ok,
                    background: t.okSoft,
                    title: 'Mask sensitive data',
                    subtitle: 'Tokens, passwords and cookies, on screen and in exports',
                    value: AppInspect.maskData.value,
                    onChanged: (v) => AppInspect.maskData.value = v,
                  ),
                ),
                const NlSectionLabel('Appearance'),
                NlCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('AppInspect only. Your app keeps its own theme.',
                          style: TextStyle(fontSize: 13, color: t.textSecondary)),
                      const SizedBox(height: 12),
                      NlSegmented<bool>(
                        value: AppInspect.darkTheme.value,
                        onChanged: (v) => AppInspect.darkTheme.value = v,
                        options: const [(false, 'Light'), (true, 'Dark')],
                      ),
                    ],
                  ),
                ),
                const NlSectionLabel('Slow call limit'),
                NlCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Calls slower than this are flagged.',
                          style: TextStyle(fontSize: 13, color: t.textSecondary)),
                      const SizedBox(height: 12),
                      NlSegmented<Duration>(
                        value: limit,
                        onChanged: (d) => AppInspect.slowThreshold.value = d,
                        options: [for (final d in limits) (d, formatDuration(d))],
                      ),
                    ],
                  ),
                ),
                const NlSectionLabel('Storage'),
                NlCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Meter(
                          label: 'Calls', used: AppInspect.store.calls.length, max: config.maxCalls, color: t.accent),
                      const SizedBox(height: 14),
                      _Meter(
                          label: 'Log entries',
                          used: AppInspect.store.logs.length,
                          max: config.maxLogs,
                          color: t.violet),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            foregroundColor: t.err, side: BorderSide(color: t.err.withValues(alpha: 0.4))),
                        onPressed: () {
                          AppInspect.store
                            ..clear()
                            ..clearLogs();
                          showNlToast(context, 'Calls and logs cleared');
                        },
                        icon: const Icon(Icons.delete_sweep_rounded, size: 19),
                        label: const Text('Clear calls and logs'),
                      ),
                    ],
                  ),
                ),
                const NlSectionLabel('About'),
                NlCard(
                  child: Text(
                    'AppInspect $appInspectVersion. On in debug builds, and in other builds only with '
                    '--dart-define=APP_INSPECT=true. Production builds don\'t contain it.',
                    style: TextStyle(fontSize: 13, height: 1.5, color: t.textSecondary),
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

/// How full a buffer is, as a bar that fills when it changes.
class _Meter extends StatelessWidget {
  const _Meter({required this.label, required this.used, required this.max, required this.color});

  final String label;
  final int used;
  final int max;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = AppInspectTokens.of(context);
    final fraction = max == 0 ? 0.0 : (used / max).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: t.text)),
            const Spacer(),
            Text('$used of $max', style: TextStyle(fontSize: 12.5, color: t.textSecondary)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: fraction),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, f, _) => LinearProgressIndicator(
              value: f,
              minHeight: 8,
              color: color,
              backgroundColor: t.surfaceAlt,
            ),
          ),
        ),
      ],
    );
  }
}
