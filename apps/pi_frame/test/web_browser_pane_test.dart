import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pi_frame_theme/pi_frame_theme.dart';

import 'package:pi_frame/features/browser/browser_models.dart';
import 'package:pi_frame/features/browser/browser_service.dart';
import 'package:pi_frame/features/browser/browser_controller.dart';
import 'package:pi_frame/features/browser/web_browser_pane.dart';
import 'package:pi_frame/features/composer/composer_draft.dart';
import 'package:pi_frame/features/workspace/repository_workspace.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';

class _FakeHttpBaseClient extends http.BaseClient {
  final Map<String, http.Response> responses;
  _FakeHttpBaseClient(this.responses);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final urlStr = request.url.toString();
    http.Response? matched;

    for (final entry in responses.entries) {
      if (urlStr.contains(entry.key) || entry.key == urlStr) {
        matched = entry.value;
        break;
      }
    }

    matched ??= http.Response(
      '<html><head><title>Not Found</title></head><body>Page not found.</body></html>',
      404,
      headers: {'content-type': 'text/html; charset=utf-8'},
    );

    return http.StreamedResponse(
      Stream.value(matched.bodyBytes),
      matched.statusCode,
      headers: matched.headers,
    );
  }
}

class _FakeWorkspaceClient extends PcpClient {
  _FakeWorkspaceClient() : super(port: 1, token: 'test');

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
      ],
      'totalAdditions': 5,
      'totalDeletions': 2,
    },
  };

  @override
  Future<Map<String, dynamic>> getWorkspaceDiff(
    String sessionId, {
    String? filePath,
  }) async => {
    'data': {'diff': 'diff --git a/file b/file\n+test\n'},
  };
}

Widget _buildTestApp({
  required Widget child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: [FrameTokens.dark]),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  const sampleArticleHtml = '''
<!DOCTYPE html>
<html>
<head>
  <title>Flutter Architecture Guide</title>
  <meta name="description" content="A comprehensive guide to Flutter state management and Riverpod architecture.">
</head>
<body>
  <h1>Flutter State Management</h1>
  <h2>Getting Started with Riverpod</h2>
  <p>Riverpod is a reactive caching and state-management framework for Flutter applications.</p>
  <p>It enables declarative dependency injection, testing without mocks, and compile-time safety.</p>
  <pre><code>final countProvider = StateProvider((ref) => 0);</code></pre>
  <a href="/docs/providers">Learn more about providers</a>
  <a href="https://dart.dev">Dart Official Site</a>
</body>
</html>
''';

  const sampleDdgHtml = '''
<!DOCTYPE html>
<html>
<head>
  <title>flutter dev at DuckDuckGo</title>
</head>
<body>
  <div class="result">
    <a class="result__snippet" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fflutter.dev%2F">
      Flutter transforms the app development process. Build, test, and deploy beautiful web, mobile, desktop and embedded apps from a single codebase.
    </a>
  </div>
</body>
</html>
''';

  group('WebBrowserService Unit Tests', () {
    late _FakeHttpBaseClient fakeClient;
    late WebBrowserService service;

    setUp(() {
      fakeClient = _FakeHttpBaseClient({
        'https://flutter.dev/guide': http.Response(
          sampleArticleHtml,
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        ),
        'duckduckgo.com/html/?q=flutter+dev': http.Response(
          sampleDdgHtml,
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        ),
        'https://error.example.com': http.Response(
          'Server Error',
          500,
          headers: {'content-type': 'text/plain'},
        ),
      });
      service = WebBrowserService(client: fakeClient);
    });

    test('normalizeUrl handles full URLs, domains, and search queries', () {
      expect(
        service.normalizeUrl('https://flutter.dev'),
        'https://flutter.dev',
      );
      expect(
        service.normalizeUrl('flutter.dev'),
        'https://flutter.dev',
      );
      expect(
        service.normalizeUrl('http://localhost:8080/app'),
        'http://localhost:8080/app',
      );
      // Query search
      final searchUrl = service.normalizeUrl('flutter riverpod state', defaultEngine: SearchEngine.duckDuckGo);
      final searchUri = Uri.parse(searchUrl);
      expect(searchUri.host, contains('duckduckgo.com'));
      expect(searchUri.queryParameters['q'], 'flutter riverpod state');
    });

    test('load correctly parses HTML headings, paragraphs, code, and links', () async {
      final content = await service.load('https://flutter.dev/guide');
      expect(content.title, 'Flutter Architecture Guide');
      expect(content.description, contains('Flutter state management and Riverpod'));
      expect(content.headings, contains('Flutter State Management'));
      expect(content.headings, contains('Getting Started with Riverpod'));
      expect(content.paragraphs.length, 2);
      expect(content.codeSnippets.length, 1);
      expect(content.codeSnippets.first, 'final countProvider = StateProvider((ref) => 0);');
      // Relative link resolution
      expect(content.links.any((l) => l.url == 'https://flutter.dev/docs/providers'), isTrue);
      // Absolute link
      expect(content.links.any((l) => l.url == 'https://dart.dev'), isTrue);
    });

    test('load parses DuckDuckGo search result with decoded uddg link', () async {
      final content = await service.load(
        'https://duckduckgo.com/html/?q=flutter+dev',
      );
      expect(content.searchResults.isNotEmpty, isTrue);
      final first = content.searchResults.first;
      expect(first.url, 'https://flutter.dev/');
      expect(first.snippet, contains('Flutter transforms the app development process'));
    });

    test('load throws on HTTP error', () async {
      expect(
        () => service.load('https://error.example.com'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('WebBrowserNotifier Controller Tests', () {
    late _FakeHttpBaseClient fakeClient;

    setUp(() {
      fakeClient = _FakeHttpBaseClient({
        'https://flutter.dev/guide': http.Response(
          sampleArticleHtml,
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        ),
      });
    });

    test('Starts with initial home tab and default bookmarks', () {
      final container = ProviderContainer(
        overrides: [
          browserClientProvider.overrideWithValue(fakeClient),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(webBrowserProvider);
      expect(state.tabs.length, 1);
      expect(state.activeTab.isHome, isTrue);
      expect(state.bookmarks.isNotEmpty, isTrue);
      expect(state.searchEngine, SearchEngine.google);
    });

    test('Navigates to URL and tracks history', () async {
      final container = ProviderContainer(
        overrides: [
          browserClientProvider.overrideWithValue(fakeClient),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(webBrowserProvider.notifier);
      await notifier.navigate('https://flutter.dev/guide');

      final state = container.read(webBrowserProvider);
      expect(state.activeTab.url, 'https://flutter.dev/guide');
      expect(state.activeTab.title, 'Flutter Architecture Guide');
      expect(state.activeTab.content, isNotNull);
      expect(state.activeTab.canGoBack, isTrue);
      expect(state.activeTab.canGoForward, isFalse);

      // Back navigation
      await notifier.goBack();
      final backState = container.read(webBrowserProvider);
      expect(backState.activeTab.isHome, isTrue);
      expect(backState.activeTab.canGoForward, isTrue);

      // Forward navigation
      await notifier.goForward();
      final forwardState = container.read(webBrowserProvider);
      expect(forwardState.activeTab.url, 'https://flutter.dev/guide');
    });

    test('Multi-tab management: newTab, switchTab, closeTab', () async {
      final container = ProviderContainer(
        overrides: [
          browserClientProvider.overrideWithValue(fakeClient),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(webBrowserProvider.notifier);
      final firstTabId = container.read(webBrowserProvider).activeTabId;

      notifier.newTab();
      final stateWithTwoTabs = container.read(webBrowserProvider);
      expect(stateWithTwoTabs.tabs.length, 2);
      final secondTabId = stateWithTwoTabs.activeTabId;
      expect(secondTabId, isNot(firstTabId));

      // Switch back
      notifier.switchTab(firstTabId);
      expect(container.read(webBrowserProvider).activeTabId, firstTabId);

      // Close tab
      notifier.closeTab(firstTabId);
      final stateAfterClose = container.read(webBrowserProvider);
      expect(stateAfterClose.tabs.length, 1);
      expect(stateAfterClose.activeTabId, secondTabId);

      // Closing remaining tab re-creates a fresh home tab
      notifier.closeTab(secondTabId);
      final stateFresh = container.read(webBrowserProvider);
      expect(stateFresh.tabs.length, 1);
      expect(stateFresh.activeTab.isHome, isTrue);
    });

    test('setSearchEngine and toggleBookmark updates state', () {
      final container = ProviderContainer(
        overrides: [
          browserClientProvider.overrideWithValue(fakeClient),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(webBrowserProvider.notifier);
      notifier.setSearchEngine(SearchEngine.github);
      expect(container.read(webBrowserProvider).searchEngine, SearchEngine.github);

      // Toggle bookmark for a custom URL
      final countBefore = container.read(webBrowserProvider).bookmarks.length;
      notifier.toggleBookmark(
        'https://example.com/custom',
        'Custom Bookmark',
      );
      final bookmarks = container.read(webBrowserProvider).bookmarks;
      expect(bookmarks.length, countBefore + 1);
      expect(bookmarks.any((b) => b.url == 'https://example.com/custom'), isTrue);

      // Toggle again to remove
      notifier.toggleBookmark(
        'https://example.com/custom',
        'Custom Bookmark',
      );
      expect(container.read(webBrowserProvider).bookmarks.length, countBefore);
    });
  });

  group('WebBrowserPane Widget Tests', () {
    late _FakeHttpBaseClient fakeClient;

    setUp(() {
      fakeClient = _FakeHttpBaseClient({
        'https://flutter.dev/guide': http.Response(
          sampleArticleHtml,
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        ),
        'duckduckgo.com/html/?q=flutter+dev': http.Response(
          sampleDdgHtml,
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        ),
      });
    });

    testWidgets('Renders home dashboard with omnibox, engine selector, and quick search buttons', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            browserClientProvider.overrideWithValue(fakeClient),
          ],
          child: const SizedBox(
            width: 480,
            height: 700,
            child: WebBrowserPane(sessionId: 'test-session'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Browser web PiFrame'), findsOneWidget);
      expect(find.byKey(const ValueKey('browser-omnibox-input')), findsOneWidget);
      expect(find.byKey(const ValueKey('browser-home-dashboard')), findsOneWidget);
      expect(find.text('pub.dev'), findsWidgets);
      expect(find.text('GitHub'), findsWidgets);
      expect(find.text('Flutter Docs'), findsWidgets);
    });

    testWidgets('Submitting query in omnibox loads content and shows reader view', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            browserClientProvider.overrideWithValue(fakeClient),
          ],
          child: const SizedBox(
            width: 480,
            height: 700,
            child: WebBrowserPane(sessionId: 'test-session'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final inputFinder = find.byKey(const ValueKey('browser-omnibox-input'));
      await tester.enterText(inputFinder, 'https://flutter.dev/guide');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pumpAndSettle();

      // Verify rendered reader content
      expect(find.text('Flutter Architecture Guide'), findsWidgets);
      expect(find.text('Flutter State Management'), findsOneWidget);
      expect(find.text('Getting Started with Riverpod'), findsOneWidget);
      expect(
        find.text('final countProvider = StateProvider((ref) => 0);'),
        findsOneWidget,
      );
      expect(find.byTooltip('Invia al Chat Composer'), findsWidgets);
    });

    testWidgets('Clicking "Invia a Chat Composer" updates composerDraftProvider', (tester) async {
      final container = ProviderContainer(
        overrides: [
          browserClientProvider.overrideWithValue(fakeClient),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: [FrameTokens.dark]),
            home: const Scaffold(
              body: SizedBox(
                width: 480,
                height: 700,
                child: WebBrowserPane(sessionId: 'session-draft-test'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to guide
      await container
          .read(webBrowserProvider.notifier)
          .navigate('https://flutter.dev/guide');
      await tester.pumpAndSettle();

      // Click "Invia a Chat Composer"
      final sendBtn = find.byKey(const ValueKey('browser-send-to-chat-btn'));
      expect(sendBtn, findsOneWidget);
      await tester.tap(sendBtn);
      await tester.pumpAndSettle();

      final draft = container.read(composerDraftProvider('session-draft-test'));
      expect(
        draft,
        contains('[Flutter Architecture Guide](https://flutter.dev/guide)'),
      );
    });

    testWidgets('Header chip switcher toggles rightPaneModeProvider between git and browser', (tester) async {
      final fakePcp = _FakeWorkspaceClient();
      final container = ProviderContainer(
        overrides: [
          pcpClientProvider.overrideWithValue(fakePcp),
          browserClientProvider.overrideWithValue(fakeClient),
        ],
      );
      addTearDown(container.dispose);

      // Verify default is git
      expect(container.read(rightPaneModeProvider), RightPaneMode.git);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: [FrameTokens.dark]),
            home: Scaffold(
              body: SizedBox(
                width: 480,
                height: 700,
                child: Consumer(
                  builder: (context, ref, _) {
                    final mode = ref.watch(rightPaneModeProvider);
                    return mode == RightPaneMode.browser
                        ? const WebBrowserPane(sessionId: 'test-session')
                        : const GitChangesPane(sessionId: 'test-session');
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the browser chip in GitChangesPane header
      final browserChip = find.byKey(const ValueKey('right-pane-switch-browser-chip'));
      expect(browserChip, findsOneWidget);
      await tester.tap(browserChip);
      await tester.pumpAndSettle();

      // Now mode should be browser
      expect(container.read(rightPaneModeProvider), RightPaneMode.browser);
      expect(find.byType(WebBrowserPane), findsOneWidget);

      // Find git chip in WebBrowserPane header
      final gitChip = find.byKey(const ValueKey('right-pane-switch-git-chip'));
      expect(gitChip, findsOneWidget);
      await tester.tap(gitChip);
      await tester.pumpAndSettle();

      // Now mode should be git again
      expect(container.read(rightPaneModeProvider), RightPaneMode.git);
      expect(find.byType(GitChangesPane), findsOneWidget);
    });

    testWidgets('Tab management UI: adds new tab and closes tab', (tester) async {
      final container = ProviderContainer(
        overrides: [
          browserClientProvider.overrideWithValue(fakeClient),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: [FrameTokens.dark]),
            home: const Scaffold(
              body: SizedBox(
                width: 480,
                height: 700,
                child: WebBrowserPane(sessionId: 'test-session'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final initialTabId = container.read(webBrowserProvider).activeTabId;

      // Tap "+" button to open new tab
      final newTabBtn = find.byKey(const ValueKey('browser-new-tab-btn'));
      expect(newTabBtn, findsOneWidget);
      await tester.tap(newTabBtn);
      await tester.pumpAndSettle();

      expect(container.read(webBrowserProvider).tabs.length, 2);

      // Close the first tab
      final closeBtn = find.byKey(ValueKey('browser-close-tab-$initialTabId'));
      expect(closeBtn, findsOneWidget);
      await tester.tap(closeBtn);
      await tester.pumpAndSettle();

      expect(container.read(webBrowserProvider).tabs.length, 1);
    });

    testWidgets('Error state renders retry button and error details', (tester) async {
      final errorClient = _FakeHttpBaseClient({
        'https://broken.link': http.Response('Internal Server Error', 500),
      });

      final container = ProviderContainer(
        overrides: [
          browserClientProvider.overrideWithValue(errorClient),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: [FrameTokens.dark]),
            home: const Scaffold(
              body: SizedBox(
                width: 480,
                height: 700,
                child: WebBrowserPane(sessionId: 'test-session'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await container
          .read(webBrowserProvider.notifier)
          .navigate('https://broken.link');
      await tester.pumpAndSettle();

      expect(find.text('Impossibile caricare la pagina'), findsOneWidget);
      expect(find.byKey(const ValueKey('browser-retry-btn')), findsOneWidget);
    });

    testWidgets('Bookmark button in omnibox toggles bookmark', (tester) async {
      final container = ProviderContainer(
        overrides: [
          browserClientProvider.overrideWithValue(fakeClient),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: [FrameTokens.dark]),
            home: const Scaffold(
              body: SizedBox(
                width: 480,
                height: 700,
                child: WebBrowserPane(sessionId: 'test-session'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await container
          .read(webBrowserProvider.notifier)
          .navigate('https://flutter.dev/guide');
      await tester.pumpAndSettle();

      final bookmarkBtn = find.byKey(const ValueKey('browser-bookmark-btn'));
      expect(bookmarkBtn, findsOneWidget);

      expect(
        container.read(webBrowserProvider).isBookmarked('https://flutter.dev/guide'),
        isFalse,
      );

      // Tap bookmark button
      await tester.tap(bookmarkBtn);
      await tester.pumpAndSettle();

      expect(
        container.read(webBrowserProvider).isBookmarked('https://flutter.dev/guide'),
        isTrue,
      );

      // Tap again to unbookmark
      await tester.tap(bookmarkBtn);
      await tester.pumpAndSettle();

      expect(
        container.read(webBrowserProvider).isBookmarked('https://flutter.dev/guide'),
        isFalse,
      );
    });
  });
}
