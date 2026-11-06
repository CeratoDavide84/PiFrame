import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import * as readline from 'node:readline';
import { getPiFrameBaseDir } from '../config/config.js';

export function isTemporarySessionCwd(cwd: string, tempDir = os.tmpdir()): boolean {
  const pathApi = path.win32.isAbsolute(cwd) || path.win32.isAbsolute(tempDir) ? path.win32 : path;
  const relative = pathApi.relative(pathApi.resolve(tempDir), pathApi.resolve(cwd));
  return relative === '' || (!relative.startsWith(`..${pathApi.sep}`) && relative !== '..' && !pathApi.isAbsolute(relative));
}

function messageText(message: any): string {
  let text = typeof message.content === 'string' ? message.content :
    (Array.isArray(message.content) ? message.content
      .filter((block: any) => block.type === 'text')
      .map((block: any) => block.text || '').join('') : '');
  if (!text && message.role === 'bashExecution') text = message.command ? `!${message.command}` : (message.output || '');
  if (!text && (message.role === 'branchSummary' || message.role === 'compactionSummary')) text = message.summary || '';
  return text;
}

function parseCost(value: unknown): number | undefined {
  const raw = typeof value === 'object' && value !== null
    ? (value as any).total ?? (value as any).amount
    : value;
  return typeof raw === 'number' && Number.isFinite(raw) && raw >= 0 ? raw : undefined;
}

export interface SessionSummary {
  id: string;
  name?: string;
  cwd: string;
  gitRoot?: string | null;
  sessionFile: string;
  createdAt: number;
  lastActivityAt: number;
  sizeBytes: number;
  messageCount?: number;
  lastMessagePreview?: string;
  isActive: boolean;
  parentSession?: string;
  isSubsession?: boolean;
  isProvisional?: boolean;
}

export class SessionIndex {
  private cachePath: string;
  private sessionsDir: string;
  private cache = new Map<string, { mtime: number; ctime?: number; summary: SessionSummary }>();
  private unstableFiles = false;
  private fastSnapshot = new Map<string, SessionSummary>();
  private fastSnapshotReady = false;
  private fastSnapshotRevision = -1;
  private fastScanVersion = 0;
  private cacheRevisionValue = 0;
  private scanProgressCallbacks = new Set<(cacheRevision: number) => void>();
  private cacheSavePromise: Promise<void> = Promise.resolve();
  private fileRevisionCounter = 0;
  private fileRemovalRevisions = new Map<string, number>();
  private fullScanPromise?: Promise<SessionSummary[]>;
  private fastScanPromise?: Promise<{ sessions: SessionSummary[]; needsRefresh: boolean }>;

  public get cacheRevision(): number {
    return this.cacheRevisionValue;
  }

  public get hasUnstableFiles(): boolean {
    return this.unstableFiles;
  }

  public getCachedSnapshot(activeSessionIds = new Set<string>()): SessionSummary[] {
    const summaries = this.fastSnapshotReady && this.fastSnapshotRevision === this.cacheRevisionValue
      ? [...this.fastSnapshot.values()]
      : [...this.cache.values()].map(({ summary }) => summary);
    return summaries
      .filter((summary) => !isTemporarySessionCwd(summary.cwd) || !!summary.parentSession)
      .map((summary) => ({ ...summary, isActive: activeSessionIds.has(summary.id) }))
      .sort((a, b) => b.lastActivityAt - a.lastActivityAt);
  }

  private bumpCacheRevision(): void {
    const revision = ++this.cacheRevisionValue;
    for (const callback of [...this.scanProgressCallbacks]) {
      try { callback(revision); } catch { /* Progress observers cannot interrupt indexing. */ }
    }
  }

  constructor(opts: { sessionsDir?: string; cachePath?: string } = {}) {
    this.sessionsDir = opts.sessionsDir || process.env.PI_CODING_AGENT_SESSION_DIR ||
      path.join(process.env.PI_CODING_AGENT_DIR || path.join(os.homedir(), '.pi', 'agent'), 'sessions');
    this.cachePath = opts.cachePath || path.join(getPiFrameBaseDir(), 'index.json');
    this.loadCache();
  }

  private loadCache(): void {
    if (fs.existsSync(this.cachePath)) {
      try {
        const raw = fs.readFileSync(this.cachePath, 'utf8');
        const list = JSON.parse(raw);
        for (const item of list) {
          if (item.id && item.mtime && item.summary) {
            this.cache.set(item.id, item);
          }
        }
      } catch {}
    }
  }

  private saveCacheAsync(): Promise<void> {
    const write = this.cacheSavePromise.catch(() => {}).then(async () => {
      while (true) {
        const revision = this.cacheRevisionValue;
        const list = Array.from(this.cache, ([id, value]) => ({ id, ...value }));
        const temp = `${this.cachePath}.tmp.${process.pid}.${Date.now()}.${Math.random().toString(36).slice(2)}`;
        try {
          await fs.promises.mkdir(path.dirname(this.cachePath), { recursive: true });
          await fs.promises.writeFile(temp, JSON.stringify(list, null, 2), 'utf8');
          if (revision !== this.cacheRevisionValue) {
            await fs.promises.unlink(temp).catch(() => {});
            continue;
          }
          await fs.promises.rename(temp, this.cachePath);
          if (revision === this.cacheRevisionValue) return;
        } catch {
          await fs.promises.unlink(temp).catch(() => {});
          return;
        }
      }
    });
    this.cacheSavePromise = write;
    return write;
  }

  private async enumerateSessionFiles(): Promise<Array<{ filePath: string; dirName: string }>> {
    const rootEntries = await fs.promises.readdir(this.sessionsDir, { withFileTypes: true });
    const groups = await this.mapBounded(rootEntries, 32, async (entry) => {
      const fullPath = path.join(this.sessionsDir, entry.name);
      let isDirectory = entry.isDirectory();
      let isFile = entry.isFile();
      if (entry.isSymbolicLink()) {
        try {
          const stat = await fs.promises.stat(fullPath);
          isDirectory = stat.isDirectory();
          isFile = stat.isFile();
        } catch { return []; }
      }
      if (isDirectory) {
        let children: fs.Dirent[];
        try { children = await fs.promises.readdir(fullPath, { withFileTypes: true }); }
        catch (cause) {
          if ((cause as NodeJS.ErrnoException).code === 'ENOENT') return [];
          const error = new Error(`Failed to enumerate session directory: ${fullPath}`, { cause }) as NodeJS.ErrnoException;
          error.code = 'SESSION_DIRECTORY_READ_FAILED';
          throw error;
        }
        return children.filter((child) => child.isFile() || child.isSymbolicLink())
          .map((child) => ({ filePath: path.join(fullPath, child.name), dirName: entry.name }));
      }
      return isFile ? [{ filePath: fullPath, dirName: entry.name }] : [];
    });
    return groups.flat().filter(({ filePath }) => {
      const file = path.basename(filePath);
      return file.endsWith('.json') || file.endsWith('.jsonl');
    });
  }

  private async mapBounded<T, R>(items: T[], concurrency: number, fn: (item: T) => Promise<R>): Promise<R[]> {
    const result = new Array<R>(items.length);
    let next = 0;
    await Promise.all(Array.from({ length: Math.min(concurrency, items.length) }, async () => {
      while (true) {
        const index = next++;
        if (index >= items.length) return;
        result[index] = await fn(items[index]);
      }
    }));
    return result;
  }

  private cacheMatches(value: { mtime: number; ctime?: number; summary: SessionSummary }, stat: fs.Stats): boolean {
    return value.mtime === stat.mtimeMs && value.summary.sizeBytes === stat.size &&
      (value.ctime === undefined || value.ctime === stat.ctimeMs);
  }

  private touchCache(filePath: string, value: { mtime: number; ctime: number; summary: SessionSummary }): void {
    const previous = this.cache.get(filePath);
    if (!previous || previous.mtime !== value.mtime || previous.ctime !== value.ctime || JSON.stringify(previous.summary) !== JSON.stringify(value.summary)) {
      this.cache.set(filePath, value);
      this.bumpCacheRevision();
    }
  }

  /** Scans Pi sessions asynchronously without changing their files. */
  public async scan(
    activeSessionIds = new Set<string>(),
    onProgress?: (cacheRevision: number) => void
  ): Promise<SessionSummary[]> {
    const listener = onProgress ? (revision: number) => onProgress(revision) : undefined;
    if (listener) this.scanProgressCallbacks.add(listener);
    try {
      if (!this.fullScanPromise) {
        this.fullScanPromise = this.scanAuthoritative().finally(() => { this.fullScanPromise = undefined; });
      }
      const summaries = await this.fullScanPromise;
      return summaries.map((summary) => ({ ...summary, isActive: activeSessionIds.has(summary.id) }));
    } finally {
      if (listener) this.scanProgressCallbacks.delete(listener);
    }
  }

  private async scanAuthoritative(): Promise<SessionSummary[]> {
    this.unstableFiles = false;
    const scanRevision = this.fileRevisionCounter;
    let files: Array<{ filePath: string; dirName: string }>;
    try { files = await this.enumerateSessionFiles(); }
    catch (err) {
      if ((err as NodeJS.ErrnoException).code === 'ENOENT') {
        if (this.cache.size) {
          this.cache.clear();
          this.bumpCacheRevision();
          await this.saveCacheAsync();
        }
        this.fastSnapshot.clear();
        this.fastSnapshotReady = true;
        this.fastSnapshotRevision = this.cacheRevisionValue;
        this.fastScanVersion++;
        return [];
      }
      throw err;
    }

    const present = new Set(files.map(({ filePath }) => filePath));
    let changed = false;
    for (const cachedPath of this.cache.keys()) {
      if (!present.has(cachedPath)) {
        this.cache.delete(cachedPath);
        this.bumpCacheRevision();
        this.fastScanVersion++;
        changed = true;
      }
    }
    for (const snapshotPath of this.fastSnapshot.keys()) {
      if (!present.has(snapshotPath)) {
        this.fastSnapshot.delete(snapshotPath);
        this.fastScanVersion++;
      }
    }

    type Candidate = { filePath: string; dirName: string; stat: fs.Stats };
    const candidates = await this.mapBounded(files, 8, async ({ filePath, dirName }): Promise<Candidate | null> => {
      try { return { filePath, dirName, stat: await fs.promises.stat(filePath) }; }
      catch (err) {
        if ((err as NodeJS.ErrnoException).code === 'ENOENT') {
          if (this.cache.delete(filePath)) { this.bumpCacheRevision(); changed = true; }
          this.fastSnapshot.delete(filePath);
          this.fastScanVersion++;
        }
        return null;
      }
    });
    const ordered = candidates.filter((candidate): candidate is Candidate => candidate !== null)
      .sort((a, b) => b.stat.mtimeMs - a.stat.mtimeMs);
    const summaries = await this.mapBounded(ordered, 8, async ({ filePath, dirName, stat: before }) => {
      try {
        const cached = this.cache.get(filePath);
        let summary: SessionSummary | null;
        if (cached && cached.ctime !== undefined && this.cacheMatches(cached, before)) {
          summary = cached.summary;
        } else {
          summary = await this.parseSessionFileAsync(
            path.basename(filePath, path.extname(filePath)), filePath, before, dirName
          );
          const after = await fs.promises.stat(filePath);
          if ((this.fileRemovalRevisions.get(filePath) ?? 0) > scanRevision) return null;
          if (before.mtimeMs !== after.mtimeMs || before.size !== after.size || before.ctimeMs !== after.ctimeMs) {
            this.unstableFiles = true;
            return null;
          }
          if (!summary) return null;
          this.touchCache(filePath, { mtime: after.mtimeMs, ctime: after.ctimeMs, summary });
          changed = true;
        }
        if ((this.fileRemovalRevisions.get(filePath) ?? 0) > scanRevision) return null;
        if (!summary || (isTemporarySessionCwd(summary.cwd) && !summary.parentSession)) return null;
        return summary;
      } catch (err) {
        if ((err as NodeJS.ErrnoException).code === 'ENOENT') {
          if (this.cache.delete(filePath)) { this.bumpCacheRevision(); changed = true; }
          this.fastSnapshot.delete(filePath);
          this.fastScanVersion++;
        }
        return null;
      }
    });

    const existing = await this.mapBounded(summaries.filter((summary): summary is SessionSummary => summary !== null), 8, async (summary) => {
      try { await fs.promises.stat(summary.sessionFile); return summary; }
      catch {
        if (this.cache.delete(summary.sessionFile)) { this.bumpCacheRevision(); changed = true; }
        this.fastSnapshot.delete(summary.sessionFile);
        this.fastScanVersion++;
        return null;
      }
    });
    if (changed) await this.saveCacheAsync();
    return existing.filter((summary): summary is SessionSummary => summary !== null &&
      (this.fileRemovalRevisions.get(summary.sessionFile) ?? 0) <= scanRevision)
      .sort((a, b) => b.lastActivityAt - a.lastActivityAt);
  }

  public async scanFast(activeSessionIds = new Set<string>()): Promise<{ sessions: SessionSummary[]; needsRefresh: boolean }> {
    if (!this.fastScanPromise) {
      this.fastScanPromise = this.scanFastSnapshot().finally(() => { this.fastScanPromise = undefined; });
    }
    const result = await this.fastScanPromise;
    return {
      ...result,
      sessions: result.sessions.map((summary) => ({ ...summary, isActive: activeSessionIds.has(summary.id) }))
    };
  }

  private async scanFastSnapshot(): Promise<{ sessions: SessionSummary[]; needsRefresh: boolean }> {
    const scanVersion = ++this.fastScanVersion;
    const scanRemovalRevision = this.fileRevisionCounter;
    const scanCacheRevision = this.cacheRevisionValue;
    const snapshotAtStart = new Map(this.fastSnapshot);
    let files: Array<{ filePath: string; dirName: string }>;
    try { files = await this.enumerateSessionFiles(); }
    catch (err) {
      if ((err as NodeJS.ErrnoException).code === 'ENOENT') {
        const snapshotChanged = this.fastSnapshot.size !== snapshotAtStart.size ||
          [...snapshotAtStart].some(([filePath, summary]) => this.fastSnapshot.get(filePath) !== summary);
        if (scanVersion !== this.fastScanVersion || this.cacheRevisionValue !== scanCacheRevision || snapshotChanged) {
          return { sessions: this.getCachedSnapshot(), needsRefresh: true };
        }
        if (this.cache.size) {
          this.cache.clear();
          this.bumpCacheRevision();
          const clearRevision = this.cacheRevisionValue;
          await this.saveCacheAsync();
          if (scanVersion !== this.fastScanVersion || this.cacheRevisionValue !== clearRevision) {
            return { sessions: this.getCachedSnapshot(), needsRefresh: true };
          }
        }
        this.fastSnapshot.clear();
        this.fastSnapshotReady = true;
        this.fastSnapshotRevision = this.cacheRevisionValue;
        this.fastScanVersion++;
        return { sessions: [], needsRefresh: false };
      }
      throw err;
    }

    let needsRefresh = false;
    const removedDuringScan = new Set<string>();
    let cacheChangedDuringScan = false;
    const present = new Set(files.map(({ filePath }) => filePath));
    const cacheChangedDuringEnumeration = this.cacheRevisionValue !== scanCacheRevision;
    const snapshotChangedDuringEnumeration = this.fastSnapshot.size !== snapshotAtStart.size ||
      [...snapshotAtStart].some(([filePath, summary]) => this.fastSnapshot.get(filePath) !== summary);
    if (cacheChangedDuringEnumeration || snapshotChangedDuringEnumeration) needsRefresh = true;
    let removedCache = false;
    if (!cacheChangedDuringEnumeration && !snapshotChangedDuringEnumeration) {
      for (const cachedPath of this.cache.keys()) {
        if (!present.has(cachedPath)) {
          this.cache.delete(cachedPath);
          this.bumpCacheRevision();
          removedCache = true;
        }
      }
    } else {
      needsRefresh = true;
    }
    const cacheRevisionAfterPrune = this.cacheRevisionValue;
    if (removedCache) await this.saveCacheAsync();
    const cacheChangedDuringSave = this.cacheRevisionValue !== cacheRevisionAfterPrune;
    if (cacheChangedDuringSave) needsRefresh = true;
    const snapshotCacheRevision = this.cacheRevisionValue;

    const results = await this.mapBounded(files, 32, async ({ filePath, dirName }) => {
      try {
        const stat = await fs.promises.stat(filePath);
        const cached = this.cache.get(filePath);
        if (cached && this.cacheMatches(cached, stat)) {
          if (isTemporarySessionCwd(cached.summary.cwd) && !cached.summary.parentSession) return null;
          if (cached.ctime === undefined) needsRefresh = true;
          return { summary: { ...cached.summary, sizeBytes: stat.size, lastActivityAt: stat.mtimeMs }, stat };
        }
        const provisional = await this.parseSessionFileFast(filePath, stat, dirName);
        if (!provisional) return null;
        needsRefresh = true;
        return { summary: provisional, stat };
      } catch (err) {
        if ((err as NodeJS.ErrnoException).code === 'ENOENT') {
          if (this.cache.delete(filePath)) { this.bumpCacheRevision(); cacheChangedDuringScan = true; }
          removedDuringScan.add(filePath);
        }
        return null;
      }
    });

    const checked = await this.mapBounded(results.filter((item): item is { summary: SessionSummary; stat: fs.Stats } => item !== null), 32, async ({ summary, stat }) => {
      try {
        const current = await fs.promises.stat(summary.sessionFile);
        if (current.mtimeMs !== stat.mtimeMs || current.ctimeMs !== stat.ctimeMs || current.size !== stat.size) needsRefresh = true;
        return summary;
      } catch {
        if (this.cache.delete(summary.sessionFile)) { this.bumpCacheRevision(); cacheChangedDuringScan = true; }
        removedDuringScan.add(summary.sessionFile);
        return null;
      }
    });
    if (cacheChangedDuringScan) await this.saveCacheAsync();
    const sessions = checked.filter((summary): summary is SessionSummary => summary !== null &&
      (this.fileRemovalRevisions.get(summary.sessionFile) ?? 0) <= scanRemovalRevision)
      .sort((a, b) => b.lastActivityAt - a.lastActivityAt);
    if (this.cacheRevisionValue !== snapshotCacheRevision) needsRefresh = true;
    if (scanVersion === this.fastScanVersion && !cacheChangedDuringEnumeration && !cacheChangedDuringSave && !cacheChangedDuringScan && this.cacheRevisionValue === snapshotCacheRevision) {
      const nextSnapshot = new Map(sessions.map((summary) => [summary.sessionFile, summary]));
      for (const [filePath, summary] of this.fastSnapshot) {
        if (snapshotAtStart.get(filePath) !== summary) nextSnapshot.set(filePath, summary);
      }
      for (const filePath of removedDuringScan) nextSnapshot.delete(filePath);
      this.fastSnapshot = nextSnapshot;
      this.fastSnapshotReady = true;
      this.fastSnapshotRevision = snapshotCacheRevision;
    } else {
      needsRefresh = true;
    }
    return { sessions, needsRefresh };
  }

  public findFast(sessionId: string): SessionSummary | undefined {
    return this.findInFastSnapshot(sessionId);
  }

  private findInFastSnapshot(sessionId: string): SessionSummary | undefined {
    const items = [...this.fastSnapshot.values()];
    return items.find((summary) => summary.id === sessionId) || items.find((summary) => {
      const basename = path.basename(summary.sessionFile, path.extname(summary.sessionFile));
      return basename === sessionId || basename.startsWith(sessionId);
    });
  }

  public async resolveFast(sessionId: string): Promise<SessionSummary | undefined> {
    const provisional = this.findInFastSnapshot(sessionId);
    if (!provisional) return undefined;
    const snapshotVersion = this.fastScanVersion;
    const filePath = provisional.sessionFile;
    const removalRevision = this.fileRemovalRevisions.get(filePath) ?? 0;
    try {
      const before = await fs.promises.stat(filePath);
      const cached = this.cache.get(filePath);
      if (cached && cached.ctime !== undefined && this.cacheMatches(cached, before)) {
        if ((this.fileRemovalRevisions.get(filePath) ?? 0) !== removalRevision) return undefined;
        const resolved = { ...cached.summary, isActive: provisional.isActive };
        if (snapshotVersion === this.fastScanVersion) this.fastSnapshot.set(filePath, resolved);
        return resolved;
      }
      const summary = await this.parseSessionFileAsync(
        path.basename(filePath, path.extname(filePath)), filePath, before, path.basename(path.dirname(filePath))
      );
      const after = await fs.promises.stat(filePath);
      if (!summary || (isTemporarySessionCwd(summary.cwd) && !summary.parentSession)) return undefined;
      if (before.mtimeMs !== after.mtimeMs || before.size !== after.size || before.ctimeMs !== after.ctimeMs) {
        return { ...provisional, isProvisional: true };
      }
      if ((this.fileRemovalRevisions.get(filePath) ?? 0) !== removalRevision) return undefined;
      this.touchCache(filePath, { mtime: after.mtimeMs, ctime: after.ctimeMs, summary });
      await this.saveCacheAsync();
      if ((this.fileRemovalRevisions.get(filePath) ?? 0) !== removalRevision) return undefined;
      const resolved = { ...summary, isActive: provisional.isActive };
      if (snapshotVersion === this.fastScanVersion) this.fastSnapshot.set(filePath, resolved);
      return resolved;
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code === 'ENOENT') {
        this.fastSnapshot.delete(filePath);
        this.fastScanVersion++;
        if (this.cache.delete(filePath)) {
          this.bumpCacheRevision();
          await this.saveCacheAsync();
        }
      }
      return undefined;
    }
  }

  public async listSessions(
    activeSessionIds = new Set<string>(),
    query?: string,
    limit: number = 50,
    includeSubsessions = false
  ): Promise<SessionSummary[]> {
    let list = await this.scan(activeSessionIds);

    if (!includeSubsessions) {
      list = list.filter((s) => !s.isSubsession);
    }

    if (query && query.trim().length > 0) {
      const q = query.trim().toLowerCase();
      list = list.filter(
        (s) =>
          s.id.toLowerCase().includes(q) ||
          (s.name && s.name.toLowerCase().includes(q)) ||
          s.cwd.toLowerCase().includes(q) ||
          (s.lastMessagePreview && s.lastMessagePreview.toLowerCase().includes(q))
      );
    }

    return list.slice(0, limit);
  }

  public removeSession(sessionId: string): string | null {
    let deletedPath: string | null = null;
    for (const [filePath, cached] of this.cache.entries()) {
      if (cached.summary.id === sessionId || path.basename(filePath, path.extname(filePath)) === sessionId) {
        deletedPath = filePath;
        break;
      }
    }
    if (!deletedPath) {
      for (const [filePath, summary] of this.fastSnapshot.entries()) {
        if (summary.id === sessionId || path.basename(filePath, path.extname(filePath)) === sessionId) {
          deletedPath = filePath;
          break;
        }
      }
    }
    if (deletedPath) {
      if (this.cache.delete(deletedPath)) this.bumpCacheRevision();
      this.fastSnapshot.delete(deletedPath);
      this.fastScanVersion++;
      this.fileRemovalRevisions.set(deletedPath, ++this.fileRevisionCounter);
      if (fs.existsSync(deletedPath)) {
        try {
          fs.unlinkSync(deletedPath);
        } catch (err) {
          console.error('Failed to unlink session file:', deletedPath, err);
        }
      }
    }
    void this.saveCacheAsync();
    return deletedPath;
  }

  public readTranscript(filePath: string): Array<Record<string, unknown>> {
    const entries: any[] = [];
    for (const line of fs.readFileSync(filePath, 'utf8').split('\n')) {
      try {
        const entry = JSON.parse(line);
        if (entry.type !== 'session') entries.push(entry);
      } catch { /* An active terminal may have an unfinished final line. */ }
    }
    return SessionIndex.projectTranscript(entries);
  }

  public static projectTranscript(entries: any[]): Array<Record<string, unknown>> {
    const byId = new Map(entries.filter((e) => e.id).map((e) => [e.id, e]));
    const branch: any[] = [];
    const visited = new Set<string>();
    let cursor = entries.at(-1);
    while (cursor && cursor.id && !visited.has(cursor.id)) {
      visited.add(cursor.id);
      branch.unshift(cursor);
      cursor = byId.get(cursor.parentId);
    }
    return (branch.length ? branch : entries)
      .filter((entry) => (entry.type === 'message' || entry.role) && (entry.message || entry).role !== 'system')
      .map((entry) => ({ ...(entry.message || entry), id: entry.id }));
  }

  private makeSummary(
    sessionId: string,
    filePath: string,
    stat: fs.Stats,
    cwd: string,
    name: string | undefined,
    parentSession: string | undefined,
    messageCount?: number,
    lastMessagePreview?: string
  ): SessionSummary | null {
    if (isTemporarySessionCwd(cwd) && !parentSession) return null;
    const isSubagentNameOrId =
      Boolean(name && (name.includes('worker#') || /(?:^|_)(?:worker|reviewer|scout|oracle|delegate|researcher|evidence-auditor)#/i.test(name) || /#([0-9a-fA-F]+)/.test(name) || name.startsWith('subagent'))) ||
      Boolean(sessionId && (sessionId.includes('worker#') || /(?:^|_)(?:worker|reviewer|scout|oracle|delegate|researcher|evidence-auditor)#/i.test(sessionId) || sessionId.startsWith('subagent') || filePath.includes('subagent')));
    const summary: SessionSummary = {
      id: sessionId, name, cwd, gitRoot: null, sessionFile: filePath,
      createdAt: stat.birthtimeMs || stat.mtimeMs, lastActivityAt: stat.mtimeMs,
      sizeBytes: stat.size, lastMessagePreview, isActive: false, parentSession,
      isSubsession: Boolean(isSubagentNameOrId || (parentSession && isTemporarySessionCwd(cwd))),
    };
    if (messageCount !== undefined) summary.messageCount = messageCount;
    return summary;
  }

  private async parseSessionFileAsync(
    initialId: string, filePath: string, stat: fs.Stats, _dirName: string
  ): Promise<SessionSummary | null> {
    let sessionId = initialId;
    let cwd = process.cwd();
    let name: string | undefined = sessionId;
    let messageCount = 0;
    let lastMessagePreview: string | undefined;
    let parentSession: string | undefined;
    let firstLine = true;
    let readFailed = false;
    try {
      const stream = fs.createReadStream(filePath, { encoding: 'utf8' });
      const lines = readline.createInterface({ input: stream, crlfDelay: Infinity });
      for await (const line of lines) {
        if (firstLine) {
          firstLine = false;
          try {
            const header = JSON.parse(line);
            if (header.type === 'session') {
              if (header.parentSession) parentSession = header.parentSession;
              if (header.cwd && isTemporarySessionCwd(header.cwd) && !parentSession) {
                lines.close();
                stream.destroy();
                return null;
              }
            }
          } catch { /* Legacy or incomplete headers use the normal parser below. */ }
        }
        if (!line.trim()) continue;
        try {
          const entry = JSON.parse(line);
          if (entry.type === 'session') {
            if (entry.id) sessionId = entry.id;
            if (entry.cwd) cwd = entry.cwd;
            if (entry.parentSession) parentSession = entry.parentSession;
          }
          if (entry.type === 'session_info') name = entry.name;
          if (entry.sessionName) name = entry.sessionName;
          if (entry.type === 'message' || entry.role) {
            const message = entry.message || entry;
            if (message.role === 'system') continue;
            messageCount++;
            const text = messageText(message);
            if (text) lastMessagePreview = text.slice(0, 100);
          }
        } catch {}
      }
    } catch { readFailed = true; }
    if (readFailed) return null;
    return this.makeSummary(sessionId, filePath, stat, cwd, name, parentSession, messageCount, lastMessagePreview);
  }

  private async parseSessionFileFast(filePath: string, stat: fs.Stats, _dirName: string): Promise<SessionSummary | null> {
    let sessionId = path.basename(filePath, path.extname(filePath));
    let cwd = process.cwd();
    let name: string | undefined = sessionId;
    let hasTailTitle = false;
    let parentSession: string | undefined;
    let lastMessagePreview: string | undefined;
    const fd = await fs.promises.open(filePath, 'r');
    try {
      const head = Buffer.alloc(16 * 1024);
      const headRead = await fd.read(head, 0, head.length, 0);
      const headText = head.subarray(0, headRead.bytesRead).toString('utf8');
      const headerEnd = headText.indexOf('\n');
      const headerComplete = headerEnd >= 0 || stat.size <= headRead.bytesRead;
      if (headerComplete) {
        try {
          const header = JSON.parse(headerEnd >= 0 ? headText.slice(0, headerEnd) : headText);
          if (header.type === 'session') {
            if (header.id) sessionId = header.id;
            if (header.cwd) cwd = header.cwd;
            if (header.parentSession) parentSession = header.parentSession;
            if (header.cwd && isTemporarySessionCwd(header.cwd) && !parentSession) return null;
          }
        } catch { /* An incomplete or legacy header uses filename defaults. */ }
      }

      const tailLength = Math.min(64 * 1024, stat.size);
      const tail = Buffer.alloc(tailLength);
      const tailRead = await fd.read(tail, 0, tailLength, Math.max(0, stat.size - tailLength));
      let tailText = tail.subarray(0, tailRead.bytesRead).toString('utf8');
      const startsAtFileBeginning = stat.size <= tailLength;
      if (!startsAtFileBeginning) {
        const firstNewline = tailText.indexOf('\n');
        if (firstNewline < 0) tailText = '';
        else tailText = tailText.slice(firstNewline + 1);
      }
      const lines = tailText.split('\n');
      if (!tailText.endsWith('\n')) lines.pop();
      for (const line of lines) {
        if (!line.trim()) continue;
        try {
          const entry = JSON.parse(line);
          if (entry.type === 'session') {
            if (entry.id) sessionId = entry.id;
            if (entry.cwd) cwd = entry.cwd;
            if (entry.parentSession) parentSession = entry.parentSession;
          }
          if (entry.type === 'session_info') { name = entry.name; hasTailTitle = true; }
          if (entry.sessionName) { name = entry.sessionName; hasTailTitle = true; }
          if (entry.type === 'message' || entry.role) {
            const message = entry.message || entry;
            if (message.role === 'system') continue;
            const text = messageText(message);
            if (text) lastMessagePreview = text.slice(0, 100);
          }
        } catch {}
      }
      if (!hasTailTitle) {
        const cached = this.cache.get(filePath);
        if (cached) name = cached.summary.name;
      }
    } finally { await fd.close(); }
    const freshStat = await fs.promises.stat(filePath);
    return this.makeSummary(sessionId, filePath, freshStat, cwd, name, parentSession, undefined, lastMessagePreview);
  }

  public async getSubagents(parentSessionId: string, parentSessionFile?: string | null): Promise<Array<{
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
    const { sessions: all } = await this.scanFast();
    const resolvedParent = parentSessionFile || all.find((session) =>
      session.id === parentSessionId ||
      path.basename(session.sessionFile) === parentSessionId ||
      path.basename(session.sessionFile, path.extname(session.sessionFile)) === parentSessionId
    )?.sessionFile;
    const isChildOfParent = (child: SessionSummary): boolean => {
      const parent = child.parentSession;
      if (!parent) return false;
      if (parent === parentSessionId) return true;
      if (!resolvedParent) return false;
      const parentPath = path.isAbsolute(parent)
        ? parent
        : path.resolve(path.dirname(child.sessionFile), parent);
      return path.resolve(parentPath) === path.resolve(resolvedParent);
    };
    const children = all.filter(isChildOfParent);

    type Subagent = {
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
    };
    const agentResults = new Map<string, Subagent>();
    if (resolvedParent && fs.existsSync(resolvedParent)) {
      try {
        const lines = readline.createInterface({
          input: fs.createReadStream(resolvedParent, { encoding: 'utf8' }),
          crlfDelay: Infinity,
        });
        for await (const line of lines) {
          try {
            const entry = JSON.parse(line);
            const message = entry.message || entry;
            if (message.role === 'user' ||
                (entry.type === 'custom_message' && entry.customType === 'subagent-notification')) {
              const text = messageText(message);
              const notification = /<task-notification>([\s\S]*?)<\/task-notification>/.exec(text)?.[1];
              if (notification) {
                const id = /<task-id>([^<]+)<\/task-id>/.exec(notification)?.[1]?.trim();
                const status = /<status>([^<]+)<\/status>/.exec(notification)?.[1]?.trim().toLowerCase();
                const toolCallId = /<tool-use-id>([^<]+)<\/tool-use-id>/.exec(notification)?.[1]?.trim();
                const byToolCall = toolCallId
                  ? [...agentResults.values()].filter((item) => item.toolCallId === toolCallId)
                  : [];
                const agent = (id ? agentResults.get(id) : undefined) ??
                  (byToolCall.length === 1 ? byToolCall[0] : undefined);
                if (agent && status) {
                  agent.status = /error|fail/.test(status) ? 'error' :
                    /stop|cancel/.test(status) ? 'stopped' :
                    /wrapped|steered/.test(status) ? 'steered' : 'completed';
                }
              }
            }
            const details = message.details || entry.details;
            if (message.role !== 'toolResult' || message.toolName !== 'Agent' || typeof details?.agentId !== 'string') continue;
            const previous = agentResults.get(details.agentId);
            const result: Subagent = {
              id: details.agentId,
              name: details.description || details.subagentType || previous?.name || details.agentId,
              output: typeof details.output === 'string' ? details.output : previous?.output || '',
              status: details.status === 'background' ? 'running' :
                typeof details.status === 'string' ? details.status : previous?.status || 'completed',
              description: typeof details.description === 'string' ? details.description : previous?.description,
              toolCallId: typeof message.toolCallId === 'string' ? message.toolCallId :
                typeof entry.toolCallId === 'string' ? entry.toolCallId : previous?.toolCallId,
            };
            agentResults.set(details.agentId, result);
          } catch { /* Active session files can end with an incomplete line. */ }
        }
      } catch { /* Parent details are optional; persisted child sessions still work. */ }
    }

    const childData = new Map<string, {
      child: SessionSummary;
      output: string;
      lastMessagePreview?: string;
      model?: string;
      cost?: number;
      agentPrefix?: string;
    }>();
    for (const child of children) {
      let output = '';
      let lastMessagePreview = child.lastMessagePreview;
      let modelChange: string | undefined;
      let messageModel: string | undefined;
      let cost: number | undefined;
      let agentPrefix: string | undefined;
      try {
        if (child.sessionFile && fs.existsSync(child.sessionFile)) {
          const lines = readline.createInterface({
            input: fs.createReadStream(child.sessionFile, { encoding: 'utf8' }),
            crlfDelay: Infinity,
          });
          for await (const line of lines) {
            try {
              const entry = JSON.parse(line);
              if (entry.type === 'model_change' && entry.modelId) modelChange = entry.modelId;
              if (entry.type === 'session_info' && typeof entry.name === 'string') {
                const suffix = entry.name.slice(entry.name.lastIndexOf('#') + 1);
                if (entry.name.includes('#') && suffix) agentPrefix = suffix;
              }
              const costValue = entry.usage?.cost !== undefined ? entry.usage.cost : entry.message?.usage?.cost;
              const turnCost = parseCost(costValue);
              if (turnCost !== undefined) cost = (cost ?? 0) + turnCost;
              if (entry.type === 'message' || entry.role) {
                const msg = entry.message || entry;
                if (typeof msg.model === 'string') messageModel = msg.model;
                else if (typeof entry.model === 'string') messageModel = entry.model;
                if (msg.role !== 'system') {
                  const text = messageText(msg);
                  if (text) lastMessagePreview = text.slice(0, 100);
                }
                if (msg.role === 'assistant') {
                  const content = msg.content;
                  if (typeof content === 'string') {
                    output += (output ? '\n' : '') + content;
                  } else if (Array.isArray(content)) {
                    for (const b of content) {
                      if (b.type === 'text' && b.text) output += (output ? '\n' : '') + b.text;
                    }
                  }
                }
              }
            } catch {}
          }
        }
      } catch {}
      childData.set(child.sessionFile, {
        child, output: output.trim(), lastMessagePreview,
        model: messageModel || modelChange, cost, agentPrefix
      });
    }

    const childMatches = new Map<string, Subagent>();
    for (const [file, data] of childData) {
      if (!data.agentPrefix) continue;
      const matches = [...agentResults.values()].filter((result) => result.id.startsWith(data.agentPrefix!));
      const samePrefixChildren = [...childData.values()].filter((candidate) => candidate.agentPrefix === data.agentPrefix);
      if (matches.length === 1 && samePrefixChildren.length === 1) {
        childMatches.set(file, matches[0]);
      }
    }

    const result: Subagent[] = [...agentResults.values()];
    for (const [file, data] of childData) {
      const { child, output, lastMessagePreview, model, cost } = data;
      const agent = childMatches.get(file);
      if (agent) {
        const index = result.findIndex((item) => item.id === agent.id);
        result[index] = {
          ...agent,
          sessionId: child.id,
          model,
          cost,
          output: output || lastMessagePreview || agent.output,
          status: child.isActive ? 'running' : agent.status,
          description: agent.description || lastMessagePreview,
        };
        continue;
      }
      // Keep ambiguous or legacy child sessions visible without claiming an Agent identity.
      result.push({
        id: child.id,
        unlinked: true,
        name: child.name || child.id,
        model,
        cost,
        output: output || lastMessagePreview || '',
        status: child.isActive ? 'running' : 'completed',
        description: lastMessagePreview,
      });
    }
    return result;
  }

  public extractSessionMetadata(filePath: string): {
    usage?: Record<string, unknown>;
    model?: string | null;
    thinkingLevel?: string | null;
  } {
    let model: string | null = null;
    let thinkingLevel: string | null = null;
    let totalCost = 0;
    let hasCost = false;
    let totalTokens = 0;
    let inputTokens = 0;
    let outputTokens = 0;
    let hasTokens = false;
    let currentModel: string | null = null;
    const byModel: Record<string, { cost?: number; tokens: { total: number; input: number; output: number } }> = {};
    const costByDay: Record<string, number> = {};

    try {
      if (filePath && fs.existsSync(filePath)) {
        const content = fs.readFileSync(filePath, 'utf8');
        const lines = content.split('\n').filter(Boolean);
        for (const line of lines) {
          try {
            const entry = JSON.parse(line);
            if (entry.type === 'model_change' && (entry.modelId || entry.model)) {
              model = entry.modelId || entry.model;
              currentModel = model;
            }
            if (entry.type === 'thinking_change' && entry.thinkingLevel) {
              thinkingLevel = entry.thinkingLevel;
            }
            if (entry.thinkingLevel) {
              thinkingLevel = entry.thinkingLevel;
            }
            if (entry.message?.model) {
              currentModel = entry.message.model;
            }
            if (entry.modelId || entry.model) {
              currentModel = entry.modelId || entry.model;
            }

            const u = entry.usage || entry.message?.usage;
            if (u) {
              let lineCost = 0;
              let hasLineCost = false;
              const parsedCost = parseCost(entry.usage?.cost !== undefined ? entry.usage.cost : entry.message?.usage?.cost);
              if (parsedCost !== undefined) {
                totalCost += parsedCost;
                lineCost = parsedCost;
                hasCost = true;
                hasLineCost = true;
                const rawTimestamp = entry.message?.timestamp ?? entry.timestamp;
                const date = typeof rawTimestamp === 'number' || typeof rawTimestamp === 'string'
                  ? new Date(rawTimestamp) : null;
                if (date && Number.isFinite(date.getTime())) {
                  const day = date.toISOString().slice(0, 10);
                  costByDay[day] = (costByDay[day] ?? 0) + parsedCost;
                }
              }

              let lineTotalTokens = 0;
              let lineInputTokens = 0;
              let lineOutputTokens = 0;
              let hasLineTokens = false;

              if (u.tokens && typeof u.tokens === 'object') {
                if (typeof u.tokens.total === 'number') totalTokens = u.tokens.total;
                if (typeof u.tokens.input === 'number') inputTokens = u.tokens.input;
                if (typeof u.tokens.output === 'number') outputTokens = u.tokens.output;
                lineTotalTokens = Number(u.tokens.total) || 0;
                lineInputTokens = Number(u.tokens.input) || 0;
                lineOutputTokens = Number(u.tokens.output) || 0;
                hasTokens = true;
                hasLineTokens = true;
              } else if (u.totalTokens !== undefined) {
                totalTokens = Number(u.totalTokens) || totalTokens;
                lineTotalTokens = Number(u.totalTokens) || 0;
                hasTokens = true;
                hasLineTokens = true;
              } else if (u.total !== undefined) {
                totalTokens = Number(u.total) || totalTokens;
                lineTotalTokens = Number(u.total) || 0;
                hasTokens = true;
                hasLineTokens = true;
              }

              if (hasLineCost || hasLineTokens) {
                let modelKey = entry.message?.model || entry.model || entry.modelId || currentModel;
                if (entry.type === 'compaction' || entry.role === 'compactionSummary' || entry.type === 'summary' ||
                    ((entry.message?.role === 'toolResult' || entry.role === 'toolResult') && !entry.message?.model && !entry.model)) {
                  modelKey = 'Tools/summaries';
                } else if (!modelKey) {
                  modelKey = model || 'Modello Principale';
                }
                if (!byModel[modelKey]) {
                  byModel[modelKey] = { tokens: { total: 0, input: 0, output: 0 } };
                }
                if (hasLineCost) {
                  byModel[modelKey].cost = (byModel[modelKey].cost ?? 0) + lineCost;
                }
                if (hasLineTokens) {
                  byModel[modelKey].tokens.total += lineTotalTokens;
                  byModel[modelKey].tokens.input += lineInputTokens;
                  byModel[modelKey].tokens.output += lineOutputTokens;
                }
              }
            }
          } catch {}
        }
      }
    } catch {}

    const usage: Record<string, unknown> = {};
    if (hasCost) {
      usage.cost = totalCost;
    }
    if (Object.keys(costByDay).length > 0) usage.costByDay = costByDay;
    if (hasTokens) {
      usage.totalTokens = totalTokens;
      usage.tokens = {
        total: totalTokens,
        input: inputTokens,
        output: outputTokens,
      };
    }
    if (Object.keys(byModel).length > 0) {
      usage.byModel = byModel;
      usage.models = byModel;
    }

    return {
      usage: Object.keys(usage).length > 0 ? usage : undefined,
      model,
      thinkingLevel,
    };
  }
}

