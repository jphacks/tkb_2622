import type { AccountState, IPhoneRestrictionState } from '../bridge/types';

export function iPhoneIntegrationStatus(
  account: AccountState,
  restriction: IPhoneRestrictionState | null | undefined,
  restrictionError: string | undefined,
): string {
  if (account.status === 'error') return 'API接続エラー';
  if (account.status === 'signedIn') {
    if (restrictionError) return '状態取得エラー';
    return restriction?.deviceId ? 'iPhone報告受信' : '状態報告待ち';
  }

  switch (account.status) {
    case 'unconfigured': return '接続先未設定';
    case 'storageUnavailable': return '資格情報ストア未使用';
    case 'otpPending': return 'ログイン確認中';
    case 'demo': return 'デモ表示';
    case 'signedOut': return '未ログイン';
  }
}
