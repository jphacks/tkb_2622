import { useState } from 'react';
import { isNative } from '../bridge';
import type { ClassificationCandidate, Command, SessionAction, Snapshot } from '../bridge/types';
import { clock, duration, minimumDuration, plannedDuration } from '../components/format';

export const statusLabels: Record<string, string> = { RUNNING: '作業中', PAUSED: '一時停止中', FINALIZED: '作業終了', ABORTED: '中止済み', COMPLETED_LOCAL: '終了・同期待ち', ABORTED_LOCAL: '中止・同期待ち' };
export interface PageProps {
  state: Snapshot;
  busy: boolean;
  getClassificationCandidates?: () => Promise<ClassificationCandidate[]>;
  captureCurrentClassificationCandidate?: () => Promise<ClassificationCandidate>;
  execute: (command: Command) => Promise<Snapshot | null>;
  requestEmailOTP: (email: string) => Promise<Snapshot | null>;
  verifyEmailOTP: (email: string, code: string) => Promise<Snapshot | null>;
  signOut: () => Promise<Snapshot | null>;
  refreshAccount: () => Promise<void>;
  onNavigate?: (page: 'feedback' | 'history' | 'settings') => void;
}

export function SessionPage({ state, busy, execute, onNavigate }: PageProps) {
  const [name, setName] = useState('');
  const [choosingTask, setChoosingTask] = useState(false);
  const session = state.session;
  const active = session && ['RUNNING', 'PAUSED'].includes(session.status);
  const cloudManaged = Boolean(session?.serverVersion);
  const unmatchedCloudSession = state.cloudSession && state.cloudSession.id !== session?.id ? state.cloudSession : null;
  const task = active ? session.task : state.settings.tasks.find(item => item.id === state.settings.selectedTaskId) ?? state.settings.tasks[0];
  if (!task) return <section className="session-panel start-panel"><h1>タスクがありません</h1><p>設定から最初のタスクを作成してください。</p><button className="button primary" onClick={() => onNavigate?.('settings')}>設定を開く</button></section>;
  const elapsed = session?.elapsedSeconds ?? 0;
  const canFinish = state.actions.finish.allowed;
  const monitor = state.monitor ?? { state: 'unavailable', appId: '', appName: '', browserName: '', domain: '', lastSample: '', sampleCount: 0, message: '' };
  const observedContext = [monitor.appName, monitor.domain].filter(Boolean).join(' ・ ');
  const monitorLine = state.mode === 'local-monitor'
    ? monitor.message || (observedContext ? `観測中：${observedContext}（${monitor.sampleCount}件）` : `観測状態：${monitor.state}（${monitor.sampleCount}件）`)
    : `デモ観測：${monitor.sampleCount}件`;
  const availableBalanceLabel = state.mode === 'local-monitor'
    ? state.cloudSession && state.balanceSeconds !== null ? `未終了セッションの報酬残高　${duration(state.balanceSeconds)}` : '作業中の報酬残高は開始後に表示'
    : state.balanceSeconds === null ? '利用できる時間　未取得' : `利用できる時間　${duration(state.balanceSeconds)}（デモ）`;
  const cloudSessionHint = state.cloudSession?.message || (session?.serverVersion ? state.actions.pause.reason : '');
  const phoneRestriction = state.iPhoneRestriction;
  const desiredRestrictionLabel: Record<string, string> = {
    SHIELDED: '制限する要求', TIMED_UNLOCK: '利用枠中の解除要求',
    SESSION_ENDED: '作業終了後の解除要求', UNRESTRICTED: '制限解除要求',
  };
  const expectedShieldStatus = phoneRestriction?.desiredMode === 'SHIELDED' ? 'SHIELDED'
    : ['TIMED_UNLOCK', 'SESSION_ENDED', 'UNRESTRICTED'].includes(phoneRestriction?.desiredMode ?? '') ? 'UNSHIELDED' : '';
  const restrictionApplied = Boolean(phoneRestriction?.lastReportedAt)
    && phoneRestriction!.appliedRevision >= phoneRestriction!.controlRevision
    && phoneRestriction!.shieldStatus === expectedShieldStatus
    && phoneRestriction!.permissionStatus === 'GRANTED';
  const phoneShieldLabel: Record<string, string> = { SHIELDED: '制限中', UNSHIELDED: '解除中', UNKNOWN: '状態不明', ERROR: '適用エラー' };
  const act = (action: SessionAction, label: string, primary = false) => <button className={primary ? 'button primary panel-button' : 'button panel-button'} disabled={busy || !state.actions[action].allowed} title={state.actions[action].reason} onClick={() => execute({ action, name })}>{label}</button>;
  const abort = () => {
    // ローカル計測とWindowsアプリでは，Go側がOSのダイアログで確認する．
    const confirmedByHost = state.mode === 'local-monitor' || (state.platform === 'windows' && isNative());
    if (!confirmedByHost && !window.confirm('作業を中止しますか？（デモ）')) return;
    void execute({ action: 'abort' });
  };

  if (session && ['COMPLETED_LOCAL', 'ABORTED_LOCAL'].includes(session.status)) return <section className="session-panel running-panel" aria-label="作業の同期待ち">
    <header className="running-header"><span className="session-status paused"><i />{session.status === 'ABORTED_LOCAL' ? '中止・同期待ち' : '終了・同期待ち'}</span><span className="session-name">{session.name || session.task.name}</span></header>
    <div className="timer-card"><span>記録した作業時間</span><strong className="panel-timer">{clock(elapsed)}</strong><p>記録の同期と評価が完了すると、結果を表示します。</p></div>
    <button className="button primary panel-button" disabled={busy || !state.actions.retry.allowed} title={state.actions.retry.reason} onClick={() => execute({ action: 'retry' })}>記録を同期して結果を表示</button>
    <p className="panel-note">同期が確認されるまで報酬は確定しません。iPhoneの利用制限は未接続です。</p>
    <footer className="panel-footer"><button onClick={() => onNavigate?.('history')}>これまでの記録</button><button onClick={() => onNavigate?.('settings')}>設定</button></footer>
  </section>;

  if (!active) return <section className="session-panel start-panel" aria-label="作業開始">
    <header className="panel-header"><strong className="panel-brand">Focus Link</strong><span>{availableBalanceLabel}</span></header>
    <button className="start-button" disabled={busy || !state.actions.start.allowed} title={state.actions.start.reason} onClick={() => execute({ action: 'start', name })}><span aria-hidden="true">▶</span><strong>開始</strong></button>
    <label className="panel-label">作業名<input maxLength={80} placeholder="今日は何に取り組みますか？" value={name} onChange={event => setName(event.target.value)} /></label>
    <div className="task-strip"><span><strong>{choosingTask ? 'タスクを選ぶ' : task.name}</strong><small>{choosingTask ? '選択すると次回の作業から反映されます' : `予定 ${plannedDuration(task.plannedSeconds)} ・ 最小 ${minimumDuration(task.minimumSeconds)}`}</small></span>{choosingTask ? <select aria-label="タスク" value={task.id} disabled={busy} onChange={event => { const selected = state.settings.tasks.find(item => item.id === event.target.value)!; execute({ action: 'saveTask', task: selected }); setChoosingTask(false); }}><option value={task.id}>{task.name}</option>{state.settings.tasks.filter(item => item.id !== task.id).map(item => <option key={item.id} value={item.id}>{item.name}</option>)}</select> : <button className="link-button" onClick={() => setChoosingTask(true)}>変更</button>}</div>
    <div className="start-details"><p>押すとまとめて始まること</p><ul><li className="available">アプリ・入力状況の観測 <span>{state.mode === 'local-monitor' ? 'macOS' : 'デモ'}</span></li><li className={state.mode === 'local-monitor' && state.account?.status === 'signedIn' ? 'available' : ''}>活動分類・報酬評価 <span>{state.mode === 'local-monitor' && state.account?.status === 'signedIn' ? 'サーバー同期' : '未接続'}</span></li><li>iPhone利用枠終了 <span>未接続</span></li><li>VS Codeとフォルダ <span>未接続</span></li><li>グループ通知 <span>未接続</span></li></ul></div>
    {!state.actions.start.allowed && <p className="panel-note">{state.actions.start.reason}</p>}
    {state.cloudSession && <div className="paused-explanation"><p className="panel-note">{state.cloudSession.message}</p>{state.cloudSession.ownedByThisDevice && <button className="button danger-link" disabled={busy || !state.actions.abort.allowed} title={state.actions.abort.reason} onClick={() => execute({ action: 'abortCloudSession' })}>サーバー上の作業を中止</button>}</div>}
    <footer className="panel-footer"><button onClick={() => onNavigate?.('history')}>これまでの記録</button><button onClick={() => onNavigate?.('settings')}>設定</button></footer>
  </section>;

  const paused = session.status === 'PAUSED';
  const remaining = Math.max(0, task.minimumSeconds - elapsed);
  return <section className={`session-panel ${paused ? 'paused-panel' : 'running-panel'}`} aria-label={paused ? '一時停止中の作業' : '作業中'}>
    <header className="running-header"><span className={paused ? 'session-status paused' : 'session-status'}><i />{paused ? '一時停止中' : '作業中'}</span>{session.trackingOnly ? <span className="tracking-only-badge">{paused ? 'iPhone制限なし（計測停止中）' : 'iPhone制限なしで記録中'}</span> : null}<span className="session-name">{paused ? `計測 ${clock(elapsed)} で停止` : session.name || session.task.name}</span></header>
    {paused ? <div className="pause-balance"><span>{session.trackingOnly ? 'このセッションの報酬残高' : 'iPhone利用枠'}</span><strong>{state.balanceSeconds === null ? '未取得' : duration(state.balanceSeconds)}</strong><small>{session.trackingOnly ? '終了・中止時に未使用分を破棄します。iPhoneの利用制限は行いません。' : '実際の利用時間の取得・制限は未接続'}</small></div> : <div className="timer-card"><span>計測時間（一時停止を除く）</span><strong className="panel-timer">{clock(elapsed)}</strong><div className="progress"><span style={{ width: `${Math.min(100, elapsed / task.minimumSeconds * 100)}%` }} /></div><p>{canFinish ? '最小作業時間に到達しました' : `最小作業時間 ${minimumDuration(task.minimumSeconds)}（あと${duration(remaining)}）`}</p></div>}
    {!paused && cloudManaged && session.trackingOnly ? <div className="balance-row"><span>このセッションの報酬残高</span><strong>{state.balanceSeconds === null ? '未取得' : duration(state.balanceSeconds)}</strong></div> : null}
    <p className="panel-note">{monitorLine}</p>
    {cloudSessionHint ? <p className="panel-note" role="status">{cloudSessionHint}</p> : null}
    {cloudManaged && !session.trackingOnly ? <div className="panel-note iphone-restriction-status" role="status">
      <strong>iPhone制限</strong>
      {phoneRestriction?.deviceId ? <>
        <p>サーバー要求: {desiredRestrictionLabel[phoneRestriction.desiredMode] ?? '状態確認が必要'}</p>
        <p>iPhone報告: {restrictionApplied ? '適用確認済み' : phoneShieldLabel[phoneRestriction.shieldStatus] ?? '未報告'}
          {phoneRestriction.controlRevision > 0 ? `（更新 ${phoneRestriction.appliedRevision}/${phoneRestriction.controlRevision}）` : ''}</p>
        {phoneRestriction.failureReason ? <p>{phoneRestriction.failureReason}</p> : null}
      </> : <p>iPhoneの制限状態は未登録または未取得です。</p>}
      {state.iPhoneRestrictionError ? <p>{state.iPhoneRestrictionError} 前回の報告が表示されている場合があります。</p> : null}
      {!restrictionApplied && phoneRestriction?.deviceId ? <p>この表示はサーバーが受け取った報告です。iOS上の現在の制限を直接検査した結果ではありません。</p> : null}
    </div> : null}
    {unmatchedCloudSession?.ownedByThisDevice && <button className="link-button danger-link" disabled={busy || !state.actions.abort.allowed} title={state.actions.abort.reason} onClick={() => execute({ action: 'abortCloudSession' })}>未照合のサーバー作業を中止</button>}
    {paused && state.mode === 'demo' && <div className="balance-row"><span>報酬の残高</span><strong>{state.balanceSeconds === null ? '未取得' : `${duration(state.balanceSeconds)}（デモ）`}</strong></div>}
    {paused && <div className="paused-explanation"><p className="panel-note">{cloudManaged ? session.trackingOnly ? '記録専用セッションです。再開するとmacOS計測とサーバーへの記録同期を再開します。iPhoneの利用制限は行いません。' : '再開するとmacOS計測とサーバーへの記録同期を再開します。' : state.mode === 'local-monitor' ? '再開するとローカル計測を再開します。報酬の付与・iPhone利用枠は未接続です。' : '再開すると、残っている利用枠は破棄されます。実際のiPhone利用枠はありません。'}</p>{state.mode === 'demo' && (session.evaluation !== 'complete' || state.sync !== 'synced') ? <button className="link-button" disabled={busy} onClick={() => execute({ action: 'retry' })}>記録の送信・評価を確認する（デモ）</button> : null}</div>}
    {!paused ? <><div className="panel-actions">{act('pause', '一時停止')}{act('finish', canFinish ? '終了' : `終了（あと${duration(remaining)}）`, true)}</div><p className="panel-note">{cloudManaged && session.trackingOnly ? '終了・中止時に未使用分を破棄します。このセッションではiPhoneの利用制限を行いません。作業を再開するとmacOS計測を再開します。' : '一時停止中のiPhone利用枠は未接続です。作業を再開すると計測を再開します。'}</p><footer className="panel-footer"><button className="danger-link" disabled={busy || !state.actions.abort.allowed} onClick={abort}>中止する（報酬なし）</button><span className="panel-sync">{cloudManaged ? state.sync === 'pending' ? 'サーバー同期待ち' : 'サーバー同期済み' : state.mode === 'local-monitor' ? 'このMacに保存' : state.sync === 'synced' ? '同期済み（デモ）' : '同期待ち'}</span></footer></> : <><span className="resume-spacer" />{act('resume', '作業を再開する', true)}<div className="paused-subactions"><button className="link-button" disabled={busy || !state.actions.finish.allowed} title={state.actions.finish.reason} onClick={() => execute({ action: 'finish' })}>終了する</button><button className="link-button danger-link" disabled={busy || !state.actions.abort.allowed} onClick={abort}>中止する（報酬なし）</button></div></>}
  </section>;
}
