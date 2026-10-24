import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import type { Result, RewardStatus } from '../bridge/types';
import { FeedbackPage } from './FeedbackPage';

function renderFeedback(rewardStatus: RewardStatus, overrides: Partial<Result> = {}) {
  const result: Result = {
    sessionId: 'session-1',
    name: 'レポート作成',
    status: 'FINALIZED',
    elapsedSeconds: 1800,
    workSeconds: 1500,
    distractedSeconds: 180,
    uncertainSeconds: 120,
    earnedSeconds: 300,
    usedSeconds: 60,
    discardedSeconds: 0,
    rewardStatus,
    ...overrides,
  };

  return renderToStaticMarkup(createElement(FeedbackPage, { result, mode: 'local-monitor' }));
}

describe('FeedbackPage reward card', () => {
  it('shows a server-confirmed reward in local-monitor mode', () => {
    const markup = renderFeedback('granted', { rewardPolicyVersion: 2, rewardGrantStopped: true });

    expect(markup).toContain('+5分');
    expect(markup).toContain('付与済み');
    expect(markup).toContain('適用ルール v2');
    expect(markup).toContain('利用枠に充当 1分（実利用時間ではありません）');
    expect(markup).toContain('追加付与は停止しています');
  });

  it('distinguishes a confirmed zero reward from a missing amount', () => {
    const markup = renderFeedback('ineligible', { earnedSeconds: 0 });

    expect(markup).toContain('0秒');
    expect(markup).toContain('付与対象外');
  });

  it('does not show zero as a confirmed amount while pending', () => {
    const markup = renderFeedback('pending', { earnedSeconds: 0 });

    expect(markup).not.toContain('+0秒');
    expect(markup).toContain('ログ確認中');
    expect(markup).toContain('金額は確定表示しません');
  });

  it.each([
    ['queued', '残高への反映待ち'],
    ['granted', '付与済み'],
    ['ineligible', '付与対象外'],
    ['unavailable', '未取得'],
  ] as const)('localizes the %s status', (status, label) => {
    expect(renderFeedback(status)).toContain(label);
  });
});
