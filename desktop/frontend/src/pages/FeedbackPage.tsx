import type { CSSProperties } from 'react';
import type { Result } from '../bridge/types';
import { duration } from '../components/format';
import { statusLabels } from './SessionPage';

const colors = {
  ink: '#1E1B3A',
  muted: '#5E5A78',
  border: '#E6E2F3',
  softBorder: '#F2F0FA',
  purple: '#5B4BDB',
  work: '#6D5DF0',
  related: '#9B86F5',
  distraction: '#FF7A59',
  uncertain: '#9A91AE',
  inactive: '#64748B',
};

const cardStyle: CSSProperties = {
  background: '#FFFFFF',
  border: `1px solid ${colors.border}`,
  borderRadius: 16,
  padding: '22px 24px',
  display: 'flex',
  flexDirection: 'column',
  gap: 16,
};

const headingStyle: CSSProperties = {
  margin: 0,
  fontSize: 15,
  fontWeight: 700,
};

const metaStyle: CSSProperties = {
  fontSize: 12,
  color: colors.muted,
};

const tableHeaderStyle: CSSProperties = {
  padding: '8px 6px',
  fontWeight: 500,
  borderBottom: `1px solid ${colors.border}`,
};

const tableCellStyle: CSSProperties = {
  padding: '10px 6px',
  borderBottom: `1px solid ${colors.softBorder}`,
};

const categories = [
  { key: 'work', label: '作業', color: colors.work, background: '#ECE9FF', foreground: '#4336B8' },
  { key: 'distraction', label: '脱線', color: colors.distraction, background: '#FFF0E9', foreground: '#A64A32' },
  { key: 'uncertain', label: '保留', color: colors.uncertain, background: '#F2EFF7', foreground: '#655B79' },
] as const;

export function FeedbackPage({ result, mode }: { result: Result | null; mode: 'demo' | 'local-monitor' }) {
  const hasLocalEvaluation = mode === 'local-monitor' && Boolean(result?.evaluatorVersion);
  const categories = hasLocalEvaluation ? [
    { key: 'task', label: '作業（T）', color: colors.work, background: '#ECE9FF', foreground: '#4336B8' },
    { key: 'related', label: '関連作業（R）', color: colors.related, background: '#F0EBFF', foreground: '#553DAD' },
    { key: 'distraction', label: '脱線（D）', color: colors.distraction, background: '#FFF0E9', foreground: '#A64A32' },
    { key: 'uncertain', label: '不明（U）', color: colors.uncertain, background: '#F2EFF7', foreground: '#655B79' },
    { key: 'inactive', label: '非活動（I）', color: colors.inactive, background: '#EEF2F6', foreground: '#475569' },
  ] : [
    { key: 'work', label: '作業', color: colors.work, background: '#ECE9FF', foreground: '#4336B8' },
    { key: 'distraction', label: '脱線', color: colors.distraction, background: '#FFF0E9', foreground: '#A64A32' },
    { key: 'uncertain', label: '保留', color: colors.uncertain, background: '#F2EFF7', foreground: '#655B79' },
  ];
  const categorySeconds = hasLocalEvaluation ? [
    result?.taskSeconds ?? 0, result?.relatedSeconds ?? 0, result?.distractedSeconds ?? 0,
    result?.uncertainSeconds ?? 0, result?.inactiveSeconds ?? 0,
  ] : [result?.workSeconds ?? 0, result?.distractedSeconds ?? 0, result?.uncertainSeconds ?? 0];
  const classifiedSeconds = categorySeconds.reduce((total, seconds) => total + Math.max(0, seconds), 0);
  const timeFor = (seconds: number | undefined) => result && seconds !== undefined ? duration(seconds) : '—';
  const percentage = (value: number | undefined, multiplier = 100) =>
    value !== undefined && Number.isFinite(value) ? `${(value * multiplier).toFixed(1)}%` : '—';

  const calculatedWorkSeconds = (result?.taskSeconds ?? 0) + (result?.relatedSeconds ?? 0);
  const knownSeconds = calculatedWorkSeconds + (result?.distractedSeconds ?? 0);
  const evaluationSeconds = result?.elapsedSeconds ?? 0;
  const b100 = result?.b100 ?? (knownSeconds > 0 ? 100 * calculatedWorkSeconds / knownSeconds : undefined);
  const q = result?.q ?? (evaluationSeconds > 0 ? (knownSeconds + (result?.inactiveSeconds ?? 0)) / evaluationSeconds : undefined);
  const workRate = result?.workRate ?? (evaluationSeconds > 0 ? calculatedWorkSeconds / evaluationSeconds : undefined);
  return <div style={{ display: 'flex', flexDirection: 'column', gap: 20, minWidth: 0 }}>
    <header style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
      <div style={{ fontSize: 13, color: colors.muted }}>
        {result?.name || '作業名 —'} ・ 日時・作業時間帯 未取得
      </div>
      <h1 style={{ margin: 0, color: colors.ink, fontSize: 26, lineHeight: 1.4, fontWeight: 700 }}>おつかれさまでした</h1>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
        <span style={{ fontSize: 13, padding: '4px 12px', borderRadius: 99, background: '#FFF1C2', color: '#6E4E00', fontWeight: 700 }}>
          {result ? statusLabels[result.status] ?? '状態未取得' : '結果はありません'}
        </span>
        <span style={{ fontSize: 13, padding: '4px 12px', borderRadius: 99, background: '#F2EFF7', color: '#655B79', fontWeight: 700 }}>
          {mode === 'local-monitor' ? (hasLocalEvaluation ? 'ローカル5分類評価済み' : 'ローカル評価未完了') : '同期・評価状態 未取得'}
        </span>
      </div>
    </header>

    <section className="result-metrics-grid" aria-label="報酬と分類指標">
      <div style={{ minWidth: 0, boxSizing: 'border-box', background: colors.purple, color: '#FFFFFF', borderRadius: 16, padding: '20px 22px', display: 'flex', flexDirection: 'column', gap: 6 }}>
        <div style={{ fontSize: 13, color: '#E4E0FF' }}>{mode === 'local-monitor' ? '報酬（未確定）' : '獲得した報酬'}</div>
        <div style={{ fontWeight: 700, fontSize: 44, lineHeight: 1.1, fontVariantNumeric: 'tabular-nums' }}>
          {mode === 'local-monitor' ? '—' : result ? `+${duration(result.earnedSeconds)}` : '—'}
        </div>
        <div style={{ fontSize: 13, color: '#E4E0FF' }}>{mode === 'local-monitor' ? '報酬換算式・報酬APIは未接続です' : '算定根拠・受取前後の残高：未取得'}</div>
      </div>
      {hasLocalEvaluation ? [
        { label: '既知分類内の作業割合（B100）', value: percentage(b100, 1), detail: '100×(T+R)/(T+R+D)。不明・非活動は分母に含みません。' },
        { label: '判定カバレッジ（Q）', value: percentage(q), detail: '(T+R+D+I)/E。判定できた時間の割合です。' },
        { label: '計測時間に対する作業割合', value: percentage(workRate), detail: '(T+R)/E。不明時間も含む計測時間を分母にします。' },
      ].map(metric => <div key={metric.label} style={{ minWidth: 0, boxSizing: 'border-box', background: '#FFFFFF', border: `1px solid ${colors.border}`, borderRadius: 16, padding: '20px 22px', display: 'flex', flexDirection: 'column', gap: 6 }}>
        <div style={{ fontSize: 13, color: colors.muted }}>{metric.label}</div>
        <div style={{ fontSize: 34, fontWeight: 700, lineHeight: 1.1, color: colors.ink, fontVariantNumeric: 'tabular-nums' }}>{metric.value}</div>
        <div style={{ fontSize: 12, color: colors.muted }}>{metric.detail}</div>
      </div>) : <div style={{ minWidth: 0, boxSizing: 'border-box', background: '#FFFFFF', border: `1px solid ${colors.border}`, borderRadius: 16, padding: '20px 22px', display: 'flex', flexDirection: 'column', gap: 6 }}>
        <div style={{ fontSize: 13, color: colors.muted }}>集中度</div>
        <div style={{ fontSize: 28, fontWeight: 700, lineHeight: 1.2, color: colors.ink }}>未評価</div>
        <div style={{ fontSize: 12, color: colors.muted }}>分類集計の参考値であり、心理的な集中度を直接測定するスコアはありません。</div>
      </div>}
      {hasLocalEvaluation && <p style={{ flex: '1 1 100%', margin: 0, fontSize: 12, color: colors.muted }}>
        これらはアプリ・サイトの分類集計から算出した参考値で、心理的な集中度を直接測定したスコアではありません。
      </p>}
    </section>

    <section style={cardStyle}>
      <div style={{ display: 'flex', flexWrap: 'wrap', justifyContent: 'space-between', gap: 12, alignItems: 'baseline' }}>
        <h2 style={headingStyle}>計測時間 {timeFor(result?.elapsedSeconds)} の内訳</h2>
        <span style={metaStyle}>{hasLocalEvaluation ? '一時停止区間は集計から除外済み' : '一時停止時間は未取得'}</span>
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))', gap: 12 }}>
        {categories.map((category, index) => {
          const seconds = categorySeconds[index];
          return <div key={category.key} style={{ borderRadius: 12, background: category.background, padding: '14px 16px', minWidth: 0 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 13, fontWeight: 700, color: category.foreground }}>
              <span aria-hidden="true" style={{ display: 'inline-block', width: 10, height: 10, flex: '0 0 10px', borderRadius: 3, background: category.color }} />
              {category.label}
            </div>
            <div style={{ fontSize: 24, fontWeight: 700, marginTop: 4, fontVariantNumeric: 'tabular-nums' }}>{timeFor(result ? seconds : undefined)}</div>
            <div style={{ fontSize: 12, color: colors.muted }}>{hasLocalEvaluation ? result?.evaluatorVersion : '分類根拠は未取得'}</div>
          </div>;
        })}
      </div>
      <div role="img" aria-label={hasLocalEvaluation ? '5分類の時間内訳' : '作業、脱線、保留の時間内訳'} style={{ display: 'flex', height: 30, borderRadius: 6, overflow: 'hidden', background: '#EFEDF7' }}>
        {categories.map((category, index) => {
          const seconds = Math.max(0, categorySeconds[index]);
          const width = classifiedSeconds === 0 ? 0 : seconds / classifiedSeconds * 100;
          return <span key={category.key} style={{ width: `${width}%`, background: category.color, borderRight: width > 0 ? '1px solid #FFFFFF' : undefined }} />;
        })}
      </div>
      <div style={{ display: 'flex', flexWrap: 'wrap', justifyContent: 'space-between', gap: 8, fontSize: 12, color: colors.muted }}>
        <span>開始時刻 —</span>
        <span style={{ display: 'inline-flex', flexWrap: 'wrap', gap: 14 }}>
          {categories.map((category, index) => <span key={category.key} style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
            <span aria-hidden="true" style={{ display: 'inline-block', width: 10, height: 10, borderRadius: 2, background: category.color }} />
            {category.label} {timeFor(result ? categorySeconds[index] : undefined)}
          </span>)}
        </span>
        <span>終了時刻 —</span>
      </div>
      <p style={{ margin: 0, fontSize: 13, color: colors.muted }}>{hasLocalEvaluation ? '5分類はこのMacで集計しました。非活動（I）は確定した画面ロック・スリープ情報がある場合だけ加算します。報酬時間は未確定です。' : mode === 'local-monitor' ? '観測データはこのMacに保存しました。ローカル評価を完了できませんでした。' : '保留の内訳・判定理由は未取得です。実際のアプリ利用状況は計測していません。'}</p>
    </section>

    <section style={{ ...cardStyle, gap: 12 }}>
      <div style={{ display: 'flex', flexWrap: 'wrap', justifyContent: 'space-between', gap: 12, alignItems: 'baseline' }}>
        <h2 style={headingStyle}>アプリ・サイト別の区間</h2>
        <span style={metaStyle}>区間一覧の画面表示は未接続</span>
      </div>
      <div style={{ overflowX: 'auto' }}>
        <table style={{ width: '100%', minWidth: 600, borderCollapse: 'collapse', fontSize: 14, fontVariantNumeric: 'tabular-nums', textAlign: 'left', whiteSpace: 'nowrap' }}>
          <thead>
            <tr style={{ color: colors.muted, fontSize: 12 }}>
              <th scope="col" style={tableHeaderStyle}>アプリ・サイト</th>
              <th scope="col" style={tableHeaderStyle}>時間</th>
              <th scope="col" style={tableHeaderStyle}>判定</th>
              <th scope="col" style={tableHeaderStyle}>根拠</th>
              <th scope="col" style={tableHeaderStyle}><span className="sr-only">操作</span></th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td colSpan={5} style={{ ...tableCellStyle, padding: '18px 6px', textAlign: 'center', color: colors.muted, whiteSpace: 'normal' }}>
                {hasLocalEvaluation ? '5分類の時間合計を上に表示しています。アプリ・サイト別の区間明細は未表示です。' : 'アプリ・サイト別の判定データは未取得です。'}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <div style={{ fontSize: 12, color: colors.muted }}>分類の修正は、判定データの取得後に利用できます。</div>
    </section>

    <section style={{ ...cardStyle, gap: 10 }}>
      <h2 style={headingStyle}>一時停止中の iPhone 利用</h2>
      <div style={{ fontSize: 14, lineHeight: 1.9 }}>
        <div>利用枠 —（未取得）・ 実際に使った時間 <strong>—</strong>（未取得）</div>
        <div>作業再開時に終了した枠の残り：<strong>—</strong>（未取得）</div>
      </div>
      <div style={{ fontSize: 12, color: colors.muted }}>iPhoneの利用・解除適用データは未接続です。</div>
    </section>
  </div>;
}
