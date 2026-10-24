import { useState } from 'react';
import type { PageProps } from './SessionPage';

export function StartupPage({ state, busy, execute, onLater, onStarted, onResumed }: PageProps & { onLater: () => void; onStarted: () => void; onResumed: () => void }) {
  const [name, setName] = useState('');
  const unfinished = state.session && ['RUNNING', 'PAUSED', 'COMPLETED_LOCAL', 'ABORTED_LOCAL'].includes(state.session.status);
  return <main className="startup-panel">
    <section className="popup-section">
      <header className="popup-heading"><h1>作業を始めますか？</h1><span>利用できる時間　<strong>{state.balanceSeconds === null ? '未取得' : 'デモ'}</strong></span></header>
      <button className="popup-start" disabled={busy || !state.actions.start.allowed} title={state.actions.start.reason} onClick={() => { execute({ action: 'start', name }); onStarted(); }}><span aria-hidden="true">▶</span>開始</button>
      <div className="popup-form"><input aria-label="作業名" maxLength={80} placeholder="作業名（あとから入力できます）" value={name} onChange={event => setName(event.target.value)} /><button className="button" disabled={busy} onClick={onLater}>あとで</button></div>
      <p className="group-hint">グループ通知は未接続</p>
    </section>
    {unfinished && <section className="popup-pending"><h2>終わっていない作業があります</h2><p>前回の作業を確認してください。再開前に、記録の同期と評価を確認します。</p><div className="popup-actions"><button className="button primary" disabled={busy || !state.actions.resume.allowed} title={state.actions.resume.reason} onClick={() => { execute({ action: 'resume' }); onResumed(); }}>再開する</button><button className="button" disabled={busy} onClick={onLater}>終了・中止を選ぶ</button></div></section>}
  </main>;
}
