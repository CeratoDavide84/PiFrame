import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';

void main() {
  late HttpServer server;
  late PcpClient client;
  late WebSocket socket;
  late StreamSubscription subscription;
  final commands = <Map<String, dynamic>>[];

  setUp(() async {
    commands.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final ready = Completer<void>();
    subscription = server.listen((request) async {
      socket = await WebSocketTransformer.upgrade(request);
      socket.listen((raw) {
        final frame = jsonDecode(raw as String) as Map<String, dynamic>;
        if (frame['kind'] == 'hello') {
          socket.add(jsonEncode({'kind': 'welcome'}));
        } else if (frame['kind'] == 'command') {
          commands.add(frame);
        }
      });
    });
    client = PcpClient(port: server.port, token: 'test');
    client.connectionStateStream.listen((state) {
      if (state == DaemonConnectionState.connected && !ready.isCompleted) {
        ready.complete();
      }
    });
    client.connect();
    await ready.future.timeout(const Duration(seconds: 3));
  });

  tearDown(() async {
    client.dispose();
    await socket.close();
    await subscription.cancel();
    await server.close(force: true);
  });

  test('failed results reject instead of hiding daemon errors', () async {
    final result = client.listSessions();
    final assertion = expectLater(result, throwsA(isA<StateError>()));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    socket.add(
      jsonEncode({
        'kind': 'result',
        'commandId': commands.single['commandId'],
        'payload': {'state': 'failed', 'error': 'Worker unavailable'},
      }),
    );
    await assertion;
  });

  test(
    'rapid same-type commands have distinct IDs and both complete',
    () async {
      final first = client.listSessions();
      final second = client.listSessions();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(commands.length, 2);
      expect(commands[0]['commandId'], isNot(commands[1]['commandId']));
      for (final command in commands) {
        socket.add(
          jsonEncode({
            'kind': 'result',
            'commandId': command['commandId'],
            'payload': {
              'state': 'completed',
              'data': {'sessions': []},
            },
          }),
        );
      }
      await Future.wait([first, second]);
    },
  );

  test(
    'workspace commands use the active session and preserve validated payloads',
    () async {
      final requests = <Future<Map<String, dynamic>>>[
        client.listWorkspaceFiles('session-a'),
        client.readWorkspaceFile('session-a', 'lib/main.dart'),
        client.saveWorkspaceFile('session-a', {
          'path': 'lib/main.dart',
          'content': 'updated',
          'revision': List.filled(64, 'a').join(),
        }),
        client.workspaceGitAction('session-a', {
          'action': 'commit',
          'paths': ['lib/main.dart'],
          'expectedStagedPaths': ['lib/main.dart'],
          'message': 'Update main',
        }),
      ];
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(commands.map((command) => command['type']).toList(), [
        'workspace.listFiles',
        'workspace.readFile',
        'workspace.saveFile',
        'workspace.gitAction',
      ]);
      for (var index = 0; index < commands.length; index++) {
        expect(commands[index]['sessionId'], 'session-a');
        socket.add(
          jsonEncode({
            'kind': 'result',
            'commandId': commands[index]['commandId'],
            'payload': {'state': 'completed', 'data': {}},
          }),
        );
      }
      await Future.wait(requests);
      expect(commands[1]['payload']['path'], 'lib/main.dart');
      expect(commands[2]['payload']['revision'], List.filled(64, 'a').join());
      expect(commands[3]['payload']['expectedStagedPaths'], ['lib/main.dart']);
    },
  );

  test('context settings serialize backend command payloads', () async {
    final limitFuture = client.setContextWindowOverride('session-a', 195000);
    final reserveFuture = client.setCompactionReservePercent('session-a', 5.0);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(commands.map((command) => command['type']).toList(), [
      'agent.setContextWindowOverride',
      'agent.setCompactionReservePercent',
    ]);
    expect(commands[0]['payload'], {'limit': 195000});
    expect(commands[1]['payload'], {'percent': 5.0});
    for (final command in commands) {
      socket.add(
        jsonEncode({
          'kind': 'result',
          'commandId': command['commandId'],
          'payload': {
            'state': 'completed',
            'data': {
              'contextWindowOverride': 195000,
              'compactionReservePercent': 5.0,
            },
          },
        }),
      );
    }
    await Future.wait([limitFuture, reserveFuture]);
  });

  test('Pi authentication commands carry no credential data', () async {
    final login = client.piAuthLogin('session-a');
    final logout = client.piAuthLogout('session-a');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(commands.map((command) => command['type']).toList(), [
      'agent.authLogin',
      'agent.authLogout',
    ]);
    expect(commands.every((command) => command['payload'].isEmpty), isTrue);
    expect(
      commands.every((command) => command['sessionId'] == 'session-a'),
      isTrue,
    );
    for (final command in commands) {
      socket.add(
        jsonEncode({
          'kind': 'result',
          'commandId': command['commandId'],
          'payload': {
            'state': 'completed',
            'data': {'started': true},
          },
        }),
      );
    }
    await Future.wait([login, logout]);
  });

  test('subagents unwrap daemon data with persisted model and cost', () async {
    final result = client.getSubagents('parent');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(commands.single['type'], 'session.subagents');
    socket.add(jsonEncode({
      'kind': 'result',
      'commandId': commands.single['commandId'],
      'payload': {
        'state': 'completed',
        'data': {
          'subagents': [
            {'id': 'child', 'model': 'actual-model', 'cost': 0.0175},
          ],
        },
      },
    }));
    expect(await result, [
      {'id': 'child', 'model': 'actual-model', 'cost': 0.0175},
    ]);
  });

  test('subagents propagate failed responses instead of returning empty', () async {
    final result = client.getSubagents('parent');
    final assertion = expectLater(result, throwsA(isA<StateError>()));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    socket.add(jsonEncode({
      'kind': 'result',
      'commandId': commands.single['commandId'],
      'payload': {'state': 'failed', 'error': 'Unavailable'},
    }));
    await assertion;
  });

  test('subagents reject malformed data instead of returning empty', () async {
    final result = client.getSubagents('parent');
    final assertion = expectLater(result, throwsA(isA<FormatException>()));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    socket.add(jsonEncode({
      'kind': 'result',
      'commandId': commands.single['commandId'],
      'payload': {'state': 'completed', 'data': {}},
    }));
    await assertion;
  });

  test('dispose rejects pending commands', () async {
    final result = client.listSessions();
    final assertion = expectLater(result, throwsA(isA<StateError>()));
    client.dispose();
    await assertion;
  });

  test(
    'remote connection commands format correct payloads and complete',
    () async {
      final statusFuture = client.getRemoteStatus();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(commands.last['type'], 'remote.getStatus');
      socket.add(
        jsonEncode({
          'kind': 'result',
          'commandId': commands.last['commandId'],
          'payload': {
            'state': 'completed',
            'data': {'enabled': false, 'state': 'stopped'},
          },
        }),
      );
      final status = await statusFuture;
      final statusData = status['data'] as Map<String, dynamic>;
      expect(statusData['enabled'], false);

      final startFuture = client.startRemoteTunnel(
        tunnelProvider: 'cloudflared',
        customUrl: null,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(commands.last['type'], 'remote.start');
      expect(commands.last['payload']['tunnelProvider'], 'cloudflared');
      socket.add(
        jsonEncode({
          'kind': 'result',
          'commandId': commands.last['commandId'],
          'payload': {
            'state': 'completed',
            'data': {'enabled': true, 'state': 'running'},
          },
        }),
      );
      await startFuture;

      final pairFuture = client.generateRemotePairing(ttlMs: 300000);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(commands.last['type'], 'remote.generatePairing');
      expect(commands.last['payload']['ttlMs'], 300000);
      socket.add(
        jsonEncode({
          'kind': 'result',
          'commandId': commands.last['commandId'],
          'payload': {
            'state': 'completed',
            'data': {'secret': 'pair_tok_test'},
          },
        }),
      );
      final pair = await pairFuture;
      final pairData = pair['data'] as Map<String, dynamic>;
      expect(pairData['secret'], 'pair_tok_test');

      final optFuture = client.setRemoteOptions(defaultMode: 'control');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(commands.last['type'], 'remote.setOptions');
      expect(commands.last['payload']['defaultMode'], 'control');
      socket.add(
        jsonEncode({
          'kind': 'result',
          'commandId': commands.last['commandId'],
          'payload': {'state': 'completed', 'data': {}},
        }),
      );
      await optFuture;

      final modeFuture = client.setRemoteDeviceMode(
        deviceId: 'dev_test_123',
        mode: 'control',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(commands.last['type'], 'remote.setDeviceMode');
      expect(commands.last['payload']['deviceId'], 'dev_test_123');
      expect(commands.last['payload']['mode'], 'control');
      socket.add(
        jsonEncode({
          'kind': 'result',
          'commandId': commands.last['commandId'],
          'payload': {
            'state': 'completed',
            'data': {'ok': true},
          },
        }),
      );
      await modeFuture;

      final revFuture = client.revokeRemoteDevice('dev_test_123');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(commands.last['type'], 'remote.revokeDevice');
      expect(commands.last['payload']['deviceId'], 'dev_test_123');
      socket.add(
        jsonEncode({
          'kind': 'result',
          'commandId': commands.last['commandId'],
          'payload': {
            'state': 'completed',
            'data': {'ok': true},
          },
        }),
      );
      await revFuture;

      final stopFuture = client.stopRemoteTunnel();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(commands.last['type'], 'remote.stop');
      socket.add(
        jsonEncode({
          'kind': 'result',
          'commandId': commands.last['commandId'],
          'payload': {
            'state': 'completed',
            'data': {'enabled': false, 'state': 'stopped'},
          },
        }),
      );
      await stopFuture;
    },
  );
}
