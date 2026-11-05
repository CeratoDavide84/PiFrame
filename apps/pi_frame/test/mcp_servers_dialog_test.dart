import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/features/settings/mcp_servers_dialog.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

void main() {
  group('McpServersDialog', () {
    testWidgets('renders server list with checkbox and badges', (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const tokens = FrameTokens.dark;
      final testServers = [
        const McpServerItem(
          name: 'dart',
          scope: 'global',
          sourcePath: '/path/to/mcp.json',
          enabled: true,
          transport: 'dart mcp-server',
          state: 'connected',
          tools: ['run_tests', 'analyze_files'],
          description: 'Official Dart server',
        ),
        const McpServerItem(
          name: 'git',
          scope: 'project',
          sourcePath: '/project/.pi/mcp.json',
          enabled: false,
          transport: 'git-mcp',
          state: 'disabled',
          tools: [],
          description: 'Git integration',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: McpServersDialog(
                tokens: tokens,
                initialServers: testServers,
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      // Check title and servers
      expect(find.text('Server MCP disponibili'), findsOneWidget);
      expect(find.text('dart'), findsOneWidget);
      expect(find.text('git'), findsOneWidget);
      expect(find.text('Connesso'), findsOneWidget);
      expect(find.text('Disabilitato'), findsOneWidget);
      expect(find.text('Progetto'), findsOneWidget);
      expect(find.text('1 su 2 server attivi'), findsOneWidget);

      // Checkboxes exist for each server
      expect(find.byKey(const ValueKey('mcp-checkbox-dart')), findsOneWidget);
      expect(find.byKey(const ValueKey('mcp-checkbox-git')), findsOneWidget);

      final dartCheckbox = tester.widget<Checkbox>(
        find.byKey(const ValueKey('mcp-checkbox-dart')),
      );
      expect(dartCheckbox.value, isTrue);

      final gitCheckbox = tester.widget<Checkbox>(
        find.byKey(const ValueKey('mcp-checkbox-git')),
      );
      expect(gitCheckbox.value, isFalse);

      // Tap on tools chip for dart
      expect(find.text('2 tool'), findsOneWidget);
      await tester.tap(find.text('2 tool'));
      await tester.pump();

      expect(find.text('run_tests'), findsOneWidget);
      expect(find.text('analyze_files'), findsOneWidget);
    });
  });
}
