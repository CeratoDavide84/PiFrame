import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/terminal/terminal_settings.dart';
import '../../ui/code/code_block.dart';
import '../../ui/code/diff_block.dart';
import 'task_notification_card.dart';

Future<void> _openUrl(String url) async {
  try {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      await launchUrl(uri);
    }
  } catch (_) {
    if (kIsWeb) return;
    try {
      if (Platform.isWindows) {
        await Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      }
    } catch (_) {}
  }
}

String resolvePathForOsExplorer(String rawPath, {String? cwd}) {
  // The browser has no OS file system: keep the raw reference untouched and
  // never touch dart:io (Platform throws UnsupportedError on the web).
  if (kIsWeb) return rawPath.trim();
  String resolved = rawPath.trim();
  if (resolved.startsWith('file://')) {
    final uri = Uri.tryParse(resolved);
    if (uri != null) {
      if (uri.host.isNotEmpty) {
        resolved = '\\\\${uri.host}${uri.path}'.replaceAll('/', '\\');
      } else if (Platform.isWindows && RegExp(r'^/[a-zA-Z]:').hasMatch(uri.path)) {
        resolved = uri.path.substring(1).replaceAll('/', '\\');
      } else {
        resolved = uri.path;
      }
    } else {
      resolved = resolved.replaceFirst(RegExp(r'^file://+'), '');
    }
  }

  // Remove query, anchor or line:col numbers like :42:10 or #L10-20
  resolved = resolved.replaceAll(RegExp(r'#.*$'), '');
  resolved = resolved.replaceAll(RegExp(r':\d+(?::\d+)?$'), '');

  if (!Platform.isWindows) {
    if (cwd != null && cwd.isNotEmpty && !resolved.startsWith('/')) {
      final sep = cwd.endsWith('/') ? '' : '/';
      return '$cwd$sep$resolved';
    }
    return resolved;
  }

  // Windows platform handling:
  // 1. Check if resolved is already a WSL UNC path (e.g. \\wsl.localhost\... or \\wsl$\...)
  final directWsl = parseWslPath(resolved);
  if (directWsl != null) {
    final host = resolved.contains(r'wsl$') ? r'wsl$' : 'wsl.localhost';
    final p = directWsl['linuxPath'] ?? '';
    return '\\\\$host\\${directWsl['distro']}$p'.replaceAll('/', '\\');
  }

  // 2. Check if cwd is a WSL path
  final cwdWsl = cwd != null ? parseWslPath(cwd) : null;
  if (cwdWsl != null) {
    final host = cwd!.contains(r'wsl$') ? r'wsl$' : 'wsl.localhost';
    final distro = cwdWsl['distro']!;
    final baseLinux = cwdWsl['linuxPath']!;
    if (resolved.startsWith('/')) {
      return '\\\\$host\\$distro$resolved'.replaceAll('/', '\\');
    }
    final sep = baseLinux.endsWith('/') || resolved.startsWith('/') ? '' : '/';
    return '\\\\$host\\$distro$baseLinux$sep$resolved'.replaceAll('/', '\\');
  }

  // 3. What if cwd or resolved starts with '/' (pure Linux path on Windows)?
  if (cwd != null && (cwd.startsWith('/') || resolved.startsWith('/'))) {
    final targetLinux = resolved.startsWith('/')
        ? resolved
        : (cwd.endsWith('/') ? '$cwd$resolved' : '$cwd/$resolved');
    return '\\\\wsl.localhost\\LMD_env$targetLinux'.replaceAll('/', '\\');
  }

  // 4. Standard Windows path
  if (cwd != null && cwd.isNotEmpty) {
    final isAbsolute = RegExp(r'^[a-zA-Z]:[/\\]').hasMatch(resolved) ||
        resolved.startsWith(r'\\');
    if (!isAbsolute) {
      final separator = cwd.endsWith('\\') || cwd.endsWith('/') ? '' : '\\';
      return '$cwd$separator$resolved'.replaceAll('/', '\\');
    }
  }

  return resolved.replaceAll('/', '\\');
}

Future<void> openInOsFileExplorer(String rawPath, {String? cwd}) async {
  // Remote browsers cannot reveal files in the host OS explorer.
  if (kIsWeb) return;
  try {
    final targetPath = resolvePathForOsExplorer(rawPath, cwd: cwd);

    if (Platform.isWindows) {
      String winPath = targetPath.replaceAll('/', '\\');
      var file = File(winPath);
      var dir = Directory(winPath);

      // If target does not exist and appears to be WSL, try dynamic resolution via wslpath
      if (!file.existsSync() &&
          !dir.existsSync() &&
          (cwd?.contains('wsl') == true ||
              rawPath.contains('wsl') ||
              rawPath.startsWith('/'))) {
        try {
          final rawClean = rawPath
              .replaceFirst(RegExp(r'^file://+'), '')
              .replaceAll(RegExp(r'#.*$'), '')
              .replaceAll(RegExp(r':\d+(?::\d+)?$'), '');
          final targetLinux = rawClean.startsWith('/')
              ? rawClean
              : (cwd != null
                  ? '${parseWslPath(cwd)?['linuxPath'] ?? cwd}/$rawClean'
                  : rawClean);
          final res = await Process.run(
            'wsl.exe',
            ['wslpath', '-w', targetLinux],
          ).timeout(const Duration(seconds: 1));
          if (res.exitCode == 0) {
            final out = (res.stdout as String).trim();
            if (out.isNotEmpty &&
                (File(out).existsSync() || Directory(out).existsSync())) {
              winPath = out;
              file = File(winPath);
              dir = Directory(winPath);
            }
          }
        } catch (_) {}
      }

      if (file.existsSync()) {
        await Process.run('explorer.exe', ['/select,$winPath']);
      } else if (dir.existsSync()) {
        await Process.run('explorer.exe', [winPath]);
      } else {
        final parentDir = file.parent;
        if (parentDir.existsSync()) {
          await Process.run('explorer.exe', [parentDir.path]);
        } else {
          await Process.run('explorer.exe', ['/select,$winPath']);
        }
      }
    } else if (Platform.isMacOS) {
      final file = File(targetPath);
      if (file.existsSync()) {
        await Process.run('open', ['-R', targetPath]);
      } else {
        await Process.run('open', [targetPath]);
      }
    } else if (Platform.isLinux) {
      final file = File(targetPath);
      if (file.existsSync()) {
        await Process.run('xdg-open', [file.parent.path]);
      } else {
        await Process.run('xdg-open', [targetPath]);
      }
    }
  } catch (e) {
    debugPrint('openInOsFileExplorer error: $e');
  }
}

bool isLikelyFilePath(String s) {
  final clean = s.trim();
  if (clean.isEmpty || clean.contains('\n') || clean.length > 300) return false;
  if (clean.startsWith('http://') || clean.startsWith('https://')) return false;
  if (clean.startsWith('file://')) return true;
  if (RegExp(r'^[a-zA-Z]:[/\\]').hasMatch(clean)) return true;
  final hasSep = clean.contains('/') || clean.contains(r'\');
  final hasExt = RegExp(
    r'\.(dart|ts|js|jsx|tsx|json|yaml|yml|md|markdown|txt|html|css|scss|sh|ps1|bat|cpp|c|h|hpp|rs|go|py|lock|toml|env|gradle|properties|xml|svg|png|jpg|jpeg|gif|webp|ico|wasm)$',
    caseSensitive: false,
  ).hasMatch(clean);
  if (hasExt) return true;
  if (hasSep && RegExp(r'[\w\-.]+$').hasMatch(clean)) {
    return true;
  }
  return false;
}

class RichContent extends StatefulWidget {
  final String text;
  final String? cwd;

  const RichContent({super.key, required this.text, this.cwd});

  @override
  State<RichContent> createState() => _RichContentState();

  static final RegExp _fenceRegex = RegExp(
    r'```([a-zA-Z0-9_\-\+]*)\n([\s\S]*?)```',
  );
  static final RegExp _numberedListRegex = RegExp(r'^(\d+)\.\s');
  static final RegExp _mdLinkRegex = RegExp(r'\[([^\]]+)\]\(([^)]+)\)');
  static final RegExp _rawUrlRegex = RegExp(
    r'(?<![\(\[])(https?://[^\s\)]+|file://[^\s\)]+)',
  );
  static final RegExp _inlineCodeRegex = RegExp(r'`([^`]+)`');
  static final RegExp _boldRegex = RegExp(r'\*\*([^*]+)\*\*');
  static final RegExp _rawFilePathRegex = RegExp(
    r'(?<![/\w\-])((?:[a-zA-Z]:[\\/]|(?:\.{1,2}[\\/])|(?:[\w\-]+[\\/]))[\w\-./\\]+\.(?:dart|ts|js|jsx|tsx|json|yaml|yml|md|txt|html|css|sh|ps1|bat|cpp|c|h|rs|go|py|lock|toml))\b',
  );
  static final RegExp _taskNotifRegex = RegExp(
    r'<task-notification>[\s\S]*?</task-notification>(?:\s*Full transcript available at:\s*[^\r\n]+)?',
    caseSensitive: false,
  );

  static void _addTextOrNotification(List<_Segment> segments, String text) {
    int lastIdx = 0;
    for (final m in _taskNotifRegex.allMatches(text)) {
      if (m.start > lastIdx) {
        final pre = text.substring(lastIdx, m.start).trim();
        if (pre.isNotEmpty) segments.add(_TextSegment(pre));
      }
      final notifStr = m.group(0)!;
      final data = TaskNotificationData.tryParse(notifStr);
      if (data != null) {
        segments.add(_TaskNotificationSegment(data));
      } else {
        segments.add(_TextSegment(notifStr));
      }
      lastIdx = m.end;
    }
    if (lastIdx < text.length) {
      final post = text.substring(lastIdx).trim();
      if (post.isNotEmpty) segments.add(_TextSegment(post));
    }
  }

  static List<_Segment> _parseSegments(String raw) {
    final segments = <_Segment>[];
    final normalized = raw.contains('\r') ? raw.replaceAll('\r\n', '\n') : raw;

    int lastIndex = 0;
    for (final match in _fenceRegex.allMatches(normalized)) {
      if (match.start > lastIndex) {
        final textPart = normalized.substring(lastIndex, match.start).trim();
        if (textPart.isNotEmpty) {
          _addTextOrNotification(segments, textPart);
        }
      }

      final lang = match.group(1);
      final code = match.group(2) ?? '';
      segments.add(_CodeSegment(code: code, language: lang));
      lastIndex = match.end;
    }

    if (lastIndex < normalized.length) {
      final remaining = normalized.substring(lastIndex).trim();
      if (remaining.isNotEmpty) {
        _addTextOrNotification(segments, remaining);
      }
    }

    if (segments.isEmpty && normalized.isNotEmpty) {
      _addTextOrNotification(segments, normalized);
    }

    return segments;
  }

  static Widget _buildMarkdownText(
    String text,
    FrameTokens tokens, {
    String? cwd,
    required bool isItalian,
  }) {
    final rawLines =
        (text.contains('\r') ? text.replaceAll('\r\n', '\n') : text).split(
          '\n',
        );
    final widgets = <Widget>[];
    final currentPara = StringBuffer();

    void flushPara() {
      if (currentPara.isNotEmpty) {
        final content = currentPara.toString().trim();
        if (content.isNotEmpty) {
          widgets.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text.rich(
                _parseInlineSpans(content, tokens, cwd: cwd, isItalian: isItalian),
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 13.5,
                  height: 1.55,
                ),
              ),
            ),
          );
        }
        currentPara.clear();
      }
    }

    for (final line in rawLines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('# ') ||
          trimmed.startsWith('## ') ||
          trimmed.startsWith('### ')) {
        flushPara();
        if (trimmed.startsWith('### ')) {
          widgets.add(
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Text(
                trimmed.substring(4),
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        } else if (trimmed.startsWith('## ')) {
          widgets.add(
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 6),
              child: Container(
                padding: const EdgeInsets.only(left: 8),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: tokens.accent, width: 3),
                  ),
                ),
                child: Text(
                  trimmed.substring(3),
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 16.5,
                    fontWeight: FontWeight.bold,
                    fontFamily: tokens.headingFontFamily,
                  ),
                ),
              ),
            ),
          );
        } else if (trimmed.startsWith('# ')) {
          widgets.add(
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 8),
              child: Text(
                trimmed.substring(2),
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  fontFamily: tokens.headingFontFamily,
                ),
              ),
            ),
          );
        }
      } else if (trimmed.startsWith('> ')) {
        flushPara();
        widgets.add(
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: tokens.surfaceElevated.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              border: Border(
                left: BorderSide(
                  color: tokens.accent.withValues(alpha: 0.6),
                  width: 3,
                ),
              ),
            ),
            child: Text.rich(
              _parseInlineSpans(trimmed.substring(2).trim(), tokens, cwd: cwd, isItalian: isItalian),
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: 13,
                fontStyle: FontStyle.italic,
                height: 1.5,
              ),
            ),
          ),
        );
      } else if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        flushPara();
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 8, left: 4),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tokens.accent,
                    ),
                  ),
                ),
                Expanded(
                  child: Text.rich(
                    _parseInlineSpans(
                      trimmed.substring(2).trim(),
                      tokens,
                      cwd: cwd,
                      isItalian: isItalian,
                    ),
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 13.5,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      } else if (_numberedListRegex.hasMatch(trimmed)) {
        flushPara();
        final match = _numberedListRegex.firstMatch(trimmed)!;
        final numStr = match.group(1)!;
        final itemText = trimmed.substring(match.end).trim();
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 20,
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    '$numStr.',
                    style: TextStyle(
                      color: tokens.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      fontFamily: tokens.monoFontFamily,
                    ),
                  ),
                ),
                Expanded(
                  child: Text.rich(
                    _parseInlineSpans(itemText, tokens, cwd: cwd, isItalian: isItalian),
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 13.5,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      } else if (trimmed.isEmpty) {
        flushPara();
      } else {
        if (currentPara.isNotEmpty) currentPara.write('\n');
        currentPara.write(line);
      }
    }
    flushPara();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  static TextSpan _parseInlineSpans(
    String text,
    FrameTokens tokens, {
    String? cwd,
    required bool isItalian,
  }) {
    final spans = <InlineSpan>[];

    final lines = text.split('\n');
    for (var l = 0; l < lines.length; l++) {
      final line = lines[l];
      final hasMarkdown =
          line.contains('[') ||
          line.contains('http') ||
          line.contains('file') ||
          line.contains('`') ||
          line.contains('*') ||
          line.contains('/') ||
          line.contains(r'\');
      if (!hasMarkdown) {
        if (line.isNotEmpty) {
          spans.add(TextSpan(text: line));
        }
        if (l < lines.length - 1) {
          spans.add(const TextSpan(text: '\n'));
        }
        continue;
      }

      final matches = <_InlineMatch>[];

      // Markdown links: [label](target)
      for (final m in _mdLinkRegex.allMatches(line)) {
        matches.add(
          _InlineMatch(
            m.start,
            m.end,
            m.group(1)!,
            _InlineType.link,
            target: m.group(2)!,
          ),
        );
      }

      // Raw URLs: https://... or file://...
      for (final m in _rawUrlRegex.allMatches(line)) {
        final start = m.start;
        final end = m.end;
        // Skip if already inside a markdown link match
        final overlaps = matches.any(
          (other) =>
              (start >= other.start && start < other.end) ||
              (end > other.start && end <= other.end),
        );
        if (!overlaps) {
          matches.add(
            _InlineMatch(
              start,
              end,
              m.group(1)!,
              _InlineType.link,
              target: m.group(1)!,
            ),
          );
        }
      }

      // Inline code: `code`
      for (final m in _inlineCodeRegex.allMatches(line)) {
        final start = m.start;
        final end = m.end;
        final overlaps = matches.any(
          (other) =>
              (start >= other.start && start < other.end) ||
              (end > other.start && end <= other.end),
        );
        if (!overlaps) {
          matches.add(_InlineMatch(start, end, m.group(1)!, _InlineType.code));
        }
      }

      // Bold: **text**
      for (final m in _boldRegex.allMatches(line)) {
        final start = m.start;
        final end = m.end;
        final overlaps = matches.any(
          (other) =>
              (start >= other.start && start < other.end) ||
              (end > other.start && end <= other.end),
        );
        if (!overlaps) {
          matches.add(_InlineMatch(start, end, m.group(1)!, _InlineType.bold));
        }
      }

      // Raw file paths in text (e.g. apps/pi_frame/lib/main.dart)
      for (final m in _rawFilePathRegex.allMatches(line)) {
        final start = m.start;
        final end = m.end;
        final overlaps = matches.any(
          (other) =>
              (start >= other.start && start < other.end) ||
              (end > other.start && end <= other.end),
        );
        if (!overlaps) {
          matches.add(
            _InlineMatch(
              start,
              end,
              m.group(1)!,
              _InlineType.filePath,
              target: m.group(1)!,
            ),
          );
        }
      }

      matches.sort((a, b) => a.start.compareTo(b.start));

      int lastEnd = 0;
      for (final m in matches) {
        if (m.start < lastEnd) continue;
        if (m.start > lastEnd) {
          spans.add(TextSpan(text: line.substring(lastEnd, m.start)));
        }
        if (m.type == _InlineType.code) {
          final isFile = isLikelyFilePath(m.text);
          if (!isFile) {
            spans.add(
              TextSpan(
                text: m.text,
                style: TextStyle(
                  color: tokens.textPrimary,
                  backgroundColor: tokens.surfaceElevated,
                  fontFamily: tokens.monoFontFamily,
                  fontSize: 12,
                ),
              ),
            );
            lastEnd = m.end;
            continue;
          }

          spans.add(
            _buildFileChip(
              displayText: m.text,
              targetPath: m.text,
              tokens: tokens,
              cwd: cwd,
              isItalian: isItalian,
            ),
          );
        } else if (m.type == _InlineType.bold) {
          spans.add(
            TextSpan(
              text: m.text,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          );
        } else if (m.type == _InlineType.filePath) {
          final target = m.target ?? m.text;
          spans.add(
            _buildFileChip(
              displayText: m.text,
              targetPath: target,
              tokens: tokens,
              cwd: cwd,
              isItalian: isItalian,
            ),
          );
        } else if (m.type == _InlineType.link) {
          final targetUrl = m.target ?? m.text;
          final isFile =
              targetUrl.startsWith('file://') || isLikelyFilePath(targetUrl);
          if (isFile) {
            spans.add(
              _buildFileChip(
                displayText: m.text,
                targetPath: targetUrl,
                tokens: tokens,
                cwd: cwd,
                isItalian: isItalian,
              ),
            );
          } else {
            spans.add(
              _buildWebLink(
                displayText: m.text,
                targetUrl: targetUrl,
                tokens: tokens,
              ),
            );
          }
        }
        lastEnd = m.end;
      }

      if (lastEnd < line.length) {
        spans.add(TextSpan(text: line.substring(lastEnd)));
      }

      if (l < lines.length - 1) {
        spans.add(const TextSpan(text: '\n'));
      }
    }

    return TextSpan(children: spans);
  }

  static InlineSpan _buildFileChip({
    required String displayText,
    required String targetPath,
    required FrameTokens tokens,
    required bool isItalian,
    String? cwd,
  }) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      margin: const EdgeInsets.symmetric(horizontal: 2),
      constraints: const BoxConstraints(maxWidth: 360),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(
          color: tokens.accent.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.insert_drive_file_outlined,
            size: 11,
            color: tokens.accent,
          ),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              displayText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.textPrimary,
                fontFamily: tokens.monoFontFamily,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );

    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: SelectionContainer.disabled(
        child: Tooltip(
          message: isItalian
              ? 'CTRL+clic per aprire in Esplora file'
              : 'Ctrl+click to open in File Explorer',
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                openInOsFileExplorer(targetPath, cwd: cwd);
              },
              child: chip,
            ),
          ),
        ),
      ),
    );
  }

  static InlineSpan _buildWebLink({
    required String displayText,
    required String targetUrl,
    required FrameTokens tokens,
  }) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: SelectionContainer.disabled(
        child: Tooltip(
          message: targetUrl,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _openUrl(targetUrl),
              child: Text(
                displayText,
                style: TextStyle(
                  color: tokens.accent,
                  decoration: TextDecoration.underline,
                  decorationColor: tokens.accent.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


class _RichContentState extends State<RichContent> {
  String? _cachedText;
  FrameTokens? _cachedTokens;
  String? _cachedCwd;
  bool? _cachedIsItalian;
  Widget? _cachedBuiltWidget;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isItalian = Localizations.localeOf(context).languageCode == 'it';
    if (_cachedBuiltWidget != null &&
        _cachedText == widget.text &&
        _cachedCwd == widget.cwd &&
        _cachedIsItalian == isItalian &&
        identical(_cachedTokens, tokens)) {
      return _cachedBuiltWidget!;
    }

    _cachedText = widget.text;
    _cachedTokens = tokens;
    _cachedCwd = widget.cwd;
    _cachedIsItalian = isItalian;

    final segments = RichContent._parseSegments(widget.text);

    _cachedBuiltWidget = SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: segments.map((seg) {
          if (seg is _CodeSegment) {
            if (seg.language == 'diff') {
              return DiffBlock(diffText: seg.code);
            }
            return CodeBlock(code: seg.code, language: seg.language);
          } else if (seg is _TaskNotificationSegment) {
            return TaskNotificationCard(
              data: seg.data,
              cwd: widget.cwd,
            );
          } else if (seg is _TextSegment) {
            return RichContent._buildMarkdownText(
              seg.content,
              tokens,
              cwd: widget.cwd,
              isItalian: isItalian,
            );
          }
          return const SizedBox.shrink();
        }).toList(),
      ),
    );

    return _cachedBuiltWidget!;
  }
}

enum _InlineType { code, bold, link, filePath }

class _InlineMatch {
  final int start;
  final int end;
  final String text;
  final _InlineType type;
  final String? target;
  _InlineMatch(this.start, this.end, this.text, this.type, {this.target});
}

abstract class _Segment {}

class _TextSegment extends _Segment {
  final String content;
  _TextSegment(this.content);
}

class _TaskNotificationSegment extends _Segment {
  final TaskNotificationData data;
  _TaskNotificationSegment(this.data);
}

class _CodeSegment extends _Segment {
  final String code;
  final String? language;
  _CodeSegment({required this.code, this.language});
}
