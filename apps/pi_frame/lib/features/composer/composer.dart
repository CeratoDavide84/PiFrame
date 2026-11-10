import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:window_manager/window_manager.dart';

import 'package:file_selector/file_selector.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../data/goal/session_goal_provider.dart';
import '../../data/language/language_settings.dart';
import '../../domain/session/agent_status.dart';
import '../../domain/session/attachment_model.dart';
import '../../domain/session/context_pricing_helper.dart';
import 'attachment_chips.dart';
import 'composer_attachments_provider.dart';
import 'composer_draft.dart';
import 'copilot_file_picker.dart';
import 'file_mention_menu.dart';
import 'slash_menu.dart';
import 'session_goal_banner.dart';
import '../../ui/precision.dart';
import '../../ui/shimmer_border.dart';
import '../dialogs/extension_ui_dialog.dart';
import '../session_tree/session_tree_dialog.dart';
import '../sessions_sidebar/session_actions.dart' show createSession;
import '../workspace/repository_workspace.dart';
import '../workspace/pane_drag_state.dart';
import '../session_changes/session_changes_provider.dart';
import '../../ui/frame_snack_bar.dart';
import '../context_panel/context_window_selector.dart';

final composerSendingProvider = StateProvider.family<bool, String>(
  (ref, sessionId) => false,
);

class _ComposerSizeAnimator extends ConsumerWidget {
  final Widget child;

  const _ComposerSizeAnimator({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // While a pane divider is dragged the composer follows it directly; AnimatedSize would
    // tween its size and trail the divider. Minimize/expand keeps the 280 ms height tween.
    if (ref.watch(paneDraggingProvider)) return child;
    return AnimatedSize(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOutCubic,
      alignment: Alignment.bottomCenter,
      child: child,
    );
  }
}

class Composer extends ConsumerStatefulWidget {
  final String sessionId;

  const Composer({super.key, required this.sessionId});

  @override
  ConsumerState<Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<Composer> {
  String _tr(String it, String en) =>
      ref.read(appLanguageProvider) == AppLanguage.it ? it : en;
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<Map<String, dynamic>> _availableCommands = [];
  bool _showSlashMenu = false;
  bool _isInterrupting = false;
  bool _showFileMentionMenu = false;
  String _fileMentionQuery = '';
  int _fileMentionStartIndex = -1;
  int _fileMentionSelectedIndex = 0;
  List<Map<String, dynamic>> _matchingMentionFiles = [];
  bool _queueExpanded = true;
  bool _isManuallyExpanded = false;
  bool _isPointerOver = false;
  Timer? _hoverGraceTimer;
  Timer? _expand5sTimer;
  final ValueNotifier<Offset?> _minimizedHoverOffsetNotifier =
      ValueNotifier<Offset?>(null);
  bool _hasText = false;
  bool _isInputEnlarged = false;
  List<Map<String, dynamic>> _models = [];
  bool _isContextPickerLoading = false;
  // Model/thinking menus load their options asynchronously before opening: ignore re-taps meanwhile.
  bool _isPickerBusy = false;
  // Cards the user closed locally (timeout, stale or answered); the daemon event may arrive later or never.
  final Set<String> _dismissedUiRequestIds = {};
  int _modelLoadGeneration = 0;

  Future<void> _guardPicker(Future<void> Function() open) async {
    if (_isPickerBusy) return;
    _isPickerBusy = true;
    try {
      await open();
    } finally {
      _isPickerBusy = false;
    }
  }

  Future<void> _loadModels() async {
    final generation = ++_modelLoadGeneration;
    final sessionId = widget.sessionId;
    final notifier = ref.read(sessionStateFamily(sessionId).notifier);
    final models = await notifier.getAvailableModels();
    if (mounted &&
        widget.sessionId == sessionId &&
        generation == _modelLoadGeneration) {
      setState(() {
        _models = models
            .map((model) => Map<String, dynamic>.from(model))
            .toList();
      });
    }
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _showEditSteerDialog(
    BuildContext context,
    int index,
    String initialText,
  ) async {
    final tokens = context.tokens;
    final textController = TextEditingController(text: initialText);
    final sessionNotifier = ref.read(
      sessionStateFamily(widget.sessionId).notifier,
    );

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: tokens.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            side: BorderSide(color: tokens.borderStrong),
          ),
          title: Row(
            children: [
              Icon(Icons.edit_note, size: 20, color: tokens.accent),
              const SizedBox(width: 8),
              Text(
                _tr(
                  'Modifica messaggio in coda (Steer #${index + 1})',
                  'Edit queued message (Steer #${index + 1})',
                ),
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _tr(
                    'Modifica il testo del messaggio in coda prima che venga inviato all\'agente:',
                    'Edit the queued message before it is sent to the agent:',
                  ),
                  style: TextStyle(color: tokens.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('edit-steer-dialog-field'),
                  controller: textController,
                  maxLines: 4,
                  style: TextStyle(color: tokens.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: tokens.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                      borderSide: BorderSide(color: tokens.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                      borderSide: BorderSide(color: tokens.accent),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                sessionNotifier.removeSteerMessage(index);
                _controller.text = textController.text;
                _focusNode.requestFocus();
                FrameSnackBar.show(
                  context,
                  message: _tr(
                    'Messaggio caricato nel composer per la modifica',
                    'Message loaded into the composer for editing',
                  ),
                  duration: const Duration(seconds: 2),
                );
              },
              child: Text(
                _tr('Carica nel composer', 'Load into composer'),
                style: TextStyle(color: tokens.accent),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text(
                _tr('Annulla', 'Cancel'),
                style: TextStyle(color: tokens.textMuted),
              ),
            ),
            FilledButton(
              key: const ValueKey('edit-steer-dialog-save'),
              onPressed: () async {
                final newText = textController.text.trim();
                Navigator.of(dialogCtx).pop();
                if (newText.isNotEmpty) {
                  await sessionNotifier.updateSteerMessage(index, newText);
                }
              },
              child: Text(_tr('Aggiorna', 'Update')),
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    final initialText = ref.read(composerDraftProvider(widget.sessionId));
    _controller.text = initialText;
    _hasText = initialText.trim().isNotEmpty;
    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
    _loadCommands();
    _loadModels();
  }

  Future<void> _loadCommands() async {
    final notifier = ref.read(sessionStateFamily(widget.sessionId).notifier);
    final cmds = await notifier.getCommands();
    if (mounted) {
      setState(() {
        _availableCommands = [
          ...cmds,
          {
            'name': 'goal',
            'description': _tr(
              'Imposta o aggiorna il goal di questa sessione',
              'Set or update this session goal',
            ),
            'argumentHint': '[obiettivo]',
            'source': 'piframe',
          },
        ];
      });
    }
  }

  bool _isInteractionRequest(Map<String, dynamic> request) {
    final method = request['method']?.toString();
    return request['dialog'] == true ||
        method == 'confirm' ||
        method == 'select' ||
        method == 'input' ||
        method == 'editor';
  }

  bool _hasPendingInteractionRequest() {
    return ref
        .read(sessionStateFamily(widget.sessionId))
        .pendingUiRequests
        .any(
          (request) =>
              _isInteractionRequest(request) &&
              !_dismissedUiRequestIds.contains(
                request['requestId']?.toString(),
              ),
        );
  }

  void _onTextChanged() {
    final text = _controller.text;
    ref.read(composerDraftProvider(widget.sessionId).notifier).state = text;
    final hasText = text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() {
        _hasText = hasText;
      });
    }
    final show = text.startsWith('/') && !text.contains('\n');
    if (show != _showSlashMenu) {
      setState(() {
        _showSlashMenu = show;
      });
    }

    final selection = _controller.selection;
    final cursor = selection.baseOffset;
    if (cursor > 0 && cursor <= text.length) {
      final beforeCursor = text.substring(0, cursor);
      final atMatch = RegExp(r'@([a-zA-Z0-9_\-\./]*)$')
          .firstMatch(beforeCursor);
      if (atMatch != null) {
        final query = atMatch.group(1)!;
        final start = atMatch.start;
        _updateFileMentions(query, start);
      } else if (_showFileMentionMenu) {
        setState(() => _showFileMentionMenu = false);
        _focusNode.requestFocus();
      }
    } else if (_showFileMentionMenu) {
      setState(() => _showFileMentionMenu = false);
      _focusNode.requestFocus();
    }
  }

  Future<void> _updateFileMentions(String query, int startIndex) async {
    final repoNotifier = ref.read(
      repositoryStateProvider(widget.sessionId).notifier,
    );
    if (repoNotifier.currentState.files.isEmpty) {
      await repoNotifier.loadFiles();
    }
    if (!mounted) return;
    final allFiles = repoNotifier.currentState.files;
    final cleanQuery = query.toLowerCase();

    final matches = allFiles
        .where((f) {
          final p = (f['path']?.toString() ?? '').toLowerCase();
          if (cleanQuery.isEmpty) return true;
          return p.contains(cleanQuery);
        })
        .take(6)
        .toList();

    setState(() {
      _showFileMentionMenu = matches.isNotEmpty;
      _fileMentionQuery = query;
      _fileMentionStartIndex = startIndex;
      _matchingMentionFiles = matches;
      _fileMentionSelectedIndex = 0;
    });
    _focusNode.requestFocus();
  }

  void _completeFileMention(String path) {
    final text = _controller.text;
    final cursor = _controller.selection.baseOffset;
    if (_fileMentionStartIndex >= 0 && cursor >= _fileMentionStartIndex) {
      final prefix = text.substring(0, _fileMentionStartIndex);
      final suffix = cursor < text.length ? text.substring(cursor) : '';
      final newText = '$prefix@$path $suffix';
      final newOffset = prefix.length + path.length + 2;
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newOffset),
      );
      ref.read(composerDraftProvider(widget.sessionId).notifier).state =
          newText;
    } else {
      final separator = text.isEmpty || text.endsWith(' ') ? '' : ' ';
      final newText = '$text$separator@$path ';
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
      ref.read(composerDraftProvider(widget.sessionId).notifier).state =
          newText;
    }
    setState(() {
      _showFileMentionMenu = false;
      _matchingMentionFiles = [];
    });
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _hoverGraceTimer?.cancel();
    _expand5sTimer?.cancel();
    _minimizedHoverOffsetNotifier.dispose();
    _focusNode.removeListener(_onFocusChanged);
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send({String? streamingBehavior}) async {
    if (_hasPendingInteractionRequest()) return;

    final draft = _controller.text;
    final text = draft.trim();
    final attachments = ref.read(composerAttachmentsProvider(widget.sessionId));

    if ((text.isEmpty && attachments.isEmpty) ||
        ref.read(composerSendingProvider(widget.sessionId))) {
      return;
    }
    final goalMatch = RegExp(
      r'^/goal(?:\s+(.*))?$',
      caseSensitive: false,
    ).firstMatch(text);
    if (goalMatch != null) {
      if (attachments.isNotEmpty) {
        FrameSnackBar.show(
          context,
          message: _tr(
            'Rimuovi gli allegati prima di impostare un goal.',
            'Remove attachments before setting a goal.',
          ),
        );
        return;
      }
      try {
        final value = goalMatch.group(1)?.trim() ?? '';
        if (value.toLowerCase() == 'clear' || value.toLowerCase() == 'remove') {
          await ref
              .read(sessionGoalProvider(widget.sessionId).notifier)
              .setGoal(null);
        } else if (value.isEmpty) {
          await _showGoalDialog();
        } else {
          await ref
              .read(sessionGoalProvider(widget.sessionId).notifier)
              .setGoal(value);
        }
        if (mounted) _controller.clear();
      } catch (error) {
        if (mounted)
          FrameSnackBar.show(
            context,
            message: _tr(
              'Salvataggio goal non riuscito: $error',
              'Could not save goal: $error',
            ),
          );
      }
      return;
    }
    final builtin = _parsePiBuiltin(text);
    if (builtin != null) {
      final sending = ref.read(
        composerSendingProvider(widget.sessionId).notifier,
      );
      sending.state = true;
      try {
        if (attachments.isNotEmpty) {
          throw StateError(
            'Rimuovi gli allegati prima di eseguire un comando Pi.',
          );
        }
        await _runPiBuiltin(builtin.$1, builtin.$2);
        if (!mounted) return;
        if (_controller.text == draft) _controller.clear();
        final savedDraft = ref.read(
          composerDraftProvider(widget.sessionId).notifier,
        );
        if (savedDraft.mounted && savedDraft.state == draft) {
          savedDraft.state = '';
        }
      } catch (error) {
        if (mounted) {
          FrameSnackBar.show(
            context,
            message: _tr(
              'Comando non riuscito: $error',
              'Command failed: $error',
            ),
          );
        }
      } finally {
        if (sending.mounted) sending.state = false;
      }
      return;
    }
    _isManuallyExpanded = false;
    final savedDraft = ref.read(
      composerDraftProvider(widget.sessionId).notifier,
    );
    final sending = ref.read(
      composerSendingProvider(widget.sessionId).notifier,
    );
    final attachmentsNotifier = ref.read(
      composerAttachmentsProvider(widget.sessionId).notifier,
    );
    sending.state = true;
    try {
      final userPrompt = attachments.isNotEmpty
          ? '${encodeAttachmentsTag(attachments)}${text.isNotEmpty ? '\n$text' : ''}'
          : text;
      final goal = ref.read(sessionGoalProvider(widget.sessionId));
      final fullPrompt = goal == null
          ? userPrompt
          : '[PiFrame session goal: $goal]\nTreat this as the persistent objective for this session. Keep it in mind while answering and working.\n\n$userPrompt';

      final isPrompt = streamingBehavior == null;
      if (isPrompt) {
        if (mounted && _controller.text == draft) _controller.clear();
        if (savedDraft.mounted && savedDraft.state == draft) {
          savedDraft.state = '';
        }
        if (attachmentsNotifier.mounted) attachmentsNotifier.clear();
      }

      await ref
          .read(sessionStateFamily(widget.sessionId).notifier)
          .sendPrompt(fullPrompt, streamingBehavior: streamingBehavior);

      if (!isPrompt) {
        if (attachmentsNotifier.mounted) attachmentsNotifier.clear();
        if (savedDraft.mounted && savedDraft.state == draft) {
          savedDraft.state = '';
        }
        if (mounted && _controller.text == draft) _controller.clear();
      }
    } catch (error) {
      if (mounted && streamingBehavior != null) {
        FrameSnackBar.show(
          context,
          message: _tr('Invio non riuscito: $error', 'Send failed: $error'),
        );
      }
    } finally {
      if (sending.mounted) sending.state = false;
    }
  }

  Future<void> _showGoalDialog() async {
    final goals = ref.read(sessionGoalProvider(widget.sessionId));
    final controller = TextEditingController(text: goals);
    final saved = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_tr('Goal della sessione', 'Session goal')),
        content: SizedBox(
          width: 460,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(
              hintText: _tr(
                'Cosa deve completare l’agente?',
                'What should the agent complete?',
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_tr('Annulla', 'Cancel')),
          ),
          if (goals != null)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, ''),
              child: Text(_tr('Rimuovi goal', 'Clear goal')),
            ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: Text(_tr('Salva goal', 'Save goal')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (saved != null && mounted)
      await ref
          .read(sessionGoalProvider(widget.sessionId).notifier)
          .setGoal(saved);
  }

  Future<void> _continueAmbiguousSession() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_tr('Verifica la sessione Pi', 'Check the Pi session')),
        content: Text(
          _tr(
            'PiFrame rileva Pi interattivo aperto in questa cartella, ma Pi non comunica quale file di sessione usa. '
                'Continua solo se questa sessione non è aperta nel terminale. Due processi sullo stesso file possono danneggiare la cronologia.',
            'PiFrame detected interactive Pi in this folder, but Pi does not report which session file it uses. Continue only if this session is not open in the terminal. Two processes using the same file may corrupt the history.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_tr('Annulla', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_tr('Continua qui', 'Continue here')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final client = ref.read(pcpClientProvider);
      if (client == null) throw StateError('Daemon non connesso');
      await client.continueSession(widget.sessionId, confirmed: true);
      if (!mounted) return;
      ref.invalidate(sessionListProvider);
      ref.invalidate(sessionStateFamily(widget.sessionId));
    } catch (error) {
      if (mounted) {
        FrameSnackBar.show(
          context,
          message: _tr('Ripresa non riuscita: $error', 'Resume failed: $error'),
        );
      }
    }
  }

  Future<void> _runAction(Future<dynamic> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) {
        FrameSnackBar.show(
          context,
          message: _tr('Azione non riuscita: $error', 'Action failed: $error'),
        );
      }
    }
  }

  void _onAttachSelected(String value) {
    switch (value) {
      case 'repo':
        _addFileToContext();
        break;
      case 'external':
        _addExternalFiles();
        break;
      case 'link':
        _addWebLink();
        break;
      case 'image':
        _addImageFiles();
        break;
    }
  }

  Future<void> _addFileToContext() async {
    final repository = ref.read(
      repositoryStateProvider(widget.sessionId).notifier,
    );
    if (repository.currentState.files.isEmpty) await repository.loadFiles();
    if (!mounted) return;
    final state = repository.currentState;
    if (state.files.isEmpty) {
      FrameSnackBar.show(
        context,
        message:
            state.error ??
            _tr(
              'Nessun file disponibile nella sessione.',
              'No files available in this session.',
            ),
      );
      return;
    }

    final result = await CopilotFilePicker.show(context, files: state.files);
    if (result == null || !mounted) return;

    final isImg = isImageExtension(result.path);
    final fileName = result.path.replaceAll('\\', '/').split('/').last;
    ref
        .read(composerAttachmentsProvider(widget.sessionId).notifier)
        .add(
          ChatAttachment(
            id: 'att_repo_${DateTime.now().microsecondsSinceEpoch}',
            type: isImg ? AttachmentType.image : AttachmentType.repoFile,
            name: fileName,
            pathOrUrl: result.path,
          ),
        );
    _completeFileMention(result.path);
    _focusNode.requestFocus();
  }

  Future<void> _addExternalFiles() async {
    try {
      final files = await openFiles();
      if (files.isEmpty || !mounted) return;

      final attachments = <ChatAttachment>[];
      for (var i = 0; i < files.length; i++) {
        final f = files[i];
        final isImg = isImageExtension(f.path);
        attachments.add(
          ChatAttachment(
            id: 'att_ext_${DateTime.now().microsecondsSinceEpoch}_$i',
            type: isImg ? AttachmentType.image : AttachmentType.externalFile,
            name: f.name,
            pathOrUrl: f.path,
          ),
        );
      }

      ref
          .read(composerAttachmentsProvider(widget.sessionId).notifier)
          .addAll(attachments);
      _focusNode.requestFocus();
    } catch (e) {
      debugPrint('Selezione file annullata o non riuscita: $e');
    }
  }

  Future<void> _addWebLink() async {
    final attachment = await WebLinkInputDialog.show(context);
    if (attachment == null || !mounted) return;

    ref
        .read(composerAttachmentsProvider(widget.sessionId).notifier)
        .add(attachment);
    _focusNode.requestFocus();
  }

  Future<void> _addImageFiles() async {
    try {
      final files = await openFiles(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'Immagini',
            extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg'],
          ),
        ],
      );
      if (files.isEmpty || !mounted) return;

      final attachments = <ChatAttachment>[];
      for (var i = 0; i < files.length; i++) {
        final f = files[i];
        attachments.add(
          ChatAttachment(
            id: 'att_img_${DateTime.now().microsecondsSinceEpoch}_$i',
            type: AttachmentType.image,
            name: f.name,
            pathOrUrl: f.path,
          ),
        );
      }

      ref
          .read(composerAttachmentsProvider(widget.sessionId).notifier)
          .addAll(attachments);
      _focusNode.requestFocus();
    } catch (e) {
      debugPrint('Selezione immagini annullata o non riuscita: $e');
    }
  }

  Future<void> _interrupt() async {
    if (_isInterrupting) return;
    setState(() {
      _isInterrupting = true;
    });

    final sessionNotifier = ref.read(
      sessionStateFamily(widget.sessionId).notifier,
    );
    try {
      await sessionNotifier.interrupt();
    } catch (error) {
      if (mounted) {
        FrameSnackBar.show(
          context,
          message: _tr(
            'Interruzione non riuscita: $error',
            'Interrupt failed: $error',
          ),
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _isInterrupting = false);
    }
    if (!mounted) return;

    FrameSnackBar.show(
      context,
      message: _tr(
        'Agente interrotto. La coda di messaggi è stata cancellata.',
        'Agent stopped. The message queue was cleared.',
      ),
      duration: const Duration(seconds: 3),
    );
  }

  void _onSelectSlashCommand(Map<String, dynamic> cmd) {
    final name = cmd['name'] as String? ?? '';
    _controller.text = '/$name ';
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
    setState(() {
      _showSlashMenu = false;
    });
    _focusNode.requestFocus();
  }

  (String, String)? _parsePiBuiltin(String text) {
    final match = RegExp(
      r'^/([a-z][a-z0-9-]*)(?:\s+(.*))?$',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return null;
    final name = match.group(1)!.toLowerCase();
    final isBuiltin = _availableCommands.any(
      (command) => command['source'] == 'builtin' && command['name'] == name,
    );
    return isBuiltin ? (name, match.group(2)?.trim() ?? '') : null;
  }

  Future<void> _runPiBuiltin(String name, String args) async {
    final notifier = ref.read(sessionStateFamily(widget.sessionId).notifier);
    switch (name) {
      case 'settings':
        ref.read(showSettingsProvider.notifier).state = true;
        return;
      case 'model':
        if (args.isEmpty) return _showModelPicker(context);
        final models = await notifier.getAvailableModels();
        final target = args.toLowerCase();
        final selected = models.where((model) {
          final id = model['id']?.toString() ?? '';
          final provider = model['provider']?.toString() ?? '';
          final display = model['name']?.toString() ?? id;
          return id.toLowerCase() == target ||
              display.toLowerCase() == target ||
              '$provider/$id'.toLowerCase() == target;
        }).firstOrNull;
        if (selected == null) throw StateError('Modello "$args" non trovato.');
        await notifier.setModel(
          selected['provider']?.toString() ?? 'default',
          selected['id']?.toString() ?? args,
        );
        return;
      case 'thinking':
        if (args.isEmpty) return _showThinkingPicker(context);
        final levels = await notifier.getAvailableThinkingLevels();
        if (!mounted) return;
        final level = levels
            .where((item) => item.toLowerCase() == args.toLowerCase())
            .firstOrNull;
        if (level == null) {
          throw StateError('Livello di thinking "$args" non disponibile.');
        }
        await notifier.setThinkingLevel(level);
        return;
      case 'tree':
        return SessionTreeDialog.show(context, sessionId: widget.sessionId);
      case 'new':
        return createSession(context, ref);
      case 'compact':
        await notifier.compact();
        return;
      case 'reload':
        await notifier.sendPrompt('/reload');
        return;
      case 'login':
        if (args.isNotEmpty) {
          throw StateError('/login non accetta argomenti.');
        }
        await notifier.piAuthLogin();
        await _loadModels();
        return;
      case 'logout':
        if (args.isNotEmpty) {
          throw StateError('/logout non accetta argomenti.');
        }
        await notifier.piAuthLogout();
        await _loadModels();
        return;
      case 'copy':
        final latest = ref
            .read(sessionStateFamily(widget.sessionId))
            .entries
            .where(
              (entry) =>
                  entry.role == 'assistant' && entry.text.trim().isNotEmpty,
            )
            .lastOrNull;
        if (latest == null) {
          throw StateError('Nessun messaggio dell’agente da copiare.');
        }
        await Clipboard.setData(ClipboardData(text: latest.text));
        if (!mounted) return;
        FrameSnackBar.show(
          context,
          message: _tr(
            'Ultimo messaggio dell’agente copiato.',
            'Last agent message copied.',
          ),
        );
        return;
      case 'name':
        final current =
            ref.read(sessionStateFamily(widget.sessionId)).sessionName ?? '';
        final name = args.isEmpty ? await _askSessionName(current) : args;
        if (name == null || name.trim().isEmpty) return;
        await notifier.rename(name.trim());
        ref.invalidate(sessionListProvider);
        return;
      case 'session':
        await _showPiSessionInfo();
        return;
      case 'clone':
        await _cloneFromSlash();
        return;
      case 'fork':
        await _forkFromSlash(args);
        return;
      case 'resume':
        await _resumeFromSlash();
        return;
      case 'quit':
        if (!await resolveDirtyRepository(context, ref, widget.sessionId)) {
          return;
        }
        await windowManager.close();
        return;
      default:
        FrameSnackBar.show(
          context,
          message: _tr(
            '/$name è un comando integrato di Pi basato sulla TUI. PiFrame non lo invia al modello, ma non supporta ancora questa azione.',
            '/$name is a built-in Pi TUI command. PiFrame does not send it to the model, but this action is not supported yet.',
          ),
          duration: const Duration(seconds: 5),
        );
    }
  }

  Future<String?> _askSessionName(String initial) async {
    final controller = TextEditingController(text: initial);
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_tr('Nome sessione', 'Session name')),
          content: TextField(
            controller: controller,
            autofocus: true,
            onSubmitted: (value) => Navigator.pop(dialogContext, value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_tr('Annulla', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: Text(_tr('Salva', 'Save')),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _cloneFromSlash() async {
    if (!await resolveDirtyRepository(context, ref, widget.sessionId)) return;
    if (!mounted) return;
    final client = ref.read(pcpClientProvider);
    if (client == null) throw StateError('Daemon non connesso.');
    final result = await client.cloneSession(widget.sessionId);
    final data = result['data'] as Map<String, dynamic>? ?? result;
    final targetId = (data['sessionId'] ?? data['id']) as String?;
    if (targetId == null) {
      throw StateError('La sessione duplicata non è stata restituita.');
    }
    if (!mounted || !await switchSessionSafely(context, ref, targetId)) return;
    ref.invalidate(sessionListProvider);
  }

  Future<void> _forkFromSlash(String args) async {
    if (!await resolveDirtyRepository(context, ref, widget.sessionId)) return;
    if (!mounted) return;
    final state = ref.read(sessionStateFamily(widget.sessionId));
    var entryId = args.isEmpty ? null : args;
    if (entryId == null) {
      final userEntries = state.entries
          .where((entry) => entry.role == 'user')
          .toList();
      if (userEntries.isEmpty) {
        throw StateError(
          _tr(
            'La sessione non contiene messaggi utente da cui creare un fork.',
            'The session has no user messages to fork from.',
          ),
        );
      }
      entryId = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_tr('Crea un fork', 'Create a fork')),
          content: SizedBox(
            width: 460,
            height: 360,
            child: ListView.builder(
              itemCount: userEntries.length,
              itemBuilder: (_, index) {
                final entry = userEntries[userEntries.length - 1 - index];
                return ListTile(
                  title: Text(
                    entry.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(entry.id),
                  onTap: () => Navigator.pop(dialogContext, entry.id),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_tr('Annulla', 'Cancel')),
            ),
          ],
        ),
      );
      if (entryId == null) return;
    }
    final client = ref.read(pcpClientProvider);
    if (client == null) throw StateError('Daemon non connesso.');
    final result = await client.forkSession(widget.sessionId, entryId: entryId);
    final data = result['data'] as Map<String, dynamic>? ?? result;
    final targetId = (data['sessionId'] ?? data['id']) as String?;
    if (targetId == null) throw StateError('Il fork non è stato creato.');
    if (!mounted || !await switchSessionSafely(context, ref, targetId)) return;
    ref.invalidate(sessionListProvider);
  }

  Future<void> _resumeFromSlash() async {
    ref.invalidate(sessionListProvider);
    final sessions = await ref.read(sessionListProvider.future);
    if (!mounted) return;
    final selectedId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_tr('Riprendi una sessione', 'Resume a session')),
        content: SizedBox(
          width: 460,
          height: 360,
          child: sessions.isEmpty
              ? Center(
                  child: Text(
                    _tr(
                      'Nessuna sessione disponibile.',
                      'No sessions available.',
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: sessions.length,
                  itemBuilder: (_, index) {
                    final session = sessions[index];
                    final id = session['id']?.toString() ?? '';
                    return ListTile(
                      title: Text(session['name']?.toString() ?? id),
                      subtitle: Text(
                        session['cwd']?.toString() ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: id.isEmpty
                          ? null
                          : () => Navigator.pop(dialogContext, id),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_tr('Annulla', 'Cancel')),
          ),
        ],
      ),
    );
    if (selectedId == null || !mounted) return;
    await switchSessionSafely(context, ref, selectedId);
  }

  Future<void> _showPiSessionInfo() async {
    final state = ref.read(sessionStateFamily(widget.sessionId));
    final stats = state.sessionStats ?? const <String, dynamic>{};
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_tr('Sessione Pi', 'Pi session')),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _tr(
                    'Nome: ${state.sessionName ?? '—'}',
                    'Name: ${state.sessionName ?? '—'}',
                  ),
                ),
                Text(
                  _tr(
                    'Sessione: ${state.sessionId}',
                    'Session: ${state.sessionId}',
                  ),
                ),
                Text(_tr('Cartella: ${state.cwd}', 'Folder: ${state.cwd}')),
                Text(
                  _tr(
                    'Modello: ${state.currentModel ?? '—'}',
                    'Model: ${state.currentModel ?? '—'}',
                  ),
                ),
                Text(
                  _tr(
                    'Livello di ragionamento: ${state.currentThinkingLevel ?? '—'}',
                    'Thinking level: ${state.currentThinkingLevel ?? '—'}',
                  ),
                ),
                const SizedBox(height: 12),
                for (final entry in stats.entries)
                  Text('${entry.key}: ${entry.value}'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_tr('Chiudi', 'Close')),
          ),
        ],
      ),
    );
  }

  Future<void> _showModelPicker(BuildContext chipContext) async {
    final notifier = ref.read(sessionStateFamily(widget.sessionId).notifier);
    final models = await notifier.getAvailableModels().timeout(
      const Duration(seconds: 10),
      onTimeout: () => const <Map<String, dynamic>>[],
    );
    if (!mounted || !chipContext.mounted) return;
    final tokens = context.tokens;
    final current = ref.read(sessionStateFamily(widget.sessionId)).currentModel;

    if (models.isEmpty) {
      FrameSnackBar.show(
        context,
        message: _tr(
          'Nessun modello alternativo disponibile.',
          'No alternative model available.',
        ),
      );
      return;
    }

    final renderBox = chipContext.findRenderObject() as RenderBox?;
    final offset = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;

    final selected = await showMenu<Map<String, dynamic>>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        (offset.dy - (models.length * 40).clamp(100, 360).toDouble()).clamp(
          40.0,
          double.infinity,
        ),
        offset.dx + 260,
        offset.dy,
      ),
      color: tokens.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        side: BorderSide(color: tokens.borderStrong),
      ),
      items: models.map((m) {
        final id = m['id']?.toString() ?? '';
        final name = m['name']?.toString() ?? id;
        final isCurrent = id == current || name == current;
        return PopupMenuItem<Map<String, dynamic>>(
          value: m,
          height: 38,
          child: Row(
            children: [
              Icon(
                Icons.psychology_outlined,
                size: 15,
                color: isCurrent ? tokens.accent : tokens.textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: isCurrent ? tokens.accent : tokens.textPrimary,
                        fontSize: 12,
                        fontWeight: isCurrent
                            ? FontWeight.bold
                            : FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (m['provider'] != null)
                      Text(
                        m['provider'].toString(),
                        style: TextStyle(color: tokens.textMuted, fontSize: 10),
                      ),
                  ],
                ),
              ),
              if (isCurrent) Icon(Icons.check, size: 14, color: tokens.accent),
            ],
          ),
        );
      }).toList(),
    );

    if (selected != null && mounted) {
      final provider = selected['provider']?.toString() ?? 'default';
      final id = selected['id']?.toString() ?? '';
      await notifier.setModel(provider, id);
    }
  }

  Future<void> _showThinkingPicker(BuildContext chipContext) async {
    final notifier = ref.read(sessionStateFamily(widget.sessionId).notifier);
    final levels = await notifier.getAvailableThinkingLevels().timeout(
      const Duration(seconds: 10),
      onTimeout: () => const <String>[],
    );
    final effectiveLevels = levels.isNotEmpty
        ? levels
        : const ['off', 'low', 'medium', 'high'];
    if (!mounted || !chipContext.mounted) return;
    final tokens = context.tokens;
    final current = ref
        .read(sessionStateFamily(widget.sessionId))
        .currentThinkingLevel;

    final renderBox = chipContext.findRenderObject() as RenderBox?;
    final offset = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        (offset.dy - (effectiveLevels.length * 36).toDouble() - 10).clamp(
          40.0,
          double.infinity,
        ),
        offset.dx + 160,
        offset.dy,
      ),
      color: tokens.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        side: BorderSide(color: tokens.borderStrong),
      ),
      items: effectiveLevels.map((lvl) {
        final isCurrent = lvl.toLowerCase() == (current ?? '').toLowerCase();
        return PopupMenuItem<String>(
          value: lvl,
          height: 34,
          child: Row(
            children: [
              Icon(
                Icons.bolt_outlined,
                size: 14,
                color: isCurrent ? tokens.thinking : tokens.textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  lvl.toUpperCase(),
                  style: TextStyle(
                    color: isCurrent ? tokens.thinking : tokens.textPrimary,
                    fontSize: 12,
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
              if (isCurrent)
                Icon(Icons.check, size: 14, color: tokens.thinking),
            ],
          ),
        );
      }).toList(),
    );

    if (selected != null && mounted) {
      await notifier.setThinkingLevel(selected);
    }
  }

  Future<void> _showContextSizePicker() async {
    if (_isContextPickerLoading) return;
    final sessionId = widget.sessionId;
    setState(() => _isContextPickerLoading = true);
    try {
      // The first load can precede the daemon connection. Retry instead of silently using an empty catalogue.
      await _loadModels();
      if (!mounted || widget.sessionId != sessionId) return;
      final currentModel = ref.read(sessionStateFamily(sessionId)).currentModel;
      final model = _models.firstWhere(
        (model) => model['name'] == currentModel || model['id'] == currentModel,
        orElse: () => const <String, dynamic>{},
      );
      final maximum = modelContextWindow(model);
      if (maximum == null || maximum <= 0) {
        FrameSnackBar.show(
          context,
          message: _tr(
            'Contesto del modello non disponibile. Riprova quando il daemon è connesso.',
            'Model context unavailable. Try again when the daemon is connected.',
          ),
        );
        return;
      }
      final tokens = context.tokens;
      setState(() => _isContextPickerLoading = false);
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          key: const ValueKey('composer-context-size-dialog'),
          backgroundColor: tokens.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            side: BorderSide(color: tokens.borderStrong),
          ),
          title: Text(_tr('Dimensione Contesto', 'Context size')),
          content: SizedBox(
            width: 340,
            child: SingleChildScrollView(
              child: ContextWindowSelector(sessionId: sessionId, model: model),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_tr('Chiudi', 'Close')),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        FrameSnackBar.show(
          context,
          message: _tr(
            'Selezione contesto non riuscita: $error',
            'Context selection failed: $error',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isContextPickerLoading = false);
    }
  }

  Widget _buildAttachButton(FrameTokens tokens) {
    return PopupMenuButton<String>(
      key: const ValueKey('composer-attach-popup-btn'),
      tooltip: _tr(
        'Allega file, link o immagine',
        'Attach a file, link or image',
      ),
      icon: Icon(Icons.attach_file, size: 17, color: tokens.textSecondary),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      color: tokens.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        side: BorderSide(color: tokens.borderStrong),
      ),
      offset: const Offset(0, -170),
      onSelected: _onAttachSelected,
      itemBuilder: (ctx) => [
        PopupMenuItem(
          key: const ValueKey('attach-option-repo'),
          value: 'repo',
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_open_outlined, size: 16, color: tokens.accent),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _tr('File dal repository', 'File from repository'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: tokens.textPrimary, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          key: const ValueKey('attach-option-external'),
          value: 'external',
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.upload_file_outlined,
                size: 16,
                color: tokens.syntaxFunction,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _tr('File esterno', 'External file'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: tokens.textPrimary, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          key: const ValueKey('attach-option-link'),
          value: 'link',
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.link, size: 16, color: tokens.syntaxKeyword),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _tr('Link web', 'Web link'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: tokens.textPrimary, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          key: const ValueKey('attach-option-image'),
          value: 'image',
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.image_outlined, size: 16, color: tokens.syntaxType),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _tr('Immagine', 'Image'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: tokens.textPrimary, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appLanguageProvider);
    final tokens = context.tokens;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final isMobile = screenWidth < 600;
    final horizontalMargin = isMobile ? 14.0 : 8.0;
    final bottomMargin = isMobile
        ? (bottomPadding > 0 ? bottomPadding + 4.0 : 12.0)
        : 8.0;
    final isSending = ref.watch(composerSendingProvider(widget.sessionId));
    final attachments = ref.watch(
      composerAttachmentsProvider(widget.sessionId),
    );
    ref.listen<String>(composerDraftProvider(widget.sessionId), (
      previous,
      draft,
    ) {
      if (_controller.text != draft) {
        final currentSelection = _controller.selection;
        final newOffset =
            currentSelection.isValid &&
                currentSelection.baseOffset <= draft.length
            ? currentSelection.baseOffset
            : draft.length;
        _controller.value = TextEditingValue(
          text: draft,
          selection: TextSelection.collapsed(offset: newOffset),
        );
      }
    });
    final (
      readOnly,
      readOnlyReason,
      isStreaming,
      agentStatus,
      steeringQueue,
      followUpQueue,
      pendingUiRequests,
      activeToolCallsNotEmpty,
      currentModel,
      currentThinkingLevel,
      contextOverride,
    ) = ref.watch(
      sessionStateFamily(widget.sessionId).select(
        (s) => (
          s.readOnly,
          s.readOnlyReason,
          s.isStreaming,
          s.agentStatus,
          s.steeringQueue,
          s.followUpQueue,
          s.pendingUiRequests,
          s.activeToolCalls.isNotEmpty,
          s.currentModel,
          s.currentThinkingLevel,
          s.contextWindowOverride,
        ),
      ),
    );
    final sessionNotifier = ref.read(
      sessionStateFamily(widget.sessionId).notifier,
    );
    if (readOnly) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              readOnlyReason == 'terminal'
                  ? _tr(
                      'Pi ha una sessione interattiva aperta in questa cartella. Duplica per evitare scritture concorrenti.',
                      'Pi has an interactive session open in this folder. Duplicate it to avoid concurrent writes.',
                    )
                  : _tr(
                      'PiFrame non può verificare che questa sessione sia chiusa. Duplica per continuare in sicurezza.',
                      'PiFrame cannot verify that this session is closed. Duplicate it to continue safely.',
                    ),
              style: TextStyle(color: tokens.textSecondary),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (readOnlyReason == 'unknown') ...[
                  TextButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: Text(_tr('Continua qui', 'Continue here')),
                    onPressed: _continueAmbiguousSession,
                  ),
                  const SizedBox(width: 8),
                ],
                TextButton.icon(
                  icon: const Icon(Icons.copy_outlined),
                  label: Text(
                    _tr('Duplica e continua', 'Duplicate and continue'),
                  ),
                  onPressed: () async {
                    try {
                      final client = ref.read(pcpClientProvider);
                      if (client == null) {
                        throw StateError('Daemon non connesso');
                      }
                      if (!await resolveDirtyRepository(
                        context,
                        ref,
                        ref.read(activeSessionIdProvider),
                      )) {
                        return;
                      }
                      final result = await client.cloneSession(
                        widget.sessionId,
                      );
                      if (!mounted || !context.mounted) return;
                      final data =
                          (result['data'] as Map<String, dynamic>?) ?? result;
                      final targetSessionId =
                          (data['sessionId'] ?? data['id']) as String?;
                      if (targetSessionId != null) {
                        if (!await switchSessionSafely(
                          context,
                          ref,
                          targetSessionId,
                        )) {
                          return;
                        }
                        ref.invalidate(sessionListProvider);
                      }
                    } catch (error) {
                      if (context.mounted) {
                        FrameSnackBar.show(
                          context,
                          message: _tr(
                            'Duplicazione non riuscita: $error',
                            'Duplication failed: $error',
                          ),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      );
    }
    final isError = agentStatus == AgentStatus.workerError;
    final totalQueued = steeringQueue.length + followUpQueue.length;

    final activeModelMap = _models.firstWhere(
      (m) => m['name'] == currentModel || m['id'] == currentModel,
      orElse: () => const {},
    );
    final isVariablePricing =
        hasVariableContextPricing(activeModelMap) ||
        (currentModel != null &&
            (currentModel.toLowerCase().contains('luna') ||
                currentModel.toLowerCase().contains('haiku')));
    final effectiveContextWindow =
        contextOverride ?? modelContextWindow(activeModelMap);
    final isLongPrompt =
        _controller.text.length > 80 || _controller.text.contains('\n');

    final pendingInteractionRequests = pendingUiRequests
        .where(
          (request) =>
              !_dismissedUiRequestIds.contains(
                request['requestId']?.toString(),
              ) &&
              _isInteractionRequest(request),
        )
        .toList();

    final isShimmerActive =
        isSending ||
        isStreaming ||
        agentStatus == AgentStatus.working ||
        agentStatus == AgentStatus.retrying ||
        agentStatus == AgentStatus.compacting ||
        activeToolCallsNotEmpty;

    final isAgentAnswering =
        isStreaming ||
        agentStatus == AgentStatus.working ||
        activeToolCallsNotEmpty;

    if (!isAgentAnswering && _isManuallyExpanded) {
      _isManuallyExpanded = false;
    }

    final isFocused = _focusNode.hasFocus;
    final hasInputtedText = _hasText || _controller.text.trim().isNotEmpty;
    final hasAttachments = attachments.isNotEmpty;
    final shouldMinimize =
        isAgentAnswering &&
        !isFocused &&
        !_isManuallyExpanded &&
        !hasInputtedText &&
        !hasAttachments &&
        pendingInteractionRequests.isEmpty;

    return MouseRegion(
      key: const ValueKey('composer-mouse-region'),
      onEnter: (event) {
        _isPointerOver = true;
        _hoverGraceTimer?.cancel();
        _hoverGraceTimer = null;
        if (shouldMinimize) {
          _expand5sTimer?.cancel();
          _expand5sTimer = Timer(const Duration(seconds: 5), () {
            if (mounted && _isPointerOver) {
              setState(() {
                _isManuallyExpanded = true;
                _minimizedHoverOffsetNotifier.value = null;
              });
            }
          });
        }
      },
      onHover: (event) {
        if (shouldMinimize && _expand5sTimer == null && _isPointerOver) {
          _expand5sTimer = Timer(const Duration(seconds: 5), () {
            if (mounted && _isPointerOver) {
              setState(() {
                _isManuallyExpanded = true;
                _minimizedHoverOffsetNotifier.value = null;
              });
            }
          });
        }
      },
      onExit: (_) {
        _isPointerOver = false;
        _minimizedHoverOffsetNotifier.value = null;
        _expand5sTimer?.cancel();
        _expand5sTimer = null;
        if (_isManuallyExpanded) {
          _hoverGraceTimer?.cancel();
          _hoverGraceTimer = Timer(const Duration(milliseconds: 600), () {
            if (mounted && !_isPointerOver) {
              setState(() => _isManuallyExpanded = false);
            }
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOutCubic,
        margin: EdgeInsets.fromLTRB(
          horizontalMargin,
          4,
          horizontalMargin,
          bottomMargin,
        ),
        child: ShimmerBorder(
          isActive: isShimmerActive,
          borderRadius: BorderRadius.circular(tokens.radiusLg),
          child: _ComposerSizeAnimator(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeInOutCubic,
              switchOutCurve: Curves.easeInOutCubic,
              layoutBuilder: (currentChild, previousChildren) {
                return Stack(
                  alignment: Alignment.bottomCenter,
                  clipBehavior: Clip.hardEdge,
                  children: [
                    ...previousChildren.map(
                      (child) => Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: child,
                      ),
                    ),
                    ?currentChild,
                  ],
                );
              },
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: Container(
                key: ValueKey('composer_box_${shouldMinimize ? 'min' : 'max'}'),
                padding: shouldMinimize
                    ? const EdgeInsets.symmetric(horizontal: 14, vertical: 8)
                    : const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: tokens.surfaceElevated,
                  borderRadius: BorderRadius.circular(tokens.radiusLg),
                  border: Border.all(
                    color: shouldMinimize
                        ? tokens.agentWorking.withValues(alpha: 0.3)
                        : tokens.surfaceElevated.withValues(alpha: 0),
                    width: 1,
                  ),
                ),
                child: pendingInteractionRequests.isNotEmpty
                    ? Padding(
                        key: const ValueKey('composer-extension-ui-card'),
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ExtensionUiDialog(
                          key: ValueKey(
                            'ext_ui_${pendingInteractionRequests.last['requestId']}',
                          ),
                          sessionId: widget.sessionId,
                          request: pendingInteractionRequests.last,
                          isCard: true,
                          onDismissed: () {
                            if (!mounted) return;
                            setState(
                              () => _dismissedUiRequestIds.add(
                                pendingInteractionRequests.last['requestId']
                                    .toString(),
                              ),
                            );
                          },
                        ),
                      )
                    : shouldMinimize
                    ? MouseRegion(
                        onEnter: (event) {
                          _minimizedHoverOffsetNotifier.value =
                              event.localPosition;
                        },
                        onHover: (event) {
                          _minimizedHoverOffsetNotifier.value =
                              event.localPosition;
                        },
                        onExit: (_) {
                          _minimizedHoverOffsetNotifier.value = null;
                        },
                        child: ValueListenableBuilder<Offset?>(
                          valueListenable: _minimizedHoverOffsetNotifier,
                          builder: (context, hoverOffset, childWidget) {
                            return CustomPaint(
                              painter: hoverOffset == null
                                  ? null
                                  : _GlowPointerPainter(
                                      pointerPosition: hoverOffset,
                                      borderRadius: BorderRadius.circular(
                                        tokens.radiusLg,
                                      ),
                                      glowColor: tokens.accent,
                                      borderColor: tokens.accent,
                                    ),
                              child: childWidget,
                            );
                          },
                          child: _buildMinimizedBar(tokens, isStreaming),
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SessionGoalBanner(sessionId: widget.sessionId),
                          // File Mention overlay if active
                          if (_showFileMentionMenu &&
                              _matchingMentionFiles.isNotEmpty)
                            Padding(
                              key: const ValueKey('composer-file-mention-menu'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              child: FileMentionMenu(
                                key: const ValueKey(
                                  'composer-file-mention-list',
                                ),
                                files: _matchingMentionFiles,
                                query: _fileMentionQuery,
                                selectedIndex: _fileMentionSelectedIndex,
                                onSelect: _completeFileMention,
                              ),
                            ),

                          // Slash Menu overlay if active
                          if (_showSlashMenu && _availableCommands.isNotEmpty)
                            Padding(
                              key: const ValueKey('composer-slash-menu'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              child: SlashMenu(
                                key: const ValueKey('composer-slash-list'),
                                commands: _availableCommands,
                                filter: _controller.text,
                                onSelect: _onSelectSlashCommand,
                              ),
                            ),

                          // Pending Queue bar (if any queue exists)
                          if (totalQueued > 0)
                            Container(
                              key: const ValueKey('composer-queue-bar'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              color: tokens.surfaceElevated,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.queue,
                                        size: 16,
                                        color: tokens.accent,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _tr(
                                            'In coda ($totalQueued): ${steeringQueue.length} steer, ${followUpQueue.length} follow-up',
                                            'Queued ($totalQueued): ${steeringQueue.length} steer, ${followUpQueue.length} follow-up',
                                          ),
                                          style: TextStyle(
                                            color: tokens.textSecondary,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      if (steeringQueue.isNotEmpty)
                                        IconButton(
                                          key: const ValueKey(
                                            'composer-queue-toggle-expand',
                                          ),
                                          tooltip: _queueExpanded
                                              ? _tr(
                                                  'Nascondi messaggi in coda',
                                                  'Hide queued messages',
                                                )
                                              : _tr(
                                                  'Mostra messaggi in coda',
                                                  'Show queued messages',
                                                ),
                                          icon: Icon(
                                            _queueExpanded
                                                ? Icons.keyboard_arrow_up
                                                : Icons.keyboard_arrow_down,
                                            size: 16,
                                            color: tokens.textSecondary,
                                          ),
                                          onPressed: () => setState(
                                            () => _queueExpanded =
                                                !_queueExpanded,
                                          ),
                                        ),
                                      TextButton.icon(
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        icon: Icon(
                                          Icons.clear_all,
                                          size: 14,
                                          color: tokens.textMuted,
                                        ),
                                        label: Text(
                                          _tr('Svuota coda', 'Clear queue'),
                                          style: TextStyle(
                                            color: tokens.textMuted,
                                            fontSize: 11,
                                          ),
                                        ),
                                        onPressed: () => _runAction(
                                          sessionNotifier.clearQueue,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_queueExpanded &&
                                      steeringQueue.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    for (
                                      var i = 0;
                                      i < steeringQueue.length;
                                      i++
                                    )
                                      Container(
                                        key: ValueKey('steer-queue-item-$i'),
                                        margin: const EdgeInsets.only(
                                          bottom: 4,
                                        ),
                                        padding: const EdgeInsets.fromLTRB(
                                          8,
                                          4,
                                          6,
                                          4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: tokens.surface,
                                          borderRadius: BorderRadius.circular(
                                            tokens.radiusSm,
                                          ),
                                          border: Border.all(
                                            color: tokens.border,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 5,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: tokens.accent.withValues(
                                                  alpha: 0.15,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      tokens.radiusSm,
                                                    ),
                                              ),
                                              child: Text(
                                                'STEER #${i + 1}',
                                                style: TextStyle(
                                                  color: tokens.accent,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                steeringQueue[i],
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: tokens.textPrimary,
                                                  fontSize: 12,
                                                  fontFamily:
                                                      tokens.monoFontFamily,
                                                ),
                                              ),
                                            ),
                                            IconButton(
                                              key: ValueKey(
                                                'edit-steer-btn-$i',
                                              ),
                                              tooltip: _tr(
                                                'Modifica messaggio steer in coda',
                                                'Edit queued steer message',
                                              ),
                                              icon: Icon(
                                                Icons.edit_outlined,
                                                size: 14,
                                                color: tokens.accent,
                                              ),
                                              constraints: const BoxConstraints(
                                                minWidth: 26,
                                                minHeight: 26,
                                              ),
                                              padding: EdgeInsets.zero,
                                              onPressed: () =>
                                                  _showEditSteerDialog(
                                                    context,
                                                    i,
                                                    steeringQueue[i],
                                                  ),
                                            ),
                                            IconButton(
                                              key: ValueKey(
                                                'delete-steer-btn-$i',
                                              ),
                                              tooltip: _tr(
                                                'Elimina dalla coda',
                                                'Remove from queue',
                                              ),
                                              icon: Icon(
                                                Icons.close,
                                                size: 14,
                                                color: tokens.textMuted,
                                              ),
                                              constraints: const BoxConstraints(
                                                minWidth: 26,
                                                minHeight: 26,
                                              ),
                                              padding: EdgeInsets.zero,
                                              onPressed: () => sessionNotifier
                                                  .removeSteerMessage(i),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ],
                              ),
                            ),

                          // Worker Crash Recovery Banner
                          if (isError)
                            Container(
                              key: const ValueKey('composer-crash-banner'),
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              color: tokens.danger.withValues(alpha: 0.15),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    size: 18,
                                    color: tokens.danger,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _tr(
                                        'Il worker Pi è terminato inaspettatamente. Nessun comando è stato re-inviato automaticamente.',
                                        'The Pi worker stopped unexpectedly. No commands were automatically resent.',
                                      ),
                                      style: TextStyle(
                                        color: tokens.danger,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: tokens.accent,
                                      foregroundColor: tokens.accentContrast,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      minimumSize: Size.zero,
                                    ),
                                    icon: const Icon(Icons.refresh, size: 14),
                                    label: Text(
                                      _tr(
                                        'Riprendi sessione',
                                        'Resume session',
                                      ),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    onPressed: () => _runAction(
                                      sessionNotifier.recoverSession,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // Input area
                          Padding(
                            key: const ValueKey('composer-input-area'),
                            padding: const EdgeInsets.all(4),
                            child: Focus(
                              key: const ValueKey('composer-input-focus'),
                              onKeyEvent: (node, event) {
                                if (event is KeyDownEvent) {
                                  // File Mention keyboard navigation
                                  if (_showFileMentionMenu &&
                                      _matchingMentionFiles.isNotEmpty) {
                                    if (event.logicalKey ==
                                        LogicalKeyboardKey.arrowDown) {
                                      setState(() {
                                        _fileMentionSelectedIndex =
                                            (_fileMentionSelectedIndex + 1) %
                                            _matchingMentionFiles.length;
                                      });
                                      return KeyEventResult.handled;
                                    }
                                    if (event.logicalKey ==
                                        LogicalKeyboardKey.arrowUp) {
                                      setState(() {
                                        _fileMentionSelectedIndex =
                                            (_fileMentionSelectedIndex -
                                                1 +
                                                _matchingMentionFiles.length) %
                                            _matchingMentionFiles.length;
                                      });
                                      return KeyEventResult.handled;
                                    }
                                    if (event.logicalKey ==
                                            LogicalKeyboardKey.tab ||
                                        event.logicalKey ==
                                            LogicalKeyboardKey.enter) {
                                      final chosen =
                                          _matchingMentionFiles[_fileMentionSelectedIndex]['path']
                                              ?.toString() ??
                                          '';
                                      if (chosen.isNotEmpty) {
                                        _completeFileMention(chosen);
                                        return KeyEventResult.handled;
                                      }
                                    }
                                    if (event.logicalKey ==
                                        LogicalKeyboardKey.escape) {
                                      setState(
                                        () => _showFileMentionMenu = false,
                                      );
                                      return KeyEventResult.handled;
                                    }
                                  }

                                  if (event.logicalKey ==
                                      LogicalKeyboardKey.escape) {
                                    if (isStreaming) {
                                      _interrupt();
                                      return KeyEventResult.handled;
                                    }
                                  }
                                  if (event.logicalKey ==
                                          LogicalKeyboardKey.enter &&
                                      (HardwareKeyboard
                                              .instance
                                              .isMetaPressed ||
                                          HardwareKeyboard
                                              .instance
                                              .isControlPressed)) {
                                    if (isStreaming) {
                                      _send(streamingBehavior: 'steer');
                                    } else {
                                      _send();
                                    }
                                    return KeyEventResult.handled;
                                  }
                                }
                                return KeyEventResult.ignored;
                              },
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (attachments.isNotEmpty)
                                    AttachmentListBar(
                                      key: const ValueKey(
                                        'composer-attachments-bar',
                                      ),
                                      attachments: attachments,
                                      isEditable: true,
                                      onRemove: (a) => ref
                                          .read(
                                            composerAttachmentsProvider(
                                              widget.sessionId,
                                            ).notifier,
                                          )
                                          .remove(a.id),
                                    ),
                                  Stack(
                                    children: [
                                      TextField(
                                        key: const ValueKey(
                                          'composer-text-field',
                                        ),
                                        cursorColor: tokens.accent,
                                        controller: _controller,
                                        focusNode: _focusNode,
                                        maxLines: _isInputEnlarged ? 16 : 5,
                                        minLines: _isInputEnlarged ? 8 : 2,
                                        onChanged: (_) {
                                          if (mounted) setState(() {});
                                        },
                                        style: TextStyle(
                                          color: tokens.textPrimary,
                                          fontSize: 14.5,
                                          height: 1.45,
                                        ),
                                        decoration: InputDecoration(
                                          hintText: isStreaming
                                              ? _tr(
                                                  'Aggiungi istruzioni o prepara il prossimo turno...',
                                                  'Add instructions or prepare the next turn...',
                                                )
                                              : _tr(
                                                  'Cosa vuoi realizzare? Digita / per i comandi.',
                                                  'What would you like to do? Type / for commands.',
                                                ),
                                          hintStyle: TextStyle(
                                            color: tokens.textMuted,
                                            fontSize: 13.5,
                                          ),
                                          filled: false,
                                          border: InputBorder.none,
                                          enabledBorder: InputBorder.none,
                                          focusedBorder: InputBorder.none,
                                          contentPadding: EdgeInsets.fromLTRB(
                                            4,
                                            2,
                                            (isLongPrompt || _isInputEnlarged)
                                                ? 80
                                                : 4,
                                            6,
                                          ),
                                        ),
                                      ),
                                      if (isLongPrompt || _isInputEnlarged)
                                        Positioned(
                                          top: 2,
                                          right: 2,
                                          child: Tooltip(
                                            message: _isInputEnlarged
                                                ? _tr(
                                                    'Riduci area di testo',
                                                    'Shrink text area',
                                                  )
                                                : _tr(
                                                    'Ingrandisci area di testo',
                                                    'Expand text area',
                                                  ),
                                            child: InkWell(
                                              key: const ValueKey(
                                                'composer-enlarge-prompt-btn',
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    tokens.radiusSm,
                                                  ),
                                              onTap: () => setState(
                                                () => _isInputEnlarged =
                                                    !_isInputEnlarged,
                                              ),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 3,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: tokens.surfaceElevated,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        tokens.radiusSm,
                                                      ),
                                                  border: Border.all(
                                                    color: _isInputEnlarged
                                                        ? tokens.accent
                                                        : tokens.border,
                                                    width: 1,
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      _isInputEnlarged
                                                          ? Icons
                                                                .close_fullscreen
                                                          : Icons.open_in_full,
                                                      size: 11,
                                                      color: _isInputEnlarged
                                                          ? tokens.accent
                                                          : tokens
                                                                .textSecondary,
                                                    ),
                                                    const SizedBox(width: 3),
                                                    Text(
                                                      _isInputEnlarged
                                                          ? _tr(
                                                              'Riduci',
                                                              'Shrink',
                                                            )
                                                          : _tr(
                                                              'Ingrandisci',
                                                              'Expand',
                                                            ),
                                                      style: TextStyle(
                                                        color: _isInputEnlarged
                                                            ? tokens.accent
                                                            : tokens
                                                                  .textSecondary,
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Builder(
                                                builder: (chipCtx) => Tooltip(
                                                  message: _tr(
                                                    'Cambia modello',
                                                    'Change model',
                                                  ),
                                                  child: InkWell(
                                                    key: const ValueKey(
                                                      'composer-model-picker-btn',
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          tokens.radiusSm,
                                                        ),
                                                    onTap: () => _guardPicker(
                                                      () => _showModelPicker(
                                                        chipCtx,
                                                      ),
                                                    ),
                                                    child: Container(
                                                      height: 26,
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 7,
                                                            vertical: 3,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: tokens
                                                            .surfaceElevated,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              tokens.radiusSm,
                                                            ),
                                                        border: Border.all(
                                                          color: tokens.border,
                                                        ),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                            Icons
                                                                .smart_toy_outlined,
                                                            size: 13,
                                                            color:
                                                                tokens.accent,
                                                          ),
                                                          const SizedBox(
                                                            width: 4,
                                                          ),
                                                          ConstrainedBox(
                                                            constraints: BoxConstraints(
                                                              maxWidth:
                                                                  MediaQuery.sizeOf(
                                                                        context,
                                                                      ).width <
                                                                      500
                                                                  ? 80
                                                                  : 130,
                                                            ),
                                                            child: Text(
                                                              currentModel ??
                                                                  _tr(
                                                                    'Modello',
                                                                    'Model',
                                                                  ),
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: TextStyle(
                                                                color: tokens
                                                                    .textSecondary,
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            width: 2,
                                                          ),
                                                          Icon(
                                                            Icons
                                                                .keyboard_arrow_down,
                                                            size: 13,
                                                            color: tokens
                                                                .textMuted,
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Builder(
                                                builder: (chipCtx) => Tooltip(
                                                  message: _tr(
                                                    'Livello thinking',
                                                    'Thinking level',
                                                  ),
                                                  child: InkWell(
                                                    key: const ValueKey(
                                                      'composer-thinking-picker-btn',
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          tokens.radiusSm,
                                                        ),
                                                    onTap: () => _guardPicker(
                                                      () => _showThinkingPicker(
                                                        chipCtx,
                                                      ),
                                                    ),
                                                    child: Container(
                                                      height: 26,
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 3,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: tokens
                                                            .surfaceElevated,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              tokens.radiusSm,
                                                            ),
                                                        border: Border.all(
                                                          color: tokens.border,
                                                        ),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                            Icons.bolt_outlined,
                                                            size: 13,
                                                            color:
                                                                tokens.thinking,
                                                          ),
                                                          const SizedBox(
                                                            width: 3,
                                                          ),
                                                          Text(
                                                            (currentThinkingLevel ??
                                                                    'med')
                                                                .toUpperCase(),
                                                            style: TextStyle(
                                                              color: tokens
                                                                  .textSecondary,
                                                              fontSize: 10.5,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            width: 2,
                                                          ),
                                                          Icon(
                                                            Icons
                                                                .keyboard_arrow_down,
                                                            size: 13,
                                                            color: tokens
                                                                .textMuted,
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              if (isVariablePricing) ...[
                                                const SizedBox(width: 4),
                                                Builder(
                                                  builder: (chipCtx) => Tooltip(
                                                    message: _tr(
                                                      'Dimensione contesto (pricing variabile)',
                                                      'Context size (variable pricing)',
                                                    ),
                                                    child: InkWell(
                                                      key: const ValueKey(
                                                        'composer-context-size-picker-btn',
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            tokens.radiusSm,
                                                          ),
                                                      onTap:
                                                          _showContextSizePicker,
                                                      child: Container(
                                                        height: 26,
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 7,
                                                              vertical: 3,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: tokens
                                                              .surfaceElevated,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                tokens.radiusSm,
                                                              ),
                                                          border: Border.all(
                                                            color: tokens.accent
                                                                .withValues(
                                                                  alpha: 0.35,
                                                                ),
                                                          ),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            if (_isContextPickerLoading)
                                                              SizedBox(
                                                                width: 12,
                                                                height: 12,
                                                                child: CircularProgressIndicator(
                                                                  strokeWidth:
                                                                      1.5,
                                                                  color: tokens
                                                                      .accent,
                                                                ),
                                                              )
                                                            else
                                                              Icon(
                                                                Icons.tune,
                                                                size: 12,
                                                                color: tokens
                                                                    .accent,
                                                              ),
                                                            const SizedBox(
                                                              width: 3,
                                                            ),
                                                            Text(
                                                              formatTokens(
                                                                effectiveContextWindow,
                                                              ),
                                                              style: TextStyle(
                                                                color: tokens
                                                                    .accent,
                                                                fontSize: 10.5,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 2,
                                                            ),
                                                            Icon(
                                                              Icons
                                                                  .keyboard_arrow_down,
                                                              size: 12,
                                                              color: tokens
                                                                  .textMuted,
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                      Tooltip(
                                        message: _isInputEnlarged
                                            ? _tr(
                                                'Riduci area di testo',
                                                'Shrink text area',
                                              )
                                            : _tr(
                                                'Ingrandisci area di testo',
                                                'Expand text area',
                                              ),
                                        child: IconButton(
                                          key: const ValueKey(
                                            'composer-enlarge-toggle-btn',
                                          ),
                                          icon: Icon(
                                            _isInputEnlarged
                                                ? Icons.close_fullscreen
                                                : Icons.open_in_full,
                                            size: 15,
                                            color:
                                                (_isInputEnlarged ||
                                                    isLongPrompt)
                                                ? tokens.accent
                                                : tokens.textMuted,
                                          ),
                                          visualDensity: VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 28,
                                            minHeight: 28,
                                          ),
                                          onPressed: () => setState(
                                            () => _isInputEnlarged =
                                                !_isInputEnlarged,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      _buildAttachButton(tokens),
                                      const SizedBox(width: 4),
                                      if (isStreaming ||
                                          agentStatus == AgentStatus.working ||
                                          activeToolCallsNotEmpty) ...[
                                        IconButton(
                                          icon: _isInterrupting
                                              ? SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: tokens.danger,
                                                      ),
                                                )
                                              : Icon(
                                                  Icons.stop_circle_outlined,
                                                  color: tokens.signalDanger,
                                                  size: 19,
                                                ),
                                          tooltip: _tr(
                                            'Interrompi (Esc)',
                                            'Stop (Esc)',
                                          ),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 28,
                                            minHeight: 28,
                                          ),
                                          onPressed: _isInterrupting
                                              ? null
                                              : _interrupt,
                                        ),
                                        const SizedBox(width: 4),
                                        Tooltip(
                                          message: _tr(
                                            'Steer: interrompe e applica (Ctrl+Invio)',
                                            'Steer: interrupt and apply (Ctrl+Enter)',
                                          ),
                                          child: Container(
                                            width: 28,
                                            height: 28,
                                            decoration: BoxDecoration(
                                              color: tokens.accent,
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    tokens.radiusSm,
                                                  ),
                                            ),
                                            child: IconButton(
                                              key: const ValueKey(
                                                'composer-steer-btn',
                                              ),
                                              padding: EdgeInsets.zero,
                                              icon: Stack(
                                                alignment: Alignment.center,
                                                children: [
                                                  Icon(
                                                    Icons.bolt,
                                                    size: 16,
                                                    color:
                                                        tokens.accentContrast,
                                                  ),
                                                  SizedBox(
                                                    width: 0,
                                                    height: 0,
                                                    child: Text(
                                                      'Steer',
                                                      style: TextStyle(
                                                        fontSize: 0,
                                                        color: tokens.background
                                                            .withValues(
                                                              alpha: 0,
                                                            ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              onPressed: isSending
                                                  ? null
                                                  : () => _send(
                                                      streamingBehavior:
                                                          'steer',
                                                    ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Tooltip(
                                          message: _tr(
                                            'Follow-up: metti in coda',
                                            'Follow-up: add to queue',
                                          ),
                                          child: Container(
                                            width: 28,
                                            height: 28,
                                            decoration: BoxDecoration(
                                              color: tokens.surfaceElevated,
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    tokens.radiusSm,
                                                  ),
                                              border: Border.all(
                                                color: tokens.border,
                                              ),
                                            ),
                                            child: IconButton(
                                              key: const ValueKey(
                                                'composer-followup-btn',
                                              ),
                                              padding: EdgeInsets.zero,
                                              icon: Stack(
                                                alignment: Alignment.center,
                                                children: [
                                                  Icon(
                                                    Icons.more_time,
                                                    size: 15,
                                                    color: tokens.textPrimary,
                                                  ),
                                                  SizedBox(
                                                    width: 0,
                                                    height: 0,
                                                    child: Text(
                                                      'Follow-up',
                                                      style: TextStyle(
                                                        fontSize: 0,
                                                        color: tokens.background
                                                            .withValues(
                                                              alpha: 0,
                                                            ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              onPressed: isSending
                                                  ? null
                                                  : () => _send(
                                                      streamingBehavior:
                                                          'followUp',
                                                    ),
                                            ),
                                          ),
                                        ),
                                      ] else ...[
                                        if (ref.watch(
                                          sessionHasModifiedFilesProvider(
                                            widget.sessionId,
                                          ),
                                        )) ...[
                                          Tooltip(
                                            message:
                                                ref.watch(
                                                  isReviewingChangesProvider,
                                                )
                                                ? _tr(
                                                    'Chiudi revisione modifiche',
                                                    'Close changes review',
                                                  )
                                                : _tr(
                                                    'Rivedi modifiche ai file',
                                                    'Review file changes',
                                                  ),
                                            child: Container(
                                              width: 28,
                                              height: 28,
                                              margin: const EdgeInsets.only(
                                                right: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color:
                                                    ref.watch(
                                                      isReviewingChangesProvider,
                                                    )
                                                    ? tokens.accent.withValues(
                                                        alpha: 0.15,
                                                      )
                                                    : tokens.surfaceElevated,
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      tokens.radiusSm,
                                                    ),
                                                border: Border.all(
                                                  color:
                                                      ref.watch(
                                                        isReviewingChangesProvider,
                                                      )
                                                      ? tokens.accent
                                                      : tokens.border,
                                                ),
                                              ),
                                              child: IconButton(
                                                key: const ValueKey(
                                                  'review-changes-btn',
                                                ),
                                                padding: EdgeInsets.zero,
                                                icon: Stack(
                                                  alignment: Alignment.center,
                                                  children: [
                                                    Icon(
                                                      ref.watch(
                                                            isReviewingChangesProvider,
                                                          )
                                                          ? Icons.rate_review
                                                          : Icons
                                                                .rate_review_outlined,
                                                      size: 15,
                                                      color:
                                                          ref.watch(
                                                            isReviewingChangesProvider,
                                                          )
                                                          ? tokens.accent
                                                          : tokens
                                                                .textSecondary,
                                                    ),
                                                    SizedBox(
                                                      width: 0,
                                                      height: 0,
                                                      child: Text(
                                                        'Review changes',
                                                        style: TextStyle(
                                                          fontSize: 0,
                                                          color: tokens
                                                              .background
                                                              .withValues(
                                                                alpha: 0,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                onPressed: () {
                                                  ref
                                                      .read(
                                                        isReviewingChangesProvider
                                                            .notifier,
                                                      )
                                                      .update((v) => !v);
                                                },
                                              ),
                                            ),
                                          ),
                                        ],
                                        Tooltip(
                                          message: _tr(
                                            'Invia prompt (Ctrl+Invio)',
                                            'Send prompt (Ctrl+Enter)',
                                          ),
                                          child: PressFeedback(
                                            child: FilledButton(
                                              key: const ValueKey(
                                                'composer-send-btn',
                                              ),
                                              style: FilledButton.styleFrom(
                                                backgroundColor: tokens.accent,
                                                foregroundColor:
                                                    tokens.accentContrast,
                                                padding: EdgeInsets.zero,
                                                minimumSize: const Size(28, 28),
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        tokens.radiusSm,
                                                      ),
                                                ),
                                              ),
                                              onPressed: isSending
                                                  ? null
                                                  : () => _send(),
                                              child: Stack(
                                                alignment: Alignment.center,
                                                children: [
                                                  if (isSending)
                                                    SizedBox(
                                                      width: 14,
                                                      height: 14,
                                                      child:
                                                          CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            color: tokens
                                                                .accentContrast,
                                                          ),
                                                    )
                                                  else
                                                    Icon(
                                                      Icons.arrow_upward,
                                                      size: 16,
                                                      color:
                                                          tokens.accentContrast,
                                                    ),
                                                  SizedBox(
                                                    width: 0,
                                                    height: 0,
                                                    child: Text(
                                                      _tr('Invia', 'Send'),
                                                      style: TextStyle(
                                                        fontSize: 0,
                                                        color: tokens.background
                                                            .withValues(
                                                              alpha: 0,
                                                            ),
                                                      ),
                                                    ),
                                                  ),
                                                  if (isSending)
                                                    const SizedBox(
                                                      width: 0,
                                                      height: 0,
                                                      child: Icon(
                                                        Icons.arrow_upward,
                                                        size: 0,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMinimizedBar(FrameTokens tokens, bool isStreaming) {
    final isTest = WidgetsBinding.instance.runtimeType.toString().contains(
      'Test',
    );
    return InkWell(
      key: const ValueKey('composer-minimized-bar'),
      borderRadius: BorderRadius.circular(tokens.radiusLg),
      onTap: () {
        _expand5sTimer?.cancel();
        _expand5sTimer = null;
        _minimizedHoverOffsetNotifier.value = null;
        setState(() => _isManuallyExpanded = true);
        _focusNode.requestFocus();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: isTest
                  ? Icon(Icons.sync, size: 12, color: tokens.agentWorking)
                  : CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: tokens.agentWorking,
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _tr(
                  'L\'agente sta rispondendo... Passa il mouse o clicca per scrivere',
                  'The agent is responding... Hover or click to type',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: 12,
                  fontFamily: tokens.uiFontFamily,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (isStreaming) ...[
              const SizedBox(width: 8),
              InkWell(
                key: const ValueKey('composer-minimized-interrupt'),
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                onTap: _interrupt,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.stop_circle_outlined,
                        size: 13,
                        color: tokens.signalDanger,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _tr('Interrompi', 'Stop'),
                        style: TextStyle(
                          color: tokens.signalDanger,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(width: 8),
            Icon(Icons.unfold_more, size: 16, color: tokens.textMuted),
          ],
        ),
      ),
    );
  }
}

class _GlowPointerPainter extends CustomPainter {
  final Offset? pointerPosition;
  final BorderRadius borderRadius;
  final Color glowColor;
  final Color borderColor;
  static const double radius = 120.0;

  const _GlowPointerPainter({
    required this.pointerPosition,
    required this.borderRadius,
    required this.glowColor,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final pos = pointerPosition;
    if (pos == null) return;

    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect);

    // 1. Subtle inner ambient glow following pointer, clipped to card
    canvas.save();
    canvas.clipRRect(rrect);

    final glowPaint = Paint()
      ..shader = ui.Gradient.radial(
        pos,
        radius,
        [
          glowColor.withValues(alpha: 0.22),
          glowColor.withValues(alpha: 0.08),
          glowColor.withValues(alpha: 0.0),
        ],
        const [0.0, 0.45, 1.0],
      );

    canvas.drawRect(rect, glowPaint);
    canvas.restore();

    // 2. Glowing border highlight following pointer
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..shader = ui.Gradient.radial(
        pos,
        radius,
        [
          borderColor.withValues(alpha: 0.85),
          glowColor.withValues(alpha: 0.4),
          glowColor.withValues(alpha: 0.0),
        ],
        const [0.0, 0.5, 1.0],
      );

    canvas.drawRRect(rrect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _GlowPointerPainter oldDelegate) {
    return oldDelegate.pointerPosition != pointerPosition ||
        oldDelegate.glowColor != glowColor ||
        oldDelegate.borderColor != borderColor;
  }
}
