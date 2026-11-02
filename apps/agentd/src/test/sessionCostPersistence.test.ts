import { test } from 'node:test';
import * as assert from 'node:assert';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import { SessionIndex } from '../sessions/SessionIndex.js';

test('SessionIndex: extractSessionMetadata correctly extracts usage, model, thinking, and cost', async (t) => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'agentd-cost-test-'));
  const sessionFile = path.join(tmpDir, 'test-session.jsonl');

  t.after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  const lines = [
    JSON.stringify({ type: 'session', id: 'session-1', cwd: '/test' }),
    JSON.stringify({ type: 'model_change', modelId: 'claude-3-5-sonnet' }),
    JSON.stringify({ type: 'thinking_change', thinkingLevel: 'high' }),
    JSON.stringify({
      type: 'message',
      role: 'assistant',
      content: 'Thinking and acting...',
      usage: {
        cost: 0.015,
        tokens: { total: 4000, input: 3000, output: 1000 },
      },
    }),
    JSON.stringify({
      type: 'message',
      role: 'assistant',
      content: 'Finished task.',
      usage: {
        cost: { total: 0.025 },
        tokens: { total: 6500, input: 5000, output: 1500 },
      },
    }),
  ];

  fs.writeFileSync(sessionFile, lines.join('\n'), 'utf8');

  const index = new SessionIndex();
  const meta = index.extractSessionMetadata(sessionFile);

  assert.strictEqual(meta.model, 'claude-3-5-sonnet');
  assert.strictEqual(meta.thinkingLevel, 'high');
  assert.ok(meta.usage);
  assert.ok((meta.usage as any).byModel);
  assert.strictEqual(Math.abs((meta.usage as any).byModel['claude-3-5-sonnet'].cost - 0.040) < 0.0001, true);
  assert.strictEqual((meta.usage.tokens as any).total, 6500);
});

test('SessionIndex: extractSessionMetadata extracts per-model costs across multiple models', async (t) => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'agentd-multi-cost-test-'));
  const sessionFile = path.join(tmpDir, 'test-session.jsonl');

  t.after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  const lines = [
    JSON.stringify({ type: 'model_change', modelId: 'github-copilot/gpt-6.1-sol' }),
    JSON.stringify({
      type: 'message',
      role: 'assistant',
      usage: { cost: 46.818, tokens: { total: 100000000 } },
    }),
    JSON.stringify({ type: 'model_change', modelId: 'github-copilot/claude-haiku-5-5' }),
    JSON.stringify({
      type: 'message',
      role: 'assistant',
      usage: { cost: 27.539, tokens: { total: 356000000 } },
    }),
    JSON.stringify({
      type: 'compaction',
      usage: { cost: 1.183, tokens: { total: 43000000 } },
    }),
  ];

  fs.writeFileSync(sessionFile, lines.join('\n'), 'utf8');

  const index = new SessionIndex();
  const meta = index.extractSessionMetadata(sessionFile);

  assert.ok(meta.usage);
  const byModel = (meta.usage as any).byModel;
  assert.ok(byModel);
  assert.strictEqual(Math.abs(byModel['github-copilot/gpt-6.1-sol'].cost - 46.818) < 0.001, true);
  assert.strictEqual(Math.abs(byModel['github-copilot/claude-haiku-5-5'].cost - 27.539) < 0.001, true);
  assert.strictEqual(Math.abs(byModel['Tools/summaries'].cost - 1.183) < 0.001, true);
});

test('SessionIndex: tool usage is not attributed to the parent model and missing cost is not zero', (t) => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'agentd-usage-source-'));
  t.after(() => fs.rmSync(tmpDir, { recursive: true, force: true }));
  const sessionFile = path.join(tmpDir, 'session.jsonl');
  fs.writeFileSync(sessionFile, [
    { type: 'model_change', modelId: 'parent-model' },
    { type: 'message', message: { role: 'assistant', model: 'parent-model', usage: { cost: 0.02 } } },
    { type: 'message', message: { role: 'toolResult', usage: { cost: 0.0125 } } },
    { type: 'message', message: { role: 'assistant', model: 'unknown-price-model', usage: { tokens: { total: 15 } } } },
  ].map((entry) => JSON.stringify(entry)).join('\n'));
  const usage = new SessionIndex().extractSessionMetadata(sessionFile).usage as any;
  assert.equal(usage.byModel['parent-model'].cost, 0.02);
  assert.equal(usage.byModel['Tools/summaries'].cost, 0.0125);
  assert.equal(usage.byModel['unknown-price-model'].cost, undefined);
  assert.ok(Math.abs(usage.cost - 0.0325) < 0.000001);
});

test('SessionIndex: getSubagents accumulates nested Pi usage as child sessions grow', async (t) => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'agentd-nested-subagent-'));
  t.after(() => fs.rmSync(tmpDir, { recursive: true, force: true }));
  const subFile = path.join(tmpDir, 'worker.jsonl');
  fs.writeFileSync(subFile, [
    { type: 'session', id: 'worker#nested', parentSession: 'parent.jsonl', cwd: '/test' },
    { type: 'model_change', modelId: 'test-model' },
    { type: 'message', message: { role: 'assistant', content: 'First turn', usage: { cost: { total: 0.0175 } } } },
  ].map((entry) => JSON.stringify(entry)).join('\n') + '\n');
  const index = new SessionIndex({ sessionsDir: tmpDir, cachePath: path.join(tmpDir, 'index.json') });
  const initial = await index.getSubagents('parent', path.join(tmpDir, 'parent.jsonl'));
  assert.strictEqual(initial.length, 1);
  assert.strictEqual(initial[0].cost, 0.0175);
  assert.strictEqual(initial[0].unlinked, true);

  fs.appendFileSync(subFile, [
    { type: 'message', message: { role: 'assistant', content: 'Second turn', usage: { cost: 0.025 } } },
    { type: 'message', message: { role: 'assistant', content: 'Third turn', usage: { cost: { amount: 0.0075 } } } },
    // Legacy wrapper usage must win over the same message usage, not count twice.
    { type: 'message', usage: { cost: 0.01 }, message: { role: 'assistant', usage: { cost: 0.01 } } },
    { type: 'message', message: { role: 'assistant', usage: { cost: { total: 'Infinity' } } } },
    { type: 'message', message: { role: 'assistant', usage: { cost: 'invalid' } } },
    { type: 'message', usage: { tokens: { total: 99 } }, message: { role: 'assistant', usage: { cost: 0.004 } } },
  ].map((entry) => JSON.stringify(entry)).join('\n') + '\n');
  const before = fs.readFileSync(subFile, 'utf8');
  const updated = await index.getSubagents('parent', path.join(tmpDir, 'parent.jsonl'));
  assert.strictEqual(updated.length, 1);
  assert.ok(Math.abs(updated[0].cost! - 0.064) < 0.000001);
  assert.strictEqual(updated[0].model, 'test-model');
  assert.match(updated[0].output, /First turn\nSecond turn\nThird turn/);
  assert.strictEqual(fs.readFileSync(subFile, 'utf8'), before);
  assert.strictEqual((await index.getSubagents('unrelated')).length, 0);
});

test('SessionIndex: getSubagents uses parent Agent identity and persisted child usage', async (t) => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'agentd-agent-identity-'));
  const sessionsDir = path.join(tmpDir, 'sessions');
  fs.mkdirSync(sessionsDir, { recursive: true });
  t.after(() => fs.rmSync(tmpDir, { recursive: true, force: true }));
  const parentFile = path.join(sessionsDir, 'parent.jsonl');
  const childFile = path.join(sessionsDir, 'unrelated-child-uuid.jsonl');
  const agentId = '1f84d18e-7a93-42c';
  fs.writeFileSync(parentFile, [
    { type: 'session', id: 'parent', cwd: '/test' },
    { type: 'message', message: { role: 'toolResult', toolName: 'Agent', toolCallId: 'call-agent', details: {
      agentId, modelName: 'parent-requested-model', cost: 0.01, status: 'running', subagentType: 'codebase-analyzer', description: 'Inspect code',
    } } },
    { type: 'message', message: { role: 'toolResult', toolName: 'Agent', toolCallId: 'call-agent', details: {
      agentId, modelName: 'parent-requested-model', cost: 0.04, status: 'completed', subagentType: 'codebase-analyzer', description: 'Inspect code',
    } } },
  ].map((entry) => JSON.stringify(entry)).join('\n') + '\n');
  fs.writeFileSync(childFile, [
    { type: 'session', id: 'child-jsonl-uuid', parentSession: parentFile, cwd: '/test' },
    { type: 'session_info', name: `codebase-analyzer#${agentId.slice(0, 8)}` },
    { type: 'model_change', modelId: 'requested-model' },
    { type: 'message', message: { role: 'assistant', model: 'gpt-6 luna', content: 'Finished', usage: { cost: 0.025 } } },
  ].map((entry) => JSON.stringify(entry)).join('\n') + '\n');
  const index = new SessionIndex({ sessionsDir, cachePath: path.join(tmpDir, 'cache.json') });
  const agents = await index.getSubagents('parent', parentFile);
  assert.equal(agents.length, 1);
  assert.equal(agents[0].id, agentId);
  assert.equal(agents[0].name, 'Inspect code');
  assert.equal(agents[0].description, 'Inspect code');
  assert.equal(agents[0].toolCallId, 'call-agent');
  assert.equal(agents[0].model, 'gpt-6 luna');
  assert.equal(agents[0].cost, 0.025);
  assert.equal(agents[0].status, 'completed');
});

test('SessionIndex: getSubagents returns parent-only Agent results and leaves missing costs undefined', async (t) => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'agentd-agent-foreground-'));
  const sessionsDir = path.join(tmpDir, 'sessions');
  fs.mkdirSync(sessionsDir, { recursive: true });
  t.after(() => fs.rmSync(tmpDir, { recursive: true, force: true }));
  const parentFile = path.join(sessionsDir, 'parent.jsonl');
  fs.writeFileSync(parentFile, [
    { type: 'session', id: 'parent', cwd: '/test' },
    { type: 'message', message: { role: 'toolResult', toolName: 'Agent', toolCallId: 'foreground-call', details: {
      agentId: 'foreground-agent-id', modelName: 'gpt-6 luna', cost: 0.01, status: 'running', subagentType: 'researcher',
    } } },
    { type: 'message', message: { role: 'toolResult', toolName: 'Agent', toolCallId: 'foreground-call', details: {
      agentId: 'foreground-agent-id', modelName: 'gpt-6 luna', cost: 0.025, status: 'completed', subagentType: 'researcher',
    } } },
    { type: 'message', message: { role: 'toolResult', toolName: 'Agent', toolCallId: 'foreground-call', details: {
      agentId: 'foreground-agent-id', status: 'completed', subagentType: 'researcher',
    } } },
    { type: 'message', message: { role: 'toolResult', toolName: 'Agent', toolCallId: 'missing-cost-call', details: {
      agentId: 'missing-cost-agent', modelName: 'gpt-6 luna', status: 'running', subagentType: 'researcher',
    } } },
  ].map((entry) => JSON.stringify(entry)).join('\n') + '\n');
  const index = new SessionIndex({ sessionsDir, cachePath: path.join(tmpDir, 'cache.json') });
  const agents = await index.getSubagents('parent');
  assert.equal(agents.length, 2);
  assert.equal(agents[0].id, 'foreground-agent-id');
  assert.equal(agents[0].toolCallId, 'foreground-call');
  assert.equal(agents[0].model, undefined);
  assert.equal(agents[0].cost, undefined);
  assert.equal(agents[1].cost, undefined);
  assert.equal(agents[1].model, undefined);
  assert.equal(agents[1].status, 'running');
});

test('SessionIndex: getSubagents avoids ambiguous prefixes and unrelated parent sessions', async (t) => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'agentd-agent-ambiguity-'));
  const sessionsDir = path.join(tmpDir, 'sessions');
  fs.mkdirSync(sessionsDir, { recursive: true });
  t.after(() => fs.rmSync(tmpDir, { recursive: true, force: true }));
  const parentFile = path.join(sessionsDir, 'parent.jsonl');
  const childFile = path.join(sessionsDir, 'child.jsonl');
  const unrelatedFile = path.join(sessionsDir, 'unrelated-child.jsonl');
  fs.writeFileSync(parentFile, [
    { type: 'session', id: 'parent', cwd: '/test' },
    ...['1f84d18e-agent-a', '1f84d18e-agent-b'].map((agentId) => ({
      type: 'message', message: { role: 'toolResult', toolName: 'Agent', toolCallId: `call-${agentId}`, details: {
        agentId, modelName: 'parent-model', cost: 0.01, status: 'completed', subagentType: 'analyzer',
      } },
    })),
  ].map((entry) => JSON.stringify(entry)).join('\n') + '\n');
  fs.writeFileSync(childFile, [
    { type: 'session', id: 'child-session', parentSession: parentFile, cwd: '/test' },
    { type: 'session_info', name: 'analyzer#1f84d18e' },
  ].map((entry) => JSON.stringify(entry)).join('\n') + '\n');
  fs.writeFileSync(unrelatedFile, JSON.stringify({
    type: 'session', id: 'unrelated-child', parentSession: path.join(sessionsDir, 'other', 'parent.jsonl'), cwd: '/test',
  }) + '\n');
  const index = new SessionIndex({ sessionsDir, cachePath: path.join(tmpDir, 'cache.json') });
  const agents = await index.getSubagents('parent', parentFile);
  assert.deepEqual(agents.map((agent) => agent.id).sort(), ['1f84d18e-agent-a', '1f84d18e-agent-b', 'child-session']);
  assert.equal(agents.find((agent) => agent.id === 'child-session')?.model, undefined);
  assert.equal(agents.find((agent) => agent.id === 'child-session')?.unlinked, true);
  assert.ok(agents.filter((agent) => agent.id !== 'child-session').every((agent) => !agent.unlinked));
  assert.equal((await index.getSubagents('parent')).some((agent) => agent.id === 'unrelated-child'), false);
});

test('SessionIndex: notification tool-call identity updates the actual agent and child', async (t) => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'agentd-agent-notification-'));
  t.after(() => fs.rmSync(tmpDir, { recursive: true, force: true }));
  const parentFile = path.join(tmpDir, 'parent.jsonl');
  const childFile = path.join(tmpDir, 'child.jsonl');
  const agentId = 'c44c9b4f-81e3-482';
  fs.writeFileSync(parentFile, [
    { type: 'session', id: 'parent', cwd: '/repo' },
    { type: 'message', message: { role: 'toolResult', toolName: 'Agent', toolCallId: 'call-agent', details: {
      agentId, status: 'background', subagentType: 'reviewer', description: 'Review pending cost changes',
    } } },
    { type: 'custom_message', customType: 'subagent-notification', content: '<task-notification><task-id>different-task-id</task-id><tool-use-id>call-agent</tool-use-id><status>Done</status><summary>Agent finished</summary></task-notification>' },
  ].map((entry) => JSON.stringify(entry)).join('\n') + '\n');
  fs.writeFileSync(childFile, [
    { type: 'session', id: 'child-session', parentSession: parentFile, cwd: '/repo' },
    { type: 'session_info', name: 'reviewer#c44c9b4f' },
    { type: 'model_change', modelId: 'actual-model' },
    { type: 'message', message: { role: 'assistant', content: 'Result preview is not a name', usage: { cost: { total: 0.0175 } } } },
  ].map((entry) => JSON.stringify(entry)).join('\n') + '\n');
  const index = new SessionIndex({ sessionsDir: tmpDir, cachePath: path.join(tmpDir, 'cache.json') });
  const agents = await index.getSubagents('parent', parentFile);
  assert.equal(agents.length, 1);
  assert.equal(agents[0].id, agentId);
  assert.equal(agents[0].sessionId, 'child-session');
  assert.equal(agents[0].toolCallId, 'call-agent');
  assert.equal(agents[0].name, 'Review pending cost changes');
  assert.equal(agents[0].description, 'Review pending cost changes');
  assert.equal(agents[0].model, 'actual-model');
  assert.equal(agents[0].cost, 0.0175);
  assert.equal(agents[0].status, 'completed');
});

test('SessionIndex: relative parent paths do not collide by basename', async (t) => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'agentd-relative-parents-'));
  t.after(() => fs.rmSync(tmpDir, { recursive: true, force: true }));
  for (const group of ['a', 'b']) {
    const dir = path.join(tmpDir, group);
    fs.mkdirSync(dir);
    fs.writeFileSync(path.join(dir, 'parent.jsonl'), JSON.stringify({ type: 'session', id: `parent-${group}`, cwd: '/repo' }) + '\n');
    fs.writeFileSync(path.join(dir, 'child.jsonl'), [
      { type: 'session', id: `child-${group}`, parentSession: 'parent.jsonl', cwd: '/repo' },
      { type: 'session_info', name: `reviewer#${group}` },
    ].map((entry) => JSON.stringify(entry)).join('\n') + '\n');
  }
  const index = new SessionIndex({ sessionsDir: tmpDir, cachePath: path.join(tmpDir, 'cache.json') });
  const agents = await index.getSubagents('parent-a', path.join(tmpDir, 'a', 'parent.jsonl'));
  assert.deepEqual(agents.map((agent) => agent.id), ['child-a']);
});

test('SessionIndex: getSubagents includes persisted subagents in temporary worktrees', async (t) => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'agentd-worktree-subagent-'));
  const sessionsDir = path.join(tmpDir, 'sessions');
  const worktreeCwd = path.join(tmpDir, 'worktree');
  fs.mkdirSync(sessionsDir, { recursive: true });
  fs.mkdirSync(worktreeCwd, { recursive: true });
  t.after(() => fs.rmSync(tmpDir, { recursive: true, force: true }));

  const parentFile = path.join(sessionsDir, 'parent.jsonl');
  const childFile = path.join(sessionsDir, 'child.jsonl');
  fs.writeFileSync(childFile, [
    { type: 'session', id: 'worker#abc12345', parentSession: parentFile, cwd: worktreeCwd },
    { type: 'session_info', name: 'reviewer#abc12345' },
    { type: 'model_change', modelId: 'test-model' },
    { type: 'message', message: { role: 'assistant', content: 'Done', usage: { cost: { total: 0.042 } } } },
  ].map((entry) => JSON.stringify(entry)).join('\n') + '\n');

  const index = new SessionIndex({
    sessionsDir,
    cachePath: path.join(tmpDir, 'cache.json'),
  });
  const subagents = await index.getSubagents('parent', parentFile);

  assert.strictEqual(subagents.length, 1);
  assert.strictEqual(subagents[0].cost, 0.042);
  assert.ok(!(await index.listSessions()).some((session) => session.id === 'worker#abc12345'));
});

test('SessionIndex: getSubagents parses object and number costs without NaN', async (t) => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'agentd-subagent-test-'));
  const sessionsDir = path.join(tmpDir, 'sessions');
  fs.mkdirSync(sessionsDir, { recursive: true });

  t.after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  const parentBasename = 'main-sess.jsonl';
  const subFile = path.join(sessionsDir, 'worker-1.jsonl');

  const lines = [
    JSON.stringify({
      type: 'session',
      id: 'worker#1',
      parentSession: parentBasename,
      cwd: '/test',
    }),
    JSON.stringify({ type: 'session_info', name: 'worker#1' }),
    JSON.stringify({ type: 'model_change', modelId: 'gpt-6-luna' }),
    JSON.stringify({
      type: 'message',
      role: 'assistant',
      content: 'Subagent output completed.',
      usage: {
        cost: { total: 0.0175 },
      },
    }),
  ];

  fs.writeFileSync(subFile, lines.join('\n'), 'utf8');

  const index = new SessionIndex({
    sessionsDir,
    cachePath: path.join(tmpDir, 'cache.json'),
  });
  const subagents = await index.getSubagents('main-sess', path.join(sessionsDir, parentBasename));

  assert.strictEqual(subagents.length, 1);
  assert.strictEqual(subagents[0].id, 'worker#1');
  assert.strictEqual(subagents[0].model, 'gpt-6-luna');
  assert.strictEqual(subagents[0].cost, 0.0175);
  assert.strictEqual(Number.isNaN(subagents[0].cost), false);
});
