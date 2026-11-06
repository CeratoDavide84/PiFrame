import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_protocol/pi_frame_protocol.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../data/daemon/pcp_client.dart';
import '../../data/language/language_settings.dart';
import '../workspace/repository_workspace.dart';
import 'pinned_sessions_provider.dart';
import 'removed_repos_provider.dart';
import '../../ui/frame_snack_bar.dart';

Future<String?> _chooseSessionDirectory(
  BuildContext context,
  String initialDirectory,
) => showDialog<String>(
  context: context,
  builder: (_) => _SessionDirectoryDialog(initialDirectory: initialDirectory),
);

class _SessionDirectoryDialog extends ConsumerStatefulWidget {
  const _SessionDirectoryDialog({required this.initialDirectory});
  final String initialDirectory;

  @override
  ConsumerState<_SessionDirectoryDialog> createState() =>
      _SessionDirectoryDialogState();
}

class _SessionDirectoryDialogState extends ConsumerState<_SessionDirectoryDialog> {
  String _tr(String it, String en) => ref.read(appLanguageProvider) == AppLanguage.it ? it : en;
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialDirectory,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickDirectory() async {
    try {
      final directory = await getDirectoryPath();
      if (mounted && directory != null) {
        setState(() => _controller.text = directory);
      }
    } catch (error) {
      if (mounted) {
        FrameSnackBar.show(
          context,
          message: _tr('Cartella non disponibile: $error', 'Folder unavailable: $error'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_tr('Nuova sessione', 'New session')),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('new-session-cwd'),
          controller: _controller,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: _tr('Cartella di lavoro', 'Working directory'),
            hintText: _tr('C:\\Progetti\\mio-progetto', 'C:\\Projects\\my-project'),
          ),
        ),
        if (kIsWeb) ...[
          const SizedBox(height: 8),
          Text(
            _tr('Nel browser inserisci il percorso locale raggiungibile dal daemon.', 'In the browser, enter a local path accessible to the daemon.'),
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ],
    ),
    actions: [
      if (!kIsWeb)
        TextButton.icon(
          onPressed: _pickDirectory,
          icon: const Icon(Icons.folder_open_outlined),
          label: Text(_tr('Scegli cartella', 'Choose folder')),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(_tr('Annulla', 'Cancel')),
      ),
      FilledButton(
        onPressed: _controller.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _controller.text.trim()),
        child: Text(_tr('Crea', 'Create')),
      ),
    ],
  );
}

Future<void> createSession(
  BuildContext context,
  WidgetRef ref, {
  String? name,
  String? cwd,
}) async {
  final isItalian = ref.read(appLanguageProvider) == AppLanguage.it;
  final client = ref.read(pcpClientProvider);
  if (client == null) return;
  if (!await resolveDirtyRepository(
    context,
    ref,
    ref.read(activeSessionIdProvider),
  )) {
    return;
  }
  if (!context.mounted) return;

  var workingDirectory = cwd;
  if (workingDirectory == null) {
    final activeId = ref.read(activeSessionIdProvider);
    final initialDirectory = activeId == null
        ? ''
        : ref.read(sessionStateFamily(activeId)).cwd;
    workingDirectory = await _chooseSessionDirectory(context, initialDirectory);
  }
  if (!context.mounted) return;
  if (workingDirectory == null || workingDirectory.trim().isEmpty) return;

  try {
    final now = DateTime.now().millisecondsSinceEpoch;
    final result = await client.sendCommand(
      PcpCommand(
        protocol: 1,
        id: 'cmd_$now',
        ts: now,
        commandId: PcpClient.newCommandId('crt'),
        type: 'session.create',
        payload: {'name': ?name, 'cwd': workingDirectory.trim()},
      ),
    );
    if (!context.mounted) return;
    final data = (result['data'] as Map<String, dynamic>?) ?? result;
    final session = (data['session'] as Map<String, dynamic>?) ?? data;
    final id = (session['id'] ?? data['id']) as String?;
    if (id != null) {
      if (!await switchSessionSafely(context, ref, id)) return;
      ref.invalidate(sessionListProvider);
    }
  } catch (error) {
    if (context.mounted) {
      FrameSnackBar.show(context, message: isItalian ? 'Creazione non riuscita: $error' : 'Creation failed: $error');
    }
  }
}

Future<void> deleteSessionWithConfirmation(
  BuildContext context,
  WidgetRef ref, {
  required String sessionId,
  required String sessionName,
}) async {
  final isItalian = ref.read(appLanguageProvider) == AppLanguage.it;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final tokens = ctx.tokens;
      return AlertDialog(
        title: Row(
          children: [
            Icon(Icons.delete_outline, color: tokens.danger, size: 22),
            const SizedBox(width: 8),
            Expanded(child: Text(isItalian ? 'Elimina sessione' : 'Delete session')),
          ],
        ),
        content: Text(
          isItalian ? 'Sei sicuro di voler eliminare la sessione "$sessionName"?\nTutti i messaggi e la cronologia della sessione verranno eliminati definitivamente.' : 'Delete session "$sessionName"?\nAll messages and session history will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isItalian ? 'Annulla' : 'Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: tokens.danger,
              foregroundColor: tokens.surface,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isItalian ? 'Elimina' : 'Delete'),
          ),
        ],
      );
    },
  );

  if (confirmed != true || !context.mounted) return;

  final client = ref.read(pcpClientProvider);
  if (client == null) return;

  try {
    await client.deleteSession(sessionId);
    if (ref.read(activeSessionIdProvider) == sessionId) {
      ref.read(activeSessionIdProvider.notifier).state = null;
    }
    ref.read(pinnedSessionsProvider.notifier).unpin(sessionId);

    ref.invalidate(sessionListProvider);

    if (context.mounted) {
      FrameSnackBar.show(
        context,
        message: isItalian ? 'Sessione "$sessionName" eliminata.' : 'Session "$sessionName" deleted.',
      );
    }
  } catch (error) {
    if (context.mounted) {
      FrameSnackBar.show(
        context,
        message: isItalian ? 'Eliminazione non riuscita: $error' : 'Deletion failed: $error',
      );
    }
  }
}

Future<void> removeRepoWithConfirmation(
  BuildContext context,
  WidgetRef ref, {
  required String folder,
  required String repoName,
  required List<Map<String, dynamic>> folderSessions,
}) async {
  final isItalian = ref.read(appLanguageProvider) == AppLanguage.it;
  // Step 1: Choice dialog
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) {
      final tokens = ctx.tokens;
      return AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.folder_delete_outlined, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isItalian ? 'Rimuovi repository "$repoName"' : 'Remove repository "$repoName"',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isItalian ? 'Il repository contiene ${folderSessions.length} session${folderSessions.length == 1 ? 'e' : 'i'}. Scegli cosa desideri fare:' : 'This repository contains ${folderSessions.length} session${folderSessions.length == 1 ? '' : 's'}. Choose what to do:',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            InkWell(
              key: const ValueKey('hide-repo-only-btn'),
              onTap: () => Navigator.pop(ctx, 'hide'),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: tokens.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.visibility_off_outlined, color: tokens.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isItalian ? 'Rimuovi solo dalla vista' : 'Remove from view only',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isItalian ? 'Nasconde il repository dal pannello sessioni. Nessuna sessione viene eliminata dal disco.' : 'Hides the repository from the sessions panel. No sessions are deleted from disk.',
                            style: TextStyle(fontSize: 11, color: tokens.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            InkWell(
              key: const ValueKey('delete-all-repo-sessions-btn'),
              onTap: () => Navigator.pop(ctx, 'delete_all'),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: tokens.danger.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.delete_forever_outlined, color: tokens.danger),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isItalian ? 'Elimina repository e tutte le sessioni...' : 'Remove repository and delete all sessions...',
                            style: TextStyle(fontWeight: FontWeight.bold, color: tokens.danger, fontSize: 13),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isItalian ? 'Elimina definitivamente dal disco tutte le sessioni di questo repository.' : 'Permanently deletes all sessions for this repository from disk.',
                            style: TextStyle(fontSize: 11, color: tokens.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(isItalian ? 'Annulla' : 'Cancel'),
          ),
        ],
      );
    },
  );

  if (choice == null || !context.mounted) return;

  if (choice == 'hide') {
    ref.read(removedReposProvider.notifier).removeRepo(folder);
    ref.invalidate(sessionListProvider);
    if (context.mounted) {
      FrameSnackBar.show(
        context,
        message: isItalian ? 'Repository "$repoName" rimosso dal riquadro.' : 'Repository "$repoName" removed from the panel.',
        action: SnackBarAction(
          label: isItalian ? 'Ripristina' : 'Restore',
          onPressed: () {
            ref.read(removedReposProvider.notifier).restoreRepo(folder);
            ref.invalidate(sessionListProvider);
          },
        ),
      );
    }
    return;
  }

  if (choice == 'delete_all') {
    // Step 2: Second warning with type "delete" box
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DeleteRepoConfirmDialog(
        folder: folder,
        repoName: repoName,
        sessionsCount: folderSessions.length,
        isItalian: isItalian,
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final client = ref.read(pcpClientProvider);
    if (client == null) return;

    try {
      final activeId = ref.read(activeSessionIdProvider);
      for (final s in folderSessions) {
        final id = s['id'] as String?;
        if (id != null) {
          try {
            await client.deleteSession(id);
            if (id == activeId) {
              ref.read(activeSessionIdProvider.notifier).state = null;
            }
            ref.read(pinnedSessionsProvider.notifier).unpin(id);
          } catch (_) {}
        }
      }

      ref.read(removedReposProvider.notifier).removeRepo(folder);
      ref.invalidate(sessionListProvider);

      if (context.mounted) {
        FrameSnackBar.show(
          context,
          message: isItalian ? 'Tutte le sessioni di "$repoName" sono state eliminate.' : 'All sessions for "$repoName" were deleted.',
        );
      }
    } catch (error) {
      if (context.mounted) {
        FrameSnackBar.show(
          context,
          message: isItalian ? 'Errore durante l\'eliminazione: $error' : 'Deletion failed: $error',
        );
      }
    }
  }
}

class _DeleteRepoConfirmDialog extends StatefulWidget {
  final String folder;
  final String repoName;
  final int sessionsCount;
  final bool isItalian;

  const _DeleteRepoConfirmDialog({
    required this.folder,
    required this.repoName,
    required this.sessionsCount,
    required this.isItalian,
  });

  @override
  State<_DeleteRepoConfirmDialog> createState() =>
      _DeleteRepoConfirmDialogState();
}

class _DeleteRepoConfirmDialogState extends State<_DeleteRepoConfirmDialog> {
  final TextEditingController _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final canDelete = _textController.text.trim().toLowerCase() == 'delete';

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: tokens.danger, size: 24),
          const SizedBox(width: 8),
          Expanded(child: Text(widget.isItalian ? 'ATTENZIONE: Eliminazione' : 'WARNING: Deletion')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.isItalian ? 'Stai per eliminare definitivamente tutte le ${widget.sessionsCount} sessioni del repository:\n'
            '${widget.folder}\n\n'
            'Questa operazione cancellerà tutti i file di sessione e NON può essere annullata.\n\n'
            'Per confermare, digita "delete" nel campo sottostante:' : 'You are about to permanently delete all ${widget.sessionsCount} sessions for the repository:\n${widget.folder}\n\nThis will delete all session files and CANNOT be undone.\n\nTo confirm, type "delete" below:',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _textController,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'delete',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(widget.isItalian ? 'Annulla' : 'Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: tokens.danger,
            foregroundColor: tokens.surface,
          ),
          onPressed: canDelete ? () => Navigator.pop(context, true) : null,
          child: Text(widget.isItalian ? 'Elimina tutto' : 'Delete all'),
        ),
      ],
    );
  }
}

