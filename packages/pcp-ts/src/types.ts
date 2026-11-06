/**
 * PCP/1 (PiFrame Protocol) TypeScript Type Definitions
 * Normative contract for client-daemon communication.
 */

export type ProtocolVersion = 1;

export type ProtocolKind =
  | 'hello'
  | 'welcome'
  | 'command'
  | 'ack'
  | 'result'
  | 'event'
  | 'snapshot'
  | 'error'
  | 'ping'
  | 'pong';

export interface PcpEnvelope<T = Record<string, unknown>> {
  protocol: ProtocolVersion;
  kind: ProtocolKind;
  id: string;
  ts: number;
  commandId?: string;
  sessionId?: string;
  seq?: number;
  type: string;
  payload: T;
}

// -----------------------------------------------------------------------------
// Handshake
// -----------------------------------------------------------------------------

export interface ClientInfo {
  name: string;
  version: string;
  platform: string;
}

export interface PcpHelloPayload {
  token: string;
  client: ClientInfo;
  encoding: 'json';
  capabilities: string[];
}

export type PcpHello = PcpEnvelope<PcpHelloPayload> & {
  kind: 'hello';
  type: 'connection.hello';
};

export interface DaemonInfo {
  version: string;
  startedAt: number;
  pid: number;
}

export interface PiInfo {
  path: string;
  version: string;
  supported: boolean;
}

export interface ProtocolLimits {
  maxFrameBytes: number;
  journalMaxEvents: number;
}

export interface PcpWelcomePayload {
  clientId: string;
  daemon: DaemonInfo;
  pi: PiInfo;
  capabilities: string[];
  limits: ProtocolLimits;
}

export type PcpWelcome = PcpEnvelope<PcpWelcomePayload> & {
  kind: 'welcome';
  type: 'connection.welcome';
};

// -----------------------------------------------------------------------------
// Commands
// -----------------------------------------------------------------------------

export type PcpCommandType =
  | 'pi.packages.list'
  | 'pi.packages.update'
  | 'pi.packages.remove'
  | 'pi.packages.pin'
  | 'daemon.getStatus'
  | 'daemon.getConfig'
  | 'daemon.setConfig'
  | 'usage.getAnalytics'
  | 'session.list'
  | 'session.create'
  | 'session.open'
  | 'session.attach'
  | 'session.detach'
  | 'session.closeWorker'
  | 'session.delete'
  | 'session.rename'
  | 'session.fork'
  | 'session.clone'
  | 'session.getTree'
  | 'session.getEntries'
  | 'session.getHistory'
  | 'session.getStats'
  | 'session.getForkPoints'
  | 'session.subagents'
  | 'agent.prompt'
  | 'agent.steer'
  | 'agent.followUp'
  | 'agent.abort'
  | 'agent.clearQueue'
  | 'agent.interrupt'
  | 'agent.compact'
  | 'agent.setContextWindowOverride'
  | 'agent.setCompactionReservePercent'
  | 'agent.setAutoCompaction'
  | 'agent.setAutoRetry'
  | 'agent.abortRetry'
  | 'agent.setModel'
  | 'agent.authLogin'
  | 'agent.authLogout'
  | 'agent.getModels'
  | 'agent.setThinkingLevel'
  | 'agent.getThinkingLevels'
  | 'agent.setSteeringMode'
  | 'agent.setFollowUpMode'
  | 'agent.getCommands'
  | 'ui.claim'
  | 'ui.respond'
  | 'workspace.refresh'
  | 'workspace.getDiff'
  | 'workspace.listFiles'
  | 'workspace.readFile'
  | 'workspace.saveFile'
  | 'workspace.gitAction'
  | 'remote.getStatus'
  | 'remote.start'
  | 'remote.stop'
  | 'remote.generatePairing'
  | 'remote.setDeviceMode'
  | 'remote.installCloudflared'
  | 'remote.installTailscale'
  | 'remote.setTailscaleHostname'
  | 'remote.revokeDevice'
  | 'remote.revokeAll'
  | 'remote.setOptions';

export interface PcpCommand<T = Record<string, unknown>> extends PcpEnvelope<T> {
  kind: 'command';
  commandId: string;
  type: PcpCommandType;
}

export interface PiPackageInfo {
  source: string;
  name: string;
  version: string | null;
  pinnedVersion: string | null;
}

export interface WorkspaceFileInfo {
  path: string;
  sizeBytes: number;
}

export interface WorkspaceListFilesResult {
  rootPath: string;
  files: WorkspaceFileInfo[];
  truncated: boolean;
}

export interface WorkspaceReadFileResult {
  rootPath: string;
  path: string;
  content: string;
  revision: string;
  sizeBytes: number;
}

export interface WorkspaceSaveFileRequest {
  path: string;
  content: string;
  revision: string;
}

export type WorkspaceGitAction = 'stage' | 'unstage' | 'commit' | 'discard';

export interface WorkspaceGitActionRequest {
  action: WorkspaceGitAction;
  paths: string[];
  expectedStagedPaths?: string[];
  message?: string;
}

// -----------------------------------------------------------------------------
// Ack & Result
// -----------------------------------------------------------------------------

export type PcpAckState = 'accepted' | 'executing' | 'resume' | 'rejected' | 'deduplicated';

export interface PcpAckPayload {
  state: PcpAckState;
  reason?: string;
}

export interface PcpAck extends PcpEnvelope<PcpAckPayload> {
  kind: 'ack';
  commandId: string;
  type: 'command.ack';
}

export type PcpResultState = 'completed' | 'failed' | 'deduplicated' | 'rejected';

export interface PcpResultPayload<T = Record<string, unknown>> {
  state: PcpResultState;
  data?: T;
  error?: string;
}

export interface PcpResult<T = Record<string, unknown>> extends PcpEnvelope<PcpResultPayload<T>> {
  kind: 'result';
  commandId: string;
  type: 'command.result';
}

// -----------------------------------------------------------------------------
// Normalized Events
// -----------------------------------------------------------------------------

export type PcpEventType =
  | 'session.status'
  | 'run.started'
  | 'run.ended'
  | 'run.settled'
  | 'turn.started'
  | 'turn.ended'
  | 'message.started'
  | 'message.completed'
  | 'text.started'
  | 'text.delta'
  | 'text.completed'
  | 'thinking.started'
  | 'thinking.delta'
  | 'thinking.completed'
  | 'toolcall.started'
  | 'toolcall.argsDelta'
  | 'toolcall.completed'
  | 'usage.updated'
  | 'tool.started'
  | 'tool.progress'
  | 'tool.completed'
  | 'queue.changed'
  | 'compaction.started'
  | 'compaction.ended'
  | 'retry.started'
  | 'retry.ended'
  | 'summarization.retry'
  | 'bash.output'
  | 'extension.error'
  | 'ui.request'
  | 'ui.claimed'
  | 'ui.resolved'
  | 'ui.notify'
  | 'ui.status'
  | 'ui.widget'
  | 'ui.editorText'
  | 'ui.title'
  | 'workspace.changed'
  | 'worker.diagnostic'
  | 'worker.crashed'
  | 'journal.gap'
  | 'session.indexChanged'
  | 'daemon.configChanged'
  | 'remote.statusChanged';

export interface PcpEvent<T = Record<string, unknown>> extends PcpEnvelope<T> {
  kind: 'event';
  sessionId: string;
  seq: number;
  type: PcpEventType;
}

// -----------------------------------------------------------------------------
// Snapshots
// -----------------------------------------------------------------------------

export interface SessionMeta {
  id: string;
  name?: string;
  cwd: string;
  gitRoot?: string | null;
  sessionFile?: string | null;
  createdAt?: number;
  lastActivityAt?: number;
}

export interface RuntimeMeta {
  status: string;
  model?: Record<string, unknown> | null;
  thinkingLevel?: string | null;
  steeringMode?: string | null;
  followUpMode?: string | null;
  isStreaming: boolean;
  runStartedAt?: number | null;
  isCompacting: boolean;
  autoCompaction: boolean;
  queue: {
    steering: string[];
    followUp: string[];
  };
  contextWindowOverride?: number | null;
  compactionReservePercent?: number;
}

export interface TranscriptMeta {
  entries: Array<Record<string, unknown>>;
  leafId?: string | null;
  totalEntries?: number;
  hasMore?: boolean;
}

export type RemoteDeviceMode = 'view' | 'control';

export interface RemoteDeviceRecord {
  deviceId: string;
  name: string;
  userAgent?: string;
  mode: RemoteDeviceMode;
  createdAt: number;
  lastUsedAt: number;
  expiresAt: number;
  remoteIp?: string;
}

export interface RemoteStatusPayload {
  enabled: boolean;
  state: 'stopped' | 'starting' | 'running' | 'error';
  url?: string;
  tunnelProvider: string;
  cloudflaredInstalled: boolean;
  cloudflaredPath?: string;
  tailscale?: {
    installed: boolean;
    running: boolean;
    hostname?: string;
    domain?: string;
    magicDnsSuffix?: string;
  };
  error?: string;
  localPort?: number;
  devices: RemoteDeviceRecord[];
  pairingPending?: {
    expiresAt: number;
    url?: string;
  };
  options: {
    defaultMode: RemoteDeviceMode;
  };
}

export interface PcpSnapshotPayload {
  session: SessionMeta;
  runtime: RuntimeMeta;
  transcript: TranscriptMeta;
  liveMessage?: Record<string, unknown> | null;
  activeTools: Array<Record<string, unknown>>;
  pendingUiRequests: Array<Record<string, unknown>>;
  usage: Record<string, unknown>;
  workspace: Record<string, unknown>;
}

export interface PcpSnapshot extends PcpEnvelope<PcpSnapshotPayload> {
  kind: 'snapshot';
  sessionId: string;
  seq: number;
  type: 'session.snapshot';
}

// -----------------------------------------------------------------------------
// Errors
// -----------------------------------------------------------------------------

export type PcpErrorCode =
  | 'AUTH_FAILED'
  | 'PROTOCOL_VERSION_UNSUPPORTED'
  | 'INVALID_MESSAGE'
  | 'SESSION_NOT_FOUND'
  | 'SESSION_BUSY'
  | 'WORKER_UNAVAILABLE'
  | 'WORKER_CRASHED'
  | 'PI_NOT_FOUND'
  | 'PI_VERSION_UNSUPPORTED'
  | 'COMMAND_REJECTED'
  | 'COMMAND_TIMEOUT'
  | 'UI_REQUEST_NOT_CLAIMED'
  | 'UI_REQUEST_EXPIRED'
  | 'JOURNAL_GAP'
  | 'CONFIG_INVALID'
  | 'RATE_LIMITED'
  | 'INTERNAL';

export interface PcpErrorPayload {
  code: PcpErrorCode;
  message: string;
  retryable?: boolean;
  details?: Record<string, unknown>;
  hint?: string;
}

export interface PcpError extends PcpEnvelope<PcpErrorPayload> {
  kind: 'error';
  type: 'error';
}

// -----------------------------------------------------------------------------
// Ping / Pong
// -----------------------------------------------------------------------------

export interface PcpPing extends PcpEnvelope<Record<string, unknown>> {
  kind: 'ping';
  type: 'heartbeat.ping';
}

export interface PcpPong extends PcpEnvelope<Record<string, unknown>> {
  kind: 'pong';
  type: 'heartbeat.pong';
}

// -----------------------------------------------------------------------------
// Message Unions
// -----------------------------------------------------------------------------

export type ClientMessage =
  | PcpHello
  | PcpCommand<any>
  | PcpPong;

export type ServerMessage =
  | PcpWelcome
  | PcpAck
  | PcpResult<any>
  | PcpEvent<any>
  | PcpSnapshot
  | PcpError
  | PcpPing;

export type PcpMessage = ClientMessage | ServerMessage;
