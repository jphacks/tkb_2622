export function clock(seconds: number): string {
  return `${Math.floor(seconds / 3600)}:${String(Math.floor(seconds / 60) % 60).padStart(2, '0')}:${String(seconds % 60).padStart(2, '0')}`;
}
export function duration(seconds: number): string {
  if (seconds < 60) return `${seconds}秒`;
  const minutes = Math.floor(seconds / 60);
  return minutes >= 60 ? `${Math.floor(minutes / 60)}時間${minutes % 60}分` : `${minutes}分`;
}

export function plannedDuration(seconds: number): string {
  if (seconds < 60) return `${seconds}秒`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}分`;
  const hours = Math.floor(minutes / 60);
  return minutes % 60 === 0 ? `${hours}時間` : `${hours}時間${minutes % 60}分`;
}

export function minimumDuration(seconds: number): string {
  if (seconds < 60) return `${seconds}秒`;
  return `${Math.floor(seconds / 60)}分`;
}
