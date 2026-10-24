import type { Command, DesktopBridge, Snapshot } from '../bridge/types';

export interface ViewState { snapshot: Snapshot | null; busy: boolean; error: string | null }

export class DesktopStore {
  private view: ViewState = { snapshot: null, busy: false, error: null };
  private listeners = new Set<() => void>();
  private unsubscribe: (() => void) | undefined;
  private generation = 0;
  constructor(private bridge: DesktopBridge) {}
  getSnapshot = () => this.view;
  subscribe = (listener: () => void) => { this.listeners.add(listener); return () => { this.listeners.delete(listener); }; };
  private set(next: Partial<ViewState>) { this.view = { ...this.view, ...next }; for (const listener of this.listeners) listener(); }
  private accept(snapshot: Snapshot) {
    if (this.view.snapshot && snapshot.revision <= this.view.snapshot.revision) return;
    this.set({ snapshot, error: null });
  }
  async connect() {
    const generation = ++this.generation;
    this.unsubscribe?.();
    this.unsubscribe = this.bridge.subscribe(state => { if (generation === this.generation) this.accept(state); });
    try { const state = await this.bridge.getStartupState(); if (generation === this.generation) this.accept(state); }
    catch { if (generation === this.generation) this.set({ error: 'Goとの接続に失敗しました。接続を再試行してください。' }); }
  }
  disconnect() { this.generation++; this.unsubscribe?.(); this.unsubscribe = undefined; }
  async execute(command: Command): Promise<Snapshot | null> {
		return this.perform(() => this.bridge.execute(command));
	}
	async requestEmailOTP(email: string): Promise<Snapshot | null> {
		return this.perform(() => this.bridge.requestEmailOTP(email));
	}
	async verifyEmailOTP(email: string, code: string): Promise<Snapshot | null> {
		return this.perform(() => this.bridge.verifyEmailOTP(email, code));
	}
	async signOut(): Promise<Snapshot | null> {
		return this.perform(() => this.bridge.signOut());
	}
	private async perform(operation: () => Promise<Snapshot>): Promise<Snapshot | null> {
    if (this.view.busy) return null;
    const generation = this.generation;
    this.set({ busy: true, error: null });
    try {
      const state = await operation();
      if (generation !== this.generation) return null;
      this.accept(state);
      return state;
    }
    catch {
      if (generation === this.generation) this.set({ error: '操作の結果を取得できませんでした。状態を再取得してください。' });
      return null;
    }
    finally { this.set({ busy: false }); }
  }
}
