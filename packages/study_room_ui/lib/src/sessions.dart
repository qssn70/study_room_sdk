import 'package:flutter/material.dart';
import 'package:study_room_sdk/study_room_sdk.dart';

import 'localizations.dart';

export 'focus_ui.dart' show PomodoroTimerView;

class FocusTimer extends StatelessWidget {
  const FocusTimer({
    required this.elapsed,
    required this.status,
    required this.onStart,
    required this.onPause,
    this.onResume,
    this.onFinish,
    super.key,
  });

  final Duration elapsed;
  final StudySessionStatus status;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback? onResume;
  final VoidCallback? onFinish;

  @override
  Widget build(BuildContext context) {
    final localizations = studyRoomLocalizationsOf(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _format(elapsed),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            FocusTraversalOrder(
              order: const NumericFocusOrder(1),
              child: SizedBox.square(
                dimension: 48,
                child: status == StudySessionStatus.running
                    ? IconButton(
                        tooltip: localizations.pause,
                        icon: const Icon(Icons.pause),
                        onPressed: onPause,
                      )
                    : IconButton(
                        tooltip: status == StudySessionStatus.paused
                            ? localizations.resume
                            : localizations.start,
                        icon: const Icon(Icons.play_arrow),
                        onPressed: status == StudySessionStatus.paused
                            ? (onResume ?? onStart)
                            : onStart,
                      ),
              ),
            ),
            FocusTraversalOrder(
              order: const NumericFocusOrder(2),
              child: SizedBox.square(
                dimension: 48,
                child: IconButton(
                  tooltip: localizations.finish,
                  icon: const Icon(Icons.stop),
                  onPressed: onFinish,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _format(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
