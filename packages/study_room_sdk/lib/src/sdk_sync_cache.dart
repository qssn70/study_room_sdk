part of 'sdk.dart';

extension _StudyRoomSdkSyncCache on StudyRoomSdk {
  Future<bool> _synchronize(
    int generation, {
    StudyRoomCancellationToken? cancellationToken,
    bool bufferAlreadyStarted = false,
  }) async {
    if (!bufferAlreadyStarted) _beginEventBuffer();
    final previous = _syncState;
    final nextRooms = <String, StudyRoom>{};
    final nextSessions = <String, List<StudySessionState>>{};
    final nextMessages = <String, List<ChatMessage>>{};
    final nextOwnerInbox = <String, List<RoomJoinRequest>>{};
    final staleRooms = <String>{};
    var myRequests = previous.myJoinRequests;
    var personalDataStale = false;
    try {
      final roomIds = _joinedRoomIds.toList(growable: false);
      var nextRoomIndex = 0;
      Future<void> worker() async {
        while (nextRoomIndex < roomIds.length) {
          final roomId = roomIds[nextRoomIndex];
          nextRoomIndex += 1;
          _ensureGeneration(generation);
          await _synchronizeRoom(
            roomId,
            previous: previous,
            nextRooms: nextRooms,
            nextSessions: nextSessions,
            nextMessages: nextMessages,
            nextOwnerInbox: nextOwnerInbox,
            staleRooms: staleRooms,
            cancellationToken: cancellationToken,
          );
        }
      }

      await Future.wait(
        List.generate(roomIds.length.clamp(0, 4), (_) => worker()),
      );
      try {
        myRequests = (await joinRequests.mine(
          limit: 100,
          cancellationToken: cancellationToken,
        )).items;
      } on StudyRoomException catch (error) {
        if (error.kind == StudyRoomExceptionKind.authentication ||
            error.kind == StudyRoomExceptionKind.cancelled) {
          rethrow;
        }
        if (!error.retryable) rethrow;
        personalDataStale = true;
      }
      _ensureGeneration(generation);
      var candidate = StudyRoomSyncState(
        rooms: nextRooms,
        activeSessionsByRoom: nextSessions,
        recentMessagesByRoom: nextMessages,
        myJoinRequests: myRequests,
        ownerInboxByRoom: nextOwnerInbox,
        staleRoomIds: staleRooms,
        personalDataStale: personalDataStale,
        lastSyncedAt: staleRooms.isEmpty && !personalDataStale
            ? _now
            : previous.lastSyncedAt,
      );
      candidate = _finishEventBuffer(candidate);
      _publishSyncState(candidate);
      return candidate.isDegraded;
    } catch (_) {
      final recovered = _finishEventBuffer(previous);
      if (!identical(recovered, previous)) _publishSyncState(recovered);
      rethrow;
    }
  }

  Future<void> _synchronizeRoom(
    String roomId, {
    required StudyRoomSyncState previous,
    required Map<String, StudyRoom> nextRooms,
    required Map<String, List<StudySessionState>> nextSessions,
    required Map<String, List<ChatMessage>> nextMessages,
    required Map<String, List<RoomJoinRequest>> nextOwnerInbox,
    required Set<String> staleRooms,
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    StudyRoom room;
    try {
      room = await rooms.get(roomId, cancellationToken: cancellationToken);
    } on StudyRoomException catch (error) {
      if (error.kind == StudyRoomExceptionKind.authentication ||
          error.kind == StudyRoomExceptionKind.cancelled) {
        rethrow;
      }
      if (error.kind == StudyRoomExceptionKind.authorization ||
          error.kind == StudyRoomExceptionKind.notFound) {
        _removeRoom(roomId, publish: false);
        return;
      }
      if (!error.retryable) rethrow;
      final oldRoom = previous.rooms[roomId] ?? _pendingRoomSeeds[roomId];
      if (oldRoom != null) nextRooms[roomId] = oldRoom;
      nextSessions[roomId] = previous.activeSessionsByRoom[roomId] ?? const [];
      nextMessages[roomId] = previous.recentMessagesByRoom[roomId] ?? const [];
      if (previous.ownerInboxByRoom.containsKey(roomId)) {
        nextOwnerInbox[roomId] = previous.ownerInboxByRoom[roomId] ?? const [];
      }
      staleRooms.add(roomId);
      return;
    }

    nextRooms[roomId] = room;
    try {
      nextSessions[roomId] = await _allActiveSessions(
        roomId,
        cancellationToken: cancellationToken,
      );
    } on StudyRoomException catch (error) {
      if (error.kind == StudyRoomExceptionKind.authentication ||
          error.kind == StudyRoomExceptionKind.cancelled ||
          !error.retryable) {
        rethrow;
      }
      nextSessions[roomId] = previous.activeSessionsByRoom[roomId] ?? const [];
      staleRooms.add(roomId);
    }

    try {
      nextMessages[roomId] = (await chat.history(
        roomId,
        limit: 100,
        cancellationToken: cancellationToken,
      )).items;
    } on StudyRoomException catch (error) {
      if (error.kind == StudyRoomExceptionKind.authentication ||
          error.kind == StudyRoomExceptionKind.cancelled ||
          !error.retryable) {
        rethrow;
      }
      nextMessages[roomId] = previous.recentMessagesByRoom[roomId] ?? const [];
      staleRooms.add(roomId);
    }

    try {
      nextOwnerInbox[roomId] = await _allOwnerJoinRequests(
        roomId,
        cancellationToken: cancellationToken,
      );
    } on StudyRoomException catch (error) {
      if (error.kind == StudyRoomExceptionKind.authentication ||
          error.kind == StudyRoomExceptionKind.cancelled) {
        rethrow;
      }
      if (error.kind == StudyRoomExceptionKind.authorization) {
        nextOwnerInbox.remove(roomId);
        return;
      }
      if (!error.retryable) {
        rethrow;
      }
      if (previous.ownerInboxByRoom.containsKey(roomId)) {
        nextOwnerInbox[roomId] = previous.ownerInboxByRoom[roomId] ?? const [];
      }
      staleRooms.add(roomId);
    }
  }

  Future<List<StudySessionState>> _allActiveSessions(
    String roomId, {
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    final items = <StudySessionState>[];
    String? cursor;
    final seenCursors = <String>{};
    do {
      final page = await sessions.listActive(
        roomId,
        cursor: cursor,
        limit: 100,
        cancellationToken: cancellationToken,
      );
      items.addAll(page.items);
      cursor = page.nextCursor;
      if (cursor != null && !seenCursors.add(cursor)) {
        throw const StudyRoomException(
          'Active-session pagination returned a repeated cursor',
          kind: StudyRoomExceptionKind.protocol,
          code: 'invalid_cursor',
        );
      }
    } while (cursor != null);
    return items;
  }

  Future<List<RoomJoinRequest>> _allOwnerJoinRequests(
    String roomId, {
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    final items = <RoomJoinRequest>[];
    String? cursor;
    final seenCursors = <String>{};
    do {
      final page = await joinRequests.forRoom(
        roomId,
        cursor: cursor,
        limit: 100,
        cancellationToken: cancellationToken,
      );
      items.addAll(page.items);
      cursor = page.nextCursor;
      if (cursor != null && !seenCursors.add(cursor)) {
        throw const StudyRoomException(
          'Owner join-request pagination returned a repeated cursor',
          kind: StudyRoomExceptionKind.protocol,
          code: 'invalid_cursor',
        );
      }
    } while (cursor != null);
    return items;
  }

  void _beginEventBuffer() {
    _bufferedEvents.clear();
    _bufferingEvents = true;
  }

  StudyRoomSyncState _finishEventBuffer(StudyRoomSyncState state) {
    var next = state;
    _bufferingEvents = false;
    final buffered = List<StudyRoomRealtimeEvent>.of(_bufferedEvents);
    _bufferedEvents.clear();
    for (final event in buffered) {
      next = _applyEvent(next, event);
    }
    return next;
  }

  void _handleRealtimeEvent(Map<String, dynamic> value) {
    try {
      final event = StudyRoomRealtimeEvent.fromJson(value);
      if (!_rememberEvent(event.eventId)) return;
      if (_bufferingEvents) {
        _bufferedEvents.add(event);
      } else {
        _publishSyncState(_applyEvent(_syncState, event));
      }
      _events.add(event);
    } catch (error, stackTrace) {
      _addEventError(error, stackTrace);
    }
  }

  bool _rememberEvent(String eventId) {
    if (!_seenEventIds.add(eventId)) return false;
    if (_seenEventIds.length > 1024) _seenEventIds.remove(_seenEventIds.first);
    return true;
  }

  StudyRoomSyncState _applyEvent(
    StudyRoomSyncState state,
    StudyRoomRealtimeEvent event,
  ) {
    final roomId = event.roomId;
    final rooms = Map<String, StudyRoom>.of(state.rooms);
    final sessionsByRoom = _copyLists(state.activeSessionsByRoom);
    final messagesByRoom = _copyLists(state.recentMessagesByRoom);
    final ownerInboxByRoom = _copyLists(state.ownerInboxByRoom);
    var myRequests = List<RoomJoinRequest>.of(state.myJoinRequests);

    switch (event.type) {
      case 'room.state':
        final room = StudyRoom.fromJson(event.payload);
        final current = rooms[room.id];
        if (current == null || current.version <= room.version) {
          rooms[room.id] = room;
        }
      case 'membership.updated':
        if (event.payload['active'] == false && roomId != null) {
          _joinedRoomIds.remove(roomId);
          rooms.remove(roomId);
          sessionsByRoom.remove(roomId);
          messagesByRoom.remove(roomId);
          ownerInboxByRoom.remove(roomId);
        }
      case 'member.presence.updated':
        if (roomId != null && rooms[roomId] != null) {
          final memberId = event.payload['id'] as String?;
          final status = event.payload['status'];
          if (memberId != null && status != null) {
            final room = rooms[roomId]!;
            rooms[roomId] = StudyRoom(
              id: room.id,
              appId: room.appId,
              title: room.title,
              version: event.roomVersion ?? room.version,
              members: room.members
                  .map(
                    (member) => member.id == memberId
                        ? StudyMember(
                            id: member.id,
                            displayName: member.displayName,
                            avatarUrl: member.avatarUrl,
                            status: PresenceStatus.values.firstWhere(
                              (candidate) => candidate.name == status,
                            ),
                            role: member.role,
                          )
                        : member,
                  )
                  .toList(growable: false),
            );
          }
        }
      case 'chat.message.created':
        if (roomId != null) {
          final message = ChatMessage.fromJson(event.payload);
          final messages = messagesByRoom[roomId] ?? <ChatMessage>[];
          if (!messages.any((item) => item.id == message.id)) {
            messages.add(message);
            messages.sort((a, b) => a.sentAt.compareTo(b.sentAt));
            if (messages.length > 100) {
              messages.removeRange(0, messages.length - 100);
            }
          }
          messagesByRoom[roomId] = messages;
        }
      case 'session.updated':
        if (roomId != null) {
          final session = StudySessionState.fromJson(event.payload);
          final sessions = sessionsByRoom[roomId] ?? <StudySessionState>[];
          sessions.removeWhere((item) => item.id == session.id);
          if (session.status != StudySessionStatus.finished) {
            sessions.add(session);
          }
          sessionsByRoom[roomId] = sessions;
        }
      case 'join-request.created':
        if (roomId != null && ownerInboxByRoom.containsKey(roomId)) {
          final request = RoomJoinRequest.fromJson(event.payload);
          final requests = ownerInboxByRoom[roomId] ?? <RoomJoinRequest>[];
          _upsertJoinRequest(requests, request);
          ownerInboxByRoom[roomId] = requests;
        }
      case 'join-request.updated':
        final request = RoomJoinRequest.fromJson(event.payload);
        _upsertJoinRequest(myRequests, request);
    }

    return StudyRoomSyncState(
      rooms: rooms,
      activeSessionsByRoom: sessionsByRoom,
      recentMessagesByRoom: messagesByRoom,
      myJoinRequests: myRequests,
      ownerInboxByRoom: ownerInboxByRoom,
      staleRoomIds: state.staleRoomIds,
      personalDataStale: state.personalDataStale,
      lastSyncedAt: state.lastSyncedAt,
    );
  }

  static Map<String, List<T>> _copyLists<T>(Map<String, List<T>> source) =>
      source.map((key, value) => MapEntry(key, List<T>.of(value)));

  static void _upsertJoinRequest(
    List<RoomJoinRequest> requests,
    RoomJoinRequest request,
  ) {
    requests.removeWhere((item) => item.id == request.id);
    requests.add(request);
  }

  void _publishSyncState(StudyRoomSyncState state) {
    _syncState = state;
    if (!_syncStates.isClosed) _syncStates.add(state);
  }

  void _publishRoom(StudyRoom room) {
    final rooms = Map<String, StudyRoom>.of(_syncState.rooms)..[room.id] = room;
    _publishSyncState(_copySyncState(rooms: rooms));
  }

  void _publishMessage(ChatMessage message) {
    final messages = _copyLists(_syncState.recentMessagesByRoom);
    final roomMessages = messages[message.roomId] ?? <ChatMessage>[];
    if (!roomMessages.any((item) => item.id == message.id)) {
      roomMessages.add(message);
      roomMessages.sort((a, b) => a.sentAt.compareTo(b.sentAt));
      if (roomMessages.length > 100) {
        roomMessages.removeRange(0, roomMessages.length - 100);
      }
    }
    messages[message.roomId] = roomMessages;
    _publishSyncState(_copySyncState(recentMessagesByRoom: messages));
  }

  void _publishSession(StudySessionState session) {
    final sessions = _copyLists(_syncState.activeSessionsByRoom);
    final roomSessions = sessions[session.roomId] ?? <StudySessionState>[];
    roomSessions.removeWhere((item) => item.id == session.id);
    if (session.status != StudySessionStatus.finished) {
      roomSessions.add(session);
    }
    sessions[session.roomId] = roomSessions;
    _publishSyncState(_copySyncState(activeSessionsByRoom: sessions));
  }

  void _publishMyRequest(RoomJoinRequest request) {
    final requests = List<RoomJoinRequest>.of(_syncState.myJoinRequests);
    _upsertJoinRequest(requests, request);
    _publishSyncState(_copySyncState(myJoinRequests: requests));
  }

  void _removeOwnerRequest(String roomId, String requestId) {
    final owner = _copyLists(_syncState.ownerInboxByRoom);
    owner[roomId]?.removeWhere((request) => request.id == requestId);
    _publishSyncState(_copySyncState(ownerInboxByRoom: owner));
  }

  StudyRoomSyncState _copySyncState({
    Map<String, StudyRoom>? rooms,
    Map<String, List<StudySessionState>>? activeSessionsByRoom,
    Map<String, List<ChatMessage>>? recentMessagesByRoom,
    List<RoomJoinRequest>? myJoinRequests,
    Map<String, List<RoomJoinRequest>>? ownerInboxByRoom,
  }) => StudyRoomSyncState(
    rooms: rooms ?? _syncState.rooms,
    activeSessionsByRoom:
        activeSessionsByRoom ?? _syncState.activeSessionsByRoom,
    recentMessagesByRoom:
        recentMessagesByRoom ?? _syncState.recentMessagesByRoom,
    myJoinRequests: myJoinRequests ?? _syncState.myJoinRequests,
    ownerInboxByRoom: ownerInboxByRoom ?? _syncState.ownerInboxByRoom,
    staleRoomIds: _syncState.staleRoomIds,
    personalDataStale: _syncState.personalDataStale,
    lastSyncedAt: _syncState.lastSyncedAt,
  );

  void _removeRoom(String roomId, {bool publish = true}) {
    _joinedRoomIds.remove(roomId);
    _pendingRoomSeeds.remove(roomId);
    final rooms = Map<String, StudyRoom>.of(_syncState.rooms)..remove(roomId);
    final sessions = _copyLists(_syncState.activeSessionsByRoom)
      ..remove(roomId);
    final messages = _copyLists(_syncState.recentMessagesByRoom)
      ..remove(roomId);
    final owner = _copyLists(_syncState.ownerInboxByRoom)..remove(roomId);
    final stale = Set<String>.of(_syncState.staleRoomIds)..remove(roomId);
    if (publish) {
      _publishSyncState(
        StudyRoomSyncState(
          rooms: rooms,
          activeSessionsByRoom: sessions,
          recentMessagesByRoom: messages,
          myJoinRequests: _syncState.myJoinRequests,
          ownerInboxByRoom: owner,
          staleRoomIds: stale,
          personalDataStale: _syncState.personalDataStale,
          lastSyncedAt: _syncState.lastSyncedAt,
        ),
      );
    }
  }
}
