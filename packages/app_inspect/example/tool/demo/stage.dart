import 'package:flutter/material.dart';

/// Who says a line in the story.
enum Speaker { qa, dev }

/// One chat message in the story.
class ChatLine {
  const ChatLine(this.speaker, this.text, this.id);

  final Speaker speaker;
  final String text;
  final int id;
}

/// What the stage shows around the app: the chat, a narration line, a title
/// card and the finger that taps. The demo script changes it as it goes.
class DemoDirector extends ChangeNotifier {
  final List<ChatLine> chat = [];
  String? narration;
  Widget? card;
  Offset? finger;
  Duration fingerMove = const Duration(milliseconds: 450);
  int presses = 0;
  int _ids = 0;

  /// Shows a chat message in place of the one before.
  void say(Speaker speaker, String text) {
    chat
      ..clear()
      ..add(ChatLine(speaker, text, _ids++));
    narration = null;
    notifyListeners();
  }

  /// Replaces the chat with one line that explains what's on screen.
  void narrate(String text) {
    chat.clear();
    narration = text;
    notifyListeners();
  }

  void showCard(Widget card) {
    this.card = card;
    notifyListeners();
  }

  void hideCard() {
    card = null;
    notifyListeners();
  }

  /// Moves the finger to [to], in screen coordinates, over [over].
  void moveFinger(Offset? to, {Duration over = const Duration(milliseconds: 450)}) {
    finger = to;
    fingerMove = over;
    notifyListeners();
  }

  /// Shows a press: the finger squeezes and a ring spreads out.
  void press() {
    presses++;
    notifyListeners();
  }
}

const Color _ink = Color(0xFF0B1020);
const Color _indigo = Color(0xFF4F46E5);
const Color _violet = Color(0xFF7C3AED);

/// The whole screen: a dark backdrop, the story on top and the live app
/// below it. Everything that matters sits in the middle 9:16 band, so the
/// recording can be cut to 1080x1920 for LinkedIn.
class DemoStage extends StatelessWidget {
  const DemoStage({super.key, required this.director, required this.app});

  final DemoDirector director;
  final Widget app;

  static const double captionHeight = 152;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screen = media.size;
    final bandHeight = screen.width * 16 / 9;
    final bandTop = (screen.height - bandHeight) / 2;
    final appRect = Rect.fromLTRB(10, bandTop + captionHeight, screen.width - 10, bandTop + bandHeight - 10);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white, decoration: TextDecoration.none, fontWeight: FontWeight.w500),
        child: Stack(
          children: [
            const Positioned.fill(child: _Backdrop()),
            Positioned.fromRect(
              rect: appRect,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [BoxShadow(color: _indigo.withValues(alpha: 0.35), blurRadius: 40, spreadRadius: -6)],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  // The app lays out for this smaller screen, at full size.
                  child: MediaQuery(
                    data: media.copyWith(
                      size: appRect.size,
                      padding: EdgeInsets.zero,
                      viewPadding: EdgeInsets.zero,
                      viewInsets: EdgeInsets.zero,
                    ),
                    child: app,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              top: bandTop + 8,
              height: captionHeight - 16,
              child: _Story(director: director),
            ),
            Positioned.fill(child: IgnorePointer(child: _Finger(director: director))),
            Positioned(
              left: 0,
              right: 0,
              top: bandTop,
              height: bandHeight,
              child: IgnorePointer(child: _Card(director: director)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.75),
            radius: 1.25,
            colors: [Color(0xFF241F5C), _ink],
          ),
        ),
      );
}

/// The chat or the narration line, above the app.
class _Story extends StatelessWidget {
  const _Story({required this.director});

  final DemoDirector director;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: director,
      builder: (context, _) {
        final narration = director.narration;
        final line = director.chat.isEmpty ? null : director.chat.last;
        // The old line fades out as the new one slides in, so the band is
        // never empty between them.
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 380),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.bottomCenter,
            children: [...previous, if (current != null) current],
          ),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(animation),
              child: child,
            ),
          ),
          child: narration != null
              ? Container(
                  key: ValueKey('n:$narration'),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                  ),
                  child: Text(
                    narration,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 19, height: 1.3, fontWeight: FontWeight.w700, letterSpacing: -0.2),
                  ),
                )
              : line == null
                  ? const SizedBox(key: ValueKey('empty'), width: double.infinity)
                  : _Bubble(line, key: ValueKey(line.id)),
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.line, {super.key});

  final ChatLine line;

  @override
  Widget build(BuildContext context) {
    final mine = line.speaker == Speaker.dev;
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 330),
            child: Container(
              padding: const EdgeInsets.fromLTRB(13, 8, 13, 9),
              decoration: BoxDecoration(
                gradient: mine ? const LinearGradient(colors: [_indigo, _violet]) : null,
                color: mine ? null : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(mine ? 18 : 5),
                  bottomRight: Radius.circular(mine ? 5 : 18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    mine ? 'Me · Flutter dev' : 'QA · Tester',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                      color: mine ? Colors.white.withValues(alpha: 0.8) : _indigo,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    line.text,
                    style: TextStyle(
                      fontSize: 15.5,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: mine ? Colors.white : _ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A fingertip that glides to what the tester taps.
class _Finger extends StatelessWidget {
  const _Finger({required this.director});

  final DemoDirector director;

  static const double size = 34;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: director,
      builder: (context, _) {
        final at = director.finger;
        return Stack(
          children: [
            AnimatedPositioned(
              duration: director.fingerMove,
              curve: Curves.easeInOutCubic,
              left: (at?.dx ?? 0) - size / 2,
              top: (at?.dy ?? 0) - size / 2,
              child: AnimatedOpacity(
                opacity: at == null ? 0 : 1,
                duration: const Duration(milliseconds: 250),
                child: _Tip(presses: director.presses),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip({required this.presses});

  final int presses;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(presses),
      tween: Tween(begin: presses == 0 ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 520),
      builder: (context, t, _) {
        // Squeezes at the start of a press, while a ring spreads out.
        final squeeze = t < 0.3 ? 1 - 0.25 * (t / 0.3) : 0.75 + 0.25 * ((t - 0.3) / 0.7);
        return SizedBox.square(
          dimension: _Finger.size,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              if (t < 1)
                Container(
                  width: _Finger.size * (1 + 1.6 * t),
                  height: _Finger.size * (1 + 1.6 * t),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.7 * (1 - t)), width: 2),
                  ),
                ),
              Transform.scale(
                scale: squeeze,
                child: Container(
                  width: _Finger.size,
                  height: _Finger.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.45),
                    border: Border.all(color: Colors.white, width: 2.5),
                    boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(0, 3))],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A full-band title card that fades over the stage.
class _Card extends StatelessWidget {
  const _Card({required this.director});

  final DemoDirector director;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: director,
      builder: (context, _) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        child: director.card == null
            ? const SizedBox.expand(key: ValueKey('none'))
            : SizedBox.expand(key: ValueKey(director.card.hashCode), child: director.card),
      ),
    );
  }
}

/// The opening card: the problem in two lines.
class IntroCard extends StatelessWidget {
  const IntroCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const _CardFrame(
      children: [
        _Chip('Every Flutter team has had this day'),
        SizedBox(height: 26),
        Text(
          'QA needed one API response.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 31, height: 1.15, fontWeight: FontWeight.w800, letterSpacing: -0.8),
        ),
        SizedBox(height: 14),
        Text(
          'I was in the middle\nof a P0 bug fix. 🔥',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 25, height: 1.25, fontWeight: FontWeight.w700, color: Color(0xFFC7C9FF)),
        ),
      ],
    );
  }
}

/// The closing card: what AppInspect is and how to get it.
class OutroCard extends StatelessWidget {
  const OutroCard({super.key});

  @override
  Widget build(BuildContext context) {
    return _CardFrame(
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_indigo, _violet]),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [BoxShadow(color: _indigo.withValues(alpha: 0.6), blurRadius: 30)],
          ),
          child: const Icon(Icons.manage_search_rounded, color: Colors.white, size: 42),
        ),
        const SizedBox(height: 18),
        const Text('AppInspect', style: TextStyle(fontSize: 38, fontWeight: FontWeight.w800, letterSpacing: -1)),
        const SizedBox(height: 6),
        const Text(
          'In-app network inspector for Flutter',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFFC7C9FF)),
        ),
        const SizedBox(height: 26),
        const Text(
          'QA finds the API call.\nDevs stay in flow.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 25, height: 1.25, fontWeight: FontWeight.w800, letterSpacing: -0.4),
        ),
        const SizedBox(height: 26),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: const Text(
            r'$ flutter pub add app_inspect',
            style:
                TextStyle(fontFamily: 'Menlo', fontSize: 16.5, fontWeight: FontWeight.w600, color: Color(0xFF86EFAC)),
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          'Dio · http · cURL · HAR · Postman · masking\nFree and open source on pub.dev',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, height: 1.5, color: Color(0xFFA5A8D6)),
        ),
      ],
    );
  }
}

class _CardFrame extends StatelessWidget {
  const _CardFrame({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(center: Alignment(0, -0.3), radius: 1.1, colors: [Color(0xFF2B2470), _ink]),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Text(text, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
      );
}
