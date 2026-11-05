import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame_protocol/pi_frame_protocol.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/data/language/language_settings.dart';
import 'package:pi_frame/features/settings/remote_section.dart';

class _MockRemoteClient extends PcpClient {
  _MockRemoteClient({this.initialData}) : super(port: 1, token: 'test');
  final Map<String, dynamic>? initialData;
  final _eventsController = StreamController<PcpEvent>.broadcast();

  void emitEvent(PcpEvent event) {
    _eventsController.add(event);
  }

  @override
  Stream<PcpEvent> events(String sessionId) => _eventsController.stream;

  @override
  Future<Map<String, dynamic>> getRemoteStatus() async => {
    'data': initialData ?? {
      'enabled': false,
      'state': 'stopped',
      'tunnelProvider': 'cloudflared',
      'devices': [],
      'options': {'defaultMode': 'view'},
    },
  };
}

void main() {
  testWidgets('remote settings update when the language changes', (tester) async {
    final client = _MockRemoteClient();
    await tester.pumpWidget(ProviderScope(
      overrides: [pcpClientProvider.overrideWithValue(client)],
      child: const MaterialApp(home: Scaffold(body: RemoteSection())),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('Connessione Remota Sicura'), findsOneWidget);
    final container = ProviderScope.containerOf(tester.element(find.byType(RemoteSection)));
    container.read(appLanguageProvider.notifier).setLanguage(AppLanguage.en);
    await tester.pump();
    expect(find.text('Secure remote connection'), findsOneWidget);
    expect(find.text('DISABLED'), findsOneWidget);
  });

  testWidgets('RemoteSection renders disabled state and options', (tester) async {
    final client = _MockRemoteClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pcpClientProvider.overrideWithValue(client),
        ],
        child: const MaterialApp(
          home: Scaffold(body: RemoteSection()),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('Connessione Remota Sicura'), findsOneWidget);
    expect(find.text('DISATTIVATO'), findsOneWidget);
    expect(find.text('Abilita Accesso Remoto'), findsOneWidget);
    expect(find.text('Configurazione Provider Tunnel'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets('RemoteSection renders active tunnel with QR code and device modes', (tester) async {
    final client = _MockRemoteClient(
      initialData: {
        'enabled': true,
        'state': 'running',
        'url': 'https://test-phone-tunnel.trycloudflare.com',
        'tunnelProvider': 'cloudflared',
        'localPort': 54321,
        'pairingPending': {
          'secret': 'pair_tok_mock123',
          'url': 'https://test-phone-tunnel.trycloudflare.com/#pair=pair_tok_mock123',
          'expiresAt': DateTime.now().millisecondsSinceEpoch + 600000,
        },
        'options': {'defaultMode': 'view'},
        'devices': [
          {
            'deviceId': 'dev_test_phone',
            'name': 'Apple iOS Device',
            'mode': 'view',
            'remoteIp': '198.51.100.42',
            'lastUsedAt': DateTime.now().millisecondsSinceEpoch,
            'expiresAt': DateTime.now().millisecondsSinceEpoch + 86400000,
          }
        ],
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pcpClientProvider.overrideWithValue(client),
        ],
        child: const MaterialApp(
          home: Scaffold(body: RemoteSection()),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('ATTIVO'), findsOneWidget);
    expect(find.text('Associa il tuo Smartphone'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);

    // Scroll down to reveal options and paired devices section
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();

    expect(find.text('Modalità Predefinita per Nuovi Dispositivi'), findsOneWidget);
    expect(find.text('Apple iOS Device'), findsOneWidget);
    expect(find.text('VIEW'), findsOneWidget);
    expect(find.text('Revoca'), findsOneWidget);
  });
}
