import 'dart:async';

import 'package:flutter/material.dart';
import 'package:study_room_sdk/study_room_sdk.dart';

import 'analytics.dart';
import 'audio.dart';
import 'focus_api.dart';
import 'focus_clock.dart';
import 'focus_contracts.dart';
import 'focus_formatters.dart';
import 'focus_primitives.dart';
import 'focus_stats_overview.dart';
import 'focus_timer_components.dart';
import 'localizations.dart';
import 'rooms.dart';

part 'focus_desktop_pages.dart';

/// Package-internal desktop shell for the focus experience.
class StudyFocusDesktopShell extends StatelessWidget {
  const StudyFocusDesktopShell({
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
    final section = model.shell.desktopSection;
    final defaultPage = switch (section) {
      StudyFocusDesktopSection.focus => _focusPage(),
      StudyFocusDesktopSection.analytics => _DesktopAnalyticsPage(
        key: ValueKey('desktop-analytics-${model.data.dataRevision}'),
        store: model.data.store,
        date: model.data.date,
      ),
      StudyFocusDesktopSection.history => _DesktopHistoryPage(
        model: model,
        actions: actions,
      ),
      StudyFocusDesktopSection.settings => _DesktopSettingsPage(
        model: model,
        actions: actions,
      ),
    };
    final page =
        actions.desktopPageBuilder?.call(context, section, defaultPage) ??
        defaultPage;
    return Column(
      key: const Key('study_focus_desktop_shell'),
      children: [
        _DesktopTopNav(
          section: section,
          onSectionChanged: actions.selectDesktopSection,
          onNewTask: () => _editStudyTask(
            context,
            date: model.data.date,
            onSave: actions.saveTask,
            editor: actions.taskEditor,
          ),
        ),
        Expanded(child: page),
      ],
    );
  }

  Widget _focusPage() {
    final visibleMembers = model.data.members.where(
      (member) =>
          member.id != model.data.currentUserId &&
          member.status != PresenceStatus.offline,
    );
    final members = model.data.showCompanions
        ? SilentCompanionList(
            currentUserId: model.data.currentUserId,
            members: model.data.members,
            theme: SilentCompanionTheme(
              avatarSize: 32,
              focusingColor: studyFocusAccent,
              onlineColor: studyFocusAccent,
              idleColor: Colors.white.withValues(alpha: 0.42),
              awayColor: studyFocusRest,
            ),
          )
        : const SizedBox.shrink();
    return Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(56, 30, 56, 34),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: StudyFocusCoreCluster(
                      model: model,
                      actions: actions,
                      sizing: sizing,
                      desktop: true,
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: StudyFocusGoalCard(
                    model: model,
                    actions: actions,
                    desktop: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          key: const Key('study_focus_desktop_sidebar'),
          width: 380,
          child: _DesktopSidePanel(
            members: members,
            onlineCount: visibleMembers.length,
            stats: StudyFocusStatsOverview(
              store: model.data.store,
              date: model.data.date,
            ),
            model: model,
            actions: actions,
          ),
        ),
      ],
    );
  }
}

class _DesktopTopNav extends StatefulWidget {
  const _DesktopTopNav({
    required this.section,
    required this.onSectionChanged,
    required this.onNewTask,
  });

  final StudyFocusDesktopSection section;
  final ValueChanged<StudyFocusDesktopSection> onSectionChanged;
  final VoidCallback onNewTask;

  @override
  State<_DesktopTopNav> createState() => _DesktopTopNavState();
}

class _DesktopTopNavState extends State<_DesktopTopNav> {
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = studyRoomLocalizationsOf(context);
    return SizedBox(
      height: 60,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.18),
          border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: studyFocusAccent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                localizations.focusAppTitle,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 36),
              _DesktopNavItem(
                localizations.focusSection,
                selected: widget.section == StudyFocusDesktopSection.focus,
                onPressed: () =>
                    widget.onSectionChanged(StudyFocusDesktopSection.focus),
              ),
              _DesktopNavItem(
                localizations.analyticsSection,
                selected: widget.section == StudyFocusDesktopSection.analytics,
                onPressed: () =>
                    widget.onSectionChanged(StudyFocusDesktopSection.analytics),
              ),
              _DesktopNavItem(
                localizations.historySection,
                selected: widget.section == StudyFocusDesktopSection.history,
                onPressed: () =>
                    widget.onSectionChanged(StudyFocusDesktopSection.history),
              ),
              _DesktopNavItem(
                localizations.settingsSection,
                selected: widget.section == StudyFocusDesktopSection.settings,
                onPressed: () =>
                    widget.onSectionChanged(StudyFocusDesktopSection.settings),
              ),
              const Spacer(),
              Text(
                TimeOfDay.fromDateTime(
                  StudyFocusClockScope.nowOf(context),
                ).format(context),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.66),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 18),
              FilledButton.icon(
                onPressed: widget.onNewTask,
                icon: const Icon(Icons.add, size: 18),
                label: Text(localizations.newTask),
                style: FilledButton.styleFrom(
                  backgroundColor: studyFocusAccent,
                  foregroundColor: const Color(0xFF10251A),
                  minimumSize: const Size(112, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopNavItem extends StatelessWidget {
  const _DesktopNavItem(
    this.label, {
    required this.onPressed,
    this.selected = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: TextButton(
        onPressed: onPressed,
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Colors.white.withValues(alpha: selected ? 0.96 : 0.58),
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _DesktopSidePanel extends StatelessWidget {
  const _DesktopSidePanel({
    required this.members,
    required this.onlineCount,
    required this.stats,
    required this.model,
    required this.actions,
  });

  final Widget members;
  final int onlineCount;
  final Widget stats;
  final StudyFocusLayoutModel model;
  final StudyFocusActions actions;

  @override
  Widget build(BuildContext context) {
    final localizations = studyRoomLocalizationsOf(context);
    return StudyFocusGlassPanel(
      borderRadius: BorderRadius.zero,
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DesktopSectionHeader(
              title: localizations.silentCompanions,
              trailing: localizations.onlineMemberCount(onlineCount),
            ),
            const SizedBox(height: 14),
            _DesktopPanelCard(child: members),
            const SizedBox(height: 24),
            _DesktopSectionHeader(title: localizations.whiteNoise),
            const SizedBox(height: 12),
            _DesktopSoundGrid(model: model, actions: actions),
            const SizedBox(height: 24),
            _DesktopSectionHeader(title: localizations.todayPrivateData),
            const SizedBox(height: 12),
            _DesktopPanelCard(child: stats),
          ],
        ),
      ),
    );
  }
}

class _DesktopSectionHeader extends StatelessWidget {
  const _DesktopSectionHeader({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.52),
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}

class _DesktopPanelCard extends StatelessWidget {
  const _DesktopPanelCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(padding: const EdgeInsets.all(12), child: child),
    );
  }
}

class _DesktopSoundGrid extends StatelessWidget {
  const _DesktopSoundGrid({required this.model, required this.actions});

  final StudyFocusLayoutModel model;
  final StudyFocusActions actions;

  @override
  Widget build(BuildContext context) {
    final localizations = studyRoomLocalizationsOf(context);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: model.sound.tracks
          .map(
            (track) => SizedBox(
              width: 96,
              child: _DesktopSoundTile(
                icon: _soundIcon(track.id),
                label: track.label,
                displayLabel: localizedSoundTrackLabel(track, localizations),
                selected: model.sound.selectedTrackId == track.id,
                playing:
                    model.sound.playing &&
                    model.sound.selectedTrackId == track.id,
                onPressed: () => unawaited(actions.toggleSound(track)),
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  IconData _soundIcon(String id) => switch (id) {
    'rain' => Icons.water_drop,
    'cafe' => Icons.local_cafe,
    'library' => Icons.local_library,
    'keyboard' => Icons.keyboard,
    _ => Icons.graphic_eq,
  };
}

class _DesktopSoundTile extends StatelessWidget {
  const _DesktopSoundTile({
    required this.icon,
    required this.label,
    required this.displayLabel,
    required this.selected,
    required this.playing,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String displayLabel;
  final bool selected;
  final bool playing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        key: Key('desktop_sound_$label'),
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: selected ? 0.16 : 0.06),
            border: Border.all(
              color: selected
                  ? studyFocusAccent
                  : Colors.white.withValues(alpha: 0.10),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              children: [
                Icon(
                  playing ? Icons.pause : icon,
                  size: 22,
                  color: studyFocusAccent,
                ),
                const SizedBox(height: 8),
                Text(
                  displayLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
