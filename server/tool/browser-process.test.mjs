import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { once } from 'node:events';
import test from 'node:test';

import { closeServer, terminateProcess } from './browser-process.mjs';

test('terminateProcess waits until the child has exited', async (context) => {
  const child = spawn(
    process.execPath,
    ['-e', 'process.on("SIGTERM",()=>setTimeout(()=>process.exit(0),100));setInterval(()=>{},1000)'],
    { stdio: 'ignore' },
  );
  context.after(() => {
    if (child.exitCode === null && child.signalCode === null) child.kill('SIGKILL');
  });
  await once(child, 'spawn');
  let exitObserved = false;
  child.once('exit', () => {
    exitObserved = true;
  });

  await terminateProcess(child, { graceMs: 2_000, forceMs: 2_000 });

  assert.equal(exitObserved, true);
  assert.equal(child.exitCode !== null || child.signalCode !== null, true);
});

test('closeServer resolves after the listening socket closes', async () => {
  const server = createServer((_request, response) => response.end('ok'));
  await new Promise((resolveListen, rejectListen) => {
    server.once('error', rejectListen);
    server.listen(0, '127.0.0.1', resolveListen);
  });

  await closeServer(server);

  assert.equal(server.listening, false);
});
