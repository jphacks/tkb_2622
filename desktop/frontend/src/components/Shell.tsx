import type { ReactNode } from 'react';

export type Page = 'session' | 'feedback' | 'history' | 'settings';
export interface ShellProps { page: Page; onNavigate: (page: Page) => void; balanceLabel: string; children: ReactNode }
const navigation: { id: Page; label: string }[] = [
  { id: 'feedback', label: '今回のフィードバック' },
  { id: 'history', label: 'これまでの記録' },
  { id: 'settings', label: '設定' },
];

export function Navigation({ page, onNavigate }: Pick<ShellProps, 'page' | 'onNavigate'>) {
  return <nav className="main-navigation" aria-label="メニュー">{navigation.map(item =>
    <button key={item.id} className={page === item.id ? 'nav-item selected' : 'nav-item'} aria-current={page === item.id ? 'page' : undefined} onClick={() => onNavigate(item.id)}>{item.label}</button>)}</nav>;
}

export function Brand({ onClick }: { onClick?: () => void }) {
  const content = <><span className="brand-symbol" aria-hidden="true"><svg width="16" height="16" viewBox="8 8 84 84"><g transform="translate(50 50) scale(1) translate(-50 -50)" fill="currentColor"><rect x="30" y="14" width="40" height="28" rx="6" fill="none" stroke="currentColor" strokeWidth="8"/><rect x="38" y="45" width="24" height="6" rx="3"/><rect x="45" y="48" width="10" height="42" rx="5"/><rect x="51" y="66" width="14" height="7" rx="3"/><rect x="51" y="78" width="10" height="7" rx="3"/></g></svg></span><span>Focus Link</span></>;
  if (onClick) return <button type="button" className="brand brand-button" aria-label="Focus Link、作業画面に戻る" title="作業画面に戻る" onClick={onClick}>{content}</button>;
  return <div className="brand">{content}</div>;
}
