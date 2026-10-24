import { useState } from 'react';
import type { Classification, Task } from '../bridge/types';
import type { PageProps } from './SessionPage';
import { minimumDuration, plannedDuration } from '../components/format';
import { taskPurposes } from '../fixtures';

export function SettingsPage({ state, busy, execute }: PageProps) {
  const [task, setTask] = useState<Task>({ id: '', name: '', minimumSeconds: 60, plannedSeconds: 1500 });
  const [classification, setClassification] = useState<Classification>({ name: '', category: 'work' });
  const [addingTask, setAddingTask] = useState(false);
  const [addingClassification, setAddingClassification] = useState<Classification['category'] | null>(null);
  const changeCategory = (item: Classification, category: Classification['category']) => execute({ action: 'classification', classification: { ...item, category } });

  return <div className="settings-page">
    <form className="settings-stack" onSubmit={event => { event.preventDefault(); execute({ action: 'saveTask', task }); setAddingTask(false); }}>
      <header className="page-heading"><div><h1>設定</h1><p>メニューバーの「開始」は、ここで選んだタスクで始まります。変更は次のセッションから反映されます。</p></div></header>
      <section className="card settings-section">
        <div className="settings-section-heading"><h2>タスク</h2><button type="button" className="button" onClick={() => setAddingTask(!addingTask)}>＋ タスクを追加</button></div>
        <div className="settings-task-list" role="radiogroup" aria-label="開始ボタンで使うタスク">{state.settings.tasks.map(item => <button key={item.id} type="button" role="radio" aria-checked={item.id === state.settings.selectedTaskId} className={`settings-task ${item.id === state.settings.selectedTaskId ? 'selected' : ''}`} disabled={busy} onClick={() => execute({ action: 'saveTask', task: item })}><span className={`radio-dot ${item.id === state.settings.selectedTaskId ? 'checked' : ''}`} aria-hidden="true" /><span className="settings-task-copy"><strong>{item.name}</strong><small>{taskPurposes.get(item.id) ?? '作業'} ・ 予定 {plannedDuration(item.plannedSeconds)} ・ 最小 {minimumDuration(item.minimumSeconds)}</small></span>{item.id === state.settings.selectedTaskId && <strong className="selected-label">開始ボタンで使用</strong>}</button>)}</div>
        {addingTask && <div className="settings-task-form"><label>タスク名<input required maxLength={80} value={task.name} onChange={event => setTask({ ...task, name: event.target.value })} /></label><label>最小時間（秒）<input type="number" required min={1} max={86400} value={task.minimumSeconds} onChange={event => setTask({ ...task, minimumSeconds: Number(event.target.value) })} /></label><label>予定時間（秒）<input type="number" required min={task.minimumSeconds} max={86400} value={task.plannedSeconds} onChange={event => setTask({ ...task, plannedSeconds: Number(event.target.value) })} /></label><button className="button primary" disabled={busy}>追加して選択</button></div>}
        <p className="settings-note">最小作業時間を過ぎると「終了」できます。それより前は「中止（報酬なし）」のみです。予定時間になっても自動では終わりません。</p>
        <label className="settings-checkbox-row"><input type="checkbox" checked disabled readOnly /><span>開始と同時に VS Code と前回のフォルダを開く</span><small>未接続</small></label>
      </section>
      <section className="card settings-section">
        <h2>アプリ・サイトの分類</h2>
        {(['work', 'distraction', 'uncertain'] as const).map(category => {
          const items = state.settings.classifications.filter(item => item.category === category);
          if (category === 'uncertain' && items.length === 0) return null;
          return <div className="classification-group" key={category}><span>{category === 'work' ? '作業' : category === 'distraction' ? '娯楽' : '保留'}</span><div className="classification-chips">{items.map(item => <button type="button" key={item.name} className={`classification-chip ${category}`} onClick={() => changeCategory(item, category === 'work' ? 'distraction' : 'work')} title="クリックして分類を切り替え">{item.name}</button>)}<button type="button" className="classification-add" onClick={() => { setClassification({ ...classification, category }); setAddingClassification(category); }}>＋ 追加</button></div></div>;
        })}
        {addingClassification && <div className="classification-form"><label>アプリ名・ドメイン<input autoFocus maxLength={200} placeholder="例：Notion" value={classification.name} onChange={event => setClassification({ ...classification, name: event.target.value })} /></label><select aria-label="追加する分類" value={classification.category} onChange={event => setClassification({ ...classification, category: event.target.value as Classification['category'] })}><option value="work">作業</option><option value="distraction">娯楽</option><option value="uncertain">保留</option></select><button type="button" className="button" disabled={busy || !classification.name.trim()} onClick={() => { execute({ action: 'classification', classification }); setClassification({ ...classification, name: '' }); setAddingClassification(null); }}>追加</button><button type="button" className="text-button" onClick={() => setAddingClassification(null)}>キャンセル</button></div>}
        <p className="settings-note">分類を実際の計測・判定に使う機能は未接続です。分類根拠のない時間は保留として扱います。</p>
      </section>
      <section className="card settings-section compact-settings"><h2>端末と報酬</h2><div className="settings-row"><span>計測権限<small>アプリ・サイトの計測状態</small></span><span className="unavailable">未接続</span></div><div className="settings-row"><span>アカウント<small>残高・報酬のサーバー同期</small></span><span className="unavailable">未接続</span></div><div className="settings-row"><span>iPhone・通知<small>利用枠の反映と通知状態</small></span><span className="unavailable">未接続</span></div></section>
      <section className="card settings-section compact-settings"><h2>通知</h2><div className="settings-row"><span>グループのメンバーが作業を始めたら通知<small>このMacとiPhoneに届きます</small></span><span className="unavailable">未接続</span></div><div className="settings-row"><span>作業中・一時停止中は、報酬や利用開始の通知を出しません</span><strong>常に有効</strong></div></section>
      <section className="card settings-section"><h2>プライバシー</h2><div className="settings-row"><span>ブラウザのサイト（ドメイン）を判定に使う<small>この基盤ではブラウザ情報を取得しません</small></span><span className="unavailable">未接続</span></div><p className="settings-note">キー入力の内容や画面の画像は取得しません。アプリとサイトの計測自体が未接続です。</p></section>
    </form>
  </div>;
}
