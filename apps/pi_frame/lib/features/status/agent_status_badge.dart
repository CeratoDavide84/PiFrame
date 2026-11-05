import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/language/language_settings.dart';
import '../../domain/session/agent_status.dart';

class AgentStatusBadge extends ConsumerWidget {
  final AgentStatus status;
  final bool onDisplay;
  const AgentStatusBadge({
    super.key,
    required this.status,
    this.onDisplay = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isItalian = ref.watch(appLanguageProvider) == AppLanguage.it;
    final label = isItalian
        ? status.label
        : switch (status) {
            AgentStatus.idle => 'Idle',
            AgentStatus.working => 'Working',
            AgentStatus.retrying => 'Retrying...',
            AgentStatus.compacting => 'Compacting...',
            AgentStatus.awaitingUser => 'Waiting for input',
            AgentStatus.settled => 'Completed',
            AgentStatus.error => 'Error',
            AgentStatus.workerError => 'Worker stopped',
          };
    final tokens = context.tokens;
    final foreground = switch (status) {
      AgentStatus.idle || AgentStatus.settled => tokens.success,
      AgentStatus.working => tokens.agentWorking,
      AgentStatus.retrying => tokens.warning,
      AgentStatus.compacting => tokens.info,
      AgentStatus.awaitingUser => tokens.agentAwaitingUser,
      AgentStatus.error || AgentStatus.workerError => tokens.danger,
    };
    if (onDisplay) {
      final signal = switch (status) {
        AgentStatus.error || AgentStatus.workerError => tokens.signalDanger,
        AgentStatus.working ||
        AgentStatus.retrying ||
        AgentStatus.awaitingUser => tokens.signalWarning,
        _ => tokens.displayText,
      };
      return Semantics(
        liveRegion: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: signal,
                shape: BoxShape.circle,
                border: Border.all(color: tokens.borderStrong, width: 1),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: tokens.displayText,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }
    return Semantics(
      liveRegion: true,
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            foreground.withValues(alpha: 0.12),
            tokens.surface,
          ),
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          border: Border.all(color: tokens.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: foreground,
                shape: BoxShape.circle,
                border: Border.all(color: tokens.borderStrong, width: 1),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
