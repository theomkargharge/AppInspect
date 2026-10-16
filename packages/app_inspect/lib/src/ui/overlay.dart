import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../app_inspect.dart';
import 'bubble.dart';
import 'kit.dart';
import 'kit_controls.dart';
import 'list_page.dart';
import 'logs_page.dart';
import 'report_page.dart';
import 'theme.dart';

/// Sits above the app: the app itself, the bubble, and the inspector.
///
/// The inspector brings its own theme, localizations and navigator, so it
/// never touches the app's route stack, theme or analytics.
class AppInspectOverlay extends StatelessWidget {
  const AppInspectOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Bug-report screenshots are taken from here, so they show the app
          // without the bubble or the inspector.
          RepaintBoundary(key: appInspectAppKey, child: child),
          if (AppInspect.config.showBubble) const AppInspectBubble(),
          const _InspectorPresenter(),
        ],
      ),
    );
  }
}

/// Slides the inspector up when it opens, and back down when it closes.
class _InspectorPresenter extends StatefulWidget {
  const _InspectorPresenter();

  @override
  State<_InspectorPresenter> createState() => _InspectorPresenterState();
}

class _InspectorPresenterState extends State<_InspectorPresenter> with SingleTickerProviderStateMixin {
  // Created in initState, not lazily: dispose must never be the first use.
  late final AnimationController _controller;
  late final Animation<double> _curve;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
      reverseDuration: const Duration(milliseconds: 240),
    );
    _curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    AppInspect.isOpen.addListener(_sync);
    if (AppInspect.isOpen.value) {
      _shown = true;
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    AppInspect.isOpen.removeListener(_sync);
    _controller.dispose();
    super.dispose();
  }

  void _sync() {
    if (AppInspect.isOpen.value) {
      setState(() => _shown = true);
      _controller.forward();
    } else {
      _controller.reverse().whenComplete(() {
        if (mounted && !AppInspect.isOpen.value) setState(() => _shown = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_shown) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) {
        final v = _curve.value;
        return IgnorePointer(
          ignoring: !AppInspect.isOpen.value,
          child: Opacity(
            opacity: v.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, 48 * (1 - v)),
              child: Transform.scale(scale: 0.97 + 0.03 * v, child: child),
            ),
          ),
        );
      },
      child: const AppInspectInspector(),
    );
  }
}

/// The full-screen inspector, with its own navigator for its pages.
class AppInspectInspector extends StatefulWidget {
  const AppInspectInspector({super.key});

  @override
  State<AppInspectInspector> createState() => _AppInspectInspectorState();
}

class _AppInspectInspectorState extends State<AppInspectInspector> {
  // Lets the bug-report screenshot fly into its full-screen view.
  final HeroController _heroes = MaterialApp.createMaterialHeroController();

  @override
  void dispose() {
    _heroes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Everything, the PIN screen included, lives inside the navigator, which
    // gives text fields, tooltips and toasts the overlay they need.
    return ValueListenableBuilder<bool>(
      valueListenable: AppInspect.darkTheme,
      builder: (context, dark, _) {
        final theme = buildAppInspectTheme(dark: dark);
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
          child: Localizations(
            locale: const Locale('en', 'US'),
            delegates: const [
              DefaultMaterialLocalizations.delegate,
              DefaultCupertinoLocalizations.delegate,
              DefaultWidgetsLocalizations.delegate,
            ],
            child: Theme(
              data: theme,
              child: DefaultTextEditingShortcuts(
                child: ScaffoldMessenger(
                  child: Material(
                    color: theme.scaffoldBackgroundColor,
                    child: HeroControllerScope(
                      controller: _heroes,
                      child: Navigator(
                        key: appInspectNavigatorKey,
                        onGenerateRoute: (settings) => MaterialPageRoute<void>(
                          settings: settings,
                          builder: (_) => const _InspectorHome(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The Network and Logs tabs, or the PIN screen until the right PIN is entered.
class _InspectorHome extends StatefulWidget {
  const _InspectorHome();

  @override
  State<_InspectorHome> createState() => _InspectorHomeState();
}

class _InspectorHomeState extends State<_InspectorHome> {
  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: AppInspect.isUnlocked ? const _InspectorTabs() : _PinGate(onUnlocked: () => setState(() {})),
      );
}

class _InspectorTabs extends StatefulWidget {
  const _InspectorTabs();

  @override
  State<_InspectorTabs> createState() => _InspectorTabsState();
}

class _InspectorTabsState extends State<_InspectorTabs> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    AppInspect.store.addListener(_openPendingReport);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openPendingReport());
  }

  @override
  void dispose() {
    AppInspect.store.removeListener(_openPendingReport);
    super.dispose();
  }

  /// Holding the bubble asks for the bug report straight away.
  void _openPendingReport() {
    if (!appInspectReportPending || !mounted) return;
    appInspectReportPending = false;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ReportPage()));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppInspect.store,
      builder: (context, _) {
        final errors = AppInspect.store.logs.where((l) => l.level == AppInspectLogLevel.error).length;
        return Scaffold(
          // Each tab is its own Scaffold and handles the keyboard itself.
          resizeToAvoidBottomInset: false,
          extendBody: true,
          body: IndexedStack(index: _tab, children: const [CallListPage(), LogsPage()]),
          bottomNavigationBar: NlNavBar(
            index: _tab,
            onChanged: (i) => setState(() => _tab = i),
            items: [
              const NlNavItem(icon: Icons.sync_alt_rounded, label: 'Network', key: ValueKey('app_inspect_tab_network')),
              NlNavItem(icon: Icons.notes_rounded, label: 'Logs', badge: errors, key: const ValueKey('app_inspect_tab_logs')),
            ],
          ),
        );
      },
    );
  }
}

/// Asks for `AppInspectConfig.pin` before showing anything. A wrong PIN shakes.
class _PinGate extends StatefulWidget {
  const _PinGate({required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  State<_PinGate> createState() => _PinGateState();
}

class _PinGateState extends State<_PinGate> with SingleTickerProviderStateMixin {
  final TextEditingController _pin = TextEditingController();
  late final AnimationController _shake;
  bool _wrong = false;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  }

  @override
  void dispose() {
    _pin.dispose();
    _shake.dispose();
    super.dispose();
  }

  void _submit() {
    if (AppInspect.unlock(_pin.text)) {
      HapticFeedback.lightImpact();
      widget.onUnlocked();
    } else {
      HapticFeedback.heavyImpact();
      _shake.forward(from: 0);
      setState(() {
        _wrong = true;
        _pin.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppInspectTokens.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: NlIconButton(icon: Icons.close_rounded, tooltip: 'Close AppInspect', onPressed: AppInspect.close),
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(color: t.accentSoft, shape: BoxShape.circle),
                            child: Icon(Icons.lock_rounded, size: 34, color: t.accent),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Enter the AppInspect PIN',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: t.text),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'This build is shared outside the team, so the inspector is locked.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, height: 1.45, color: t.textSecondary),
                        ),
                        const SizedBox(height: 26),
                        AnimatedBuilder(
                          animation: _shake,
                          builder: (context, child) => Transform.translate(
                            offset: Offset(math.sin(_shake.value * math.pi * 6) * 10 * (1 - _shake.value), 0),
                            child: child,
                          ),
                          child: TextField(
                            controller: _pin,
                            autofocus: true,
                            obscureText: true,
                            obscuringCharacter: '●',
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            maxLength: 12,
                            style: TextStyle(fontSize: 22, letterSpacing: 10, color: t.text),
                            onChanged: (_) {
                              if (_wrong) setState(() => _wrong = false);
                            },
                            onSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              counterText: '',
                              hintText: 'PIN',
                              errorText: _wrong ? 'Wrong PIN. Try again.' : null,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _submit, child: const Text('Unlock')),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
