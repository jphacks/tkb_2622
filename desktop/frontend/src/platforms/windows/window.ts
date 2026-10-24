interface WindowRuntime {
  WindowGetSize(): Promise<{ w: number; h: number }>;
  WindowSetSize(width: number, height: number): void;
}

// WailsのWindowSetSizeはWindowsではタイトルバーと枠を含む外寸になるため，
// 画面（WebView）が指定の大きさになるよう枠の分を足す．
export async function setWindowsContentSize(runtime: WindowRuntime, width: number, height: number) {
  const outer = await runtime.WindowGetSize();
  const frameWidth = Math.max(0, outer.w - window.innerWidth);
  const frameHeight = Math.max(0, outer.h - window.innerHeight);
  runtime.WindowSetSize(width + frameWidth, height + frameHeight);
}
