function hasExited(child) {
  return child.exitCode !== null || child.signalCode !== null;
}

function waitForExit(child, timeoutMs) {
  if (hasExited(child)) return Promise.resolve(true);
  return new Promise((resolveExit, rejectExit) => {
    let timer;
    const cleanup = () => {
      clearTimeout(timer);
      child.off('exit', onExit);
      child.off('error', onError);
    };
    const onExit = () => {
      cleanup();
      resolveExit(true);
    };
    const onError = (error) => {
      cleanup();
      rejectExit(error);
    };
    child.once('exit', onExit);
    child.once('error', onError);
    timer = setTimeout(() => {
      cleanup();
      resolveExit(false);
    }, timeoutMs);
    timer.unref?.();
  });
}

export async function terminateProcess(
  child,
  { graceMs = 5_000, forceMs = 5_000 } = {},
) {
  if (hasExited(child)) return;
  child.kill('SIGTERM');
  if (await waitForExit(child, graceMs)) return;
  child.kill('SIGKILL');
  if (await waitForExit(child, forceMs)) return;
  child.unref();
  throw new Error(`Process ${child.pid ?? 'unknown'} did not exit after termination`);
}

export async function closeServer(server) {
  if (!server.listening) return;
  await new Promise((resolveClose, rejectClose) => {
    server.close((error) => {
      if (error) rejectClose(error);
      else resolveClose();
    });
  });
}
