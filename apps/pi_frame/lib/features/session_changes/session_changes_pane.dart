import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/language/language_settings.dart';
import '../workspace/repository_workspace.dart' show WorkspacePane;
import 'review_file_diff_viewer.dart';
import 'session_changes_provider.dart';

class SessionChangesPane extends ConsumerStatefulWidget {
  final String sessionId;
  final VoidCallback? onClose;
  final List<WorkspacePane>? companionTabs;
  final WorkspacePane? activeCompanionTab;
  final ValueChanged<WorkspacePane>? onSelectCompanionTab;

  const SessionChangesPane({
    super.key,
    required this.sessionId,
    this.onClose,
    this.companionTabs,
    this.activeCompanionTab,
    this.onSelectCompanionTab,
  });

  @override
  ConsumerState<SessionChangesPane> createState() => _SessionChangesPaneState();
}

class _SessionChangesPaneState extends ConsumerState<SessionChangesPane> {
  String _tr(String it, String en) =>
      ref.read(appLanguageProvider) == AppLanguage.it ? it : en;
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(sessionChangesProvider(widget.sessionId).notifier).refresh();
    });
  }

  void _toggleFileExpansion(String path) {
    final notifier = ref.read(
      expandedReviewFilesProvider(widget.sessionId).notifier,
    );
    final current = ref.read(expandedReviewFilesProvider(widget.sessionId));
    if (current.contains(path)) {
      notifier.state = Set<String>.from(current)..remove(path);
    } else {
      notifier.state = Set<String>.from(current)..add(path);
      // Fetch diff for this file if not already loaded
      ref
          .read(sessionChangesProvider(widget.sessionId).notifier)
          .fetchFileDiff(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appLanguageProvider);
    final tokens = context.tokens;
    final changes = ref.watch(sessionChangesProvider(widget.sessionId));
    final expandedFiles = ref.watch(
      expandedReviewFilesProvider(widget.sessionId),
    );
    final diffMode = ref.watch(diffViewModeProvider);

    return Container(
      decoration: BoxDecoration(color: tokens.surface),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            height: 38,
            margin: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: tokens.surfaceElevated,
              borderRadius: BorderRadius.circular(tokens.radiusMd),
              border: Border.all(color: tokens.borderStrong),
            ),
            child: Row(
              children: [
                if (widget.companionTabs != null &&
                    widget.companionTabs!.length > 1)
                  Expanded(
                    child: Row(
                      children: [
                        for (final tab in widget.companionTabs!) ...[
                          Builder(
                            builder: (context) {
                              final isActive = tab == widget.activeCompanionTab;
                              final (tabTitle, tabIcon) = switch (tab) {
                                WorkspacePane.repository => (
                                  'File',
                                  Icons.folder_outlined,
                                ),
                                WorkspacePane.git => (
                                  'Review Changes',
                                  Icons.rate_review_outlined,
                                ),
                                WorkspacePane.chat => (
                                  'Chat',
                                  Icons.chat_bubble_outline,
                                ),
                              };
                              return MouseRegion(
                                cursor: isActive
                                    ? SystemMouseCursors.basic
                                    : SystemMouseCursors.click,
                                child: GestureDetector(
                                  key: ValueKey('companion-tab-${tab.name}'),
                                  behavior: HitTestBehavior.opaque,
                                  onTap: isActive
                                      ? null
                                      : () => widget.onSelectCompanionTab?.call(
                                          tab,
                                        ),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 140),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isActive ? 10 : 7,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isActive
                                          ? tokens.surface
                                          : tokens.surface.withValues(alpha: 0),
                                      borderRadius: BorderRadius.circular(
                                        tokens.radiusSm,
                                      ),
                                      border: isActive
                                          ? Border.all(
                                              color: tokens.borderStrong,
                                              width: 1,
                                            )
                                          : null,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          tabIcon,
                                          size: isActive ? 14 : 13,
                                          color: isActive
                                              ? tokens.accent
                                              : tokens.textMuted,
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          isActive
                                              ? tabTitle.toUpperCase()
                                              : tabTitle,
                                          style: TextStyle(
                                            color: isActive
                                                ? tokens.textPrimary
                                                : tokens.textMuted,
                                            fontSize: isActive ? 11.5 : 11,
                                            fontFamily: tokens.uiFontFamily,
                                            fontWeight: isActive
                                                ? FontWeight.w600
                                                : FontWeight.w500,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 4),
                        ],
                      ],
                    ),
                  )
                else ...[
                  Icon(
                    Icons.rate_review_outlined,
                    size: 16,
                    color: tokens.accent,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Review Changes',
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 11.5,
                      fontFamily: tokens.uiFontFamily,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
                if (changes.files.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.surface,
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                      border: Border.all(color: tokens.border),
                    ),
                    child: Text(
                      '${changes.files.length}',
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                // Diff View Mode Toggle Button
                Tooltip(
                  message: diffMode == DiffViewMode.singleColumn
                      ? 'Passa a visualizzazione a 2 colonne'
                      : 'Passa a visualizzazione a colonna singola',
                  child: InkWell(
                    key: const ValueKey('toggle-diff-mode-btn'),
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    onTap: () {
                      final newMode = diffMode == DiffViewMode.singleColumn
                          ? DiffViewMode.twoColumn
                          : DiffViewMode.singleColumn;
                      ref.read(diffViewModeProvider.notifier).state = newMode;
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: tokens.surface,
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                        border: Border.all(color: tokens.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            diffMode == DiffViewMode.singleColumn
                                ? Icons.view_column_outlined
                                : Icons.table_rows_outlined,
                            size: 15,
                            color: tokens.accent,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            diffMode == DiffViewMode.singleColumn ? '00' : '1',
                            style: TextStyle(
                              fontFamily: tokens.monoFontFamily,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: tokens.displayText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Refresh Button
                IconButton(
                  key: const ValueKey('refresh-session-changes-btn'),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 26,
                    minHeight: 26,
                  ),
                  icon: const Icon(Icons.refresh, size: 16),
                  tooltip: _tr('Aggiorna modifiche', 'Refresh changes'),
                  onPressed: () {
                    ref
                        .read(sessionChangesProvider(widget.sessionId).notifier)
                        .refresh();
                  },
                ),
                // Close Button
                if (widget.onClose != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    key: const ValueKey('close-session-changes-btn'),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 26,
                      minHeight: 26,
                    ),
                    icon: const Icon(Icons.close, size: 16),
                    tooltip: _tr('Chiudi revisione', 'Close review'),
                    onPressed: widget.onClose,
                  ),
                ],
              ],
            ),
          ),

          // Body: Loading, Empty, or Scrollable File List
          Expanded(
            child: changes.isLoading && changes.files.isEmpty
                ? Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: tokens.accent,
                    ),
                  )
                : changes.files.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 36,
                            color: tokens.textMuted,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _tr(
                              'Nessun file modificato in questa sessione.',
                              'No files changed in this session.',
                            ),
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: changes.files.length,
                    itemBuilder: (context, index) {
                      final file = changes.files[index];
                      final isExpanded = expandedFiles.contains(file.path);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildFileRow(file, isExpanded, tokens),
                          if (isExpanded)
                            ReviewFileDiffViewer(file: file, mode: diffMode),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileRow(
    SessionChangedFile file,
    bool isExpanded,
    FrameTokens tokens,
  ) {
    return InkWell(
      key: ValueKey('review-file-${file.path}'),
      onTap: () => _toggleFileExpansion(file.path),
      hoverColor: tokens.surfaceElevated.withValues(alpha: 0.6),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: isExpanded
              ? tokens.surfaceElevated.withValues(alpha: 0.4)
              : null,
          border: Border(
            bottom: BorderSide(
              color: tokens.border.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            // File type icon badge
            _buildFileTypeBadge(file.filename, tokens),
            const SizedBox(width: 8),
            // Filename
            Text(
              file.filename,
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                fontFamily: tokens.monoFontFamily,
              ),
            ),
            if (file.directory.isNotEmpty) ...[
              const SizedBox(width: 8),
              // Location / directory
              Expanded(
                child: Text(
                  file.directory,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: 11,
                    fontFamily: tokens.monoFontFamily,
                  ),
                ),
              ),
            ] else
              const Spacer(),
            const SizedBox(width: 8),
            // Additions (+ green)
            Text(
              '+${file.additions}',
              style: TextStyle(
                color: tokens.diffAddedFg,
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 4),
            // Deletions (- red)
            Text(
              '-${file.deletions}',
              style: TextStyle(
                color: tokens.diffRemovedFg,
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            // Expand or minimize icon
            Icon(
              isExpanded ? Icons.keyboard_arrow_down : Icons.chevron_right,
              size: 16,
              color: tokens.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileTypeBadge(String filename, FrameTokens tokens) {
    final ext = filename.contains('.')
        ? filename.split('.').last.toLowerCase()
        : '';

    switch (ext) {
      case 'ts':
      case 'tsx':
        return _textBadge(
          'TS',
          tokens.syntaxVariable,
          tokens,
          textColor: tokens.accentContrast,
        );
      case 'js':
      case 'jsx':
        return _textBadge(
          'JS',
          tokens.syntaxFunction,
          tokens,
          textColor: tokens.textPrimary,
        );
      case 'dart':
        return _dartBadge(tokens);
      case 'json':
        return _textBadge(
          '{ }',
          tokens.syntaxNumber,
          tokens,
          textColor: tokens.textPrimary,
        );
      case 'md':
        return _textBadge(
          'MD',
          tokens.syntaxKeyword,
          tokens,
          textColor: tokens.accentContrast,
        );
      case 'py':
        return _textBadge(
          'PY',
          tokens.syntaxType,
          tokens,
          textColor: tokens.accentContrast,
        );
      case 'yaml':
      case 'yml':
        return _textBadge(
          'YML',
          tokens.syntaxString,
          tokens,
          textColor: tokens.accentContrast,
        );
      case 'css':
      case 'scss':
        return _textBadge(
          '#',
          tokens.syntaxOperator,
          tokens,
          textColor: tokens.accentContrast,
        );
      case 'html':
        return _textBadge(
          '<>',
          tokens.syntaxPunctuation,
          tokens,
          textColor: tokens.accentContrast,
        );
      default:
        return Icon(
          Icons.insert_drive_file_outlined,
          size: 15,
          color: tokens.textMuted,
        );
    }
  }

  Widget _textBadge(
    String text,
    Color bgColor,
    FrameTokens tokens, {
    Color? textColor,
  }) {
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor ?? tokens.accentContrast,
          fontSize: text.length > 2 ? 8 : 9,
          fontWeight: FontWeight.bold,
          height: 1.0,
        ),
      ),
    );
  }

  Widget _dartBadge(FrameTokens tokens) {
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tokens.accent,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Icon(Icons.flutter_dash, size: 13, color: tokens.accentContrast),
    );
  }
}
