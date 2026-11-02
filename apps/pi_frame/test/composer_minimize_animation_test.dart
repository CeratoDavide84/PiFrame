import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/features/composer/composer.dart';
import 'package:pi_frame/features/transcript/transcript_view.dart';
import 'package:pi_frame/features/composer/composer_draft.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

void main() {
  Widget wrapComposer({required SessionState state}) {
    return ProviderScope(
      overrides: [
        sessionStateFamily('s_min_test').overrideWith(
          (ref) => SessionStateNotifier('s_min_test', null)..state = state,
        ),
      ],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
        home: const Scaffold(
          body: Column(
            children: [
              Expanded(child: SizedBox()),
              Composer(sessionId: 's_min_test'),
            ],
          ),
        ),
      ),
    );
  }

  group('Composer minimize and maximize behavior when agent is answering', () {
    testWidgets('minimizes chat input window when agent is streaming / answering', (tester) async {
      final state = const SessionState(
        sessionId: 's_min_test',
        cwd: '/test',
        agentStatus: AgentStatus.working,
        streamingTextBlocks: {0: 'Generating answer...'},
      );

      await tester.pumpWidget(wrapComposer(state: state));
      await tester.pump(const Duration(milliseconds: 300));

      // Should be minimized with compact bar
      expect(find.byKey(const ValueKey('composer-minimized-bar')), findsOneWidget);
      expect(find.textContaining('L\'agente sta rispondendo'), findsOneWidget);
      // The full text field input area is minimized
      expect(find.byKey(const ValueKey('composer-input-area')), findsNothing);
    });

    testWidgets('hides and restores unsent draft while an agent question is pending', (tester) async {
      const draft = 'Keep this unfinished message';
      final notifier = SessionStateNotifier('s_min_test', null)
        ..state = const SessionState(
          sessionId: 's_min_test',
          cwd: '/test',
          agentStatus: AgentStatus.working,
          streamingTextBlocks: {0: 'Waiting for an answer...'},
        );
      final container = ProviderContainer(
        overrides: [
          sessionStateFamily('s_min_test').overrideWith((ref) => notifier),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: const [FrameTokens.dark],
            ),
            home: const Scaffold(
              body: Column(
                children: [
                  Expanded(child: SizedBox()),
                  Composer(sessionId: 's_min_test'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-minimized-bar')));
      await tester.pumpAndSettle();
      final composerField = find.byKey(const ValueKey('composer-text-field'));
      await tester.enterText(composerField, draft);
      await tester.pump();
      expect(container.read(composerDraftProvider('s_min_test')), draft);

      notifier.state = notifier.state.copyWith(
        agentStatus: AgentStatus.awaitingUser,
        streamingTextBlocks: const {},
        pendingUiRequests: const [
          {
            'requestId': 'question-1',
            'method': 'select',
            'dialog': true,
            'title': 'Choose an option',
            'options': ['Yes', 'No'],
          },
        ],
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('composer-extension-ui-card')), findsOneWidget);
      expect(find.byKey(const ValueKey('composer-input-area')), findsNothing);
      expect(composerField, findsNothing);
      expect(find.byKey(const ValueKey('composer-send-btn')), findsNothing);
      tester.testTextInput.enterText('This must not replace the draft');
      await tester.pump();
      expect(container.read(composerDraftProvider('s_min_test')), draft);

      notifier.state = notifier.state.copyWith(
        agentStatus: AgentStatus.working,
        pendingUiRequests: const [],
        streamingTextBlocks: const {0: 'Continuing after the answer...'},
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('composer-input-area')), findsOneWidget);
      expect(tester.widget<TextField>(composerField).controller!.text, draft);
      expect(container.read(composerDraftProvider('s_min_test')), draft);
    });

    testWidgets('shows glowing pointer effect and keeps chat input window minimized during hover < 5s, then expands at >= 5s', (tester) async {
      final state = const SessionState(
        sessionId: 's_min_test',
        cwd: '/test',
        agentStatus: AgentStatus.working,
        streamingTextBlocks: {0: 'Generating answer...'},
      );

      await tester.pumpWidget(wrapComposer(state: state));
      await tester.pump(const Duration(milliseconds: 300));

      // Initially minimized
      expect(find.byKey(const ValueKey('composer-minimized-bar')), findsOneWidget);

      // Simulate mouse hover
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(Composer)));
      await tester.pump(const Duration(milliseconds: 300));

      // At 300ms hover, it is STILL minimized (with glowing pointer effect)!
      expect(find.byKey(const ValueKey('composer-minimized-bar')), findsOneWidget);
      expect(find.byKey(const ValueKey('composer-input-area')), findsNothing);

      // After 5 seconds of keeping pointer over it, it expands
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 350));

      // Now maximized: full text field and steer/interrupt controls are visible
      expect(find.byKey(const ValueKey('composer-input-area')), findsOneWidget);
      expect(find.text('Steer'), findsOneWidget);

      // Moving mouse away: during grace period (300ms) it stays open
      await gesture.moveTo(const Offset(10, 10)); // outside composer
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('composer-input-area')), findsOneWidget);
      expect(find.byKey(const ValueKey('composer-minimized-bar')), findsNothing);

      // After grace period (600ms + animation) expires, it minimizes back
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byKey(const ValueKey('composer-minimized-bar')), findsOneWidget);
    });

    testWidgets('expands chat input window immediately when user clicks on minimized bar', (tester) async {
      final state = const SessionState(
        sessionId: 's_min_test',
        cwd: '/test',
        agentStatus: AgentStatus.working,
        streamingTextBlocks: {0: 'Generating answer...'},
      );

      await tester.pumpWidget(wrapComposer(state: state));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const ValueKey('composer-minimized-bar')), findsOneWidget);

      // Tap on minimized bar expands immediately
      await tester.tap(find.byKey(const ValueKey('composer-minimized-bar')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('composer-input-area')), findsOneWidget);
    });

    testWidgets('minimized chat interrupt button and text use signalDanger color matching maximized stop button', (tester) async {
      final state = const SessionState(
        sessionId: 's_min_test',
        cwd: '/test',
        agentStatus: AgentStatus.working,
        streamingTextBlocks: {0: 'Generating answer...'},
      );

      await tester.pumpWidget(wrapComposer(state: state));
      await tester.pump(const Duration(milliseconds: 300));

      final interruptIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey('composer-minimized-interrupt')),
          matching: find.byIcon(Icons.stop_circle_outlined),
        ),
      );
      final interruptText = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('composer-minimized-interrupt')),
          matching: find.text('Interrompi'),
        ),
      );

      expect(interruptIcon.color, FrameTokens.dark.signalDanger);
      expect(interruptText.style?.color, FrameTokens.dark.signalDanger);
    });

    testWidgets('does not minimize if text has been inputted even if user clicks away while model is generating', (tester) async {
      // Start with settled session
      var sessionNotifier = SessionStateNotifier('s_min_test', null)
        ..state = const SessionState(
          sessionId: 's_min_test',
          cwd: '/test',
          agentStatus: AgentStatus.settled,
        );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionStateFamily('s_min_test').overrideWith((ref) => sessionNotifier),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
            home: const Scaffold(
              body: Column(
                children: [
                  Expanded(child: SizedBox()),
                  Composer(sessionId: 's_min_test'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter some text into the composer
      await tester.enterText(find.byKey(const ValueKey('composer-text-field')), 'I have written some instructions here');
      await tester.pumpAndSettle();

      // User unfocuses / clicks away (e.g. tap elsewhere)
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      // Model starts generating / answering
      sessionNotifier.state = sessionNotifier.state.copyWith(
        agentStatus: AgentStatus.working,
        streamingTextBlocks: {0: 'Generating answer while text was entered...'},
      );
      // Wait past any grace periods / animations
      await tester.pump(const Duration(milliseconds: 1000));

      // Should NOT be minimized because the user wrote text!
      expect(find.byKey(const ValueKey('composer-input-area')), findsOneWidget);
      expect(find.byKey(const ValueKey('composer-minimized-bar')), findsNothing);
      expect(find.text('I have written some instructions here'), findsOneWidget);
    });

    testWidgets('does not minimize if the input box is focused', (tester) async {
      // Start with settled session
      var sessionNotifier = SessionStateNotifier('s_min_test', null)
        ..state = const SessionState(
          sessionId: 's_min_test',
          cwd: '/test',
          agentStatus: AgentStatus.settled,
        );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionStateFamily('s_min_test').overrideWith((ref) => sessionNotifier),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
            home: const Scaffold(
              body: Column(
                children: [
                  Expanded(child: SizedBox()),
                  Composer(sessionId: 's_min_test'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Focus the text field
      await tester.tap(find.byKey(const ValueKey('composer-text-field')));
      await tester.pumpAndSettle();

      // Now agent starts answering / working
      sessionNotifier.state = sessionNotifier.state.copyWith(
        agentStatus: AgentStatus.working,
        streamingTextBlocks: {0: 'Streaming while focused...'},
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Because input box is focused, it should NOT minimize!
      expect(find.byKey(const ValueKey('composer-input-area')), findsOneWidget);
      expect(find.byKey(const ValueKey('composer-minimized-bar')), findsNothing);
    });

    testWidgets('transcript scroll stays locked and scrolls synchronously as composer expands', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      final entries = List.generate(
        30,
        (i) => SessionEntry(
          id: 'e_$i',
          role: i.isEven ? 'user' : 'assistant',
          text: 'Message $i with extra content lines to fill height\nLine 2\nLine 3',
          timestamp: 1000 + i,
        ),
      );

      final sessionNotifier = SessionStateNotifier('s_sync', null)
        ..state = SessionState(
          sessionId: 's_sync',
          cwd: '/test',
          agentStatus: AgentStatus.settled,
          entries: entries,
        );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            daemonEndpointProvider.overrideWith((ref) async => null),
            sessionStateFamily('s_sync').overrideWith((ref) => sessionNotifier),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
            home: const Scaffold(
              body: Column(
                children: [
                  Expanded(child: TranscriptView(sessionId: 's_sync')),
                  Composer(sessionId: 's_sync'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollController = tester.widget<ListView>(find.byKey(const ValueKey('transcript-scroll'))).controller!;
      final initialOffset = scrollController.offset;
      final initialMax = scrollController.position.maxScrollExtent;
      expect((initialMax - initialOffset).abs(), lessThan(5.0));

      // Now agent starts working -> composer minimizes
      sessionNotifier.state = sessionNotifier.state.copyWith(
        agentStatus: AgentStatus.working,
        streamingTextBlocks: {0: 'Thinking...'},
      );
      await tester.pumpAndSettle();

      // Minimized bar is visible
      expect(find.byKey(const ValueKey('composer-minimized-bar')), findsOneWidget);
      final minimizedOffset = scrollController.offset;
      final minimizedMax = scrollController.position.maxScrollExtent;
      expect((minimizedMax - minimizedOffset).abs(), lessThan(5.0));

      // Tap to expand
      await tester.tap(find.byKey(const ValueKey('composer-minimized-bar')));

      // Pump mid-animation frame (140ms into 280ms)
      await tester.pump(const Duration(milliseconds: 140));
      final midOffset = scrollController.offset;
      final midMax = scrollController.position.maxScrollExtent;
      // During expansion, scroll position stays glued to the bottom without snapping
      expect((midMax - midOffset).abs(), lessThan(5.0));

      // Complete expansion
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('composer-input-area')), findsOneWidget);
      final finalOffset = scrollController.offset;
      final finalMax = scrollController.position.maxScrollExtent;
      expect((finalMax - finalOffset).abs(), lessThan(5.0));
      expect(finalOffset, greaterThanOrEqualTo(midOffset));
    });
  });
}

