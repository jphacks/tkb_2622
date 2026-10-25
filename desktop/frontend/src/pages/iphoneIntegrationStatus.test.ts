import { describe, expect, it } from 'vitest';
import type { AccountState, IPhoneRestrictionState } from '../bridge/types';
import { iPhoneIntegrationStatus } from './iphoneIntegrationStatus';

const signedIn: AccountState = {
  status: 'signedIn', email: 'demo@example.com', deviceRegistered: true, message: '',
};

const phoneReport: IPhoneRestrictionState = {
  sessionId: 'session-1', deviceId: 'iphone-1', controlRevision: 2,
  desiredMode: 'SHIELDED', appliedRevision: 2, shieldStatus: 'SHIELDED',
  permissionStatus: 'GRANTED', lastReportedAt: '2026-10-25T00:00:00Z',
};

describe('iPhoneIntegrationStatus', () => {
  it('shows when an iPhone report has reached the server', () => {
    expect(iPhoneIntegrationStatus(signedIn, phoneReport, undefined)).toBe('iPhone報告受信');
  });

  it('distinguishes an authenticated account waiting for an iPhone report', () => {
    expect(iPhoneIntegrationStatus(signedIn, null, undefined)).toBe('状態報告待ち');
  });

  it('surfaces iPhone state API failures instead of claiming the integration is disconnected', () => {
    expect(iPhoneIntegrationStatus(signedIn, null, 'GetRestrictionState failed')).toBe('状態取得エラー');
  });

  it('shows account connection failures separately from missing iPhone reports', () => {
    expect(iPhoneIntegrationStatus({ ...signedIn, status: 'error' }, null, undefined)).toBe('API接続エラー');
    expect(iPhoneIntegrationStatus({ ...signedIn, status: 'signedOut' }, null, undefined)).toBe('未ログイン');
  });
});
