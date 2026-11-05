import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../data/language/language_settings.dart';
import '../../domain/session/context_pricing_helper.dart';
import '../../domain/session/agent_status.dart';
import '../session_tree/session_tree_dialog.dart';
import '../workspace/repository_workspace.dart';
import 'context_window_selector.dart';
import '../../ui/frame_snack_bar.dart';

class ContextPanel extends ConsumerStatefulWidget {
  final String sessionId;

  const ContextPanel({super.key, required this.sessionId});

  @override
  ConsumerState<ContextPanel> createState() => _ContextPanelState();
}

class _ContextPanelState extends ConsumerState<ContextPanel> {
  String _tr(String it, String en) =>
      ref.read(appLanguageProvider) == AppLanguage.it ? it : en;
  List<Map<String, dynamic>> _models = [];
  List<String> _thinkingLevels = [];
  bool _isLoadingParams = true;
  bool _isCompacting = false;
  double? _reserveDraft;
  bool _savingReserve = false;

  @override
  void initState() {
    super.initState();
    _loadParams();
  }

  @override
  void didUpdateWidget(covariant ContextPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) {
      _models = [];
      _isLoadingParams = true;
      _reserveDraft = null;
      _savingReserve = false;
      _loadParams();
    }
  }

  Future<void> _loadParams() async {
    final sessionId = widget.sessionId;
    final notifier = ref.read(sessionStateFamily(sessionId).notifier);
    await notifier.refreshDefaults();
    try {
      final result = await notifier.getAvailableModelsWithWarning();
      final levels = await notifier.getAvailableThinkingLevels();

      if (mounted && widget.sessionId == sessionId) {
        setState(() {
          _models = result.models.map((model) => Map<String, dynamic>.from(model)).toList();
          _thinkingLevels = levels.isNotEmpty
              ? levels
              : ['off', 'low', 'medium', 'high'];
          _isLoadingParams = false;
        });
        if (result.warning != null) {
          FrameSnackBar.show(context, message: result.warning!);
        }
      }
    } catch (error) {
      if (mounted && widget.sessionId == sessionId) {
        setState(() => _isLoadingParams = false);
        FrameSnackBar.show(context, message: _tr('Modelli non disponibili: $error', 'Models unavailable: $error'));
      }
    }
  }

  Future<bool> _runAction(Future<void> Function() action) async {
    try {
      await action();
      return true;
    } catch (error) {
      if (mounted) {
        FrameSnackBar.show(context, message: _tr('Azione non riuscita: $error', 'Action failed: $error'));
      }
      return false;
    }
  }

  Future<void> _saveReserve(double percent) async {
    if (_savingReserve || ref.read(contextPolicySavingProvider(widget.sessionId))) return;
    final sessionId = widget.sessionId;
    final saving = ref.read(contextPolicySavingProvider(sessionId).notifier);
    saving.state = true;
    setState(() => _savingReserve = true);
    try {
      await ref
          .read(sessionStateFamily(sessionId).notifier)
          .setCompactionReservePercent(percent);
    } catch (error) {
      if (mounted) {
        if (widget.sessionId == sessionId) FrameSnackBar.show(context, message: _tr('Margine non applicato: $error', 'Reserve not applied: $error'));
      }
    } finally {
      if (saving.mounted) saving.state = false;
      if (mounted && widget.sessionId == sessionId) {
        setState(() {
          _savingReserve = false;
          _reserveDraft = null;
        });
      }
    }
  }

  Future<void> _triggerCompaction() async {
    if (_isCompacting) return;
    setState(() => _isCompacting = true);

    final notifier = ref.read(sessionStateFamily(widget.sessionId).notifier);
    Map<String, dynamic>? res;
    try {
      final result = await notifier.compact();
      res = (result?['data'] as Map<String, dynamic>?) ?? result;
    } catch (error) {
      if (mounted) {
        FrameSnackBar.show(
          context,
          message: _tr('Compattazione non riuscita: $error', 'Compaction failed: $error'),
        );
      }
    } finally {
      if (mounted) setState(() => _isCompacting = false);
    }

    if (mounted && res != null) {
      final tokensBefore = res['tokensBefore'] ?? '?';
      final tokensAfter =
          res['estimatedTokensAfter'] ?? res['tokensAfter'] ?? '?';
      final usage = res['usage'] as Map?;
      final cost = usage?['cost'] is Map ? '\$${usage!['cost']['total']}' : '';

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: context.tokens.surface,
          title: Text(
            _tr('Compattazione completata', 'Compaction complete'),
            style: TextStyle(color: context.tokens.textPrimary),
          ),
          content: Text(
            _tr('Token prima: $tokensBefore\nToken dopo: $tokensAfter\n${cost.isNotEmpty ? "Costo: $cost" : ""}', 'Tokens before: $tokensBefore\nTokens after: $tokensAfter\n${cost.isNotEmpty ? "Cost: $cost" : ""}'),
            style: TextStyle(color: context.tokens.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'OK',
                style: TextStyle(color: context.tokens.textPrimary),
              ),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _cloneSession() async {
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
      final result = await client.cloneSession(widget.sessionId);
      if (!mounted) return;
      final data = (result['data'] as Map<String, dynamic>?) ?? result;
      final targetSessionId = (data['sessionId'] ?? data['id']) as String?;
      if (targetSessionId != null) {
        if (!await switchSessionSafely(context, ref, targetSessionId)) {
          return;
        }
        ref.invalidate(sessionListProvider);
      }
    } catch (error) {
      if (mounted) {
        FrameSnackBar.show(
          context,
          message: _tr('Duplicazione non riuscita: $error', 'Duplication failed: $error'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appLanguageProvider);
    final tokens = context.tokens;
    final currentModel = ref.watch(
      sessionStateFamily(widget.sessionId).select((s) => s.currentModel),
    );
    final currentThinkingLevel = ref.watch(
      sessionStateFamily(widget.sessionId)
          .select((s) => s.currentThinkingLevel),
    );
    final usage = ref.watch(
      sessionStateFamily(widget.sessionId).select((s) => s.usage),
    );
    final sessionStats = ref.watch(
      sessionStateFamily(widget.sessionId).select((s) => s.sessionStats),
    );
    final readOnly = ref.watch(
      sessionStateFamily(widget.sessionId).select((s) => s.readOnly),
    );
    final sessionBusy = ref.watch(
      sessionStateFamily(widget.sessionId).select((s) => s.isStreaming ||
          const {AgentStatus.retrying, AgentStatus.compacting, AgentStatus.awaitingUser}.contains(s.agentStatus)),
    );
    final policySaving = ref.watch(contextPolicySavingProvider(widget.sessionId));
    final sessionNotifier = ref.read(
      sessionStateFamily(widget.sessionId).notifier,
    );

    final currentModelName =
        currentModel ??
        (_models.isNotEmpty
            ? (_models.first['name'] ?? _models.first['id'])
            : 'Default');
    final currentThinking = currentThinkingLevel ?? 'medium';

    final contextUsage =
        (sessionStats?['contextUsage'] as Map<String, dynamic>?) ??
        (usage?['contextUsage'] as Map<String, dynamic>?);
    final totalTokens = (contextUsage?['tokens'] as num?)?.toInt();
    final percent = (contextUsage?['percent'] as num?)?.toDouble();
    final autoCompaction = ref.watch(
      sessionStateFamily(widget.sessionId).select((s) => s.autoCompaction),
    );

    final activeModelMap = _models.firstWhere(
      (m) => m['name'] == currentModel || m['id'] == currentModel,
      orElse: () => const {},
    );
    final fullWindow = modelContextWindow(activeModelMap);
    final contextOverride = ref.watch(
      sessionStateFamily(widget.sessionId)
          .select((s) => s.contextWindowOverride),
    );
    final reservePercent = ref.watch(
      sessionStateFamily(widget.sessionId)
          .select((s) => s.compactionReservePercent),
    );
    final reserveValue = (_reserveDraft ?? reservePercent).clamp(0.5, 25).toDouble();
    final effectiveWindow =
        contextOverride ??
        (contextUsage?['contextWindow'] as num?)?.toInt() ??
        fullWindow ??
        0;
    final compactionThreshold = effectiveWindow > 0
        ? usableContextWindow(effectiveWindow, reservePercent)
        : 0.0;
    final effectivePercent = effectiveWindow > 0 && totalTokens != null
        ? (totalTokens / effectiveWindow * 100.0)
        : percent;

    return Container(
      width: 320,
      decoration: BoxDecoration(color: tokens.surface),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: tokens.displaySurface,
              border: Border(bottom: BorderSide(color: tokens.border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _tr('Sessione', 'Session'),
                    style: TextStyle(
                      color: tokens.displayText,
                      fontSize: 24,
                      height: 1,
                      fontFamily: tokens.headingFontFamily,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Session settings; repository and Git status live in Git Changes.
                // 1. Modello Attivo
                Text(
                  _tr('Modello LLM', 'LLM model'),
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                _isLoadingParams
                    ? SizedBox(
                        height: 36,
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: tokens.accent,
                          ),
                        ),
                      )
                    : _models.isEmpty
                    ? Text(
                        currentModel == null
                            ? _tr('Nessun modello abilitato in Pi.', 'No models enabled in Pi.')
                            : '$currentModel\nElenco modelli non disponibile.',
                        style: TextStyle(color: tokens.textMuted, fontSize: 12),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: tokens.surfaceElevated,
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                          border: Border.all(color: tokens.border, width: 1),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            borderRadius: BorderRadius.circular(
                              tokens.radiusMd,
                            ),
                            dropdownColor: tokens.surfaceElevated,
                            value:
                                _models.any(
                                  (m) =>
                                      m['name'] == currentModelName ||
                                      m['id'] == currentModelName,
                                )
                                ? currentModelName
                                : (_models.isNotEmpty
                                      ? (_models.first['name'] ??
                                            _models.first['id'])
                                      : null),
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: 13,
                              fontFamily: tokens.uiFontFamily,
                            ),
                            items: _models.map((m) {
                              final name =
                                  m['name'] as String? ?? m['id'] as String;
                              return DropdownMenuItem<String>(
                                value: name,
                                child: Text(
                                  name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: readOnly || sessionBusy || policySaving
                                ? null
                                : (newModel) {
                                    if (newModel != null) {
                                      final modelObj = _models.firstWhere(
                                        (m) =>
                                            (m['name'] ?? m['id'])
                                                ?.toString() ==
                                            newModel,
                                        orElse: () => {
                                          'provider': '',
                                          'id': newModel,
                                        },
                                      );
                                      final provider =
                                          modelObj['provider']?.toString() ??
                                          '';
                                      final modelId =
                                          modelObj['id']?.toString() ??
                                          newModel;
                                      _runAction(
                                        () => sessionNotifier.setModel(
                                          provider,
                                          modelId,
                                        ),
                                      );
                                    }
                                  },
                          ),
                        ),
                      ),
                const SizedBox(height: 16),

                // 2. Livello Reasoning / Thinking
                Text(
                  _tr('Livello Thinking', 'Thinking level'),
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: tokens.surfaceElevated,
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    border: Border.all(color: tokens.border, width: 1),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      borderRadius: BorderRadius.circular(tokens.radiusMd),
                      dropdownColor: tokens.surfaceElevated,
                      value: _thinkingLevels.contains(currentThinking)
                          ? currentThinking
                          : (_thinkingLevels.isNotEmpty
                                ? _thinkingLevels.first
                                : 'off'),
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: 13,
                        fontFamily: tokens.uiFontFamily,
                      ),
                      items: _thinkingLevels.map((lvl) {
                        return DropdownMenuItem<String>(
                          value: lvl,
                          child: Text(lvl.toUpperCase()),
                        );
                      }).toList(),
                      onChanged: readOnly || sessionBusy || policySaving
                          ? null
                          : (newLevel) {
                              if (newLevel != null) {
                                _runAction(
                                  () => sessionNotifier.setThinkingLevel(
                                    newLevel,
                                  ),
                                );
                              }
                            },
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Text(
                  _tr('Dimensione Contesto', 'Context size'),
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                ContextWindowSelector(
                  sessionId: widget.sessionId,
                  model: activeModelMap,
                  readOnly: readOnly,
                ),
                const SizedBox(height: 12),
                Text(
                  _tr('Margine per compattazione (%)', 'Compaction reserve (%)'),
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Slider(
                  key: const ValueKey('context-panel-compaction-reserve-slider'),
                  activeColor: tokens.accent,
                  thumbColor: tokens.accent,
                  inactiveColor: tokens.border,
                  min: 0.5,
                  max: 25,
                  divisions: 49,
                  value: reserveValue,
                  label: '${reserveValue.toStringAsFixed(1)}%',
                  semanticFormatterCallback: (value) => '${value.toStringAsFixed(1)}%',
                  onChanged: readOnly || sessionBusy || _savingReserve || policySaving
                      ? null
                      : (value) => setState(() => _reserveDraft = value),
                  onChangeEnd: readOnly || sessionBusy || _savingReserve || policySaving
                      ? null
                      : _saveReserve,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_tr('0,5–25% · Passo 0,5%', '0.5–25% · Step 0.5%'), style: TextStyle(color: tokens.textMuted, fontSize: 10)),
                    Text('${reserveValue.toStringAsFixed(1)}%',
                      style: TextStyle(color: tokens.textMuted, fontSize: 11)),
                  ],
                ),
                if (reservePercent < 0.5 || reservePercent > 25)
                  Text(_tr('Margine salvato fuori intervallo: ${reservePercent.toStringAsFixed(1)}%. Trascina per aggiornarlo.', 'Saved reserve is out of range: ${reservePercent.toStringAsFixed(1)}%. Drag to update.'),
                    style: TextStyle(color: tokens.warning, fontSize: 10)),
                const SizedBox(height: 4),
                Text(
                  !autoCompaction
                      ? _tr('Compattazione automatica disabilitata in Pi.', 'Automatic compaction is disabled in Pi.')
                      : effectiveWindow > 0
                          ? _tr('Soglia: ${formatTokens(compactionThreshold.floor())} token; margine ${reservePercent.toStringAsFixed(1)}%. Pi può compattare prima se la sua riserva nativa è maggiore. Output singoli possono oltrepassare la soglia.', 'Threshold: ${formatTokens(compactionThreshold.floor())} tokens; reserve ${reservePercent.toStringAsFixed(1)}%. Pi may compact earlier if its native reserve is larger. Individual outputs may exceed the threshold.')
                          : _tr('Il margine resta inutilizzato prima della compattazione automatica.', 'The reserve remains unused before automatic compaction.'),
                  style: TextStyle(color: tokens.textMuted, fontSize: 10),
                ),
                const SizedBox(height: 16),

                // 4. Finestra di Contesto
                Text(
                  _tr('Utilizzo Contesto', 'Context usage'),
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                if (effectivePercent != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    child: LinearProgressIndicator(
                      value: (effectivePercent / 100.0).clamp(0.0, 1.0),
                      backgroundColor: tokens.background,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        effectivePercent > 80
                            ? tokens.danger
                            : (effectivePercent > 60
                                  ? tokens.warning
                                  : tokens.success),
                      ),
                      minHeight: 8,
                    ),
                  ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      totalTokens == null
                          ? _tr('Dati non disponibili', 'Data unavailable')
                          : '$totalTokens / ${formatTokens(effectiveWindow)} token',
                      style: TextStyle(color: tokens.textMuted, fontSize: 11),
                    ),
                    if (effectivePercent != null)
                      Text(
                        '${effectivePercent.toStringAsFixed(1)} %',
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),

                // 5. Actions (Compaction, Duplicate Branch)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: tokens.surfaceElevated,
                    foregroundColor: tokens.textPrimary,
                    side: BorderSide(color: tokens.border),
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                    ),
                  ),
                  icon: _isCompacting
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: tokens.accent,
                          ),
                        )
                      : Icon(Icons.compress, size: 16, color: tokens.accent),
                  label: Text(
                    _isCompacting ? _tr('Compattazione...', 'Compacting...') : _tr('Compatta contesto', 'Compact context'),
                  ),
                  onPressed: _isCompacting || readOnly
                      ? null
                      : _triggerCompaction,
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: tokens.textSecondary,
                    side: BorderSide(color: tokens.border),
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                    ),
                  ),
                  icon: Icon(
                    Icons.content_copy,
                    size: 15,
                    color: tokens.textSecondary,
                  ),
                  label: Text(_tr('Duplica Ramo (Clone)', 'Clone branch')),
                  onPressed: _cloneSession,
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: tokens.textSecondary,
                    side: BorderSide(color: tokens.border),
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                    ),
                  ),
                  icon: Icon(
                    Icons.account_tree_outlined,
                    size: 15,
                    color: tokens.textSecondary,
                  ),
                  label: Text(_tr('Albero dei Rami (Tree)', 'Branch tree')),
                  onPressed: () => SessionTreeDialog.show(
                    context,
                    sessionId: widget.sessionId,
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
