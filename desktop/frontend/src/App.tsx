import { useEffect, useState, useSyncExternalStore } from 'react';
import { createBridge, isNative } from './bridge';
import type { Result } from './bridge/types';
import { DesktopStore } from './state/store';
import { MacShell } from './platforms/macos/Shell';
import { WindowsShell } from './platforms/windows/Shell';
import type { Page } from './components/Shell';
import { SessionPage } from './pages/SessionPage';
import { StartupPage } from './pages/StartupPage';
import { FeedbackPage } from './pages/FeedbackPage';
import { HistoryPage } from './pages/HistoryPage';
import { SettingsPage } from './pages/SettingsPage';
import { scenarios } from './fixtures';
import { duration } from './components/format';

function ConnectedApp({ store }: { store: DesktopStore }) {
  const view = useSyncExternalStore(store.subscribe, store.getSnapshot);
  const [page, setPage] = useState<Page>('session');
  const [showStartup, setShowStartup] = useState(true);
  const [selectedResult, setSelectedResult] = useState<Result | null>(null);
  useEffect(() => { void store.connect(); return () => store.disconnect(); }, [store]);
  useEffect(() => {
    const snapshot = view.snapshot;
    if (!snapshot || !isNative()) return;
    const active = snapshot.session && ['RUNNING', 'PAUSED'].includes(snapshot.session.status);
    const size = page !== 'session' ? [1080, 780] : showStartup ? [440, active ? 490 : 280] : active ? [360, 500] : [360, 580];
    void import('../wailsjs/runtime/runtime').then(runtime => runtime.WindowSetSize(size[0], size[1]));
  }, [page, showStartup, view.snapshot?.platform, view.snapshot?.session?.status]);
  const { snapshot: state, busy, error } = view;
  if (!state) return <div className="startup-message" role="status"><h1>Focus Link</h1><p>{error || '作業スペースを準備しています…'}</p>{error && <button className="button" onClick={() => void store.connect()}>接続を再試行</button>}</div>;
  if (state.platform === 'unsupported') return <div className="startup-message">このOSは対応していません。</div>;
  const Shell = state.platform === 'windows' ? WindowsShell : MacShell;
  const props = { state, busy, execute: (command: Parameters<DesktopStore['execute']>[0]) => {
    const session = state.session;
    const isPendingCompletion = command.action === 'retry' && session && ['COMPLETED_LOCAL', 'ABORTED_LOCAL'].includes(session.status);
    const shouldOpenFeedback = command.action === 'finish' || command.action === 'abort' || isPendingCompletion;
    const revisionBeforeCommand = state.revision;
    void store.execute(command).then(() => {
      if (!shouldOpenFeedback) return;
      const updated = store.getSnapshot().snapshot;
      const result = updated?.result;
      const completed = updated?.session;
      if (!updated || updated.revision <= revisionBeforeCommand || !completed || !result || completed.id !== session?.id || result.sessionId !== completed.id || !['FINALIZED', 'ABORTED'].includes(completed.status)) return;
      setSelectedResult(result);
      setShowStartup(false);
      setPage('feedback');
    });
  }, onNavigate: (next: 'feedback' | 'history' | 'settings') => setPage(next) };
  const active = state.session && ['RUNNING', 'PAUSED'].includes(state.session.status);
  const content = page === 'session' ? (showStartup ? <StartupPage {...props} onLater={() => setShowStartup(false)} onStarted={() => setShowStartup(false)} onResumed={() => setShowStartup(false)} /> : <SessionPage {...props} />) : page === 'feedback' ? <FeedbackPage result={selectedResult ?? state.result} /> : page === 'history' ? <HistoryPage history={state.history} onSelect={result => { setSelectedResult(result); setPage('feedback'); }} /> : <SettingsPage {...props} />;
  const openMain = page !== 'session';
  const balanceLabel = state.balanceSeconds === null ? '未取得' : duration(state.balanceSeconds);
  const body = openMain ? <Shell page={page} balanceLabel={balanceLabel} onNavigate={next => { setPage(next); setSelectedResult(null); }}><div className="page-content">{content}</div></Shell> : <div className={showStartup ? 'compact-window startup-window' : 'compact-window'}>{content}</div>;
  return <>{(error || state.failure) && <div className="error-banner" role="alert">{error || state.failure?.message}{error && <button className="text-button" onClick={() => void store.connect()}>状態を再取得</button>}</div>}{body}<details className={isNative() ? 'demo-tools native-demo-tools' : 'demo-tools'}><summary>デモの状態を切り替えて確認する</summary><div className="demo-controls"><label>シナリオ<select defaultValue="" disabled={busy} onChange={event => { props.execute({ action: 'scenario', scenarioId: event.target.value }); setPage(event.target.value === 'result' ? 'feedback' : 'session'); setShowStartup(event.target.value === 'ready'); setSelectedResult(null); }}><option value="" disabled>確認したい状態を選択</option>{scenarios.map(item => <option key={item.id} value={item.id}>{item.label}</option>)}</select></label>{!isNative() && <label>プレビューするOS<select value={state.platform} onChange={event => { const url = new URL(window.location.href); url.searchParams.set('platform', event.target.value); window.location.assign(url); }}><option value="macos">Mac</option><option value="windows">Windows</option></select></label>}<button className="button" disabled={busy} onClick={() => props.execute({ action: 'connection' })}>{state.online ? 'オフラインを再現' : 'オンラインに戻す'}</button></div><p>デモ表示です。実際の計測・報酬・iPhone制限は未接続です。Go接続は終了時に初期化されます。ブラウザはデモ専用のローカル保存を使います。</p></details></>;
}

export default function App() {
  const [store, setStore] = useState<DesktopStore | null>(null);
  const [error, setError] = useState('');
  useEffect(() => {
    let cancelled = false;
    let dispose: (() => void) | undefined;
    void createBridge().then(bridge => {
      if (cancelled) { bridge.dispose(); return; }
      dispose = () => bridge.dispose(); setStore(new DesktopStore(bridge));
    }).catch(() => setError('接続の初期化に失敗しました。アプリを再起動してください。'));
    return () => { cancelled = true; dispose?.(); };
  }, []);
  return store ? <ConnectedApp store={store} /> : <div className="startup-message" role="status">{error || 'Focus Link を起動しています…'}</div>;
}
