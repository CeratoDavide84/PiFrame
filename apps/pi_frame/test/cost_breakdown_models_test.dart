import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/features/transcript/subagents_provider.dart';
import 'package:pi_frame/features/transcript/transcript_view.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class _EmptySubagentsNotifier extends SubagentsNotifier {
  _EmptySubagentsNotifier(super.ref, super.sessionId) {
    state = const [];
  }
}

void main() {
  testWidgets('Cost breakdown dialog displays all models used during session with costs and tokens', (tester) async {
    const sessionId = 'session_multi_model_cost';

    final sessionState = SessionState(
      sessionId: sessionId,
      sessionName: 'New Camera Plugin',
      cwd: 'C:/repos/plugin',
      currentModel: 'github-copilot/gpt-6.1-sol',
      sessionStats: {
        'cost': 79.223,
        'byModel': {
          'github-copilot/gpt-6.1-sol': {
            'cost': 46.818,
            'tokens': {'total': 100000000},
          },
          'github-copilot/claude-haiku-5-5': {
            'cost': 27.539,
            'tokens': {'total': 356000000},
          },
          'github-copilot/gpt-6-luna': {
            'cost': 3.683,
            'tokens': {'total': 173000000},
          },
          'Tools/summaries': {
            'cost': 1.183,
            'tokens': {'total': 43000000},
          },
        },
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStateFamily(sessionId).overrideWith(
            (ref) => SessionStateNotifier(sessionId, null)..state = sessionState,
          ),
          subagentsFamily(sessionId).overrideWith(
            (ref) => _EmptySubagentsNotifier(ref, sessionId),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [FrameTokens.dark],
          ),
          home: const Scaffold(
            body: TranscriptView(sessionId: sessionId),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify header cost display
    expect(find.textContaining('\$79.2230'), findsOneWidget);

    // Tap Cost chip to open breakdown dialog
    await tester.tap(find.textContaining('\$79.2230'));
    await tester.pumpAndSettle();

    // Dialog Level 0 Overview
    expect(find.text('Dettaglio Costi Sessione'), findsOneWidget);
    expect(find.byKey(const ValueKey('cost-breakdown-agent-row')), findsOneWidget);

    // Click on Agent cost row to open Level 1 (Agent Models)
    await tester.tap(find.byKey(const ValueKey('cost-breakdown-agent-row')));
    await tester.pumpAndSettle();

    // Dialog Level 1: Agent Models
    expect(find.text('Costi Modelli Agente'), findsOneWidget);
    expect(find.text('Costo riportato da Pi'), findsOneWidget);

    // Check all models and their costs
    expect(find.text('github-copilot/gpt-6.1-sol'), findsOneWidget);
    expect(find.text('\$46.8180'), findsOneWidget);
    expect(find.text('100.0M tokens'), findsOneWidget);

    expect(find.text('github-copilot/claude-haiku-5-5'), findsOneWidget);
    expect(find.text('\$27.5390'), findsOneWidget);
    expect(find.text('356.0M tokens'), findsOneWidget);

    expect(find.text('github-copilot/gpt-6-luna'), findsOneWidget);
    expect(find.text('\$3.6830'), findsOneWidget);
    expect(find.text('173.0M tokens'), findsOneWidget);

    expect(find.text('Tools/summaries'), findsOneWidget);
    expect(find.text('\$1.1830'), findsOneWidget);
    expect(find.text('43.0M tokens'), findsOneWidget);
  });

  testWidgets('Cost breakdown aggregates per-model costs from session entries when byModel is not in stats', (tester) async {
    const sessionId = 'session_entries_cost';

    final sessionState = SessionState(
      sessionId: sessionId,
      sessionName: 'Entries Cost Test',
      cwd: 'C:/repos/test',
      currentModel: 'model-b',
      entries: const [
        SessionEntry(
          id: 'msg1',
          role: 'assistant',
          text: 'Response from model-a',
          timestamp: 1000,
          metadata: {
            'model': 'model-a',
            'usage': {
              'cost': 0.015,
              'tokens': {'total': 15000},
            },
          },
        ),
        SessionEntry(
          id: 'msg2',
          role: 'assistant',
          text: 'Response from model-b',
          timestamp: 2000,
          metadata: {
            'model': 'model-b',
            'usage': {
              'cost': 0.025,
              'tokens': {'total': 25000},
            },
          },
        ),
      ],
      usage: const {
        'cost': 0.040,
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStateFamily(sessionId).overrideWith(
            (ref) => SessionStateNotifier(sessionId, null)..state = sessionState,
          ),
          subagentsFamily(sessionId).overrideWith(
            (ref) => _EmptySubagentsNotifier(ref, sessionId),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [FrameTokens.dark],
          ),
          home: const Scaffold(
            body: TranscriptView(sessionId: sessionId),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Tap Cost chip
    await tester.tap(find.textContaining('\$0.0400'));
    await tester.pumpAndSettle();

    // Navigate to Level 1
    await tester.tap(find.byKey(const ValueKey('cost-breakdown-agent-row')));
    await tester.pumpAndSettle();

    expect(find.text('Costi Modelli Agente'), findsOneWidget);
    expect(find.text('model-a'), findsOneWidget);
    expect(find.text('\$0.0150'), findsOneWidget);
    expect(find.text('15.0k tokens'), findsOneWidget);

    expect(find.text('model-b'), findsOneWidget);
    expect(find.text('\$0.0250'), findsOneWidget);
    expect(find.text('25.0k tokens'), findsOneWidget);
  });
}
