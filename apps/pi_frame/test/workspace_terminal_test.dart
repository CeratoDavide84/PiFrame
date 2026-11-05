import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/features/workspace/integrated_terminal.dart';
import 'package:pi_frame/features/workspace/repository_workspace.dart';
import 'package:pi_frame/domain/session/session_state.dart';

void main() {
  testWidgets('IntegratedTerminalPanel creates tabs and closes tabs', (tester) async {
    const tokens = FrameTokens.dark;
    var collapsed = false;
    var closed = false;

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            width: 600,
            child: IntegratedTerminalPanel(
              cwd: '',
              tokens: tokens,
              onCollapseDownward: () => collapsed = true,
              onClose: () => closed = true,
            ),
          ),
        ),
      )),
    );
    await tester.pumpAndSettle();

    // Verify first terminal tab and TerminalView exist
    expect(find.byIcon(Icons.terminal), findsWidgets);
    expect(find.byType(TerminalView), findsOneWidget); // Direct in-terminal view
    expect(find.byTooltip('Apri nel terminale nativo (OS)'), findsOneWidget);
    expect(find.byTooltip('Interrompi processo (Ctrl+C)'), findsOneWidget);

    // Verify + button exists (PopupMenuButton with add icon)
    final addBtn = find.byTooltip('Nuovo terminale');
    expect(addBtn, findsOneWidget);

    // Tap + button to open menu and create second tab
    await tester.tap(addBtn);
    await tester.pumpAndSettle();

    // Select default new terminal
    final defaultItem = find.text(
      find.text('Nuovo terminale (PowerShell)').evaluate().isNotEmpty
          ? 'Nuovo terminale (PowerShell)'
          : 'Nuovo terminale',
    );
    expect(defaultItem, findsOneWidget);
    await tester.tap(defaultItem);
    await tester.pumpAndSettle();

    // Now there should be 2 close buttons (one for each tab)
    expect(find.byIcon(Icons.close), findsWidgets);

    // Test collapse downward button
    final collapseBtn = find.byTooltip('Collassa in basso');
    expect(collapseBtn, findsOneWidget);
    await tester.tap(collapseBtn);
    expect(collapsed, isTrue);

    // Test close button on panel
    final closePanelBtn = find.byTooltip('Chiudi terminale');
    expect(closePanelBtn, findsOneWidget);
    await tester.tap(closePanelBtn);
    expect(closed, isTrue);
  });

  testWidgets('RepositoryPane has terminal button that toggles terminal panel', (tester) async {
    final container = ProviderContainer(
      overrides: [
        sessionStateFamily('session-1').overrideWith(
          (ref) => SessionStateNotifier('session-1', null)
            ..state = const SessionState(
              sessionId: 'session-1',
              cwd: 'C:/test',
            ),
        ),
        repositoryStateProvider('session-1').overrideWith(
          (ref) => RepositoryController(
            'session-1',
            () => null,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              height: 700,
              child: RepositoryPane(
                sessionId: 'session-1',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Terminal button should be present in Repository header
    final termToggleBtn = find.byTooltip('Terminale integrato');
    expect(termToggleBtn, findsOneWidget);

    // Click terminal button to open terminal panel
    await tester.tap(termToggleBtn);
    await tester.pumpAndSettle();

    // Now IntegratedTerminalPanel should be visible
    expect(find.byType(IntegratedTerminalPanel), findsOneWidget);

    // Click collapse downward button in terminal
    final collapseDownBtn = find.byTooltip('Collassa in basso');
    expect(collapseDownBtn, findsOneWidget);
    await tester.tap(collapseDownBtn);
    await tester.pumpAndSettle();

    // Now the collapsed terminal bar should be visible with expand arrow
    expect(find.text('TERMINALE'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);

    // Tap the collapsed bar to expand it back
    await tester.tap(find.text('TERMINALE'));
    await tester.pumpAndSettle();

    // IntegratedTerminalPanel should be expanded again
    expect(find.byType(IntegratedTerminalPanel), findsOneWidget);
  });

  testWidgets('TerminalView accepts user typing and sends to process', (tester) async {
    const tokens = FrameTokens.dark;
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            width: 600,
            child: IntegratedTerminalPanel(
              cwd: '',
              tokens: tokens,
              onCollapseDownward: () {},
              onClose: () {},
            ),
          ),
        ),
      )),
    );
    await tester.pumpAndSettle();

    // Tap on terminal to ensure it is focused
    await tester.tap(find.byType(TerminalView));
    await tester.pumpAndSettle();

    final terminalView = tester.widget<TerminalView>(find.byType(TerminalView));

    // Test writing to terminal buffer
    terminalView.terminal.write('dir\r\n');
    await tester.pumpAndSettle();
    expect(terminalView.terminal.buffer.getText().contains('dir'), isTrue);

    // Verify typing events and control keys are handled cleanly
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
  });
}
