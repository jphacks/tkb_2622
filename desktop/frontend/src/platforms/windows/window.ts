interface WindowRuntime {
  WindowGetSize(): Promise<{ w: number; h: number }>;
  WindowSetSize(width: number, height: number): void;
  WindowCenter(): void;
}

let queue: Promise<void> = Promise.resolve();
let frame: { width: number; height: number } | null = null;

// WailsのWindowSetSizeはWindowsではタイトルバーと枠を含む外寸になるため，
// 画面（WebView）が指定の大きさになるよう枠の分を足す．
// 大きさを変えても左上の位置は動かないので，作業領域（タスクバーを除く）に収めてから中央へ移す．
// 画面の切り替えで続けて呼ばれても混ざらないよう，1件ずつ順に処理する．
export function setWindowsContentSize(runtime: WindowRuntime, width: number, height: number) {
  queue = queue.then(() => resizeAndCenter(runtime, width, height)).catch(() => undefined);
  return queue;
}

async function resizeAndCenter(runtime: WindowRuntime, width: number, height: number) {
  if (!frame) {
    // 枠の太さは変わらないため，ウィンドウが落ち着いている最初の呼び出しで1回だけ測る．
    const outer = await runtime.WindowGetSize();
    frame = { width: Math.max(0, outer.w - window.innerWidth), height: Math.max(0, outer.h - window.innerHeight) };
  }
  const targetWidth = Math.min(width + frame.width, window.screen.availWidth);
  const targetHeight = Math.min(height + frame.height, window.screen.availHeight);
  runtime.WindowSetSize(targetWidth, targetHeight);
  // WailsはSetSizeとCenterを別々のgoroutineで処理し順序を保証しないため，大きさの反映を待ってから中央へ移す．
  for (let attempt = 0; attempt < 20; attempt++) {
    const current = await runtime.WindowGetSize();
    if (Math.abs(current.w - targetWidth) <= 1 && Math.abs(current.h - targetHeight) <= 1) break;
    await new Promise(resolve => setTimeout(resolve, 25));
  }
  runtime.WindowCenter();
}
