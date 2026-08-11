import {
  ack,
  api1,
  api2,
  assert,
  connect,
  delay,
  expectNoEvent,
  memberStatus,
  nextEvent,
  request,
  runId,
  token,
} from './e2e-support.mjs';

const ownerId = `flow-owner-${runId}`;
const memberId = `flow-member-${runId}`;
const applicantId = `flow-applicant-${runId}`;
const ownerToken = await token({ sub: ownerId, displayName: 'Flow Owner' });
const memberToken = await token({ sub: memberId, displayName: 'Flow Member' });
const applicantToken = await token({ sub: applicantId, displayName: 'Flow Applicant' });
const room = await request(api1, ownerToken, 'POST', '/v1/rooms', { title: `Two instance ${runId}` });
const secondRoom = await request(api2, ownerToken, 'POST', '/v1/rooms', { title: `Second request ${runId}` });
await request(api2, memberToken, 'POST', `/v1/rooms/${room.id}/join-requests`);
await request(api1, memberToken, 'POST', `/v1/rooms/${secondRoom.id}/join-requests`);
await request(api2, applicantToken, 'POST', `/v1/rooms/${room.id}/join-requests`);

const inboxPageOne = await request(api1, ownerToken, 'GET', `/v1/rooms/${room.id}/join-requests?limit=1`);
assert(inboxPageOne.items.length === 1 && inboxPageOne.nextCursor, 'Owner inbox did not produce a first cursor page');
const inboxPageTwo = await request(
  api2,
  ownerToken,
  'GET',
  `/v1/rooms/${room.id}/join-requests?limit=1&cursor=${encodeURIComponent(inboxPageOne.nextCursor)}`,
);
assert(inboxPageTwo.items.length === 1, 'Owner inbox second cursor page is missing');
assert(inboxPageTwo.items[0].id !== inboxPageOne.items[0].id, 'Owner inbox cursor repeated an item');
const inbox = await request(api1, ownerToken, 'GET', `/v1/rooms/${room.id}/join-requests?limit=100`);
assert(inbox.items.length === 2 && inbox.nextCursor === null, 'Owner inbox maximum page boundary is incorrect');
await request(api1, ownerToken, 'GET', `/v1/rooms/${room.id}/join-requests?limit=101`, undefined, [400]);

const personalPageOne = await request(api2, memberToken, 'GET', '/v1/join-requests?limit=1');
assert(personalPageOne.items.length === 1 && personalPageOne.nextCursor, 'Personal requests did not produce a first cursor page');
const personalPageTwo = await request(
  api1,
  memberToken,
  'GET',
  `/v1/join-requests?limit=1&cursor=${encodeURIComponent(personalPageOne.nextCursor)}`,
);
assert(personalPageTwo.items.length === 1, 'Personal requests second cursor page is missing');
assert(personalPageTwo.items[0].id !== personalPageOne.items[0].id, 'Personal request cursor repeated an item');
const personalBoundary = await request(api2, memberToken, 'GET', '/v1/join-requests?limit=100');
assert(personalBoundary.items.length === 2 && personalBoundary.nextCursor === null, 'Personal request maximum page boundary is incorrect');
await request(api2, memberToken, 'GET', '/v1/join-requests?limit=101', undefined, [400]);

const pending = inbox.items.find((item) => item.userId === memberId);
assert(pending, 'Member join request is missing from the owner inbox');
await request(
  api1,
  ownerToken,
  'PATCH',
  `/v1/rooms/${room.id}/join-requests/${pending.id}`,
  { decision: 'approved' },
);

const ownerSocket = await connect(api1, ownerToken);
const memberSocket = await connect(api2, memberToken);
let runningSessionSocket;
let pausedSessionSocket;
try {
  await ack(ownerSocket, 'room.subscribe', { roomId: room.id });
  await ack(memberSocket, 'room.subscribe', { roomId: room.id });

  const duplicateApplicantId = `flow-duplicate-${runId}`;
  const duplicateApplicantToken = await token({
    sub: duplicateApplicantId,
    displayName: 'Duplicate Applicant',
  });
  const createdRequestEvent = nextEvent(
    ownerSocket,
    (event) => event.type === 'join-request.created'
      && event.payload?.userId === duplicateApplicantId,
  );
  const firstDuplicateRequest = await request(
    api1,
    duplicateApplicantToken,
    'POST',
    `/v1/rooms/${room.id}/join-requests`,
  );
  await createdRequestEvent;
  const duplicateEventGuard = expectNoEvent(
    ownerSocket,
    (event) => event.type === 'join-request.created'
      && event.payload?.userId === duplicateApplicantId,
  );
  const repeatedRequest = await request(
    api2,
    duplicateApplicantToken,
    'POST',
    `/v1/rooms/${room.id}/join-requests`,
  );
  assert(repeatedRequest.id === firstDuplicateRequest.id, 'Repeated join request returned a different request');
  await duplicateEventGuard;

  const chatText = `cross-instance-${runId}`;
  const chatEvent = nextEvent(
    memberSocket,
    (event) => event.type === 'chat.message.created' && event.payload?.text === chatText,
  );
  await request(api1, ownerToken, 'POST', `/v1/rooms/${room.id}/messages`, { text: chatText });
  await chatEvent;

  const focusing = nextEvent(
    ownerSocket,
    (event) => event.type === 'member.presence.updated'
      && event.payload?.id === memberId
      && event.payload?.status === 'focusing',
  );
  const session = await request(api2, memberToken, 'POST', `/v1/rooms/${room.id}/sessions`);
  await focusing;

  const focusingAfterSubscribe = nextEvent(
    ownerSocket,
    (event) => event.type === 'member.presence.updated'
      && event.payload?.id === memberId
      && event.payload?.status === 'focusing',
  );
  runningSessionSocket = await connect(api1, memberToken);
  await ack(runningSessionSocket, 'room.subscribe', { roomId: room.id });
  await focusingAfterSubscribe;

  const idle = nextEvent(
    ownerSocket,
    (event) => event.type === 'member.presence.updated'
      && event.payload?.id === memberId
      && event.payload?.status === 'idle',
  );
  await request(api2, memberToken, 'PATCH', `/v1/sessions/${session.id}`, { status: 'paused' });
  await idle;

  const idleAfterSubscribe = nextEvent(
    ownerSocket,
    (event) => event.type === 'member.presence.updated'
      && event.payload?.id === memberId
      && event.payload?.status === 'idle',
  );
  pausedSessionSocket = await connect(api2, memberToken);
  await ack(pausedSessionSocket, 'room.subscribe', { roomId: room.id });
  await idleAfterSubscribe;

  const online = nextEvent(
    ownerSocket,
    (event) => event.type === 'member.presence.updated'
      && event.payload?.id === memberId
      && event.payload?.status === 'online',
  );
  await request(api2, memberToken, 'PATCH', `/v1/sessions/${session.id}`, { status: 'finished' });
  await online;

  await ack(memberSocket, 'presence.set-away', { roomId: room.id, away: true });
  await ack(runningSessionSocket, 'presence.set-away', { roomId: room.id, away: true });
  const partiallyAwayRoom = await request(api1, ownerToken, 'GET', `/v1/rooms/${room.id}`);
  assert(
    memberStatus(partiallyAwayRoom, memberId) === 'online',
    'Member became away before every active connection was away',
  );

  const away = nextEvent(
    ownerSocket,
    (event) => event.type === 'member.presence.updated'
      && event.payload?.id === memberId
      && event.payload?.status === 'away',
  );
  await ack(pausedSessionSocket, 'presence.set-away', { roomId: room.id, away: true });
  await away;
  const authoritativeRoom = await request(api1, ownerToken, 'GET', `/v1/rooms/${room.id}`);
  assert(memberStatus(authoritativeRoom, memberId) === 'away', 'REST snapshot did not retain away presence');

  let removedEventCount = 0;
  const countRemovedEvents = (event) => {
    if (event.type === 'membership.updated' && event.roomId === room.id && event.payload?.active === false) {
      removedEventCount += 1;
    }
  };
  memberSocket.on('study-room.event', countRemovedEvents);
  const removed = nextEvent(
    memberSocket,
    (event) => event.type === 'membership.updated'
      && event.roomId === room.id
      && event.payload?.active === false,
  );
  await request(api1, ownerToken, 'DELETE', `/v1/rooms/${room.id}/members/${encodeURIComponent(memberId)}`);
  await removed;
  await delay(1_000);
  memberSocket.off('study-room.event', countRemovedEvents);
  assert(removedEventCount === 1, `Removed member received ${removedEventCount} membership.updated events`);
  await request(api2, memberToken, 'GET', `/v1/rooms/${room.id}`, undefined, [403]);
  const rejected = await ack(memberSocket, 'room.subscribe', { roomId: room.id }, false);
  assert(rejected.error?.code === 'membership_required', 'Removed member received an unexpected subscribe error');

  const afterEviction = `after-eviction-${runId}`;
  const noRoomEvents = [memberSocket, runningSessionSocket, pausedSessionSocket].map((socket) => expectNoEvent(
    socket,
    (event) => event.type === 'chat.message.created' && event.payload?.text === afterEviction,
  ));
  await request(api1, ownerToken, 'POST', `/v1/rooms/${room.id}/messages`, { text: afterEviction });
  await Promise.all(noRoomEvents);
  console.log('Two-instance approval, chat, authoritative presence, session, and eviction E2E passed.');
} finally {
  ownerSocket.close();
  memberSocket.close();
  runningSessionSocket?.close();
  pausedSessionSocket?.close();
}
