import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/language/language_settings.dart';
import 'todo_provider.dart';

class TodoPopDown extends ConsumerStatefulWidget {
  final String sessionId;
  final VoidCallback? onClose;
  final bool? isExpanded;
  final VoidCallback? onToggleExpand;
  final bool hideBookTab;

  const TodoPopDown({
    super.key,
    required this.sessionId,
    this.onClose,
    this.isExpanded,
    this.onToggleExpand,
    this.hideBookTab = false,
  });

  @override
  ConsumerState<TodoPopDown> createState() => _TodoPopDownState();
}

class _TodoPopDownState extends ConsumerState<TodoPopDown> {
  final TextEditingController _addController = TextEditingController();
  final Set<int> _expandedTaskIds = <int>{};
  bool _isAdding = false;
  bool _internalExpanded = true;

  String _tr(String it, String en) =>
      ref.read(appLanguageProvider) == AppLanguage.it ? it : en;

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
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  void _submitNewTask() {
    final text = _addController.text.trim();
    if (text.isEmpty) return;
    ref.read(todosFamily(widget.sessionId).notifier).addTask(text);
    _addController.clear();
    setState(() => _isAdding = false);
  }

  void _toggleTaskExpanded(int id) {
    setState(() {
      if (_expandedTaskIds.contains(id)) {
        _expandedTaskIds.remove(id);
      } else {
        _expandedTaskIds.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appLanguageProvider);
    final tokens = context.tokens;
    final todos = ref.watch(todosFamily(widget.sessionId));
    final notifier = ref.read(todosFamily(widget.sessionId).notifier);

    if (todos.isEmpty) {
      return const SizedBox.shrink();
    }

    final completedCount = todos.where((t) => t.isCompleted).length;
    final inProgressCount = todos.where((t) => t.isInProgress).length;
    final totalCount = todos.length;
    final percent = totalCount > 0 ? (completedCount / totalCount) : 0.0;
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    final panelContent = _isExpanded
        ? Container(
            key: const ValueKey('todo-popdown-panel'),
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
              border: Border.all(color: tokens.borderStrong, width: 1.0),
              boxShadow: [
                BoxShadow(
                  color: tokens.overlay.withValues(alpha: 0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header Bar
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.surface,
                    borderRadius: widget.hideBookTab
                        ? BorderRadius.only(
                            topRight: Radius.circular(tokens.radiusMd),
                          )
                        : BorderRadius.vertical(
                            top: Radius.circular(tokens.radiusMd),
                          ),
                    border: Border(
                      bottom: BorderSide(
                        color: tokens.border.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.checklist_rtl_rounded,
                        size: 15,
                        color: tokens.accent,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _tr('Task Agente (Todo)', 'Agent tasks (Todo)'),
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color:
                              (percent >= 1.0 ? tokens.success : tokens.accent)
                                  .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                        ),
                        child: Text(
                          _tr(
                            '$completedCount / $totalCount completati',
                            '$completedCount / $totalCount completed',
                          ),
                          style: TextStyle(
                            color: percent >= 1.0
                                ? tokens.success
                                : tokens.accent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (inProgressCount > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.agentWorking.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(
                              tokens.radiusSm,
                            ),
                          ),
                          child: Text(
                            _tr(
                              '$inProgressCount in corso',
                              '$inProgressCount in progress',
                            ),
                            style: TextStyle(
                              color: tokens.agentWorking,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      IconButton(
                        tooltip: _isAdding
                            ? _tr('Annulla', 'Cancel')
                            : _tr('Aggiungi task', 'Add task'),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 26,
                          minHeight: 26,
                        ),
                        icon: Icon(
                          _isAdding ? Icons.close : Icons.add_circle_outline,
                          size: 15,
                          color: tokens.accent,
                        ),
                        onPressed: () => setState(() => _isAdding = !_isAdding),
                      ),
                      IconButton(
                        key: const ValueKey('todo-popdown-close-btn'),
                        tooltip: _tr('Nascondi attività', 'Hide tasks'),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 26,
                          minHeight: 26,
                        ),
                        icon: Icon(
                          Icons.keyboard_arrow_up,
                          size: 16,
                          color: tokens.textMuted,
                        ),
                        onPressed: _handleToggle,
                      ),
                    ],
                  ),
                ),

                // Add Task Form (collapsible)
                if (_isAdding)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    color: tokens.background,
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const ValueKey('todo-add-task-field'),
                            controller: _addController,
                            autofocus: true,
                            onSubmitted: (_) => _submitNewTask(),
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: 12,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 4,
                              ),
                              hintText: _tr(
                                'Aggiungi task e premi Invio...',
                                'Add a task and press Enter...',
                              ),
                              hintStyle: TextStyle(
                                color: tokens.textMuted,
                                fontSize: 11.5,
                              ),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        FilledButton(
                          key: const ValueKey('todo-add-task-submit'),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                          ),
                          onPressed: _submitNewTask,
                          child: Text(
                            _tr('Aggiungi', 'Add'),
                            style: const TextStyle(fontSize: 10.5),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Compact, scrollable list of collapsed tasks
                if (todos.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Center(
                      child: Text(
                        _tr(
                          'Nessun task ancora pianificato per questa sessione.',
                          'No tasks have been planned for this session yet.',
                        ),
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      itemCount: todos.length,
                      separatorBuilder: (ctx, i) => Divider(
                        color: tokens.border.withValues(alpha: 0.35),
                        height: 1,
                      ),
                      itemBuilder: (ctx, index) {
                        final task = todos[index];
                        final isExpanded = _expandedTaskIds.contains(task.id);
                        final hasDescription =
                            task.description != null &&
                            task.description!.trim().isNotEmpty;

                        return InkWell(
                          key: ValueKey('todo-item-row-${task.id}'),
                          onTap: () => _toggleTaskExpanded(task.id),
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 4,
                              horizontal: 4,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    // Checkbox
                                    SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: Checkbox(
                                        key: ValueKey(
                                          'todo-checkbox-${task.id}',
                                        ),
                                        value: task.isCompleted,
                                        activeColor: tokens.accent,
                                        checkColor: tokens.surface,
                                        side: BorderSide(
                                          color: task.isCompleted
                                              ? tokens.accent
                                              : tokens.borderStrong,
                                          width: 1.4,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            tokens.radiusSm,
                                          ),
                                        ),
                                        onChanged: (val) {
                                          notifier.toggleStatus(task.id);
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),

                                    // Task Title
                                    Expanded(
                                      child: Text(
                                        task.subject,
                                        maxLines: isExpanded ? null : 1,
                                        overflow: isExpanded
                                            ? null
                                            : TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: task.isCompleted
                                              ? tokens.textMuted
                                              : task.isInProgress
                                              ? tokens.textPrimary
                                              : tokens.textSecondary,
                                          fontSize: 12,
                                          fontWeight: task.isInProgress
                                              ? FontWeight.bold
                                              : FontWeight.w500,
                                          decoration: task.isCompleted
                                              ? TextDecoration.lineThrough
                                              : null,
                                          decorationColor: tokens.textMuted,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),

                                    // Status Badge
                                    _buildStatusBadge(task, tokens),

                                    // Expand / Collapse Chevron
                                    const SizedBox(width: 4),
                                    Icon(
                                      isExpanded
                                          ? Icons.keyboard_arrow_up
                                          : Icons.keyboard_arrow_down,
                                      size: 14,
                                      color: hasDescription
                                          ? tokens.textSecondary
                                          : tokens.textMuted.withValues(
                                              alpha: 0.4,
                                            ),
                                    ),
                                  ],
                                ),

                                // Expanded Description
                                if (isExpanded) ...[
                                  const SizedBox(height: 4),
                                  Container(
                                    margin: const EdgeInsets.only(
                                      left: 30,
                                      right: 4,
                                      bottom: 4,
                                    ),
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: tokens.background.withValues(
                                        alpha: 0.7,
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        tokens.radiusSm,
                                      ),
                                      border: Border.all(
                                        color: tokens.border.withValues(
                                          alpha: 0.5,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      hasDescription
                                          ? task.description!
                                          : _tr(
                                              'Nessuna descrizione dettagliata disponibile per questo task.',
                                              'No detailed description is available for this task.',
                                            ),
                                      style: TextStyle(
                                        color: hasDescription
                                            ? tokens.textSecondary
                                            : tokens.textMuted,
                                        fontSize: 11,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          )
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
                      Container(
                        height: 2.5,
                        decoration: BoxDecoration(
                          color: tokens.accent.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(1.5),
                        ),
                      ),
                      InkWell(
                        key: const ValueKey('todo-peek-tab'),
                        onTap: _handleToggle,
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(6),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2.5,
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
                                Icons.checklist_rtl_rounded,
                                size: 11,
                                color: tokens.accent,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _tr(
                                  'Attività ($completedCount/$totalCount)',
                                  'Tasks ($completedCount/$totalCount)',
                                ),
                                style: TextStyle(
                                  color: tokens.textSecondary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Icon(
                                Icons.keyboard_arrow_down,
                                size: 12,
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

  Widget _buildStatusBadge(TodoItem task, FrameTokens tokens) {
    if (task.isCompleted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: tokens.success.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          border: Border.all(
            color: tokens.success.withValues(alpha: 0.35),
            width: 0.8,
          ),
        ),
        child: Text(
          'COMPLETATO',
          style: TextStyle(
            color: tokens.success,
            fontSize: 8.5,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    if (task.isInProgress) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: tokens.agentWorking.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          border: Border.all(
            color: tokens.agentWorking.withValues(alpha: 0.4),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 7,
              height: 7,
              child: CircularProgressIndicator(
                strokeWidth: 1.2,
                color: tokens.agentWorking,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'IN CORSO',
              style: TextStyle(
                color: tokens.agentWorking,
                fontSize: 8.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.border, width: 0.8),
      ),
      child: Text(
        'IN ATTESA',
        style: TextStyle(
          color: tokens.textMuted,
          fontSize: 8.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
