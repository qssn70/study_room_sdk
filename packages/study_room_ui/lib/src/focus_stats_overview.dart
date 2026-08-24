import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:study_room_sdk/study_room_sdk.dart';

import 'focus_formatters.dart';
import 'focus_primitives.dart';
import 'focus_store_builder.dart';
import 'localizations.dart';

/// Package-internal statistics summary shared by desktop and responsive shells.
class StudyFocusStatsOverview extends StatelessWidget {
  const StudyFocusStatsOverview({
    required this.store,
    required this.date,
    super.key,
  });

  final StudyStore store;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final localizations = studyRoomLocalizationsOf(context);
    return StudyStoreListenableBuilder<StudyStats>(
      store: store,
      dependency: studyDateKey(date),
      changeKinds: const {StudyStoreChangeKind.dayRecord},
      load: () => StudyAnalytics(store).statsFor(date),
      builder: (context, snapshot) {
        final stats = snapshot.data;
        if (stats == null) {
          return const LinearProgressIndicator();
        }
        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: _Metric(
                    value: _formatHours(
                      stats.todayFocusDuration,
                      localizations,
                    ),
                    label: localizations.todayFocus,
                  ),
                ),
                Expanded(
                  child: _Metric(
                    value: localizations.pomodoroCountValue(
                      stats.todayPomodoroCount,
                    ),
                    label: localizations.todayPomodoros,
                  ),
                ),
                Expanded(
                  child: _Metric(
                    value: localizations.dayCountValue(stats.streakDays),
                    label: localizations.streak,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _Bars(days: stats.lastSevenDays),
          ],
        );
      },
    );
  }

  String _formatHours(Duration duration, StudyRoomLocalizations localizations) {
    final value = NumberFormat.decimalPattern(
      localizations.localeName,
    ).format(duration.inMinutes / 60);
    return localizations.hoursValue(value);
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.54),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({required this.days});

  final List<StudyDayRecord> days;

  @override
  Widget build(BuildContext context) {
    final visibleDays = days.isEmpty
        ? List<StudyDayRecord>.generate(
            7,
            (index) => StudyDayRecord(date: DateTime(1970, 1, index + 1)),
          )
        : days;
    return SizedBox(
      height: 42,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var index = 0; index < visibleDays.length; index++) ...[
            Expanded(
              child: FractionallySizedBox(
                heightFactor: (visibleDays[index].focusDuration.inMinutes / 120)
                    .clamp(0.16, 1.0),
                alignment: Alignment.bottomCenter,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: index == visibleDays.length - 1
                        ? studyFocusAccent
                        : const Color(0xFF546E7A).withValues(alpha: 0.62),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
            if (index != visibleDays.length - 1) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}
