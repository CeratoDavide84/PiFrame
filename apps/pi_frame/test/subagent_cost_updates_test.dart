import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/daemon/daemon_providers.dart';
import 'package:pi_frame/data/daemon/pcp_client.dart';
import 'package:pi_frame/domain/session/agent_status.dart';
import 'package:pi_frame/domain/session/session_state.dart';
import 'package:pi_frame/features/transcript/subagent_panel.dart';
import 'package:pi_frame/features/transcript/subagents_provider.dart';
import 'package:pi_frame/features/transcript/transcript_view.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

class _CostClient extends PcpClient {
  _CostClient() : super(port: 0, token: 'test');
  double cost = 0.0175;
  int calls = 0;
  String? toolCallId;
  List<Map<String, dynamic>>? rows;
  bool fail = false;

  @override
  DaemonConnectionState get state => DaemonConnectionState.connected;

  @override
  Future<List<Map<String, dynamic>>> getSubagents(String sessionId) async {
    calls++;
    if (fail) throw StateError('daemon unavailable');
    return rows ?? [
      {
        'id': 'worker#1',
        if (toolCallId != null) 'toolCallId': toolCallId,
        'name': 'Reviewer',
        'model': 'test-model',
        'cost': cost,
        'status': 'completed',
        'output': 'Review in progress',
      },
    ];
  }
}

class _SlowSubagentsClient extends PcpClient {
  _SlowSubagentsClient() : super(port: 0, token: 'test');
  final response = Completer<List<Map<String, dynamic>>>();
  int calls = 0;

  @override
  DaemonConnectionState get state => DaemonConnectionState.connected;

  @override
  Future<List<Map<String, dynamic>>> getSubagents(String sessionId) {
    calls++;
    return response.future;
  }
}

void main() {
  testWidgets('background launch stays active during a slow daemon reply', (tester) async {
    const launch = SessionEntry(
      id: 'launch', role: 'assistant', text: '', timestamp: 1000,
      toolCalls: [ToolExecutionState(
        toolCallId: 'call-bg', toolName: 'Agent',
        args: {'description': 'Investigate'},
        output: 'Agent started in background.\nAgent ID: bg-123\nType: delegate\nYou will be notified when this agent completes.',
      )],
    );
    final client = _SlowSubagentsClient();
    final session = SessionStateNotifier('background', null)
      ..state = const SessionState(
        sessionId: 'background', cwd: '/repo', agentStatus: AgentStatus.settled,
        entries: [launch],
      );
    final container = ProviderContainer(overrides: [
      pcpClientProvider.overrideWithValue(client),
      sessionStateFamily('background').overrideWith((ref) => session),
    ]);
    final subscription = container.listen(subagentsFamily('background'), (_, _) {});
    var disposed = false;
    addTearDown(() {
      if (!disposed) { subscription.close(); container.dispose(); client.dispose(); }
    });
    await tester.pump();
    expect(container.read(subagentsFamily('background')).single.status, 'running');
    await tester.pump(const Duration(seconds: 10));
    expect(client.calls, 1, reason: 'A slow request must not be duplicated');
    client.response.complete([
      {'id': 'bg-123', 'toolCallId': 'call-bg', 'status': 'running', 'model': 'actual-model'},
    ]);
    await tester.pump();
    expect(container.read(subagentsFamily('background')).single.model, 'actual-model');
    expect(container.read(subagentsFamily('background')).single.isRunning, isTrue);
    session.state = session.state.copyWith(entries: const [
      launch,
      SessionEntry(
        id: 'done', role: 'custom', timestamp: 2000,
        text: '<task-notification><task-id>bg-123</task-id><tool-use-id>call-bg</tool-use-id><status>Done</status><summary>Agent finished</summary></task-notification>',
      ),
    ]);
    await tester.pump();
    expect(container.read(subagentsFamily('background')).single.status, 'completed');
    disposed = true;
    subscription.close();
    container.dispose();
    client.dispose();
    await tester.pump(const Duration(milliseconds: 1));
  });

  test('queued launch stays active after the parent settles', () {
    final container = ProviderContainer(overrides: [
      pcpClientProvider.overrideWithValue(null),
      sessionStateFamily('queued').overrideWith(
        (ref) => SessionStateNotifier('queued', null)
          ..state = const SessionState(
            sessionId: 'queued', cwd: '/repo', agentStatus: AgentStatus.settled,
            entries: [SessionEntry(
              id: 'launch', role: 'assistant', text: '', timestamp: 1000,
              toolCalls: [ToolExecutionState(
                toolCallId: 'call-queued', toolName: 'Agent',
                output: 'Agent queued in background.\nAgent ID: queued-123\nType: delegate',
              )],
            )],
          ),
      ),
    ]);
    addTearDown(container.dispose);
    final subscription = container.listen(subagentsFamily('queued'), (_, _) {});
    addTearDown(subscription.close);
    expect(container.read(subagentsFamily('queued')).single.isRunning, isTrue);
  });

  testWidgets('consumed result completes the existing background agent', (tester) async {
    const agentId = 'result-123';
    final client = _CostClient()..rows = [
      {'id': agentId, 'toolCallId': 'call-bg', 'status': 'running'},
    ];
    final session = SessionStateNotifier('consumed', null)
      ..state = const SessionState(
        sessionId: 'consumed', cwd: '/repo', agentStatus: AgentStatus.settled,
        entries: [SessionEntry(
          id: 'launch', role: 'assistant', text: '', timestamp: 1000,
          toolCalls: [ToolExecutionState(
            toolCallId: 'call-bg', toolName: 'Agent',
            output: 'Agent started in background.\nAgent ID: $agentId\nType: delegate',
          )],
        )],
      );
    final container = ProviderContainer(overrides: [
      pcpClientProvider.overrideWithValue(client),
      sessionStateFamily('consumed').overrideWith((ref) => session),
    ]);
    final subscription = container.listen(subagentsFamily('consumed'), (_, _) {});
    var disposed = false;
    addTearDown(() {
      if (!disposed) { subscription.close(); container.dispose(); client.dispose(); }
    });
    await tester.pump();
    expect(container.read(subagentsFamily('consumed')).single.isRunning, isTrue);
    final launch = session.state.entries.single;
    session.state = session.state.copyWith(entries: [
      launch,
      const SessionEntry(
        id: 'result', role: 'assistant', text: '', timestamp: 2000,
        toolCalls: [ToolExecutionState(
          toolCallId: 'call-result', toolName: 'get_subagent_result',
          args: {'agent_id': agentId},
          output: 'Agent: $agentId\nType: delegate | Status: completed | Tool uses: 3\nDescription: Investigate\n\nFinished.',
        )],
      ),
    ]);
    await tester.pump();
    final agents = container.read(subagentsFamily('consumed'));
    expect(agents, hasLength(1));
    expect(agents.single.status, 'completed');
    disposed = true;
    subscription.close();
    container.dispose();
    client.dispose();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('background card changes from running to completed on notification', (tester) async {
    const launch = SessionEntry(
      id: 'launch', role: 'assistant', text: '', timestamp: 1000,
      toolCalls: [ToolExecutionState(
        toolCallId: 'call-card', toolName: 'Agent', args: {'description': 'Investigate'},
        output: 'Agent started in background.\nAgent ID: card-1\nType: delegate',
      )],
    );
    final session = SessionStateNotifier('card', null)
      ..state = const SessionState(
        sessionId: 'card', cwd: '/repo', agentStatus: AgentStatus.settled,
        entries: [launch],
      );
    final container = ProviderContainer(overrides: [
      pcpClientProvider.overrideWithValue(null),
      sessionStateFamily('card').overrideWith((ref) => session),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
        home: const Scaffold(body: SubagentsPopDown(sessionId: 'card')),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('In corso'), findsOneWidget);
    expect(find.text('Completato'), findsNothing);
    session.state = session.state.copyWith(entries: const [
      launch,
      SessionEntry(id: 'done', role: 'custom', timestamp: 2000,
        text: '<task-notification><task-id>card-1</task-id><tool-use-id>call-card</tool-use-id><status>Done</status><summary>Done</summary></task-notification>'),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Completato'), findsOneWidget);
    expect(find.text('In corso'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  test('batched notifications finish the right agents with distinct statuses', () {
    final container = ProviderContainer(overrides: [
      pcpClientProvider.overrideWithValue(null),
      sessionStateFamily('batch').overrideWith(
        (ref) => SessionStateNotifier('batch', null)
          ..state = const SessionState(
            sessionId: 'batch', cwd: '/repo', agentStatus: AgentStatus.settled,
            entries: [
              SessionEntry(
                id: 'launch', role: 'assistant', text: '', timestamp: 1000,
                toolCalls: [
                  ToolExecutionState(toolCallId: 'call-1', toolName: 'Agent',
                    output: 'Agent started in background.\nAgent ID: batch-1\nType: delegate'),
                  ToolExecutionState(toolCallId: 'call-2', toolName: 'Agent',
                    output: 'Agent queued in background.\nAgent ID: batch-2\nType: delegate'),
                ],
              ),
              SessionEntry(
                id: 'done', role: 'custom', timestamp: 2000,
                text: '<task-notification><task-id>batch-1</task-id><status>Done</status><summary>Done</summary></task-notification>\n'
                    '<task-notification><task-id>batch-2</task-id><status>Aborted (max turns exceeded)</status><summary>Aborted</summary></task-notification>',
              ),
            ],
          ),
      ),
    ]);
    addTearDown(container.dispose);
    final subscription = container.listen(subagentsFamily('batch'), (_, _) {});
    addTearDown(subscription.close);
    final agents = container.read(subagentsFamily('batch'));
    expect(agents, hasLength(2));
    expect(agents.singleWhere((a) => a.id == 'batch-1').status, 'completed');
    expect(agents.singleWhere((a) => a.id == 'batch-2').status, 'stopped');
  });

  test('an old completion does not terminate a resumed background agent', () {
    final container = ProviderContainer(overrides: [
      pcpClientProvider.overrideWithValue(null),
      sessionStateFamily('resumed').overrideWith(
        (ref) => SessionStateNotifier('resumed', null)
          ..state = const SessionState(
            sessionId: 'resumed', cwd: '/repo', agentStatus: AgentStatus.settled,
            entries: [
              SessionEntry(id: 'first', role: 'assistant', text: '', timestamp: 1000,
                toolCalls: [ToolExecutionState(toolCallId: 'call-first', toolName: 'Agent',
                  output: 'Agent started in background.\nAgent ID: resumed-1\nType: delegate')]),
              SessionEntry(id: 'done', role: 'custom', timestamp: 2000,
                text: '<task-notification><task-id>resumed-1</task-id><tool-use-id>call-first</tool-use-id><status>Done</status><summary>Done</summary></task-notification>'),
              SessionEntry(id: 'resumed', role: 'assistant', text: '', timestamp: 3000,
                toolCalls: [ToolExecutionState(toolCallId: 'call-resume', toolName: 'Agent',
                  args: {'resume': 'resumed-1'},
                  output: 'Agent started in background.\nAgent ID: resumed-1\nType: delegate')]),
            ],
          ),
      ),
    ]);
    addTearDown(container.dispose);
    final subscription = container.listen(subagentsFamily('resumed'), (_, _) {});
    addTearDown(subscription.close);
    final agents = container.read(subagentsFamily('resumed'));
    expect(agents, hasLength(1));
    expect(agents.single.status, 'running');
    expect(agents.single.toolCallId, 'call-resume');
  });

  testWidgets('stale daemon result cannot finish a resumed launch', (tester) async {
    final client = _CostClient()..rows = [
      {'id': 'resumed-1', 'toolCallId': 'call-first', 'status': 'completed'},
    ];
    final container = ProviderContainer(overrides: [
      pcpClientProvider.overrideWithValue(client),
      sessionStateFamily('resumed-stale').overrideWith(
        (ref) => SessionStateNotifier('resumed-stale', null)
          ..state = const SessionState(
            sessionId: 'resumed-stale', cwd: '/repo', agentStatus: AgentStatus.settled,
            entries: [SessionEntry(id: 'resumed', role: 'assistant', text: '', timestamp: 3000,
              toolCalls: [ToolExecutionState(toolCallId: 'call-resume', toolName: 'Agent',
                output: 'Agent started in background.\nAgent ID: resumed-1\nType: delegate')])],
          ),
      ),
    ]);
    final subscription = container.listen(subagentsFamily('resumed-stale'), (_, _) {});
    var disposed = false;
    addTearDown(() {
      if (!disposed) { subscription.close(); container.dispose(); client.dispose(); }
    });
    await tester.pump();
    final agent = container.read(subagentsFamily('resumed-stale')).single;
    expect(agent.status, 'running');
    expect(agent.toolCallId, 'call-resume');
    disposed = true;
    subscription.close();
    container.dispose();
    client.dispose();
    await tester.pump(const Duration(milliseconds: 1));
  });

  for (final (rawStatus, expectedStatus) in [
    ('error', 'error'), ('stopped', 'stopped'), ('aborted', 'stopped'), ('steered', 'steered'),
  ]) {
    test('consumed $rawStatus result updates the existing agent', () {
      final container = ProviderContainer(overrides: [
        pcpClientProvider.overrideWithValue(null),
        sessionStateFamily('result-status').overrideWith(
          (ref) => SessionStateNotifier('result-status', null)
            ..state = SessionState(
              sessionId: 'result-status', cwd: '/repo', agentStatus: AgentStatus.settled,
              entries: [
                const SessionEntry(id: 'launch', role: 'assistant', text: '', timestamp: 1000,
                  toolCalls: [ToolExecutionState(toolCallId: 'call-agent', toolName: 'Agent',
                    output: 'Agent started in background.\nAgent ID: result-agent\nType: delegate')]),
                SessionEntry(id: 'result', role: 'assistant', text: '', timestamp: 2000,
                  toolCalls: [ToolExecutionState(toolCallId: 'call-result', toolName: 'get_subagent_result',
                    output: 'Agent: result-agent\nType: delegate | Status: $rawStatus | Tool uses: 3\nDescription: Task')]),
              ],
            ),
        ),
      ]);
      addTearDown(container.dispose);
      final subscription = container.listen(subagentsFamily('result-status'), (_, _) {});
      addTearDown(subscription.close);
      expect(container.read(subagentsFamily('result-status')).single.status, expectedStatus);
    });
  }

  testWidgets('agent result and notification merge into the launched agent', (
    tester,
  ) async {
    const agentId = 'c44c9b4f-1234-456';
    final client = _CostClient()
      ..rows = [
        {
          'id': agentId,
          'name': 'reviewer#c44c9b4f',
          'toolCallId': 'call-agent',
          'sessionId': 'child-session',
          'model': 'actual-model',
          'cost': 0.0175,
          'status': 'completed',
        },
      ];
    final container = ProviderContainer(overrides: [
      pcpClientProvider.overrideWithValue(client),
      sessionStateFamily('realistic').overrideWith(
        (ref) => SessionStateNotifier('realistic', null)
          ..state = const SessionState(
            sessionId: 'realistic',
            cwd: '/repo',
            entries: [
              SessionEntry(
                id: 'launch',
                role: 'assistant',
                text: '',
                timestamp: 1000,
                toolCalls: [
                  ToolExecutionState(
                    toolCallId: 'call-agent',
                    toolName: 'Agent',
                    args: {
                      'subagent_type': 'reviewer',
                      'description': 'Review pending cost changes',
                    },
                    output: 'Agent ID: $agentId\nType: reviewer',
                  ),
                  ToolExecutionState(
                    toolCallId: 'call-result',
                    toolName: 'get_subagent_result',
                    args: {'agent_id': agentId},
                    output: 'Type: reviewer | Status: completed | Tool uses: 10',
                  ),
                  ToolExecutionState(
                    toolCallId: 'call-steer',
                    toolName: 'steer_subagent',
                    args: {'agent_id': agentId, 'message': 'Continue'},
                    output: 'Steering message sent',
                  ),
                ],
              ),
              SessionEntry(
                id: 'notification',
                role: 'user',
                timestamp: 2000,
                text: '''<task-notification>
<task-id>$agentId</task-id>
<tool-use-id>call-agent</tool-use-id>
<status>Done</status>
<summary>Agent "Review pending cost changes" completed</summary>
<result>Review completed.</result>
</task-notification>''',
              ),
            ],
          ),
      ),
    ]);
    addTearDown(() {
      container.dispose();
      client.dispose();
    });
    final subscription = container.listen(subagentsFamily('realistic'), (_, _) {});
    addTearDown(subscription.close);
    await tester.pump();
    final children = container.read(subagentsFamily('realistic'));
    expect(children, hasLength(1));
    expect(children.single.id, agentId);
    expect(children.single.name, 'Review pending cost changes');
    expect(children.single.model, 'actual-model');
    expect(children.single.cost, 0.0175);
    expect(children.single.toolCallId, 'call-agent');
  });

  testWidgets('distinct agents with the same description remain distinct', (
    tester,
  ) async {
    final client = _CostClient()
      ..rows = [
        {'id': 'agent-1', 'toolCallId': 'call-1', 'name': 'reviewer#11111111', 'description': 'Review code', 'cost': 0.01, 'status': 'completed'},
        {'id': 'agent-2', 'toolCallId': 'call-2', 'name': 'reviewer#22222222', 'description': 'Review code', 'cost': 0.02, 'status': 'completed'},
      ];
    final container = ProviderContainer(overrides: [
      pcpClientProvider.overrideWithValue(client),
      sessionStateFamily('concurrent').overrideWith(
        (ref) => SessionStateNotifier('concurrent', null)
          ..state = const SessionState(
            sessionId: 'concurrent',
            cwd: '/repo',
            entries: [
              SessionEntry(
                id: 'launches',
                role: 'assistant',
                text: '',
                timestamp: 1000,
                toolCalls: [
                  ToolExecutionState(toolCallId: 'call-1', toolName: 'Agent', args: {'description': 'Review code'}),
                  ToolExecutionState(toolCallId: 'call-2', toolName: 'Agent', args: {'description': 'Review code'}),
                ],
              ),
            ],
          ),
      ),
    ]);
    addTearDown(() {
      container.dispose();
      client.dispose();
    });
    final subscription = container.listen(subagentsFamily('concurrent'), (_, _) {});
    addTearDown(subscription.close);
    await tester.pump();
    final agents = container.read(subagentsFamily('concurrent'));
    expect(agents.map((agent) => agent.id).toSet(), {'agent-1', 'agent-2'});
    expect(agents.fold<double>(0, (total, agent) => total + agent.cost!), closeTo(0.03, 0.000001));
  });

  testWidgets('ambiguous child is visible without an extra agent card', (tester) async {
    final client = _CostClient()
      ..rows = [
        {'id': 'agent-1', 'name': 'First agent', 'status': 'completed'},
        {'id': 'agent-2', 'name': 'Second agent', 'status': 'completed'},
        {'id': 'child', 'name': 'reviewer#12345678', 'cost': 0.015, 'status': 'completed', 'unlinked': true},
      ];
    final container = ProviderContainer(overrides: [
      pcpClientProvider.overrideWithValue(client),
      sessionStateFamily('ambiguous').overrideWith(
        (ref) => SessionStateNotifier('ambiguous', null)
          ..state = const SessionState(sessionId: 'ambiguous', cwd: '/repo', sessionStats: {'cost': 0.02}),
      ),
    ]);
    addTearDown(() { container.dispose(); client.dispose(); });
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
        home: const Scaffold(body: SubagentsPopDown(sessionId: 'ambiguous')),
      ),
    ));
    await tester.pump();
    expect(find.text('Subagenti (2)'), findsOneWidget);
    expect(find.byKey(const ValueKey('subagent-card-agent-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('subagent-card-agent-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('subagent-card-child')), findsNothing);
    expect(find.textContaining('Sessione figlia non attribuita: reviewer#12345678'), findsOneWidget);
    expect(find.text('Parziale \$0.0150'), findsNothing);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [FrameTokens.dark]),
        home: const Scaffold(body: TranscriptView(sessionId: 'ambiguous')),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('\$0.0200'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cost-breakdown-subagents-row')));
    await tester.pumpAndSettle();
    expect(find.text('Costi sessioni figlie (2 agenti)'), findsOneWidget);
    expect(find.byKey(const ValueKey('unlinked-session-cost-child')), findsOneWidget);
    expect(find.byKey(const ValueKey('subagent-cost-item-child')), findsNothing);
    expect(find.textContaining('Parziale \$0.0150'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('wrapped notification is terminal while parent is active', () {
    final container = ProviderContainer(overrides: [
      pcpClientProvider.overrideWithValue(null),
      sessionStateFamily('wrapped').overrideWith(
        (ref) => SessionStateNotifier('wrapped', null)
          ..state = const SessionState(
            sessionId: 'wrapped',
            cwd: '/repo',
            agentStatus: AgentStatus.working,
            entries: [
              SessionEntry(
                id: 'launch', role: 'assistant', text: '', timestamp: 1000,
                toolCalls: [ToolExecutionState(toolCallId: 'call-wrapped', toolName: 'Agent', args: {'description': 'Review code'})],
              ),
              SessionEntry(
                id: 'notification', role: 'custom', timestamp: 1001,
                text: '<task-notification><task-id>wrapped-id</task-id><tool-use-id>call-wrapped</tool-use-id><status>WRAPPED UP (TURN LIMIT)</status><summary>Agent finished</summary></task-notification>',
              ),
            ],
          ),
      ),
    ]);
    addTearDown(container.dispose);
    final subscription = container.listen(subagentsFamily('wrapped'), (_, _) {});
    addTearDown(subscription.close);
    final agent = container.read(subagentsFamily('wrapped')).single;
    expect(agent.status, 'steered');
    expect(agent.isRunning, isFalse);
    expect(agent.isCompleted, isTrue);
  });

  test('steering an active agent keeps it running', () async {
    final container = ProviderContainer(overrides: [
      pcpClientProvider.overrideWithValue(null),
      sessionStateFamily('steer').overrideWith(
        (ref) => SessionStateNotifier('steer', null)
          ..state = const SessionState(
            sessionId: 'steer', cwd: '/repo', agentStatus: AgentStatus.working,
            activeToolCalls: {
              'call-steer': ToolExecutionState(
                toolCallId: 'call-steer', toolName: 'Agent', args: {}, isRunning: true,
              ),
            },
          ),
      ),
    ]);
    addTearDown(container.dispose);
    final subscription = container.listen(subagentsFamily('steer'), (_, _) {});
    addTearDown(subscription.close);
    await container.read(subagentsFamily('steer').notifier).steerSubagent('call-steer', 'Continue');
    final agent = container.read(subagentsFamily('steer')).single;
    expect(agent.status, 'steering');
    expect(agent.isRunning, isTrue);
    container.read(sessionStateFamily('steer').notifier).state = const SessionState(
      sessionId: 'steer', cwd: '/repo', agentStatus: AgentStatus.working,
      entries: [
        SessionEntry(
          id: 'launch', role: 'assistant', text: '', timestamp: 1000,
          toolCalls: [ToolExecutionState(toolCallId: 'call-steer', toolName: 'Agent', args: {})],
        ),
        SessionEntry(
          id: 'done', role: 'custom', timestamp: 1001,
          text: '<task-notification><task-id>done-agent</task-id><tool-use-id>call-steer</tool-use-id><status>Done</status><summary>Agent finished</summary></task-notification>',
        ),
      ],
    );
    final completed = container.read(subagentsFamily('steer')).single;
    expect(completed.status, 'completed');
    expect(completed.isRunning, isFalse);
  });

  testWidgets('orphan notifications and workflow tools do not create agents', (
    tester,
  ) async {
    final client = _CostClient()..rows = [];
    final container = ProviderContainer(overrides: [
      pcpClientProvider.overrideWithValue(client),
      sessionStateFamily('nonagents').overrideWith(
        (ref) => SessionStateNotifier('nonagents', null)
          ..state = const SessionState(
            sessionId: 'nonagents',
            cwd: '/repo',
            entries: [
              SessionEntry(
                id: 'workflow',
                role: 'assistant',
                timestamp: 1000,
                text: '',
                toolCalls: [
                  ToolExecutionState(
                    toolCallId: 'workflow-call',
                    toolName: 'SubagentWorkflow',
                    args: {},
                    output: 'Workflow completed',
                  ),
                  ToolExecutionState(
                    toolCallId: 'status-call',
                    toolName: 'get_subagent_status',
                    args: {'subagent_type': 'reviewer'},
                  ),
                  ToolExecutionState(
                    toolCallId: 'config-call',
                    toolName: 'configure_tool',
                    args: {'agent_model': 'requested-model'},
                  ),
                ],
              ),
              SessionEntry(
                id: 'notification',
                role: 'user',
                timestamp: 2000,
                text: '''<task-notification>
<task-id>workflow-task</task-id>
<tool-use-id>workflow-call</tool-use-id>
<status>Done</status>
<summary>Workflow completed</summary>
<result>All work finished.</result>
</task-notification>''',
              ),
            ],
          ),
      ),
    ]);
    addTearDown(() {
      container.dispose();
      client.dispose();
    });
    final subscription = container.listen(subagentsFamily('nonagents'), (_, _) {});
    addTearDown(subscription.close);
    await tester.pump();
    expect(container.read(subagentsFamily('nonagents')), isEmpty);
  });

  testWidgets('agent output and prompt prices are not treated as actual cost', (
    tester,
  ) async {
    final client = _CostClient()..rows = [];
    final container = ProviderContainer(overrides: [
      pcpClientProvider.overrideWithValue(client),
      sessionStateFamily('unknown-cost').overrideWith(
        (ref) => SessionStateNotifier('unknown-cost', null)
          ..state = const SessionState(
            sessionId: 'unknown-cost',
            cwd: '/repo',
            entries: [
              SessionEntry(
                id: 'launch',
                role: 'assistant',
                text: 'Example price: \$12.50',
                timestamp: 1000,
                toolCalls: [
                  ToolExecutionState(
                    toolCallId: 'call-agent',
                    toolName: 'Agent',
                    args: {'subagent_type': 'reviewer', 'cost': 99.0},
                    output: 'The service cost: \$7.50',
                  ),
                ],
              ),
            ],
          ),
      ),
    ]);
    addTearDown(() {
      container.dispose();
      client.dispose();
    });
    final subscription = container.listen(subagentsFamily('unknown-cost'), (_, _) {});
    addTearDown(subscription.close);
    await tester.pump();
    expect(container.read(subagentsFamily('unknown-cost')).single.cost, isNull);
  });

  testWidgets('empty successful refresh clears daemon-only children but errors do not', (
    tester,
  ) async {
    final client = _CostClient();
    final session = SessionStateNotifier('refresh', null)
      ..state = const SessionState(sessionId: 'refresh', cwd: '/repo');
    final container = ProviderContainer(overrides: [
      pcpClientProvider.overrideWithValue(client),
      sessionStateFamily('refresh').overrideWith((ref) => session),
    ]);
    addTearDown(() {
      container.dispose();
      client.dispose();
    });
    final subscription = container.listen(subagentsFamily('refresh'), (_, _) {});
    addTearDown(subscription.close);
    await tester.pump();
    expect(container.read(subagentsFamily('refresh')), hasLength(1));

    client.fail = true;
    session.state = session.state.copyWith(agentStatus: AgentStatus.working);
    await tester.pump();
    expect(container.read(subagentsFamily('refresh')), hasLength(1));

    client.fail = false;
    client.rows = [];
    session.state = session.state.copyWith(agentStatus: AgentStatus.settled);
    await tester.pump();
    expect(container.read(subagentsFamily('refresh')), isEmpty);
  });

  testWidgets('verified child metadata survives parent updates', (tester) async {
    final client = _CostClient();
    final session = SessionStateNotifier('metadata', null)
      ..state = const SessionState(
        sessionId: 'metadata',
        cwd: '/repo',
        currentModel: 'parent-model',
        entries: [
          SessionEntry(
            id: 'tool-entry',
            role: 'assistant',
            text: '',
            timestamp: 0,
            toolCalls: [
              ToolExecutionState(
                toolCallId: 'call-1',
                toolName: 'Agent',
                args: {'model': 'requested-model'},
                output: 'Agent ID: worker#1\nCost: \$0.0100',
              ),
            ],
          ),
        ],
      );
    final container = ProviderContainer(overrides: [
      pcpClientProvider.overrideWithValue(client),
      sessionStateFamily('metadata').overrideWith((ref) => session),
    ]);
    addTearDown(() {
      container.dispose();
      client.dispose();
    });
    final subscription = container.listen(subagentsFamily('metadata'), (_, _) {});
    addTearDown(subscription.close);
    await tester.pump();
    expect(container.read(subagentsFamily('metadata')).single.model, 'test-model');
    expect(container.read(subagentsFamily('metadata')).single.cost, client.cost);

    session.state = session.state.copyWith(sessionStats: const {'cost': 1.0});
    await tester.pump();
    final child = container.read(subagentsFamily('metadata')).single;
    expect(child.model, 'test-model');
    expect(child.cost, client.cost);
  });

  testWidgets('daemon links a child to its active call without duplicate cost', (tester) async {
    final client = _CostClient()..toolCallId = 'running-call';
    final container = ProviderContainer(overrides: [
      pcpClientProvider.overrideWithValue(client),
      sessionStateFamily('linked').overrideWith(
        (ref) => SessionStateNotifier('linked', null)
          ..state = const SessionState(
            sessionId: 'linked',
            cwd: '/repo',
            activeToolCalls: {
              'running-call': ToolExecutionState(
                toolCallId: 'running-call',
                toolName: 'Agent',
                args: {'model': 'requested-model'},
                isRunning: true,
              ),
            },
          ),
      ),
    ]);
    addTearDown(() {
      container.dispose();
      client.dispose();
    });
    final subscription = container.listen(subagentsFamily('linked'), (_, _) {});
    addTearDown(subscription.close);
    await tester.pump();
    final children = container.read(subagentsFamily('linked'));
    expect(children, hasLength(1));
    expect(children.single.id, 'worker#1');
    expect(children.single.toolCallId, 'running-call');
    expect(children.single.model, 'test-model');
    expect(children.single.cost, client.cost);
    expect(children.single.isRunning, isTrue);
    final session = container.read(sessionStateFamily('linked').notifier);
    session.state = session.state.copyWith(activeToolCalls: const {});
    await tester.pump();
  });

  testWidgets('daemon costs keep refreshing in cards and the open cost popup', (
    tester,
  ) async {
    final client = _CostClient();
    final notifier = SessionStateNotifier('costs', null)
      ..state = const SessionState(
        sessionId: 'costs',
        cwd: '/repo',
        agentStatus: AgentStatus.working,
        sessionStats: {'cost': 0.02},
      );
    final container = ProviderContainer(
      overrides: [
        daemonEndpointProvider.overrideWith((ref) async => null),
        pcpClientProvider.overrideWithValue(client),
        sessionStateFamily('costs').overrideWith((ref) => notifier),
      ],
    );
    addTearDown(() {
      container.dispose();
      client.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [FrameTokens.dark],
          ),
          home: const Scaffold(body: TranscriptView(sessionId: 'costs')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(subagentsFamily('costs')).single.cost, 0.0175);
    await tester.tap(find.byKey(const ValueKey('subagents-book-tab')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('\$0.0175'), findsWidgets);

    await tester.tap(find.textContaining('\$0.0200'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find.byKey(const ValueKey('cost-breakdown-subagents-row')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Costi Subagenti & Modelli'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('\$0.0175')),
      findsNWidgets(2),
    );

    final callsBefore = client.calls;
    client.cost = 0.0425;
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(client.calls, greaterThan(callsBefore));
    expect(container.read(subagentsFamily('costs')).single.cost, 0.0425);
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('\$0.0425')),
      findsNWidgets(2),
    );
    await tester.tap(find.byKey(const ValueKey('cost-breakdown-back-btn')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('\$0.0200')),
      findsNWidgets(2),
    );
    await tester.tap(find.byKey(const ValueKey('cost-breakdown-close-btn')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('\$0.0425'), findsWidgets);
    expect(find.textContaining('\$0.0200'), findsOneWidget);
    expect(find.textContaining('\$0.0625'), findsNothing);

    // A settled parent with no running children no longer needs polling.
    notifier.state = notifier.state.copyWith(agentStatus: AgentStatus.settled);
    await tester.pumpAndSettle();
    final settledCalls = client.calls;
    await tester.pump(const Duration(seconds: 10));
    expect(client.calls, settledCalls);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
