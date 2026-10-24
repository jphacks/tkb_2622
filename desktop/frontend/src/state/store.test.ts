import { describe, expect, it, vi } from 'vitest';
import { DesktopStore } from './store';
import type { DesktopBridge, SessionStatus, Snapshot } from '../bridge/types';

function makeSnapshot(revision: number, status?: SessionStatus): Snapshot {
  const allowed = { allowed: true, reason: '' };
  const session = status
    ? {
        id: 'session-1',
        name: '作業',
        task: { id: 'task-1', name: '作業', plannedSeconds: 120, minimumSeconds: 60 },
        status,
        elapsedSeconds: 10,
        evaluation: 'pending' as const,
      }
    : null;
  return {
    revision,
    platform: 'macos',
    mode: 'demo',
    updatedAt: new Date(0).toISOString(),
    session,
    balanceSeconds: null,
    sync: 'synced',
    permission: 'unknown',
    online: true,
    restrictionDesired: 'restricted',
    restrictionConfirmed: false,
    settings: {
      tasks: [{ id: 'task-1', name: '作業', plannedSeconds: 120, minimumSeconds: 60 }],
      selectedTaskId: 'task-1',
      classifications: [],
    },
    history: [],
    result: null,
    actions: {
      start: allowed,
      pause: allowed,
      resume: allowed,
      finish: allowed,
      abort: allowed,
      retry: allowed,
    },
    failure: null,
  };
}

function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });
  return { promise, resolve, reject };
}

function controlledBridge() {
  const active = new Set<(snapshot: Snapshot) => void>();
  const callbacks: Array<(snapshot: Snapshot) => void> = [];
  const bridge: DesktopBridge = {
    getStartupState: vi.fn(async () => makeSnapshot(0)),
    getClassificationCandidates: vi.fn(async () => []),
    captureCurrentClassificationCandidate: vi.fn(async () => ({ name: 'Code', appId: 'com.microsoft.VSCode', appName: 'Code', domain: '', sampleCount: 1 })),
    execute: vi.fn(async () => makeSnapshot(1)),
    requestEmailOTP: vi.fn(async () => makeSnapshot(1)),
    verifyEmailOTP: vi.fn(async () => makeSnapshot(1)),
    signOut: vi.fn(async () => makeSnapshot(1)),
    subscribe: vi.fn((listener: (snapshot: Snapshot) => void) => {
      active.add(listener);
      callbacks.push(listener);
      return () => active.delete(listener);
    }),
    dispose: vi.fn(),
  };
  return { bridge, active, callbacks };
}

describe('DesktopStore', () => {
  it('disconnect後の古いイベント・初期応答を破棄し、購読を解除する', async () => {
    const { bridge, active, callbacks } = controlledBridge();
    const startup = deferred<Snapshot>();
    bridge.getStartupState = vi.fn(() => startup.promise);
    const store = new DesktopStore(bridge);

    const connected = store.connect();
    store.disconnect();
    callbacks[0](makeSnapshot(2, 'RUNNING'));
    startup.resolve(makeSnapshot(1, 'PAUSED'));
    await connected;

    expect(active.size).toBe(0);
    expect(store.getSnapshot().snapshot).toBeNull();
  });

  it('再接続後に古い購読と遅れて届いた初期応答で状態を巻き戻さない', async () => {
    const { bridge, callbacks } = controlledBridge();
    const oldStartup = deferred<Snapshot>();
    const currentStartup = deferred<Snapshot>();
    bridge.getStartupState = vi.fn()
      .mockImplementationOnce(() => oldStartup.promise)
      .mockImplementationOnce(() => currentStartup.promise);
    const store = new DesktopStore(bridge);

    const oldConnection = store.connect();
    const currentConnection = store.connect();
    callbacks[0](makeSnapshot(8, 'RUNNING'));
    callbacks[1](makeSnapshot(5, 'PAUSED'));
    currentStartup.resolve(makeSnapshot(4));
    oldStartup.resolve(makeSnapshot(9, 'RUNNING'));
    await Promise.all([oldConnection, currentConnection]);

    expect(store.getSnapshot().snapshot?.revision).toBe(5);
    expect(store.getSnapshot().snapshot?.session?.status).toBe('PAUSED');
    store.disconnect();
  });

  it('操作中の連打を抑止し、切断前に始めた操作の応答を受け入れない', async () => {
    const { bridge } = controlledBridge();
    const response = deferred<Snapshot>();
    bridge.execute = vi.fn(() => response.promise);
    const store = new DesktopStore(bridge);

    const first = store.execute({ action: 'pause' });
    await store.execute({ action: 'finish' });
    expect(bridge.execute).toHaveBeenCalledTimes(1);
    expect(store.getSnapshot().busy).toBe(true);

    store.disconnect();
    response.resolve(makeSnapshot(1, 'PAUSED'));
    await first;

    expect(store.getSnapshot().snapshot).toBeNull();
    expect(store.getSnapshot().busy).toBe(false);
  });
});
