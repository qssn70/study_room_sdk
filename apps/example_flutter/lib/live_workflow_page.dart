import 'dart:async';

import 'package:flutter/material.dart';
import 'package:study_room_sdk/study_room_sdk.dart';

import 'live_workflow_controller.dart';

class LiveWorkflowPage extends StatefulWidget {
  const LiveWorkflowPage({
    this.controller,
    this.onOpenOffline,
    this.autoConnect = true,
    super.key,
  });

  final LiveWorkflowController? controller;
  final VoidCallback? onOpenOffline;
  final bool autoConnect;

  @override
  State<LiveWorkflowPage> createState() => _LiveWorkflowPageState();
}

class _LiveWorkflowPageState extends State<LiveWorkflowPage> {
  late final LiveWorkflowController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? LiveWorkflowController();
    _controller.addListener(_changed);
    if (widget.autoConnect) {
      unawaited(_guard('connect', _controller.connect));
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    if (_ownsController) unawaited(_controller.close());
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _guard(String command, Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (!mounted) return;
      final message = _controller.errorFor(command) ?? 'Command failed';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Study Room RC workflow'),
        actions: [
          IconButton(
            key: const Key('workflow_settings'),
            tooltip: 'Connection settings',
            onPressed: _controller.isPending('connect') ? null : _showSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          if (widget.onOpenOffline != null)
            IconButton(
              key: const Key('open_offline_focus'),
              tooltip: 'Offline focus demo',
              onPressed: widget.onOpenOffline,
              icon: const Icon(Icons.timer_outlined),
            ),
        ],
      ),
      body: Column(
        children: [
          _ConnectionStrip(controller: _controller),
          _WorkflowProgress(controller: _controller),
          const Divider(height: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 900) {
                  return Row(
                    key: const Key('workflow_wide'),
                    children: [
                      Expanded(
                        child: _ActorWorkspace(
                          actor: DemoActor.owner,
                          controller: _controller,
                          guard: _guard,
                          confirm: _confirm,
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: _ActorWorkspace(
                          actor: DemoActor.member,
                          controller: _controller,
                          guard: _guard,
                          confirm: _confirm,
                        ),
                      ),
                    ],
                  );
                }
                return DefaultTabController(
                  length: 2,
                  child: Column(
                    key: const Key('workflow_compact'),
                    children: [
                      const TabBar(
                        tabs: [
                          Tab(text: 'Owner'),
                          Tab(text: 'Member'),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: DemoActor.values
                              .map(
                                (actor) => _ActorWorkspace(
                                  actor: actor,
                                  controller: _controller,
                                  guard: _guard,
                                  confirm: _confirm,
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _showSettings() async {
    final current = _controller.endpoints;
    final api = TextEditingController(text: current.apiBaseUri.toString());
    final realtime = TextEditingController(
      text: current.realtimeUri.toString(),
    );
    final token = TextEditingController(text: current.tokenEndpoint.toString());
    final value = await showDialog<LiveEndpointConfig>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connection settings'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('api_endpoint'),
                controller: api,
                decoration: const InputDecoration(labelText: 'HTTP API URL'),
              ),
              TextField(
                key: const Key('realtime_endpoint'),
                controller: realtime,
                decoration: const InputDecoration(labelText: 'Realtime URL'),
              ),
              TextField(
                key: const Key('token_endpoint'),
                controller: token,
                decoration: const InputDecoration(
                  labelText: 'Development token endpoint',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () {
              try {
                Navigator.pop(
                  context,
                  LiveEndpointConfig(
                    apiBaseUri: Uri.parse(api.text.trim()),
                    realtimeUri: Uri.parse(realtime.text.trim()),
                    tokenEndpoint: Uri.parse(token.text.trim()),
                  ),
                );
              } on FormatException {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Enter valid endpoint URLs')),
                );
              }
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Reconnect'),
          ),
        ],
      ),
    );
    api.dispose();
    realtime.dispose();
    token.dispose();
    if (value != null && mounted) {
      await _guard('connect', () => _controller.updateEndpoints(value));
    }
  }
}

class _ConnectionStrip extends StatelessWidget {
  const _ConnectionStrip({required this.controller});
  final LiveWorkflowController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              controller.endpoints.apiBaseUri.toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          for (final actor in DemoActor.values) ...[
            const SizedBox(width: 12),
            _ConnectionBadge(
              actor: actor,
              state: controller.connectionFor(actor),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConnectionBadge extends StatelessWidget {
  const _ConnectionBadge({required this.actor, required this.state});
  final DemoActor actor;
  final StudyRoomConnectionState state;

  @override
  Widget build(BuildContext context) {
    final ready = state == StudyRoomConnectionState.connected;
    return Semantics(
      label: '${actor.displayName} connection ${state.name}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ready ? Icons.cloud_done_outlined : Icons.sync,
            size: 16,
            color: ready ? Colors.green.shade700 : Colors.orange.shade800,
          ),
          const SizedBox(width: 4),
          Text(
            actor.displayName,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _WorkflowProgress extends StatelessWidget {
  const _WorkflowProgress({required this.controller});
  final LiveWorkflowController controller;

  static const labels = <WorkflowAction, String>{
    WorkflowAction.createRoom: 'Create',
    WorkflowAction.requestJoin: 'Request',
    WorkflowAction.approve: 'Approve',
    WorkflowAction.subscribeBoth: 'Subscribe',
    WorkflowAction.ownerChat: 'Owner chat',
    WorkflowAction.memberChat: 'Member chat',
    WorkflowAction.startSession: 'Start',
    WorkflowAction.pauseSession: 'Pause',
    WorkflowAction.resumeSession: 'Resume',
    WorkflowAction.finishSession: 'Finish',
    WorkflowAction.presenceAway: 'Away',
    WorkflowAction.removeMember: 'Remove',
    WorkflowAction.requestAgain: 'Request again',
    WorkflowAction.leave: 'Leave',
    WorkflowAction.rejoin: 'Rejoin',
    WorkflowAction.transferOwnership: 'Transfer',
    WorkflowAction.originalOwnerLeave: 'Old owner leaves',
    WorkflowAction.deleteRoom: 'Delete',
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        key: const Key('workflow_sequence'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        scrollDirection: Axis.horizontal,
        itemCount: WorkflowAction.values.length,
        separatorBuilder: (_, _) => const Icon(Icons.chevron_right, size: 14),
        itemBuilder: (context, index) {
          final action = WorkflowAction.values[index];
          final done = controller.completedActions.contains(action);
          return Row(
            children: [
              Icon(
                done ? Icons.check_circle : Icons.circle_outlined,
                size: 14,
                color: done ? Colors.green.shade700 : Colors.grey.shade600,
              ),
              const SizedBox(width: 4),
              Text(
                labels[action]!,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          );
        },
      ),
    );
  }
}

typedef _Guard =
    Future<void> Function(String command, Future<void> Function() action);
typedef _Confirm = Future<bool> Function(String title, String body);

class _ActorWorkspace extends StatefulWidget {
  const _ActorWorkspace({
    required this.actor,
    required this.controller,
    required this.guard,
    required this.confirm,
  });
  final DemoActor actor;
  final LiveWorkflowController controller;
  final _Guard guard;
  final _Confirm confirm;

  @override
  State<_ActorWorkspace> createState() => _ActorWorkspaceState();
}

class _ActorWorkspaceState extends State<_ActorWorkspace> {
  final _roomTitle = TextEditingController(text: 'RC study room');
  final _message = TextEditingController();

  @override
  void dispose() {
    _roomTitle.dispose();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actor = widget.actor;
    final controller = widget.controller;
    final room = controller.roomFor(actor);
    final membership = controller.membershipFor(actor);
    final isOwner = membership?.role == RoomRole.owner;
    final messages = controller.messagesFor(actor);
    final session = controller.sessionFor(actor);
    final sessionStatus = session?.status ?? StudySessionStatus.idle;
    return ListView(
      key: Key('${actor.name}_workspace'),
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            CircleAvatar(child: Text(actor.displayName.characters.first)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    actor.displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    membership == null ? 'Not a member' : membership.role.name,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (controller.isPending('connect'))
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (actor == DemoActor.owner && controller.roomId == null) ...[
          TextField(
            key: const Key('room_title'),
            controller: _roomTitle,
            decoration: const InputDecoration(labelText: 'Room title'),
          ),
          const SizedBox(height: 8),
          _CommandButton(
            key: const Key('create_room'),
            icon: Icons.add,
            label: 'Create room',
            pending: controller.isPending('create'),
            onPressed: controller.connected
                ? () => widget.guard(
                    'create',
                    () => controller.createRoom(_roomTitle.text),
                  )
                : null,
          ),
        ],
        if (controller.roomId != null) ...[
          _RoomSummary(room: room, roomId: controller.roomId!),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (membership == null && actor == DemoActor.member)
                _CommandButton(
                  key: const Key('member_request_join'),
                  icon: Icons.person_add_alt_1,
                  label: 'Request to join',
                  pending: controller.isPending('request'),
                  onPressed: () => widget.guard(
                    'request',
                    () => controller.requestJoin(
                      again: controller.completedActions.contains(
                        WorkflowAction.removeMember,
                      ),
                    ),
                  ),
                ),
              if (isOwner && !controller.isMember(DemoActor.member))
                _CommandButton(
                  key: Key('${actor.name}_approve'),
                  icon: Icons.check,
                  label: 'Approve request',
                  pending: controller.isPending('approve'),
                  onPressed: () => widget.guard('approve', controller.approve),
                ),
              if (membership != null)
                _CommandButton(
                  key: Key('${actor.name}_subscribe'),
                  icon: Icons.notifications_active_outlined,
                  label: 'Subscribe both',
                  pending: controller.isPending('subscribe'),
                  onPressed: () =>
                      widget.guard('subscribe', controller.subscribeBoth),
                ),
              if (isOwner &&
                  controller.isMember(LiveWorkflowController.otherActor(actor)))
                _CommandButton(
                  key: Key('${actor.name}_remove'),
                  icon: Icons.person_remove_outlined,
                  label: 'Remove other',
                  pending: controller.isPending('remove'),
                  onPressed: () => _confirmed(
                    'Remove member?',
                    'The other actor will lose access to this room.',
                    'remove',
                    () => controller.removeOther(actor),
                  ),
                ),
              if (isOwner &&
                  controller.isMember(LiveWorkflowController.otherActor(actor)))
                _CommandButton(
                  key: Key('${actor.name}_transfer'),
                  icon: Icons.swap_horiz,
                  label: 'Transfer ownership',
                  pending: controller.isPending('transfer'),
                  onPressed: () => _confirmed(
                    'Transfer ownership?',
                    'The other actor will become the room owner.',
                    'transfer',
                    () => controller.transferToOther(actor),
                  ),
                ),
              if (membership != null && !isOwner)
                _CommandButton(
                  key: Key('${actor.name}_leave'),
                  icon: Icons.logout,
                  label: 'Leave room',
                  pending: controller.isPending('${actor.name}-leave'),
                  onPressed: () => _confirmed(
                    'Leave room?',
                    '${actor.displayName} will unsubscribe and clear room data.',
                    '${actor.name}-leave',
                    () => controller.leave(actor),
                  ),
                ),
              if (isOwner)
                _CommandButton(
                  key: Key('${actor.name}_delete'),
                  icon: Icons.delete_outline,
                  label: 'Delete room',
                  pending: controller.isPending('delete'),
                  destructive: true,
                  onPressed: () => _confirmed(
                    'Delete room?',
                    'This permanently deletes the room for both actors.',
                    'delete',
                    () => controller.deleteRoom(actor),
                  ),
                ),
            ],
          ),
        ],
        if (membership != null) ...[
          const Divider(height: 32),
          Text(
            'Session and presence',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Text('Session: ${sessionStatus.name}')),
              Switch(
                key: Key('${actor.name}_away'),
                value: membership.status == PresenceStatus.away,
                onChanged: controller.isPending('${actor.name}-presence')
                    ? null
                    : (value) => widget.guard(
                        '${actor.name}-presence',
                        () => controller.setAway(actor, value),
                      ),
              ),
              const Text('Away'),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              _CommandButton(
                key: Key('${actor.name}_session_start'),
                icon: Icons.play_arrow,
                label: sessionStatus == StudySessionStatus.paused
                    ? 'Resume'
                    : 'Start',
                pending: controller.isPending('${actor.name}-session'),
                onPressed:
                    sessionStatus == StudySessionStatus.idle ||
                        sessionStatus == StudySessionStatus.finished
                    ? () => widget.guard(
                        '${actor.name}-session',
                        () => controller.startSession(actor),
                      )
                    : sessionStatus == StudySessionStatus.paused
                    ? () => widget.guard(
                        '${actor.name}-session',
                        () => controller.updateSession(
                          actor,
                          StudySessionStatus.running,
                        ),
                      )
                    : null,
              ),
              _CommandButton(
                key: Key('${actor.name}_session_pause'),
                icon: Icons.pause,
                label: 'Pause',
                pending: controller.isPending('${actor.name}-session'),
                onPressed: sessionStatus == StudySessionStatus.running
                    ? () => widget.guard(
                        '${actor.name}-session',
                        () => controller.updateSession(
                          actor,
                          StudySessionStatus.paused,
                        ),
                      )
                    : null,
              ),
              _CommandButton(
                key: Key('${actor.name}_session_finish'),
                icon: Icons.stop,
                label: 'Finish',
                pending: controller.isPending('${actor.name}-session'),
                onPressed:
                    sessionStatus == StudySessionStatus.running ||
                        sessionStatus == StudySessionStatus.paused
                    ? () => widget.guard(
                        '${actor.name}-session',
                        () => controller.updateSession(
                          actor,
                          StudySessionStatus.finished,
                        ),
                      )
                    : null,
              ),
            ],
          ),
          const Divider(height: 32),
          Text('Chat', style: Theme.of(context).textTheme.titleSmall),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: messages.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('No messages yet'),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(message.senderName),
                        subtitle: Text(message.text),
                      );
                    },
                  ),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: Key('${actor.name}_message'),
                  controller: _message,
                  decoration: const InputDecoration(labelText: 'Message'),
                  onSubmitted: (_) => _send(),
                ),
              ),
              IconButton.filled(
                key: Key('${actor.name}_send'),
                tooltip: 'Send message',
                onPressed: controller.isPending('${actor.name}-chat')
                    ? null
                    : _send,
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ],
        for (final entry in _errorsForActor(controller, actor))
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              entry,
              key: Key('${actor.name}_error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }

  Iterable<String> _errorsForActor(
    LiveWorkflowController controller,
    DemoActor actor,
  ) sync* {
    final commands = <String>{
      'connect',
      'create',
      'request',
      'approve',
      'subscribe',
      'remove',
      'transfer',
      'delete',
      '${actor.name}-chat',
      '${actor.name}-session',
      '${actor.name}-presence',
      '${actor.name}-leave',
    };
    for (final command in commands) {
      final error = controller.errorFor(command);
      if (error != null) yield error;
    }
  }

  Future<void> _confirmed(
    String title,
    String body,
    String command,
    Future<void> Function() action,
  ) async {
    if (await widget.confirm(title, body)) {
      await widget.guard(command, action);
    }
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty) return;
    await widget.guard(
      '${widget.actor.name}-chat',
      () => widget.controller.sendMessage(widget.actor, text),
    );
    if (widget.controller.errorFor('${widget.actor.name}-chat') == null) {
      _message.clear();
    }
  }
}

class _RoomSummary extends StatelessWidget {
  const _RoomSummary({required this.room, required this.roomId});
  final StudyRoom? room;
  final String roomId;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(room?.title ?? 'Room not subscribed'),
            const SizedBox(height: 2),
            SelectableText(
              roomId,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (room != null)
              Text(
                '${room!.members.length} member(s), version ${room!.version}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

class _CommandButton extends StatelessWidget {
  const _CommandButton({
    required this.icon,
    required this.label,
    required this.pending,
    required this.onPressed,
    this.destructive = false,
    super.key,
  });
  final IconData icon;
  final String label;
  final bool pending;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: pending ? null : onPressed,
      style: destructive
          ? FilledButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            )
          : null,
      icon: pending
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon),
      label: Text(label),
    );
  }
}
