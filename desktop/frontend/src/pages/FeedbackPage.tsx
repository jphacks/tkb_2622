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
  distraction: '#FF7A59',
  uncertain: '#9A91AE',
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

export function FeedbackPage({ result }: { result: Result | null }) {
  const categorySeconds = [
    result?.workSeconds ?? 0,
    result?.distractedSeconds ?? 0,
    result?.uncertainSeconds ?? 0,
  ];
  const classifiedSeconds = categorySeconds.reduce((total, seconds) => total + Math.max(0, seconds), 0);
  const timeFor = (seconds: number | undefined) => result && seconds !== undefined ? duration(seconds) : '—';

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
          同期・評価状態 未取得
        </span>
      </div>
    </header>

    <section style={{ display: 'flex', flexWrap: 'wrap', gap: 14 }} aria-label="報酬と集中スコア">
      <div style={{ flex: '1 1 260px', boxSizing: 'border-box', background: colors.purple, color: '#FFFFFF', borderRadius: 16, padding: '20px 22px', display: 'flex', flexDirection: 'column', gap: 6 }}>
        <div style={{ fontSize: 13, color: '#E4E0FF' }}>獲得した報酬</div>
        <div style={{ fontWeight: 700, fontSize: 44, lineHeight: 1.1, fontVariantNumeric: 'tabular-nums' }}>
          {result ? `+${duration(result.earnedSeconds)}` : '—'}
        </div>
        <div style={{ fontSize: 13, color: '#E4E0FF' }}>算定根拠・受取前後の残高：未取得</div>
      </div>
      <div style={{ flex: '1 1 200px', boxSizing: 'border-box', background: '#FFFFFF', border: `1px solid ${colors.border}`, borderRadius: 16, padding: '20px 22px', display: 'flex', flexDirection: 'column', gap: 6 }}>
        <div style={{ fontSize: 13, color: colors.muted }}>集中スコア</div>
        <div style={{ fontSize: 40, fontWeight: 700, lineHeight: 1.1 }}>—<span style={{ fontSize: 15, fontWeight: 500 }}> / 100</span></div>
        <div style={{ fontSize: 12, color: colors.muted }}>スコア・判定ルールは未取得</div>
      </div>
    </section>

    <section style={cardStyle}>
      <div style={{ display: 'flex', flexWrap: 'wrap', justifyContent: 'space-between', gap: 12, alignItems: 'baseline' }}>
        <h2 style={headingStyle}>計測時間 {timeFor(result?.elapsedSeconds)} の内訳</h2>
        <span style={metaStyle}>一時停止時間は未取得</span>
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, minmax(0, 1fr))', gap: 12 }}>
        {categories.map((category, index) => {
          const seconds = categorySeconds[index];
          return <div key={category.key} style={{ borderRadius: 12, background: category.background, padding: '14px 16px', minWidth: 0 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 13, fontWeight: 700, color: category.foreground }}>
              <span aria-hidden="true" style={{ display: 'inline-block', width: 10, height: 10, flex: '0 0 10px', borderRadius: 3, background: category.color }} />
              {category.label}
            </div>
            <div style={{ fontSize: 24, fontWeight: 700, marginTop: 4, fontVariantNumeric: 'tabular-nums' }}>{timeFor(result ? seconds : undefined)}</div>
            <div style={{ fontSize: 12, color: colors.muted }}>分類根拠は未取得</div>
          </div>;
        })}
      </div>
      <div role="img" aria-label="作業、脱線、保留の時間内訳" style={{ display: 'flex', height: 30, borderRadius: 6, overflow: 'hidden', background: '#EFEDF7' }}>
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
      <p style={{ margin: 0, fontSize: 13, color: colors.muted }}>保留の内訳・判定理由は未取得です。実際のアプリ利用状況は計測していません。</p>
    </section>

    <section style={{ ...cardStyle, gap: 12 }}>
      <div style={{ display: 'flex', flexWrap: 'wrap', justifyContent: 'space-between', gap: 12, alignItems: 'baseline' }}>
        <h2 style={headingStyle}>判定の根拠（アプリ・サイト別）</h2>
        <span style={metaStyle}>分類根拠は未取得です</span>
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
                アプリ・サイト別の判定データは未取得です。
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
