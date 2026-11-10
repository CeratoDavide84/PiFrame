import 'package:flutter/material.dart';
import '../../domain/session/session_state.dart';
import 'tool_card.dart';

class ToolTimeline extends StatelessWidget {
  final List<ToolExecutionState> toolCalls;
  final VoidCallback? onCardExpansionChanged;

  const ToolTimeline({
    super.key,
    required this.toolCalls,
    this.onCardExpansionChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (toolCalls.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < toolCalls.length; i++) ...[
            ToolCard(
              key: ValueKey(toolCalls[i].toolCallId),
              tool: toolCalls[i],
              onExpansionChanged: onCardExpansionChanged,
            ),
            if (i < toolCalls.length - 1)
              const SizedBox(height: 1),
          ],
        ],
      ),
    );
  }
}
