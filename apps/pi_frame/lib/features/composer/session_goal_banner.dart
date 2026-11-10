import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/goal/session_goal_provider.dart';
import '../../data/language/language_settings.dart';

class SessionGoalBanner extends ConsumerWidget {
  const SessionGoalBanner({super.key, required this.sessionId});
  final String sessionId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goal = ref.watch(sessionGoalProvider(sessionId));
    if (goal == null || goal.isEmpty) return const SizedBox.shrink();
    final italian = ref.watch(appLanguageProvider) == AppLanguage.it;
    final tokens = context.tokens;
    return Container(
      key: const ValueKey('session-goal-banner'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      color: tokens.accent.withValues(alpha: 0.09),
      child: Row(
        children: [
          Icon(Icons.flag_outlined, size: 15, color: tokens.accent),
          const SizedBox(width: 8),
          Text(
            italian ? 'GOAL' : 'GOAL',
            style: TextStyle(
              color: tokens.accent,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              goal,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tokens.textPrimary, fontSize: 12),
            ),
          ),
          IconButton(
            tooltip: italian ? 'Rimuovi goal' : 'Clear goal',
            visualDensity: VisualDensity.compact,
            onPressed: () =>
                ref.read(sessionGoalProvider(sessionId).notifier).setGoal(null),
            icon: Icon(Icons.close, size: 14, color: tokens.textMuted),
          ),
        ],
      ),
    );
  }
}
