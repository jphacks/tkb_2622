export type Platform = 'macos' | 'windows' | 'unsupported';
export type SessionStatus = 'RUNNING' | 'PAUSED' | 'FINALIZED' | 'ABORTED' | 'COMPLETED_LOCAL' | 'ABORTED_LOCAL';
export interface Task { id: string; name: string; category?: string; mode?: string; plannedSeconds: number; minimumSeconds: number; version?: number; pendingOperationId?: string; pendingSettingsHash?: string }
export interface WorkSession { id: string; name: string; status: SessionStatus; task: Task; serverVersion?: number; trackingOnly?: boolean; classifications?: Classification[]; rulesVersion?: string; elapsedSeconds: number; evaluation: 'pending' | 'complete' | 'failed' }
export interface CloudSession { id: string; taskId: string; name: string; status: string; version: number; ownedByThisDevice: boolean; trackingOnly?: boolean; message: string }
export interface Capability { allowed: boolean; reason: string }
export interface Failure { code: string; message: string; retryable: boolean }
export interface AccountState { status: 'unconfigured' | 'storageUnavailable' | 'signedOut' | 'otpPending' | 'signedIn' | 'error' | 'demo'; email: string; deviceRegistered: boolean; message: string }
export interface MonitorStatus { state: string; appId?: string; appName: string; browserName: string; domain: string; lastSample: string; sampleCount: number; message: string }
export interface Classification { name: string; appId?: string; domain?: string; category: 'work' | 'related' | 'distraction' | 'uncertain' }
export interface ClassificationCandidate { name: string; appId: string; appName: string; domain: string; sampleCount: number }
export interface Settings { tasks: Task[]; selectedTaskId: string; classifications: Classification[] }
export interface Result { sessionId: string; name: string; status: SessionStatus; elapsedSeconds: number; taskSeconds?: number; relatedSeconds?: number; workSeconds: number; distractedSeconds: number; uncertainSeconds: number; inactiveSeconds?: number; evaluatorVersion?: string; b100?: number; q?: number; workRate?: number; earnedSeconds: number; usedSeconds: number; discardedSeconds: number }
export type SessionAction = 'start' | 'pause' | 'resume' | 'finish' | 'abort' | 'retry';
export interface Snapshot {
  revision: number; platform: Platform; mode: 'demo' | 'local-monitor'; updatedAt: string;
  session: WorkSession | null; cloudSession?: CloudSession | null; balanceSeconds: number | null;
  cloudOperationPending?: boolean;
  sync: 'synced' | 'pending' | 'failed'; permission: 'unknown' | 'denied'; online: boolean;
  monitor?: MonitorStatus;
  account?: AccountState;
  restrictionDesired: 'unknown' | 'restricted' | 'unrestricted'; restrictionConfirmed: boolean;
  settings: Settings; history: Result[]; result: Result | null;
  actions: Record<SessionAction, Capability>; failure: Failure | null;
}
export type Command =
  | { action: SessionAction; name?: string }
  | { action: 'abortCloudSession' }
  | { action: 'scenario'; scenarioId: string }
  | { action: 'connection' }
  | { action: 'saveTask'; task: Task }
  | { action: 'classification'; classification: Classification }
  | { action: 'saveSettings'; settings: Settings };
export interface DesktopBridge {
  getStartupState(): Promise<Snapshot>;
  getClassificationCandidates(): Promise<ClassificationCandidate[]>;
  captureCurrentClassificationCandidate(): Promise<ClassificationCandidate>;
  execute(command: Command): Promise<Snapshot>;
  requestEmailOTP(email: string): Promise<Snapshot>;
  verifyEmailOTP(email: string, code: string): Promise<Snapshot>;
  signOut(): Promise<Snapshot>;
  subscribe(listener: (state: Snapshot) => void): () => void;
  dispose(): void;
}
