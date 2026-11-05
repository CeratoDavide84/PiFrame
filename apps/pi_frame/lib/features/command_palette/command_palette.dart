import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../data/language/language_settings.dart';
import '../../ui/frame_snack_bar.dart';
import '../sessions_sidebar/session_actions.dart';
import '../browser/browser_models.dart';
import '../browser/browser_controller.dart';

class PaletteAction {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Future<void> Function() onExecute;

  const PaletteAction({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onExecute,
  });
}

class CommandPalette extends ConsumerStatefulWidget {
  final VoidCallback? onOpenSettings;

  const CommandPalette({super.key, this.onOpenSettings});

  static Future<void> show(
    BuildContext context, {
    VoidCallback? onOpenSettings,
  }) {
    return showDialog(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      barrierColor: context.tokens.overlay,
      builder: (_) => CommandPalette(onOpenSettings: onOpenSettings),
    );
  }

  @override
  ConsumerState<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends ConsumerState<CommandPalette> {
  String _tr(String it, String en) =>
      ref.read(appLanguageProvider) == AppLanguage.it ? it : en;
  final _searchController = TextEditingController();
  int _selectedIndex = 0;
  bool _executing = false;
  final _scrollController = ScrollController();

  void _move(int delta, int count) {
    if (count == 0) return;
    setState(
      () => _selectedIndex = (_selectedIndex + delta).clamp(0, count - 1),
    );
    if (_scrollController.hasClients) {
      final offset = (_selectedIndex * 72.0).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.jumpTo(offset);
    }
  }

  Future<void> _execute(PaletteAction action) async {
    if (_executing) return;
    setState(() => _executing = true);
    try {
      await action.onExecute();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        FrameSnackBar.show(context, message: _tr('Azione non riuscita: $error', 'Action failed: $error'));
      }
    } finally {
      if (mounted) setState(() => _executing = false);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<PaletteAction> _buildActions(BuildContext context) {
    final activeSessionId = ref.read(activeSessionIdProvider);
    final pcpClient = ref.read(pcpClientProvider);

    return [
      PaletteAction(
        id: 'new_session',
        title: _tr('Crea nuova sessione', 'Create new session'),
        subtitle: _tr('Avvia una nuova sessione Pi', 'Start a new Pi session'),
        icon: Icons.add_circle_outline,
        onExecute: () async {
          if (pcpClient == null) return;
          await createSession(context, ref, name: _tr('Nuova Sessione', 'New session'));
          if (!mounted || !context.mounted) return;
          ref.invalidate(sessionListProvider);
        },
      ),
      if (activeSessionId != null &&
          !ref.watch(sessionStateFamily(activeSessionId)).readOnly) ...[
        PaletteAction(
          id: 'compact',
          title: _tr('Compatta contesto', 'Compact context'),
          subtitle: _tr('Esegui manual compaction per ridurre i token', 'Run manual compaction to reduce tokens'),
          icon: Icons.compress,
          onExecute: () async {
            await ref
                .read(sessionStateFamily(activeSessionId).notifier)
                .compact();
          },
        ),
        PaletteAction(
          id: 'clear_queue',
          title: _tr('Svuota coda', 'Clear queue'),
          subtitle: _tr('Rimuovi tutti i messaggi steer e follow-up in attesa', 'Remove all pending steer and follow-up messages'),
          icon: Icons.clear_all,
          onExecute: () async {
            await ref
                .read(sessionStateFamily(activeSessionId).notifier)
                .clearQueue();
          },
        ),
        PaletteAction(
          id: 'interrupt',
          title: _tr('Interrompi agente (Esc)', 'Stop agent (Esc)'),
          subtitle: _tr('Ferma il modello in esecuzione', 'Stop the running model'),
          icon: Icons.stop_circle_outlined,
          onExecute: () async {
            await ref
                .read(sessionStateFamily(activeSessionId).notifier)
                .interrupt();
          },
        ),
      ],
      if (ref.watch(browserPaneSupportedProvider)) ...[
        PaletteAction(
          id: 'switch_to_browser',
          title: _tr('Mostra Web Browser', 'Show web browser'),
          subtitle: _tr('Apri il browser web integrato nel pannello laterale', 'Open the integrated web browser in the side panel'),
          icon: Icons.language_outlined,
          onExecute: () async {
            ref.read(rightPaneModeProvider.notifier).state =
                RightPaneMode.browser;
          },
        ),
        PaletteAction(
          id: 'switch_to_git',
          title: _tr('Mostra Modifiche Git', 'Show Git changes'),
          subtitle: _tr('Mostra il pannello delle modifiche Git nel pannello laterale', 'Show Git changes in the side panel'),
          icon: Icons.source_outlined,
          onExecute: () async {
            ref.read(rightPaneModeProvider.notifier).state = RightPaneMode.git;
          },
        ),
      ],
      PaletteAction(
        id: 'settings',
        title: _tr('Apri Impostazioni', 'Open settings'),
        subtitle: _tr('Configura percorso Pi, timeout worker e aspetto', 'Configure Pi path, worker timeouts and appearance'),
        icon: Icons.settings,
        onExecute: () async {
          widget.onOpenSettings?.call();
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appLanguageProvider);
    final tokens = context.tokens;
    final allActions = _buildActions(context);
    final query = _searchController.text.trim().toLowerCase();

    final filtered = allActions.where((a) {
      return a.title.toLowerCase().contains(query) ||
          a.subtitle.toLowerCase().contains(query);
    }).toList();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _move(1, filtered.length),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _move(-1, filtered.length),
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (filtered.isNotEmpty) _execute(filtered[_selectedIndex]);
        },
      },
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540, maxHeight: 420),
          child: Material(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(tokens.radiusLg),
            clipBehavior: Clip.antiAlias,
            elevation: 0,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(tokens.radiusLg),
                border: Border.all(color: tokens.border),
              ),
              child: Column(
                children: [
                  // Search Input Header
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search, size: 20, color: tokens.textMuted),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            autofocus: true,
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: 15,
                            ),
                            decoration: InputDecoration(
                              hintText: _tr('Cerca un\'azione o comando...', 'Search for an action or command...'),
                              hintStyle: TextStyle(
                                color: tokens.textMuted,
                                fontSize: 14,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                            onChanged: (_) =>
                                setState(() => _selectedIndex = 0),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.surface,
                            borderRadius: BorderRadius.circular(
                              tokens.radiusSm,
                            ),
                            border: Border.all(color: tokens.border),
                          ),
                          child: Text(
                            'ESC',
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: 10,
                              fontFamily: tokens.monoFontFamily,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: tokens.border),

                  // Results list
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              _tr('Nessuna azione trovata', 'No actions found'),
                              style: TextStyle(
                                color: tokens.textMuted,
                                fontSize: 13,
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final action = filtered[index];
                              final isSelected = index == _selectedIndex;

                              return InkWell(
                                onTap: _executing
                                    ? null
                                    : () => _execute(action),
                                hoverColor: tokens.surface,
                                child: Container(
                                  color: isSelected
                                      ? tokens.accent.withValues(alpha: 0.1)
                                      : null,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        action.icon,
                                        size: 18,
                                        color: isSelected
                                            ? tokens.accent
                                            : tokens.textSecondary,
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              action.title,
                                              style: TextStyle(
                                                color: tokens.textPrimary,
                                                fontSize: 13,
                                                fontWeight: isSelected
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                              ),
                                            ),
                                            Text(
                                              action.subtitle,
                                              style: TextStyle(
                                                color: tokens.textMuted,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
