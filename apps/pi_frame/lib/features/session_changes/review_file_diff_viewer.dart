import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/language/language_settings.dart';
import '../../ui/code/syntax_highlighter.dart';
import 'diff_parser.dart';
import 'session_changes_provider.dart';

class ReviewFileDiffViewer extends ConsumerStatefulWidget {
  final SessionChangedFile file;
  final DiffViewMode mode;

  const ReviewFileDiffViewer({
    super.key,
    required this.file,
    required this.mode,
  });

  @override
  ConsumerState<ReviewFileDiffViewer> createState() =>
      _ReviewFileDiffViewerState();
}

class _ReviewFileDiffViewerState extends ConsumerState<ReviewFileDiffViewer> {
  ParsedDiff? _parsedDiff;
  String? _lastDiffText;
  final Set<int> _expandedHunkGaps = {};

  String _tr(String it, String en) =>
      ref.read(appLanguageProvider) == AppLanguage.it ? it : en;

  void _parseDiffIfNeeded() {
    final diffText = widget.file.diff ?? '';
    if (_lastDiffText == diffText) return;
    _lastDiffText = diffText;
    _parsedDiff = DiffParser.parse(diffText);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appLanguageProvider);
    final tokens = context.tokens;
    _parseDiffIfNeeded();

    if (widget.file.isLoadingDiff) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: tokens.accent,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _tr('Caricamento diff...', 'Loading diff...'),
              style: TextStyle(color: tokens.textMuted, fontSize: 11),
            ),
          ],
        ),
      );
    }

    final parsed = _parsedDiff;
    if (parsed == null || parsed.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        alignment: Alignment.centerLeft,
        child: Text(
          widget.file.diff?.isNotEmpty == true
              ? widget.file.diff!
              : _tr('Nessuna differenza da mostrare.', 'No diff to display.'),
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: 11,
            fontFamily: tokens.monoFontFamily,
          ),
        ),
      );
    }

    final lang = SyntaxHighlighter.inferLanguage(widget.file.filename);

    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceElevated.withValues(alpha: 0.35),
        border: Border(
          top: BorderSide(color: tokens.border.withValues(alpha: 0.5)),
          bottom: BorderSide(color: tokens.border.withValues(alpha: 0.5)),
        ),
      ),
      child: widget.mode == DiffViewMode.twoColumn
          ? _buildTwoColumnDiff(parsed, tokens, lang)
          : _buildSingleColumnDiff(parsed, tokens, lang),
    );
  }

  Widget _buildSingleColumnDiff(
    ParsedDiff parsed,
    FrameTokens tokens,
    String lang,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: IntrinsicWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int hIndex = 0; hIndex < parsed.hunks.length; hIndex++) ...[
              if (hIndex > 0)
                _buildCollapsedGap(
                  hIndex,
                  parsed.hunks[hIndex - 1].newStart +
                      parsed.hunks[hIndex - 1].newCount,
                  parsed.hunks[hIndex].newStart,
                  tokens,
                ),
              for (final line in parsed.hunks[hIndex].lines)
                _buildSingleColumnLine(line, tokens, lang),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSingleColumnLine(
    DiffLine line,
    FrameTokens tokens,
    String lang,
  ) {
    final isAdd = line.type == DiffLineType.addition;
    final isDel = line.type == DiffLineType.deletion;

    final bg = isAdd
        ? tokens.diffAddedBg
        : (isDel ? tokens.diffRemovedBg : null);

    final prefixColor = isAdd
        ? tokens.diffAddedFg
        : (isDel
              ? tokens.diffRemovedFg
              : tokens.textMuted.withValues(alpha: 0.4));

    final prefix = isAdd ? '+ ' : (isDel ? '- ' : '  ');

    final codeSpans = SyntaxHighlighter.highlightLine(
      line.text,
      lang,
      tokens,
      defaultColor: isAdd
          ? tokens.diffAddedFg
          : (isDel ? tokens.diffRemovedFg : tokens.diffContextFg),
    );

    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Old line number
          SizedBox(
            width: 36,
            child: Text(
              line.oldLineNumber?.toString() ?? '',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: tokens.monoFontFamily,
                fontSize: 11,
                color: tokens.textMuted.withValues(alpha: 0.6),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // New line number
          SizedBox(
            width: 36,
            child: Text(
              line.newLineNumber?.toString() ?? '',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: tokens.monoFontFamily,
                fontSize: 11,
                color: tokens.textMuted.withValues(alpha: 0.6),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Prefix (+, -, space)
          Text(
            prefix,
            style: TextStyle(
              fontFamily: tokens.monoFontFamily,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: prefixColor,
            ),
          ),
          // Code content
          Text.rich(
            TextSpan(children: codeSpans),
            style: TextStyle(
              fontFamily: tokens.monoFontFamily,
              fontSize: 11.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTwoColumnDiff(
    ParsedDiff parsed,
    FrameTokens tokens,
    String lang,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: IntrinsicWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int hIndex = 0; hIndex < parsed.hunks.length; hIndex++) ...[
              if (hIndex > 0)
                _buildCollapsedGap(
                  hIndex,
                  parsed.hunks[hIndex - 1].newStart +
                      parsed.hunks[hIndex - 1].newCount,
                  parsed.hunks[hIndex].newStart,
                  tokens,
                ),
              for (final row in parsed.hunks[hIndex].toSplitRows())
                _buildTwoColumnRow(row, tokens, lang),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTwoColumnRow(SplitDiffRow row, FrameTokens tokens, String lang) {
    final left = row.left;
    final right = row.right;

    final leftBg = left?.type == DiffLineType.deletion
        ? tokens.diffRemovedBg
        : null;

    final rightBg = right?.type == DiffLineType.addition
        ? tokens.diffAddedBg
        : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Column (Old / Deletion / Context)
        Container(
          width: 380,
          color: leftBg,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 36,
                child: Text(
                  left?.oldLineNumber?.toString() ?? '',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontFamily: tokens.monoFontFamily,
                    fontSize: 11,
                    color: tokens.textMuted.withValues(alpha: 0.6),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (left != null)
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: SyntaxHighlighter.highlightLine(
                        left.text,
                        lang,
                        tokens,
                        defaultColor: left.type == DiffLineType.deletion
                            ? tokens.diffRemovedFg
                            : tokens.diffContextFg,
                      ),
                    ),
                    style: TextStyle(
                      fontFamily: tokens.monoFontFamily,
                      fontSize: 11.5,
                      height: 1.35,
                    ),
                  ),
                )
              else
                const Spacer(),
            ],
          ),
        ),
        // Divider
        Container(width: 1, color: tokens.border),
        // Right Column (New / Addition / Context)
        Container(
          width: 380,
          color: rightBg,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 36,
                child: Text(
                  right?.newLineNumber?.toString() ?? '',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontFamily: tokens.monoFontFamily,
                    fontSize: 11,
                    color: tokens.textMuted.withValues(alpha: 0.6),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (right != null)
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: SyntaxHighlighter.highlightLine(
                        right.text,
                        lang,
                        tokens,
                        defaultColor: right.type == DiffLineType.addition
                            ? tokens.diffAddedFg
                            : tokens.diffContextFg,
                      ),
                    ),
                    style: TextStyle(
                      fontFamily: tokens.monoFontFamily,
                      fontSize: 11.5,
                      height: 1.35,
                    ),
                  ),
                )
              else
                const Spacer(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCollapsedGap(
    int gapIndex,
    int prevEnd,
    int nextStart,
    FrameTokens tokens,
  ) {
    final count = (nextStart - prevEnd).clamp(1, 100000);
    final isExpanded = _expandedHunkGaps.contains(gapIndex);

    return Container(
      color: tokens.surfaceElevated.withValues(alpha: 0.5),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            border: Border.all(color: tokens.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isExpanded ? 'Linee espanse' : '+$count more lines',
                style: TextStyle(
                  fontFamily: tokens.monoFontFamily,
                  fontSize: 10,
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              _buildSmallExpandBtn('+10', () {
                setState(() => _expandedHunkGaps.add(gapIndex));
              }, tokens),
              const SizedBox(width: 4),
              _buildSmallExpandBtn('+10', () {
                setState(() => _expandedHunkGaps.add(gapIndex));
              }, tokens),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSmallExpandBtn(
    String label,
    VoidCallback onTap,
    FrameTokens tokens,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(tokens.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: tokens.surfaceElevated,
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          border: Border.all(color: tokens.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: tokens.monoFontFamily,
            fontSize: 9,
            color: tokens.textMuted,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
