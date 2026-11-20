import 'package:flutter/material.dart';

/// App themes to try AppInspect with. AppInspect takes the colors of the one
/// you pick, in the bubble and in the inspector.
enum DemoTheme {
  orange('Kartly orange', Color(0xFFE2582B)),
  teal('Teal', Color(0xFF00897B)),
  indigo('Indigo', Color(0xFF3F51B5)),
  green('Green', Color(0xFF2E7D32)),
  pink('Pink', Color(0xFFD81B60)),
  // Close to the red of a failure: the bubble turns solid red instead.
  red('Brand red', Color(0xFFD32F2F)),
  mono('Monochrome', Color(0xFF607D8B)),
  // An older Material 2 theme, without Material 3's surface colors.
  material2('Material 2 blue', Color(0xFF2196F3)),
  // Its own page color, which AppInspect puts behind its cards too.
  cream('Red on cream', Color(0xFFB71C1C));

  const DemoTheme(this.label, this.seed);

  final String label;
  final Color seed;

  ThemeData build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return switch (this) {
      material2 => ThemeData(useMaterial3: false, brightness: brightness, primarySwatch: Colors.blue),
      mono => ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: seed,
            brightness: brightness,
            dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
          ),
        ),
      cream => ThemeData(
          colorScheme: dark
              ? const ColorScheme.dark(primary: Color(0xFFEF9A9A), surface: Color(0xFF221A17))
              : const ColorScheme.light(primary: Color(0xFFB71C1C), surface: Color(0xFFFFFCF7)),
          scaffoldBackgroundColor: dark ? const Color(0xFF16110F) : const Color(0xFFF7F1E8),
        ),
      _ => ThemeData(colorSchemeSeed: seed, brightness: brightness),
    };
  }
}

/// The theme picked in the demo, and whether it's light, dark or the system's.
final ValueNotifier<DemoTheme> demoTheme = ValueNotifier(DemoTheme.orange);
final ValueNotifier<ThemeMode> demoThemeMode = ValueNotifier(ThemeMode.system);

/// Opens the theme picker. Put it in an app bar.
class ThemePickerButton extends StatelessWidget {
  const ThemePickerButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        icon: const Icon(Icons.palette_outlined),
        tooltip: 'App theme',
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (_) => const ThemePicker(),
        ),
      );
}

/// Picks the app's theme. The AppInspect bubble stays on top of this sheet,
/// so you can watch it change.
class ThemePicker extends StatelessWidget {
  const ThemePicker({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([demoTheme, demoThemeMode]),
      builder: (context, _) {
        final text = Theme.of(context).textTheme;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('App theme', style: text.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'AppInspect takes the app\'s colors. Watch the bubble, then open it.',
                  style: text.bodyMedium,
                ),
                const SizedBox(height: 16),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto)),
                    ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode)),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode)),
                  ],
                  selected: {demoThemeMode.value},
                  onSelectionChanged: (s) => demoThemeMode.value = s.single,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final theme in DemoTheme.values)
                      ChoiceChip(
                        avatar: CircleAvatar(backgroundColor: theme.seed),
                        label: Text(theme.label),
                        selected: demoTheme.value == theme,
                        onSelected: (_) => demoTheme.value = theme,
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
