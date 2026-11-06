import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../data/language/language_settings.dart';
import '../../ui/frame_snack_bar.dart';
import '../../domain/session/agent_status.dart';
import '../../domain/session/attachment_model.dart';
import '../../domain/session/session_state.dart';
import '../composer/attachment_chips.dart';
import '../composer/composer_attachments_provider.dart';
import '../composer/composer_draft.dart';
import '../status/agent_status_badge.dart';
import '../tool_timeline/tool_timeline.dart';
import '../workspace/repository_workspace.dart';
import 'rich_content.dart';
import 'thinking_block.dart';
import 'subagent_panel.dart';
import 'subagents_provider.dart';
import 'todo_panel.dart';
import 'todo_provider.dart';
import 'usage_history_chart.dart';

enum _ActiveBookTab { none, todos, subagents }

class BottomAnchoredScrollController extends ScrollController {
  BottomAnchoredScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
    this.shouldAnchorToBottom,
  });

  bool Function()? shouldAnchorToBottom;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _BottomAnchoredScrollPosition(
      physics: physics,
      context: context,
      oldPosition: oldPosition,
      shouldAnchorToBottom: shouldAnchorToBottom,
    );
  }
}

class _BottomAnchoredScrollPosition extends ScrollPositionWithSingleContext {
  _BottomAnchoredScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    this.shouldAnchorToBottom,
  });

  final bool Function()? shouldAnchorToBottom;

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    final oldMax = hasContentDimensions ? this.maxScrollExtent : null;
    final isDragging = activity is DragScrollActivity;
    final isAtBottom = !isDragging &&
        (shouldAnchorToBottom?.call() ?? true) &&
        oldMax != null &&
        (oldMax - pixels).abs() <= 50;

    final applied = super.applyContentDimensions(minScrollExtent, maxScrollExtent);

    if (isAtBottom && maxScrollExtent != oldMax) {
      final delta = maxScrollExtent - oldMax;
      if (delta != 0) {
        final newPixels = (pixels + delta).clamp(minScrollExtent, maxScrollExtent);
        final correction = newPixels - pixels;
        if (correction.abs() > 0.01) {
          correctBy(correction);
          return false;
        }
      }
    }
    return applied;
  }
}

class _MeasureSizeRenderObject extends RenderProxyBox {
  _MeasureSizeRenderObject({required this.onSizeChange});
  void Function(Size size) onSizeChange;
  Size? _oldSize;

  @override
  void performLayout() {
    super.performLayout();
    final newSize = size;
    if (_oldSize != newSize) {
      _oldSize = newSize;
      onSizeChange(newSize);
    }
  }
}

class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({
    required this.onSizeChange,
    required super.child,
  });

  final void Function(Size size) onSizeChange;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _MeasureSizeRenderObject(onSizeChange: onSizeChange);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _MeasureSizeRenderObject renderObject,
  ) {
    renderObject.onSizeChange = onSizeChange;
  }
}

class SmartTranscriptChildDelegate extends SliverChildBuilderDelegate {
  final List<String> itemKeys;
  final Map<String, double> heightCache;

  SmartTranscriptChildDelegate({
    required Widget Function(BuildContext, int) builder,
    required this.itemKeys,
    required this.heightCache,
  }) : super(builder, childCount: itemKeys.length);

  @override
  double? estimateMaxScrollOffset(
    int firstIndex,
    int lastIndex,
    double leadingScrollOffset,
    double trailingScrollOffset,
  ) {
    final total = itemKeys.length;
    if (total == 0) return null;
    final avg = heightCache.isEmpty
        ? 120.0
        : heightCache.values.reduce((sum, height) => sum + height) /
              heightCache.length;
    final remainingAfter = total - 1 - lastIndex;
    if (remainingAfter <= 0) {
      return trailingScrollOffset;
    }

    double estimatedAfter = 0;
    for (int i = lastIndex + 1; i < total; i++) {
      estimatedAfter += heightCache[itemKeys[i]] ?? avg;
    }

    return trailingScrollOffset + estimatedAfter;
  }
}

class TranscriptView extends ConsumerStatefulWidget {
  final String sessionId;

  const TranscriptView({super.key, required this.sessionId});

  @override
  ConsumerState<TranscriptView> createState() => _TranscriptViewState();
}

class _TranscriptViewState extends ConsumerState<TranscriptView> {
  String _tr(String it, String en) => ref.read(appLanguageProvider) == AppLanguage.it ? it : en;
  late final BottomAnchoredScrollController _scrollController =
      BottomAnchoredScrollController(
    shouldAnchorToBottom: () => !_userScrolledUpNotifier.value,
  );
  final ValueNotifier<bool> _userScrolledUpNotifier = ValueNotifier<bool>(false);
  bool get _userScrolledUp => _userScrolledUpNotifier.value;
  set _userScrolledUp(bool value) => _userScrolledUpNotifier.value = value;

  bool _isProgrammaticScroll = false;
  String? _lastHandledUiRequestId;

  static const int _initialVisibleCount = 35;
  static const int _pageSize = 250;
  int _visibleCount = _initialVisibleCount;

  final Map<String, double> _entryHeights = {};
  String? _targetAnchorId;
  final GlobalKey _anchorKey = GlobalKey();

  double _calculateAverageHeight() {
    if (_entryHeights.isEmpty) return 120.0;
    double sum = 0;
    for (final height in _entryHeights.values) {
      sum += height;
    }
    return sum / _entryHeights.length;
  }

  bool _initialScrollDone = false;

  bool _isRenaming = false;
  final TextEditingController _renameController = TextEditingController();
  final FocusNode _renameFocusNode = FocusNode();
  final Set<String> _expandedThinkingBlocks = <String>{};
  int _lastTotalEntries = 0;

  static final RegExp _ansiEscape1 = RegExp(r'\x1B\[[0-9;]*[a-zA-Z]');
  static final RegExp _ansiEscape2 = RegExp(r'\x1B\([B0-9]');
  static final RegExp _controlChars = RegExp(
    r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]',
  );
  static final RegExp _splitListDelim = RegExp(r'[,;\s]+');

  Widget? _cachedBentoHeader;
  String? _cachedHeaderSessionName;
  String? _cachedHeaderCwd;
  AgentStatus? _cachedHeaderAgentStatus;
  String? _cachedHeaderModel;
  String? _cachedHeaderThinkingLevel;
  String? _cachedHeaderContextLabel;
  num? _cachedHeaderCost;
  bool? _cachedHeaderIsRenaming;
  bool? _cachedHeaderIsCompact;
  FrameTokens? _cachedHeaderTokens;
  List<MapEntry<String, dynamic>>? _cachedHeaderExtStatuses;
  _ActiveBookTab _activeBookTab = _ActiveBookTab.none;
  int _lastRunningSubagentCount = 0;
  int _lastActiveTodoCount = 0;
  bool _userManuallyToggledTabs = false;
  String? _trackedSessionId;

  void _toggleBookTab(_ActiveBookTab tab) {
    _isProgrammaticScroll = true;
    setState(() {
      _activeBookTab = (_activeBookTab == tab) ? _ActiveBookTab.none : tab;
      _userManuallyToggledTabs = true;
    });
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) {
        _isProgrammaticScroll = false;
      }
    });
  }

  bool _extensionStatusesEqual(
    List<MapEntry<String, dynamic>> a,
    List<MapEntry<String, dynamic>>? b,
  ) {
    if (b == null || a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].key != b[i].key || a[i].value != b[i].value) return false;
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(sessionStateFamily(widget.sessionId).notifier)
            .refreshDefaults();
      }
    });
  }

  @override
  void didUpdateWidget(TranscriptView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) {
      _isRenaming = false;
      _cachedBentoHeader = null;
      _cachedHeaderExtStatuses = null;
      _expandedThinkingBlocks.clear();
      _lastTotalEntries = 0;
      _visibleCount = _pageSize;
      _initialScrollDone = false;
      _userScrolledUp = false;
      _userManuallyToggledTabs = false;
      _activeBookTab = _ActiveBookTab.none;
      _lastActiveTodoCount = 0;
      _lastRunningSubagentCount = 0;
      _trackedSessionId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref
              .read(sessionStateFamily(widget.sessionId).notifier)
              .refreshDefaults();
        }
      });
    }
  }

  void _startRenaming(String currentName) {
    setState(() {
      _isRenaming = true;
      _cachedBentoHeader = null;
      _renameController.text = currentName;
      _renameController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: currentName.length,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _renameFocusNode.canRequestFocus) {
        _renameFocusNode.requestFocus();
      }
    });
  }

  void _cancelRename() {
    if (!_isRenaming) return;
    setState(() {
      _isRenaming = false;
      _cachedBentoHeader = null;
    });
  }

  Future<void> _submitRename() async {
    if (!_isRenaming) return;
    final newName = _renameController.text.trim();
    setState(() {
      _isRenaming = false;
      _cachedBentoHeader = null;
    });
    if (newName.isEmpty) return;

    final currentState = ref.read(sessionStateFamily(widget.sessionId));
    if (newName == (currentState.sessionName ?? widget.sessionId)) return;

    try {
      final notifier = ref.read(sessionStateFamily(widget.sessionId).notifier);
      await notifier.rename(newName);
      ref.invalidate(sessionListProvider);
    } catch (e) {
      if (mounted) {
        FrameSnackBar.show(
          context,
          message: _tr('Errore durante la rinomina: $e', 'Rename failed: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        );
      }
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (!_scrollController.hasClients || _isProgrammaticScroll) return false;

    if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.forward) {
        // User intentionally scrolled upward towards older messages
        final dist =
            _scrollController.position.maxScrollExtent -
            _scrollController.offset;
        if (dist > 60 && !_userScrolledUp) {
          _userScrolledUp = true;
        }
      } else if (notification.direction == ScrollDirection.reverse) {
        // User scrolled downward towards bottom
        final dist =
            _scrollController.position.maxScrollExtent -
            _scrollController.offset;
        if (dist < 40 && _userScrolledUp) {
          _userScrolledUp = false;
        }
      }
    } else if (notification is ScrollUpdateNotification) {
      final dist =
          _scrollController.position.maxScrollExtent - _scrollController.offset;
      if (notification.dragDetails != null) {
        if (dist > 60 && !_userScrolledUp) {
          _userScrolledUp = true;
        } else if (dist < 30 && _userScrolledUp) {
          _userScrolledUp = false;
        }
      }
    }
    return false;
  }

  void _pauseStreamFollowing() {
    _userScrolledUp = true;
  }

  void _followStream() {
    if (!_scrollController.hasClients || _userScrolledUp) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final current = _scrollController.offset;
    final delta = maxScroll - current;
    if (delta <= 0.5) return;

    _isProgrammaticScroll = true;
    _scrollController.jumpTo(maxScroll);
    scheduleMicrotask(() {
      _isProgrammaticScroll = false;
    });
  }

  void _scrollToBottomFull() {
    if (!_scrollController.hasClients) return;
    _isProgrammaticScroll = true;
    _userScrolledUp = false;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        _isProgrammaticScroll = false;
        return;
      }
      if (_scrollController.position.maxScrollExtent >
          _scrollController.offset) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _isProgrammaticScroll = false;
          if (!_scrollController.hasClients) return;
          if (_scrollController.position.maxScrollExtent >
              _scrollController.offset) {
            _scrollController.jumpTo(
              _scrollController.position.maxScrollExtent,
            );
          }
        });
      } else {
        _isProgrammaticScroll = false;
      }
    });
  }

  void _scrollToBottom({bool animate = true}) {
    if (!_scrollController.hasClients) return;
    _isProgrammaticScroll = true;
    _userScrolledUp = false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (animate) {
      _scrollController
          .animateTo(
            maxScroll,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : context.tokens.panelDuration,
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
            _isProgrammaticScroll = false;
          });
    } else {
      _scrollController.jumpTo(maxScroll);
      scheduleMicrotask(() {
        _isProgrammaticScroll = false;
      });
    }
  }

  @override
  void dispose() {
    _renameController.dispose();
    _renameFocusNode.dispose();
    _scrollController.dispose();
    _userScrolledUpNotifier.dispose();
    super.dispose();
  }

  void _checkPendingUiRequests(List<Map<String, dynamic>> requests) {
    if (requests.isEmpty) return;
    final req = requests.last;
    final reqId = req['requestId']?.toString();
    if (reqId != null && reqId != _lastHandledUiRequestId) {
      _lastHandledUiRequestId = reqId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (req['method'] == 'notify') {
          FrameSnackBar.show(
            context,
            message: req['message']?.toString() ?? _tr('Notifica', 'Notification'),
          );
        }
      });
    }
  }

  String _formatTokens(Object? value) {
    if (value is! num) return '—';
    final count = value.toInt();
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 10000) return '${(count / 1000).round()}k';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}k';
    return '$count';
  }

  String _cleanStatusValue(String raw) {
    if (!raw.contains('\x1B') &&
        !raw.contains('[') &&
        !raw.contains('"') &&
        !raw.contains("'")) {
      final t = raw.trim();
      return t.isEmpty ? '—' : t.toUpperCase();
    }

    var s = raw.replaceAll(_ansiEscape1, '');
    s = s.replaceAll(_ansiEscape2, '');
    s = s.replaceAll(_controlChars, '');
    s = s.trim();

    if (s.startsWith('[') && s.endsWith(']')) {
      final inner = s.substring(1, s.length - 1).trim();
      final parts = inner.split(_splitListDelim);
      if (parts.isNotEmpty && parts.every((p) => int.tryParse(p) != null)) {
        try {
          final bytes = parts.map((p) => int.parse(p)).toList();
          if (bytes.every((b) => b >= 32 && b <= 126)) {
            return String.fromCharCodes(bytes).toUpperCase();
          }
        } catch (_) {}
      }
    }

    if ((s.startsWith('"') && s.endsWith('"')) ||
        (s.startsWith("'") && s.endsWith("'"))) {
      s = s.substring(1, s.length - 1).trim();
    }

    return s.isEmpty ? '—' : s.toUpperCase();
  }

  Widget _metricChip(
    FrameTokens tokens,
    String label,
    String value, {
    IconData? leadingIcon,
    Color? iconColor,
    Color? valueColor,
    void Function(BuildContext)? onTap,
    IconData? trailingIcon,
  }) {
    return Builder(
      builder: (chipContext) {
        final chip = Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            border: Border.all(color: tokens.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leadingIcon != null) ...[
                Icon(
                  leadingIcon,
                  size: 12,
                  color: iconColor ?? tokens.textMuted,
                ),
                const SizedBox(width: 4),
              ],
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$label · ',
                      style: TextStyle(color: tokens.textMuted, fontSize: 10),
                    ),
                    TextSpan(
                      text: value,
                      style: TextStyle(
                        color: valueColor ?? tokens.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: 3),
                Icon(trailingIcon, size: 11, color: tokens.textMuted),
              ],
            ],
          ),
        );

        if (onTap == null) return chip;

        return InkWell(
          onTap: () => onTap(chipContext),
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          child: chip,
        );
      },
    );
  }

  Future<void> _showContextDialog(
    BuildContext chipContext,
    Map? contextUsage,
    Map? stats,
    num? cost,
  ) async {
    final tokens = context.tokens;
    final notifier = ref.read(sessionStateFamily(widget.sessionId).notifier);

    await showDialog(
      context: context,
      builder: (dialogCtx) {
        bool compacting = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final currentSession = ref.watch(
              sessionStateFamily(widget.sessionId),
            );
            final currentStats = currentSession.sessionStats;
            final currentUsage =
                currentStats?['contextUsage'] as Map? ??
                currentSession.usage?['contextUsage'] as Map?;
            final tokensUsed =
                currentUsage?['tokens'] ??
                currentSession.usage?['totalTokens'] ??
                '—';
            final maxWindow = currentSession.contextWindowOverride ?? currentUsage?['contextWindow'] ?? '—';
            final pct = (currentSession.contextWindowOverride != null && tokensUsed is num && currentSession.contextWindowOverride! > 0)
                ? (tokensUsed.toDouble() / currentSession.contextWindowOverride! * 100.0)
                : ((currentUsage?['percent'] as num?)?.toDouble() ?? 0.0);
            final inTokens =
                currentSession.usage?['inputTokens'] ??
                currentStats?['inputTokens'] ??
                '—';
            final outTokens =
                currentSession.usage?['outputTokens'] ??
                currentStats?['outputTokens'] ??
                '—';
            final cacheTokens =
                currentSession.usage?['cacheReadTokens'] ??
                currentStats?['cacheReadTokens'] ??
                '—';

            return Dialog(
              backgroundColor: tokens.surfaceElevated,
              alignment: const Alignment(0.0, -0.45),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(tokens.radiusMd),
                side: BorderSide(color: tokens.borderStrong),
              ),
              child: SizedBox(
                width: 330,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.pie_chart_outline,
                                size: 16,
                                color: tokens.syntaxFunction,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _tr('Contesto & Token', 'Context & tokens'),
                                style: TextStyle(
                                  color: tokens.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: Icon(
                              Icons.close,
                              size: 16,
                              color: tokens.textMuted,
                            ),
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _tr('Utilizzo:', 'Usage:'),
                            style: TextStyle(
                              color: tokens.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            '${pct.toStringAsFixed(1)}% (${_formatTokens(tokensUsed)} / ${_formatTokens(maxWindow)})',
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                        child: LinearProgressIndicator(
                          value: (pct / 100.0).clamp(0.0, 1.0),
                          backgroundColor: tokens.surface,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            pct > 85
                                ? tokens.danger
                                : pct > 65
                                ? tokens.warning
                                : tokens.syntaxFunction,
                          ),
                          minHeight: 6,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Divider(color: tokens.border, height: 1),
                      const SizedBox(height: 8),
                      _tokenRow('Token Input', inTokens.toString(), tokens),
                      _tokenRow('Token Output', outTokens.toString(), tokens),
                      _tokenRow('Token Cache', cacheTokens.toString(), tokens),
                      _tokenRow(
                        _tr('Costo Stimato', 'Estimated cost'),
                        cost == null ? '—' : '\$${cost.toStringAsFixed(4)}',
                        tokens,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: tokens.accent,
                          foregroundColor: tokens.accentContrast,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              tokens.radiusSm,
                            ),
                          ),
                        ),
                        icon: compacting
                            ? SizedBox(
                                width: 13,
                                height: 13,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: tokens.accentContrast,
                                ),
                              )
                            : const Icon(Icons.compress, size: 15),
                        label: Text(
                          compacting ? _tr('Compattazione...', 'Compacting...') : _tr('Compatta Contesto', 'Compact context'),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: compacting || currentSession.readOnly
                            ? null
                            : () async {
                                setDialogState(() => compacting = true);
                                try {
                                  await notifier.compact();
                                  if (mounted && ctx.mounted) {
                                    FrameSnackBar.show(
                                      context,
                                      message: _tr('Compattazione completata!', 'Compaction complete!'),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted && ctx.mounted) {
                                    FrameSnackBar.show(
                                      context,
                                      message: _tr('Errore compattazione: $e', 'Compaction failed: $e'),
                                    );
                                  }
                                } finally {
                                  setDialogState(() => compacting = false);
                                }
                              },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _tokenRow(String label, String value, FrameTokens tokens) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: tokens.textMuted, fontSize: 12)),
          Text(
            value,
            style: TextStyle(
              color: tokens.textPrimary,
              fontFamily: tokens.monoFontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCostBreakdownDialog(
    BuildContext chipContext,
    double? mainAgentCost,
    SessionState sessionState,
  ) async {
    final tokens = context.tokens;

    final Map<String, double> agentModelCosts = {};
    final Map<String, int> agentModelTokens = {};

    void parseModelsMap(dynamic map) {
      if (map is! Map) return;
      for (final entry in map.entries) {
        final mName = entry.key.toString();
        final val = entry.value;
        final mCost = (val is Map
            ? (val['cost'] is Map ? (val['cost']['total'] ?? val['cost']['amount']) : val['cost'])
            : val) as num?;
        if (mCost != null) {
          agentModelCosts[mName] = mCost.toDouble();
        }
        if (val is Map) {
          final toks = val['tokens'];
          final totalTok = toks is Map
              ? (toks['total'] as num?)
              : (val['totalTokens'] as num? ?? val['total'] as num?);
          if (totalTok != null) {
            agentModelTokens[mName] = totalTok.toInt();
          }
        }
      }
    }

    parseModelsMap(sessionState.sessionStats?['models']);
    if (agentModelCosts.isEmpty) parseModelsMap(sessionState.sessionStats?['byModel']);
    if (agentModelCosts.isEmpty) parseModelsMap(sessionState.usage?['models']);
    if (agentModelCosts.isEmpty) parseModelsMap(sessionState.usage?['byModel']);

    if (agentModelCosts.isEmpty) {
      for (final e in sessionState.entries) {
        final m = e.metadata?['model']?.toString();
        if (m != null && m.isNotEmpty) {
          final u = e.metadata?['usage'];
          final c = u is Map
              ? (u['cost'] is Map ? (u['cost']['total'] ?? u['cost']['amount']) : u['cost'])
              : null;
          final costNum = (c as num?)?.toDouble() ?? 0.0;
          if (costNum > 0) {
            agentModelCosts[m] = (agentModelCosts[m] ?? 0.0) + costNum;
          }
          if (u is Map) {
            final t = u['tokens'] is Map
                ? (u['tokens']['total'] as num?)
                : (u['totalTokens'] as num? ?? u['total'] as num?);
            if (t != null) {
              agentModelTokens[m] = (agentModelTokens[m] ?? 0) + t.toInt();
            }
          }
        }
      }
    }

    String formatTokens(int tokens) {
      if (tokens >= 1000000000) {
        return '${(tokens / 1000000000).toStringAsFixed(1)}B tokens';
      } else if (tokens >= 1000000) {
        return '${(tokens / 1000000).toStringAsFixed(1)}M tokens';
      } else if (tokens >= 1000) {
        return '${(tokens / 1000).toStringAsFixed(1)}k tokens';
      }
      return '$tokens tokens';
    }

    await showDialog(
      context: context,
      builder: (dialogCtx) {
        int level = 0; // 0: Overview, 1: Main Agent Models, 2: Subagents Breakdown

        return StatefulBuilder(
          builder: (ctx, setDialogState) => Consumer(builder: (ctx, dialogRef, _) {
            final subagents = dialogRef.watch(subagentsFamily(sessionState.sessionId));
            final agents = subagents.where((sub) => !sub.isUnlinked).toList();
            final subagentsCost = agents.fold<double>(0, (sum, sub) => sum + (sub.cost ?? 0));
            final knownSubagentCosts = agents.where((sub) => sub.cost != null).length;
            final subagentsCostLabel = knownSubagentCosts == 0
                ? 'N/D'
                : '${knownSubagentCosts < agents.length ? 'Parziale ' : ''}\$${subagentsCost.toStringAsFixed(4)}';
            final sessionCostLabel = mainAgentCost == null ? 'N/D' : '\$${mainAgentCost.toStringAsFixed(4)}';
            final agentCount = agents.length;
            Widget content;
            String title;
            IconData titleIcon;

            if (level == 1) {
              // Level 1: Agent Models
              title = _tr('Costi Modelli Agente', 'Agent model costs');
              titleIcon = Icons.smart_toy_outlined;
              content = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: tokens.surface,
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                      border: Border.all(color: tokens.border.withValues(alpha: 0.6)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _tr('Costo riportato da Pi', 'Cost reported by Pi'),
                            style: TextStyle(
                              color: tokens.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        Text(
                          sessionCostLabel,
                          style: TextStyle(
                            color: tokens.syntaxString,
                            fontWeight: FontWeight.bold,
                            fontFamily: tokens.monoFontFamily,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (agentModelCosts.isEmpty)
                    Text(_tr('Costi per modello non disponibili', 'Model costs unavailable'), style: TextStyle(color: tokens.textMuted, fontSize: 11))
                  else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: ListView(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      children: agentModelCosts.entries.map((entry) {
                        return Container(
                          key: ValueKey('agent-model-cost-${entry.key}'),
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: tokens.surface,
                            borderRadius: BorderRadius.circular(tokens.radiusSm),
                            border: Border.all(color: tokens.border.withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.memory_outlined,
                                      size: 13,
                                      color: tokens.syntaxKeyword,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            entry.key,
                                            style: TextStyle(
                                              color: tokens.textPrimary,
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (agentModelTokens[entry.key] != null &&
                                              agentModelTokens[entry.key]! > 0)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 2),
                                              child: Text(
                                                formatTokens(agentModelTokens[entry.key]!),
                                                style: TextStyle(
                                                  color: tokens.textMuted,
                                                  fontSize: 10,
                                                  fontFamily: tokens.monoFontFamily,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '\$${entry.value.toStringAsFixed(4)}',
                                style: TextStyle(
                                  color: tokens.syntaxString,
                                  fontFamily: tokens.monoFontFamily,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              );
            } else if (level == 2) {
              // Level 2: Subagents Breakdown
              title = _tr('Costi Subagenti & Modelli', 'Subagent & model costs');
              titleIcon = Icons.hub_outlined;
              content = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: tokens.surface,
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                      border: Border.all(color: tokens.border.withValues(alpha: 0.6)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _tr('Costi sessioni figlie ($agentCount agenti)', 'Child session costs ($agentCount agents)'),
                            style: TextStyle(
                              color: tokens.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        Text(
                          subagentsCostLabel,
                          style: TextStyle(
                            color: tokens.syntaxString,
                            fontWeight: FontWeight.bold,
                            fontFamily: tokens.monoFontFamily,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (subagents.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: Text(
                          _tr('Nessun subagente eseguito.', 'No subagents executed.'),
                          style: TextStyle(color: tokens.textMuted, fontSize: 11),
                        ),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: subagents.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (ctx, i) {
                          final sub = subagents[i];
                          final subCost = sub.cost != null
                              ? '\$${sub.cost!.toStringAsFixed(4)}'
                              : 'N/D';
                          final subModel = sub.model ?? 'N/D';
                          if (sub.isUnlinked) {
                            return Padding(
                              key: ValueKey('unlinked-session-cost-${sub.id}'),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              child: Text(
                                _tr('Sessione figlia non attribuita: ${sub.name} · $subModel · $subCost', 'Unattributed child session: ${sub.name} · $subModel · $subCost'),
                                style: TextStyle(color: tokens.textMuted, fontSize: 11),
                              ),
                            );
                          }

                          return Container(
                            key: ValueKey('subagent-cost-item-${sub.id}'),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            decoration: BoxDecoration(
                              color: tokens.surface,
                              borderRadius: BorderRadius.circular(tokens.radiusSm),
                              border: Border.all(color: tokens.border.withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        sub.name.isNotEmpty ? sub.name : _tr('Subagente #${i + 1}', 'Subagent #${i + 1}'),
                                        style: TextStyle(
                                          color: tokens.textPrimary,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.memory_outlined,
                                            size: 10,
                                            color: tokens.syntaxFunction,
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            subModel,
                                            style: TextStyle(
                                              color: tokens.textSecondary,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  subCost,
                                  style: TextStyle(
                                    color: tokens.syntaxString,
                                    fontFamily: tokens.monoFontFamily,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              );
            } else {
              // Level 0: Main Overview (Total, Agent, Subagents)
              title = _tr('Dettaglio Costi Sessione', 'Session cost details');
              titleIcon = Icons.monetization_on_outlined;
              content = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: tokens.surface,
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                      border: Border.all(color: tokens.border.withValues(alpha: 0.6)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _tr('Costo riportato da Pi', 'Cost reported by Pi'),
                            style: TextStyle(
                              color: tokens.textSecondary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Text(
                          sessionCostLabel,
                          style: TextStyle(
                            color: tokens.syntaxString,
                            fontWeight: FontWeight.bold,
                            fontFamily: tokens.monoFontFamily,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _tr('Il costo Pi può già includere i subagenti. Le cifre non vengono sommate.', 'Pi costs may already include subagents. The amounts are not added together.'),
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: 10.5,
                    ),
                  ),
                  const SizedBox(height: 8),

                  UsageHistoryChart(
                    costByDay: sessionState.sessionStats?['costByDay'] ?? sessionState.usage?['costByDay'],
                    italian: _tr('it', 'en') == 'it',
                  ),
                  const SizedBox(height: 8),

                  // Agent Cost Row (Clickable)
                  InkWell(
                    key: const ValueKey('cost-breakdown-agent-row'),
                    onTap: () => setDialogState(() => level = 1),
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                      decoration: BoxDecoration(
                        color: tokens.surface,
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                        border: Border.all(color: tokens.border),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.smart_toy_outlined,
                            size: 15,
                            color: tokens.accent,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _tr('Sessione Pi', 'Pi session'),
                                  style: TextStyle(
                                    color: tokens.textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  sessionState.currentModel ?? _tr('Modello sessione', 'Session model'),
                                  style: TextStyle(
                                    color: tokens.textMuted,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            sessionCostLabel,
                            style: TextStyle(
                              color: tokens.syntaxString,
                              fontFamily: tokens.monoFontFamily,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: tokens.textMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Subagents Cost Row (Clickable)
                  InkWell(
                    key: const ValueKey('cost-breakdown-subagents-row'),
                    onTap: () => setDialogState(() => level = 2),
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                      decoration: BoxDecoration(
                        color: tokens.surface,
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                        border: Border.all(color: tokens.border),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.hub_outlined,
                            size: 15,
                            color: tokens.syntaxFunction,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _tr('Subagenti', 'Subagents'),
                                  style: TextStyle(
                                    color: tokens.textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '$agentCount subagenti identificati',
                                  style: TextStyle(
                                    color: tokens.textMuted,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            subagentsCostLabel,
                            style: TextStyle(
                              color: tokens.syntaxString,
                              fontFamily: tokens.monoFontFamily,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: tokens.textMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }

            return Dialog(
              backgroundColor: tokens.surfaceElevated,
              alignment: const Alignment(0.0, -0.45),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(tokens.radiusMd),
                side: BorderSide(color: tokens.borderStrong),
              ),
              child: SizedBox(
                width: 350,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SingleChildScrollView(child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                if (level != 0) ...[
                                  IconButton(
                                    key: const ValueKey('cost-breakdown-back-btn'),
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                    icon: Icon(Icons.arrow_back, size: 16, color: tokens.textPrimary),
                                    onPressed: () => setDialogState(() => level = 0),
                                  ),
                                  const SizedBox(width: 4),
                                ] else ...[
                                  Icon(titleIcon, size: 16, color: tokens.syntaxString),
                                  const SizedBox(width: 6),
                                ],
                                Expanded(
                                  child: Text(
                                    title,
                                    style: TextStyle(
                                      color: tokens.textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: tokens.headingFontFamily,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            key: const ValueKey('cost-breakdown-close-btn'),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: Icon(Icons.close, size: 16, color: tokens.textMuted),
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      content,
                    ],
                  )),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appLanguageProvider);
    final tokens = context.tokens;
    final sessionState = ref.watch(sessionStateFamily(widget.sessionId));
    final stats = sessionState.sessionStats;
    final contextUsage =
        stats?['contextUsage'] as Map? ??
        sessionState.usage?['contextUsage'] as Map?;
    final effectiveContextWindow = sessionState.contextWindowOverride ?? contextUsage?['contextWindow'];
    final effectiveTokens = contextUsage?['tokens'] ?? sessionState.usage?['totalTokens'];
    final effectivePercent = (sessionState.contextWindowOverride != null && effectiveTokens is num && sessionState.contextWindowOverride! > 0)
        ? (effectiveTokens.toDouble() / sessionState.contextWindowOverride! * 100.0)
        : (contextUsage?['percent'] as num?);
    final contextLabel = contextUsage == null
        ? _tr('non disponibile', 'unavailable')
        : effectivePercent == null
        ? _tr('post-compattazione · —/${_formatTokens(effectiveContextWindow)}', 'post-compaction · —/${_formatTokens(effectiveContextWindow)}')
        : '${effectivePercent.toStringAsFixed(1)}% · ${_formatTokens(effectiveTokens)}/${_formatTokens(effectiveContextWindow)}';
    final subagents = ref.watch(subagentsFamily(widget.sessionId));
    final todos = ref.watch(todosFamily(widget.sessionId));

    final sessionStatsCost = (stats?['cost'] as num?)?.toDouble();
    final turnCost = (sessionState.usage?['cost'] is Map
            ? (sessionState.usage!['cost']['total'] as num? ??
                sessionState.usage!['cost']['amount'] as num?)
            : (sessionState.usage?['cost'] as num?))
        ?.toDouble();
    final mainAgentCost = sessionStatsCost != null
        ? (turnCost != null && turnCost > sessionStatsCost
            ? turnCost
            : sessionStatsCost)
        : turnCost;
    final subagentsCost = subagents.fold<double>(
      0.0,
      (acc, s) => acc + (s.isUnlinked ? 0.0 : s.cost ?? 0.0),
    );
    final cost = mainAgentCost;

    final activeTodoCount = todos.where((t) => !t.isCompleted).length;
    final runningSubagentCount = subagents.where((s) => !s.isUnlinked && s.isRunning).length;

    final isNewSession = _trackedSessionId != widget.sessionId;
    if (isNewSession) {
      _trackedSessionId = widget.sessionId;
      _activeBookTab = _ActiveBookTab.none;
      _userManuallyToggledTabs = false;
      _lastActiveTodoCount = activeTodoCount;
      _lastRunningSubagentCount = runningSubagentCount;
    } else {
      if (runningSubagentCount > _lastRunningSubagentCount) {
        if (!_userManuallyToggledTabs) {
          _activeBookTab = _ActiveBookTab.subagents;
        }
      } else if (activeTodoCount > _lastActiveTodoCount) {
        if (!_userManuallyToggledTabs && _activeBookTab != _ActiveBookTab.subagents) {
          _activeBookTab = _ActiveBookTab.todos;
        }
      }
      _lastActiveTodoCount = activeTodoCount;
      _lastRunningSubagentCount = runningSubagentCount;
    }

    final extensionStatuses = sessionState.extensionStatuses.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    // Auto check pending extension UI requests
    _checkPendingUiRequests(sessionState.pendingUiRequests);

    final hasActiveTools = sessionState.activeToolCalls.isNotEmpty;
    final liveThinking = sessionState.currentStreamingThinking;
    final liveText = sessionState.currentStreamingText;
    final isCompact = MediaQuery.sizeOf(context).width < 600;

    // Windowing / Pagination for long transcripts (excluding internal/junk messages)
    final cleanEntries = sessionState.entries
        .where((e) => !e.isJunkOrInternal)
        .toList();
    final totalEntries = cleanEntries.length;

    // Keep visible messages in view if new messages arrive during active session
    if (_lastTotalEntries > 0 && totalEntries > _lastTotalEntries) {
      final added = totalEntries - _lastTotalEntries;
      _visibleCount = _visibleCount + added;
      if (cleanEntries.isNotEmpty && cleanEntries.last.role == 'user') {
        _userScrolledUp = false;
      }
    }
    _lastTotalEntries = totalEntries;

    // Transition live thinking expansion to newly committed entry if stream finished
    if (!sessionState.isStreaming &&
        _expandedThinkingBlocks.contains('live_${widget.sessionId}')) {
      final lastAssistant = cleanEntries.reversed
          .where(
            (e) =>
                e.role == 'assistant' &&
                e.thinking != null &&
                e.thinking!.trim().isNotEmpty,
          )
          .firstOrNull;
      if (lastAssistant != null) {
        _expandedThinkingBlocks.remove('live_${widget.sessionId}');
        _expandedThinkingBlocks.add(lastAssistant.id);
      }
    }

    final hiddenCount = (totalEntries - _visibleCount).clamp(0, totalEntries);
    final visibleEntries = cleanEntries.sublist(hiddenCount);
    final hasLoadBanner = hiddenCount > 0 || sessionState.hasMoreHistory;
    final visibleToolIds = {
      for (final entry in visibleEntries)
        for (final tool in entry.toolCalls)
          if (tool.toolCallId.isNotEmpty) tool.toolCallId,
    };
    final liveTools = sessionState.activeToolCalls.values
        .where((tool) => !visibleToolIds.contains(tool.toolCallId))
        .toList();
    final showLiveStream = sessionState.isStreaming ||
        liveText.isNotEmpty || liveThinking.isNotEmpty || liveTools.isNotEmpty;

    // Auto-scroll fluidly with stream if user is near bottom
    if (!_userScrolledUp && showLiveStream) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _followStream();
      });
    }

    final itemKeys = <String>[];
    if (hasLoadBanner) itemKeys.add('banner');
    for (final e in visibleEntries) {
      itemKeys.add(e.id);
    }
    if (showLiveStream) itemKeys.add('livestream');

    // Initial scroll to bottom when opening session or receiving first entries
    if (!_initialScrollDone && sessionState.entries.isNotEmpty) {
      _initialScrollDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottomFull();
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBentoHeader(
          sessionState,
          tokens,
          isCompact,
          contextLabel,
          contextUsage,
          stats,
          cost,
          extensionStatuses,
          subagents,
          todos,
          mainAgentCost: mainAgentCost,
          subagentsCost: subagentsCost,
        ),
        if (todos.isNotEmpty || subagents.isNotEmpty)
          _buildUnifiedBookTabsBar(
            context,
            tokens,
            todos,
            subagents,
            subagentsCost,
            runningSubagentCount,
            isCompact,
          ),
        Expanded(
          child: Stack(
            children: [
              NotificationListener<ScrollNotification>(
                onNotification: _handleScrollNotification,
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  trackVisibility: false,
                  interactive: true,
                  child: ListView.custom(
                    key: const ValueKey('transcript-scroll'),
                    controller: _scrollController,
                    scrollCacheExtent: const ScrollCacheExtent.pixels(2000.0),
                    padding: EdgeInsets.only(
                      top: 10,
                      bottom: isCompact ? 16 : 28,
                    ),
                    childrenDelegate: SmartTranscriptChildDelegate(
                      itemKeys: itemKeys,
                      heightCache: _entryHeights,
                      builder: (context, index) {
                        if (hasLoadBanner && index == 0) {
                          final isLocalHidden = hiddenCount > 0;
                          final int? remainingRemote =
                              sessionState.totalTranscriptEntries != null
                                  ? (sessionState.totalTranscriptEntries! -
                                          totalEntries)
                                      .clamp(
                                        0,
                                        sessionState.totalTranscriptEntries!,
                                      )
                                  : null;
                          final label = isLocalHidden
                              ? _tr('Carica messaggi precedenti ($hiddenCount non mostrati)', 'Load previous messages ($hiddenCount hidden)')
                              : (remainingRemote != null && remainingRemote > 0
                                  ? _tr('Carica altri messaggi dalla cronologia ($remainingRemote rimanenti)', 'Load more history ($remainingRemote remaining)')
                                  : _tr('Carica altri messaggi dalla cronologia', 'Load more messages from history'));

                          return _MeasureSize(
                            onSizeChange: (s) => _entryHeights['banner'] = s.height,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Center(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    side: BorderSide(color: tokens.border),
                                    foregroundColor: tokens.textSecondary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        tokens.radiusSm,
                                      ),
                                    ),
                                  ),
                                  icon: const Icon(Icons.history, size: 14),
                                  label: Text(
                                    label,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  onPressed: () async {
                                    if (visibleEntries.isEmpty) return;
                                    final anchorEntry = visibleEntries.first;
                                    _targetAnchorId = anchorEntry.id;
                                    final oldOffset = _scrollController.offset;

                                    double? initialAnchorY;
                                    final initialBox = _anchorKey.currentContext
                                        ?.findRenderObject() as RenderBox?;
                                    if (initialBox != null && initialBox.attached) {
                                      initialAnchorY = initialBox
                                          .localToGlobal(Offset.zero)
                                          .dy;
                                    }

                                    final avg = _calculateAverageHeight();
                                    double addedHeight = 0;

                                    if (isLocalHidden) {
                                      final oldVisibleCount = _visibleCount;
                                      final newVisibleCount = (_visibleCount + _pageSize)
                                          .clamp(0, totalEntries);
                                      final oldHiddenCount = totalEntries - oldVisibleCount;
                                      final newHiddenCount = totalEntries - newVisibleCount;
                                      for (int i = newHiddenCount; i < oldHiddenCount; i++) {
                                        addedHeight += _entryHeights[cleanEntries[i].id] ?? avg;
                                      }
                                      setState(() {
                                        _visibleCount = newVisibleCount;
                                      });
                                    } else {
                                      final added = await ref
                                          .read(
                                            sessionStateFamily(
                                              widget.sessionId,
                                            ).notifier,
                                          )
                                          .loadOlderHistory(limit: _pageSize);
                                      addedHeight = added * avg;
                                    }

                                    if (addedHeight > 0 && _scrollController.hasClients) {
                                      _isProgrammaticScroll = true;
                                      _scrollController.jumpTo(oldOffset + addedHeight);
                                    }

                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      _isProgrammaticScroll = false;
                                      if (!mounted ||
                                          !_scrollController.hasClients ||
                                          initialAnchorY == null) {
                                        _targetAnchorId = null;
                                        return;
                                      }
                                      final currentBox = _anchorKey.currentContext
                                          ?.findRenderObject() as RenderBox?;
                                      if (currentBox != null && currentBox.attached) {
                                        final currentY = currentBox
                                            .localToGlobal(Offset.zero)
                                            .dy;
                                        final diff = currentY - initialAnchorY;
                                        if (diff.abs() > 0.5) {
                                          _isProgrammaticScroll = true;
                                          _scrollController
                                              .jumpTo(_scrollController.offset + diff);
                                          scheduleMicrotask(
                                            () => _isProgrammaticScroll = false,
                                          );
                                        }
                                      }
                                      _targetAnchorId = null;
                                    });
                                  },
                                ),
                              ),
                            ),
                          );
                        }

                        final entryIndex = index - (hasLoadBanner ? 1 : 0);
                        if (entryIndex < visibleEntries.length) {
                          final entry = visibleEntries[entryIndex];
                          int? elapsedSeconds;
                          if (entry.role != 'user') {
                            final cleanIdx = hiddenCount + entryIndex;
                            if (cleanIdx > 0 && cleanIdx < cleanEntries.length) {
                              final prev = cleanEntries[cleanIdx - 1];
                              final diffMs = entry.timestamp - prev.timestamp;
                              if (diffMs >= 5000) {
                                elapsedSeconds = (diffMs / 1000).round();
                              }
                            }
                            if (elapsedSeconds == null &&
                                entry.toolCalls.isNotEmpty) {
                              int totalToolMs = 0;
                              for (final t in entry.toolCalls) {
                                if (t.durationMs != null) {
                                  totalToolMs += t.durationMs!;
                                }
                              }
                              if (totalToolMs >= 5000) {
                                elapsedSeconds = (totalToolMs / 1000).round();
                              }
                            }
                          }
                          final firstVisibleId = _targetAnchorId ??
                              (visibleEntries.isNotEmpty ? visibleEntries.first.id : null);
                          final isAnchor = entry.id == firstVisibleId;
                          return _MeasureSize(
                            onSizeChange: (s) => _entryHeights[entry.id] = s.height,
                            child: Padding(
                              key: isAnchor ? _anchorKey : ValueKey('entry_row_${entry.id}'),
                              padding: EdgeInsets.symmetric(
                                horizontal: isCompact ? 12 : 24,
                              ),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 820),
                                  child: RepaintBoundary(
                                    key: ValueKey(entry.id),
                                    child: _buildEntryItem(
                                      entry.copyWith(
                                        toolCalls: entry.toolCalls.map((tool) {
                                          final live = tool.toolCallId.isEmpty
                                              ? null
                                              : sessionState.activeToolCalls[tool.toolCallId];
                                          if (live == null) return tool;
                                          return ToolExecutionState(
                                            toolCallId: tool.toolCallId,
                                            toolName: live.toolName.isEmpty
                                                ? tool.toolName : live.toolName,
                                            args: live.args.isEmpty ? tool.args : live.args,
                                            output: live.output.isEmpty
                                                ? tool.output : live.output,
                                            isRunning: live.isRunning,
                                            isError: live.isError || tool.isError,
                                            durationMs: live.durationMs ?? tool.durationMs,
                                            startedAt: live.startedAt ?? tool.startedAt,
                                          );
                                        }).toList(),
                                      ),
                                      tokens,
                                      elapsedSeconds: elapsedSeconds,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }

                        return _MeasureSize(
                          onSizeChange: (s) => _entryHeights['livestream'] = s.height,
                          child: Padding(
                            key: const ValueKey('entry_row_livestream'),
                            padding: EdgeInsets.symmetric(
                              horizontal: isCompact ? 12 : 24,
                            ),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 820),
                                child: RepaintBoundary(
                                  child: _buildLiveStream(
                                    sessionState,
                                    tokens,
                                    liveThinking,
                                    liveText,
                                    hasActiveTools,
                                    liveTools,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              // Overlay activity panels so expanding them cannot move the chat.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _activeBookTab == _ActiveBookTab.todos && todos.isNotEmpty
                      ? TodoPopDown(
                          sessionId: widget.sessionId,
                          isExpanded: true,
                          hideBookTab: true,
                          onClose: () => _toggleBookTab(_ActiveBookTab.todos),
                        )
                      : _activeBookTab == _ActiveBookTab.subagents && subagents.isNotEmpty
                          ? SubagentsPopDown(
                              sessionId: widget.sessionId,
                              isExpanded: true,
                              hideBookTab: true,
                              onClose: () => _toggleBookTab(_ActiveBookTab.subagents),
                            )
                          : const SizedBox.shrink(),
                ),
              ),

              // Floating Scroll-to-bottom Button
              ValueListenableBuilder<bool>(
                valueListenable: _userScrolledUpNotifier,
                builder: (context, userScrolledUp, _) {
                  if (!userScrolledUp) return const SizedBox.shrink();
                  return Positioned(
                    right: 24,
                    bottom: 24,
                    child: FloatingActionButton.small(
                      backgroundColor: tokens.surfaceElevated,
                      foregroundColor: tokens.accent,
                      onPressed: () {
                        _userScrolledUp = false;
                        _scrollToBottom(animate: true);
                      },
                      child: const Icon(Icons.arrow_downward, size: 18),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBentoHeader(
    SessionState sessionState,
    FrameTokens tokens,
    bool isCompact,
    String contextLabel,
    Map? contextUsage,
    Map? stats,
    num? cost,
    List<MapEntry<String, dynamic>> extensionStatuses,
    List<SubagentItem> subagents,
    List<TodoItem> todos, {
    double? mainAgentCost,
    double subagentsCost = 0.0,
  }) {
    final effectiveSessionName = sessionState.sessionName ?? widget.sessionId;
    if (_cachedBentoHeader != null &&
        _cachedHeaderSessionName == effectiveSessionName &&
        _cachedHeaderCwd == sessionState.cwd &&
        _cachedHeaderAgentStatus == sessionState.agentStatus &&
        _cachedHeaderModel == sessionState.currentModel &&
        _cachedHeaderThinkingLevel == sessionState.currentThinkingLevel &&
        _cachedHeaderContextLabel == contextLabel &&
        _cachedHeaderCost == cost &&
        _cachedHeaderIsRenaming == _isRenaming &&
        _cachedHeaderIsCompact == isCompact &&
        identical(_cachedHeaderTokens, tokens) &&
        _extensionStatusesEqual(extensionStatuses, _cachedHeaderExtStatuses)) {
      return _cachedBentoHeader!;
    }

    _cachedHeaderSessionName = effectiveSessionName;
    _cachedHeaderCwd = sessionState.cwd;
    _cachedHeaderAgentStatus = sessionState.agentStatus;
    _cachedHeaderModel = sessionState.currentModel;
    _cachedHeaderThinkingLevel = sessionState.currentThinkingLevel;
    _cachedHeaderContextLabel = contextLabel;
    _cachedHeaderCost = cost;
    _cachedHeaderIsRenaming = _isRenaming;
    _cachedHeaderIsCompact = isCompact;
    _cachedHeaderTokens = tokens;
    _cachedHeaderExtStatuses = extensionStatuses;

    _cachedBentoHeader = Container(
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 10 : 12,
        vertical: isCompact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        border: Border.all(color: tokens.borderStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_isRenaming)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          children: [
                            Expanded(
                              child: Focus(
                                onKeyEvent: (node, event) {
                                  if (event is KeyDownEvent) {
                                    if (event.logicalKey ==
                                        LogicalKeyboardKey.escape) {
                                      _cancelRename();
                                      return KeyEventResult.handled;
                                    }
                                    if (event.logicalKey ==
                                            LogicalKeyboardKey.enter ||
                                        event.logicalKey ==
                                            LogicalKeyboardKey.numpadEnter) {
                                      _submitRename();
                                      return KeyEventResult.handled;
                                    }
                                  }
                                  return KeyEventResult.ignored;
                                },
                                child: TextField(
                                  key: const ValueKey(
                                    'session-name-rename-field',
                                  ),
                                  controller: _renameController,
                                  focusNode: _renameFocusNode,
                                  autofocus: true,
                                  maxLines: 1,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _submitRename(),
                                  style: TextStyle(
                                    color: tokens.textPrimary,
                                    fontFamily: tokens.headingFontFamily,
                                    fontSize: isCompact ? 15 : 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    filled: true,
                                    fillColor: tokens.surfaceElevated,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                        tokens.radiusSm,
                                      ),
                                      borderSide: BorderSide(
                                        color: tokens.syntaxKeyword,
                                        width: 1.2,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                        tokens.radiusSm,
                                      ),
                                      borderSide: BorderSide(
                                        color: tokens.syntaxKeyword,
                                        width: 1.2,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                        tokens.radiusSm,
                                      ),
                                      borderSide: BorderSide(
                                        color: tokens.syntaxKeyword,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              key: const ValueKey('session-name-rename-submit'),
                              icon: Icon(
                                Icons.check,
                                size: 16,
                                color: tokens.syntaxFunction,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 26,
                                minHeight: 26,
                              ),
                              tooltip: _tr('Salva', 'Save'),
                              onPressed: _submitRename,
                            ),
                            IconButton(
                              key: const ValueKey('session-name-rename-cancel'),
                              icon: Icon(
                                Icons.close,
                                size: 16,
                                color: tokens.textMuted,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 26,
                                minHeight: 26,
                              ),
                              tooltip: _tr('Annulla', 'Cancel'),
                              onPressed: _cancelRename,
                            ),
                          ],
                        ),
                      )
                    else
                      GestureDetector(
                        key: const ValueKey('session-name-title'),
                        behavior: HitTestBehavior.opaque,
                        onDoubleTap: () => _startRenaming(
                          sessionState.sessionName ?? widget.sessionId,
                        ),
                        child: Tooltip(
                          message: _tr('Doppio clic per rinominare', 'Double-click to rename'),
                          waitDuration: const Duration(milliseconds: 400),
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    sessionState.sessionName ??
                                        widget.sessionId,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: tokens.textPrimary,
                                      fontFamily: tokens.headingFontFamily,
                                      fontSize: isCompact ? 16 : 19,
                                      height: 1.1,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.edit_outlined,
                                  size: isCompact ? 13 : 15,
                                  color: tokens.textMuted.withValues(
                                    alpha: 0.45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          Icons.folder_outlined,
                          size: 12,
                          color: tokens.syntaxFunction,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            sessionState.cwd.isNotEmpty
                                ? sessionState.cwd
                                : _tr('Nessuna cartella aperta', 'No folder open'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.textSecondary,
                              fontSize: 11,
                              fontFamily: tokens.monoFontFamily,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              AgentStatusBadge(
                status: sessionState.agentStatus,
                onDisplay: false,
              ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _metricChip(
                  tokens,
                  'Contesto',
                  contextLabel,
                  leadingIcon: Icons.pie_chart_outline,
                  iconColor: tokens.syntaxFunction,
                  trailingIcon: Icons.info_outline,
                  onTap: (ctx) =>
                      _showContextDialog(ctx, contextUsage, stats, cost),
                ),
                const SizedBox(width: 6),
                _metricChip(
                  tokens,
                  'Costo',
                  cost == null ? '—' : '\$${cost.toStringAsFixed(4)}',
                  leadingIcon: Icons.monetization_on_outlined,
                  iconColor: tokens.syntaxString,
                  valueColor: tokens.syntaxString,
                  trailingIcon: Icons.arrow_drop_down,
                  onTap: (ctx) => _showCostBreakdownDialog(
                    ctx,
                    mainAgentCost,
                    sessionState,
                  ),
                ),
                for (final status in extensionStatuses) ...[
                  const SizedBox(width: 6),
                  _metricChip(
                    tokens,
                    status.key,
                    _cleanStatusValue(status.value),
                    leadingIcon: Icons.extension_outlined,
                    iconColor: tokens.syntaxKeyword,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    return _cachedBentoHeader!;
  }


  Widget _buildUnifiedBookTabsBar(
    BuildContext context,
    FrameTokens tokens,
    List<TodoItem> todos,
    List<SubagentItem> subagents,
    double subagentsCost,
    int runningSubagentCount,
    bool isCompact,
  ) {
    final completedCount = todos.where((t) => t.isCompleted).length;
    final totalCount = todos.length;
    final isAnyExpanded = _activeBookTab != _ActiveBookTab.none;

    return Container(
      margin: EdgeInsets.only(
        left: isCompact ? 12 : 8,
        right: isCompact ? 12 : 8,
        bottom: isAnyExpanded ? 0 : 4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isAnyExpanded)
            Container(
              height: 2.5,
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                color: tokens.borderStrong.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(1.5),
              ),
            )
          else
            // Reserve the collapsed divider's space to keep the transcript still.
            const SizedBox(height: 4.5),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (todos.isNotEmpty)
                InkWell(
                  key: const ValueKey('todo-peek-tab'),
                  onTap: () => _toggleBookTab(_ActiveBookTab.todos),
                  borderRadius: _activeBookTab == _ActiveBookTab.todos
                      ? const BorderRadius.vertical(top: Radius.circular(6))
                      : BorderRadius.circular(6),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: _activeBookTab == _ActiveBookTab.todos ? 4.5 : 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: _activeBookTab == _ActiveBookTab.todos
                          ? tokens.surface
                          : tokens.surfaceElevated.withValues(alpha: 0.6),
                      borderRadius: _activeBookTab == _ActiveBookTab.todos
                          ? const BorderRadius.vertical(top: Radius.circular(6))
                          : BorderRadius.circular(6),
                      border: Border.all(
                        color: _activeBookTab == _ActiveBookTab.todos
                            ? tokens.borderStrong
                            : tokens.borderStrong.withValues(alpha: 0.6),
                        width: 1,
                      ),
                      boxShadow: _activeBookTab == _ActiveBookTab.todos
                          ? []
                          : [
                              BoxShadow(
                                color: tokens.overlay.withValues(alpha: 0.08),
                                blurRadius: 3,
                                offset: const Offset(0, 1),
                              ),
                            ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.checklist_rtl_rounded,
                          size: 12,
                          color: tokens.accent,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _tr('Attività ($completedCount/$totalCount)', 'Tasks ($completedCount/$totalCount)'),
                          style: TextStyle(
                            color: _activeBookTab == _ActiveBookTab.todos
                                ? tokens.textPrimary
                                : tokens.textSecondary,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(
                          _activeBookTab == _ActiveBookTab.todos
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          size: 13,
                          color: _activeBookTab == _ActiveBookTab.todos
                              ? tokens.accent
                              : tokens.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              if (todos.isNotEmpty && subagents.isNotEmpty)
                const SizedBox(width: 6),
              if (subagents.isNotEmpty)
                InkWell(
                  key: const ValueKey('subagents-book-tab'),
                  onTap: () => _toggleBookTab(_ActiveBookTab.subagents),
                  borderRadius: _activeBookTab == _ActiveBookTab.subagents
                      ? const BorderRadius.vertical(top: Radius.circular(6))
                      : BorderRadius.circular(6),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: _activeBookTab == _ActiveBookTab.subagents ? 4.5 : 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: _activeBookTab == _ActiveBookTab.subagents
                          ? tokens.surface
                          : tokens.surfaceElevated.withValues(alpha: 0.6),
                      borderRadius: _activeBookTab == _ActiveBookTab.subagents
                          ? const BorderRadius.vertical(top: Radius.circular(6))
                          : BorderRadius.circular(6),
                      border: Border.all(
                        color: _activeBookTab == _ActiveBookTab.subagents
                            ? tokens.borderStrong
                            : tokens.borderStrong.withValues(alpha: 0.6),
                        width: 1,
                      ),
                      boxShadow: _activeBookTab == _ActiveBookTab.subagents
                          ? []
                          : [
                              BoxShadow(
                                color: tokens.overlay.withValues(alpha: 0.08),
                                blurRadius: 3,
                                offset: const Offset(0, 1),
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
                          _tr('Subagenti (${subagents.where((s) => !s.isUnlinked).length})', 'Subagents (${subagents.where((s) => !s.isUnlinked).length})'),
                          style: TextStyle(
                            color: _activeBookTab == _ActiveBookTab.subagents
                                ? tokens.textPrimary
                                : tokens.textSecondary,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (subagentsCost > 0) ...[
                          const SizedBox(width: 5),
                          Text(
                            '${subagents.any((s) => !s.isUnlinked && s.cost == null) ? 'Parziale ' : ''}\$${subagentsCost.toStringAsFixed(4)}',
                            style: TextStyle(
                              color: tokens.syntaxString,
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              fontFamily: tokens.monoFontFamily,
                            ),
                          ),
                        ],
                        if (runningSubagentCount > 0) ...[
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
                          _activeBookTab == _ActiveBookTab.subagents
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          size: 13,
                          color: tokens.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLiveStream(
    SessionState sessionState,
    FrameTokens tokens,
    String liveThinking,
    String liveText,
    bool hasActiveTools,
    List<ToolExecutionState> liveTools,
  ) {
    final hasLiveThinking = liveThinking.trim().isNotEmpty;
    final hasLiveText = liveText.trim().isNotEmpty;
    final hasLoadingIndicator = sessionState.agentStatus == AgentStatus.working &&
        !hasLiveThinking &&
        !hasActiveTools;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasLiveThinking) ...[
            ThinkingBlock(
              key: ValueKey('thinking_live_${widget.sessionId}'),
              thinkingText: liveThinking,
              isStreaming: sessionState.isStreaming,
              isExpanded: _expandedThinkingBlocks.contains(
                'live_${widget.sessionId}',
              ),
              onExpansionChanged: (expanded) {
                setState(() {
                  if (expanded) {
                    _expandedThinkingBlocks.add('live_${widget.sessionId}');
                  } else {
                    _expandedThinkingBlocks.remove('live_${widget.sessionId}');
                  }
                });
              },
            ),
            if (liveTools.isNotEmpty || hasLiveText || hasLoadingIndicator)
              const SizedBox(height: 6),
          ],
          if (liveTools.isNotEmpty) ...[
            ToolTimeline(
              toolCalls: liveTools,
              onCardExpansionChanged: _pauseStreamFollowing,
            ),
            if (hasLiveText || hasLoadingIndicator)
              const SizedBox(height: 6),
          ],
          if (hasLiveText) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: tokens.surfaceElevated,
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                border: Border.all(color: tokens.borderStrong),
              ),
              child: RichContent(text: liveText, cwd: sessionState.cwd),
            ),
            const SizedBox(height: 6),
          ] else if (hasLoadingIndicator) ...[
            Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    color: tokens.agentWorking,
                    strokeWidth: 2,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _tr('Elaborazione in corso...', 'Processing...'),
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          // Seconds counter for live turn taking >= 5s
          _LiveTurnTimerWidget(
            startTime: sessionState.runStartedAt == null ? null :
                DateTime.fromMillisecondsSinceEpoch(sessionState.runStartedAt!),
            tokens: tokens,
          ),
        ],
      ),
    );
  }

  Future<void> _handleFork(String entryId) async {
    final client = ref.read(pcpClientProvider);
    if (client == null) return;
    if (!await resolveDirtyRepository(
      context,
      ref,
      ref.read(activeSessionIdProvider),
    )) {
      return;
    }
    try {
      final res = await client.forkSession(widget.sessionId, entryId: entryId);
      if (!mounted || !context.mounted) return;
      final data = res['data'] as Map<String, dynamic>? ?? res;
      if (data['cancelled'] == true) {
        if (!mounted) return;
        FrameSnackBar.show(
          context,
          message: "Fork annullato dall'extension",
        );
        return;
      }
      final newSid = data['sessionId'] as String? ?? data['id'] as String?;
      if (newSid != null) {
        if (!await switchSessionSafely(context, ref, newSid)) return;
        ref.invalidate(sessionListProvider);
        if (!mounted) return;
        FrameSnackBar.show(
          context,
          message: _tr('Nuovo ramo avviato: $newSid', 'New branch started: $newSid'),
        );
      }
    } catch (e) {
      if (!mounted) return;
      FrameSnackBar.show(
        context,
        message: _tr('Errore fork: $e', 'Fork failed: $e'),
        backgroundColor: context.tokens.danger,
      );
    }
  }

  void _restoreFailedPrompt(String entryId) {
    final entry = ref
        .read(sessionStateFamily(widget.sessionId).notifier)
        .removeFailedPrompt(entryId);
    if (entry == null) return;
    final (text, attachments) = parseAttachmentsFromText(entry.text);
    final draft = ref.read(composerDraftProvider(widget.sessionId).notifier);
    final existingDraft = draft.state;
    draft.state = [
      if (text.isNotEmpty) text,
      if (existingDraft.isNotEmpty) existingDraft,
    ].join('\n');
    ref
        .read(composerAttachmentsProvider(widget.sessionId).notifier)
        .addAll(attachments);
  }

  Widget _buildEntryItem(
    SessionEntry entry,
    FrameTokens tokens, {
    int? elapsedSeconds,
  }) {
    if (entry.isJunkOrInternal) return const SizedBox.shrink();
    final cwd = ref.watch(
      sessionStateFamily(widget.sessionId).select((s) => s.cwd),
    );
    final isUser = entry.role == 'user';

    if (isUser) {
      final (cleanText, attachments) = parseAttachmentsFromText(entry.text);
      final sendError = entry.metadata?['sendError'] as String?;
      final screenWidth = MediaQuery.sizeOf(context).width;
      final bubble = Container(
        key: sendError == null
            ? null
            : ValueKey('failed-message-bubble-${entry.id}'),
        constraints: const BoxConstraints(maxWidth: 720),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tokens.userBubble,
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          border: Border.all(
            color: sendError == null ? tokens.border : tokens.danger,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_outline, size: 13, color: tokens.accent),
                    const SizedBox(width: 4),
                    Text(
                      'Tu',
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Flexible(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => _handleFork(entry.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.call_split,
                            size: 12,
                            color: tokens.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              _tr('Riparti da qui', 'Branch from here'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tokens.textSecondary,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (attachments.isNotEmpty) ...[
              const SizedBox(height: 10),
              AttachmentListBar(
                key: ValueKey('user-attachments-${entry.id}'),
                attachments: attachments,
                isEditable: false,
              ),
            ],
            if (cleanText.isNotEmpty) ...[
              const SizedBox(height: 8),
              RichContent(text: cleanText, cwd: cwd),
            ],
            if (sendError != null) ...[
              const SizedBox(height: 8),
              Text(
                _tr('Invio non riuscito: $sendError', 'Send failed: $sendError'),
                key: ValueKey('failed-message-error-${entry.id}'),
                style: TextStyle(color: tokens.danger, fontSize: 12),
              ),
            ],
          ],
        ),
      );

      if (sendError == null) {
        return Container(
          margin: EdgeInsets.only(
            left: screenWidth < 500 ? 12 : 48,
            bottom: 12,
          ),
          alignment: Alignment.centerRight,
          child: bubble,
        );
      }

      return Container(
        margin: EdgeInsets.only(
          left: screenWidth < 500 ? 12 : 48,
          right: screenWidth < 500 ? 12 : 48,
          bottom: 12,
        ),
        child: Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  key: ValueKey('failed-user-message-${entry.id}'),
                  onDoubleTap: () => _restoreFailedPrompt(entry.id),
                  child: bubble,
                ),
              ),
            ),
            IconButton(
              key: ValueKey('retry-user-message-${entry.id}'),
              tooltip: _tr('Riprova invio', 'Retry sending'),
              onPressed: () => unawaited(
                ref
                    .read(sessionStateFamily(widget.sessionId).notifier)
                    .retryFailedPrompt(entry.id),
              ),
              icon: const Icon(Icons.refresh),
              color: tokens.danger,
            ),
          ],
        ),
      );
    }

    if (entry.role == 'bashExecution') {
      return _buildBashExecutionItem(entry, tokens);
    }

    if (entry.role == 'branchSummary') {
      return _buildBranchSummaryItem(entry, tokens);
    }

    if (entry.role == 'compactionSummary') {
      return _buildCompactionSummaryItem(entry, tokens);
    }

    if (entry.role == 'custom') {
      return _buildCustomItem(entry, tokens);
    }

    // Assistant entry
    final isToolOnly = entry.text.trim().isEmpty &&
        (entry.toolCalls.isNotEmpty ||
            (entry.thinking != null && entry.thinking!.trim().isNotEmpty));
    return Container(
      margin: EdgeInsets.only(bottom: isToolOnly ? 6 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Thinking block if present
          if (entry.thinking != null && entry.thinking!.trim().isNotEmpty) ...[
            ThinkingBlock(
              key: ValueKey('thinking_${entry.id}'),
              thinkingText: entry.thinking!.trim(),
              isExpanded: _expandedThinkingBlocks.contains(entry.id),
              onExpansionChanged: (expanded) {
                setState(() {
                  if (expanded) {
                    _expandedThinkingBlocks.add(entry.id);
                  } else {
                    _expandedThinkingBlocks.remove(entry.id);
                  }
                });
              },
            ),
            if (entry.toolCalls.isNotEmpty || entry.text.isNotEmpty)
              const SizedBox(height: 6),
          ],

          // Tool calls timeline if present
          if (entry.toolCalls.isNotEmpty) ...[
            ToolTimeline(
              toolCalls: entry.toolCalls,
              onCardExpansionChanged: _pauseStreamFollowing,
            ),
            if (entry.text.isNotEmpty)
              const SizedBox(height: 6),
          ],

          // Message content
          if (entry.text.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(tokens.radiusMd),
                border: Border.all(color: tokens.borderStrong),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.smart_toy_outlined,
                            size: 14,
                            color: tokens.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _tr('Assistente', 'Assistant'),
                            style: TextStyle(
                              color: tokens.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (elapsedSeconds != null &&
                              elapsedSeconds >= 5) ...[
                            Container(
                              key: ValueKey('entry_timer_${entry.id}'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: tokens.surfaceElevated,
                                borderRadius: BorderRadius.circular(
                                  tokens.radiusSm,
                                ),
                                border: Border.all(color: tokens.border),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.timer_outlined,
                                    size: 11,
                                    color: tokens.textMuted,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    '${elapsedSeconds}s',
                                    style: TextStyle(
                                      color: tokens.textMuted,
                                      fontSize: 10,
                                      fontFamily: tokens.monoFontFamily,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          IconButton(
                            tooltip: _tr('Copia messaggio', 'Copy message'),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: entry.text));
                              FrameSnackBar.show(
                                context,
                                message: _tr('Messaggio copiato negli appunti', 'Message copied to clipboard'),
                                duration: const Duration(seconds: 1),
                              );
                            },
                            icon: Icon(
                              Icons.copy_outlined,
                              size: 16,
                              color: tokens.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Builder(
                    builder: (context) {
                      final (cleanText, attachments) =
                          parseAttachmentsFromText(entry.text);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (attachments.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            AttachmentListBar(
                              key: ValueKey('asst-attachments-${entry.id}'),
                              attachments: attachments,
                              isEditable: false,
                            ),
                          ],
                          if (cleanText.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            RichContent(text: cleanText, cwd: cwd),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBashExecutionItem(SessionEntry entry, FrameTokens tokens) {
    final command = entry.metadata?['command']?.toString() ?? '!command';
    final exitCode = entry.metadata?['exitCode'] as int?;
    final cancelled = entry.metadata?['cancelled'] == true;
    final truncated = entry.metadata?['truncated'] == true;
    final output = entry.text;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        border: Border.all(color: tokens.borderStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: tokens.surfaceElevated,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(tokens.radiusMd),
              ),
              border: Border(bottom: BorderSide(color: tokens.border)),
            ),
            child: Row(
              children: [
                Icon(Icons.terminal, size: 14, color: tokens.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    command,
                    style: TextStyle(
                      fontFamily: tokens.monoFontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: tokens.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (cancelled) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: tokens.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                      border: Border.all(color: tokens.warning.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      _tr('annullato', 'cancelled'),
                      style: TextStyle(
                        fontSize: 10,
                        color: tokens.warning,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ] else if (exitCode != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: exitCode == 0
                          ? tokens.success.withValues(alpha: 0.15)
                          : tokens.danger.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                      border: Border.all(
                        color: (exitCode == 0 ? tokens.success : tokens.danger)
                            .withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      'exit $exitCode',
                      style: TextStyle(
                        fontFamily: tokens.monoFontFamily,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: exitCode == 0 ? tokens.success : tokens.danger,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.copy, size: 13),
                  tooltip: _tr('Copia output', 'Copy output'),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: output));
                    FrameSnackBar.show(
                      context,
                      message: _tr('Output copiato', 'Output copied'),
                      duration: const Duration(seconds: 1),
                    );
                  },
                ),
              ],
            ),
          ),
          if (output.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                output,
                style: TextStyle(
                  fontFamily: tokens.monoFontFamily,
                  fontSize: 11.5,
                  height: 1.4,
                  color: tokens.textSecondary,
                ),
              ),
            ),
          if (truncated)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(
                _tr('Output parziale (troncato)', 'Partial output (truncated)'),
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  fontSize: 10,
                  color: tokens.textMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBranchSummaryItem(SessionEntry entry, FrameTokens tokens) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        children: [
          Icon(Icons.call_split, size: 14, color: tokens.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.text.isNotEmpty
                  ? entry.text
                  : _tr('Diramazione creata da ${entry.metadata?['fromId'] ?? ''}', 'Branch created from ${entry.metadata?['fromId'] ?? ''}'),
              style: TextStyle(
                fontSize: 11,
                color: tokens.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (entry.metadata?['fromId'] != null)
            Text(
              'orig: ${entry.metadata!['fromId']}',
              style: TextStyle(
                fontFamily: tokens.monoFontFamily,
                fontSize: 10,
                color: tokens.textMuted,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCompactionSummaryItem(SessionEntry entry, FrameTokens tokens) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        children: [
          Icon(Icons.compress, size: 14, color: tokens.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.text.isNotEmpty ? entry.text : _tr('Contesto compattato', 'Context compacted'),
              style: TextStyle(
                fontSize: 11,
                color: tokens.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (entry.metadata?['tokensBefore'] != null)
            Text(
              _tr('${entry.metadata!['tokensBefore']} token iniziali', '${entry.metadata!['tokensBefore']} initial tokens'),
              style: TextStyle(
                fontFamily: tokens.monoFontFamily,
                fontSize: 10,
                color: tokens.textMuted,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCustomItem(SessionEntry entry, FrameTokens tokens) {
    final customType =
        entry.metadata?['customType']?.toString() ?? 'Estensione';
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        border: Border.all(color: tokens.borderStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: tokens.surfaceElevated,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(tokens.radiusMd),
              ),
              border: Border(bottom: BorderSide(color: tokens.border)),
            ),
            child: Row(
              children: [
                Icon(Icons.extension_outlined, size: 13, color: tokens.accent),
                const SizedBox(width: 6),
                Text(
                  customType,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: tokens.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          if (entry.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: RichContent(text: entry.text),
            ),
        ],
      ),
    );
  }
}

class _LiveTurnTimerWidget extends StatefulWidget {
  final DateTime? startTime;
  final FrameTokens tokens;

  const _LiveTurnTimerWidget({
    required this.startTime,
    required this.tokens,
  });

  @override
  State<_LiveTurnTimerWidget> createState() => _LiveTurnTimerWidgetState();
}

class _LiveTurnTimerWidgetState extends State<_LiveTurnTimerWidget> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(_LiveTurnTimerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startTime != widget.startTime) {
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    if (widget.startTime != null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final liveElapsedSec = widget.startTime != null
        ? DateTime.now().difference(widget.startTime!).inSeconds
        : 0;

    if (liveElapsedSec < 5) {
      return const SizedBox.shrink();
    }

    final tokens = widget.tokens;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Container(
            key: const ValueKey('livestream-seconds-counter'),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: tokens.agentWorking.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              border: Border.all(
                color: tokens.agentWorking.withValues(alpha: 0.35),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: 12,
                  color: tokens.agentWorking,
                ),
                const SizedBox(width: 4),
                Text(
                  '${liveElapsedSec}s',
                  style: TextStyle(
                    color: tokens.agentWorking,
                    fontSize: 11,
                    fontFamily: tokens.monoFontFamily,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
