import { useState } from 'react';
import type { PageProps } from './SessionPage';
import { duration } from '../components/format';

export function StartupPage({ state, busy, execute, onLater, onStarted, onResumed }: PageProps & { onLater: () => void; onStarted: () => void; onResumed: () => void }) {
  const [name, setName] = useState('');
  const unfinished = state.session && ['RUNNING', 'PAUSED', 'COMPLETED_LOCAL', 'ABORTED_LOCAL'].includes(state.session.status);
  const activeCloudSession = state.session && (state.session.serverVersion ?? 0) > 0 && ['RUNNING', 'PAUSED'].includes(state.session.status);
  const activeSession = state.session && ['RUNNING', 'PAUSED'].includes(state.session.status);
  const balanceLabel = state.mode === 'demo'
    ? state.balanceSeconds === null ? '未取得' : `${duration(state.balanceSeconds)}（デモ）`
    : activeCloudSession && state.balanceSeconds !== null ? duration(state.balanceSeconds)
      : state.account?.status !== 'signedIn' ? 'ログイン後に表示'
        : activeSession ? '未取得' : '作業開始後に表示';
  const balanceTitle = state.mode === 'demo' ? '利用できる時間'
    : activeCloudSession && state.session?.trackingOnly ? 'このセッションの報酬残高'
      : activeCloudSession ? 'セッション報酬残高' : '報酬残高';
  const unmatchedCloudSession = state.cloudSession && state.cloudSession.id !== state.session?.id ? state.cloudSession : null;
  const cloudStatus = state.cloudSession?.status === 'RUNNING' ? '作業中' : state.cloudSession?.status === 'PAUSED' ? '一時停止中' : '状態確認が必要';
  return <main className="startup-panel">
    <section className="popup-section">
      <header className="popup-heading"><h1>作業を始めますか？</h1><span>{balanceTitle}　<strong>{balanceLabel}</strong></span></header>
      <button className="popup-start" disabled={busy || !state.actions.start.allowed} title={state.actions.start.reason} onClick={async () => { const updated = await execute({ action: 'start', name }); if (updated?.session?.status === 'RUNNING' && !updated.failure) onStarted(); }}><span aria-hidden="true">▶</span>開始</button>
      <div className="popup-form"><input aria-label="作業名" maxLength={80} placeholder="作業名（あとから入力できます）" value={name} onChange={event => setName(event.target.value)} /><button className="button" disabled={busy} onClick={onLater}>あとで</button></div>
      {!state.actions.start.allowed && <p className="group-hint">{state.actions.start.reason}</p>}
      <p className="group-hint">グループ通知は未接続</p>
    </section>
    {unfinished && <section className="popup-pending"><h2>終わっていない作業があります</h2><p>{state.cloudSession?.id === state.session?.id ? state.cloudSession?.message : state.actions.resume.allowed ? state.mode === 'local-monitor' ? '前回の作業を一時停止状態で復元しました。ローカル記録から再開できます。' : '前回の作業を確認してください。再開前に、記録の同期と評価を確認します。' : state.actions.resume.reason}</p><div className="popup-actions"><button className="button primary" disabled={busy || !state.actions.resume.allowed} title={state.actions.resume.reason} onClick={async () => { const updated = await execute({ action: 'resume' }); if (updated?.session?.status === 'RUNNING' && !updated.failure) onResumed(); }}>再開する</button><button className="button" disabled={busy} onClick={onLater}>終了・中止を選ぶ</button></div></section>}
    {unmatchedCloudSession && <section className="popup-pending"><h2>サーバーに未終了の作業があります</h2><p>{unmatchedCloudSession.name || unmatchedCloudSession.taskId} ・ {cloudStatus}</p><p>{unmatchedCloudSession.message}</p><div className="popup-actions">{unmatchedCloudSession.ownedByThisDevice && <button className="button primary" disabled={busy || !state.actions.abort.allowed} title={state.actions.abort.reason} onClick={() => execute({ action: 'abortCloudSession' })}>サーバー上の作業を中止</button>}<button className="button" disabled={busy} onClick={onLater}>あとで</button></div></section>}
  </main>;
}
