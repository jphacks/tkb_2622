import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { DemoBridge } from './demo';

class MemoryStorage implements Storage {
  private values = new Map<string, string>();

  get length() { return this.values.size; }
  clear() { this.values.clear(); }
  getItem(key: string) { return this.values.get(key) ?? null; }
  key(index: number) { return [...this.values.keys()][index] ?? null; }
  removeItem(key: string) { this.values.delete(key); }
  setItem(key: string, value: string) { this.values.set(key, String(value)); }
}

describe('DemoBridge', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-10-24T00:00:00.000Z'));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('設定画面の下書きを一括保存し、無効な設定は反映しない', async () => {
    const bridge = new DemoBridge('macos');
    const settings = {
      tasks: [{ id: 'writing', name: '論文執筆', plannedSeconds: 7200, minimumSeconds: 3600 }],
      selectedTaskId: 'writing',
      classifications: [{ name: 'Notion', category: 'work' as const }],
    };
    let state = await bridge.execute({ action: 'saveSettings', settings });
    expect(state.settings).toEqual(settings);
    expect(state.failure).toBeNull();

    state = await bridge.execute({ action: 'saveSettings', settings: { ...settings, tasks: [...settings.tasks, settings.tasks[0]] } });
    expect(state.settings).toEqual(settings);
    expect(state.failure?.code).toBe('invalid_input');
    bridge.dispose();
  });

  it('最小時間に達する前は終了できず、到達後は結果を確定する', async () => {
    const bridge = new DemoBridge('macos');
    await bridge.execute({ action: 'scenario', scenarioId: 'running' });
    const unsubscribe = bridge.subscribe(() => {});

    vi.setSystemTime(new Date(Date.now() + 3_587_000));
    let state = await bridge.execute({ action: 'finish' });
    expect(state.session?.elapsedSeconds).toBe(3_599);
    expect(state.actions.finish.allowed).toBe(false);
    expect(state.session?.status).toBe('RUNNING');
    expect(state.failure?.code).toBe('invalid_state');

    vi.setSystemTime(new Date(Date.now() + 1_000));
    state = await bridge.execute({ action: 'finish' });
    expect(state.session?.status).toBe('FINALIZED');
    expect(state.result?.elapsedSeconds).toBe(3_600);
    unsubscribe();
    bridge.dispose();
  });

  it('一時停止後はtickが経過時間を増やさない', async () => {
    const bridge = new DemoBridge('macos');
    await bridge.execute({ action: 'start' });
    const unsubscribe = bridge.subscribe(() => {});

    await vi.advanceTimersByTimeAsync(2_300);
    const paused = await bridge.execute({ action: 'pause' });
    expect(paused.session?.status).toBe('PAUSED');
    const elapsed = paused.session?.elapsedSeconds;

    await vi.advanceTimersByTimeAsync(4_000);
    const afterWait = await bridge.getStartupState();
    expect(afterWait.session?.elapsedSeconds).toBe(elapsed);

    unsubscribe();
    bridge.dispose();
  });

  it('オフラインの終了・中止は同期待ちになり、再試行後に確定する', async () => {
    const finishBridge = new DemoBridge('macos');
    await finishBridge.execute({ action: 'scenario', scenarioId: 'running' });
    const unsubscribeFinish = finishBridge.subscribe(() => {});
    vi.setSystemTime(new Date(Date.now() + 3_588_000));
    await finishBridge.execute({ action: 'connection' });

    let state = await finishBridge.execute({ action: 'finish' });
    expect(state.session?.status).toBe('COMPLETED_LOCAL');
    expect(state.sync).toBe('pending');
    expect(state.result).toBeNull();
    expect(state.restrictionDesired).toBe('restricted');

    state = await finishBridge.execute({ action: 'retry' });
    expect(state.session?.status).toBe('FINALIZED');
    expect(state.sync).toBe('synced');
    expect(state.result?.status).toBe('FINALIZED');
    unsubscribeFinish();
    finishBridge.dispose();

    const abortBridge = new DemoBridge('macos');
    await abortBridge.execute({ action: 'scenario', scenarioId: 'running' });
    await abortBridge.execute({ action: 'connection' });
    state = await abortBridge.execute({ action: 'abort' });
    expect(state.session?.status).toBe('ABORTED_LOCAL');
    expect(state.sync).toBe('pending');

    state = await abortBridge.execute({ action: 'retry' });
    expect(state.session?.status).toBe('ABORTED');
    expect(state.sync).toBe('synced');
    abortBridge.dispose();
  });

  it('Storageからの再生成では実行中を一時停止状態へ復元する', async () => {
    const storage = new MemoryStorage();
    const firstBridge = new DemoBridge('macos', storage);
    const started = await firstBridge.execute({ action: 'start' });
    const sessionID = started.session?.id;
    firstBridge.dispose();

    const restartedBridge = new DemoBridge('windows', storage);
    const restored = await restartedBridge.getStartupState();
    expect(restored.platform).toBe('windows');
    expect(restored.session?.id).toBe(sessionID);
    expect(restored.session?.status).toBe('PAUSED');
    expect(restored.session?.evaluation).toBe('pending');
    expect(restored.sync).toBe('pending');

    const unsubscribe = restartedBridge.subscribe(() => {});
    await vi.advanceTimersByTimeAsync(3_000);
    const afterWait = await restartedBridge.getStartupState();
    expect(afterWait.session?.status).toBe('PAUSED');
    expect(afterWait.session?.elapsedSeconds).toBe(restored.session?.elapsedSeconds);

    unsubscribe();
    restartedBridge.dispose();
  });

  it('最後の購読解除でtimerを止め、再接続時は一つだけ動かす', async () => {
    const bridge = new DemoBridge('macos');
    await bridge.execute({ action: 'scenario', scenarioId: 'running' });
    const firstEvents: number[] = [];
    const secondEvents: number[] = [];
    const unsubscribeFirst = bridge.subscribe(state => firstEvents.push(state.revision));
    const unsubscribeSecond = bridge.subscribe(state => secondEvents.push(state.revision));

    expect(vi.getTimerCount()).toBe(1);
    await vi.advanceTimersByTimeAsync(1_100);
    expect(firstEvents).toHaveLength(1);
    expect(secondEvents).toHaveLength(1);

    unsubscribeFirst();
    await vi.advanceTimersByTimeAsync(1_100);
    expect(firstEvents).toHaveLength(1);
    expect(secondEvents).toHaveLength(2);

    unsubscribeSecond();
    expect(vi.getTimerCount()).toBe(0);
    const disconnectedRevision = (await bridge.getStartupState()).revision;
    await vi.advanceTimersByTimeAsync(2_000);
    expect((await bridge.getStartupState()).revision).toBe(disconnectedRevision);

    const reconnectedEvents: number[] = [];
    bridge.subscribe(state => reconnectedEvents.push(state.revision));
    expect(vi.getTimerCount()).toBe(1);
    await vi.advanceTimersByTimeAsync(1_100);
    expect(reconnectedEvents).toHaveLength(1);

    bridge.dispose();
    expect(vi.getTimerCount()).toBe(0);
    const disposedRevision = (await bridge.getStartupState()).revision;
    await vi.advanceTimersByTimeAsync(2_000);
    expect(reconnectedEvents).toHaveLength(1);
    expect((await bridge.getStartupState()).revision).toBe(disposedRevision);
  });

  it('停止・同期待ちからオンライン終了すると同期済みになり残高を破棄する', async () => {
    const bridge = new DemoBridge('macos');
    const paused = await bridge.execute({ action: 'scenario', scenarioId: 'pausing' });
    expect(paused.session?.status).toBe('PAUSED');
    expect(paused.sync).toBe('pending');
    expect(paused.balanceSeconds).toBe(120);

    const finished = await bridge.execute({ action: 'finish' });
    expect(finished.session?.status).toBe('FINALIZED');
    expect(finished.sync).toBe('synced');
    expect(finished.balanceSeconds).toBe(0);
    expect(finished.result?.discardedSeconds).toBe(120);
    bridge.dispose();
  });

  it('権限拒否またはオフラインでは開始を拒否する', async () => {
    const deniedBridge = new DemoBridge('macos');
    await deniedBridge.execute({ action: 'scenario', scenarioId: 'denied' });
    const denied = await deniedBridge.execute({ action: 'start' });
    expect(denied.session).toBeNull();
    expect(denied.failure?.code).toBe('invalid_state');
    expect(denied.actions.start.allowed).toBe(false);
    deniedBridge.dispose();

    const offlineBridge = new DemoBridge('macos');
    await offlineBridge.execute({ action: 'connection' });
    const offline = await offlineBridge.execute({ action: 'start' });
    expect(offline.session).toBeNull();
    expect(offline.failure?.code).toBe('invalid_state');
    expect(offline.actions.start.allowed).toBe(false);
    offlineBridge.dispose();
  });

  it('作業名は80文字まで受理し、81文字は拒否する', async () => {
    const acceptedBridge = new DemoBridge('macos');
    const accepted = await acceptedBridge.execute({ action: 'start', name: 'あ'.repeat(80) });
    expect([...accepted.session!.name]).toHaveLength(80);
    acceptedBridge.dispose();

    const rejectedBridge = new DemoBridge('macos');
    const rejected = await rejectedBridge.execute({ action: 'start', name: 'あ'.repeat(81) });
    expect(rejected.session).toBeNull();
    expect(rejected.failure?.code).toBe('invalid_input');
    rejectedBridge.dispose();
  });

});
