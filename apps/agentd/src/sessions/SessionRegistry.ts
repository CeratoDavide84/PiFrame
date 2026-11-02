import * as fs from 'node:fs';
import * as path from 'node:path';
import { ulid } from 'ulid';
import { Session } from './Session.js';
import { SessionIndex, type SessionSummary } from './SessionIndex.js';
import { WorkerSupervisor } from './WorkerSupervisor.js';
import type { ConnectionManager } from '../server/wsServer.js';
import type { Connection } from '../server/connection.js';
import type { PiCapabilities } from '../pi/piCommands.js';
import type { PcpSnapshot, PcpSnapshotPayload } from '@piframe/pcp-ts';
import { hasInteractivePiInCwd } from './PiTerminalDetector.js';
import { writeContextPolicy, deleteContextPolicy } from '../pi/contextPolicy.js';

const SESSION_SUMMARY_FIELDS: (keyof SessionSummary)[] = [
  'id', 'name', 'cwd', 'gitRoot', 'sessionFile', 'createdAt', 'lastActivityAt',
  'sizeBytes', 'messageCount', 'lastMessagePreview', 'isActive', 'parentSession',
  'isSubsession', 'isProvisional'
];

function sameSessionSummaries(a: SessionSummary[], b: SessionSummary[]): boolean {
  return a.length === b.length && a.every((summary, index) =>
    SESSION_SUMMARY_FIELDS.every((field) => summary[field] === b[index]?.[field]));
}

export interface SessionRegistryOptions {
  piExecutablePath: string;
  capabilities: PiCapabilities;
  workerIdleTimeoutMs: number;
  connectionManager: ConnectionManager;
  sessionIndex?: SessionIndex;
  checkTerminalOwner?: (cwd: string, sessionFile?: string | null, sessionId?: string) => Promise<boolean | null>;
}

export class SessionRegistry {
  private sessions = new Map<string, Session>();
  private index: SessionIndex;
  private indexRefresh?: Promise<void>;
  private indexRefreshRequested = false;
  private indexRetry?: NodeJS.Timeout;
  private indexRetryDelayMs = 2000;
  private pendingSessionNames = new Map<string, { file: string; name: string }>();
  private closing = false;
  private supervisor: WorkerSupervisor;
  private connectionManager: ConnectionManager;
  private piExecutablePath: string;
  private checkTerminalOwner: (cwd: string, sessionFile?: string | null, sessionId?: string) => Promise<boolean | null>;

  constructor(opts: SessionRegistryOptions) {
    this.index = opts.sessionIndex || new SessionIndex();
    this.connectionManager = opts.connectionManager;
    this.piExecutablePath = opts.piExecutablePath;
    this.checkTerminalOwner = opts.checkTerminalOwner || hasInteractivePiInCwd;
    this.supervisor = new WorkerSupervisor({
      piExecutablePath: opts.piExecutablePath,
      capabilities: opts.capabilities,
      defaultIdleTimeoutMs: opts.workerIdleTimeoutMs,
      checkTerminalOwner: this.checkTerminalOwner
    });
  }

  public getSupervisor(): WorkerSupervisor {
    return this.supervisor;
  }

  public getSession(id: string): Session | undefined {
    return this.sessions.get(id);
  }

  public getAllSessions(): Session[] {
    return Array.from(this.sessions.values());
  }

  public getIndex(): SessionIndex {
    return this.index;
  }

  public getPiExecutablePath(): string {
    return this.piExecutablePath;
  }

  public async listSessions(query?: string, limit = 50, includeSubsessions = false): Promise<SessionSummary[]> {
    const activeIds = new Set(this.getAllSessions().filter((s) => !s.readOnly).map((s) => s.id));
    let sessions: SessionSummary[];
    let fastScan: Promise<{ sessions: SessionSummary[]; needsRefresh: boolean }> | undefined;
    let refreshFast = false;
    let needsRefresh = false;
    if (typeof this.index.getCachedSnapshot === 'function') {
      sessions = this.index.getCachedSnapshot(activeIds);
      if (sessions.length) {
        refreshFast = true;
      } else {
        fastScan = this.index.scanFast(activeIds);
        let timer: NodeJS.Timeout | undefined;
        const fastResult = await Promise.race([
          fastScan,
          new Promise<undefined>((resolve) => {
            timer = setTimeout(() => resolve(undefined), 250);
            timer.unref();
          })
        ]);
        if (timer) clearTimeout(timer);
        if (fastResult) {
          sessions = fastResult.sessions;
          needsRefresh = fastResult.needsRefresh;
          fastScan = undefined;
        } else {
          refreshFast = true;
        }
      }
    } else {
      const fastResult = await this.index.scanFast(activeIds);
      sessions = fastResult.sessions;
      needsRefresh = fastResult.needsRefresh;
      fastScan = undefined;
    }

    const visible = this.selectSessionList(sessions, query, limit, includeSubsessions);
    if (refreshFast) this.refreshFastIndex(activeIds, visible, query, limit, includeSubsessions, fastScan);
    if (needsRefresh) this.refreshIndex();
    return visible;
  }

  private selectSessionList(
    sessions: SessionSummary[],
    query?: string,
    limit = 50,
    includeSubsessions = false
  ): SessionSummary[] {
    const merged = new Map(sessions.map((s) => [s.id, s]));
    for (const session of this.sessions.values()) {
      merged.set(session.id, {
        ...merged.get(session.id),
        ...session.getSessionMeta(),
        sessionFile: session.sessionFile || '',
        sizeBytes: merged.get(session.id)?.sizeBytes || 0,
        messageCount: session.entries.length,
        isActive: !session.readOnly
      } as SessionSummary);
    }
    const q = query?.trim().toLowerCase();
    return Array.from(merged.values())
      .filter((s) => includeSubsessions || !s.isSubsession)
      .filter((s) => !q || [s.id, s.name, s.cwd, s.lastMessagePreview].some((value) => value?.toLowerCase().includes(q)))
      .sort((a, b) => b.lastActivityAt - a.lastActivityAt)
      .slice(0, Math.max(0, Math.min(Number(limit) || 50, 1000)));
  }

  private refreshFastIndex(
    activeSessionIds: Set<string>,
    previous: SessionSummary[],
    query: string | undefined,
    limit: number,
    includeSubsessions: boolean,
    scan?: Promise<{ sessions: SessionSummary[]; needsRefresh: boolean }>
  ): void {
    if (this.indexRetry || this.closing) return;
    if (this.indexRefresh) {
      this.indexRefreshRequested = true;
      return;
    }
    let needsRefresh = false;
    this.indexRefresh = (scan ?? this.index.scanFast(activeSessionIds)).then((result) => {
      needsRefresh = result.needsRefresh;
      const updated = this.selectSessionList(result.sessions, query, limit, includeSubsessions);
      if (this.closing || sameSessionSummaries(previous, updated)) return;
      this.connectionManager.broadcast('@daemon', {
        protocol: 1,
        kind: 'event',
        id: `evt_${ulid()}`,
        ts: Date.now(),
        sessionId: '@daemon',
        seq: 0,
        type: 'session.indexChanged',
        payload: { updated: result.sessions }
      } as any);
    }).catch((error) => {
      console.error('Error refreshing fast Pi sessions index:', error);
    }).finally(() => {
      const refreshAgain = this.indexRefreshRequested;
      this.indexRefreshRequested = false;
      this.indexRefresh = undefined;
      if ((needsRefresh || refreshAgain) && !this.closing) this.refreshIndex();
    });
  }

  private refreshIndex(): void {
    if (this.indexRetry || this.closing) return;
    if (this.indexRefresh) {
      this.indexRefreshRequested = true;
      return;
    }
    const revision = this.index.cacheRevision;
    let unstable = false;
    let progressTimer: NodeJS.Timeout | undefined;
    const onProgress = () => {
      if (progressTimer) return;
      progressTimer = setTimeout(() => {
        progressTimer = undefined;
        if (this.closing) return;
        this.connectionManager.broadcast('@daemon', {
          protocol: 1,
          kind: 'event',
          id: `evt_${ulid()}`,
          ts: Date.now(),
          sessionId: '@daemon',
          seq: 0,
          type: 'session.indexChanged',
          payload: { refreshing: true }
        } as any);
      }, 1500);
      progressTimer.unref();
    };
    this.indexRefresh = this.index.scan(new Set(), onProgress).then((sessions) => {
      unstable = this.index.hasUnstableFiles;
      if (this.closing) return;
      let renamed = false;
      for (const [id, pending] of this.pendingSessionNames) {
        const live = this.sessions.get(id);
        if (!live || live.name !== pending.name) {
          this.pendingSessionNames.delete(id);
          continue;
        }
        const summary = sessions.find((item) => item.sessionFile === pending.file);
        if (summary) {
          live.name = summary.name || id;
          this.pendingSessionNames.delete(id);
          renamed = true;
        }
      }
      if (!renamed && this.index.cacheRevision === revision) return;
      const updated = sessions.map((summary) => {
        const live = this.sessions.get(summary.id);
        return live ? {
          ...summary,
          ...live.getSessionMeta(),
          sessionFile: live.sessionFile || '',
          messageCount: live.entries.length,
          isActive: !live.readOnly
        } : summary;
      });
      this.connectionManager.broadcast('@daemon', {
        protocol: 1,
        kind: 'event',
        id: `evt_${ulid()}`,
        ts: Date.now(),
        sessionId: '@daemon',
        seq: 0,
        type: 'session.indexChanged',
        payload: { updated }
      } as any);
    }).catch((error) => {
      console.error('Error refreshing Pi sessions index:', error);
    }).finally(() => {
      if (progressTimer) clearTimeout(progressTimer);
      const refreshAgain = this.indexRefreshRequested;
      this.indexRefreshRequested = false;
      this.indexRefresh = undefined;
      if (unstable && !this.closing) {
        this.indexRetry = setTimeout(() => {
          this.indexRetry = undefined;
          this.refreshIndex();
        }, this.indexRetryDelayMs);
        this.indexRetry.unref();
        this.indexRetryDelayMs = Math.min(this.indexRetryDelayMs * 2, 30_000);
      } else {
        this.indexRetryDelayMs = 2000;
        if (refreshAgain) this.refreshIndex();
      }
    });
  }

  public async getSubagents(sessionId: string): Promise<Array<{
    id: string;
    name: string;
    model?: string;
    cost?: number;
    output: string;
    status: string;
    description?: string;
    toolCallId?: string;
    sessionId?: string;
    unlinked?: boolean;
  }>> {
    const session = this.getSession(sessionId);
    return this.index.getSubagents(sessionId, session?.sessionFile);
  }

  public async createSession(opts: { cwd?: string; name?: string; announce?: boolean }): Promise<Session> {
    const id = `s_${ulid()}`;
    const cwd = opts.cwd || process.env.INIT_CWD || process.cwd();
    const name = opts.name || `Session ${new Date().toLocaleTimeString()}`;

    const session = new Session({
      id,
      name,
      cwd,
      onBroadcast: (event) => {
        this.connectionManager.broadcast(id, event);
      }
    });

    this.sessions.set(id, session);

    if (opts.announce !== false) this.announceSession(session);
    return session;
  }

  private announceSession(session: Session): void {
    this.connectionManager.broadcast('@daemon', {
      protocol: 1,
      kind: 'event',
      id: `evt_${ulid()}`,
      ts: Date.now(),
      sessionId: '@daemon',
      seq: 0,
      type: 'session.indexChanged',
      payload: {
        added: [session.getSessionMeta()]
      }
    } as any);
  }

  private async refreshTerminalOwnership(session: Session): Promise<boolean | null> {
    if (!session.sessionFile) return false;
    const owner = await this.checkTerminalOwner(session.cwd, session.sessionFile, session.id);
    if (owner === false) {
      session.readOnly = false;
      session.readOnlyReason = null;
      session.allowAmbiguousTerminal = false;
    } else if (owner === true) {
      session.readOnly = true;
      session.readOnlyReason = 'terminal';
      session.allowAmbiguousTerminal = false;
    } else if (!session.allowAmbiguousTerminal) {
      session.readOnly = true;
      session.readOnlyReason = 'unknown';
    }
    return owner;
  }

  public async openSession(id: string, cwd?: string): Promise<Session> {
    const existing = this.sessions.get(id);
    if (existing) {
      await this.refreshTerminalOwnership(existing);
      return existing;
    }

    // Try finding in session index
    let fast = await this.index.resolveFast(id);
    if (!fast) {
      const discovery = await this.index.scanFast();
      if (discovery.needsRefresh) this.refreshIndex();
      fast = await this.index.resolveFast(id);
    }
    const summaries = fast ? [] : await this.index.scan();
    const found = fast || summaries.find((s) => s.id === id || (s.sessionFile && (path.basename(s.sessionFile, path.extname(s.sessionFile)) === id || path.basename(s.sessionFile).startsWith(id))));
    if (!found) {
      throw Object.assign(new Error(`Session ${id} not found`), { code: 'SESSION_NOT_FOUND' });
    }

    const session = new Session({
      id,
      name: found?.name || id,
      cwd: cwd || found?.cwd || process.cwd(),
      sessionFile: found?.sessionFile,
      createdAt: found?.createdAt,
      onBroadcast: (event) => {
        this.connectionManager.broadcast(id, event);
      }
    });

    // Pi RPC has no terminal attach API. Protect session files owned by interactive Pi.
    const terminalOwner = await this.refreshTerminalOwnership(session);
    session.entries = this.index.readTranscript(found.sessionFile);
    if (found.sessionFile) {
      const meta = this.index.extractSessionMetadata(found.sessionFile);
      if (meta.usage) session.usage = meta.usage;
      if (meta.model) session.model = meta.model;
      if (meta.thinkingLevel) session.thinkingLevel = meta.thinkingLevel;
    }
    this.sessions.set(id, session);
    if (found.isProvisional && found.sessionFile) {
      this.pendingSessionNames.set(id, { file: found.sessionFile, name: session.name || id });
      if (this.indexRefresh) {
        void this.indexRefresh.then(() => {
          if (this.pendingSessionNames.has(id)) this.refreshIndex();
        });
      } else {
        this.refreshIndex();
      }
    }
    return session;
  }

  public async continueSession(id: string, confirmedAmbiguousOwner = false): Promise<Session> {
    const session = this.sessions.get(id) || await this.openSession(id);
    const owner = await this.checkTerminalOwner(session.cwd, session.sessionFile, session.id);
    if (owner === true) {
      session.readOnly = true;
      session.readOnlyReason = 'terminal';
      throw new Error('An interactive Pi terminal is using this session. Duplicate it instead.');
    }
    if (owner === null && !confirmedAmbiguousOwner) {
      throw new Error('Confirm that this exact session is closed in Pi before continuing.');
    }
    session.allowAmbiguousTerminal = owner === null;
    session.readOnly = false;
    session.readOnlyReason = null;
    return session;
  }

  public async cloneSession(id: string, entryId?: string): Promise<Session> {
    const source = this.sessions.get(id) || await this.openSession(id);
    if (!source.sessionFile) await this.ensureWorkerForSession(id);
    if (!source.sessionFile) throw new Error('Pi has not persisted this session yet');
    if (source.isStreaming) throw new Error('Wait for the active run to settle before duplicating it.');
    if (entryId) {
      const persisted = this.index.readTranscript(source.sessionFile);
      if (!persisted.some((entry) => entry.id === entryId)) {
        const live = source.entries.find((entry) => entry.id === entryId);
        const match = persisted.find((entry) => entry.role === 'user' && live?.timestamp != null && entry.timestamp === live.timestamp);
        if (!match?.id) throw new Error('Fork entry no longer exists on the active branch');
        entryId = String(match.id);
      }
    }
    let clone = await this.createSession({ cwd: source.cwd, name: `${source.name} (copy)`, announce: false });
    clone.forkSourceFile = source.sessionFile;
    clone.contextWindowOverride = source.contextWindowOverride;
    clone.compactionReservePercent = source.compactionReservePercent;
    writeContextPolicy(clone.id, clone);
    try {
      const worker = await this.ensureWorkerForSession(clone.id);
      if (entryId) {
        const response = await worker.send({ command: 'fork', arguments: { entryId } });
        if (response.data?.cancelled) throw new Error('Pi cancelled the fork');
        await this.supervisor.refreshSession(clone, worker);
        const finalId = (await worker.send({ command: 'get_state' })).data?.sessionId;
        if (finalId && finalId !== clone.id) {
          // RPC fork changes Pi's identity before its new file is necessarily persisted.
          this.sessions.delete(clone.id);
          const final = new Session({
            id: finalId, name: clone.name, cwd: clone.cwd, sessionFile: clone.sessionFile,
            onBroadcast: (event) => this.connectionManager.broadcast(finalId, event)
          });
          final.entries = clone.entries;
          final.leafId = clone.leafId;
          final.model = clone.model;
          final.thinkingLevel = clone.thinkingLevel;
          final.contextWindowOverride = clone.contextWindowOverride;
          final.compactionReservePercent = clone.compactionReservePercent;
          writeContextPolicy(finalId, final);
          deleteContextPolicy(clone.id);
          this.supervisor.rekeySession(clone, final);
          await clone.close();
          clone = final;
          this.sessions.set(finalId, final);
        }
      }
      this.announceSession(clone);
      return clone;
    } catch (error) {
      await this.closeWorker(clone.id);
      this.sessions.delete(clone.id);
      deleteContextPolicy(clone.id);
      await clone.close();
      throw error;
    }
  }

  public async attachClient(
    sessionId: string,
    conn: Connection,
    lastSeq: number | null,
    commandId?: string
  ): Promise<void> {
    let session = this.sessions.get(sessionId);
    if (!session) {
      session = await this.openSession(sessionId);
    }

    if (session.sessionFile) {
      await this.refreshTerminalOwnership(session);
      if (session.readOnly || !session.worker) {
        session.entries = this.index.readTranscript(session.sessionFile);
        if (!session.usage || Object.keys(session.usage).length === 0) {
          const meta = this.index.extractSessionMetadata(session.sessionFile);
          if (meta.usage) session.usage = meta.usage;
          if (meta.model && !session.model) session.model = meta.model;
          if (meta.thinkingLevel && !session.thinkingLevel) session.thinkingLevel = meta.thinkingLevel;
        }
      }
      // Without a Pi worker, the session file is the latest source of history.
      if (session.readOnly || !session.worker) lastSeq = null;
    }
    session.attachedClientIds.add(conn.id);
    conn.attachedSessions.add(sessionId);

    const currentSeq = session.journal.currentSeq;
    const minSeq = session.journal.minSeq;

    // Case 1: lastSeq == null -> Full snapshot
    if (lastSeq === null || lastSeq === undefined) {
      const snapshotPayload: PcpSnapshotPayload = session.getSnapshot();
      const snapshotMessage: PcpSnapshot = {
        protocol: 1,
        kind: 'snapshot',
        id: `snp_${ulid()}`,
        ts: Date.now(),
        sessionId,
        seq: currentSeq,
        type: 'session.snapshot',
        payload: snapshotPayload
      };
      conn.send(snapshotMessage);
      return;
    }

    // Case 2: Resume: lastSeq >= minSeq - 1 && lastSeq <= currentSeq
    if (lastSeq >= minSeq - 1 && lastSeq <= currentSeq) {
      conn.send({
        protocol: 1,
        kind: 'ack',
        id: `ack_${ulid()}`,
        ts: Date.now(),
        commandId: commandId || `att_${ulid()}`,
        type: 'command.ack',
        sessionId,
        payload: { state: 'resume' }
      } as any);

      if (lastSeq < currentSeq) {
        const events = session.journal.getRange(lastSeq + 1, currentSeq);
        for (const event of events) {
          conn.send(event);
        }
      }
      return;
    }

    // Case 3: Gap: lastSeq < minSeq - 1
    if (lastSeq < minSeq - 1) {
      const snapshotPayload: PcpSnapshotPayload = session.getSnapshot();
      const snapshotMessage: PcpSnapshot = {
        protocol: 1,
        kind: 'snapshot',
        id: `snp_${ulid()}`,
        ts: Date.now(),
        sessionId,
        seq: currentSeq,
        type: 'session.snapshot',
        payload: snapshotPayload
      };
      conn.send(snapshotMessage);

      conn.send({
        protocol: 1,
        kind: 'event',
        id: `evt_${ulid()}`,
        ts: Date.now(),
        sessionId,
        seq: currentSeq,
        type: 'journal.gap',
        payload: {
          fromSeq: lastSeq,
          toSeq: minSeq
        }
      } as any);
      return;
    }

    // Case 4: Reset: lastSeq > currentSeq (client from another daemon or out of sync)
    const snapshotPayload: PcpSnapshotPayload = session.getSnapshot();
    const snapshotMessage: PcpSnapshot = {
      protocol: 1,
      kind: 'snapshot',
      id: `snp_${ulid()}`,
      ts: Date.now(),
      sessionId,
      seq: currentSeq,
      type: 'session.snapshot',
      payload: snapshotPayload
    };
    conn.send(snapshotMessage);

    conn.send({
      protocol: 1,
      kind: 'event',
      id: `evt_${ulid()}`,
      ts: Date.now(),
      sessionId,
      seq: currentSeq,
      type: 'journal.gap',
      payload: {
        fromSeq: lastSeq,
        toSeq: currentSeq,
        reset: true
      }
    } as any);
  }

  public async detachClient(sessionId: string, conn: Connection): Promise<void> {
    const session = this.sessions.get(sessionId);
    if (session) {
      session.attachedClientIds.delete(conn.id);
      conn.attachedSessions.delete(sessionId);
      session.uiBroker.onClientDisconnected(conn.id);
    }
  }

  public async ensureWorkerForSession(sessionId: string) {
    const session = this.sessions.get(sessionId);
    if (!session) {
      throw new Error(`Session ${sessionId} not found`);
    }
    return this.supervisor.ensureWorker(session);
  }

  public async closeWorker(sessionId: string): Promise<void> {
    await this.supervisor.stopWorker(sessionId);
  }

  public async deleteSession(sessionId: string): Promise<boolean> {
    this.pendingSessionNames.delete(sessionId);
    const session = this.sessions.get(sessionId);
    let sessionFile = session?.sessionFile;
    if (session) {
      await this.closeWorker(sessionId);
      await session.close();
      this.sessions.delete(sessionId);
    }

    deleteContextPolicy(sessionId);
    const removedFile = this.index.removeSession(sessionId);
    if (!sessionFile && removedFile) {
      sessionFile = removedFile;
    }
    if (sessionFile && fs.existsSync(sessionFile)) {
      try {
        fs.unlinkSync(sessionFile);
      } catch (_) {}
    }

    this.connectionManager.broadcastAll({
      protocol: 1,
      kind: 'event',
      id: `evt_${ulid()}`,
      ts: Date.now(),
      sessionId: '@daemon',
      seq: 0,
      type: 'session.indexChanged',
      payload: {
        removed: [sessionId]
      }
    } as any);

    return true;
  }

  public async closeAll(graceMs = 5000): Promise<void> {
    this.closing = true;
    if (this.indexRetry) clearTimeout(this.indexRetry);
    await this.supervisor.stopAll(graceMs);
    await Promise.all(Array.from(this.sessions.values(), (session) => session.close()));
  }
}
