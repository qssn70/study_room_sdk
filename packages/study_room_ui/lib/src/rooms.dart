import 'package:flutter/material.dart';
import 'package:study_room_sdk/study_room_sdk.dart';

import 'chat.dart';
import 'localizations.dart';
import 'room_style.dart';
import 'sessions.dart';

export 'room_management.dart'
    show JoinRequestInboxView, RoomMemberManagementView, StudyRoomLobbyView;
export 'room_style.dart' show StudyRoomCopy, StudyRoomTheme;

class StudyRoomView extends StatelessWidget {
  const StudyRoomView({
    required this.room,
    required this.elapsed,
    required this.sessionStatus,
    required this.messages,
    required this.onStart,
    required this.onPause,
    required this.onSendMessage,
    this.onResume,
    this.onFinish,
    this.connected = true,
    this.theme = const StudyRoomTheme(),
    this.copy = const StudyRoomCopy(),
    super.key,
  });

  final StudyRoom room;
  final Duration elapsed;
  final StudySessionStatus sessionStatus;
  final List<ChatMessage> messages;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback? onResume;
  final VoidCallback? onFinish;
  final Future<void> Function(String text) onSendMessage;
  final bool connected;
  final StudyRoomTheme theme;
  final StudyRoomCopy copy;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: theme.surfaceColor,
      child: SafeArea(
        child: Column(
          children: [
            RoomHeader(
              title: room.title,
              memberCount: room.members.length,
              connected: connected,
              copy: copy,
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 720;
                  final members = MemberGrid(
                    members: room.members,
                    copy: copy,
                    theme: theme,
                  );
                  final activity = Column(
                    children: [
                      FocusTimer(
                        elapsed: elapsed,
                        status: sessionStatus,
                        onStart: onStart,
                        onPause: onPause,
                        onResume: onResume,
                        onFinish: onFinish,
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ChatPanel(
                          messages: messages,
                          onSend: onSendMessage,
                          copy: copy,
                        ),
                      ),
                    ],
                  );
                  if (wide) {
                    return Row(
                      children: [
                        Expanded(child: members),
                        const VerticalDivider(width: 1),
                        Expanded(child: activity),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      Expanded(child: members),
                      const Divider(height: 1),
                      Expanded(child: activity),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RoomHeader extends StatelessWidget {
  const RoomHeader({
    required this.title,
    required this.memberCount,
    required this.connected,
    this.copy = const StudyRoomCopy(),
    super.key,
  });

  final String title;
  final int memberCount;
  final bool connected;
  final StudyRoomCopy copy;

  @override
  Widget build(BuildContext context) {
    final localizations = studyRoomLocalizationsOf(context);
    final color = connected ? Colors.green.shade700 : Colors.orange.shade800;
    final connectionLabel = connected
        ? copy.connected ?? localizations.connected
        : copy.reconnecting ?? localizations.reconnecting;
    final connectionStatus = Semantics(
      liveRegion: true,
      label: connectionLabel,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, color: color, size: 10),
            const SizedBox(width: 6),
            Text(connectionLabel),
          ],
        ),
      ),
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
          // Keep the trailing member/connection labels from competing with
          // the title in tablet-sized panes and split-screen layouts.
          final compact = constraints.maxWidth < 900;
          final titleWidget = Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          );
          if (largeText || compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                titleWidget,
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(localizations.onlineMemberCount(memberCount)),
                    connectionStatus,
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: titleWidget),
              Text(localizations.onlineMemberCount(memberCount)),
              const SizedBox(width: 12),
              connectionStatus,
            ],
          );
        },
      ),
    );
  }
}

class MemberGrid extends StatelessWidget {
  const MemberGrid({
    required this.members,
    this.copy = const StudyRoomCopy(),
    this.theme = const StudyRoomTheme(),
    super.key,
  });

  final List<StudyMember> members;
  final StudyRoomCopy copy;
  final StudyRoomTheme theme;

  @override
  Widget build(BuildContext context) {
    final localizations = studyRoomLocalizationsOf(context);
    if (members.isEmpty) {
      return Center(
        child: Text(copy.emptyMembers ?? localizations.emptyMembers),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisExtent: 136,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: members.length,
      itemBuilder: (context, index) {
        final member = members[index];
        final presence = _presenceLabel(member.status, localizations);
        return Semantics(
          container: true,
          label: '${member.displayName}, $presence',
          child: ExcludeSemantics(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: theme.borderColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: theme.activeColor.withValues(alpha: 0.12),
                            image: member.avatarUrl.isEmpty
                                ? null
                                : DecorationImage(
                                    image: NetworkImage(member.avatarUrl),
                                    fit: BoxFit.cover,
                                  ),
                          ),
                          child: member.avatarUrl.isEmpty
                              ? Text(_initial(member.displayName))
                              : null,
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: 120,
                          child: Text(
                            member.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(presence),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _presenceLabel(
    PresenceStatus status,
    StudyRoomLocalizations localizations,
  ) {
    return switch (status) {
      PresenceStatus.focusing => localizations.presenceFocusing,
      PresenceStatus.online => localizations.presenceOnline,
      PresenceStatus.idle => localizations.presenceIdle,
      PresenceStatus.away => localizations.presenceAway,
      PresenceStatus.offline => localizations.presenceOffline,
    };
  }

  String _initial(String name) {
    if (name.trim().isEmpty) return '?';
    return name.characters.first.toUpperCase();
  }
}

class SilentCompanionTheme {
  const SilentCompanionTheme({
    this.avatarSize = 40,
    this.focusingColor = const Color(0xFF16A34A),
    this.onlineColor = const Color(0xFF2563EB),
    this.idleColor = const Color(0xFF64748B),
    this.awayColor = const Color(0xFFF59E0B),
  });

  final double avatarSize;
  final Color focusingColor;
  final Color onlineColor;
  final Color idleColor;
  final Color awayColor;

  Color colorFor(PresenceStatus status) => switch (status) {
    PresenceStatus.focusing => focusingColor,
    PresenceStatus.online => onlineColor,
    PresenceStatus.idle || PresenceStatus.offline => idleColor,
    PresenceStatus.away => awayColor,
  };

  IconData iconFor(PresenceStatus status) => switch (status) {
    PresenceStatus.focusing => Icons.radio_button_checked,
    PresenceStatus.away => Icons.local_cafe,
    PresenceStatus.online ||
    PresenceStatus.idle ||
    PresenceStatus.offline => Icons.circle_outlined,
  };
}

class SilentCompanionList extends StatelessWidget {
  const SilentCompanionList({
    required this.currentUserId,
    required this.members,
    this.theme = const SilentCompanionTheme(),
    super.key,
  });

  final String currentUserId;
  final List<StudyMember> members;
  final SilentCompanionTheme theme;

  @override
  Widget build(BuildContext context) {
    final localizations = studyRoomLocalizationsOf(context);
    final visible = members
        .where(
          (member) =>
              member.id != currentUserId &&
              member.status != PresenceStatus.offline,
        )
        .toList(growable: false);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: visible.isEmpty
          ? SizedBox(
              height: 48,
              child: Center(child: Text(localizations.noCompanions)),
            )
          : SingleChildScrollView(
              key: ValueKey(visible.map((member) => member.id).join(',')),
              scrollDirection: Axis.horizontal,
              child: Row(
                children: visible
                    .map(
                      (member) => Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: _CompanionAvatar(
                          member: member,
                          theme: theme,
                          presence: _presenceLabel(
                            member.status,
                            localizations,
                          ),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
    );
  }

  String _presenceLabel(
    PresenceStatus status,
    StudyRoomLocalizations localizations,
  ) => switch (status) {
    PresenceStatus.focusing => localizations.presenceFocusing,
    PresenceStatus.online => localizations.presenceOnline,
    PresenceStatus.idle => localizations.presenceIdle,
    PresenceStatus.away => localizations.presenceAway,
    PresenceStatus.offline => localizations.presenceOffline,
  };
}

class _CompanionAvatar extends StatelessWidget {
  const _CompanionAvatar({
    required this.member,
    required this.theme,
    required this.presence,
  });

  final StudyMember member;
  final SilentCompanionTheme theme;
  final String presence;

  @override
  Widget build(BuildContext context) {
    final size = theme.avatarSize;
    final color = theme.colorFor(member.status);
    return Semantics(
      container: true,
      label: '${member.displayName}, $presence',
      child: ExcludeSemantics(
        child: SizedBox(
          width: size + 28,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: size,
                    height: size,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 2),
                      image: member.avatarUrl.isEmpty
                          ? null
                          : DecorationImage(
                              image: NetworkImage(member.avatarUrl),
                              fit: BoxFit.cover,
                            ),
                      color: color.withValues(alpha: 0.10),
                    ),
                    child: member.avatarUrl.isEmpty
                        ? Text(_initial(member.displayName))
                        : null,
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        theme.iconFor(member.status),
                        size: 16,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                member.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _initial(String name) {
    if (name.trim().isEmpty) return '?';
    return name.characters.first.toUpperCase();
  }
}
