import { defaultClassifications, defaultTask, defaultTasks, scenarios } from '../fixtures';
import type { Command, DesktopBridge, Platform, Snapshot, SessionStatus, Result, Settings } from './types';

const storageKey = 'focus-link.demo.v2';
const terminal = (status: string) => status === 'FINALIZED' || status === 'ABORTED';
const copy = <T,>(value: T): T => structuredClone(value);

function normalizeSettings(input: Settings): Settings | null {
  const settings = copy(input);
  const taskIDs = new Set<string>();
  for (const task of settings.tasks) {
    task.id = task.id.trim();
    task.name = task.name.trim();
    if (!task.id || !task.name || [...task.name].length > 80 || !Number.isInteger(task.minimumSeconds) || task.minimumSeconds < 1 || task.minimumSeconds > 86400 || !Number.isInteger(task.plannedSeconds) || task.plannedSeconds < task.minimumSeconds || task.plannedSeconds > 86400 || taskIDs.has(task.id)) return null;
    taskIDs.add(task.id);
  }
  if (settings.tasks.length === 0 || !taskIDs.has(settings.selectedTaskId.trim())) return null;
  settings.selectedTaskId = settings.selectedTaskId.trim();
  const classificationNames = new Set<string>();
  for (const classification of settings.classifications) {
    classification.name = classification.name.trim();
    if (!classification.name || [...classification.name].length > 200 || !['work', 'distraction', 'uncertain'].includes(classification.category) || classificationNames.has(classification.name)) return null;
    classificationNames.add(classification.name);
  }
  return settings;
}

// ブラウザ専用シミュレーター．実機ではGoの応答を使い，この判定を参照しない．
export class DemoBridge implements DesktopBridge {
  private state: Snapshot;
  private listeners = new Set<(state: Snapshot) => void>();
  private timer: ReturnType<typeof setInterval> | undefined;
  private lastTick = Date.now();

  constructor(platform: Platform, private storage?: Storage) {
    this.state = {
      revision: 0, platform, mode: 'demo', updatedAt: new Date().toISOString(), session: null,
      balanceSeconds: null, sync: 'synced', permission: 'unknown', online: true,
      monitor: { state: 'demo', appName: '', browserName: '', domain: '', lastSample: '', sampleCount: 0, message: '' },
      restrictionDesired: 'unknown', restrictionConfirmed: false,
      settings: { tasks: copy(defaultTasks), selectedTaskId: defaultTask.id, classifications: copy(defaultClassifications) },
      history: [], result: null, actions: {} as Snapshot['actions'], failure: null,
    };
    this.applyScenario('ready');
    try {
      const saved = storage?.getItem(storageKey);
      if (saved) {
        const parsed = JSON.parse(saved) as Snapshot;
        if (parsed.mode !== 'demo' || !Array.isArray(parsed.settings?.tasks) || !Number.isSafeInteger(parsed.revision)) throw new Error('invalid snapshot');
        this.state = { ...parsed, platform };
        if (this.state.session?.status === 'RUNNING') {
          this.state.session.status = 'PAUSED'; this.state.session.evaluation = 'pending'; this.state.sync = 'pending';
        }
      }
    } catch {
      this.state.failure = { code: 'storage', message: 'デモの保存データを復元できませんでした。新しいデモで確認してください。', retryable: false };
    }
    this.touch();
  }

  async getStartupState() { return copy(this.state); }

  async requestEmailOTP(email: string) {
    this.state.account = { status: 'demo', email, deviceRegistered: false, message: 'ブラウザプレビューではメール認証を行いません。' };
    this.touch();
    return copy(this.state);
  }

  async verifyEmailOTP(email: string, _code: string) {
    this.state.account = { status: 'demo', email, deviceRegistered: false, message: 'ブラウザプレビューではメール認証を行いません。' };
    this.touch();
    return copy(this.state);
  }

  async signOut() {
    this.state.account = { status: 'signedOut', email: '', deviceRegistered: false, message: '' };
    this.touch();
    return copy(this.state);
  }

  subscribe(listener: (state: Snapshot) => void) {
    this.listeners.add(listener);
    if (!this.timer) { this.lastTick = Date.now(); this.timer = setInterval(() => this.tick(), 250); }
    return () => {
      this.listeners.delete(listener);
      if (this.listeners.size === 0 && this.timer) { clearInterval(this.timer); this.timer = undefined; }
    };
  }

  dispose() { if (this.timer) clearInterval(this.timer); this.timer = undefined; this.listeners.clear(); }

  private tick() {
    if (this.state.session?.status !== 'RUNNING') { this.lastTick = Date.now(); return; }
    const seconds = Math.floor((Date.now() - this.lastTick) / 1000);
    if (seconds <= 0) return;
    this.state.session.elapsedSeconds += seconds; this.lastTick += seconds * 1000; this.touch();
  }

  private fail(code: string, message: string, retryable = false) { this.state.failure = { code, message, retryable }; }

  private complete() {
    const session = this.state.session!;
    const discardedSeconds = this.state.balanceSeconds ?? 0;
    session.evaluation = 'complete'; this.state.balanceSeconds = 0; this.state.sync = 'synced'; this.state.restrictionDesired = 'unrestricted';
    const result: Result = { sessionId: session.id, name: session.name, status: session.status, elapsedSeconds: session.elapsedSeconds, workSeconds: 0, distractedSeconds: 0, uncertainSeconds: session.elapsedSeconds, earnedSeconds: 0, usedSeconds: 0, discardedSeconds };
    this.state.result = result;
    if (!this.state.history.some(item => item.sessionId === result.sessionId)) this.state.history.unshift(result);
  }

  private applyScenario(id: string) {
    const scenario = scenarios.find(item => item.id === id);
    if (!scenario) { this.fail('invalid_input', '存在しないデモシナリオです。'); return; }
    Object.assign(this.state, { session: null, result: null, balanceSeconds: scenario.balanceSeconds, sync: scenario.sync, permission: scenario.permission, online: scenario.online, restrictionDesired: 'unknown', restrictionConfirmed: false });
    if (scenario.status) {
      this.state.session = { id: crypto.randomUUID(), name: defaultTask.name, task: copy(defaultTask), status: scenario.status as SessionStatus, elapsedSeconds: scenario.elapsedSeconds, evaluation: scenario.evaluation };
      this.state.restrictionDesired = 'restricted';
      if (terminal(scenario.status)) this.complete();
    }
    if (id === 'failure') this.fail('unavailable', 'デモ：記録の送信に失敗しました。再試行できます。', true);
  }

  private updateActions() {
    const state = this.state, session = state.session;
    const active = !!session && ['RUNNING', 'PAUSED'].includes(session.status);
    const rules = {
      start: (!session || terminal(session.status)) && state.online && state.permission !== 'denied',
      pause: active && session.status === 'RUNNING',
      resume: active && session.status === 'PAUSED' && state.online && state.sync === 'synced' && session.evaluation === 'complete' && state.permission !== 'denied',
      finish: active && session.elapsedSeconds >= session.task.minimumSeconds,
      abort: active, retry: state.sync !== 'synced',
    };
    for (const action of Object.keys(rules) as (keyof typeof rules)[]) state.actions[action] = { allowed: rules[action], reason: rules[action] ? '' : '現在の状態では操作できません。' };
    if (!state.online) state.actions.start.reason = '開始にはオンライン接続が必要です。';
    if (state.permission === 'denied') state.actions.start.reason = '計測権限が拒否されています。設定を確認してください。';
    if (active && !rules.finish) state.actions.finish.reason = '最小作業時間に達していません。';
  }

  private touch() {
    this.state.revision++; this.state.updatedAt = new Date().toISOString(); this.updateActions();
    try { this.storage?.setItem(storageKey, JSON.stringify(this.state)); }
    catch { this.fail('storage', 'デモの保存に失敗しました。この画面では操作できますが、再読み込み時には復元できません。'); }
    const state = copy(this.state); for (const listener of this.listeners) listener(state);
  }

  async execute(command: Command): Promise<Snapshot> {
    this.tick(); this.state.failure = null; this.updateActions();
    const capability = this.state.actions[command.action as keyof Snapshot['actions']];
    if (capability && !capability.allowed) { this.fail('invalid_state', capability.reason); this.touch(); return copy(this.state); }
    switch (command.action) {
      case 'scenario': this.applyScenario(command.scenarioId); break;
      case 'start': {
        if ([...(command.name?.trim() ?? '')].length > 80) { this.fail('invalid_input', '作業名は80文字以内で入力してください。'); break; }
        const task = this.state.settings.tasks.find(item => item.id === this.state.settings.selectedTaskId)!;
        this.state.session = { id: crypto.randomUUID(), name: command.name?.trim() || task.name, task: copy(task), status: 'RUNNING', elapsedSeconds: 0, evaluation: 'pending' };
        this.state.result = null; this.state.balanceSeconds = null; this.state.restrictionDesired = 'restricted'; break;
      }
      case 'pause': this.state.session!.status = 'PAUSED'; this.state.session!.evaluation = 'pending'; this.state.sync = 'pending'; break;
      case 'resume': this.state.session!.status = 'RUNNING'; this.state.session!.evaluation = 'pending'; this.state.restrictionDesired = 'restricted'; break;
      case 'finish': case 'abort': {
        this.state.session!.status = command.action === 'abort' ? 'ABORTED' : 'FINALIZED';
        if (!this.state.online) { this.state.session!.status = command.action === 'abort' ? 'ABORTED_LOCAL' : 'COMPLETED_LOCAL'; this.state.sync = 'pending'; }
        else this.complete(); break;
      }
      case 'retry': {
        this.state.online = true; this.state.sync = 'synced';
        const session = this.state.session;
        if (session?.status === 'COMPLETED_LOCAL' || session?.status === 'ABORTED_LOCAL') { session.status = session.status === 'ABORTED_LOCAL' ? 'ABORTED' : 'FINALIZED'; this.complete(); }
        else if (session) session.evaluation = 'complete'; break;
      }
      case 'connection': this.state.online = !this.state.online; break;
      case 'saveSettings': {
        const settings = normalizeSettings(command.settings);
        if (!settings) { this.fail('invalid_input', '設定内容を確認してください。'); break; }
        this.state.settings = settings;
        break;
      }
      case 'saveTask': {
        const task = copy(command.task); task.name = task.name.trim();
        if (!task.name || [...task.name].length > 80 || !Number.isInteger(task.minimumSeconds) || task.minimumSeconds < 1 || task.minimumSeconds > 86400 || !Number.isInteger(task.plannedSeconds) || task.plannedSeconds < task.minimumSeconds || task.plannedSeconds > 86400) { this.fail('invalid_input', 'タスク名は1〜80文字、最小時間は1〜86400秒、予定時間は最小時間以上・86400秒以下で入力してください。'); break; }
        task.id ||= crypto.randomUUID();
        const index = this.state.settings.tasks.findIndex(item => item.id === task.id);
        if (index >= 0) this.state.settings.tasks[index] = task; else this.state.settings.tasks.push(task);
        this.state.settings.selectedTaskId = task.id; break;
      }
      case 'classification': {
        const item = { ...command.classification, name: command.classification.name.trim() };
        if (!item.name || [...item.name].length > 200 || !['work', 'distraction', 'uncertain'].includes(item.category)) { this.fail('invalid_input', '分類の名前と種別を確認してください。'); break; }
        const index = this.state.settings.classifications.findIndex(value => value.name === item.name);
        if (index >= 0) this.state.settings.classifications[index] = item; else this.state.settings.classifications.push(item); break;
      }
    }
    if (['start', 'resume', 'pause', 'finish', 'abort', 'scenario'].includes(command.action)) this.lastTick = Date.now();
    this.touch(); return copy(this.state);
  }
}
