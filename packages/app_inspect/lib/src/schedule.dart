import 'package:flutter/scheduler.dart';

/// Runs [action] now, or right after this frame when Flutter is building,
/// laying out or painting.
///
/// The app can report an error in the middle of a frame, such as an exception
/// in a build method. Changing widget state right then isn't allowed, so
/// anything that reacts to it waits for the frame to end.
void runWhenSafe(VoidCallback action) {
  final SchedulerBinding binding;
  try {
    binding = SchedulerBinding.instance;
  } catch (_) {
    // No binding yet, so no frame either.
    action();
    return;
  }
  if (binding.schedulerPhase == SchedulerPhase.persistentCallbacks) {
    binding.addPostFrameCallback((_) => action());
  } else {
    action();
  }
}
