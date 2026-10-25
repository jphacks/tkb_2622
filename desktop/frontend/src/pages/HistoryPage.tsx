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

export function HistoryPage({ history, onSelect, onRefresh, mode, cloudConnected, historyError, balanceSeconds }: { history: Result[]; onSelect: (result: Result) => void; onRefresh: () => void; mode: 'demo' | 'local-monitor'; cloudConnected: boolean; historyError?: string; balanceSeconds: number | null }) {
  const hasHistory = history.length > 0;
  const historySynced = cloudConnected && !historyError;
  const recordedWorkSeconds = history.reduce((total, item) => total + item.workSeconds, 0);
  const recordedEarnedSeconds = history.reduce((total, item) => total + item.earnedSeconds, 0);
  const recordedSessions = String(history.length);
  const workSummary = hasHistory ? duration(recordedWorkSeconds) : '—';
  const rewardSummary = mode === 'local-monitor' && !historySynced ? '未確定' : hasHistory ? duration(recordedEarnedSeconds) : '—';
  return <div style={{ display: 'flex', flexDirection: 'column', gap: 20, minWidth: 0 }}>
    <header style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', justifyContent: 'space-between', gap: 16 }}>
      <div>
        <h1 style={{ margin: 0, color: colors.ink, fontSize: 26, lineHeight: 1.4, fontWeight: 700 }}>これまでの記録</h1>
        <div style={{ fontSize: 14, color: colors.muted, marginTop: 4 }}>{historySynced ? 'サーバー同期済み' : 'この端末に保存された記録'}</div>
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
        <button type="button" onClick={onRefresh} style={{ minHeight: 40, padding: '0 16px', borderRadius: 10, border: `1px solid ${colors.border}`, background: '#FFFFFF', color: colors.purple, fontSize: 14, fontWeight: 600 }}>更新</button>
      </div>
    </header>

    <section aria-label="記録の集計" style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: 14 }}>
      <div style={{ background: '#FFFFFF', border: `1px solid ${colors.border}`, borderRadius: 16, padding: '18px 20px' }}>
        <div style={{ fontSize: 14, color: colors.muted }}>作業時間の合計</div>
        <div style={{ fontSize: 30, fontWeight: 700, marginTop: 4, color: colors.work, fontVariantNumeric: 'tabular-nums' }}>{workSummary}</div>
        <div style={{ fontSize: 14, color: colors.muted, marginTop: 2 }}>{recordedSessions}セッション</div>
      </div>
      <div style={{ background: '#FFFFFF', border: `1px solid ${colors.border}`, borderRadius: 16, padding: '18px 20px' }}>
        <div style={{ fontSize: 14, color: colors.muted }}>獲得した報酬</div>
        <div style={{ fontSize: 30, fontWeight: 700, marginTop: 4, color: colors.reward, fontVariantNumeric: 'tabular-nums' }}>{rewardSummary}</div>
        <div style={{ fontSize: 14, color: colors.muted, marginTop: 2 }}>{mode === 'local-monitor' && !historySynced ? '同期後に確定します' : `${recordedSessions}セッション分`}</div>
      </div>
      <div style={{ background: '#FFFFFF', border: `1px solid ${colors.border}`, borderRadius: 16, padding: '18px 20px' }}>
        <div style={{ fontSize: 14, color: colors.muted }}>現在の残高</div>
        <div style={{ fontSize: 30, fontWeight: 700, marginTop: 4, color: colors.balance, fontVariantNumeric: 'tabular-nums' }}>{cloudConnected && balanceSeconds !== null ? duration(balanceSeconds) : '—'}</div>
        <div style={{ fontSize: 14, color: colors.muted, marginTop: 2 }}>{cloudConnected ? '利用できる時間' : 'ログイン後に表示'}</div>
      </div>
    </section>

    {historyError && <p role="status" style={{ margin: 0, color: colors.muted, fontSize: 14 }}>{historyError}</p>}

    <section style={{ ...cardStyle, gap: 12 }}>
        <h2 style={headingStyle}>セッション</h2>
        <div style={{ overflowX: 'auto' }}>
          <table style={{ width: '100%', minWidth: 560, borderCollapse: 'collapse', fontSize: 14, fontVariantNumeric: 'tabular-nums', textAlign: 'left', whiteSpace: 'nowrap' }}>
            <thead>
              <tr style={{ color: colors.muted, fontSize: 14 }}>
                <th scope="col" style={tableHeaderStyle}>作業名</th>
                <th scope="col" style={tableHeaderStyle}>作業時間</th>
                <th scope="col" style={tableHeaderStyle}>報酬</th>
                <th scope="col" style={tableHeaderStyle}>状態</th>
                <th scope="col" style={tableHeaderStyle}><span className="sr-only">詳細</span></th>
              </tr>
            </thead>
            <tbody>
              {history.length === 0 ? <tr>
                <td colSpan={5} style={{ ...tableCellStyle, padding: '18px 6px', textAlign: 'center', color: colors.muted, whiteSpace: 'normal' }}>記録はありません。</td>
              </tr> : history.map(item => {
                const statusColor = statusColors[item.status];
                const rewardText = mode === 'local-monitor' && !historySynced
                  ? '未確定'
                  : item.rewardStatus === 'granted'
                    ? `+${duration(item.earnedSeconds)}`
                    : item.rewardStatus === 'ineligible'
                      ? '対象外'
                      : item.rewardStatus === 'pending' || item.rewardStatus === 'queued'
                        ? '確認中'
                        : item.rewardStatus === 'unavailable'
                          ? '—'
                          : item.earnedSeconds > 0 ? `+${duration(item.earnedSeconds)}` : '—';
                return <tr key={item.sessionId}>
                  <td style={tableCellStyle}>
                    <div style={{ fontWeight: 500 }}>{item.name}</div>
                    <div style={{ fontSize: 14, color: colors.muted }}>{item.startedAt ? new Date(item.startedAt).toLocaleString('ja-JP', { dateStyle: 'short', timeStyle: 'short' }) : '日時未取得'}</div>
                  </td>
                  <td style={tableCellStyle}>{duration(item.workSeconds)}</td>
                  <td style={{ ...tableCellStyle, color: item.rewardStatus === 'granted' ? colors.reward : colors.muted, fontWeight: 700 }}>{rewardText}</td>
                  <td style={tableCellStyle}><span style={{ fontSize: 14, fontWeight: 700, padding: '4px 10px', borderRadius: 99, background: statusColor.background, color: statusColor.foreground, whiteSpace: 'nowrap' }}>{statusLabels[item.status] ?? '状態未取得'}</span></td>
                  <td style={{ ...tableCellStyle, textAlign: 'right' }}><button type="button" onClick={() => onSelect(item)} style={{ padding: 0, border: 0, background: 'transparent', color: '#5B4BDB', fontSize: 14, fontWeight: 600 }}>詳しく<span className="sr-only">：{item.name}</span></button></td>
                </tr>;
              })}
            </tbody>
          </table>
        </div>
    </section>
  </div>;
}
