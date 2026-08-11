import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:study_room_sdk/study_room_sdk.dart';

import 'analytics.dart';
import 'audio.dart';
import 'focus_api.dart';
import 'focus_contracts.dart';
import 'focus_desktop.dart';
import 'focus_formatters.dart';
import 'focus_primitives.dart';
import 'focus_store_builder.dart';
import 'focus_timer_components.dart';
import 'localizations.dart';
import 'rooms.dart';

/// Package-internal responsive router. It is intentionally not exported from
/// the package barrel; the public entry point remains [StudyFocusKitView].
class StudyFocusResponsiveLayout extends StatelessWidget {
  const StudyFocusResponsiveLayout({
    required this.model,
    required this.actions,
    super.key,
  });

  final StudyFocusLayoutModel model;
  final StudyFocusActions actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final landscape = constraints.maxWidth > constraints.maxHeight;
        final sidePanelLayout = constraints.maxWidth >= 760 || landscape;
        final suffix = sidePanelLayout ? 'landscape' : 'portrait';
        final styleKey = Key(
          'study_focus_style_${model.shell.visualStyle.name}_$suffix',
        );
        final sizing = StudyFocusSizing.fromConstraints(
          constraints,
          landscape: sidePanelLayout,
        );
        if (landscape && constraints.maxWidth >= 1100) {
          return StudyFocusDesktopShell(
            key: styleKey,
            model: model,
            actions: actions,
            sizing: sizing,
          );
        }
        if (sidePanelLayout) {
          return StudyFocusLandscapeShell(
            key: styleKey,
            model: model,
            actions: actions,
            sizing: sizing,
          );
        }
        return StudyFocusPortraitShell(
          key: styleKey,
          model: model,
          actions: actions,
          sizing: sizing,
        );
      },
    );
  }
}

class StudyFocusPortraitShell extends StatelessWidget {
  const StudyFocusPortraitShell({
    required this.model,
    required this.actions,
    required this.sizing,
    super.key,
  });

  final StudyFocusLayoutModel model;
  final StudyFocusActions actions;
  final StudyFocusSizing sizing;

  @override
  Widget build(BuildContext context) {
    final visualStyle = model.shell.visualStyle;
    final immersive = visualStyle == StudyFocusVisualStyle.immersiveDock;
    final split = visualStyle == StudyFocusVisualStyle.split;
    final goal = StudyFocusGoalCard(model: model, actions: actions);
    final core = StudyFocusCoreCluster(
      model: model,
      actions: actions,
      sizing: sizing,
      goal: split ? null : goal,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        Align(
          alignment: split ? const Alignment(0, -0.42) : Alignment.center,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: core,
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              immersive ? 0 : 24,
              0,
              immersive ? 0 : 24,
              immersive ? 0 : 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PortraitDockDrawer(
                  activePanel: model.shell.activeDockPanel,
                  members: _companions(model, avatarSize: 40),
                  sound: _StudyFocusSoundControls(
                    model: model.sound,
                    actions: actions,
                  ),
                  stats: StudyAnalyticsView(
                    store: model.data.store,
                    date: model.data.date,
                  ),
                ),
                if (split) ...[const SizedBox(height: 16), goal],
                const SizedBox(height: 16),
                _FocusDock(
                  immersive: immersive,
                  activePanel: model.shell.activeDockPanel,
                  onChanged: actions.toggleDockPanel,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class StudyFocusLandscapeShell extends StatelessWidget {
  const StudyFocusLandscapeShell({
    required this.model,
    required this.actions,
    required this.sizing,
    super.key,
  });

  final StudyFocusLayoutModel model;
  final StudyFocusActions actions;
  final StudyFocusSizing sizing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 14,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Center(
              child: StudyFocusCoreCluster(
                model: model,
                actions: actions,
                sizing: sizing,
              ),
            ),
          ),
        ),
        Expanded(
          flex: 10,
          child: _LandscapeInfoPanel(
            members: _companions(model, avatarSize: 32),
            goal: StudyFocusGoalCard(
              model: model,
              actions: actions,
              compact: true,
            ),
            sound: _StudyFocusSoundControls(
              model: model.sound,
              actions: actions,
            ),
            stats: _PrototypeStatsOverview(
              store: model.data.store,
              date: model.data.date,
            ),
          ),
        ),
      ],
    );
  }
}

Widget _companions(StudyFocusLayoutModel model, {required double avatarSize}) {
  if (!model.data.showCompanions) return const SizedBox.shrink();
  return SilentCompanionList(
    currentUserId: model.data.currentUserId,
    members: model.data.members,
    theme: SilentCompanionTheme(
      avatarSize: avatarSize,
      focusingColor: studyFocusAccent,
      onlineColor: studyFocusAccent,
      idleColor: Colors.white.withValues(alpha: 0.42),
      awayColor: studyFocusRest,
    ),
  );
}

class _StudyFocusSoundControls extends StatelessWidget {
  const _StudyFocusSoundControls({required this.model, required this.actions});

  final StudyFocusSoundModel model;
  final StudyFocusActions actions;

  @override
  Widget build(BuildContext context) {
    final localizations = studyRoomLocalizationsOf(context);
    final selected = model.tracks.cast<StudySoundTrack?>().firstWhere(
      (track) => track?.id == model.selectedTrackId,
      orElse: () => model.tracks.isEmpty ? null : model.tracks.first,
    );
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: model.tracks
                .map(
                  (track) => ChoiceChip(
                    label: Text(localizedSoundTrackLabel(track, localizations)),
                    selected: model.selectedTrackId == track.id,
                    onSelected: (_) => actions.toggleSound(track),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton.filled(
                tooltip: model.playing
                    ? localizations.pause
                    : localizations.play,
                icon: Icon(model.playing ? Icons.pause : Icons.play_arrow),
                onPressed: selected == null
                    ? null
                    : () => model.playing
                          ? actions.pauseSound()
                          : actions.toggleSound(selected),
              ),
              Expanded(
                child: Slider(
                  value: model.volume,
                  onChanged: actions.setSoundVolume,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LandscapeInfoPanel extends StatelessWidget {
  const _LandscapeInfoPanel({
    required this.members,
    required this.goal,
    required this.sound,
    required this.stats,
  });

  final Widget members;
  final Widget goal;
  final Widget sound;
  final Widget stats;

  @override
  Widget build(BuildContext context) {
    final localizations = studyRoomLocalizationsOf(context);
    return StudyFocusGlassPanel(
      key: const Key('study_focus_landscape_side_panel'),
      borderRadius: const BorderRadius.horizontal(left: Radius.circular(24)),
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LandscapeCompanionBar(members: members),
            const SizedBox(height: 14),
            _SectionHeading(localizations.todayGoal),
            const SizedBox(height: 6),
            goal,
            const SizedBox(height: 14),
            _SectionHeading(localizations.backgroundSound),
            const SizedBox(height: 6),
            sound,
            const SizedBox(height: 14),
            _SectionHeading(localizations.privateStats),
            const SizedBox(height: 6),
            stats,
          ],
        ),
      ),
    );
  }
}

class _LandscapeCompanionBar extends StatelessWidget {
  const _LandscapeCompanionBar({required this.members});

  final Widget members;

  @override
  Widget build(BuildContext context) {
    final localizations = studyRoomLocalizationsOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              localizations.companions,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.68),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: members),
          ],
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Colors.white.withValues(alpha: 0.42),
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _PrototypeStatsOverview extends StatelessWidget {
  const _PrototypeStatsOverview({required this.store, required this.date});

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
        if (stats == null) return const LinearProgressIndicator();
        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: _PrototypeMetric(
                    value: _formatHours(
                      stats.todayFocusDuration,
                      localizations,
                    ),
                    label: localizations.todayFocus,
                  ),
                ),
                Expanded(
                  child: _PrototypeMetric(
                    value: localizations.pomodoroCountValue(
                      stats.todayPomodoroCount,
                    ),
                    label: localizations.todayPomodoros,
                  ),
                ),
                Expanded(
                  child: _PrototypeMetric(
                    value: localizations.dayCountValue(stats.streakDays),
                    label: localizations.streak,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _PrototypeBars(days: stats.lastSevenDays),
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

class _PrototypeMetric extends StatelessWidget {
  const _PrototypeMetric({required this.value, required this.label});

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

class _PrototypeBars extends StatelessWidget {
  const _PrototypeBars({required this.days});

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

class _PortraitDockDrawer extends StatelessWidget {
  const _PortraitDockDrawer({
    required this.activePanel,
    required this.members,
    required this.sound,
    required this.stats,
  });

  final StudyFocusDockPanel? activePanel;
  final Widget members;
  final Widget sound;
  final Widget stats;

  @override
  Widget build(BuildContext context) {
    final localizations = studyRoomLocalizationsOf(context);
    if (activePanel == null) return const SizedBox.shrink();
    final (title, child) = switch (activePanel!) {
      StudyFocusDockPanel.stats => (localizations.privateStats, stats),
      StudyFocusDockPanel.sound => (localizations.backgroundSound, sound),
      StudyFocusDockPanel.members => (localizations.companions, members),
    };
    return SizedBox(
      height: 220,
      child: StudyFocusGlassPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            Expanded(child: SingleChildScrollView(child: child)),
          ],
        ),
      ),
    );
  }
}

class _FocusDock extends StatelessWidget {
  const _FocusDock({
    required this.immersive,
    required this.activePanel,
    required this.onChanged,
  });

  final bool immersive;
  final StudyFocusDockPanel? activePanel;
  final ValueChanged<StudyFocusDockPanel> onChanged;

  @override
  Widget build(BuildContext context) {
    final localizations = studyRoomLocalizationsOf(context);
    final dock = StudyFocusGlassPanel(
      key: const Key('study_focus_dock'),
      borderRadius: immersive
          ? const BorderRadius.vertical(top: Radius.circular(24))
          : BorderRadius.circular(999),
      padding: EdgeInsets.fromLTRB(18, 10, 18, immersive ? 24 : 10),
      child: SizedBox(
        height: 48,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _DockButton(
              icon: Icons.bar_chart,
              label: localizations.stats,
              selected: activePanel == StudyFocusDockPanel.stats,
              onPressed: () => onChanged(StudyFocusDockPanel.stats),
            ),
            _DockButton(
              icon: Icons.music_note,
              label: localizations.soundRain,
              selected:
                  activePanel == null ||
                  activePanel == StudyFocusDockPanel.sound,
              onPressed: () => onChanged(StudyFocusDockPanel.sound),
            ),
            _DockButton(
              icon: Icons.group,
              label: localizations.members,
              selected: activePanel == StudyFocusDockPanel.members,
              onPressed: () => onChanged(StudyFocusDockPanel.members),
            ),
          ],
        ),
      ),
    );
    if (immersive) return SizedBox(width: double.infinity, child: dock);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 342),
      child: SizedBox(width: double.infinity, child: dock),
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: selected
              ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
              : const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: selected
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.transparent,
            border: selected
                ? Border.all(color: Colors.white.withValues(alpha: 0.12))
                : null,
            borderRadius: BorderRadius.circular(999),
          ),
          child: selected
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: studyFocusAccent),
                    const SizedBox(width: 5),
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.72),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.78),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
