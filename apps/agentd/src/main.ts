import * as http from 'node:http';
import { acquireSingleInstanceLock } from './config/lock.js';
import { loadConfig } from './config/config.js';
import { generateAndSaveToken, writeRuntimeInfo, cleanupRuntimeFiles } from './config/runtime.js';
import { discoverPi } from './pi/discovery.js';
import { probeCapabilities } from './pi/capabilities.js';
import { createHttpServer } from './server/httpServer.js';
import { createWsServer } from './server/wsServer.js';
import { findStaticDir } from './server/static.js';
import { SessionRegistry } from './sessions/SessionRegistry.js';
import { Dispatcher } from './commands/Dispatcher.js';
import { RemoteManager } from './remote/RemoteManager.js';

const VERSION = '1.3.0'; // x-release-please-version

async function main() {
  console.log(`[agentd] Starting PiFrame Daemon v${VERSION}...`);

  // 1. Single-instance mutex lock
  const lockHandle = acquireSingleInstanceLock();
  if (!lockHandle) {
    console.log('[agentd] Another healthy daemon instance is already active. Exiting 0.');
    process.exit(0);
  }

  // 2. Load configuration
  const config = loadConfig();

  // 3. Discover Pi installation and capabilities
  const piInstall = await discoverPi(config.piPath);
  console.log(`[agentd] Pi discovery result: found=${piInstall.found}, version=${piInstall.version || 'none'}, supported=${piInstall.supported}`);
  if (piInstall.path) {
    console.log(`[agentd] Using Pi executable: ${piInstall.path}`);
  }

  const piCaps = piInstall.path
    ? await probeCapabilities(piInstall.path, piInstall.version || '0.85.0', piInstall.supported)
    : {
        version: '0.0.0',
        supported: false,
        modes: [],
        features: []
      };

  const startedAt = Date.now();

  let token = '';
  let port = 0;

  // Read cli args for optional --port
  const portArgIdx = process.argv.indexOf('--port');
  if (portArgIdx !== -1 && process.argv[portArgIdx + 1]) {
    port = parseInt(process.argv[portArgIdx + 1], 10) || 0;
  }

  const remoteManager = new RemoteManager(config);

  const staticDir = findStaticDir();

  // 4a. Local HTTP server (desktop client + loopback web UI)
  const httpServer = createHttpServer({
    config,
    token: () => token,
    version: VERSION,
    startedAt,
    remoteManager,
    staticDir,
    listener: 'local'
  });

  await new Promise<void>((resolve, reject) => {
    httpServer.listen(port, '127.0.0.1', () => resolve());
    httpServer.on('error', reject);
  });

  const boundAddr = httpServer.address() as any;
  const actualPort = boundAddr.port;
  console.log(`[agentd] Local HTTP/WS server bound strictly to 127.0.0.1:${actualPort}`);

  // 4b. Dedicated Remote HTTP server (tunnels target this port ONLY - H2/H4)
  const remoteHttpServer = createHttpServer({
    config,
    token: () => token,
    version: VERSION,
    startedAt,
    remoteManager,
    staticDir,
    listener: 'remote'
  });

  const desiredRemotePort = config.remote.listenerPort || 0;
  await new Promise<void>((resolve, reject) => {
    remoteHttpServer.listen(desiredRemotePort, '127.0.0.1', () => resolve());
    remoteHttpServer.on('error', reject);
  });

  const remoteBoundAddr = remoteHttpServer.address() as any;
  const actualRemotePort = remoteBoundAddr.port;
  console.log(`[agentd] Dedicated remote listener bound to 127.0.0.1:${actualRemotePort}`);
  remoteManager.setListenerPort(actualRemotePort);

  if (config.remote.enabled) {
    console.log('[agentd] Remote connection enabled in config. Starting tunnel...');
    // Boot auto-start: do NOT generate ephemeral pairing secret automatically (M6)
    remoteManager.start(undefined, { generatePairing: false }).catch((err) => {
      console.error('[agentd] Failed to start remote tunnel:', err.message);
    });
  }

  // 5. Initialize runtime directory (~/.piframe/runtime/daemon.json, daemon.token, etc.)
  token = generateAndSaveToken();
  writeRuntimeInfo({
    port: actualPort,
    pid: process.pid,
    version: VERSION,
    startedAt,
    protocol: 1
  });

  // 6. Setup WebSocket Server, SessionRegistry and Dispatcher
  let isShuttingDown = false;
  let registry: SessionRegistry;
  let dispatcher: Dispatcher;

  const { wss: _wss, manager } = createWsServer({
    httpServer,
    remoteHttpServer,
    config,
    token,
    version: VERSION,
    startedAt,
    remoteManager,
    piInfo: {
      path: piInstall.path || '',
      version: piInstall.version || '',
      supported: piInstall.supported
    },
    port: actualPort,
    onCommand: async (conn, cmd) => {
      await dispatcher.handle(conn, cmd);
    },
    onAttach: async (conn, sessionId, lastSeq, commandId) => {
      await registry.attachClient(sessionId, conn, lastSeq, commandId);
    },
    onDetach: async (conn, sessionId) => {
      await registry.detachClient(sessionId, conn);
    }
  });

  registry = new SessionRegistry({
    piExecutablePath: piInstall.path || '',
    capabilities: piCaps,
    workerIdleTimeoutMs: config.workerIdleTimeoutMs,
    connectionManager: manager
  });

  dispatcher = new Dispatcher(registry, manager, undefined, remoteManager);

  console.log(`[agentd] Ready. Listening on ws://127.0.0.1:${actualPort}`);

  // 7. Clean graceful shutdown on SIGINT / SIGTERM
  const shutdown = async (signal: string) => {
    if (isShuttingDown) return;
    isShuttingDown = true;
    console.log(`[agentd] Received ${signal}. Draining and shutting down...`);

    // 1. Notify clients with close code 4010 (Daemon in shutdown)
    manager.closeAll(4010, 'Daemon shutting down');

    // 2. Stop workers gracefully
    await registry.closeAll(3000);

    // 2b. Flush and stop remote tunnel without resetting enabled state in config
    remoteManager.flush();
    await remoteManager.stop({ persistEnabled: false }).catch(() => {});

    // 3. Close HTTP/WS servers
    await Promise.all([
      new Promise<void>((resolve) => httpServer.close(() => resolve())),
      new Promise<void>((resolve) => remoteHttpServer.close(() => resolve()))
    ]);

    // 4. Cleanup runtime files & single instance lock
    cleanupRuntimeFiles();
    lockHandle.release();

    console.log('[agentd] Shutdown complete.');
    process.exit(0);
  };

  process.on('SIGINT', () => void shutdown('SIGINT'));
  process.on('SIGTERM', () => void shutdown('SIGTERM'));
}

main().catch((err) => {
  console.error('[agentd] Fatal error during startup:', err);
  process.exit(1);
});
