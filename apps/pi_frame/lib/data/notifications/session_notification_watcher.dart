import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/session/agent_status.dart';
import '../../domain/session/session_state.dart';
import '../language/language_settings.dart';
import '../daemon/daemon_providers.dart';
import '../../features/sessions_sidebar/pinned_sessions_provider.dart';
import 'notification_providers.dart';
import 'taskbar_status_reporter.dart';

class SessionNotificationWatcher extends ConsumerStatefulWidget {
  const SessionNotificationWatcher({super.key});

  @override
  ConsumerState<SessionNotificationWatcher> createState() =>
      _SessionNotificationWatcherState();
}

class _SessionNotificationWatcherState
    extends ConsumerState<SessionNotificationWatcher> {
  @override
  void initState() {
    super.initState();
    ref
        .read(desktopNotificationServiceProvider)
        .onNotificationClicked = (sessionId) {
      if (mounted) {
        ref.read(activeSessionIdProvider.notifier).state = sessionId;
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    final activeId = ref.watch(activeSessionIdProvider);
    final pinnedIds = ref.watch(pinnedSessionsProvider);
    final monitoredIds = <String>{
      if (activeId != null && activeId.isNotEmpty) activeId,
      ...pinnedIds,
    };

    return Stack(
      children: [
        for (final id in monitoredIds)
          _SessionWatcherItem(key: ValueKey('watcher_$id'), sessionId: id),
      ],
    );
  }
}

class _SessionWatcherItem extends ConsumerStatefulWidget {
  final String sessionId;

  const _SessionWatcherItem({super.key, required this.sessionId});

  @override
  ConsumerState<_SessionWatcherItem> createState() =>
      _SessionWatcherItemState();
}

class _SessionWatcherItemState extends ConsumerState<_SessionWatcherItem> {
  final Set<String> _handledUiRequestIds = <String>{};
  final Set<String> _handledEntryIds = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateTaskbar(ref.read(sessionStateFamily(widget.sessionId)));
    });
  }

  void _updateTaskbar(SessionState session) {
    final working = {...ref.read(taskbarWorkingSessionsProvider)};
    if (session.isStreaming) {
      working.add(widget.sessionId);
    } else {
      working.remove(widget.sessionId);
    }
    ref.read(taskbarWorkingSessionsProvider.notifier).state = working;
    final hasError =
        session.agentStatus == AgentStatus.error ||
        session.agentStatus == AgentStatus.workerError;
    final errors = {...ref.read(taskbarErrorSessionsProvider)};
    if (hasError) {
      errors.add(widget.sessionId);
    } else {
      errors.remove(widget.sessionId);
    }
    ref.read(taskbarErrorSessionsProvider.notifier).state = errors;
    final needsAttention = session.pendingUiRequests.any((request) {
      final method = request['method']?.toString();
      return request['dialog'] == true ||
          method == 'confirm' ||
          method == 'select' ||
          method == 'input' ||
          method == 'editor';
    });
    final attention = {...ref.read(taskbarAttentionSessionsProvider)};
    if (needsAttention) {
      attention.add(widget.sessionId);
    } else {
      attention.remove(widget.sessionId);
    }
    ref.read(taskbarAttentionSessionsProvider.notifier).state = attention;
    final questions = [
      ...ref
          .read(taskbarPendingQuestionsProvider)
          .where((question) => question['sessionId'] != widget.sessionId),
      ...session.pendingUiRequests
          .where((request) {
            final method = request['method']?.toString();
            final isSecretInput =
                method == 'input' &&
                (request['placeholder']?.toString() ?? '').startsWith(
                  'piframe-secret:',
                );
            return !isSecretInput &&
                (request['dialog'] == true ||
                    method == 'confirm' ||
                    method == 'select' ||
                    method == 'input' ||
                    method == 'editor');
          })
          .map(
            (request) => <String, dynamic>{
              ...request,
              'sessionId': widget.sessionId,
              'sessionName': session.sessionName ?? widget.sessionId,
            },
          ),
    ];
    ref.read(taskbarPendingQuestionsProvider.notifier).state = questions;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      sessionStateFamily(widget.sessionId).select(
        (s) => (
          s.agentStatus,
          s.isStreaming,
          s.activeToolCalls.isNotEmpty,
          s.pendingUiRequests.length,
          s.entries.length,
        ),
      ),
      (prev, next) {
        final session = ref.read(sessionStateFamily(widget.sessionId));
        _updateTaskbar(session);
        _checkNotifications(prev, next, session);
      },
    );
    return const SizedBox.shrink();
  }

  @override
  void dispose() {
    final working = {...ref.read(taskbarWorkingSessionsProvider)}
      ..remove(widget.sessionId);
    ref.read(taskbarWorkingSessionsProvider.notifier).state = working;
    final attention = {...ref.read(taskbarAttentionSessionsProvider)}
      ..remove(widget.sessionId);
    ref.read(taskbarAttentionSessionsProvider.notifier).state = attention;
    final errors = {...ref.read(taskbarErrorSessionsProvider)}
      ..remove(widget.sessionId);
    ref.read(taskbarErrorSessionsProvider.notifier).state = errors;
    super.dispose();
  }

  Future<void> _checkNotifications(
    (AgentStatus, bool, bool, int, int)? prev,
    (AgentStatus, bool, bool, int, int) nextSummary,
    SessionState next,
  ) async {
    final enabled = ref.read(notificationsEnabledProvider);
    if (!enabled) return;

    final service = ref.read(desktopNotificationServiceProvider);
    final isItalian = ref.read(appLanguageProvider) == AppLanguage.it;
    final isFocusedCached = ref.read(appFocusProvider);
    final isFocused = await service.checkIsAppFocused(isFocusedCached);
    if (isFocused) return;

    // 1. Attention required: interactive choice, question, or confirmation dialog
    if (nextSummary.$4 > 0) {
      final pendingInteraction = next.pendingUiRequests.where((r) {
        final method = r['method']?.toString();
        return r['dialog'] == true ||
            method == 'confirm' ||
            method == 'select' ||
            method == 'input' ||
            method == 'editor';
      }).toList();

      if (pendingInteraction.isNotEmpty) {
        for (final req in pendingInteraction) {
          final reqId = req['requestId']?.toString() ?? '';
          if (reqId.isNotEmpty && !_handledUiRequestIds.contains(reqId)) {
            _handledUiRequestIds.add(reqId);
            final sessionName = next.sessionName ?? widget.sessionId;
            final title =
                req['title']?.toString() ??
                (isItalian ? 'Attenzione richiesta' : 'Attention required');
            final message =
                req['message']?.toString() ??
                (isItalian
                    ? 'L\'agente richiede una tua risposta o scelta.'
                    : 'The agent needs your response or choice.');
            if (defaultTargetPlatform != TargetPlatform.windows) {
              unawaited(
                service.showNotification(
                  title: isItalian
                      ? 'Richiesta attenzione · $sessionName'
                      : 'Attention required · $sessionName',
                  body: '$title: $message',
                  sessionId: widget.sessionId,
                ),
              );
            }
          }
        }
      }
    }

    // 2. Agent completed an answer
    final wasWorking =
        prev != null && (prev.$1 == AgentStatus.working || prev.$2 || prev.$3);
    final isSettledNow =
        nextSummary.$1 != AgentStatus.working &&
        !nextSummary.$2 &&
        !nextSummary.$3;

    if (wasWorking && isSettledNow && next.entries.isNotEmpty) {
      final lastEntry = next.entries.last;
      if (lastEntry.role == 'assistant' &&
          !_handledEntryIds.contains(lastEntry.id)) {
        _handledEntryIds.add(lastEntry.id);
        final sessionName = next.sessionName ?? widget.sessionId;
        final rawText = lastEntry.text.trim();
        final preview = rawText.isNotEmpty
            ? (rawText.length > 120
                  ? '${rawText.substring(0, 120)}...'
                  : rawText)
            : (isItalian
                  ? 'L\'agente ha completato la risposta.'
                  : 'The agent has finished its response.');
        unawaited(
          service.showNotification(
            title: isItalian
                ? 'Risposta completata · $sessionName'
                : 'Response complete · $sessionName',
            body: preview,
            sessionId: widget.sessionId,
          ),
        );
      }
    }
  }
}
