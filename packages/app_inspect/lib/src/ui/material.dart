/// Flutter's Material library, for the inspector's own screens.
///
/// Flutter 3.47 deprecated `package:flutter/material.dart` in favor of the
/// `material_ui` package. AppInspect keeps the framework's copy for now:
///
/// * `material_ui` needs Flutter 3.47 or later, and AppInspect supports
///   Flutter 3.27 and later.
/// * AppInspect reads the theme of the app it sits in. Most apps still build
///   it with the framework's MaterialApp, and `material_ui` has its own Theme
///   class. AppInspect reads both: see `AppInspectAppTheme`.
///
/// This file and `cupertino.dart` are the only ones that import the framework
/// libraries, so moving to `material_ui` later changes two lines.
library;

// ignore: deprecated_member_use
export 'package:flutter/material.dart';
