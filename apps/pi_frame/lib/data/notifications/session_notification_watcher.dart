import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/session/agent_status.dart';
import '../../domain/session/session_state.dart';
import '../language/language_settings.dart';
import '../daemon/daemon_providers.dart';
import '../../features/sessions_sidebar/pinned_sessions_provider.dart';
import 'notification_providers.dart';

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
    ref.read(desktopNotificationServiceProvider).onNotificationClicked =
        (sessionId) {
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
        _checkNotifications(prev, next, session);
      },
    );
    return const SizedBox.shrink();
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
            final title = req['title']?.toString() ??
                (isItalian ? 'Attenzione richiesta' : 'Attention required');
            final message = req['message']?.toString() ??
                (isItalian
                    ? 'L\'agente richiede una tua risposta o scelta.'
                    : 'The agent needs your response or choice.');
            unawaited(service.showNotification(
              title: isItalian
                  ? 'Richiesta attenzione · $sessionName'
                  : 'Attention required · $sessionName',
              body: '$title: $message',
              sessionId: widget.sessionId,
            ));
          }
        }
      }
    }

    // 2. Agent completed an answer
    final wasWorking = prev != null &&
        (prev.$1 == AgentStatus.working ||
            prev.$2 ||
            prev.$3);
    final isSettledNow = nextSummary.$1 != AgentStatus.working &&
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
        unawaited(service.showNotification(
          title: isItalian
              ? 'Risposta completata · $sessionName'
              : 'Response complete · $sessionName',
          body: preview,
          sessionId: widget.sessionId,
        ));
      }
    }
  }
}
