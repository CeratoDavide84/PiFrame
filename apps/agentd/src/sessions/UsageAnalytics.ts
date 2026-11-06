import * as fs from 'node:fs';
import * as readline from 'node:readline';
import type { SessionSummary } from './SessionIndex.js';

type Bucket = { date: string; model: string; cost: number; costCount: number; tokens: number; tokenCount: number; messages: number; tools: Record<string, number> };
const numeric = (value: unknown): number | undefined => typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : undefined;

/** Read each persisted record once. No account or provider billing data is inferred. */
export async function collectUsage(sessions: SessionSummary[], now = new Date()) {
  const end = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  const start = new Date(end.getTime() - 29 * 86400000).toISOString().slice(0, 10);
  const endDate = end.toISOString().slice(0, 10);
  let unreadable = 0;
  let undated = 0;
  const results: Array<{ id: string; name: string; isSubsession: boolean; days: Bucket[] }> = [];
  for (const session of sessions) {
    const buckets = new Map<string, Bucket>();
    try {
      const lines = readline.createInterface({ input: fs.createReadStream(session.sessionFile, { encoding: 'utf8' }), crlfDelay: Infinity });
      let model = '';
      for await (const line of lines) {
        let entry: any;
        try { entry = JSON.parse(line); } catch { continue; }
        if (entry.type === 'model_change') model = entry.modelId || entry.model || model;
        if (entry.type !== 'message' && !entry.role) continue;
        const message = entry.message || entry;
        if (message.role !== 'assistant') continue;
        const stamp = message.timestamp ?? entry.timestamp;
        const date = typeof stamp === 'number' || typeof stamp === 'string' ? new Date(stamp) : null;
        if (!date || !Number.isFinite(date.getTime())) { undated++; continue; }
        const day = date.toISOString().slice(0, 10);
        if (day < start || day > endDate) continue;
        const name = message.model || entry.model || model || 'Unknown';
        const key = `${day}\u0000${name}`;
        let bucket = buckets.get(key);
        if (!bucket) { bucket = { date: day, model: name, cost: 0, costCount: 0, tokens: 0, tokenCount: 0, messages: 0, tools: {} }; buckets.set(key, bucket); }
        bucket.messages++;
        const usage = entry.usage ?? message.usage;
        if (usage && typeof usage === 'object') {
          const cost = numeric(typeof usage.cost === 'object' && usage.cost !== null ? usage.cost.total ?? usage.cost.amount : usage.cost);
          if (cost !== undefined) { bucket.cost += cost; bucket.costCount++; }
          const total = numeric(usage.totalTokens) ?? numeric(usage.tokens?.total) ?? numeric(usage.total);
          const parts = ['input', 'output', 'cacheRead', 'cacheWrite'].reduce((sum, field) => sum + (numeric(usage[field]) ?? numeric(usage.tokens?.[field]) ?? 0), 0);
          if (total !== undefined || ['input', 'output', 'cacheRead', 'cacheWrite'].some(field => numeric(usage[field]) !== undefined || numeric(usage.tokens?.[field]) !== undefined)) {
            bucket.tokens += total ?? parts;
            bucket.tokenCount++;
          }
        }
        if (Array.isArray(message.content)) for (const block of message.content) {
          if (block && ['toolCall', 'tool_call', 'tool_use'].includes(block.type) && typeof block.name === 'string') {
            bucket.tools[block.name] = (bucket.tools[block.name] ?? 0) + 1;
          }
        }
      }
      if (buckets.size) results.push({ id: session.id, name: session.name || session.id, isSubsession: !!session.isSubsession, days: [...buckets.values()] });
    } catch { unreadable++; }
  }
  return { sessions: results, unreadable, undated, start, end: endDate };
}
