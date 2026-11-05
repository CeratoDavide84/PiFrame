import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/data/language/language_settings.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/composer/composer.dart';
import 'package:pi_frame/features/composer/composer_draft.dart';
import 'package:pi_frame/features/workspace/repository_workspace.dart';

class _FakeWorkspaceClient extends PcpClient {
  _FakeWorkspaceClient() : super(port: 1, token: 'test');

  String diskContent = 'original\n';
  String diskRevision = 'revision-1';
  bool unsupportedList = false;
  String? listError;
  String? requestedDiff;
  final gitActions = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> refreshWorkspace(
    String sessionId, {
    String? cwd,
  }) async => {
    'data': {
      'isRepository': true,
      'rootPath': '/repo',
      'branch': 'main',
      'files': [
        {
          'path': 'lib/main.dart',
          'status': 'modified',
          'staged': false,
          'unstaged': true,
        },
        {
          'path': 'notes.txt',
          'status': 'untracked',
          'staged': false,
          'unstaged': true,
        },
      ],
      'totalAdditions': 2,
      'totalDeletions': 1,
    },
  };

  @override
  Future<Map<String, dynamic>> getWorkspaceDiff(
    String sessionId, {
    String? filePath,
  }) async {
    requestedDiff = filePath;
    return {
      'data': {'diff': 'diff --git a/$filePath b/$filePath\\n+updated\\n'},
    };
  }

  @override
  Future<Map<String, dynamic>> workspaceGitAction(
    String sessionId,
    Map<String, dynamic> payload,
  ) async {
    gitActions.add(payload);
    return {
      'data': {'status': <String, dynamic>{}},
    };
  }

  @override
  Future<Map<String, dynamic>> listWorkspaceFiles(String sessionId) async {
    if (listError != null) throw StateError(listError!);
    if (unsupportedList) {
      throw StateError('Unsupported command type: workspace.listFiles');
    }
    return {
      'data': {
        'rootPath': '/repo',
        'files': [
          {'path': 'lib/main.dart', 'sizeBytes': diskContent.length},
          {'path': 'README.md', 'sizeBytes': 25},
        ],
        'truncated': false,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> readWorkspaceFile(
    String sessionId,
    String path,
  ) async => {
    'data': {
      'rootPath': '/repo',
      'path': path,
      'content': path == 'README.md' ? '# Welcome\nDocumentation file.' : diskContent,
      'revision': diskRevision,
      'sizeBytes': diskContent.length,
    },
  };

  @override
  Future<Map<String, dynamic>> saveWorkspaceFile(
    String sessionId,
    Map<String, dynamic> payload,
  ) async {
    if (payload['revision'] != diskRevision) {
      throw StateError('File changed on disk; reload before saving.');
    }
    diskContent = payload['content'] as String;
    diskRevision = 'revision-${DateTime.now().microsecondsSinceEpoch}';
    return {
      'data': {'path': payload['path'], 'revision': diskRevision},
    };
  }
}

void main() {
  test('repository check error gives actionable guidance in both languages', () async {
    final client = _FakeWorkspaceClient()
      ..listError = 'Session working directory is not inside a Git repository.';
    final container = ProviderContainer(
      overrides: [pcpClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    final controller = container.read(repositoryStateProvider('session-a').notifier);
    await controller.loadFiles();
    expect(container.read(repositoryStateProvider('session-a')).error, contains('PATH del daemon'));
    container.read(appLanguageProvider.notifier).setLanguage(AppLanguage.en);
    await controller.loadFiles();
    expect(container.read(repositoryStateProvider('session-a')).error, contains('daemon’s PATH'));
  });

  test(
    'stale daemon workspace command shows a safe rebuild and restart hint',
    () async {
      final client = _FakeWorkspaceClient()..unsupportedList = true;
      final container = ProviderContainer(
        overrides: [pcpClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);

      await container
          .read(repositoryStateProvider('session-a').notifier)
          .loadFiles();
      expect(
        container.read(repositoryStateProvider('session-a')).error,
        contains('riavvia il daemon solo quando nessun worker Pi è attivo'),
      );
    },
  );

  test('editor keeps dirty content on revision conflict and clears after explicit retry', () async {
    final client = _FakeWorkspaceClient();
    final container = ProviderContainer(
      overrides: [pcpClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);

    final editor = container.read(
      repositoryStateProvider('session-a').notifier,
    );
    await editor.loadFiles();
    await editor.selectFile('lib/main.dart');
    editor.edit('lib/main.dart', 'local edit\n');

    client.diskContent = 'external edit\n';
    client.diskRevision = 'revision-external';
    await expectLater(editor.save('lib/main.dart'), throwsA(isA<StateError>()));
    expect(
      editor.currentState.buffers['lib/main.dart']?.content,
      'local edit\n',
    );
    expect(editor.currentState.buffers['lib/main.dart']?.dirty, isTrue);

    final currentDisk = await editor.currentDisk('lib/main.dart');
    await editor.save('lib/main.dart', revisionOverride: currentDisk.revision);
    expect(editor.currentState.buffers['lib/main.dart']?.dirty, isFalse);
    expect(client.diskContent, 'local edit\n');
  });

  testWidgets('Git Changes opens tracked diffs and stages or undoes per file', (
    tester,
  ) async {
    final client = _FakeWorkspaceClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pcpClientProvider.overrideWithValue(client),
          sessionStateFamily('session-a').overrideWith(
            (ref) =>
                SessionStateNotifier('session-a', null)
                  ..state = const SessionState(
                    sessionId: 'session-a',
                    cwd: '/repo',
                    entries: [
                      SessionEntry(
                        id: 'agent-write',
                        role: 'assistant',
                        text: '',
                        timestamp: 1,
                        toolCalls: [
                          ToolExecutionState(
                            toolCallId: 'write-1',
                            toolName: 'write',
                            args: {'path': '/repo/lib/main.dart'},
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.light().copyWith(
            extensions: const [FrameTokens.light],
          ),
          home: const Scaffold(body: GitChangesPane(sessionId: 'session-a')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(GitChangesPane)),
    );
    final repository = container.read(
      repositoryStateProvider('session-a').notifier,
    );
    await repository.loadFiles();
    await repository.selectFile('lib/main.dart');
    repository.edit('lib/main.dart', 'manual edit\n');
    await repository.save('lib/main.dart');
    // Git changes starts collapsed by default: tap section header to expand
    await tester.tap(find.text('MODIFICHE (CHANGES)'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Tool Pi + salvataggio PiFrame'),
      findsOneWidget,
    );
    expect(find.text('lib/main.dart'), findsOneWidget);
    expect(find.text('notes.txt'), findsOneWidget);
    await tester.tap(find.text('lib/main.dart'));
    await tester.pumpAndSettle();
    expect(client.requestedDiff, 'lib/main.dart');
    expect(find.textContaining('diff --git a/lib/main.dart'), findsOneWidget);
    await tester.tap(find.byTooltip('Chiudi diff'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Metti in stage lib/main.dart'));
    await tester.pumpAndSettle();
    expect(client.gitActions.last['action'], 'stage');

    expect(find.byTooltip('Metti in stage notes.txt'), findsOneWidget);
    await tester.tap(find.byTooltip('Metti in stage notes.txt'));
    await tester.pumpAndSettle();
    expect(client.gitActions.last['action'], 'stage');
    expect(client.gitActions.last['paths'], ['notes.txt']);

    await tester.tap(find.byTooltip('Annulla modifiche a lib/main.dart'));
    await tester.pumpAndSettle();
    expect(find.text('Annullare tutte le modifiche?'), findsOneWidget);
    await tester.tap(find.text('Annulla modifiche'));
    await tester.pumpAndSettle();
    expect(client.gitActions.last['action'], 'discard');
  });

  testWidgets('Composer can add a repository file to prompt context', (
    tester,
  ) async {
    final client = _FakeWorkspaceClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pcpClientProvider.overrideWithValue(client),
          sessionStateFamily('session-a').overrideWith(
            (ref) => SessionStateNotifier(
              'session-a',
              null,
            )..state = const SessionState(sessionId: 'session-a', cwd: '/repo'),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.light().copyWith(
            extensions: const [FrameTokens.light],
          ),
          home: const Scaffold(body: Composer(sessionId: 'session-a')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Allega file, link o immagine'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('File dal repository'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('lib/main.dart'));
    await tester.pumpAndSettle();

    final draft = ProviderScope.containerOf(
      tester.element(find.byType(Composer)),
    ).read(composerDraftProvider('session-a'));
    expect(draft, contains('@lib/main.dart'));
  });

  testWidgets('Composer adds selected code with exact file and line range', (
    tester,
  ) async {
    final client = _FakeWorkspaceClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pcpClientProvider.overrideWithValue(client),
          sessionStateFamily('session-a').overrideWith(
            (ref) => SessionStateNotifier(
              'session-a',
              null,
            )..state = const SessionState(sessionId: 'session-a', cwd: '/repo'),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.light().copyWith(
            extensions: const [FrameTokens.light],
          ),
          home: const Scaffold(
            body: Row(
              children: [
                Expanded(child: RepositoryPane(sessionId: 'session-a')),
                Expanded(child: Composer(sessionId: 'session-a')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RepositoryPane)),
    );
    final repository = container.read(
      repositoryStateProvider('session-a').notifier,
    );
    await repository.loadFiles();
    await repository.selectFile('lib/main.dart');
    await tester.pumpAndSettle();

    final fieldFinder = find.byKey(
      const ValueKey('repository-editor-session-a'),
    );
    final editorField = tester.widget<TextField>(fieldFinder);
    editorField.controller!.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 8,
    );
    await tester.pump();
    final editableFinder = find.descendant(
      of: fieldFinder,
      matching: find.byType(EditableText),
    );
    final editorState = tester.state<EditableTextState>(editableFinder);
    final menu = editorField.contextMenuBuilder!(
      tester.element(fieldFinder),
      editorState,
    ) as AdaptiveTextSelectionToolbar;
    menu.buttonItems!
        .singleWhere((item) => item.label == 'Aggiungi alla chat')
        .onPressed!
        .call();

    final draft = container.read(composerDraftProvider('session-a'));
    expect(draft, contains('lib/main.dart:1-1'));
    expect(draft, contains('original'));
  });

  testWidgets('session switch cancel preserves dirty editor buffer', (
    tester,
  ) async {
    final client = _FakeWorkspaceClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pcpClientProvider.overrideWithValue(client),
          activeSessionIdProvider.overrideWith((ref) => 'session-a'),
          sessionStateFamily('session-a').overrideWith(
            (ref) => SessionStateNotifier(
              'session-a',
              null,
            )..state = const SessionState(sessionId: 'session-a', cwd: '/repo'),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.light().copyWith(
            extensions: const [FrameTokens.light],
          ),
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () => switchSessionSafely(context, ref, 'session-b'),
                child: const Text('Switch session'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.text('Switch session')),
    );
    final editor = container.read(
      repositoryStateProvider('session-a').notifier,
    );
    await editor.loadFiles();
    await editor.selectFile('lib/main.dart');
    editor.edit('lib/main.dart', 'unsaved\n');

    await tester.tap(find.text('Switch session'));
    await tester.pumpAndSettle();
    expect(find.text('Modifiche non salvate'), findsOneWidget);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();

    expect(container.read(activeSessionIdProvider), 'session-a');
    expect(editor.currentState.buffers['lib/main.dart']?.dirty, isTrue);
  });

  testWidgets(
    'RepositoryPane displays full-width treeview without empty editor, expands/collapses folders and closes editor',
    (tester) async {
      final client = _FakeWorkspaceClient();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pcpClientProvider.overrideWithValue(client),
            sessionStateFamily('session-a').overrideWith(
              (ref) => SessionStateNotifier('session-a', null)
                ..state =
                    const SessionState(sessionId: 'session-a', cwd: '/repo'),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.light().copyWith(
              extensions: const [FrameTokens.light],
            ),
            home: const Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: RepositoryPane(sessionId: 'session-a'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially no file is selected: editor field does NOT exist! No wasted space!
      expect(
        find.byKey(const ValueKey('repository-editor-session-a')),
        findsNothing,
      );
      expect(find.text('Seleziona un file'), findsNothing);

      // Hierarchical folder 'lib' is present in tree; starts collapsed by default
      expect(find.text('lib'), findsOneWidget);
      expect(find.text('main.dart'), findsNothing);

      // Tap 'lib' folder row to expand it
      await tester.tap(find.text('lib'));
      await tester.pumpAndSettle();

      // Child 'main.dart' is now visible!
      expect(find.text('main.dart'), findsOneWidget);

      // Tap 'lib' again to collapse it
      await tester.tap(find.text('lib'));
      await tester.pumpAndSettle();
      expect(find.text('main.dart'), findsNothing);

      // Tap 'lib' again to expand it
      await tester.tap(find.text('lib'));
      await tester.pumpAndSettle();
      expect(find.text('main.dart'), findsOneWidget);

      // Tap the file to open it in the editor
      await tester.tap(find.text('main.dart'));
      await tester.pumpAndSettle();

      // Now editor is opened
      expect(
        find.byKey(const ValueKey('repository-editor-session-a')),
        findsOneWidget,
      );
      expect(find.byTooltip('Chiudi file'), findsOneWidget);

      // Click close button to close the editor
      await tester.tap(find.byTooltip('Chiudi file'));
      await tester.pumpAndSettle();

      // Returns to full-width tree view, editor is gone
      expect(
        find.byKey(const ValueKey('repository-editor-session-a')),
        findsNothing,
      );
    },
  );

  testWidgets('repository controls change language without reopening', (tester) async {
    final client = _FakeWorkspaceClient();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        pcpClientProvider.overrideWithValue(client),
        sessionStateFamily('session-a').overrideWith(
          (ref) => SessionStateNotifier('session-a', null)
            ..state = const SessionState(sessionId: 'session-a', cwd: '/repo'),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData.light().copyWith(extensions: const [FrameTokens.light]),
        home: const Scaffold(body: RepositoryPane(sessionId: 'session-a')),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Aggiorna file'), findsOneWidget);
    final container = ProviderScope.containerOf(tester.element(find.byType(RepositoryPane)));
    container.read(appLanguageProvider.notifier).setLanguage(AppLanguage.en);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Refresh files'), findsOneWidget);
    expect(find.byTooltip('Aggiorna file'), findsNothing);
  });

  testWidgets(
    'RepositoryPane renders .md files in formatted preview by default and toggles to editor',
    (tester) async {
      final client = _FakeWorkspaceClient();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pcpClientProvider.overrideWithValue(client),
            sessionStateFamily('session-a').overrideWith(
              (ref) => SessionStateNotifier('session-a', null)
                ..state =
                    const SessionState(sessionId: 'session-a', cwd: '/repo'),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.light().copyWith(
              extensions: const [FrameTokens.light],
            ),
            home: const Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: RepositoryPane(sessionId: 'session-a'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open README.md
      expect(find.text('README.md'), findsOneWidget);
      await tester.tap(find.text('README.md'));
      await tester.pumpAndSettle();

      // In preview mode by default: preview widget is present, raw editor TextField is absent
      expect(
        find.byKey(const ValueKey('repository-md-preview-README.md')),
        findsOneWidget,
      );
      expect(find.text('Welcome'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('repository-editor-session-a')),
        findsNothing,
      );

      // Markdown toggle button is visible
      final toggleBtn = find.byKey(const ValueKey('repository-markdown-toggle-btn'));
      expect(toggleBtn, findsOneWidget);

      // Tap toggle button to switch to raw editor
      await tester.tap(toggleBtn);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('repository-editor-session-a')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('repository-md-preview-README.md')),
        findsNothing,
      );

      // Tap toggle button again to return to preview mode
      await tester.tap(toggleBtn);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('repository-md-preview-README.md')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('repository-editor-session-a')),
        findsNothing,
      );
    },
  );
}

