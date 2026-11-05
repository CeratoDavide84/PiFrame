import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import 'syntax_highlighter.dart';

class DiffBlock extends StatefulWidget {
  final String diffText;
  final String? filename;

  const DiffBlock({super.key, required this.diffText, this.filename});

  @override
  State<DiffBlock> createState() => _DiffBlockState();
}

class _DiffBlockState extends State<DiffBlock> {
  bool _copied = false;
  String? _cachedDiffText;
  List<String> _cachedLines = const [];
  int _cachedAdditions = 0;
  int _cachedDeletions = 0;

  void _parseDiffIfNeeded(String diffText) {
    if (_cachedDiffText == diffText) return;
    _cachedDiffText = diffText;
    final lines = diffText.split('\n');
    int additions = 0;
    int deletions = 0;
    for (final line in lines) {
      final trimmed = line.trimLeft();
      if ((line.startsWith('+') && !line.startsWith('+++')) ||
          (trimmed.startsWith('+') && !trimmed.startsWith('+++'))) {
        additions++;
      }
      if ((line.startsWith('-') && !line.startsWith('---')) ||
          (trimmed.startsWith('-') && !trimmed.startsWith('---'))) {
        deletions++;
      }
    }
    _cachedLines = lines;
    _cachedAdditions = additions;
    _cachedDeletions = deletions;
  }

  void _copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: widget.diffText));
    if (mounted) {
      setState(() => _copied = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isItalian = Localizations.localeOf(context).languageCode == 'it';
    final tokens = context.tokens;
    _parseDiffIfNeeded(widget.diffText);
    final lines = _cachedLines;
    final additions = _cachedAdditions;
    final deletions = _cachedDeletions;
    final lang = SyntaxHighlighter.inferLanguage(widget.filename);

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          border: Border.all(color: tokens.border, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: File/diff title, +/- stats, and Copy button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: tokens.surfaceElevated,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(tokens.radiusSm),
                  topRight: Radius.circular(tokens.radiusSm),
                ),
                border: Border(
                  bottom: BorderSide(color: tokens.border, width: 1),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.difference_outlined,
                        size: 14,
                        color: tokens.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        widget.filename ?? 'DIFF',
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: 12,
                          fontFamily: tokens.monoFontFamily,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (additions > 0)
                        Text(
                          '+$additions',
                          style: TextStyle(
                            color: tokens.diffAddedFg,
                            fontSize: 11,
                            fontFamily: tokens.monoFontFamily,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      if (additions > 0 && deletions > 0)
                        const SizedBox(width: 6),
                      if (deletions > 0)
                        Text(
                          '-$deletions',
                          style: TextStyle(
                            color: tokens.diffRemovedFg,
                            fontSize: 11,
                            fontFamily: tokens.monoFontFamily,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                  InkWell(
                    onTap: _copyToClipboard,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _copied ? Icons.check : Icons.copy,
                            size: 12,
                            color: _copied
                                ? tokens.success
                                : tokens.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _copied
                                ? (isItalian ? 'Copiato!' : 'Copied!')
                                : (isItalian ? 'Copia' : 'Copy'),
                            style: TextStyle(
                              color: _copied
                                  ? tokens.textPrimary
                                  : tokens.textSecondary,
                              fontSize: 11,
                              fontFamily: tokens.monoFontFamily,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Diff lines
            LayoutBuilder(
              builder: (context, constraints) {
                final minWidth = constraints.hasBoundedWidth
                    ? constraints.maxWidth
                    : 0.0;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: minWidth),
                    child: IntrinsicWidth(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: lines
                            .map((line) => _buildDiffLine(line, tokens, lang))
                            .toList(),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiffLine(String line, FrameTokens tokens, String lang) {
    if (line.isEmpty) {
      return Container(
        color: tokens.surface.withValues(alpha: 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: const Text(' '),
      );
    }

    if (line.startsWith('@@')) {
      return Container(
        color: tokens.surfaceElevated,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: Text.rich(
          TextSpan(
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: tokens.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    border: Border.all(color: tokens.border),
                  ),
                  child: Text(
                    'HUNK',
                    style: TextStyle(
                      color: tokens.accent,
                      fontSize: 9.5,
                      fontFamily: tokens.monoFontFamily,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              TextSpan(
                text: line,
                style: TextStyle(
                  color: tokens.accent,
                  fontFamily: tokens.monoFontFamily,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final trimmed = line.trimLeft();
    final isAddition =
        (line.startsWith('+') && !line.startsWith('+++')) ||
        (trimmed.startsWith('+') && !trimmed.startsWith('+++'));
    final isDeletion =
        (line.startsWith('-') && !line.startsWith('---')) ||
        (trimmed.startsWith('-') && !trimmed.startsWith('---'));
    final isHeader = line.startsWith('+++') || line.startsWith('---');

    final Color bg;
    final Color prefixColor;
    final String prefix;
    final String code;

    if (isAddition) {
      bg = tokens.diffAddedBg;
      prefixColor = tokens.diffAddedFg;
      prefix = '+ ';
      code = line.startsWith('+')
          ? (line.length > 1 ? line.substring(1) : '')
          : (trimmed.length > 1 ? trimmed.substring(1) : '');
    } else if (isDeletion) {
      bg = tokens.diffRemovedBg;
      prefixColor = tokens.diffRemovedFg;
      prefix = '- ';
      code = line.startsWith('-')
          ? (line.length > 1 ? line.substring(1) : '')
          : (trimmed.length > 1 ? trimmed.substring(1) : '');
    } else if (isHeader) {
      bg = tokens.surfaceElevated;
      prefixColor = tokens.textSecondary;
      prefix = '';
      code = line;
    } else {
      bg = tokens.surface.withValues(alpha: 0);
      prefixColor = tokens.textMuted.withValues(alpha: 0.5);
      prefix = '  ';
      code = line.startsWith(' ') ? line.substring(1) : line;
    }

    final codeSpans = isHeader
        ? [
            TextSpan(
              text: code,
              style: TextStyle(color: prefixColor, fontWeight: FontWeight.bold),
            ),
          ]
        : SyntaxHighlighter.highlightLine(
            code,
            lang,
            tokens,
            defaultColor: isAddition
                ? tokens.diffAddedFg
                : isDeletion
                ? tokens.diffRemovedFg
                : tokens.diffContextFg,
          );

    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Text.rich(
        TextSpan(
          children: [
            if (prefix.isNotEmpty)
              TextSpan(
                text: prefix,
                style: TextStyle(
                  color: prefixColor,
                  fontWeight: FontWeight.bold,
                  fontFamily: tokens.monoFontFamily,
                  fontSize: 12,
                ),
              ),
            ...codeSpans,
          ],
          style: TextStyle(
            fontFamily: tokens.monoFontFamily,
            fontSize: 12,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}
