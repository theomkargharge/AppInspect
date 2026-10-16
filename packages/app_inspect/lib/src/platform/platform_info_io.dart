import 'dart:io';

/// True under `flutter test`, which sets FLUTTER_TEST.
bool get isFlutterTest => Platform.environment.containsKey('FLUTTER_TEST');

/// The operating system and its version, such as `iOS 26.2 (23C54)`.
String get operatingSystemDescription {
  final name = switch (Platform.operatingSystem) {
    'ios' => 'iOS',
    'android' => 'Android',
    'macos' => 'macOS',
    'windows' => 'Windows',
    'linux' => 'Linux',
    final other => other,
  };
  // iOS reports "Version 26.2 (Build 23C54)".
  final version = Platform.operatingSystemVersion
      .replaceFirst(RegExp(r'^Version '), '')
      .replaceFirst('(Build ', '(');
  return '$name $version';
}
