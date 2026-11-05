import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/language/language_settings.dart';
import '../../data/daemon/daemon_providers.dart';
import '../../domain/session/context_pricing_helper.dart';
import '../../domain/session/agent_status.dart';
import '../../ui/frame_snack_bar.dart';

final customContextModeProvider = StateProvider.family<bool?, String>(
  (ref, id) => null,
);
final contextPolicySavingProvider = StateProvider.family<bool, String>(
  (ref, id) => false,
);

class ContextWindowSelector extends ConsumerStatefulWidget {
  final String sessionId;
  final Map<String, dynamic> model;
  final bool readOnly;

  const ContextWindowSelector({
    super.key,
    required this.sessionId,
    required this.model,
    this.readOnly = false,
  });

  @override
  ConsumerState<ContextWindowSelector> createState() =>
      _ContextWindowSelectorState();
}

class _ContextWindowSelectorState extends ConsumerState<ContextWindowSelector> {
  static const _custom = 'custom';
  static const _step = 50000;
  bool _pending = false;
  double? _draft;
  int _generation = 0;

  String _tr(String it, String en) =>
      ref.read(appLanguageProvider) == AppLanguage.it ? it : en;

  @override
  void didUpdateWidget(covariant ContextWindowSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId ||
        oldWidget.model['provider'] != widget.model['provider'] ||
        oldWidget.model['id'] != widget.model['id']) {
      _generation++;
      _draft = null;
      _pending = false;
    }
  }

  Future<void> _save(int limit, {required bool custom}) async {
    if (_pending || ref.read(contextPolicySavingProvider(widget.sessionId))) {
      return;
    }
    final sessionId = widget.sessionId;
    final generation = _generation;
    final saving = ref.read(contextPolicySavingProvider(sessionId).notifier);
    final mode = ref.read(customContextModeProvider(sessionId).notifier);
    saving.state = true;
    setState(() => _pending = true);
    try {
      await ref
          .read(sessionStateFamily(sessionId).notifier)
          .setContextWindow(limit);
      if (mode.mounted && generation == _generation) mode.state = custom;
      if (generation == _generation) _draft = null;
    } catch (error) {
      if (generation == _generation) _draft = null;
      if (mounted && generation == _generation) {
        FrameSnackBar.show(context, message: 'Limite non applicato: $error');
      }
    } finally {
      if (saving.mounted) saving.state = false;
      if (mounted && generation == _generation) {
        setState(() => _pending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appLanguageProvider);
    final tokens = context.tokens;
    ref.listen<String?>(
      sessionStateFamily(widget.sessionId).select((s) => s.currentModel),
      (previous, next) {
        if (previous != next) {
          ref.read(customContextModeProvider(widget.sessionId).notifier).state =
              null;
        }
      },
    );
    final session = ref.watch(sessionStateFamily(widget.sessionId));
    final maximum = modelContextWindow(widget.model);
    final presets = getVariableContextSizes(widget.model);
    final override = session.contextWindowOverride;
    final explicitCustom = ref.watch(
      customContextModeProvider(widget.sessionId),
    );
    final isCustom =
        explicitCustom == true ||
        (override != null && !presets.contains(override));
    final activeSize = override ?? maximum;
    final sliderMaximum = maximum == null
        ? 0
        : (maximum < 100000
              ? 0
              : (maximum ~/ _step * _step).clamp(100000, 1000000));
    final sliderEnabled = sliderMaximum >= 100000;
    final disabled =
        widget.readOnly ||
        session.readOnly ||
        session.isStreaming ||
        const {
          AgentStatus.retrying,
          AgentStatus.compacting,
          AgentStatus.awaitingUser,
        }.contains(session.agentStatus) ||
        _pending ||
        ref.watch(contextPolicySavingProvider(widget.sessionId)) ||
        maximum == null ||
        maximum <= 0;
    final selected = maximum == null
        ? null
        : isCustom
        ? _custom
        : presets.contains(activeSize)
        ? activeSize
        : null;
    final sliderValue =
        _draft ??
        (activeSize ?? 100000)
            .clamp(100000, sliderMaximum < 100000 ? 100000 : sliderMaximum)
            .toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: tokens.surfaceElevated,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            border: Border.all(color: tokens.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<Object>(
              key: const ValueKey('context-window-preset-dropdown'),
              isExpanded: true,
              value: selected,
              hint: Text(
                maximum == null
                    ? _tr('Massimo non disponibile', 'Maximum unavailable')
                    : _tr('Seleziona limite', 'Select limit'),
                style: TextStyle(color: tokens.textMuted, fontSize: 12),
              ),
              borderRadius: BorderRadius.circular(tokens.radiusMd),
              dropdownColor: tokens.surfaceElevated,
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: 13,
                fontFamily: tokens.uiFontFamily,
              ),
              items: [
                DropdownMenuItem<Object>(
                  value: _custom,
                  enabled: sliderEnabled,
                  child: Text(_tr('Personalizzato', 'Custom')),
                ),
                ...presets.map(
                  (size) => DropdownMenuItem<Object>(
                    value: size,
                    child: Text(
                      maximum == null
                          ? formatTokens(size)
                          : hasVariableContextPricing(widget.model)
                          ? formatContextSize(size, maximum)
                          : '${formatTokens(size)} (Max)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: disabled
                  ? null
                  : (value) async {
                      if (value == _custom) {
                        if (!sliderEnabled) return;
                        final current = activeSize ?? 100000;
                        final snapped = ((current / _step).round() * _step)
                            .clamp(100000, sliderMaximum);
                        await _save(snapped, custom: true);
                      } else if (value is int) {
                        await _save(value, custom: false);
                      }
                    },
            ),
          ),
        ),
        if (isCustom && sliderEnabled) ...[
          const SizedBox(height: 6),
          Text(
            'Finestra massima di contesto',
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${formatTokens(sliderValue.round())} token (${sliderValue.round()} token esatti)',
            style: TextStyle(color: tokens.textSecondary, fontSize: 11),
          ),
          Slider(
            key: const ValueKey('context-window-custom-slider'),
            activeColor: tokens.accent,
            thumbColor: tokens.accent,
            inactiveColor: tokens.border,
            min: 100000,
            max: sliderMaximum.toDouble(),
            divisions: sliderMaximum > 100000
                ? (sliderMaximum - 100000) ~/ _step
                : null,
            value: sliderValue,
            label: '${sliderValue.round()} token',
            semanticFormatterCallback: (value) => '${value.round()} token',
            onChanged: disabled || sliderMaximum == 100000
                ? null
                : (value) => setState(() => _draft = value),
            onChangeEnd: disabled || sliderMaximum == 100000
                ? null
                : (value) => _save(value.round(), custom: true),
          ),
          Text(
            '100k–${formatTokens(sliderMaximum)} · Passo 50k',
            style: TextStyle(color: tokens.textMuted, fontSize: 10),
          ),
        ],
      ],
    );
  }
}
