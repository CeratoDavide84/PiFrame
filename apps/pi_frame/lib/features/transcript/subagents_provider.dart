import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../data/daemon/pcp_client.dart';
import '../../domain/session/agent_status.dart';
import '../../domain/session/session_state.dart';
import 'task_notification_card.dart';

class SubagentItem {
  final String id;
  final String name;
  final String? model;
  final double? cost;
  final String output;
  final String status; // 'running', 'steering', 'completed', 'steered', 'stopped', 'error'
  final String? description;
  final String? toolCallId;
  final String? outputFile;
  final int? timestamp;
  final bool isSteeringOpen;
  final bool isUnlinked;

  const SubagentItem({
    required this.id,
    required this.name,
    this.model,
    this.cost,
    this.output = '',
    this.status = 'running',
    this.description,
    this.toolCallId,
    this.outputFile,
    this.timestamp,
    this.isSteeringOpen = false,
    this.isUnlinked = false,
  });

  bool get isRunning => status == 'running' || status == 'steering';
  bool get isCompleted => status == 'completed' || status == 'steered';
  bool get isStopped => status == 'stopped';
  bool get isSteered => status == 'steered' || status == 'steering';
  bool get isError => status == 'error';

  SubagentItem copyWith({
    String? id,
    String? name,
    String? model,
    double? cost,
    String? output,
    String? status,
    String? description,
    String? toolCallId,
    String? outputFile,
    int? timestamp,
    bool? isSteeringOpen,
    bool? isUnlinked,
  }) {
    return SubagentItem(
      id: id ?? this.id,
      name: name ?? this.name,
      model: model ?? this.model,
      cost: cost ?? this.cost,
      output: output ?? this.output,
      status: status ?? this.status,
      description: description ?? this.description,
      toolCallId: toolCallId ?? this.toolCallId,
      outputFile: outputFile ?? this.outputFile,
      timestamp: timestamp ?? this.timestamp,
      isSteeringOpen: isSteeringOpen ?? this.isSteeringOpen,
      isUnlinked: isUnlinked ?? this.isUnlinked,
    );
  }
}

class SubagentsNotifier extends StateNotifier<List<SubagentItem>> {
  final Ref ref;
  final String sessionId;
  ProviderSubscription? _subscription;
  Timer? _refreshTimer;
  final Set<String> _locallyStopped = <String>{};
  final Set<String> _locallySteered = <String>{};
  final Set<String> _openSteeringIds = <String>{};
  bool _fetchingFromDaemon = false;
  List<Map<String, dynamic>> _daemonSubagents = const [];

  SubagentsNotifier(this.ref, this.sessionId) : super([]) {
    _init();
  }

  void _init() {
    _listenToSession();
    _fetchFromDaemon();
  }

  void _listenToSession() {
    _subscription = ref.listen<SessionState>(
      sessionStateFamily(sessionId),
      (prev, next) {
        _syncFromSessionState(next);
        final shouldFetch = prev == null ||
            prev.agentStatus != next.agentStatus ||
            prev.activeToolCalls.length != next.activeToolCalls.length ||
            prev.entries.length != next.entries.length;
        if (shouldFetch) {
          _fetchFromDaemon();
        }
      },
      fireImmediately: true,
    );
  }

  void _checkTimer() {
    // Child sessions run outside agentd, so its status can lag live activity.
    final hasActive = state.any((s) => s.isRunning) ||
        (state.isNotEmpty && ref.read(sessionStateFamily(sessionId)).isStreaming);
    if (hasActive) {
      _refreshTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
        _syncFromSessionState();
        _fetchFromDaemon();
        _readOutputFiles();
      });
    } else {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    }
  }

  @override
  void dispose() {
    _subscription?.close();
    _refreshTimer?.cancel();
    _refreshTimer = null;
    super.dispose();
  }

  void _syncFromSessionState([SessionState? currentSessionState]) {
    try {
      final SessionState? sessionState = currentSessionState ?? ref.read(sessionStateFamily(sessionId));
      if (sessionState == null) return;
      final previousItems = {for (final item in state) item.id: item};
      final Map<String, SubagentItem> itemsMap = {};
      final notifications = <(TaskNotificationData, int, int)>[];
      final terminalResults = <String, (String, int)>{};
      final latestLaunch = <String, int>{};

      // Build the agent list from calls and persisted children, not notifications.
      for (var entryIndex = 0; entryIndex < sessionState.entries.length; entryIndex++) {
        final entry = sessionState.entries[entryIndex];
        for (final match in RegExp(
          r'<task-notification>[\s\S]*?</task-notification>',
          caseSensitive: false,
        ).allMatches(entry.text)) {
          final notification = TaskNotificationData.tryParse(match.group(0)!);
          if (notification != null) notifications.add((notification, entry.timestamp, entryIndex));
        }
        for (final tool in entry.toolCalls) {
          if (_isSubagentTool(tool)) {
            final subagent = _parseFromTool(tool);
            if (subagent != null) {
              terminalResults.remove(subagent.id);
              final linked = _findByToolCallId(itemsMap, subagent.toolCallId);
              final existing = linked ?? itemsMap[subagent.id] ??
                  previousItems[subagent.id] ??
                  _findByToolCallId(previousItems, subagent.toolCallId);
              final id = existing?.id ?? subagent.id;
              latestLaunch[subagent.id] = entryIndex;
              latestLaunch[id] = entryIndex;
              if (id != subagent.id) itemsMap.remove(subagent.id);
              final status = _locallyStopped.contains(id) ||
                      _locallyStopped.contains(subagent.id)
                  ? 'stopped'
                  : _locallySteered.contains(id) ||
                          _locallySteered.contains(subagent.id)
                      ? 'steering'
                      : subagent.status;
              final isSteeringOpen = _openSteeringIds.contains(id) ||
                  _openSteeringIds.contains(subagent.id);
              itemsMap[id] = subagent.copyWith(
                id: id,
                name: existing?.name ?? subagent.name,
                model: subagent.model ?? existing?.model,
                output: subagent.output.isNotEmpty
                    ? subagent.output
                    : existing?.output ?? '',
                cost: subagent.cost ?? existing?.cost,
                description: existing?.description ?? subagent.description,
                outputFile: subagent.outputFile ?? existing?.outputFile,
                timestamp: existing?.timestamp ?? subagent.timestamp,
                status: status,
                isSteeringOpen: isSteeringOpen,
              );
            }
          } else {
            _recordTerminalResult(tool, terminalResults, entryIndex);
          }
        }
      }

      // 2. Process active tool calls in sessionState (overriding historical with active state)
      for (final tool in sessionState.activeToolCalls.values) {
        if (_isSubagentTool(tool)) {
          final subagent = _parseFromTool(tool);
          if (subagent != null) {
            final linked = _findByToolCallId(itemsMap, subagent.toolCallId);
            final existing = linked ?? itemsMap[subagent.id] ??
                previousItems[subagent.id] ??
                _findByToolCallId(previousItems, subagent.toolCallId);
            final id = existing?.id ?? subagent.id;
            if (id != subagent.id) itemsMap.remove(subagent.id);
            final status = _locallyStopped.contains(id) ||
                    _locallyStopped.contains(subagent.id)
                ? 'stopped'
                : _locallySteered.contains(id) ||
                        _locallySteered.contains(subagent.id)
                    ? 'steering'
                    : (tool.isRunning ? 'running' : subagent.status);
            final isSteeringOpen = _openSteeringIds.contains(id) ||
                _openSteeringIds.contains(subagent.id);
            itemsMap[id] = subagent.copyWith(
              id: id,
              name: existing?.name ?? subagent.name,
              model: subagent.model ?? existing?.model,
              output: subagent.output.isNotEmpty
                  ? subagent.output
                  : existing?.output ?? '',
              cost: subagent.cost ?? existing?.cost,
              description: existing?.description ?? subagent.description,
              outputFile: subagent.outputFile ?? existing?.outputFile,
              timestamp: existing?.timestamp ?? subagent.timestamp,
              status: status,
              isSteeringOpen: isSteeringOpen,
            );
          }
        } else {
          _recordTerminalResult(tool, terminalResults, sessionState.entries.length);
        }
      }
      // Persisted child metadata wins over requested models and stale tool text.
      _mergeDaemonSubagents(itemsMap);
      for (final result in terminalResults.entries) {
        final agent = itemsMap[result.key];
        if (agent == null) continue;
        _locallySteered.remove(result.key);
        itemsMap[result.key] = agent.copyWith(status: result.value.$1);
      }

      // Notifications update an existing agent; they are not agent launches.
      for (final (notification, timestamp, entryIndex) in notifications) {
        final existing = itemsMap[notification.taskId] ??
            _findByToolCallId(itemsMap, notification.toolUseId);
        if (existing == null) continue;
        if ((latestLaunch[notification.taskId] ?? latestLaunch[existing.id] ?? -1) > entryIndex ||
            (terminalResults[notification.taskId]?.$2 ?? -1) > entryIndex) continue;
        final id = existing.id == existing.toolCallId
            ? notification.taskId
            : existing.id;
        if (id != existing.id) itemsMap.remove(existing.id);
        _locallySteered.remove(id);
        if (existing.toolCallId != null) _locallySteered.remove(existing.toolCallId);
        final statusText = notification.status.toLowerCase();
        final isActive = existing.toolCallId != null &&
            sessionState.activeToolCalls[existing.toolCallId]?.isRunning == true;
        final status = isActive ? 'running' :
            statusText.contains('error') || statusText.contains('fail') ? 'error' :
            statusText.contains('stop') || statusText.contains('cancel') || statusText.contains('abort') ? 'stopped' :
            statusText.contains('wrapped') || statusText.contains('steered') ? 'steered' :
            'completed';
        final summaryName = RegExp(r'Agent\s+"([^"]+)"')
            .firstMatch(notification.summary)?.group(1);
        itemsMap[id] = existing.copyWith(
          id: id,
          name: existing.description ?? summaryName ?? existing.name,
          output: notification.result.isNotEmpty ? notification.result : existing.output,
          status: status,
          toolCallId: existing.toolCallId ?? notification.toolUseId,
          outputFile: notification.outputFile ?? existing.outputFile,
          timestamp: existing.timestamp ?? timestamp,
        );
      }

      state = itemsMap.values.toList();
      _checkTimer();
    } catch (_) {}
  }

  Future<void> _fetchFromDaemon() async {
    if (_fetchingFromDaemon) return;
    final client = ref.read(pcpClientProvider);
    if (client == null || client.state != DaemonConnectionState.connected) return;
    _fetchingFromDaemon = true;
    try {
      // Keep one request in flight so a slow response is not discarded or duplicated.
      final daemonSubagents = await client.getSubagents(sessionId);
      if (!mounted) return;
      final nextIds = daemonSubagents.map((raw) => raw['id']).toSet();
      final removedIds = _daemonSubagents
          .map((raw) => raw['id'])
          .where((id) => !nextIds.contains(id))
          .toSet();
      if (removedIds.isNotEmpty) {
        state = state.where((item) => !removedIds.contains(item.id)).toList();
      }
      _daemonSubagents = daemonSubagents;
      _syncFromSessionState();
    } catch (_) {
    } finally {
      _fetchingFromDaemon = false;
    }
  }

  void _mergeDaemonSubagents(Map<String, SubagentItem> itemsMap) {
    for (final raw in _daemonSubagents) {
      final id = (raw['id'] ?? '').toString();
      if (id.isEmpty) continue;
      final model = raw['model']?.toString();
      final rawCost = raw['cost'];
      final cost = rawCost is num && rawCost.isFinite && rawCost >= 0
          ? rawCost.toDouble()
          : null;
      final output = (raw['output'] ?? '').toString();
      final toolCallId = raw['toolCallId']?.toString();
      final childSessionId = raw['sessionId']?.toString();
      final linked = _findByToolCallId(itemsMap, toolCallId);
      final existing = itemsMap[id] ?? linked ?? itemsMap[childSessionId];
      // A response for an earlier run must not overwrite a resumed launch.
      if (existing != null && toolCallId != null && existing.toolCallId != null &&
          toolCallId != existing.toolCallId) continue;
      final name = (raw['unlinked'] == true
          ? raw['name'] ?? id
          : raw['description'] ?? existing?.name ?? raw['name'] ?? id).toString();
      final activeTool = toolCallId == null
          ? null
          : ref.read(sessionStateFamily(sessionId)).activeToolCalls[toolCallId];
      final status = _locallyStopped.contains(id)
          ? 'stopped'
          : _locallySteered.contains(id)
          ? 'steering'
          : activeTool?.isRunning == true
          ? 'running'
          : (raw['status'] ?? 'completed').toString();
      if (linked != null && linked.id != id) itemsMap.remove(linked.id);
      if (childSessionId != id) itemsMap.remove(childSessionId);
      final isSteeringOpen = _openSteeringIds.contains(id);
      itemsMap[id] = SubagentItem(
        id: id,
        name: name,
        model: model ?? existing?.model,
        cost: cost ?? existing?.cost,
        output: output.isNotEmpty ? output : (existing?.output ?? ''),
        status: status,
        description: raw['description']?.toString() ?? existing?.description,
        toolCallId: toolCallId ?? existing?.toolCallId,
        outputFile: existing?.outputFile,
        timestamp: existing?.timestamp,
        isSteeringOpen: isSteeringOpen,
        isUnlinked: raw['unlinked'] == true,
      );
    }
  }

  void _readOutputFiles() {
    // Subagent output files are read from the host disk; the browser gets the
    // streamed output from the daemon instead.
    if (kIsWeb) return;
    bool changed = false;
    final updated = state.map((item) {
      if (item.outputFile != null && item.outputFile!.isNotEmpty) {
        try {
          final file = File(item.outputFile!);
          if (file.existsSync()) {
            final content = file.readAsStringSync();
            if (content.isNotEmpty && content != item.output) {
              changed = true;
              return item.copyWith(output: content);
            }
          }
        } catch (_) {}
      }
      return item;
    }).toList();

    if (changed) {
      state = updated;
    }
  }

  bool _isSubagentTool(ToolExecutionState tool) {
    final lower = tool.toolName.toLowerCase();
    if (lower == 'get_subagent_result' ||
        lower == 'steer_subagent' ||
        lower == 'stop_subagent' ||
        lower == 'list_subagents' ||
        lower == 'subagentworkflow') {
      return false;
    }
    if (const {
      'agent', 'subagent', 'delegate', 'spawn_agent', 'run_agent', 'invoke_agent',
    }.contains(lower)) return true;
    final subagentType = tool.args['subagent_type'];
    return subagentType is String && subagentType.toLowerCase() == lower;
  }

  SubagentItem? _findByToolCallId(
    Map<String, SubagentItem> items,
    String? toolCallId,
  ) {
    if (toolCallId == null || toolCallId.isEmpty) return null;
    for (final item in items.values) {
      if (item.toolCallId == toolCallId) return item;
    }
    return null;
  }

  void _recordTerminalResult(
    ToolExecutionState tool, Map<String, (String, int)> results, int entryIndex,
  ) {
    if (tool.toolName.toLowerCase() != 'get_subagent_result' || tool.isRunning || tool.isError) return;
    final match = RegExp(
      r'^Agent:\s*([^\r\n]+)\r?\nType:[^\r\n]*\|\s*Status:\s*(completed|error|steered|stopped|aborted)\b',
      caseSensitive: false,
    ).firstMatch(tool.output);
    if (match == null) return;
    final status = match.group(2)!.toLowerCase();
    results[match.group(1)!.trim()] = (status == 'aborted' ? 'stopped' : status, entryIndex);
  }

  SubagentItem? _parseFromTool(ToolExecutionState tool) {
    final args = tool.args;
    String id = tool.toolCallId;
    String name = (args['subagent_type'] ?? args['name'] ?? args['type'] ?? 'Subagente').toString();
    String? description = args['description']?.toString() ?? args['prompt']?.toString();
    String? outputFile;

    final output = tool.output;
    if (output.isNotEmpty) {
      final notif = TaskNotificationData.tryParse(output);
      if (notif != null) {
        id = notif.taskId;
        final agentNameMatch = RegExp(r'Agent\s+"([^"]+)"').firstMatch(notif.summary);
        if (agentNameMatch != null && agentNameMatch.group(1) != null) {
          name = agentNameMatch.group(1)!;
        } else if (notif.summary.isNotEmpty) {
          name = notif.summary;
        }
        if (notif.outputFile != null) {
          outputFile = notif.outputFile;
        }
        if (description == null && notif.summary.isNotEmpty) {
          description = notif.summary;
        }
      }

      // Parse Agent ID: xxx
      final idMatch = RegExp(r'Agent ID:\s*([^\r\n]+)').firstMatch(output);
      if (idMatch != null && idMatch.group(1) != null) {
        id = idMatch.group(1)!.trim();
      }

      // Parse Type: xxx
      final typeMatch = RegExp(r'Type:\s*([^\r\n]+)').firstMatch(output);
      if (typeMatch != null && typeMatch.group(1) != null) {
        name = typeMatch.group(1)!.trim();
      }

      // Parse Output file: xxx
      final fileMatch = RegExp(r'Output file:\s*([^\r\n]+)').firstMatch(output);
      if (fileMatch != null && fileMatch.group(1) != null) {
        outputFile = fileMatch.group(1)!.trim();
      }

    }

    final launchedInBackground = tool.toolName.toLowerCase() == 'agent' &&
        RegExp(r'(^|\n)Agent (started|queued) in background\.', caseSensitive: false)
            .hasMatch(output);
    final status = tool.isError
        ? 'error'
        : tool.isRunning || launchedInBackground
        ? 'running'
        : 'completed';

    return SubagentItem(
      id: id,
      name: name,
      output: output,
      status: status,
      description: description,
      toolCallId: tool.toolCallId,
      outputFile: outputFile,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      isSteeringOpen: _openSteeringIds.contains(id),
    );
  }

  void toggleSteering(String subagentId) {
    if (_openSteeringIds.contains(subagentId)) {
      _openSteeringIds.remove(subagentId);
    } else {
      _openSteeringIds.add(subagentId);
    }
    state = state.map((item) {
      if (item.id == subagentId) {
        return item.copyWith(isSteeringOpen: _openSteeringIds.contains(subagentId));
      }
      return item;
    }).toList();
  }

  Future<void> steerSubagent(String subagentId, String message) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;

    _locallySteered.add(subagentId);
    _openSteeringIds.remove(subagentId);

    state = state.map((item) {
      if (item.id == subagentId) {
        return item.copyWith(
          status: 'steering',
          isSteeringOpen: false,
          output: '${item.output}\n\n[Guida utente]: $trimmed',
        );
      }
      return item;
    }).toList();

    try {
      final client = ref.read(pcpClientProvider);
      if (client != null) {
        await client.steerSubagent(sessionId, subagentId, trimmed);
      }
    } catch (_) {}
  }

  Future<void> stopSubagent(String subagentId) async {
    _locallyStopped.add(subagentId);
    _openSteeringIds.remove(subagentId);

    state = state.map((item) {
      if (item.id == subagentId) {
        return item.copyWith(
          status: 'stopped',
          isSteeringOpen: false,
          output: '${item.output}\n\n[Interrotto dall\'utente]',
        );
      }
      return item;
    }).toList();

    try {
      final client = ref.read(pcpClientProvider);
      if (client != null) {
        await client.stopSubagent(sessionId, subagentId);
      }
    } catch (_) {}
  }
}

final subagentsFamily = StateNotifierProvider.autoDispose.family<SubagentsNotifier, List<SubagentItem>, String>(
  (ref, sessionId) => SubagentsNotifier(ref, sessionId),
);
