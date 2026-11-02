import { DiaryEntry } from '../model/Domain';

/** Explicit allowlist: no auth session, API key, avatar or device preferences. */
export function exportDiaryJson(entries: DiaryEntry[]): string {
  return JSON.stringify({ schemaVersion: 1, app: 'MILO', exportedAt: new Date().toISOString(), entries: entries }, null, 2);
}

export function exportDiaryMarkdown(entries: DiaryEntry[]): string {
  const lines: string[] = ['# MILO · 我的情绪日记', '', `共 ${entries.length} 篇`, ''];
  for (let i = 0; i < entries.length; i += 1) {
    const entry = entries[i];
    lines.push(`## ${new Date(entry.createdAt).toLocaleString()}`, '',
      `情绪：${entry.mood.labels.join('、')}（${entry.mood.valence}）`,
      `时间：${entry.timeMark ?? '此刻'}`, '', entry.diary ?? entry.note ?? '', '');
    if (entry.transcript !== undefined && entry.transcript.length > 0) {
      lines.push('### 对话记录', '');
      for (let j = 0; j < entry.transcript.length; j += 1) {
        const message = entry.transcript[j];
        lines.push(`${message.role === 'user' ? '我' : 'MILO'}：${message.text}`, '');
      }
    }
    lines.push('---', '');
  }
  return lines.join('\n');
}
