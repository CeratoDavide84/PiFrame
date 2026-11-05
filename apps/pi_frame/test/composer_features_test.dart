import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/features/composer/composer.dart';
import 'package:pi_frame/features/composer/copilot_file_picker.dart';
import 'package:pi_frame/features/composer/file_mention_menu.dart';
import 'package:pi_frame/features/workspace/repository_workspace.dart';
import 'package:pi_frame/ui/code/syntax_highlighter.dart';
import 'package:pi_frame/ui/shimmer_border.dart';

class _FakeRepoController extends RepositoryController {
  _FakeRepoController() : super('test-session', () => null) {
    state = const RepositoryState(
      files: [
        {'path': 'lib/main.dart', 'sizeBytes': 1024},
        {'path': 'lib/app.dart', 'sizeBytes': 2048},
        {'path': 'test/widget_test.dart', 'sizeBytes': 512},
      ],
    );
  }
}

void main() {
  Widget wrapWithTheme(Widget child, {List<Override> overrides = const []}) {
    return ProviderScope(
      overrides: [
        daemonEndpointProvider.overrideWith((ref) async => null),
        activeSessionIdProvider.overrideWith((ref) => 'test-session'),
        repositoryStateProvider('test-session').overrideWith(
          (ref) => _FakeRepoController(),
        ),
        ...overrides,
      ],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(
          extensions: const [FrameTokens.dark],
        ),
        home: Scaffold(body: child),
      ),
    );
  }

  group('Composer @ Mention & Copilot Picker', () {
    testWidgets('FileMentionMenu renders matching files and handles selection', (tester) async {
      String? selected;
      final files = [
        {'path': 'lib/main.dart', 'sizeBytes': 1024},
        {'path': 'lib/app.dart', 'sizeBytes': 2048},
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
          home: Scaffold(
            body: FileMentionMenu(
              files: files,
              query: 'main',
              selectedIndex: 0,
              onSelect: (path) => selected = path,
            ),
          ),
        ),
      );

      expect(find.text('main.dart'), findsOneWidget);
      expect(find.text('lib'), findsNWidgets(2));
      expect(find.text('Collega file (@)'), findsOneWidget);

      await tester.tap(find.text('main.dart'));
      expect(selected, 'lib/main.dart');
    });

    testWidgets('CopilotFilePicker filters files by search and selects mention', (tester) async {
      CopilotFileResult? result;
      final files = [
        {'path': 'lib/main.dart', 'sizeBytes': 1024},
        {'path': 'lib/app.dart', 'sizeBytes': 2048},
        {'path': 'test/app_test.dart', 'sizeBytes': 512},
      ];

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () async {
                    result = await CopilotFilePicker.show(ctx, files: files);
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Aggiungi contesto alla chat'), findsOneWidget);
      expect(find.text('3 file trovati'), findsOneWidget);

      // Search for app
      await tester.enterText(find.byType(TextField), 'app');
      await tester.pumpAndSettle();

      expect(find.text('2 file trovati'), findsOneWidget);
      expect(find.text('lib/app.dart'), findsOneWidget);

      // Select mention via Collega @ button
      await tester.tap(find.text('Collega @').first);
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.path, 'lib/app.dart');
      expect(result!.action, CopilotFileActionType.mention);
    });

    testWidgets('Typing @ in Composer activates file mention menu', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(const Composer(sessionId: 'test-session')),
      );
      await tester.pumpAndSettle();

      // Enter text with @lib
      await tester.enterText(find.byType(TextField), 'Please check @lib');
      await tester.pumpAndSettle();

      // Mention menu should be visible
      expect(find.byType(FileMentionMenu), findsOneWidget);
      expect(find.text('main.dart'), findsOneWidget);

      // Press Tab to complete
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      // Should complete to @lib/main.dart and close menu
      expect(find.byType(FileMentionMenu), findsNothing);
      expect(find.textContaining('@lib/main.dart'), findsOneWidget);
    });
  });

  group('ShimmerBorder', () {
    testWidgets('ShimmerBorder renders static border when inactive and animated painter when active', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
          home: const Scaffold(
            body: ShimmerBorder(
              isActive: false,
              borderRadius: BorderRadius.all(Radius.circular(8)),
              child: SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      );

      final borderPaint = find.descendant(
        of: find.byType(ShimmerBorder),
        matching: find.byType(CustomPaint),
      );

      expect(borderPaint, findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
          home: const Scaffold(
            body: ShimmerBorder(
              isActive: true,
              borderRadius: BorderRadius.all(Radius.circular(8)),
              child: SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      );

      expect(borderPaint, findsOneWidget);
    });
  });

  group('SyntaxHighlighter', () {
    test('inferLanguage maps extensions accurately', () {
      expect(SyntaxHighlighter.inferLanguage('main.dart'), 'dart');
      expect(SyntaxHighlighter.inferLanguage('app.tsx'), 'typescript');
      expect(SyntaxHighlighter.inferLanguage('script.py'), 'python');
      expect(SyntaxHighlighter.inferLanguage('data.json'), 'json');
      expect(SyntaxHighlighter.inferLanguage('unknown'), 'text');
    });

    test('highlight tokenizes keywords, strings, and types', () {
      const tokens = FrameTokens.dark;
      final span = SyntaxHighlighter.highlight(
        'final x = "hello"; // comment\nclass User {}',
        'dart',
        tokens,
      );

      expect(span.children, isNotEmpty);
      final textContent = span.toPlainText();
      expect(textContent, contains('final x = "hello"; // comment\nclass User {}'));
    });
  });
}
