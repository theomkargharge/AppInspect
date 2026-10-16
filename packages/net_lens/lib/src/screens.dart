import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'models.dart';
import 'net_lens.dart';
import 'store.dart';

/// Tags every call with the screen on top when it started.
///
/// Get it from `NetLens.navigatorObserver`. Only page routes count as
/// screens, so a dialog or bottom sheet keeps the screen underneath.
class NetLensNavigatorObserver extends NavigatorObserver {
  NetLensNavigatorObserver(this._store);

  final NetLensStore _store;
  final List<Route<dynamic>> _pages = [];
  final Expando<NetLensVisit> _visitOf = Expando<NetLensVisit>('NetLensVisit');
  int _unnamed = 0;

  static final RegExp _screenSuffix = RegExp(r'(Screen|Page|View)$');
  static const Set<String> _frameworkWidgets = {
    'PageView',
    'ListView',
    'GridView',
    'ScrollView',
    'CustomScrollView',
    'SingleChildScrollView',
    'NestedScrollView',
    'TabBarView',
    'ReorderableListView',
    'ListWheelScrollView',
    'CarouselView',
    'AndroidView',
    'UiKitView',
    'AppKitView',
    'HtmlElementView',
  };

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! PageRoute) return;
    // Forget routes from a navigator that's gone, such as after a hot restart.
    _pages.removeWhere((r) => !r.isActive);
    _pages.add(route);
    _enter(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _pages.remove(oldRoute);
    if (newRoute is PageRoute) {
      _pages.add(newRoute);
      _enter(newRoute);
    } else {
      _resumeTop();
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! PageRoute) return;
    _pages.remove(route);
    _resumeTop();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! PageRoute) return;
    final wasTop = _pages.isNotEmpty && identical(_pages.last, route);
    _pages.remove(route);
    if (wasTop) _resumeTop();
  }

  /// Starts a visit for a part of the current route, such as a tab.
  void tagScreen(String name) {
    final top = _pages.isEmpty ? null : _pages.last;
    final current = _store.currentVisit;
    if (current.name == name && (top == null || identical(_visitOf[top], current))) return;
    final visit = _store.startVisit(name);
    if (top != null) _visitOf[top] = visit;
  }

  void _enter(PageRoute<dynamic> route) {
    final routeName = route.settings.name;
    final useful = routeName != null && routeName.isNotEmpty && routeName != '/';
    final visit = _store.startVisit(useful ? routeName : 'Screen ${++_unnamed}');
    _visitOf[route] = visit;
    if (useful) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final found = findScreenWidget(route);
      if (found != null) {
        visit.rename(found);
        _store.refresh();
      }
    });
  }

  void _resumeTop() {
    if (_pages.isEmpty) return;
    final visit = _visitOf[_pages.last];
    if (visit != null) _store.resumeVisit(visit);
  }

  /// The first widget on the route whose type ends in Screen, Page or View,
  /// such as `ProductDetailsScreen`.
  @visibleForTesting
  static String? findScreenWidget(ModalRoute<dynamic> route) {
    final context = route.subtreeContext;
    if (context == null || !context.mounted) return null;
    String? found;
    void visit(Element element, int depth) {
      if (found != null || depth > 80) return;
      final type = element.widget.runtimeType.toString().split('<').first;
      if (!type.startsWith('_') && _screenSuffix.hasMatch(type) && !_frameworkWidgets.contains(type)) {
        found = type;
        return;
      }
      element.visitChildren((child) => visit(child, depth + 1));
    }

    context.visitChildElements((child) => visit(child, 0));
    return found;
  }
}

/// Names a part of a screen that isn't a route, such as a bottom tab or a
/// `PageView` page. Calls made while it's showing are tagged with [name].
///
/// Works with `IndexedStack` tabs: the tag switches when a tab becomes active.
class NetLensScreen extends StatefulWidget {
  const NetLensScreen({super.key, required this.name, required this.child});

  final String name;
  final Widget child;

  @override
  State<NetLensScreen> createState() => _NetLensScreenState();
}

class _NetLensScreenState extends State<NetLensScreen> {
  ValueListenable<bool>? _ticker;
  bool _visible = true;
  bool _wasShowing = false;

  /// IndexedStack hides tabs with Visibility. Offstage-style containers turn
  /// off tickers instead. Either one means the tab isn't showing.
  bool get _showing => _visible && (_ticker?.value ?? true);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!NetLens.isEnabled) return;
    _visible = Visibility.of(context);
    // getValuesNotifier replaces this from Flutter 3.35. Keep the older call
    // so apps on Flutter 3.27 to 3.34 can use NetLens too.
    // ignore: deprecated_member_use
    final ticker = TickerMode.getNotifier(context);
    if (!identical(ticker, _ticker)) {
      _ticker?.removeListener(_update);
      _ticker = ticker..addListener(_update);
    }
    _update();
  }

  @override
  void didUpdateWidget(NetLensScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.name != widget.name && _showing) NetLens.markScreen(widget.name);
  }

  /// Tags the screen each time it starts showing.
  void _update() {
    final showing = _showing;
    if (showing && !_wasShowing) NetLens.markScreen(widget.name);
    _wasShowing = showing;
  }

  @override
  void dispose() {
    _ticker?.removeListener(_update);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
