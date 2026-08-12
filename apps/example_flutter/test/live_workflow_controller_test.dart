import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:study_room_example/live_workflow_controller.dart';
import 'package:study_room_example/live_workflow_page.dart';
import 'package:study_room_sdk/study_room_sdk.dart';

void main() {
  test('fixture token provider caches and honors forceRefresh', () async {
    var requests = 0;
    final provider = DevFixtureTokenProvider(
      endpoint: Uri.parse('http://localhost:4000/token'),
      userId: 'owner',
      displayName: 'Owner',
      now: () => DateTime.utc(2026, 8, 11),
      client: MockClient((request) async {
        requests += 1;
        expect(request.method, 'POST');
        expect(jsonDecode(request.body), {
          'sub': 'owner',
          'displayName': 'Owner',
        });
        return http.Response(
          jsonEncode({
            'accessToken': 'token-$requests',
            'expiresAt': '2026-08-11T01:00:00.000Z',
          }),
          200,
        );
      }),
    );

    final first = await provider.call(const StudyRoomTokenRequest());
    final cached = await provider.call(
      const StudyRoomTokenRequest(minimumValidity: Duration(minutes: 30)),
    );
    final refreshed = await provider.call(
      const StudyRoomTokenRequest(forceRefresh: true),
    );

    expect(first.token, 'token-1');
    expect(cached.token, 'token-1');
    expect(refreshed.token, 'token-2');
    expect(requests, 2);
  });

  test(
    'fixture token provider refreshes at minimumValidity boundary',
    () async {
      var requests = 0;
      final provider = DevFixtureTokenProvider(
        endpoint: Uri.parse('http://localhost:4000/token'),
        userId: 'owner',
        displayName: 'Owner',
        now: () => DateTime.utc(2026, 8, 11),
        client: MockClient((request) async {
          requests += 1;
          return http.Response(
            jsonEncode({
              'accessToken': 'token-$requests',
              'expiresAt': '2026-08-11T01:00:00.000Z',
            }),
            200,
          );
        }),
      );

      final first = await provider.call(const StudyRoomTokenRequest());
      final stillValid = await provider.call(
        const StudyRoomTokenRequest(
          minimumValidity: Duration(minutes: 59, seconds: 59),
        ),
      );
      final atBoundary = await provider.call(
        const StudyRoomTokenRequest(minimumValidity: Duration(hours: 1)),
      );

      expect(first.token, 'token-1');
      expect(stillValid.token, 'token-1');
      expect(atBoundary.token, 'token-2');
      expect(requests, 2);
    },
  );

  test('controller completes the fixed two-user workflow', () async {
    final backend = _FakeBackend();
    final controller = LiveWorkflowController(
      gatewayFactory: (actor, _) => backend.gateway(actor),
    );

    await controller.connect();
    expect(backend.gateways, hasLength(2));
    expect(backend.gateways.values.map(identityHashCode).toSet(), hasLength(2));

    await controller.createRoom('RC room');
    await controller.requestJoin();
    await controller.approve();
    await controller.subscribeBoth();
    expect(controller.isRoomOwner(DemoActor.owner), isTrue);
    expect(controller.isMember(DemoActor.member), isTrue);

    await controller.sendMessage(DemoActor.owner, 'Owner says hello');
    await controller.sendMessage(DemoActor.member, 'Member says hello');
    expect(controller.messagesFor(DemoActor.owner), hasLength(2));
    expect(controller.messagesFor(DemoActor.member), hasLength(2));

    await controller.startSession(DemoActor.member);
    await controller.updateSession(DemoActor.member, StudySessionStatus.paused);
    await controller.updateSession(
      DemoActor.member,
      StudySessionStatus.running,
    );
    await controller.updateSession(
      DemoActor.member,
      StudySessionStatus.finished,
    );
    await controller.setAway(DemoActor.member, true);

    await controller.removeOther(DemoActor.owner);
    expect(controller.isMember(DemoActor.member), isFalse);
    expect(controller.sessionFor(DemoActor.member), isNull);
    expect(backend.gateways[DemoActor.member]!.unsubscribeCalls, 1);
    await controller.requestJoin(again: true);
    await controller.approve();
    await controller.subscribeBoth();
    expect(controller.sessionFor(DemoActor.member), isNull);
    expect(
      controller.membershipFor(DemoActor.member)?.status,
      PresenceStatus.online,
    );
    await controller.startSession(DemoActor.member);
    await controller.updateSession(
      DemoActor.member,
      StudySessionStatus.finished,
    );
    await controller.leave(DemoActor.member);
    expect(controller.isMember(DemoActor.member), isFalse);
    expect(controller.sessionFor(DemoActor.member), isNull);
    expect(backend.gateways[DemoActor.member]!.unsubscribeCalls, 2);
    await controller.requestJoin(again: true);
    await controller.approve();
    await controller.subscribeBoth();
    expect(controller.sessionFor(DemoActor.member), isNull);

    await controller.transferToOther(DemoActor.owner);
    expect(controller.isRoomOwner(DemoActor.member), isTrue);
    await controller.leave(DemoActor.owner);
    expect(controller.sessionFor(DemoActor.owner), isNull);
    expect(backend.gateways[DemoActor.owner]!.unsubscribeCalls, 1);
    await controller.deleteRoom(DemoActor.member);

    expect(controller.roomId, isNull);
    expect(controller.sessionFor(DemoActor.member), isNull);
    expect(backend.gateways[DemoActor.owner]!.unsubscribeCalls, 2);
    expect(backend.gateways[DemoActor.member]!.unsubscribeCalls, 3);
    expect(controller.completedActions, containsAll(WorkflowAction.values));
    await controller.close();
  });

  testWidgets('presence switch follows membership after removal and rejoin', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    late final LiveWorkflowController controller;
    await tester.runAsync(() async {
      final backend = _FakeBackend();
      controller = LiveWorkflowController(
        gatewayFactory: (actor, _) => backend.gateway(actor),
      );
      await controller.connect();
      await controller.createRoom('RC room');
      await controller.requestJoin();
      await controller.approve();
      await controller.subscribeBoth();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: LiveWorkflowPage(controller: controller, autoConnect: false),
      ),
    );
    await tester.pump();

    final awaySwitch = find.byKey(const Key('member_away'));
    expect(tester.widget<Switch>(awaySwitch).value, isFalse);
    await tester.tap(awaySwitch);
    await tester.runAsync(() async {
      while (controller.isPending('member-presence')) {
        await Future<void>.delayed(Duration.zero);
      }
    });
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      controller.membershipFor(DemoActor.member)?.status,
      PresenceStatus.away,
    );
    expect(tester.widget<Switch>(awaySwitch).value, isTrue);
    await tester.runAsync(() => controller.removeOther(DemoActor.owner));
    await tester.pump();
    expect(awaySwitch, findsNothing);

    await tester.runAsync(() async {
      await controller.requestJoin(again: true);
      await controller.approve();
      await controller.subscribeBoth();
    });
    await tester.pump();
    expect(
      controller.membershipFor(DemoActor.member)?.status,
      PresenceStatus.online,
    );
    expect(tester.widget<Switch>(awaySwitch).value, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(controller.close);
  });

  testWidgets('compact workbench switches actors and disables create offline', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = _FakeBackend();
    final controller = LiveWorkflowController(
      gatewayFactory: (actor, _) => backend.gateway(actor),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LiveWorkflowPage(controller: controller, autoConnect: false),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('workflow_compact')), findsOneWidget);
    expect(find.byKey(const Key('owner_workspace')), findsOneWidget);
    expect(find.byKey(const Key('member_workspace')), findsNothing);
    final createButton = find.descendant(
      of: find.byKey(const Key('create_room')),
      matching: find.byType(FilledButton),
    );
    expect(tester.widget<FilledButton>(createButton).onPressed, isNull);

    await tester.runAsync(controller.connect);
    await tester.pump();
    expect(tester.widget<FilledButton>(createButton).onPressed, isNotNull);

    await tester.tap(
      find.descendant(of: find.byType(TabBar), matching: find.text('Member')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('owner_workspace')), findsNothing);
    expect(find.byKey(const Key('member_workspace')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(controller.close);
  });

  testWidgets(
    'destructive commands require confirmation and permissions follow owner',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final backend = _FakeBackend();
      final controller = LiveWorkflowController(
        gatewayFactory: (actor, _) => backend.gateway(actor),
      );
      await tester.runAsync(() async {
        await controller.connect();
        await controller.createRoom('RC room');
        await controller.requestJoin();
        await controller.approve();
        await controller.subscribeBoth();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: LiveWorkflowPage(controller: controller, autoConnect: false),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('owner_remove')), findsOneWidget);
      expect(find.byKey(const Key('owner_transfer')), findsOneWidget);
      expect(find.byKey(const Key('owner_delete')), findsOneWidget);
      expect(find.byKey(const Key('owner_leave')), findsNothing);
      expect(find.byKey(const Key('member_remove')), findsNothing);
      expect(find.byKey(const Key('member_transfer')), findsNothing);
      expect(find.byKey(const Key('member_delete')), findsNothing);
      expect(find.byKey(const Key('member_leave')), findsOneWidget);

      Future<void> cancelCommand(Key key, String title) async {
        await tester.tap(find.byKey(key));
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();
      }

      await cancelCommand(const Key('owner_remove'), 'Remove member?');
      await cancelCommand(const Key('owner_transfer'), 'Transfer ownership?');
      await cancelCommand(const Key('member_leave'), 'Leave room?');
      await cancelCommand(const Key('owner_delete'), 'Delete room?');
      expect(controller.isRoomOwner(DemoActor.owner), isTrue);
      expect(controller.isMember(DemoActor.member), isTrue);
      expect(
        backend.gateways.values.map((gateway) => gateway.unsubscribeCalls),
        [0, 0],
      );

      await tester.tap(find.byKey(const Key('owner_transfer')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();

      expect(controller.isRoomOwner(DemoActor.member), isTrue);
      expect(find.byKey(const Key('owner_remove')), findsNothing);
      expect(find.byKey(const Key('owner_transfer')), findsNothing);
      expect(find.byKey(const Key('owner_delete')), findsNothing);
      expect(find.byKey(const Key('owner_leave')), findsOneWidget);
      expect(find.byKey(const Key('member_remove')), findsOneWidget);
      expect(find.byKey(const Key('member_transfer')), findsOneWidget);
      expect(find.byKey(const Key('member_delete')), findsOneWidget);
      expect(find.byKey(const Key('member_leave')), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(controller.close);
    },
  );

  test('controller exposes per-command pending and errors', () async {
    final backend = _FakeBackend()..failCreate = true;
    final controller = LiveWorkflowController(
      gatewayFactory: (actor, _) => backend.gateway(actor),
    );
    await controller.connect();

    final operation = controller.createRoom('failure');
    expect(controller.isPending('create'), isTrue);
    await expectLater(operation, throwsStateError);
    expect(controller.isPending('create'), isFalse);
    expect(controller.errorFor('create'), contains('create failed'));
    await controller.close();
  });

  test(
    'original owner leave does not depend on asynchronous room sync',
    () async {
      final backend = _FakeBackend();
      final controller = LiveWorkflowController(
        gatewayFactory: (actor, _) => backend.gateway(actor),
      );

      await controller.connect();
      await controller.createRoom('RC room');
      await controller.requestJoin();
      await controller.approve();
      await controller.subscribeBoth();
      await controller.transferToOther(DemoActor.owner);

      // Simulate a delayed target-side ownership event. The workflow should use
      // the successful transfer command, rather than race the member snapshot.
      backend.gateways[DemoActor.member]!._sync = StudyRoomSyncState.empty();
      await controller.leave(DemoActor.owner);

      expect(
        controller.completedActions,
        contains(WorkflowAction.originalOwnerLeave),
      );
      await controller.close();
    },
  );

  test(
    'endpoint updates wait for an in-flight connection and use the new config',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      final createdFor = <LiveEndpointConfig>[];
      final gateways = <_DelayedGateway>[];
      final controller = LiveWorkflowController(
        gatewayFactory: (actor, endpoints) {
          createdFor.add(endpoints);
          final gateway = _DelayedGateway(
            actor,
            startGate: createdFor.length <= 2 ? release.future : null,
            onStart: createdFor.length <= 2
                ? () {
                    if (!started.isCompleted) started.complete();
                  }
                : null,
          );
          gateways.add(gateway);
          return gateway;
        },
      );
      final first = controller.connect();
      await started.future;
      final updated = LiveEndpointConfig(
        apiBaseUri: Uri.parse('https://new.example.test'),
        realtimeUri: Uri.parse('wss://new.example.test/v1/realtime'),
        tokenEndpoint: Uri.parse('https://new.example.test/token'),
      );
      final second = controller.updateEndpoints(updated);
      release.complete();
      await first;
      await second;

      expect(controller.endpoints, same(updated));
      expect(createdFor.skip(2), everyElement(same(updated)));
      expect(
        gateways.take(2),
        everyElement(predicate<_DelayedGateway>((gateway) => gateway.closed)),
      );
      expect(controller.connected, isTrue);
      await controller.close();
    },
  );
}

class _DelayedGateway implements LiveActorGateway {
  _DelayedGateway(this.actor, {this.startGate, this.onStart});

  @override
  final DemoActor actor;
  final Future<void>? startGate;
  final VoidCallback? onStart;
  bool closed = false;
  final _sync = StreamController<StudyRoomSyncState>.broadcast();
  final _connections = StreamController<StudyRoomConnectionState>.broadcast();

  @override
  StudyRoomSyncState get syncState => StudyRoomSyncState.empty();
  @override
  StudyRoomConnectionState get connectionState =>
      StudyRoomConnectionState.stopped;
  @override
  Stream<StudyRoomSyncState> get syncStates => _sync.stream;
  @override
  Stream<StudyRoomConnectionState> get connectionStates => _connections.stream;
  @override
  Future<void> start() async {
    onStart?.call();
    await startGate;
  }

  @override
  Future<void> close() async {
    closed = true;
    await _sync.close();
    await _connections.close();
  }

  Never _unused() => throw UnimplementedError();
  @override
  Future<void> approve(String roomId, String requestId) async => _unused();
  @override
  Future<StudyRoom> createRoom(String title) async => _unused();
  @override
  Future<void> deleteRoom(String roomId) async => _unused();
  @override
  Future<void> leave(String roomId) async => _unused();
  @override
  Future<List<RoomJoinRequest>> pendingRequests(String roomId) async =>
      _unused();
  @override
  Future<void> removeMember(String roomId, String userId) async => _unused();
  @override
  Future<RoomJoinRequest> requestJoin(String roomId) async => _unused();
  @override
  Future<ChatMessage> sendMessage(String roomId, String text) async =>
      _unused();
  @override
  Future<void> setAway(String roomId, bool away) async => _unused();
  @override
  Future<StudySessionState> startSession(String roomId) async => _unused();
  @override
  Future<StudyRoom> subscribe(String roomId) async => _unused();
  @override
  Future<StudyRoom> transferOwnership(String roomId, String userId) async =>
      _unused();
  @override
  Future<void> unsubscribe(String roomId) async => _unused();
  @override
  Future<StudySessionState> updateSession(
    String sessionId,
    StudySessionStatus status,
  ) async => _unused();
}

class _FakeBackend {
  final Map<DemoActor, _FakeGateway> gateways = {};
  StudyRoom? room;
  RoomJoinRequest? request;
  final List<ChatMessage> messages = [];
  final Map<DemoActor, StudySessionState> sessions = {};
  var version = 0;
  var messageCounter = 0;
  var requestCounter = 0;
  var sessionCounter = 0;
  bool failCreate = false;

  _FakeGateway gateway(DemoActor actor) =>
      gateways.putIfAbsent(actor, () => _FakeGateway(this, actor));

  void publish() {
    for (final gateway in gateways.values) {
      gateway.publish();
    }
  }

  void replaceMembers(List<StudyMember> members) {
    final current = room!;
    version += 1;
    room = StudyRoom(
      id: current.id,
      appId: current.appId,
      title: current.title,
      version: version,
      members: members,
    );
    publish();
  }
}

class _FakeGateway implements LiveActorGateway {
  _FakeGateway(this.backend, this.actor);

  final _FakeBackend backend;
  @override
  final DemoActor actor;
  final _syncController = StreamController<StudyRoomSyncState>.broadcast();
  final _connectionController =
      StreamController<StudyRoomConnectionState>.broadcast();
  StudyRoomSyncState _sync = StudyRoomSyncState.empty();
  StudyRoomConnectionState _connection = StudyRoomConnectionState.stopped;
  bool joined = false;
  var unsubscribeCalls = 0;

  @override
  StudyRoomSyncState get syncState => _sync;
  @override
  StudyRoomConnectionState get connectionState => _connection;
  @override
  Stream<StudyRoomSyncState> get syncStates => _syncController.stream;
  @override
  Stream<StudyRoomConnectionState> get connectionStates =>
      _connectionController.stream;

  void publish() {
    final room = backend.room;
    final member =
        room?.members.any((item) => item.id == actor.userId) ?? false;
    if (!member) joined = false;
    final visibleRoom = joined && member ? room : null;
    _sync = StudyRoomSyncState(
      rooms: visibleRoom == null ? {} : {visibleRoom.id: visibleRoom},
      activeSessionsByRoom: visibleRoom == null
          ? {}
          : {
              visibleRoom.id: backend.sessions.values
                  .where(
                    (session) => session.status != StudySessionStatus.finished,
                  )
                  .toList(),
            },
      recentMessagesByRoom: visibleRoom == null
          ? {}
          : {visibleRoom.id: List.of(backend.messages)},
    );
    _syncController.add(_sync);
  }

  @override
  Future<void> start() async {
    _connection = StudyRoomConnectionState.connected;
    _connectionController.add(_connection);
  }

  @override
  Future<StudyRoom> createRoom(String title) async {
    await Future<void>.delayed(Duration.zero);
    if (backend.failCreate) throw StateError('create failed');
    backend.version = 1;
    backend.room = StudyRoom(
      id: 'room-1',
      appId: 'demo',
      title: title,
      version: 1,
      members: [
        StudyMember(
          id: actor.userId,
          displayName: actor.displayName,
          avatarUrl: '',
          status: PresenceStatus.online,
          role: RoomRole.owner,
        ),
      ],
    );
    return backend.room!;
  }

  @override
  Future<RoomJoinRequest> requestJoin(String roomId) async {
    backend.requestCounter += 1;
    backend.request = RoomJoinRequest(
      id: 'request-${backend.requestCounter}',
      roomId: roomId,
      userId: actor.userId,
      displayName: actor.displayName,
      status: JoinRequestStatus.pending,
      createdAt: DateTime.utc(2026, 8, 11),
      updatedAt: DateTime.utc(2026, 8, 11),
    );
    return backend.request!;
  }

  @override
  Future<List<RoomJoinRequest>> pendingRequests(String roomId) async =>
      backend.request == null ? [] : [backend.request!];

  @override
  Future<void> approve(String roomId, String requestId) async {
    final pending = backend.request!;
    final members = List<StudyMember>.of(backend.room!.members)
      ..removeWhere((member) => member.id == pending.userId)
      ..add(
        StudyMember(
          id: pending.userId,
          displayName: pending.displayName,
          avatarUrl: '',
          status: PresenceStatus.online,
        ),
      );
    backend.request = null;
    backend.replaceMembers(members);
  }

  @override
  Future<StudyRoom> subscribe(String roomId) async {
    final member = backend.room!.members.any((item) => item.id == actor.userId);
    if (!member) throw StateError('not a member');
    joined = true;
    backend.publish();
    return backend.room!;
  }

  @override
  Future<void> unsubscribe(String roomId) async {
    unsubscribeCalls += 1;
    joined = false;
    publish();
  }

  @override
  Future<ChatMessage> sendMessage(String roomId, String text) async {
    backend.messageCounter += 1;
    final message = ChatMessage(
      id: 'message-${backend.messageCounter}',
      roomId: roomId,
      senderId: actor.userId,
      senderName: actor.displayName,
      text: text,
      sentAt: DateTime.utc(2026, 8, 11, 0, 0, backend.messageCounter),
    );
    backend.messages.add(message);
    backend.publish();
    return message;
  }

  @override
  Future<StudySessionState> startSession(String roomId) async {
    backend.sessionCounter += 1;
    final session = StudySessionState(
      id: 'session-${backend.sessionCounter}',
      roomId: roomId,
      userId: actor.userId,
      status: StudySessionStatus.running,
      startedAt: DateTime.utc(2026, 8, 11),
      updatedAt: DateTime.utc(2026, 8, 11),
    );
    backend.sessions[actor] = session;
    backend.publish();
    return session;
  }

  @override
  Future<StudySessionState> updateSession(
    String sessionId,
    StudySessionStatus status,
  ) async {
    final previous = backend.sessions[actor]!;
    final session = StudySessionState(
      id: previous.id,
      roomId: previous.roomId,
      userId: previous.userId,
      status: status,
      startedAt: previous.startedAt,
      updatedAt: DateTime.utc(2026, 8, 11, 0, status.index),
      finishedAt: status == StudySessionStatus.finished
          ? DateTime.utc(2026, 8, 11, 0, 10)
          : null,
    );
    backend.sessions[actor] = session;
    backend.publish();
    return session;
  }

  @override
  Future<void> setAway(String roomId, bool away) async {
    final members = backend.room!.members
        .map(
          (member) => member.id == actor.userId
              ? StudyMember(
                  id: member.id,
                  displayName: member.displayName,
                  avatarUrl: member.avatarUrl,
                  status: away ? PresenceStatus.away : PresenceStatus.online,
                  role: member.role,
                )
              : member,
        )
        .toList();
    backend.replaceMembers(members);
  }

  @override
  Future<void> removeMember(String roomId, String userId) async {
    backend.replaceMembers(
      backend.room!.members.where((member) => member.id != userId).toList(),
    );
  }

  @override
  Future<void> leave(String roomId) async {
    backend.replaceMembers(
      backend.room!.members
          .where((member) => member.id != actor.userId)
          .toList(),
    );
  }

  @override
  Future<StudyRoom> transferOwnership(String roomId, String userId) async {
    final members = backend.room!.members
        .map(
          (member) => StudyMember(
            id: member.id,
            displayName: member.displayName,
            avatarUrl: member.avatarUrl,
            status: member.status,
            role: member.id == userId ? RoomRole.owner : RoomRole.member,
          ),
        )
        .toList();
    backend.replaceMembers(members);
    return backend.room!;
  }

  @override
  Future<void> deleteRoom(String roomId) async {
    backend.room = null;
    backend.publish();
  }

  @override
  Future<void> close() async {
    await _syncController.close();
    await _connectionController.close();
  }
}
