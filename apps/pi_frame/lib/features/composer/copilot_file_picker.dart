import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/language/language_settings.dart';

enum CopilotFileActionType { mention, attach }

class CopilotFileResult {
  final String path;
  final CopilotFileActionType action;

  const CopilotFileResult({required this.path, required this.action});
}

class CopilotFilePicker extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> files;

  const CopilotFilePicker({super.key, required this.files});

  static Future<CopilotFileResult?> show(
    BuildContext context, {
    required List<Map<String, dynamic>> files,
  }) {
    final tokens = context.tokens;
    return showDialog<CopilotFileResult>(
      context: context,
      barrierColor: tokens.overlay,
      builder: (ctx) => CopilotFilePicker(files: files),
    );
  }

  @override
  ConsumerState<CopilotFilePicker> createState() => _CopilotFilePickerState();
}

class _CopilotFilePickerState extends ConsumerState<CopilotFilePicker> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _scrollController = ScrollController();
  int _selectedIndex = 0;
  List<Map<String, dynamic>> _filteredFiles = const [];
  int _renderedLimit = 50;

  String _tr(String it, String en) =>
      ref.read(appLanguageProvider) == AppLanguage.it ? it : en;

  @override
  void initState() {
    super.initState();
    _filteredFiles = widget.files;
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter < 200 &&
        _renderedLimit < _filteredFiles.length) {
      setState(() {
        _renderedLimit = (_renderedLimit + 50).clamp(0, _filteredFiles.length);
      });
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredFiles = widget.files;
      } else {
        _filteredFiles = widget.files.where((f) {
          final path = (f['path']?.toString() ?? '').toLowerCase();
          return path.contains(query);
        }).toList();
      }
      _selectedIndex = 0;
      _renderedLimit = 50;
    });
  }

  IconData _getFileIcon(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.dart')) return Icons.code;
    if (lower.endsWith('.js') ||
        lower.endsWith('.ts') ||
        lower.endsWith('.tsx') ||
        lower.endsWith('.jsx')) {
      return Icons.javascript;
    }
    if (lower.endsWith('.json') ||
        lower.endsWith('.yaml') ||
        lower.endsWith('.yml')) {
      return Icons.data_object;
    }
    if (lower.endsWith('.md') || lower.endsWith('.txt')) {
      return Icons.article_outlined;
    }
    return Icons.description_outlined;
  }

  String _formatBytes(dynamic size) {
    final bytes = (size as num?)?.toInt() ?? 0;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _selectFile(String path, CopilotFileActionType action) {
    Navigator.of(context).pop(CopilotFileResult(path: path, action: action));
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appLanguageProvider);
    final tokens = context.tokens;

    return Dialog(
      backgroundColor: tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        side: BorderSide(color: tokens.border, width: 1),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              if (_filteredFiles.isNotEmpty) {
                setState(() {
                  _selectedIndex = (_selectedIndex + 1) % _filteredFiles.length;
                });
                return KeyEventResult.handled;
              }
            } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              if (_filteredFiles.isNotEmpty) {
                setState(() {
                  _selectedIndex =
                      (_selectedIndex - 1 + _filteredFiles.length) %
                      _filteredFiles.length;
                });
                return KeyEventResult.handled;
              }
            } else if (event.logicalKey == LogicalKeyboardKey.enter) {
              if (_filteredFiles.isNotEmpty &&
                  _selectedIndex < _filteredFiles.length) {
                final path =
                    _filteredFiles[_selectedIndex]['path']?.toString() ?? '';
                if (path.isNotEmpty) {
                  _selectFile(path, CopilotFileActionType.attach);
                  return KeyEventResult.handled;
                }
              }
            }
          }
          return KeyEventResult.ignored;
        },
        child: Container(
          width: 580,
          height: 460,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: tokens.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                    ),
                    child: Icon(Icons.add_link, size: 16, color: tokens.accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _tr(
                            'Aggiungi contesto alla chat',
                            'Add context to chat',
                          ),
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _tr(
                            'Cerca un file per includerne il contenuto o citarlo con @',
                            'Find a file to include its contents or mention it with @',
                          ),
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 18, color: tokens.textMuted),
                    tooltip: _tr('Chiudi (Esc)', 'Close (Esc)'),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Search Box
              TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                autofocus: true,
                style: TextStyle(color: tokens.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: _tr(
                    'Cerca per nome file o percorso...',
                    'Search by file name or path...',
                  ),
                  hintStyle: TextStyle(color: tokens.textMuted, fontSize: 13),
                  prefixIcon: Icon(
                    Icons.search,
                    size: 18,
                    color: tokens.textMuted,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.clear,
                            size: 16,
                            color: tokens.textMuted,
                          ),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  filled: true,
                  fillColor: tokens.surfaceElevated,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    borderSide: BorderSide(color: tokens.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    borderSide: BorderSide(color: tokens.accent, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Filter summary
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _tr(
                      '${_filteredFiles.length} file trovati',
                      '${_filteredFiles.length} files found',
                    ),
                    style: TextStyle(color: tokens.textMuted, fontSize: 11),
                  ),
                  Flexible(
                    child: Text(
                      _tr(
                        '↑↓ seleziona · Invio conferma',
                        '↑↓ select · Enter confirm',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: 10,
                        fontFamily: tokens.monoFontFamily,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Results List
              Expanded(
                child: _filteredFiles.isEmpty
                    ? Center(
                        child: Text(
                          _tr(
                            'Nessun file corrisponde alla ricerca',
                            'No files match your search',
                          ),
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          color: tokens.surfaceElevated.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                          border: Border.all(color: tokens.border),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ListView.builder(
                          controller: _scrollController,
                          itemCount: (_renderedLimit < _filteredFiles.length)
                              ? _renderedLimit + 1
                              : _filteredFiles.length,
                          itemExtent: 44.0,
                          itemBuilder: (context, index) {
                            if (index == _renderedLimit &&
                                _renderedLimit < _filteredFiles.length) {
                              return Center(
                                child: Text(
                                  _tr(
                                    'Caricamento altri file ($_renderedLimit/${_filteredFiles.length})...',
                                    'Loading more files ($_renderedLimit/${_filteredFiles.length})...',
                                  ),
                                  style: TextStyle(
                                    color: tokens.textMuted,
                                    fontSize: 11,
                                    fontFamily: tokens.monoFontFamily,
                                  ),
                                ),
                              );
                            }
                            final file = _filteredFiles[index];
                            final path = file['path']?.toString() ?? '';
                            final isSelected = index == _selectedIndex;

                            return InkWell(
                              onTap: () => _selectFile(
                                path,
                                CopilotFileActionType.attach,
                              ),
                              child: Container(
                                color: isSelected
                                    ? tokens.accent.withValues(alpha: 0.12)
                                    : tokens.surface.withValues(alpha: 0),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _getFileIcon(path),
                                      size: 16,
                                      color: isSelected
                                          ? tokens.accent
                                          : tokens.textSecondary,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        path,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: isSelected
                                              ? tokens.accent
                                              : tokens.textPrimary,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          fontFamily: tokens.monoFontFamily,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _formatBytes(file['sizeBytes']),
                                      style: TextStyle(
                                        color: tokens.textMuted,
                                        fontSize: 10,
                                        fontFamily: tokens.monoFontFamily,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Action buttons
                                    OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        side: BorderSide(color: tokens.border),
                                        foregroundColor: tokens.textSecondary,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            tokens.radiusSm,
                                          ),
                                        ),
                                      ),
                                      onPressed: () => _selectFile(
                                        path,
                                        CopilotFileActionType.mention,
                                      ),
                                      child: Text(
                                        _tr('Collega @', 'Mention @'),
                                        style: const TextStyle(fontSize: 10.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
