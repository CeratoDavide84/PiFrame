import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/composer/composer.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class _PickerSession extends SessionStateNotifier {
  _PickerSession({this.unavailable = false}) : super('picker', null) {
    state = const SessionState(
      sessionId: 'picker',
      cwd: '/fixture',
      currentModel: 'GPT-6 Luna',
      contextWindowOverride: 272000,
    );
  }
  final bool unavailable;
  int modelLoads = 0;
  Completer<List<Map<String, dynamic>>>? initialModels;
  final applied = <int?>[];
  @override
  Future<List<Map<String, dynamic>>> getAvailableModels() async {
    modelLoads++;
    // The composer can mount before the daemon is connected.
    if (modelLoads == 1 && initialModels != null) return initialModels!.future;
    if (modelLoads == 1 || unavailable) return [];
    return <Map<String, dynamic>>[
      {
        'provider': 'fixture',
        'id': 'gpt-6-luna',
        'name': 'GPT-6 Luna',
        'contextWindow': 1000000,
        'cost': {
          'tiers': [
            {'inputTokensAbove': 272000},
          ],
        },
      },
    ];
  }

  @override
  Future<void> setContextWindow(int? size) async {
    applied.add(size);
    state = state.copyWith(
      contextWindowOverride: size,
      clearContextWindowOverride: size == null,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getCommands() async => [];
}

void main() {
  Future<void> mount(WidgetTester tester, _PickerSession session) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          daemonEndpointProvider.overrideWith((ref) async => null),
          sessionStateFamily('picker').overrideWith((ref) => session),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [FrameTokens.dark],
          ),
          home: const Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: Composer(sessionId: 'picker'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'chat context picker recovers catalog loaded before daemon connection and selects tier',
    (tester) async {
      final session = _PickerSession();
      await mount(tester, session);
      final chip = find.byKey(
        const ValueKey('composer-context-size-picker-btn'),
      );
      expect(chip, findsOneWidget);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('composer-context-size-dialog')),
        findsOneWidget,
      );
      expect(session.modelLoads, greaterThan(1));
      await tester.tap(
        find.byKey(const ValueKey('context-window-preset-dropdown')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Personalizzato').last, findsOneWidget);
      expect(find.text('272k (Tier base)').last, findsOneWidget);
      await tester.tap(find.text('1M (Max / Tier esteso)').last);
      await tester.pumpAndSettle();
      expect(session.applied.last, 1000000);
      expect(
        find.byKey(const ValueKey('context-window-custom-slider')),
        findsNothing,
      );
      Navigator.of(
        tester.element(
          find.byKey(const ValueKey('composer-context-size-dialog')),
        ),
      ).pop();
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: chip, matching: find.text('1M')),
        findsOneWidget,
      );

      // Custom at the model maximum must remain Custom when the shared selector reopens.
      await tester.tap(chip);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('context-window-preset-dropdown')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Personalizzato').last);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('context-window-custom-slider')),
        findsOneWidget,
      );
      Navigator.of(
        tester.element(
          find.byKey(const ValueKey('composer-context-size-dialog')),
        ),
      ).pop();
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('context-window-custom-slider')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('context-window-preset-dropdown')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('272k (Tier base)').last);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('context-window-custom-slider')),
        findsNothing,
      );
      expect(session.applied.last, 272000);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late initial catalog cannot overwrite the successful click retry',
    (tester) async {
      final session = _PickerSession()
        ..initialModels = Completer<List<Map<String, dynamic>>>();
      await mount(tester, session);
      final chip = find.byKey(
        const ValueKey('composer-context-size-picker-btn'),
      );
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('composer-context-size-dialog')),
        findsOneWidget,
      );
      session.initialModels!.complete([]);
      await tester.pumpAndSettle();
      Navigator.of(
        tester.element(
          find.byKey(const ValueKey('composer-context-size-dialog')),
        ),
      ).pop();
      await tester.pumpAndSettle();
      await session.setContextWindow(null);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: chip, matching: find.text('1M')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'chat context picker reports unavailable metadata instead of silently ignoring taps',
    (tester) async {
      await mount(tester, _PickerSession(unavailable: true));
      await tester.tap(
        find.byKey(const ValueKey('composer-context-size-picker-btn')),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Contesto del modello non disponibile'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('composer-context-size-dialog')),
        findsNothing,
      );
    },
  );
}
