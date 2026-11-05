import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import 'rich_content.dart';

class TaskNotificationData {
  final String taskId;
  final String? toolUseId;
  final String? outputFile;
  final String status;
  final String summary;
  final String result;
  final int? totalTokens;
  final int? toolUses;
  final int? contextPercent;
  final int? durationMs;
  final String? fullTranscriptPath;

  const TaskNotificationData({
    required this.taskId,
    this.toolUseId,
    this.outputFile,
    required this.status,
    required this.summary,
    required this.result,
    this.totalTokens,
    this.toolUses,
    this.contextPercent,
    this.durationMs,
    this.fullTranscriptPath,
  });

  static TaskNotificationData? tryParse(String raw) {
    if (!raw.contains('<task-notification>')) return null;

    final notifMatch = RegExp(
      r'<task-notification>([\s\S]*?)</task-notification>',
      caseSensitive: false,
    ).firstMatch(raw);

    if (notifMatch == null) return null;
    final xmlContent = notifMatch.group(1) ?? '';

    String extractTag(String tag) {
      final m = RegExp(
        '<$tag>([\\s\\S]*?)</$tag>',
        caseSensitive: false,
      ).firstMatch(xmlContent);
      return m?.group(1)?.trim() ?? '';
    }

    final taskId = extractTag('task-id');
    final toolUseId = extractTag('tool-use-id');
    final outputFile = extractTag('output-file');
    final status = extractTag('status');
    final summary = extractTag('summary');
    final result = extractTag('result');

    final usageXml = extractTag('usage');
    int? totalTokens;
    int? toolUses;
    int? contextPercent;
    int? durationMs;

    if (usageXml.isNotEmpty) {
      final tt = RegExp(r'<total_tokens>(\d+)</total_tokens>').firstMatch(usageXml)?.group(1);
      final tu = RegExp(r'<tool_uses>(\d+)</tool_uses>').firstMatch(usageXml)?.group(1);
      final cp = RegExp(r'<context_percent>(\d+)</context_percent>').firstMatch(usageXml)?.group(1);
      final dm = RegExp(r'<duration_ms>(\d+)</duration_ms>').firstMatch(usageXml)?.group(1);

      totalTokens = tt != null ? int.tryParse(tt) : null;
      toolUses = tu != null ? int.tryParse(tu) : null;
      contextPercent = cp != null ? int.tryParse(cp) : null;
      durationMs = dm != null ? int.tryParse(dm) : null;
    }

    // Check for trailing transcript path:
    // "Full transcript available at: ..."
    String? transcriptPath;
    final transcriptMatch = RegExp(
      r'Full transcript available at:\s*([^\r\n]+)',
      caseSensitive: false,
    ).firstMatch(raw);
    if (transcriptMatch != null) {
      transcriptPath = transcriptMatch.group(1)?.trim();
    } else if (outputFile.isNotEmpty) {
      transcriptPath = outputFile;
    }

    return TaskNotificationData(
      taskId: taskId.isNotEmpty ? taskId : 'task',
      toolUseId: toolUseId.isNotEmpty ? toolUseId : null,
      outputFile: outputFile.isNotEmpty ? outputFile : null,
      status: status.isNotEmpty ? status : 'completed',
      summary: summary,
      result: result,
      totalTokens: totalTokens,
      toolUses: toolUses,
      contextPercent: contextPercent,
      durationMs: durationMs,
      fullTranscriptPath: transcriptPath,
    );
  }
}

class TaskNotificationCard extends StatefulWidget {
  final TaskNotificationData data;
  final String? cwd;

  const TaskNotificationCard({
    super.key,
    required this.data,
    this.cwd,
  });

  @override
  State<TaskNotificationCard> createState() => _TaskNotificationCardState();
}

class _TaskNotificationCardState extends State<TaskNotificationCard> {
  bool _isResultExpanded = false;

  String _formatDuration(int? ms) {
    if (ms == null) return '';
    final totalSeconds = (ms / 1000).round();
    if (totalSeconds < 60) return '${totalSeconds}s';
    final minutes = totalSeconds ~/ 60;
    final remSeconds = totalSeconds % 60;
    return '${minutes}m ${remSeconds}s';
  }

  String _formatNumber(int? n) {
    if (n == null) return '';
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return n.toString();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final data = widget.data;

    final isWrappedUp = data.status.toLowerCase().contains('turn limit') ||
        data.status.toLowerCase().contains('wrapped');
    final isError = data.status.toLowerCase().contains('error') ||
        data.status.toLowerCase().contains('failed');

    final Color statusColor = isError
        ? tokens.agentError
        : isWrappedUp
            ? tokens.signalWarning
            : tokens.success;

    final durationText = _formatDuration(data.durationMs);
    final tokensText = _formatNumber(data.totalTokens);

    return Container(
      key: ValueKey('task-notification-card-${data.taskId}'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: tokens.overlay.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(tokens.radiusMd),
              ),
              border: Border(
                bottom: BorderSide(
                  color: tokens.border.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.hub_outlined,
                  size: 15,
                  color: statusColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'Notifica Subagente',
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.4),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      data.status.toUpperCase(),
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Content body
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Summary
                if (data.summary.isNotEmpty) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.format_quote_rounded,
                          size: 14,
                          color: tokens.accent,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          data.summary,
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],

                // Metadata stats pills
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if (durationText.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.timer_outlined, size: 12, color: tokens.textMuted),
                          const SizedBox(width: 3),
                          Text(
                            durationText,
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: 10.5,
                              fontFamily: tokens.monoFontFamily,
                            ),
                          ),
                        ],
                      ),
                    if (tokensText.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.data_usage, size: 12, color: tokens.textMuted),
                          const SizedBox(width: 3),
                          Text(
                            '$tokensText tok',
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: 10.5,
                              fontFamily: tokens.monoFontFamily,
                            ),
                          ),
                        ],
                      ),
                    if (data.toolUses != null && data.toolUses! > 0)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.construction_outlined, size: 12, color: tokens.textMuted),
                          const SizedBox(width: 3),
                          Text(
                            '${data.toolUses} tool uses',
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: 10.5,
                              fontFamily: tokens.monoFontFamily,
                            ),
                          ),
                        ],
                      ),
                    if (data.contextPercent != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.pie_chart_outline, size: 12, color: tokens.textMuted),
                          const SizedBox(width: 3),
                          Text(
                            '${data.contextPercent}% contesto',
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: 10.5,
                              fontFamily: tokens.monoFontFamily,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                // Result Box (expandable)
                if (data.result.isNotEmpty) ...[
                  Container(
                    decoration: BoxDecoration(
                      color: tokens.background,
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                      border: Border.all(color: tokens.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        InkWell(
                          key: const ValueKey('task-notif-expand-result-btn'),
                          onTap: () => setState(() => _isResultExpanded = !_isResultExpanded),
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.terminal_outlined,
                                      size: 13,
                                      color: tokens.textSecondary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Risultato operazione',
                                      style: TextStyle(
                                        color: tokens.textSecondary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                Icon(
                                  _isResultExpanded
                                      ? Icons.keyboard_arrow_up
                                      : Icons.keyboard_arrow_down,
                                  size: 16,
                                  color: tokens.textMuted,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_isResultExpanded) ...[
                          Divider(color: tokens.border, height: 1),
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: SelectableText(
                              data.result,
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: 11.5,
                                fontFamily: tokens.monoFontFamily,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ] else ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                            child: Text(
                              data.result.split('\n').first,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tokens.textMuted,
                                fontSize: 11,
                                fontFamily: tokens.monoFontFamily,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // Footer Row: Task ID & Open Transcript
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'ID: ${data.taskId}',
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: 10,
                        fontFamily: tokens.monoFontFamily,
                      ),
                    ),
                    if (data.fullTranscriptPath != null &&
                        data.fullTranscriptPath!.isNotEmpty) ...[
                      InkWell(
                        onTap: () {
                          openInOsFileExplorer(
                            data.fullTranscriptPath!,
                            cwd: widget.cwd,
                          );
                        },
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.open_in_new_rounded,
                                size: 12,
                                color: tokens.accent,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Apri trascrizione completa',
                                style: TextStyle(
                                  color: tokens.accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
