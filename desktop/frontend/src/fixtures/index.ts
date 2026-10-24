import data from '../../../fixtures/scenarios.json';
import type { Classification, Snapshot, Task } from '../bridge/types';

export interface Scenario {
  id: string; label: string; status: string; elapsedSeconds: number;
  evaluation: 'pending' | 'complete' | 'failed'; sync: Snapshot['sync'];
  permission: Snapshot['permission']; online: boolean; balanceSeconds: number | null;
}

// Goとブラウザのデモが，同じシナリオ定義を読み込む．
export const scenarios = data.scenarios as Scenario[];
export const defaultTask: Task = data.task;
export const defaultTasks: Task[] = data.tasks;
export const defaultClassifications: Classification[] = data.classifications as Classification[];
export const taskPurposes = new Map(data.tasks.map(task => [task.id, task.purpose]));
