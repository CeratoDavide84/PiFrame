import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/tool_timeline/tool_card.dart';

void main() {
  Widget wrapWithTheme(Widget child) {
    return MaterialApp(
      theme: ThemeData.dark().copyWith(
        extensions: const [FrameTokens.dark],
      ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );
  }

  group('ToolCard expanded command and seconds counter tests', () {
    testWidgets('shows full bash command when expanded and copy action', (tester) async {
      const veryLongCommand =
          'pnpm --filter @piframe/agentd run build --mode=production --target=node20 --minify=true --sourcemap=false';

      const tool = ToolExecutionState(
        toolCallId: 'bash_call_1',
        toolName: 'bash',
        args: {'command': veryLongCommand, 'timeout': 30},
        output: 'Build completed in 1.4s',
        isRunning: false,
        durationMs: 1400,
      );

      await tester.pumpWidget(wrapWithTheme(const ToolCard(tool: tool)));

      // Initially collapsed: header shows bash
      expect(find.text('bash'), findsOneWidget);
      // Timeout badge in header
      expect(find.byKey(const ValueKey('tool-card-timeout-badge')), findsOneWidget);
      expect(find.text('timeout 30s'), findsOneWidget);

      // Expand the card
      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();

      // Full command should be present in the expanded command box
      final expandedBox = find.byKey(const ValueKey('tool-card-expanded-command'));
      expect(expandedBox, findsOneWidget);
      expect(find.descendant(of: expandedBox, matching: find.text(veryLongCommand)), findsOneWidget);
      expect(find.text('Comando lanciato'), findsOneWidget);
      expect(find.text('Copy command'), findsOneWidget);
      // Timeout badge in expanded header
      expect(find.byKey(const ValueKey('tool-card-expanded-timeout')), findsOneWidget);
      expect(find.text('Timeout richiesto: 30s'), findsOneWidget);
      // Output is also visible
      expect(find.text('Build completed in 1.4s'), findsOneWidget);
    });

    testWidgets('shows seconds counter when tool takes 5 seconds or more', (tester) async {
      const tool = ToolExecutionState(
        toolCallId: 'long_call_1',
        toolName: 'terminal',
        args: {'command': 'sleep 8', 'timeout': 60},
        output: 'done',
        isRunning: false,
        durationMs: 8200, // 8.2 seconds
      );

      await tester.pumpWidget(wrapWithTheme(const ToolCard(tool: tool)));

      // Over 5 seconds counter badge should be visible
      expect(find.byKey(const ValueKey('tool-card-seconds-counter')), findsOneWidget);
      expect(find.text('8s'), findsOneWidget);
      expect(find.text(' / 60s'), findsOneWidget);
    });

    testWidgets('can expand bash tool card even if output is empty', (tester) async {
      const tool = ToolExecutionState(
        toolCallId: 'empty_out_1',
        toolName: 'bash',
        args: {'command': 'mkdir -p foo/bar'},
        output: '',
        isRunning: false,
      );

      await tester.pumpWidget(wrapWithTheme(const ToolCard(tool: tool)));

      // Card should be expandable because commandText is present
      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();

      final expandedBox = find.byKey(const ValueKey('tool-card-expanded-command'));
      expect(expandedBox, findsOneWidget);
      expect(find.descendant(of: expandedBox, matching: find.text('mkdir -p foo/bar')), findsOneWidget);
    });
  });
}
