import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/features/sessions_sidebar/project_archive_provider.dart';
import 'package:pi_frame/features/sessions_sidebar/sessions_sidebar.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

void main() {
  test('project names and archives persist independently of sessions', () {
    final dir = Directory.systemTemp.createTempSync('piframe-project-archive-');
    try {
      final file = File('${dir.path}/archive.json');
      final first = ProjectArchiveNotifier(storageFile: file);
      first.renameProject('/project/a', 'Project A');
      first.toggleProject('/project/a');
      first.toggleSession('session-2');
      first.dispose();

      final restored = ProjectArchiveNotifier(storageFile: file);
      expect(restored.state.names['/project/a'], 'Project A');
      expect(restored.state.projects, {'/project/a'});
      expect(restored.state.sessions, {'session-2'});
      restored.toggleProject('/project/a');
      expect(restored.state.projects, isEmpty);
      expect(restored.state.sessions, {'session-2'});
      restored.toggleSession('session-2');
      expect(restored.state.sessions, isEmpty);
      restored.dispose();
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  testWidgets('archive view keeps session and project archives separate', (tester) async {
    final dir = Directory.systemTemp.createTempSync('piframe-project-ui-');
    final archive = ProjectArchiveNotifier(storageFile: File('${dir.path}/archive.json'));
    try {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          projectArchiveProvider.overrideWith((ref) => archive),
          daemonEndpointProvider.overrideWith((ref) async => null),
          sessionListProvider.overrideWith((ref) async => [
            {'id': 'a1', 'name': 'Session A1', 'cwd': '/alpha'},
            {'id': 'a2', 'name': 'Session A2', 'cwd': '/alpha'},
            {'id': 'b1', 'name': 'Session B1', 'cwd': '/beta'},
          ]),
        ],
        child: MaterialApp(theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]), home: const Scaffold(body: SessionsSidebar())),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('alpha'));
      await tester.pumpAndSettle();
      expect(find.text('Session A1'), findsOneWidget);
      expect(find.text('Session A2'), findsOneWidget);
      archive.toggleSession('a1');
      await tester.pumpAndSettle();
      expect(find.text('Session A1'), findsNothing);
      expect(find.text('Session A2'), findsOneWidget);
      archive.toggleProject('/beta');
      await tester.pumpAndSettle();
      expect(find.text('beta'), findsNothing);
      await tester.ensureVisible(find.text('Archivio'));
      await tester.tap(find.text('Archivio'));
      await tester.pumpAndSettle();
      expect(find.text('beta'), findsOneWidget);
      expect(find.text('Session A1'), findsOneWidget);
      expect(find.text('Session A2'), findsNothing);
      archive.toggleProject('/beta');
      archive.toggleSession('a1');
      await tester.pumpAndSettle();
      expect(find.text('Session A1'), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      dir.deleteSync(recursive: true);
    }
  });
}
