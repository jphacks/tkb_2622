import { DemoBridge } from './demo';
import { createWailsBridge } from './wails';
import type { DesktopBridge, Platform } from './types';

export const isNative = () => 'go' in window;
export function previewPlatform(): Platform {
  return new URLSearchParams(window.location.search).get('platform') === 'windows' ? 'windows' : 'macos';
}
export async function createBridge(): Promise<DesktopBridge> {
  if (isNative()) return createWailsBridge();
  return new DemoBridge(previewPlatform(), localStorage);
}
