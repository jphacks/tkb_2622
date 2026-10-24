export type Platform = 'macos' | 'windows' | 'unsupported';
export type SessionStatus = 'RUNNING' | 'PAUSED' | 'FINALIZED' | 'ABORTED' | 'COMPLETED_LOCAL' | 'ABORTED_LOCAL';
export interface Task { id: string; name: string; plannedSeconds: number; minimumSeconds: number }
export interface WorkSession { id: string; name: string; status: SessionStatus; task: Task; elapsedSeconds: number; evaluation: 'pending' | 'complete' | 'failed' }
export interface Capability { allowed: boolean; reason: string }
export interface Failure { code: string; message: string; retryable: boolean }
export interface Classification { name: string; category: 'work' | 'distraction' | 'uncertain' }
export interface Settings { tasks: Task[]; selectedTaskId: string; classifications: Classification[] }
export interface Result { sessionId: string; name: string; status: SessionStatus; elapsedSeconds: number; workSeconds: number; distractedSeconds: number; uncertainSeconds: number; earnedSeconds: number; usedSeconds: number; discardedSeconds: number }
export type SessionAction = 'start' | 'pause' | 'resume' | 'finish' | 'abort' | 'retry';
export interface Snapshot {
  revision: number; platform: Platform; mode: 'demo'; updatedAt: string;
  session: WorkSession | null; balanceSeconds: number | null;
  sync: 'synced' | 'pending' | 'failed'; permission: 'unknown' | 'denied'; online: boolean;
  restrictionDesired: 'unknown' | 'restricted' | 'unrestricted'; restrictionConfirmed: boolean;
  settings: Settings; history: Result[]; result: Result | null;
  actions: Record<SessionAction, Capability>; failure: Failure | null;
}
export type Command =
  | { action: SessionAction; name?: string }
  | { action: 'scenario'; scenarioId: string }
  | { action: 'connection' }
  | { action: 'saveTask'; task: Task }
  | { action: 'classification'; classification: Classification }
  | { action: 'saveSettings'; settings: Settings };
export interface DesktopBridge {
  getStartupState(): Promise<Snapshot>;
  execute(command: Command): Promise<Snapshot>;
  subscribe(listener: (state: Snapshot) => void): () => void;
  dispose(): void;
}
