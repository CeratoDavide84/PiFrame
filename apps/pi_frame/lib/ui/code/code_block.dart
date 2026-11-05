import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import 'syntax_highlighter.dart';

class CodeBlock extends StatefulWidget {
  final String code;
  final String? language;

  const CodeBlock({super.key, required this.code, this.language});

  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  bool _copied = false;
  String? _cachedCode;
  String? _cachedLang;
  FrameTokens? _cachedTokens;
  TextSpan? _cachedSpans;

  void _copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (mounted) {
      setState(() => _copied = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied = false);
      });
    }
  }

  TextSpan _getSpans(String code, String lang, FrameTokens tokens) {
    if (_cachedSpans != null &&
        _cachedCode == code &&
        _cachedLang == lang &&
        identical(_cachedTokens, tokens)) {
      return _cachedSpans!;
    }
    _cachedCode = code;
    _cachedLang = lang;
    _cachedTokens = tokens;
    _cachedSpans = SyntaxHighlighter.highlight(code, lang, tokens);
    return _cachedSpans!;
  }

  @override
  Widget build(BuildContext context) {
    final isItalian = Localizations.localeOf(context).languageCode == 'it';
    final tokens = context.tokens;
    final lang = widget.language?.trim().toLowerCase() ?? 'text';

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
            // Header: Language badge + Copy button
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
                  Text(
                    lang.toUpperCase(),
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: 11,
                      fontFamily: tokens.monoFontFamily,
                      fontWeight: FontWeight.bold,
                    ),
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

            // Code text area with horizontal scrolling
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: SelectableText.rich(
                _getSpans(widget.code, lang, tokens),
                style: TextStyle(
                  fontFamily: tokens.monoFontFamily,
                  fontSize: 12.5,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
