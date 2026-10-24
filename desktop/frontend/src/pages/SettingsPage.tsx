import { useEffect, useState } from 'react';
import type { Classification, Settings, Task } from '../bridge/types';
import type { PageProps } from './SessionPage';
import { minimumDuration, plannedDuration } from '../components/format';
import { taskPurposes } from '../fixtures';

const emptyTask: Task = { id: '', name: '', category: 'OTHER', mode: 'NORMAL', minimumSeconds: 300, plannedSeconds: 1500 };
const emptyClassification: Classification = { name: '', category: 'work' };

const categories = [
  ['PROGRAMMING', 'プログラミング'], ['DOCUMENT_WRITING', '文書作成'], ['READING', '読書'],
  ['DESIGN', 'デザイン'], ['STUDY', '学習'], ['OTHER', 'その他'],
] as const;
const modes = [['NORMAL', '通常'], ['READING', '読書'], ['VIDEO', '動画']] as const;
const categoryLabels = new Map<string, string>(categories);
const modeLabels = new Map<string, string>(modes);

export function SettingsPage({ state, busy, execute, requestEmailOTP, verifyEmailOTP, signOut, refreshAccount }: PageProps) {
	const monitor = state.monitor ?? { state: 'unavailable', appName: '', browserName: '', domain: '', lastSample: '', sampleCount: 0, message: '' };
  const account = state.account ?? { status: state.mode === 'demo' ? 'demo' as const : 'signedOut' as const, email: '', deviceRegistered: false, message: '' };
  const [draft, setDraft] = useState<Settings>(() => structuredClone(state.settings));
  const [task, setTask] = useState<Task>(emptyTask);
  const [classification, setClassification] = useState<Classification>(emptyClassification);
  const [addingTask, setAddingTask] = useState(false);
  const [editingTaskId, setEditingTaskId] = useState<string | null>(null);
  const [email, setEmail] = useState(account.email);
  const [otp, setOtp] = useState('');
  const [addingClassification, setAddingClassification] = useState<Classification['category'] | null>(null);
  const stateSignature = JSON.stringify(state.settings);
  const draftIsValid = draft.tasks.length > 0 && draft.tasks.some(item => item.id === draft.selectedTaskId);
  const hasUnsavedChanges = JSON.stringify(draft) !== stateSignature;
  const canSaveTasks = state.mode === 'demo' || account.status === 'signedIn';
  const monitorStatus = {
    ready: '利用可能',
    running: '計測中',
    paused: '一時停止中',
    finished: '終了',
    aborted: '中止',
    error: '要確認',
    unavailable: 'ヘルパー未準備',
    unsupported: '未対応OS',
    demo: 'デモ',
  }[monitor.state] ?? monitor.state;

  useEffect(() => setDraft(structuredClone(state.settings)), [stateSignature]);
  useEffect(() => { if (account.email) setEmail(account.email); }, [account.email]);

  const changeCategory = (item: Classification, category: Classification['category']) => {
    setDraft(current => ({ ...current, classifications: current.classifications.map(value => value.name === item.name ? { ...value, category } : value) }));
  };
  const addTask = () => {
    const name = task.name.trim();
    if (!name || [...name].length > 80 || !Number.isInteger(task.minimumSeconds) || task.minimumSeconds < 1 || task.minimumSeconds > 86400 || !Number.isInteger(task.plannedSeconds) || task.plannedSeconds < task.minimumSeconds || task.plannedSeconds > 86400) return;
    if (editingTaskId) {
      const updatedTask = { ...task, id: editingTaskId, name };
      setDraft(current => ({ ...current, tasks: current.tasks.map(item => item.id === editingTaskId ? updatedTask : item), selectedTaskId: editingTaskId }));
    } else {
      const nextTask = { ...task, id: `local-${crypto.randomUUID()}`, name };
      setDraft(current => ({ ...current, tasks: [...current.tasks, nextTask], selectedTaskId: nextTask.id }));
    }
    setTask(emptyTask);
    setEditingTaskId(null);
    setAddingTask(false);
  };
  const addClassification = () => {
    const nextClassification = { ...classification, name: classification.name.trim() };
    if (!nextClassification.name || [...nextClassification.name].length > 200) return;
    setDraft(current => {
      const index = current.classifications.findIndex(item => item.name === nextClassification.name);
      const classifications = [...current.classifications];
      if (index >= 0) classifications[index] = nextClassification;
      else classifications.push(nextClassification);
      return { ...current, classifications };
    });
    setClassification({ ...emptyClassification, category: classification.category });
    setAddingClassification(null);
  };

  return <div className="settings-page">
    <form className="settings-stack" onSubmit={event => { event.preventDefault(); if (canSaveTasks && draftIsValid && hasUnsavedChanges) execute({ action: 'saveSettings', settings: draft }); }}>
      <header className="page-heading"><div><h1>設定</h1><p>メニューバーの「開始」は、ここで選んだタスクで始まります。変更は次のセッションから反映されます。</p></div></header>
      <section className="card settings-section">
        <div className="settings-section-heading"><h2>タスク</h2><button type="button" className="button" disabled={busy || !canSaveTasks} onClick={() => { setTask(emptyTask); setEditingTaskId(null); setAddingTask(!addingTask); }}>＋ タスクを追加</button></div>
        <div className="settings-task-list" role="radiogroup" aria-label="開始ボタンで使うタスク">{draft.tasks.map(item => <div className="settings-task-row" key={item.id}><button type="button" role="radio" aria-checked={item.id === draft.selectedTaskId} className={`settings-task ${item.id === draft.selectedTaskId ? 'selected' : ''}`} disabled={busy} onClick={() => setDraft(current => ({ ...current, selectedTaskId: item.id }))}><span className={`radio-dot ${item.id === draft.selectedTaskId ? 'checked' : ''}`} aria-hidden="true" /><span className="settings-task-copy"><strong>{item.name}</strong><small>{categoryLabels.get(item.category ?? '') ?? taskPurposes.get(item.id) ?? '作業'} ・ {modeLabels.get(item.mode ?? '') ?? '通常'} ・ 予定 {plannedDuration(item.plannedSeconds)} ・ 最小 {minimumDuration(item.minimumSeconds)}</small></span>{item.id === draft.selectedTaskId && <strong className="selected-label">開始ボタンで使用</strong>}</button><button type="button" className="text-button settings-task-edit" disabled={busy || !canSaveTasks} onClick={() => { setTask({ ...item }); setEditingTaskId(item.id); setAddingTask(true); }}>編集</button></div>)}</div>
        {addingTask && <div className="settings-task-form"><label>タスク名<input required maxLength={80} value={task.name} onChange={event => setTask({ ...task, name: event.target.value })} /></label><label>カテゴリ<select value={task.category ?? 'OTHER'} onChange={event => setTask({ ...task, category: event.target.value })}>{categories.map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label><label>計測モード<select value={task.mode ?? 'NORMAL'} onChange={event => setTask({ ...task, mode: event.target.value })}>{modes.map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label><label>最小時間（秒）<input type="number" required min={1} max={86400} value={task.minimumSeconds} onChange={event => setTask({ ...task, minimumSeconds: Number(event.target.value) })} /></label><label>予定時間（秒）<input type="number" required min={task.minimumSeconds} max={86400} value={task.plannedSeconds} onChange={event => setTask({ ...task, plannedSeconds: Number(event.target.value) })} /></label><button type="button" className="button primary" disabled={busy || !task.name.trim() || !Number.isInteger(task.minimumSeconds) || task.minimumSeconds < 1 || task.minimumSeconds > 86400 || !Number.isInteger(task.plannedSeconds) || task.plannedSeconds < task.minimumSeconds || task.plannedSeconds > 86400} onClick={addTask}>{editingTaskId ? '変更を反映' : '追加して選択'}</button></div>}
        {state.mode === 'local-monitor' && !canSaveTasks && <p className="settings-note">メール認証とPC登録のあと、サーバー上のタスクを作成・編集できます。</p>}
        <p className="settings-note">最小作業時間を過ぎると「終了」できます。それより前は「中止（報酬なし）」のみです。予定時間になっても自動では終わりません。</p>
        <label className="settings-checkbox-row"><input type="checkbox" checked disabled readOnly /><span>開始と同時に VS Code と前回のフォルダを開く</span><small>未接続</small></label>
      </section>
      <section className="card settings-section">
        <h2>アプリ・サイトの分類</h2>
        {(['work', 'distraction', 'uncertain'] as const).map(category => {
          const items = draft.classifications.filter(item => item.category === category);
          if (category === 'uncertain' && items.length === 0) return null;
          return <div className="classification-group" key={category}><span>{category === 'work' ? '作業' : category === 'distraction' ? '娯楽' : '保留'}</span><div className="classification-chips">{items.map(item => <button type="button" key={item.name} className={`classification-chip ${category}`} disabled={busy} onClick={() => changeCategory(item, category === 'work' ? 'distraction' : 'work')} title="クリックして分類を切り替え">{item.name}</button>)}<button type="button" className="classification-add" disabled={busy} onClick={() => { setClassification({ ...emptyClassification, category }); setAddingClassification(category); }}>＋ 追加</button></div></div>;
        })}
        {addingClassification && <div className="classification-form"><label>アプリ名・ドメイン<input autoFocus maxLength={200} placeholder="例：Notion" value={classification.name} onChange={event => setClassification({ ...classification, name: event.target.value })} /></label><select aria-label="追加する分類" value={classification.category} onChange={event => setClassification({ ...classification, category: event.target.value as Classification['category'] })}><option value="work">作業</option><option value="distraction">娯楽</option><option value="uncertain">保留</option></select><button type="button" className="button" disabled={busy || !classification.name.trim()} onClick={addClassification}>追加</button><button type="button" className="text-button" onClick={() => setAddingClassification(null)}>キャンセル</button></div>}
        <p className="settings-note">分類を実際の計測・判定に使う機能は未接続です。分類根拠のない時間は保留として扱います。</p>
      </section>
      <section className="card settings-section">
        <h2>アカウント</h2>
        {account.status === 'demo' ? <p className="settings-note">ブラウザプレビューではメール認証を行いません。実アプリで設定してください。</p> : <>
          <div className="settings-row"><span>状態<small>{account.email || 'メールアドレスでログイン'}</small></span><strong>{({ unconfigured: '接続先未設定', storageUnavailable: '資格情報ストア未使用', signedOut: '未ログイン', otpPending: '確認コードを送信済み', signedIn: account.deviceRegistered ? 'ログイン・PC登録済み' : 'ログイン済み', error: '接続エラー' } as Record<string, string>)[account.status] ?? account.status}</strong></div>
          {account.status === 'unconfigured' ? <p className="settings-note">FOCUS_LINK_API_BASE_URL、FOCUS_LINK_SUPABASE_URL、FOCUS_LINK_SUPABASE_PUBLISHABLE_KEYをアプリ起動時の環境変数に設定してください。</p> : null}
          {account.status === 'signedOut' || account.status === 'otpPending' ? <div className="account-auth-form"><label>メールアドレス<input type="email" autoComplete="email" value={email} disabled={busy || account.status === 'otpPending'} onChange={event => setEmail(event.target.value)} /></label>{account.status === 'otpPending' && <label>メールの確認コード<input inputMode="numeric" autoComplete="one-time-code" value={otp} disabled={busy} onChange={event => setOtp(event.target.value)} /></label>}<div className="account-auth-actions">{account.status === 'signedOut' ? <button type="button" className="button primary" disabled={busy || !email.trim()} onClick={() => void requestEmailOTP(email)}>確認コードを送信</button> : <><button type="button" className="button primary" disabled={busy || !otp.trim()} onClick={() => void verifyEmailOTP(account.email || email, otp)}>ログイン</button><button type="button" className="text-button" disabled={busy} onClick={() => { setOtp(''); void requestEmailOTP(account.email || email); }}>コードを再送</button></>}</div></div> : null}
          {account.status === 'signedIn' && <div className="account-auth-actions"><button type="button" className="button" disabled={busy} onClick={() => void signOut()}>ログアウト</button></div>}
          {account.status === 'error' && <div className="account-auth-actions"><button type="button" className="button" disabled={busy} onClick={() => void refreshAccount()}>再接続</button><button type="button" className="text-button" disabled={busy} onClick={() => void signOut()}>ログアウト</button></div>}
          {account.message && <p className="settings-note" role="status">{account.message}</p>}
        </>}
      </section>
      <section className="card settings-section compact-settings"><h2>端末と報酬</h2><div className="settings-row"><span>macOS計測<small>{monitor.message || '前面アプリ・入力アイドル・対応ブラウザーのドメインを観測'}</small></span><span className={monitor.state === 'error' || monitor.state === 'unavailable' ? 'unavailable' : ''}>{monitorStatus}</span></div><div className="settings-row"><span>iPhone・通知<small>StartSessionと利用枠の反映</small></span><span className="unavailable">未接続</span></div></section>
      <section className="card settings-section compact-settings"><h2>通知</h2><div className="settings-row"><span>グループのメンバーが作業を始めたら通知<small>このMacとiPhoneに届きます</small></span><span className="unavailable">未接続</span></div><div className="settings-row"><span>作業中・一時停止中は、報酬や利用開始の通知を出しません</span><strong>常に有効</strong></div></section>
      <section className="card settings-section"><h2>プライバシー</h2><div className="settings-row"><span>観測する情報<small>前面アプリ名・アプリID、入力アイドル、対応ブラウザーのドメインをこのMacへ保存します</small></span><span>ローカル</span></div><p className="settings-note">キー入力の内容、raw URL、ページタイトル、画面画像、ブラウザーのタブIDは取得・保存しません。アプリ・ドメインの分類と報酬評価は未接続です。</p></section>
      <div className="settings-save"><button type="submit" className="button primary" disabled={busy || !canSaveTasks || !draftIsValid || !hasUnsavedChanges}>保存</button></div>
    </form>
  </div>;
}
