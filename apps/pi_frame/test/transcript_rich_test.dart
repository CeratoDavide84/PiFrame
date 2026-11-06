import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:pi_frame/features/transcript/rich_content.dart';
import 'package:pi_frame/features/transcript/thinking_block.dart';
import 'package:pi_frame/ui/code/code_block.dart';
import 'package:pi_frame/ui/code/diff_block.dart';

void main() {
  Widget wrapWithTheme(Widget child) {
    return MaterialApp(
      theme: ThemeData.dark().copyWith(
        extensions: const [FrameTokens.dark],
      ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );
  }

  testWidgets('ThinkingBlock collapses by default and expands on tap', (tester) async {
    await tester.pumpWidget(
      wrapWithTheme(
        const ThinkingBlock(
          thinkingText: 'Prima riga di sintesi\nDettaglio lungo del ragionamento interno che appare solo da espanso.',
        ),
      ),
    );

    expect(find.text('Ragionamento'), findsOneWidget);
    expect(find.textContaining('parole'), findsOneWidget);
    // Detail should not be visible when collapsed
    expect(find.text('Dettaglio lungo del ragionamento interno che appare solo da espanso.'), findsNothing);

    // Tap to expand
    await tester.tap(find.text('Ragionamento'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Dettaglio lungo del ragionamento'), findsOneWidget);
  });

  testWidgets('ThinkingBlock disappears completely when thinking text is empty or whitespace even when streaming', (tester) async {
    await tester.pumpWidget(
      wrapWithTheme(
        const ThinkingBlock(
          thinkingText: '   \n  \t ',
          isStreaming: true,
        ),
      ),
    );

    expect(find.text('Ragionamento'), findsNothing);
    expect(find.byType(ThinkingBlock), findsOneWidget);
    expect(find.byType(SizedBox), findsWidgets);
  });

  testWidgets('RichContent separates text, headers, and code fences', (tester) async {
    const markdown = '''
# Titolo Principale
Ecco del testo con `inline_code`.

```dart
void main() {}
```

```diff
+nuova riga
```
''';

    await tester.pumpWidget(
      wrapWithTheme(
        const RichContent(text: markdown),
      ),
    );

    expect(find.text('Titolo Principale'), findsOneWidget);
    expect(find.byType(CodeBlock), findsOneWidget);
    expect(find.byType(DiffBlock), findsOneWidget);
  });

  test('isLikelyFilePath correctly identifies file paths', () {
    expect(isLikelyFilePath('lib/main.dart'), isTrue);
    expect(isLikelyFilePath('apps/agentd/src/workspace/gitClient.ts'), isTrue);
    expect(isLikelyFilePath('README.md'), isTrue);
    expect(isLikelyFilePath('C:\\Personale\\Repos\\project\\file.dart'), isTrue);
    expect(isLikelyFilePath('file:///c:/path/to/file.dart'), isTrue);
    expect(isLikelyFilePath('config.json'), isTrue);

    expect(isLikelyFilePath(''), isFalse);
    expect(isLikelyFilePath('hello world'), isFalse);
    expect(isLikelyFilePath('https://github.com/flutter/flutter'), isFalse);
    expect(isLikelyFilePath('git status'), isFalse);
  });

  testWidgets('RichContent marks file code mentions with file icon and CTRL+click tooltip', (tester) async {
    const textWithFile = 'Ho modificato il file `lib/main.dart` e creato `README.md`.';

    await tester.pumpWidget(
      wrapWithTheme(
        const RichContent(text: textWithFile, cwd: '/dummy/project'),
      ),
    );

    expect(find.text('lib/main.dart'), findsOneWidget);
    expect(find.text('README.md'), findsOneWidget);
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsNWidgets(2));
    expect(find.byTooltip('Ctrl+click to open in File Explorer'), findsWidgets);

    // Verify SelectionContainer.disabled is present so that SelectionArea does not override mouse cursor
    final disabledContainers = find.descendant(
      of: find.byType(RichContent),
      matching: find.byType(SelectionContainer),
    );
    expect(disabledContainers, findsWidgets);

    // Verify MouseRegion with click cursor exists for file chips
    final clickMouseRegions = find.descendant(
      of: find.byType(RichContent),
      matching: find.byWidgetPredicate(
        (w) => w is MouseRegion && w.cursor == SystemMouseCursors.click,
      ),
    );
    expect(clickMouseRegions, findsWidgets);
  });

  test('resolvePathForOsExplorer correctly resolves WSL and Windows paths', () {
    // 1. WSL UNC cwd with relative path
    const wslCwd = r'\\wsl.localhost\LMD_env\home\strenti\Repos\my_repo';
    final res1 = resolvePathForOsExplorer('lib/main.dart', cwd: wslCwd);
    expect(res1, r'\\wsl.localhost\LMD_env\home\strenti\Repos\my_repo\lib\main.dart');

    // 2. WSL UNC cwd with Linux absolute path
    final res2 = resolvePathForOsExplorer('/home/strenti/Repos/my_repo/lib/main.dart', cwd: wslCwd);
    expect(res2, r'\\wsl.localhost\LMD_env\home\strenti\Repos\my_repo\lib\main.dart');

    // 3. WSL file:// URI
    final res3 = resolvePathForOsExplorer('file:///home/strenti/Repos/my_repo/test.dart', cwd: wslCwd);
    expect(res3, r'\\wsl.localhost\LMD_env\home\strenti\Repos\my_repo\test.dart');

    // 4. Already full WSL UNC path
    final res4 = resolvePathForOsExplorer(r'\\wsl$\LMD_env\home\strenti\file.txt');
    expect(res4, r'\\wsl$\LMD_env\home\strenti\file.txt');

    // 5. Line numbers and anchor stripped
    final res5 = resolvePathForOsExplorer('lib/main.dart:42:10#L42-L50', cwd: wslCwd);
    expect(res5, r'\\wsl.localhost\LMD_env\home\strenti\Repos\my_repo\lib\main.dart');

    // 6. Windows cwd with relative path
    const winCwd = r'C:\Personale\Repos\my_repo';
    final res6 = resolvePathForOsExplorer('lib/main.dart', cwd: winCwd);
    expect(res6, r'C:\Personale\Repos\my_repo\lib\main.dart');
  }, skip: !Platform.isWindows);

  test('resolvePathForOsExplorer correctly resolves POSIX paths', () {
    const cwd = '/home/user/project';
    expect(
      resolvePathForOsExplorer('lib/main.dart', cwd: cwd),
      '/home/user/project/lib/main.dart',
    );
    expect(
      resolvePathForOsExplorer('lib/main.dart', cwd: '$cwd/'),
      '/home/user/project/lib/main.dart',
    );
    expect(resolvePathForOsExplorer('/etc/hosts', cwd: cwd), '/etc/hosts');
    expect(
      resolvePathForOsExplorer('file:///tmp/file.dart', cwd: cwd),
      '/tmp/file.dart',
    );
    expect(
      resolvePathForOsExplorer('lib/main.dart:42:10#L42-L50', cwd: cwd),
      '/home/user/project/lib/main.dart',
    );
    expect(resolvePathForOsExplorer('lib/main.dart'), 'lib/main.dart');
  }, skip: Platform.isWindows);

  testWidgets('RichContent renders raw file paths and markdown links with file chips', (tester) async {
    const textWithVariousLinks =
        'Vedi apps/pi_frame/lib/main.dart per i dettagli oppure consulta [la guida](docs/guide.md).';

    await tester.pumpWidget(
      wrapWithTheme(
        const RichContent(
          text: textWithVariousLinks,
          cwd: r'\\wsl.localhost\LMD_env\home\strenti\repo',
        ),
      ),
    );

    expect(find.text('apps/pi_frame/lib/main.dart'), findsOneWidget);
    expect(find.text('la guida'), findsOneWidget);
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsNWidgets(2));
  });
}


