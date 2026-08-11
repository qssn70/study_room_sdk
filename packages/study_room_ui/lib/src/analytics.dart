import 'package:flutter/material.dart';
import 'package:study_room_sdk/study_room_sdk.dart';

import 'focus_store_builder.dart';
import 'localizations.dart';

class StudyStatsView extends StatelessWidget {
  const StudyStatsView({required this.store, required this.date, super.key});

  final StudyStore store;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final localizations = studyRoomLocalizationsOf(context);
    return StudyStoreListenableBuilder<StudyStats>(
      store: store,
      dependency: _dateKey(date),
      changeKinds: const {StudyStoreChangeKind.dayRecord},
      load: () => StudyAnalytics(store).statsFor(date),
      builder: (context, snapshot) {
        final stats = snapshot.data;
        if (stats == null) {
          return const LinearProgressIndicator();
        }
        return Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            _Metric(
              label: localizations.analyticsFocus,
              value: localizations.minutesValue(
                stats.todayFocusDuration.inMinutes,
              ),
            ),
            _Metric(
              label: localizations.analyticsPomodoros,
              value: localizations.pomodoroCountValue(stats.todayPomodoroCount),
            ),
            _Metric(
              label: localizations.analyticsStreak,
              value: localizations.daysValue(stats.streakDays),
            ),
          ],
        );
      },
    );
  }
}

class StudyAnalyticsView extends StatelessWidget {
  const StudyAnalyticsView({
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
      dependency: _dateKey(date),
      changeKinds: const {StudyStoreChangeKind.dayRecord},
      load: () => StudyAnalytics(store).statsFor(date),
      builder: (context, snapshot) {
        final stats = snapshot.data;
        if (stats == null) {
          return const LinearProgressIndicator();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _Metric(
                  label: localizations.analyticsToday,
                  value: localizations.minutesValue(
                    stats.todayFocusDuration.inMinutes,
                  ),
                ),
                _Metric(
                  label: localizations.analyticsCount,
                  value: localizations.pomodorosValue(stats.todayPomodoroCount),
                ),
                _Metric(
                  label: localizations.analyticsRun,
                  value: localizations.daysValue(stats.streakDays),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 42,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: stats.lastSevenDays
                    .map((day) {
                      final height = (day.focusDuration.inMinutes / 120).clamp(
                        0.04,
                        1.0,
                      );
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: FractionallySizedBox(
                            heightFactor: height,
                            alignment: Alignment.bottomCenter,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
            ),
          ],
        );
      },
    );
  }
}

class StudyReportView extends StatelessWidget {
  const StudyReportView({
    required this.store,
    required this.range,
    required this.date,
    super.key,
  });

  final StudyStore store;
  final StudyReportRange range;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final localizations = studyRoomLocalizationsOf(context);
    return StudyStoreListenableBuilder<StudyReport>(
      store: store,
      dependency: '${range.name}:${_dateKey(date)}',
      changeKinds: const {
        StudyStoreChangeKind.dayRecord,
        StudyStoreChangeKind.tasks,
      },
      load: () => StudyAnalytics(store).report(range, date),
      builder: (context, snapshot) {
        final report = snapshot.data;
        if (report == null) {
          return const LinearProgressIndicator();
        }
        final rate = report.taskCompletionRate == null
            ? localizations.noTasksReport
            : localizations.completionValue(
                (report.taskCompletionRate! * 100).round(),
              );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _Metric(
                  label: localizations.analyticsTotal,
                  value: localizations.minutesValue(
                    report.totalFocusDuration.inMinutes,
                  ),
                ),
                _Metric(
                  label: localizations.analyticsSessions,
                  value: localizations.pomodorosValue(
                    report.totalPomodoroCount,
                  ),
                ),
                _Metric(label: localizations.analyticsTasks, value: rate),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              report.totalFocusDuration == Duration.zero &&
                      report.totalPomodoroCount == 0
                  ? localizations.reportNoFocusSessions
                  : localizations.reportSummary(
                      report.totalFocusDuration.inMinutes,
                      report.totalPomodoroCount,
                      report.streakDays,
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 84),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}

String _dateKey(DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  return '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
}
