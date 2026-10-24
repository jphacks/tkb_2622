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
  const content = <><span className="brand-symbol" aria-hidden="true"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M12 21v-8"/><path d="M12 13c0-4 3-7 8-7 0 4-3 7-8 7z"/><path d="M12 15c0-3-2.5-5.5-7-5.5 0 3 2.5 5.5 7 5.5z"/></svg></span><span>Focus Link</span></>;
  if (onClick) return <button type="button" className="brand brand-button" aria-label="Focus Link、作業画面に戻る" title="作業画面に戻る" onClick={onClick}>{content}</button>;
  return <div className="brand">{content}</div>;
}
