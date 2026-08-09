import 'dart:async';

import 'package:flutter/material.dart';
import 'package:study_room_sdk/study_room_sdk.dart';

import 'localizations.dart';

class StudyRoomLobbyView extends StatefulWidget {
  const StudyRoomLobbyView({
    required this.sdk,
    required this.currentUserId,
    this.onRoomSelected,
    super.key,
  });

  final StudyRoomSdk sdk;
  final String currentUserId;
  final ValueChanged<StudyRoom>? onRoomSelected;

  @override
  State<StudyRoomLobbyView> createState() => _StudyRoomLobbyViewState();
}

class _StudyRoomLobbyViewState extends State<StudyRoomLobbyView> {
  var _loading = true;
  Object? _error;
  List<StudyRoom> _rooms = const [];
  List<RoomJoinRequest> _requests = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.sdk.rooms.list(),
        widget.sdk.joinRequests.mine(),
      ]);
      if (!mounted) return;
      setState(() {
        _rooms = (results[0] as StudyRoomPage<StudyRoom>).items;
        _requests = (results[1] as StudyRoomPage<RoomJoinRequest>).items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _createRoom() async {
    final copy = StudyRoomLocalizations.of(context);
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(copy.createRoom),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 100,
          decoration: InputDecoration(labelText: copy.roomTitle),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(copy.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(copy.createRoom),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.isEmpty) return;
    await _run(() async {
      final room = await widget.sdk.rooms.create(title);
      await _load();
      widget.onRoomSelected?.call(room);
    });
  }

  Future<void> _requestJoin() async {
    final copy = StudyRoomLocalizations.of(context);
    final controller = TextEditingController();
    final roomId = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(copy.joinRoom),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: copy.roomId),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(copy.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(copy.joinRoom),
          ),
        ],
      ),
    );
    controller.dispose();
    if (roomId == null || roomId.isEmpty) return;
    await _run(() async {
      await widget.sdk.joinRequests.request(roomId);
      await _load();
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(copy.requestSubmitted)));
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (!mounted) return;
      final copy = StudyRoomLocalizations.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(copy.operationFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = StudyRoomLocalizations.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: Text(copy.retry),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  copy.rooms,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              Semantics(
                button: true,
                label: copy.joinRoom,
                child: IconButton(
                  tooltip: copy.joinRoom,
                  onPressed: _requestJoin,
                  icon: const Icon(Icons.person_add_alt_1),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _createRoom,
                icon: const Icon(Icons.add),
                label: Text(copy.createRoom),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_rooms.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text(copy.noRooms)),
            )
          else
            ..._rooms.map(
              (room) => Card(
                child: ListTile(
                  title: Text(room.title),
                  subtitle: Text(
                    '${copy.memberCount(room.members.length)} · ${room.id}',
                  ),
                  trailing: FilledButton.tonal(
                    onPressed: () => widget.onRoomSelected?.call(room),
                    child: Text(copy.open),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 24),
          Text(copy.myRequests, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (_requests.isEmpty)
            Text(copy.noRequests)
          else
            ..._requests.map(
              (request) => ListTile(
                leading: const Icon(Icons.schedule),
                title: Text(request.roomId),
                subtitle: Text(_status(copy, request.status)),
                trailing: request.status == JoinRequestStatus.pending
                    ? TextButton(
                        onPressed: () => _run(() async {
                          await widget.sdk.joinRequests.cancel(request.roomId);
                          await _load();
                        }),
                        child: Text(copy.cancel),
                      )
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

class JoinRequestInboxView extends StatefulWidget {
  const JoinRequestInboxView({
    required this.sdk,
    required this.roomId,
    this.onChanged,
    super.key,
  });
  final StudyRoomSdk sdk;
  final String roomId;
  final VoidCallback? onChanged;

  @override
  State<JoinRequestInboxView> createState() => _JoinRequestInboxViewState();
}

class _JoinRequestInboxViewState extends State<JoinRequestInboxView> {
  List<RoomJoinRequest>? _requests;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final page = await widget.sdk.joinRequests.forRoom(widget.roomId);
      if (mounted)
        setState(() {
          _requests = page.items;
          _error = null;
        });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _decide(
    RoomJoinRequest request,
    JoinRequestStatus decision,
  ) async {
    await widget.sdk.joinRequests.decide(widget.roomId, request.id, decision);
    await _load();
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final copy = StudyRoomLocalizations.of(context);
    if (_requests == null && _error == null)
      return const Center(child: CircularProgressIndicator());
    if (_error != null)
      return Center(
        child: FilledButton(onPressed: _load, child: Text(copy.retry)),
      );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          copy.pendingRequests,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        if (_requests!.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Text(copy.noRequests),
          ),
        ..._requests!.map(
          (request) => Card(
            child: ListTile(
              title: Text(request.displayName),
              subtitle: Text(request.userId),
              trailing: Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () =>
                        _decide(request, JoinRequestStatus.rejected),
                    child: Text(copy.reject),
                  ),
                  FilledButton(
                    onPressed: () =>
                        _decide(request, JoinRequestStatus.approved),
                    child: Text(copy.approve),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class RoomMemberManagementView extends StatefulWidget {
  const RoomMemberManagementView({
    required this.sdk,
    required this.room,
    required this.currentUserId,
    this.onChanged,
    super.key,
  });
  final StudyRoomSdk sdk;
  final StudyRoom room;
  final String currentUserId;
  final ValueChanged<StudyRoom>? onChanged;

  @override
  State<RoomMemberManagementView> createState() =>
      _RoomMemberManagementViewState();
}

class _RoomMemberManagementViewState extends State<RoomMemberManagementView> {
  late StudyRoom _room = widget.room;

  Future<void> _refresh() async {
    final room = await widget.sdk.rooms.get(_room.id);
    if (!mounted) return;
    setState(() => _room = room);
    widget.onChanged?.call(room);
  }

  Future<void> _remove(StudyMember member) async {
    await widget.sdk.members.remove(_room.id, member.id);
    await _refresh();
  }

  Future<void> _transfer(StudyMember member) async {
    final room = await widget.sdk.members.transferOwnership(
      _room.id,
      member.id,
    );
    if (!mounted) return;
    setState(() => _room = room);
    widget.onChanged?.call(room);
  }

  @override
  Widget build(BuildContext context) {
    final copy = StudyRoomLocalizations.of(context);
    final isOwner = _room.members.any(
      (member) =>
          member.id == widget.currentUserId && member.role == RoomRole.owner,
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(copy.members, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        ..._room.members.map(
          (member) => Card(
            child: ListTile(
              leading: CircleAvatar(
                child: Text(
                  member.displayName.isEmpty
                      ? '?'
                      : member.displayName.characters.first,
                ),
              ),
              title: Text(member.displayName),
              subtitle: Text(
                member.role == RoomRole.owner ? copy.owner : copy.member,
              ),
              trailing:
                  !isOwner ||
                      member.id == widget.currentUserId ||
                      member.role == RoomRole.owner
                  ? null
                  : PopupMenuButton<String>(
                      onSelected: (value) => value == 'transfer'
                          ? _transfer(member)
                          : _remove(member),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'transfer',
                          child: Text(copy.transferOwnership),
                        ),
                        PopupMenuItem(
                          value: 'remove',
                          child: Text(copy.remove),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

String _status(StudyRoomLocalizations copy, JoinRequestStatus status) =>
    switch (status) {
      JoinRequestStatus.pending => copy.pending,
      JoinRequestStatus.approved => copy.approved,
      JoinRequestStatus.rejected => copy.rejected,
      JoinRequestStatus.cancelled => copy.cancelled,
    };
