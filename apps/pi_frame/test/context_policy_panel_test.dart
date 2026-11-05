import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/context_panel/context_panel.dart';
import 'package:pi_frame/features/context_panel/context_window_selector.dart';

class _PanelSession extends SessionStateNotifier {
  _PanelSession({
    int? override = 272000,
    this.modelMaximum = 1000000,
    bool auto = true,
    bool readOnly = false,
    bool busy = false,
  }) : super('policy-fixture', null) {
    state = SessionState(
      sessionId: 'policy-fixture',
      cwd: '/fixture',
      currentModel: 'Luna fixture',
      contextWindowOverride: override,
      autoCompaction: auto,
      readOnly: readOnly,
      agentStatus: busy ? AgentStatus.working : AgentStatus.settled,
      sessionStats: const {
        'tokens': {'total': 42000},
        'contextUsage': {
          'tokens': 70656,
          'contextWindow': 1000000,
          'percent': 7.0656,
        },
      },
    );
  }

  final int modelMaximum;
  bool failContext = false;
  bool failReserve = false;
  Completer<void>? pendingContext;

  @override
  Future<void> refreshDefaults() async {}
  @override
  Future<void> refreshSessionStats() async {}
  @override
  Future<({List<Map<String, dynamic>> models, String? warning})>
  getAvailableModelsWithWarning() async => (
    models: <Map<String, dynamic>>[
      {
        'id': 'luna-fixture',
        'name': 'Luna fixture',
        'provider': 'fixture',
        'contextWindow': modelMaximum,
        'cost': {
          'tiers': [
            {'inputTokensAbove': 272000},
          ],
        },
      },
    ],
    warning: null,
  );
  @override
  Future<List<String>> getAvailableThinkingLevels() async => ['medium'];
  @override
  Future<void> setContextWindow(int? size) async {
    if (pendingContext != null) await pendingContext!.future;
    if (failContext) throw StateError('context rejected');
    state = state.copyWith(
      contextWindowOverride: size,
      clearContextWindowOverride: size == null,
    );
  }

  @override
  Future<void> setCompactionReservePercent(double percent) async {
    if (failReserve) throw StateError('reserve rejected');
    state = state.copyWith(compactionReservePercent: percent);
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final font in ['SchibstedGrotesk', 'SourceCodePro']) {
      await (FontLoader(
        font,
      )..addFont(rootBundle.load('assets/fonts/$font.ttf'))).load();
    }
    await (FontLoader('BarlowCondensed')
          ..addFont(rootBundle.load('assets/fonts/BarlowCondensed-Bold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  Future<void> capturePanel(
    WidgetTester tester,
    GlobalKey key,
    String name,
  ) async {
    if (Platform.environment['PIFRAME_CAPTURE_CONTEXT_POLICY'] != '1') return;
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('../../docs/design-evidence/$name');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> mount(
    WidgetTester tester,
    _PanelSession session,
    GlobalKey capture, {
    bool? customMode,
  }) async {
    tester.view.physicalSize = const Size(440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        key: ObjectKey(session),
        overrides: [
          daemonEndpointProvider.overrideWith((ref) async => null),
          sessionStateFamily('policy-fixture').overrideWith((ref) => session),
          customContextModeProvider('policy-fixture')
              .overrideWith((ref) => customMode),
        ],
        child: MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            fontFamily: 'SchibstedGrotesk',
            extensions: const [FrameTokens.dark],
          ),
          home: RepaintBoundary(
            key: capture,
            child: const Scaffold(
              body: Center(child: ContextPanel(sessionId: 'policy-fixture')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'preset hides custom; Custom snaps to 50k and reveals bounded slider',
    (tester) async {
      final session = _PanelSession();
      final capture = GlobalKey();
      await mount(tester, session, capture);
      await capturePanel(tester, capture, 'context-policy-presets-fixture.png');
      expect(
        find.byKey(const ValueKey('context-window-custom-slider')),
        findsNothing,
      );
      final dropdown = find.byKey(
        const ValueKey('context-window-preset-dropdown'),
      );
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      expect(find.text('Personalizzato').last, findsOneWidget);
      await tester.tap(find.text('Personalizzato').last);
      await tester.pumpAndSettle();
      expect(session.state.contextWindowOverride, 250000);
      expect(
        find.byKey(const ValueKey('context-window-custom-slider')),
        findsOneWidget,
      );
      expect(
        find.textContaining('250k token (250000 token esatti)'),
        findsOneWidget,
      );

      final capped = _PanelSession(override: 263000, modelMaximum: 263000);
      await mount(tester, capped, GlobalKey());
      await tester.tap(
        find.byKey(const ValueKey('context-window-preset-dropdown')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Personalizzato').last);
      await tester.pumpAndSettle();
      expect(capped.state.contextWindowOverride, 250000);
      final slider = tester.widget<Slider>(
        find.byKey(const ValueKey('context-window-custom-slider')),
      );
      expect(slider.max, 250000);
      expect(slider.max, lessThanOrEqualTo(263000));
    },
  );

  testWidgets(
    'custom drag uses 50k steps, commits only on release and restores failures',
    (tester) async {
      final session = _PanelSession(override: 500000);
      await mount(tester, session, GlobalKey(), customMode: true);
      final finder = find.byKey(const ValueKey('context-window-custom-slider'));
      final slider = tester.widget<Slider>(finder);
      expect(slider.min, 100000);
      expect(slider.max, 1000000);
      expect(slider.divisions, 18);
      final gesture = await tester.startGesture(tester.getCenter(finder));
      await gesture.moveBy(const Offset(70, 0));
      await tester.pump();
      expect(session.state.contextWindowOverride, 500000);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(session.state.contextWindowOverride! % 50000, 0);
      expect(session.state.contextWindowOverride, greaterThanOrEqualTo(100000));
      expect(session.state.contextWindowOverride, lessThanOrEqualTo(1000000));
      final accepted = session.state.contextWindowOverride;
      session.failContext = true;
      await tester.drag(finder, const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(session.state.contextWindowOverride, accepted);
      expect(tester.widget<Slider>(finder).value, accepted!.toDouble());
      expect(find.textContaining('Limite non applicato'), findsOneWidget);
    },
  );

  testWidgets(
    'failed Custom selection stays on its accepted tier; small models cannot exceed capacity',
    (tester) async {
      final session = _PanelSession()..failContext = true;
      await mount(tester, session, GlobalKey());
      await tester.tap(
        find.byKey(const ValueKey('context-window-preset-dropdown')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Personalizzato').last);
      await tester.pumpAndSettle();
      expect(session.state.contextWindowOverride, 272000);
      expect(
        find.byKey(const ValueKey('context-window-custom-slider')),
        findsNothing,
      );
      expect(find.textContaining('Limite non applicato'), findsOneWidget);
      final small = _PanelSession(override: 64000, modelMaximum: 64000);
      await mount(tester, small, GlobalKey());
      final dropdown = tester.widget<DropdownButton<Object>>(
        find.byKey(const ValueKey('context-window-preset-dropdown')),
      );
      expect(dropdown.items!.first.enabled, isFalse);
      expect(
        find.byKey(const ValueKey('context-window-custom-slider')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'one policy save disables both controls until the backend replies',
    (tester) async {
      final session = _PanelSession()..pendingContext = Completer<void>();
      await mount(tester, session, GlobalKey());
      await tester.tap(
        find.byKey(const ValueKey('context-window-preset-dropdown')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Personalizzato').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Slider>(
              find.byKey(
                const ValueKey('context-panel-compaction-reserve-slider'),
              ),
            )
            .onChanged,
        isNull,
      );
      expect(
        tester
            .widget<DropdownButton<Object>>(
              find.byKey(const ValueKey('context-window-preset-dropdown')),
            )
            .onChanged,
        isNull,
      );
      expect(session.state.contextWindowOverride, 272000);
      session.pendingContext!.complete();
      await tester.pumpAndSettle();
      expect(session.state.contextWindowOverride, 250000);
      expect(
        tester
            .widget<Slider>(
              find.byKey(
                const ValueKey('context-panel-compaction-reserve-slider'),
              ),
            )
            .onChanged,
        isNotNull,
      );
    },
  );

  testWidgets('reserve slider uses 0.5% steps through 25%', (tester) async {
    final session = _PanelSession(override: null);
    await mount(tester, session, GlobalKey());
    final finder = find.byKey(
      const ValueKey('context-panel-compaction-reserve-slider'),
    );
    final slider = tester.widget<Slider>(finder);
    expect(slider.min, 0.5);
    expect(slider.max, 25);
    expect(slider.divisions, 49);
    await tester.drag(finder, const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(session.state.compactionReservePercent, 0.5);
    await tester.drag(finder, const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(session.state.compactionReservePercent, 25);
  });

  testWidgets(
    'errors preserve accepted values; read-only and busy disable controls',
    (tester) async {
      final session = _PanelSession(readOnly: true);
      await mount(tester, session, GlobalKey());
      expect(
        tester
            .widget<DropdownButton<Object>>(
              find.byKey(const ValueKey('context-window-preset-dropdown')),
            )
            .onChanged,
        isNull,
      );
      expect(
        tester
            .widget<Slider>(
              find.byKey(
                const ValueKey('context-panel-compaction-reserve-slider'),
              ),
            )
            .onChanged,
        isNull,
      );

      final busy = _PanelSession(busy: true);
      await mount(tester, busy, GlobalKey(), customMode: true);
      expect(
        tester
            .widget<Slider>(
              find.byKey(const ValueKey('context-window-custom-slider')),
            )
            .onChanged,
        isNull,
      );

      final failing = _PanelSession(override: null)..failReserve = true;
      await mount(tester, failing, GlobalKey());
      final reserveSlider = find.byKey(
        const ValueKey('context-panel-compaction-reserve-slider'),
      );
      await tester.drag(reserveSlider, const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(failing.state.compactionReservePercent, 2.5);
      expect(find.textContaining('Margine non applicato'), findsOneWidget);
    },
  );

  testWidgets(
    'shows runtime context usage, not token totals, and captures real fixture',
    (tester) async {
      final session = _PanelSession(override: 750000);
      final capture = GlobalKey();
      await mount(tester, session, capture, customMode: true);
      expect(find.text('70656 / 750k token'), findsOneWidget);
      expect(find.text('9.4 %'), findsOneWidget);
      expect(find.textContaining('42,000'), findsNothing);
      expect(find.text('Personalizzato'), findsOneWidget);
      expect(
        find.textContaining('750k token (750000 token esatti)'),
        findsOneWidget,
      );
      await capturePanel(tester, capture, 'context-policy-panel-fixture.png');
    },
  );

  testWidgets(
    'legacy reserve outside slider range is explicit and never silently rewritten',
    (tester) async {
      final session = _PanelSession();
      session.state = session.state.copyWith(compactionReservePercent: 50);
      await mount(tester, session, GlobalKey());
      final slider = tester.widget<Slider>(
        find.byKey(const ValueKey('context-panel-compaction-reserve-slider')),
      );
      expect(slider.value, 25);
      expect(find.text('25.0%'), findsOneWidget);
      expect(
        find.textContaining('Margine salvato fuori intervallo: 50.0%'),
        findsOneWidget,
      );
      expect(session.state.compactionReservePercent, 50);
    },
  );

  testWidgets('automatic-compaction explanation follows Pi state', (
    tester,
  ) async {
    await mount(tester, _PanelSession(auto: false), GlobalKey());
    expect(
      find.text('Compattazione automatica disabilitata in Pi.'),
      findsOneWidget,
    );
  });
}
