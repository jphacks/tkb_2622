import type { Command, DesktopBridge, Snapshot } from './types';

// 生成コードはブラウザ用ビルドで評価せず，ネイティブ接続時だけ読み込む．
export async function createWailsBridge(): Promise<DesktopBridge> {
  const [binding, runtime] = await Promise.all([
    import('../../wailsjs/go/app/App'),
    import('../../wailsjs/runtime/runtime'),
  ]);
  const listeners = new Set<() => void>();
  return {
    async getStartupState() { return await binding.GetStartupState() as Snapshot; },
    async execute(command: Command) { return await binding.Execute(command as Parameters<typeof binding.Execute>[0]) as Snapshot; },
    async requestEmailOTP(email: string) { return await binding.RequestEmailOTP(email) as Snapshot; },
    async verifyEmailOTP(email: string, code: string) { return await binding.VerifyEmailOTP(email, code) as Snapshot; },
    async signOut() { return await binding.SignOut() as Snapshot; },
    subscribe(listener) {
      const off = runtime.EventsOn('desktop:state', (state: Snapshot) => listener(state));
      listeners.add(off);
      return () => { off(); listeners.delete(off); };
    },
    dispose() { for (const off of listeners) off(); listeners.clear(); },
  };
}
