import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { collectUsage } from '../sessions/UsageAnalytics.js';
import type { SessionSummary } from '../sessions/SessionIndex.js';

test('usage analytics aggregates dated records by session and model without inventing costs', async (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'piframe-analytics-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const file = path.join(dir, 'session.jsonl');
  fs.writeFileSync(file, [
    { type: 'message', timestamp: '2026-11-06T10:00:00Z', message: { role: 'assistant', model: 'a', usage: { input: 20, output: 10, cost: { total: 0.2 } }, content: [{ type: 'toolCall', name: 'read' }] } },
    { type: 'message', timestamp: '2026-11-06T11:00:00Z', message: { role: 'assistant', model: 'a', usage: { input: 5 }, content: [] } },
    { type: 'message', timestamp: '2026-10-01T00:00:00Z', message: { role: 'assistant', model: 'a', usage: { cost: 99 } } },
    { type: 'message', message: { role: 'assistant', usage: { cost: 4 } } },
    { type: 'message', timestamp: '2026-11-06T10:00:00Z', message: { role: 'user', content: 'hi' } },
  ].map(x => JSON.stringify(x)).join('\n'));
  const session = { id: 's', name: 'Test', sessionFile: file } as SessionSummary;
  const result = await collectUsage([session, { ...session, id: 'missing', sessionFile: path.join(dir, 'missing') }], new Date('2026-11-06T13:00:00Z'));
  assert.equal(result.unreadable, 1);
  assert.equal(result.undated, 1);
  assert.equal(result.sessions.length, 1);
  assert.deepEqual(result.sessions[0].days, [{ date: '2026-11-06', model: 'a', cost: 0.2, costCount: 1, tokens: 35, tokenCount: 2, messages: 2, tools: { read: 1 } }]);
});
