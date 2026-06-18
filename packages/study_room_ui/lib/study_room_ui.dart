library study_room_ui;

import 'package:flutter/material.dart';
import 'package:study_room_sdk/study_room_sdk.dart';

class StudyRoomTheme {
  const StudyRoomTheme({
    this.activeColor = const Color(0xFF2563EB),
    this.surfaceColor = const Color(0xFFF8FAFC),
    this.borderColor = const Color(0xFFE2E8F0),
  });

  final Color activeColor;
  final Color surfaceColor;
  final Color borderColor;
}

class StudyRoomCopy {
  const StudyRoomCopy({
    this.emptyMembers = 'No members yet',
    this.emptyMessages = 'No messages yet',
    this.reconnecting = 'Reconnecting',
    this.connected = 'Connected',
  });

  final String emptyMembers;
  final String emptyMessages;
  final String reconnecting;
  final String connected;
}

class StudyRoomView extends StatelessWidget {
  const StudyRoomView({
    required this.room,
    required this.elapsed,
    required this.sessionStatus,
    required this.messages,
    required this.onStart,
    required this.onPause,
    required this.onSendMessage,
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
    final color = connected ? Colors.green.shade700 : Colors.orange.shade800;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Text('$memberCount online'),
          const SizedBox(width: 12),
          Icon(Icons.circle, color: color, size: 10),
          const SizedBox(width: 6),
          Text(connected ? copy.connected : copy.reconnecting),
        ],
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
    if (members.isEmpty) {
      return Center(child: Text(copy.emptyMembers));
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
        return DecoratedBox(
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
                    Text(_presenceLabel(member.status)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _presenceLabel(PresenceStatus status) {
    switch (status) {
      case PresenceStatus.focusing:
        return 'Focusing';
      case PresenceStatus.online:
        return 'Online';
      case PresenceStatus.idle:
        return 'Idle';
      case PresenceStatus.away:
        return 'Away';
      case PresenceStatus.offline:
        return 'Offline';
    }
  }

  String _initial(String name) {
    if (name.trim().isEmpty) {
      return '?';
    }
    return name.characters.first.toUpperCase();
  }
}

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
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _format(elapsed),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          if (status == StudySessionStatus.running)
            IconButton(
              tooltip: 'Pause',
              icon: const Icon(Icons.pause),
              onPressed: onPause,
            )
          else
            IconButton(
              tooltip: status == StudySessionStatus.paused ? 'Resume' : 'Start',
              icon: const Icon(Icons.play_arrow),
              onPressed: status == StudySessionStatus.paused
                  ? (onResume ?? onStart)
                  : onStart,
            ),
          IconButton(
            tooltip: 'Finish',
            icon: const Icon(Icons.stop),
            onPressed: onFinish,
          ),
        ],
      ),
    );
  }

  String _format(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class ChatPanel extends StatefulWidget {
  const ChatPanel({
    required this.messages,
    required this.onSend,
    this.copy = const StudyRoomCopy(),
    super.key,
  });

  final List<ChatMessage> messages;
  final Future<void> Function(String text) onSend;
  final StudyRoomCopy copy;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _controller = TextEditingController();
  var _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          Expanded(
            child: widget.messages.isEmpty
                ? Center(child: Text(widget.copy.emptyMessages))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: widget.messages.length,
                    itemBuilder: (context, index) {
                      final message = widget.messages[index];
                      return ListTile(
                        dense: true,
                        title: Text(message.senderName),
                        subtitle: Text(message.text),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Message',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Send',
                  icon: _sending
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  onPressed: _sending ? null : _send,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }
    setState(() => _sending = true);
    try {
      await widget.onSend(text);
      _controller.clear();
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }
}
