import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/language/language_settings.dart';
import 'subagents_provider.dart';

class SubagentsPopDown extends ConsumerStatefulWidget {
  final String sessionId;
  final VoidCallback? onClose;
  final bool? isExpanded;
  final VoidCallback? onToggleExpand;
  final bool hideBookTab;

  const SubagentsPopDown({
    super.key,
    required this.sessionId,
    this.onClose,
    this.isExpanded,
    this.onToggleExpand,
    this.hideBookTab = false,
  });

  @override
  ConsumerState<SubagentsPopDown> createState() => _SubagentsPopDownState();
}

class _SubagentsPopDownState extends ConsumerState<SubagentsPopDown>
    with SingleTickerProviderStateMixin {
  final Set<String> _expandedIds = <String>{};
  bool _internalExpanded = true;

  bool get _isExpanded => widget.isExpanded ?? _internalExpanded;

  void _handleToggle() {
    if (widget.onToggleExpand != null) {
      widget.onToggleExpand!();
    } else if (widget.onClose != null && _isExpanded) {
      widget.onClose!();
    } else {
      setState(() => _internalExpanded = !_internalExpanded);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appLanguageProvider);
    final tokens = context.tokens;
    final subagents = ref.watch(subagentsFamily(widget.sessionId));

    if (subagents.isEmpty) {
      return const SizedBox.shrink();
    }

    final agents = subagents.where((s) => !s.isUnlinked).toList();
    final agentCount = agents.length;
    final runningCount = agents.where((s) => s.isRunning).length;
    final knownCost = agents.fold<double>(
      0,
      (total, s) => total + (s.cost ?? 0),
    );
    final costLabel =
        '${agents.any((s) => s.cost == null) ? 'Parziale ' : ''}\$${knownCost.toStringAsFixed(4)}';

    final isMobile = MediaQuery.sizeOf(context).width < 600;

    final panelContent = _isExpanded
        ? Container(
            key: const ValueKey('subagents-popdown-panel'),
            margin: EdgeInsets.fromLTRB(
              isMobile ? 12 : 8,
              0,
              isMobile ? 12 : 8,
              6,
            ),
            decoration: BoxDecoration(
              color: tokens.surfaceElevated,
              borderRadius: widget.hideBookTab
                  ? BorderRadius.only(
                      topRight: Radius.circular(tokens.radiusMd),
                      bottomLeft: Radius.circular(tokens.radiusMd),
                      bottomRight: Radius.circular(tokens.radiusMd),
                    )
                  : BorderRadius.circular(tokens.radiusMd),
              border: Border.all(color: tokens.borderStrong, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: tokens.overlay.withValues(alpha: 0.16),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header of the popdown panel
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.surface,
                    borderRadius: widget.hideBookTab
                        ? BorderRadius.only(
                            topRight: Radius.circular(tokens.radiusMd),
                          )
                        : BorderRadius.only(
                            topLeft: Radius.circular(tokens.radiusMd),
                            topRight: Radius.circular(tokens.radiusMd),
                          ),
                    border: Border(
                      bottom: BorderSide(color: tokens.border, width: 1),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.hub_outlined,
                            size: 16,
                            color: tokens.syntaxFunction,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Subagenti ($agentCount)',
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              fontFamily: tokens.headingFontFamily,
                            ),
                          ),
                          if (agents.any((s) => (s.cost ?? 0) > 0)) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: tokens.syntaxString.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(
                                  tokens.radiusSm,
                                ),
                                border: Border.all(
                                  color: tokens.syntaxString.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.monetization_on_outlined,
                                    size: 11,
                                    color: tokens.syntaxString,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    costLabel,
                                    style: TextStyle(
                                      color: tokens.syntaxString,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: tokens.monoFontFamily,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (runningCount > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: tokens.syntaxKeyword.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(
                                  tokens.radiusSm,
                                ),
                                border: Border.all(
                                  color: tokens.syntaxKeyword.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 8,
                                    height: 8,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      value:
                                          WidgetsBinding.instance.runtimeType
                                              .toString()
                                              .contains('Test')
                                          ? 0.75
                                          : null,
                                      valueColor: AlwaysStoppedAnimation(
                                        tokens.syntaxKeyword,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    '$runningCount in esecuzione',
                                    style: TextStyle(
                                      color: tokens.syntaxKeyword,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      IconButton(
                        key: const ValueKey('subagents-popdown-close-btn'),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 26,
                          minHeight: 26,
                        ),
                        icon: Icon(
                          Icons.keyboard_arrow_up,
                          size: 18,
                          color: tokens.textMuted,
                        ),
                        tooltip: ref.read(appLanguageProvider) == AppLanguage.it ? 'Comprimi subagenti' : 'Collapse subagents',
                        onPressed: _handleToggle,
                      ),
                    ],
                  ),
                ),

                // List of expandable subagent windows
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 340),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(8),
                    itemCount: subagents.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (ctx, index) {
                      final subagent = subagents[index];
                      final isExpanded = _expandedIds.contains(subagent.id);
                      if (subagent.isUnlinked) {
                        final model = subagent.model ?? 'N/D';
                        final cost = subagent.cost == null
                            ? 'N/D'
                            : '\$${subagent.cost!.toStringAsFixed(4)}';
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          child: Text(
                            'Sessione figlia non attribuita: ${subagent.name} · $model · $cost',
                            key: ValueKey('unlinked-session-${subagent.id}'),
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        );
                      }

                      return _SubagentExpandableCard(
                        key: ValueKey('subagent-card-${subagent.id}'),
                        subagent: subagent,
                        isExpanded: isExpanded,
                        onToggleExpand: () {
                          setState(() {
                            if (isExpanded) {
                              _expandedIds.remove(subagent.id);
                            } else {
                              _expandedIds.add(subagent.id);
                            }
                          });
                        },
                        onSteer: (msg) {
                          ref
                              .read(subagentsFamily(widget.sessionId).notifier)
                              .steerSubagent(subagent.id, msg);
                        },
                        onStop: () {
                          ref
                              .read(subagentsFamily(widget.sessionId).notifier)
                              .stopSubagent(subagent.id);
                        },
                        onToggleSteeringBox: () {
                          ref
                              .read(subagentsFamily(widget.sessionId).notifier)
                              .toggleSteering(subagent.id);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          )
        // Collapsed: reveals small border peeking behind session info pane and book tab
        : (widget.hideBookTab
              ? const SizedBox.shrink()
              : Container(
                  margin: EdgeInsets.only(
                    left: isMobile ? 16 : 14,
                    right: isMobile ? 16 : 14,
                    bottom: 4,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Subtle border peeking from underneath the bottom edge of session info pane
                      Container(
                        height: 2.5,
                        decoration: BoxDecoration(
                          color: tokens.syntaxFunction.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(1.5),
                        ),
                      ),
                      // Small book tab protruding below the border
                      InkWell(
                        key: const ValueKey('subagents-book-tab'),
                        onTap: _handleToggle,
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(6),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3.5,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.surfaceElevated,
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(6),
                            ),
                            border: Border(
                              left: BorderSide(
                                color: tokens.borderStrong,
                                width: 1,
                              ),
                              right: BorderSide(
                                color: tokens.borderStrong,
                                width: 1,
                              ),
                              bottom: BorderSide(
                                color: tokens.borderStrong,
                                width: 1,
                              ),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: tokens.overlay.withValues(alpha: 0.1),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.hub_outlined,
                                size: 12,
                                color: tokens.syntaxFunction,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'Subagenti ($agentCount)',
                                style: TextStyle(
                                  color: tokens.textPrimary,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (agents.any((s) => (s.cost ?? 0) > 0)) ...[
                                const SizedBox(width: 5),
                                Text(
                                  costLabel,
                                  style: TextStyle(
                                    color: tokens.syntaxString,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: tokens.monoFontFamily,
                                  ),
                                ),
                              ],
                              if (runningCount > 0) ...[
                                const SizedBox(width: 5),
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: tokens.syntaxKeyword,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                              const SizedBox(width: 4),
                              Icon(
                                Icons.keyboard_arrow_down,
                                size: 13,
                                color: tokens.textMuted,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ));

    if (widget.hideBookTab) {
      return panelContent;
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: panelContent,
    );
  }
}

class _SubagentExpandableCard extends ConsumerStatefulWidget {
  final SubagentItem subagent;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final ValueChanged<String> onSteer;
  final VoidCallback onStop;
  final VoidCallback onToggleSteeringBox;

  const _SubagentExpandableCard({
    super.key,
    required this.subagent,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onSteer,
    required this.onStop,
    required this.onToggleSteeringBox,
  });

  @override
  ConsumerState<_SubagentExpandableCard> createState() =>
      _SubagentExpandableCardState();
}

class _SubagentExpandableCardState
    extends ConsumerState<_SubagentExpandableCard> {
  final TextEditingController _steerController = TextEditingController();
  final ScrollController _outputScrollController = ScrollController();

  String _tr(String it, String en) =>
      ref.read(appLanguageProvider) == AppLanguage.it ? it : en;

  @override
  void dispose() {
    _steerController.dispose();
    _outputScrollController.dispose();
    super.dispose();
  }

  void _submitSteer() {
    final text = _steerController.text.trim();
    if (text.isEmpty) return;
    widget.onSteer(text);
    _steerController.clear();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appLanguageProvider);
    final tokens = context.tokens;
    final sub = widget.subagent;

    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(
          color: sub.isRunning
              ? tokens.syntaxKeyword.withValues(alpha: 0.5)
              : tokens.border,
          width: sub.isRunning ? 1.2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Card Title Bar / Window Header
          InkWell(
            onTap: widget.onToggleExpand,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  // Status Icon / Pill
                  _buildStatusIndicator(tokens, sub.status),
                  const SizedBox(width: 8),

                  // Subagent Name & Model
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                sub.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: sub.isCompleted
                                      ? tokens.textMuted
                                      : tokens.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.5,
                                  decoration: sub.isCompleted
                                      ? TextDecoration.lineThrough
                                      : null,
                                  decorationColor: tokens.textMuted,
                                ),
                              ),
                            ),
                            // Always display the model used for each subagent
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: tokens.surfaceElevated,
                                borderRadius: BorderRadius.circular(3),
                                border: Border.all(color: tokens.border),
                              ),
                              child: Text(
                                sub.model != null && sub.model!.isNotEmpty
                                    ? sub.model!
                                    : 'N/D',
                                style: TextStyle(
                                  color: tokens.textSecondary,
                                  fontSize: 10,
                                  fontFamily: tokens.monoFontFamily,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (sub.description != null &&
                            sub.description!.isNotEmpty &&
                            sub.description != sub.name) ...[
                          const SizedBox(height: 1),
                          Text(
                            sub.description!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Cost Tag
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: tokens.syntaxString.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                      border: Border.all(
                        color: tokens.syntaxString.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.monetization_on_outlined,
                          size: 11,
                          color: tokens.syntaxString,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          sub.cost == null
                              ? 'N/D'
                              : '\$${sub.cost!.toStringAsFixed(4)}',
                          style: TextStyle(
                            color: tokens.syntaxString,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            fontFamily: tokens.monoFontFamily,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Steer Button
                  IconButton(
                    key: ValueKey('subagent-steer-btn-${sub.id}'),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    icon: Icon(
                      sub.isSteeringOpen
                          ? Icons.close
                          : Icons.navigation_outlined,
                      size: 15,
                      color: sub.isSteeringOpen
                          ? tokens.textMuted
                          : tokens.syntaxFunction,
                    ),
                    tooltip: sub.isSteeringOpen
                        ? _tr('Chiudi guida', 'Close steer')
                        : _tr('Guida (Steer)', 'Steer'),
                    onPressed: widget.onToggleSteeringBox,
                  ),

                  // Stop Button
                  IconButton(
                    key: ValueKey('subagent-stop-btn-${sub.id}'),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    icon: Icon(
                      Icons.stop_circle_outlined,
                      size: 16,
                      color: sub.isRunning
                          ? tokens.danger
                          : tokens.textMuted.withValues(alpha: 0.4),
                    ),
                    tooltip: sub.isRunning
                        ? 'Interrompi (Stop)'
                        : 'Subagente terminato',
                    onPressed: sub.isRunning ? widget.onStop : null,
                  ),

                  const SizedBox(width: 2),

                  // Expand/collapse chevron
                  Icon(
                    widget.isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 16,
                    color: tokens.textMuted,
                  ),
                ],
              ),
            ),
          ),

          // Card Expanded Body
          if (widget.isExpanded) ...[
            Container(height: 1, color: tokens.border),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Steering Input Box (when active)
                  if (sub.isSteeringOpen) ...[
                    Container(
                      key: ValueKey('subagent-steer-box-${sub.id}'),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: tokens.surfaceElevated,
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                        border: Border.all(
                          color: tokens.syntaxFunction,
                          width: 1.2,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.navigation_outlined,
                                size: 13,
                                color: tokens.syntaxFunction,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'Guida manuale subagente',
                                style: TextStyle(
                                  color: tokens.textPrimary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  key: ValueKey(
                                    'subagent-steer-input-${sub.id}',
                                  ),
                                  controller: _steerController,
                                  autofocus: true,
                                  style: TextStyle(
                                    color: tokens.textPrimary,
                                    fontSize: 12,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: _tr(
                                      'Invia istruzioni per guidare il subagente...',
                                      'Send instructions to steer the subagent...',
                                    ),
                                    hintStyle: TextStyle(
                                      color: tokens.textMuted,
                                      fontSize: 11.5,
                                    ),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 6,
                                    ),
                                    filled: true,
                                    fillColor: tokens.background,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                        tokens.radiusSm,
                                      ),
                                      borderSide: BorderSide(
                                        color: tokens.border,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                        tokens.radiusSm,
                                      ),
                                      borderSide: BorderSide(
                                        color: tokens.syntaxFunction,
                                        width: 1.2,
                                      ),
                                    ),
                                  ),
                                  onSubmitted: (_) => _submitSteer(),
                                ),
                              ),
                              const SizedBox(width: 6),
                              FilledButton.icon(
                                key: ValueKey('subagent-steer-send-${sub.id}'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: tokens.syntaxFunction,
                                  foregroundColor: tokens.surface,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                                icon: const Icon(Icons.send, size: 12),
                                label: Text(
                                  _tr('Invia', 'Send'),
                                  style: TextStyle(fontSize: 11),
                                ),
                                onPressed: _submitSteer,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Output Terminal/Console Display
                  Container(
                    constraints: const BoxConstraints(maxHeight: 180),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: tokens.background,
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                      border: Border.all(color: tokens.border),
                    ),
                    child: sub.output.isNotEmpty
                        ? Scrollbar(
                            controller: _outputScrollController,
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              controller: _outputScrollController,
                              child: SelectableText(
                                sub.output,
                                style: TextStyle(
                                  color: tokens.textPrimary,
                                  fontSize: 11,
                                  fontFamily: tokens.monoFontFamily,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          )
                        : Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Text(
                                sub.isRunning
                                    ? (sub.description != null &&
                                              sub.description!.isNotEmpty
                                          ? _tr(
                                              'Attività: ${sub.description}\n\nIn attesa di output dal subagente...',
                                              'Task: ${sub.description}\n\nWaiting for subagent output...',
                                            )
                                          : 'In attesa di output dal subagente...')
                                    : (sub.description != null &&
                                              sub.description!.isNotEmpty
                                          ? _tr(
                                              'Attività: ${sub.description}\n\nCompletato.',
                                              'Task: ${sub.description}\n\nCompleted.',
                                            )
                                          : _tr(
                                              'Nessun output registrato per questo subagente.',
                                              'No output recorded for this subagent.',
                                            )),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: tokens.textMuted,
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(FrameTokens tokens, String status) {
    Color color;
    IconData icon;
    String label;

    switch (status) {
      case 'running':
        color = tokens.syntaxKeyword;
        icon = Icons.refresh;
        label = _tr('In corso', 'Working');
        break;
      case 'steering':
      case 'steered':
        color = tokens.syntaxFunction;
        icon = Icons.alt_route;
        label = 'Guidato';
        break;
      case 'stopped':
        color = tokens.textMuted;
        icon = Icons.stop_circle_outlined;
        label = 'Fermato';
        break;
      case 'error':
        color = tokens.danger;
        icon = Icons.error_outline;
        label = _tr('Errore', 'Error');
        break;
      case 'completed':
      default:
        color = tokens.syntaxFunction;
        icon = Icons.check_circle_outline;
        label = _tr('Completato', 'Completed');
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
