import { Brand, Navigation, type ShellProps } from '../../components/Shell';
import './windows.css';

// Windows担当者が，状態管理を変えずにOS固有の外枠へ差し替える入口．
export function WindowsShell({ children, ...navigation }: ShellProps) {
  return <div className="app-shell windows"><aside className="sidebar"><Brand /><Navigation {...navigation} /><div className="sidebar-balance"><span>報酬残高</span><strong>{navigation.balanceLabel}</strong></div></aside><main id="main-content">{children}</main></div>;
}
