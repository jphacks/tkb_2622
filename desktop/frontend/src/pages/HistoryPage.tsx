import type { CSSProperties } from 'react';
import type { Result, SessionStatus } from '../bridge/types';
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
  reward: '#28765F',
  balance: '#78612D',
};

const cardStyle: CSSProperties = {
  background: '#FFFFFF',
  border: `1px solid ${colors.border}`,
  borderRadius: 16,
  padding: '22px 24px',
  display: 'flex',
  flexDirection: 'column',
};

const headingStyle: CSSProperties = {
  margin: 0,
  fontSize: 15,
  fontWeight: 700,
};

const tableHeaderStyle: CSSProperties = {
  padding: '8px 6px',
  fontWeight: 500,
  borderBottom: `1px solid ${colors.border}`,
};

const tableCellStyle: CSSProperties = {
  padding: '12px 6px',
  borderBottom: `1px solid ${colors.softBorder}`,
};

const statusColors: Record<SessionStatus, { background: string; foreground: string }> = {
  RUNNING: { background: '#FFF1C2', foreground: '#6E4E00' },
  PAUSED: { background: '#DDF6F0', foreground: '#076353' },
  FINALIZED: { background: '#DDF6F0', foreground: '#076353' },
  ABORTED: { background: '#F2EFF7', foreground: '#655B79' },
  COMPLETED_LOCAL: { background: '#FFF1C2', foreground: '#6E4E00' },
  ABORTED_LOCAL: { background: '#FFF1C2', foreground: '#6E4E00' },
};

const weekDays = ['月', '火', '水', '木', '金', '土', '日'];

export function HistoryPage({ history, onSelect }: { history: Result[]; onSelect: (result: Result) => void }) {
  const hasHistory = history.length > 0;
  const recordedWorkSeconds = history.reduce((total, item) => total + item.workSeconds, 0);
  const recordedEarnedSeconds = history.reduce((total, item) => total + item.earnedSeconds, 0);
  const recordedSessions = hasHistory ? String(history.length) : '—';
  const workSummary = hasHistory ? duration(recordedWorkSeconds) : '—';
  const rewardSummary = hasHistory ? duration(recordedEarnedSeconds) : '—';

  return <div style={{ display: 'flex', flexDirection: 'column', gap: 20, minWidth: 0 }}>
    <header style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', justifyContent: 'space-between', gap: 16 }}>
      <div>
        <h1 style={{ margin: 0, color: colors.ink, fontSize: 26, lineHeight: 1.4, fontWeight: 700 }}>これまでの記録</h1>
        <div style={{ fontSize: 13, color: colors.muted, marginTop: 4 }}>日時データ未取得 · 期間絞り込み未対応</div>
      </div>
      <div role="group" aria-label="期間（日時データ未取得のため選択できません）" style={{ display: 'inline-flex', padding: 4, borderRadius: 12, background: '#ECE9FF', gap: 4 }}>
        <button type="button" disabled aria-pressed={false} style={{ minHeight: 36, padding: '0 18px', borderRadius: 9, border: 0, background: 'transparent', color: '#3F2FB8', fontSize: 13 }}>週</button>
        <button type="button" disabled aria-pressed={false} style={{ minHeight: 36, padding: '0 18px', borderRadius: 9, border: 0, background: 'transparent', color: '#3F2FB8', fontSize: 13 }}>月</button>
      </div>
    </header>

    <section aria-label="記録の集計" style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: 14 }}>
      <div style={{ background: '#FFFFFF', border: `1px solid ${colors.border}`, borderRadius: 16, padding: '18px 20px' }}>
        <div style={{ fontSize: 13, color: colors.muted }}>記録内の作業時間</div>
        <div style={{ fontSize: 28, fontWeight: 700, marginTop: 4, color: colors.work, fontVariantNumeric: 'tabular-nums' }}>{workSummary}</div>
        <div style={{ fontSize: 12, color: colors.muted, marginTop: 2 }}>全セッションの合計 · {recordedSessions}件</div>
      </div>
      <div style={{ background: '#FFFFFF', border: `1px solid ${colors.border}`, borderRadius: 16, padding: '18px 20px' }}>
        <div style={{ fontSize: 13, color: colors.muted }}>平均集中スコア</div>
        <div style={{ fontSize: 28, fontWeight: 700, marginTop: 4, color: colors.ink }}>—</div>
        <div style={{ fontSize: 12, color: colors.muted, marginTop: 2 }}>スコアデータ未取得</div>
      </div>
      <div style={{ background: '#FFFFFF', border: `1px solid ${colors.border}`, borderRadius: 16, padding: '18px 20px' }}>
        <div style={{ fontSize: 13, color: colors.muted }}>記録内の獲得報酬</div>
        <div style={{ fontSize: 28, fontWeight: 700, marginTop: 4, color: colors.reward, fontVariantNumeric: 'tabular-nums' }}>{rewardSummary}</div>
        <div style={{ fontSize: 12, color: colors.muted, marginTop: 2 }}>全セッションの合計 · {recordedSessions}件</div>
      </div>
      <div style={{ background: '#FFFFFF', border: `1px solid ${colors.border}`, borderRadius: 16, padding: '18px 20px' }}>
        <div style={{ fontSize: 13, color: colors.muted }}>現在の報酬残高</div>
        <div style={{ fontSize: 28, fontWeight: 700, marginTop: 4, color: colors.balance }}>—</div>
        <div style={{ fontSize: 12, color: colors.muted, marginTop: 2 }}>残高データ未取得</div>
      </div>
    </section>

    <section style={{ ...cardStyle, gap: 16 }}>
      <div style={{ display: 'flex', flexWrap: 'wrap', justifyContent: 'space-between', gap: 12, alignItems: 'baseline' }}>
        <h2 style={headingStyle}>日ごとの作業時間</h2>
        <div style={{ display: 'flex', gap: 14, fontSize: 12, color: colors.muted }}>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}><span aria-hidden="true" style={{ display: 'inline-block', width: 10, height: 10, borderRadius: 3, background: colors.work }} />作業</span>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}><span aria-hidden="true" style={{ display: 'inline-block', width: 10, height: 10, borderRadius: 3, background: colors.distraction }} />脱線</span>
        </div>
      </div>
      <div role="img" aria-label="日別の作業時間と脱線時間は未取得です" style={{ position: 'relative', display: 'grid', gridTemplateColumns: 'repeat(7, minmax(0, 1fr))', gap: 12, alignItems: 'end', height: 200, borderBottom: `1px solid ${colors.softBorder}` }}>
        {weekDays.map(day => <div key={day} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'flex-end', gap: 6, height: '100%' }}>
          <span style={{ fontSize: 12, fontWeight: 700, color: colors.muted, fontVariantNumeric: 'tabular-nums' }}>—</span>
        </div>)}
        <span style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 12, color: colors.muted, fontSize: 13, textAlign: 'center', pointerEvents: 'none' }}>
          日別値は未取得です
        </span>
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, minmax(0, 1fr))', gap: 12, textAlign: 'center', fontSize: 12, color: colors.muted }}>
        {weekDays.map(day => <span key={day}>{day}</span>)}
      </div>
    </section>

    <section style={{ display: 'flex', flexWrap: 'wrap', gap: 20, alignItems: 'flex-start' }}>
      <div style={{ ...cardStyle, flex: '3 1 520px', minWidth: 0, gap: 12 }}>
        <h2 style={headingStyle}>セッション</h2>
        <div style={{ overflowX: 'auto' }}>
          <table style={{ width: '100%', minWidth: 560, borderCollapse: 'collapse', fontSize: 14, fontVariantNumeric: 'tabular-nums', textAlign: 'left', whiteSpace: 'nowrap' }}>
            <thead>
              <tr style={{ color: colors.muted, fontSize: 12 }}>
                <th scope="col" style={tableHeaderStyle}>作業名</th>
                <th scope="col" style={tableHeaderStyle}>作業時間</th>
                <th scope="col" style={tableHeaderStyle}>スコア</th>
                <th scope="col" style={tableHeaderStyle}>状態</th>
                <th scope="col" style={tableHeaderStyle}><span className="sr-only">詳細</span></th>
              </tr>
            </thead>
            <tbody>
              {history.length === 0 ? <tr>
                <td colSpan={5} style={{ ...tableCellStyle, padding: '18px 6px', textAlign: 'center', color: colors.muted, whiteSpace: 'normal' }}>記録はありません。</td>
              </tr> : history.map(item => {
                const statusColor = statusColors[item.status];
                return <tr key={item.sessionId}>
                  <td style={tableCellStyle}>
                    <div style={{ fontWeight: 500 }}>{item.name}</div>
                    <div style={{ fontSize: 12, color: colors.muted }}>日時未取得</div>
                  </td>
                  <td style={tableCellStyle}>{duration(item.workSeconds)}</td>
                  <td style={{ ...tableCellStyle, fontWeight: 700 }} title="集中スコアは未取得">—</td>
                  <td style={tableCellStyle}><span style={{ fontSize: 12, fontWeight: 700, padding: '3px 10px', borderRadius: 99, background: statusColor.background, color: statusColor.foreground, whiteSpace: 'nowrap' }}>{statusLabels[item.status] ?? '状態未取得'}</span></td>
                  <td style={{ ...tableCellStyle, textAlign: 'right' }}><button type="button" onClick={() => onSelect(item)} style={{ padding: 0, border: 0, background: 'transparent', color: '#5B4BDB', fontSize: 13 }}>詳しく<span className="sr-only">：{item.name}</span></button></td>
                </tr>;
              })}
            </tbody>
          </table>
        </div>
      </div>

      <div style={{ ...cardStyle, flex: '2 1 300px', minWidth: 0, gap: 4 }}>
        <h2 style={{ ...headingStyle, marginBottom: 8 }}>報酬の履歴</h2>
        {history.length === 0 ? <p style={{ margin: '10px 0', fontSize: 13, color: colors.muted }}>報酬に関するセッション記録はありません。</p> : <>
          {history.map(item => <div key={item.sessionId} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '10px 0', borderBottom: `1px solid ${colors.softBorder}`, fontVariantNumeric: 'tabular-nums' }}>
            <span style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
              <span style={{ fontSize: 14, overflowWrap: 'anywhere' }}>{item.name} の獲得報酬</span>
              <span style={{ fontSize: 12, color: colors.muted }}>日時未取得 · セッション集計</span>
            </span>
            <span style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 2, whiteSpace: 'nowrap' }}>
              <span style={{ fontSize: 15, fontWeight: 700, color: colors.purple }}>+{duration(item.earnedSeconds)}</span>
              <span style={{ fontSize: 12, color: colors.muted }}>残高 —（未取得）</span>
            </span>
          </div>)}
          <p style={{ margin: '10px 0 0', fontSize: 12, color: colors.muted }}>取引日時・現在残高を含む明細は未取得です。</p>
        </>}
      </div>
    </section>
  </div>;
}
