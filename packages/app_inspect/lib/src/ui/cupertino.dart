/// The parts of Flutter's Cupertino library AppInspect uses: iOS-style page
/// transitions, and reading the theme of a CupertinoApp.
///
/// Flutter 3.47 deprecated `package:flutter/cupertino.dart` in favor of the
/// `cupertino_ui` package. AppInspect keeps the framework's copy for the same
/// reasons as in `material.dart`.
library;

// ignore: deprecated_member_use
export 'package:flutter/cupertino.dart'
    show
        CupertinoDynamicColor,
        CupertinoPageTransition,
        CupertinoRouteTransitionMixin,
        CupertinoTheme,
        CupertinoThemeData,
        DefaultCupertinoLocalizations;
