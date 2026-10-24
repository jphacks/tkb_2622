import { Brand, Navigation, type ShellProps } from '../../components/Shell';
import './macos.css';

export function MacShell({ children, ...navigation }: ShellProps) {
  return <div className="app-shell macos"><aside className="sidebar"><Brand /><Navigation {...navigation} /><div className="sidebar-balance"><span>報酬残高</span><strong>{navigation.balanceLabel}</strong></div></aside><main id="main-content">{children}</main></div>;
}
