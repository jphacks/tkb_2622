import { Brand, Navigation, type ShellProps } from '../../components/Shell';
import './windows.css';

// Windowsにはメニューバーから作業画面へ戻る導線がないため，NavigationViewの戻るボタンに倣って先頭に置く．
export function WindowsShell({ children, ...navigation }: ShellProps) {
  return <div className="app-shell windows"><aside className="sidebar"><button type="button" className="back-button" onClick={() => navigation.onNavigate('session')}><svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M13 8H3"/><path d="M7 4 3 8l4 4"/></svg>作業画面に戻る</button><Brand onClick={() => navigation.onNavigate('session')} /><Navigation {...navigation} /><div className="sidebar-balance"><span>報酬残高</span><strong>{navigation.balanceLabel}</strong></div></aside><main id="main-content">{children}</main></div>;
}
