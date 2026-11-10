import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import 'instruction_file_dialog.dart';
import 'session_actions.dart';
import '../../data/daemon/daemon_providers.dart';
import '../../data/language/language_settings.dart';
import '../../ui/frame_snack_bar.dart';
import '../../ui/shimmer_border.dart';
import '../command_palette/command_palette.dart';
import '../session_tree/session_tree_dialog.dart';
import '../workspace/repository_workspace.dart';
import 'pinned_sessions_provider.dart';
import 'removed_repos_provider.dart';
import 'project_archive_provider.dart';
import '../../domain/session/agent_status.dart';
import '../../data/update/update_providers.dart';

bool _isSubsession(Map<String, dynamic> session) {
  if (session['isSubsession'] == true) return true;
  final parentSession = (session['parentSession'] ?? '').toString().trim();
  if (parentSession.isNotEmpty) return true;
  final name = (session['name'] ?? '').toString().toLowerCase();
  final id = (session['id'] ?? '').toString().toLowerCase();
  return name.contains('worker#') ||
      id.contains('worker#') ||
      name.contains('#') ||
      id.contains('#') ||
      name.startsWith('subagent') ||
      id.startsWith('subagent');
}

bool _isWorkerSession(Map<String, dynamic> session) => _isSubsession(session);

String _sessionFolder(Map<String, dynamic> session) {
  final gitRoot = (session['gitRoot'] ?? '').toString().trim();
  return gitRoot.isNotEmpty ? gitRoot : (session['cwd'] ?? '').toString();
}

String _folderName(String path) {
  final segments = path
      .replaceAll('\\', '/')
      .split('/')
      .where((part) => part.isNotEmpty);
  return segments.isEmpty ? 'Sessioni' : segments.last;
}

class SessionsSidebar extends ConsumerStatefulWidget {
  final VoidCallback? onSessionSelected;
  final VoidCallback? onCollapse;

  const SessionsSidebar({
    super.key,
    this.onSessionSelected,
    this.onCollapse,
  });

  @override
  ConsumerState<SessionsSidebar> createState() => _SessionsSidebarState();
}

class _SessionsSidebarState extends ConsumerState<SessionsSidebar> {
  String _tr(String it, String en) =>
      ref.read(appLanguageProvider) == AppLanguage.it ? it : en;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _filterMode = 'all'; // 'all', 'active', 'repo'
  bool _creating = false;
  final Set<String> _expandedFolders = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _showRenameDialog(String sessionId, String currentName) async {
    final tokens = context.tokens;
    final textController = TextEditingController(text: currentName);

    String? newName;
    try {
      newName = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: tokens.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            side: BorderSide(color: tokens.border, width: 1),
          ),
          title: Text(
            _tr('Rinomina Sessione', 'Rename session'),
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: TextField(
            controller: textController,
            autofocus: true,
            style: TextStyle(color: tokens.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: _tr('Nome sessione...', 'Session name...'),
              hintStyle: TextStyle(color: tokens.textMuted, fontSize: 13),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: tokens.border),
                borderRadius: BorderRadius.circular(tokens.radiusSm),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: tokens.accent),
                borderRadius: BorderRadius.circular(tokens.radiusSm),
              ),
            ),
            onSubmitted: (val) => Navigator.of(ctx).pop(val.trim()),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: tokens.textMuted),
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(_tr('Annulla', 'Cancel')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: tokens.accent,
                foregroundColor: tokens.surface,
              ),
              onPressed: () => Navigator.of(ctx).pop(textController.text.trim()),
              child: Text(_tr('Salva', 'Save')),
            ),
          ],
        ),
      );
    } finally {
      textController.dispose();
    }

    if (newName != null && newName.isNotEmpty && newName != currentName) {
      final client = ref.read(pcpClientProvider);
      if (client != null) {
        try {
          await client.renameSession(sessionId, newName);
          ref.invalidate(sessionListProvider);
          if (mounted) {
            FrameSnackBar.show(
              context,
              message: _tr('Sessione rinominata in "$newName"', 'Session renamed to "$newName"'),
            );
          }
        } catch (e) {
          if (mounted) {
            FrameSnackBar.show(
              context,
              message: _tr('Errore rinomina: $e', 'Rename failed: $e'),
              backgroundColor: tokens.danger,
            );
          }
        }
      }
    }
  }

  Future<void> _cloneSession(String sessionId) async {
    final tokens = context.tokens;
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
      final res = await client.cloneSession(sessionId);
      if (!mounted || !context.mounted) return;
      final data = res['data'] as Map<String, dynamic>? ?? res;
      final newSid = data['sessionId'] as String? ?? data['id'] as String?;
      if (newSid != null) {
        if (!await switchSessionSafely(context, ref, newSid)) return;
        ref.invalidate(sessionListProvider);
        if (mounted) {
          FrameSnackBar.show(
            context,
            message: _tr('Sessione duplicata: $newSid', 'Session duplicated: $newSid'),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        FrameSnackBar.show(
          context,
          message: _tr('Errore duplicazione: $e', 'Duplication failed: $e'),
          backgroundColor: tokens.danger,
        );
      }
    }
  }

  Future<void> _createProject() async {
    if (_creating) return;
    setState(() => _creating = true);
    await createSession(context, ref);
    if (mounted) {
      setState(() => _creating = false);
      widget.onSessionSelected?.call();
    }
  }

  Future<void> _renameProject(String folder, String currentName) async {
    final controller = TextEditingController(text: currentName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_tr('Rinomina progetto', 'Rename project')),
        content: TextField(controller: controller, autofocus: true, onSubmitted: (value) => Navigator.pop(ctx, value.trim())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_tr('Annulla', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: Text(_tr('Salva', 'Save'))),
        ],
      ),
    );
    controller.dispose();
    if (mounted && name != null && name.isNotEmpty) {
      ref.read(projectArchiveProvider.notifier).renameProject(folder, name);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appLanguageProvider);
    final tokens = context.tokens;
    final sessionsAsync = ref.watch(sessionListProvider);
    final activeId = ref.watch(activeSessionIdProvider);
    final activeSessionCwd = activeId != null
        ? ref.watch(sessionStateFamily(activeId).select((s) => s.cwd))
        : '';

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: tokens.surface,
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: tokens.border, width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _tr('Sessioni', 'Sessions'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 18,
                      height: 1.1,
                      fontFamily: tokens.headingFontFamily,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.refresh, color: tokens.textMuted, size: 18),
                  tooltip: _tr('Aggiorna sessioni', 'Refresh sessions'),
                  onPressed: () {
                    ref.invalidate(sessionListProvider);
                    final active = ref.read(activeSessionIdProvider);
                    if (active != null) {
                      ref.read(pcpClientProvider)?.attach(active);
                    }
                  },
                ),
                IconButton(
                  icon: Icon(Icons.add, color: tokens.accent, size: 20),
                  tooltip: _tr('Nuova Sessione', 'New session'),
                  onPressed: _creating || ref.watch(pcpClientProvider) == null
                      ? null
                      : () async {
                          setState(() => _creating = true);
                          await createSession(context, ref);
                          if (mounted) {
                            setState(() => _creating = false);
                            widget.onSessionSelected?.call();
                          }
                        },
                ),
                if (widget.onCollapse != null)
                  IconButton(
                    icon: Icon(Icons.chevron_left, color: tokens.textMuted, size: 20),
                    tooltip: _tr('Collassa barra sessioni', 'Collapse sessions sidebar'),
                    onPressed: widget.onCollapse,
                  ),
              ],
            ),
          ),

          // Search Field
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: tokens.border, width: 1),
              ),
            ),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: tokens.textPrimary, fontSize: 12),
              decoration: InputDecoration(
                isDense: true,
                hintText: _tr('Cerca sessioni...', 'Search sessions...'),
                hintStyle: TextStyle(color: tokens.textMuted, fontSize: 12),
                prefixIcon: Icon(
                  Icons.search,
                  size: 16,
                  color: tokens.textMuted,
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 28,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.clear,
                          size: 14,
                          color: tokens.textMuted,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 24,
                        ),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                filled: true,
                fillColor: tokens.surfaceElevated,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                  borderSide: BorderSide(color: tokens.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                  borderSide: BorderSide(color: tokens.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                  borderSide: BorderSide(color: tokens.accent),
                ),
              ),
            ),
          ),

          // Filter Chips
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: tokens.border, width: 1),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('all', _tr('Tutte', 'All'), tokens),
                  const SizedBox(width: 6),
                  _buildFilterChip('active', _tr('Gestite', 'Managed'), tokens),
                  const SizedBox(width: 6),
                  _buildFilterChip('repo', _tr('Questo repo', 'This repo'), tokens),
                  const SizedBox(width: 6),
                  _buildFilterChip('archived', _tr('Archivio', 'Archive'), tokens),
                ],
              ),
            ),
          ),

          // Session list
          Expanded(
            child: sessionsAsync.when(
              data: (allSessions) {
                final removedRepos = ref.watch(removedReposProvider);
                final archive = ref.watch(projectArchiveProvider);

                // Apply search and filter
                final filtered = allSessions.where((s) {
                  if (_isWorkerSession(s)) return false;
                  final folder = _sessionFolder(s);
                  final sessionId = (s['id'] ?? '').toString();
                  final isArchived = archive.projects.contains(folder) || archive.sessions.contains(sessionId);
                  if ((_filterMode == 'archived') != isArchived) return false;
                  if (_searchQuery.isEmpty && removedRepos.contains(folder)) {
                    return false;
                  }
                  final id = (s['id'] as String? ?? '').toLowerCase();
                  final name = (s['name'] as String? ?? '').toLowerCase();
                  final cwd = (s['cwd'] as String? ?? '').toLowerCase();
                  final preview = (s['lastMessagePreview'] as String? ?? '')
                      .toLowerCase();
                  final isActive = s['isActive'] == true;

                  // Text search
                  if (_searchQuery.isNotEmpty) {
                    final match =
                        id.contains(_searchQuery) ||
                        name.contains(_searchQuery) ||
                        (archive.names[folder] ?? '').toLowerCase().contains(_searchQuery) ||
                        cwd.contains(_searchQuery) ||
                        preview.contains(_searchQuery);
                    if (!match) return false;
                  }

                  // Mode filter
                  if (_filterMode == 'active' && !isActive) {
                    return false;
                  }
                  if (_filterMode == 'repo' && activeSessionCwd.isNotEmpty) {
                    var activeGroup = activeSessionCwd;
                    for (final candidate in allSessions) {
                      if (candidate['id'] == activeId) {
                        activeGroup = _sessionFolder(candidate);
                        break;
                      }
                    }
                    if (_sessionFolder(s) != activeGroup) return false;
                  }

                  return true;
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        _searchQuery.isNotEmpty || _filterMode != 'all'
                            ? _tr('Nessuna sessione corrisponde ai filtri', 'No sessions match the filters')
                            : _tr('Nessuna sessione trovata', 'No sessions found'),
                        style: TextStyle(color: tokens.textMuted, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final pinnedIds = ref.watch(pinnedSessionsProvider);
                final pinnedSessions = allSessions.where((s) {
                  if (_isWorkerSession(s)) return false;
                  final folder = _sessionFolder(s);
                  if (archive.projects.contains(folder) || archive.sessions.contains((s['id'] ?? '').toString())) return false;
                  if (_searchQuery.isEmpty && removedRepos.contains(folder)) {
                    return false;
                  }
                  final id = s['id'] as String? ?? '';
                  return pinnedIds.contains(id);
                }).toList();

                final activeFolders = <String>{};
                for (final s in allSessions) {
                  if (s['isActive'] == true) {
                    activeFolders.add(_sessionFolder(s));
                  }
                }

                final grouped = <String, List<Map<String, dynamic>>>{};
                for (final session in filtered) {
                  grouped
                      .putIfAbsent(_sessionFolder(session), () => [])
                      .add(session);
                }
                final rows =
                    <({String? folder, Map<String, dynamic>? session, bool isFolder, bool isPinnedHeader, bool isPinnedSession})>[];

                // Pinned sessions section on top (if not filtering)
                if (_searchQuery.isEmpty && _filterMode == 'all' && pinnedSessions.isNotEmpty) {
                  rows.add((folder: null, session: null, isFolder: false, isPinnedHeader: true, isPinnedSession: false));
                  for (final session in pinnedSessions) {
                    rows.add((folder: null, session: session, isFolder: false, isPinnedHeader: false, isPinnedSession: true));
                  }
                }

                for (final group in grouped.entries) {
                  rows.add((folder: group.key, session: null, isFolder: true, isPinnedHeader: false, isPinnedSession: false));
                  final isExpanded = _expandedFolders.contains(group.key) ||
                      _searchQuery.isNotEmpty;
                  if (isExpanded) {
                    rows.addAll(
                      group.value.map(
                        (session) => (folder: null, session: session, isFolder: false, isPinnedHeader: false, isPinnedSession: false),
                      ),
                    );
                  }
                }

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 8, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _tr('PROGETTI', 'PROJECTS'),
                              style: TextStyle(
                                color: tokens.textMuted,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            key: const ValueKey('new-project-session'),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              foregroundColor: tokens.textSecondary,
                            ),
                            onPressed: _creating ? null : _createProject,
                            icon: const Icon(Icons.add, size: 14),
                            label: Text(
                              _tr('Nuovo progetto', 'New project'),
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  itemCount: rows.length,
                  itemBuilder: (rowContext, index) {
                    final row = rows[index];
                    if (row.isPinnedHeader) {
                      final hasWorkingPinned = pinnedSessions.any((s) {
                        final sId = s['id'] as String? ?? '';
                        return ref.watch(sessionStateFamily(sId).select((st) =>
                            st.agentStatus == AgentStatus.working ||
                            st.isStreaming ||
                            st.activeToolCalls.isNotEmpty));
                      });
                      final hasActivePinned = hasWorkingPinned ||
                          pinnedSessions.any((s) => s['isActive'] == true);

                      return Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                        child: Row(
                          children: [
                            Icon(Icons.push_pin, size: 13, color: tokens.accent),
                            const SizedBox(width: 6),
                            Text(
                              _tr('FISSATE (${pinnedSessions.length})', 'PINNED (${pinnedSessions.length})'),
                              style: TextStyle(
                                color: tokens.textSecondary,
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            if (hasWorkingPinned) ...[
                              const SizedBox(width: 6),
                              _WorkingDot(color: tokens.agentWorking, size: 7),
                            ] else if (hasActivePinned) ...[
                              const SizedBox(width: 6),
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: tokens.accent,
                                  boxShadow: [
                                    BoxShadow(
                                      color: tokens.accent.withValues(alpha: 0.6),
                                      blurRadius: 4,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }

                    if (row.isFolder) {
                      final folder = row.folder ?? '';
                      final expanded = _expandedFolders.contains(folder);
                      final hasActive = activeFolders.contains(folder);
                      final folderSessions = grouped[folder] ?? [];
                      final hasWorking = folderSessions.any((s) {
                        final sId = s['id'] as String? ?? '';
                        final isSel = sId == activeId;
                        final isPin = pinnedIds.contains(sId);
                        final isAct = s['isActive'] == true;
                        if (isSel || isPin || isAct) {
                          final isWorking = ref.watch(sessionStateFamily(sId).select((st) =>
                              st.agentStatus == AgentStatus.working ||
                              st.agentStatus == AgentStatus.retrying ||
                              st.agentStatus == AgentStatus.compacting ||
                              st.isStreaming ||
                              st.activeToolCalls.isNotEmpty));
                          if (isWorking) {
                            return true;
                          }
                        }
                        return s['status'] == 'working' || s['isStreaming'] == true;
                      });

                      Widget folderTile = ListTile(
                        key: ValueKey('session-folder:$folder'),
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        minLeadingWidth: 18,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                        ),
                        leading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              expanded
                                  ? Icons.folder_open_outlined
                                  : Icons.folder_outlined,
                              size: 16,
                              color: hasWorking
                                  ? tokens.agentWorking
                                  : (hasActive
                                      ? tokens.accent
                                      : tokens.accent.withValues(alpha: 0.8)),
                            ),
                            if (hasWorking) ...[
                              const SizedBox(width: 4),
                              Container(
                                key: ValueKey('folder-working-dot:$folder'),
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: tokens.agentWorking,
                                ),
                              ),
                            ] else if (hasActive) ...[
                              const SizedBox(width: 4),
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: tokens.accent,
                                ),
                              ),
                            ],
                          ],
                        ),
                        title: Text(
                          archive.names[folder] ?? _folderName(folder),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              key: ValueKey('repo-new-session-btn-$folder'),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              style: IconButton.styleFrom(
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                minimumSize: const Size(20, 20),
                                padding: EdgeInsets.zero,
                              ),
                              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                              icon: Icon(Icons.add, size: 14, color: tokens.accent),
                              tooltip: _tr('Nuova sessione in questa cartella', 'New session in this folder'),
                              onPressed: () async {
                                setState(() => _expandedFolders.add(folder));
                                await createSession(context, ref, cwd: folder);
                                if (mounted) widget.onSessionSelected?.call();
                              },
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              expanded ? Icons.expand_more : Icons.chevron_right,
                              size: 16,
                              color: tokens.textMuted,
                            ),
                          ],
                        ),
                        onTap: () => setState(() {
                          if (expanded) {
                            _expandedFolders.remove(folder);
                          } else {
                            _expandedFolders.add(folder);
                          }
                        }),
                      );

                      folderTile = GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onSecondaryTapDown: (details) async {
                          final pos = details.globalPosition;
                          final action = await showMenu<String>(
                            context: context,
                            color: tokens.surfaceElevated,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(tokens.radiusSm),
                              side: BorderSide(color: tokens.border),
                            ),
                            position: RelativeRect.fromLTRB(
                              pos.dx,
                              pos.dy,
                              pos.dx + 1,
                              pos.dy + 1,
                            ),
                            items: [
                              PopupMenuItem(value: 'rename_project', child: Text(_tr('Rinomina progetto', 'Rename project'))),
                              PopupMenuItem(value: 'archive_project', child: Text(archive.projects.contains(folder) ? _tr('Ripristina progetto', 'Restore project') : _tr('Archivia progetto', 'Archive project'))),
                              PopupMenuItem(
                                value: 'instructions',
                                height: 32,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.description_outlined,
                                      size: 14,
                                      color: tokens.textSecondary,
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        _tr('Istruzioni repository', 'Repository instructions'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: tokens.textPrimary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'new_session',
                                height: 32,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.add,
                                      size: 14,
                                      color: tokens.accent,
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        _tr('Nuova sessione', 'New session'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: tokens.textPrimary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const PopupMenuDivider(height: 1),
                              PopupMenuItem(
                                value: 'remove_repo',
                                height: 32,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.close,
                                      size: 14,
                                      color: tokens.danger,
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        _tr('Rimuovi repository dal riquadro', 'Remove repository from sidebar'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: tokens.danger,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );

                          if (!context.mounted || action == null) return;
                          if (action == 'rename_project') {
                            await _renameProject(folder, archive.names[folder] ?? _folderName(folder));
                          } else if (action == 'archive_project') {
                            ref.read(projectArchiveProvider.notifier).toggleProject(folder);
                          } else if (action == 'instructions') {
                            final activeSid = activeFolders.contains(folder) ? activeId : null;
                            InstructionFileDialog.show(context, folder: folder, sessionId: activeSid);
                          } else if (action == 'new_session') {
                            setState(() => _expandedFolders.add(folder));
                            await createSession(context, ref, cwd: folder);
                            if (mounted) widget.onSessionSelected?.call();
                          } else if (action == 'remove_repo') {
                            removeRepoWithConfirmation(
                              context,
                              ref,
                              folder: folder,
                              repoName: _folderName(folder),
                              folderSessions: folderSessions,
                            );
                          }
                        },
                        child: folderTile,
                      );

                      return Tooltip(
                        message: folder,
                        child: Material(
                          color: tokens.surface,
                          child: folderTile,
                        ),
                      );
                    }

                    final s = row.session!;
                    final id = s['id'] as String? ?? 's';
                    final isSelected = id == activeId;
                    final isPinned = pinnedIds.contains(id);

                    return _SessionTile(
                      session: s,
                      isPinned: isPinned,
                      isPinnedSection: row.isPinnedSession,
                      isSelected: isSelected,
                      isArchived: archive.sessions.contains(id),
                      onArchive: () => ref.read(projectArchiveProvider.notifier).toggleSession(id),
                      onTap: () async {
                        if (await switchSessionSafely(context, ref, id)) {
                          widget.onSessionSelected?.call();
                        }
                      },
                      onPinToggle: () => ref
                          .read(pinnedSessionsProvider.notifier)
                          .togglePin(id),
                      onRename: (sId, sName) => _showRenameDialog(sId, sName),
                      onTree: (sId) =>
                          SessionTreeDialog.show(context, sessionId: sId),
                      onClone: (sId) => _cloneSession(sId),
                      onInstructions: (sId, folder) => InstructionFileDialog.show(
                        context,
                        folder: folder,
                        sessionId: sId,
                      ),
                      onRemoveRepo: (folder) => removeRepoWithConfirmation(
                        context,
                        ref,
                        folder: folder,
                        repoName: _folderName(folder),
                        folderSessions: grouped[folder] ?? [s],
                      ),
                      onDelete: (sId, sName) => deleteSessionWithConfirmation(
                        context,
                        ref,
                        sessionId: sId,
                        sessionName: sName,
                      ),
                    );
                  },
                      ),
                    ),
                  ],
                );
              },
              loading: () => Center(
                child: CircularProgressIndicator(
                  color: tokens.accent,
                  strokeWidth: 2,
                ),
              ),
              error: (err, _) => Center(
                child: Text(
                  _tr('Errore: $err', 'Error: $err'),
                  style: TextStyle(color: tokens.danger, fontSize: 12),
                ),
              ),
            ),
          ),

          // Bottom utility bar: Command Palette & Settings
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: tokens.border, width: 1)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: tokens.textSecondary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      alignment: Alignment.centerLeft,
                    ),
                    icon: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(Icons.settings_outlined, size: 16),
                        if (ref.watch(hasUpdateBadgeProvider))
                          Positioned(
                            top: -2,
                            right: -2,
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: tokens.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                    label: Text(
                      _tr('Impostazioni', 'Settings'),
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: () {
                      ref.read(showSettingsProvider.notifier).state = true;
                    },
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.search, size: 16, color: tokens.textMuted),
                  tooltip: _tr('Tavolozza comandi (Ctrl+K)', 'Command palette (Ctrl+K)'),
                  onPressed: () {
                    CommandPalette.show(
                      context,
                      onOpenSettings: () {
                        ref.read(showSettingsProvider.notifier).state = true;
                      },
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

  Widget _buildFilterChip(String mode, String label, FrameTokens tokens) {
    final isSelected = _filterMode == mode;
    return Semantics(
      selected: isSelected,
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: isSelected ? tokens.displayText : tokens.textPrimary,
          backgroundColor: isSelected
              ? tokens.surfaceElevated
              : tokens.surface.withValues(alpha: 0),
          side: BorderSide(
            color: isSelected ? tokens.focusRing : tokens.border,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusSm),
          ),
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 9),
          textStyle: TextStyle(
            fontSize: 11,
            fontFamily: tokens.uiFontFamily,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        onPressed: () => setState(() => _filterMode = mode),
        child: Text(label),
      ),
    );
  }
}

class _WorkingDot extends StatefulWidget {
  final Color color;
  final double size;

  const _WorkingDot({
    required this.color,
    this.size = 8.0,
  });

  @override
  State<_WorkingDot> createState() => _WorkingDotState();
}

class _WorkingDotState extends State<_WorkingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    final isTest =
        WidgetsBinding.instance.runtimeType.toString().contains('Test');
    if (!isTest) {
      _controller.repeat(reverse: true);
    }
    _pulse = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = _controller.isAnimating ? _pulse.value : 1.0;
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: 0.75 + 0.25 * scale),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.65 * scale),
                blurRadius: 5.0 * scale,
                spreadRadius: 1.2 * scale,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SessionTile extends ConsumerWidget {
  final Map<String, dynamic> session;
  final bool isPinned;
  final bool isPinnedSection;
  final bool isSelected;
  final bool isArchived;
  final VoidCallback onArchive;
  final VoidCallback onTap;
  final VoidCallback onPinToggle;
  final void Function(String id, String name) onRename;
  final void Function(String id) onTree;
  final void Function(String id) onClone;
  final void Function(String id, String folder)? onInstructions;
  final void Function(String folder)? onRemoveRepo;
  final void Function(String id, String name)? onDelete;

  const _SessionTile({
    required this.session,
    required this.isPinned,
    required this.isPinnedSection,
    required this.isSelected,
    required this.isArchived,
    required this.onArchive,
    required this.onTap,
    required this.onPinToggle,
    required this.onRename,
    required this.onTree,
    required this.onClone,
    this.onInstructions,
    this.onRemoveRepo,
    this.onDelete,
  });

  List<PopupMenuEntry<String>> _buildMenuItems(
    BuildContext context,
    FrameTokens tokens,
    bool isItalian,
  ) {
    return [
      PopupMenuItem(
        value: 'pin',
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPinned ? Icons.push_pin_outlined : Icons.push_pin,
              size: 14,
              color: tokens.accent,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                isPinned ? (isItalian ? 'Rimuovi dai fissati' : 'Unpin') : (isItalian ? 'Fissa in cima' : 'Pin to top'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'instructions',
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.description_outlined,
              size: 14,
              color: tokens.textSecondary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                isItalian ? 'Istruzioni repository' : 'Repository instructions',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'rename',
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.edit_outlined,
              size: 14,
              color: tokens.textSecondary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                isItalian ? 'Rinomina' : 'Rename',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'archive',
        child: Text(isArchived
            ? (isItalian ? 'Ripristina sessione' : 'Restore session')
            : (isItalian ? 'Archivia sessione' : 'Archive session')),
      ),
      PopupMenuItem(
        value: 'tree',
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_tree_outlined,
              size: 14,
              color: tokens.textSecondary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                isItalian ? 'Albero rami' : 'Branch tree',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'clone',
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.copy_outlined,
              size: 14,
              color: tokens.textSecondary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                isItalian ? 'Duplica' : 'Duplicate',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
      const PopupMenuDivider(height: 1),
      if (onRemoveRepo != null) ...[
        PopupMenuItem(
          value: 'remove_repo',
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.close,
                size: 14,
                color: tokens.textSecondary,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  isItalian ? 'Rimuovi repository dal riquadro' : 'Remove repository from sidebar',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
      PopupMenuItem(
        value: 'delete',
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.delete_outline,
              size: 14,
              color: tokens.danger,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                isItalian ? 'Elimina sessione' : 'Delete session',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.danger,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  void _handleAction(
    String action,
    String id,
    String name,
    String folder,
  ) {
    if (action == 'pin') {
      onPinToggle();
    } else if (action == 'instructions') {
      onInstructions?.call(id, folder);
    } else if (action == 'rename') {
      onRename(id, name);
    } else if (action == 'archive') {
      onArchive();
    } else if (action == 'tree') {
      onTree(id);
    } else if (action == 'clone') {
      onClone(id);
    } else if (action == 'remove_repo') {
      onRemoveRepo?.call(folder);
    } else if (action == 'delete') {
      onDelete?.call(id, name);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isItalian = ref.watch(appLanguageProvider) == AppLanguage.it;
    final tokens = context.tokens;
    final id = session['id'] as String? ?? 's';
    final name = session['name'] as String? ?? id;
    final cwd = session['cwd'] as String? ?? '';
    final preview = session['lastMessagePreview'] as String?;
    final isStaticActive = session['isActive'] == true;
    final folder = _sessionFolder(session);

    final isWorking = (isPinned || isSelected || isStaticActive)
        ? ref.watch(sessionStateFamily(id).select((s) =>
            s.agentStatus == AgentStatus.working ||
            s.agentStatus == AgentStatus.retrying ||
            s.agentStatus == AgentStatus.compacting ||
            s.isStreaming ||
            s.activeToolCalls.isNotEmpty))
        : (session['status'] == 'working' || session['isStreaming'] == true);

    final tile = ListTile(
      selected: isSelected,
      selectedColor: tokens.displayText,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      dense: true,
      visualDensity: VisualDensity.compact,
      minVerticalPadding: 0,
      minLeadingWidth: 14,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 0,
      ),
      leading: isWorking
          ? _WorkingDot(color: tokens.agentWorking)
          : Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? tokens.displayText
                    : (isStaticActive
                        ? tokens.agentSettled
                        : tokens.textMuted.withValues(
                            alpha: 0.5,
                          )),
                border: Border.all(color: tokens.borderStrong),
              ),
            ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isSelected ? tokens.displayText : tokens.textPrimary,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          if (isPinned) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.push_pin,
              size: 11,
              color: tokens.accent,
            ),
          ],
        ],
      ),
      trailing: PopupMenuButton<String>(
        tooltip: isItalian ? 'Azioni sessione' : 'Session actions',
        icon: Icon(
          Icons.more_horiz,
          size: 18,
          color: isSelected ? tokens.displayText : tokens.textMuted,
        ),
        color: tokens.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          side: BorderSide(color: tokens.border),
        ),
        onSelected: (action) => _handleAction(action, id, name, folder),
        itemBuilder: (ctx) => _buildMenuItems(ctx, tokens, isItalian),
      ),
      onTap: onTap,
    );

    final card = Material(
      color: isSelected
          ? tokens.displaySurface
          : tokens.surfaceElevated.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        side: BorderSide(
          color: isSelected ? tokens.focusRing : tokens.border,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: tile,
    );

    final interactiveCard = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) async {
        final pos = details.globalPosition;
        final action = await showMenu<String>(
          context: context,
          color: tokens.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            side: BorderSide(color: tokens.border),
          ),
          position: RelativeRect.fromLTRB(
            pos.dx,
            pos.dy,
            pos.dx + 1,
            pos.dy + 1,
          ),
          items: _buildMenuItems(context, tokens, isItalian),
        );
        if (action != null) {
          _handleAction(action, id, name, folder);
        }
      },
      child: Tooltip(
        message: preview != null && preview.isNotEmpty ? preview : cwd,
        child: card,
      ),
    );

    if (isWorking) {
      return Padding(
        padding: EdgeInsets.only(
          left: isPinnedSection ? 4 : 14,
          right: 4,
          bottom: 1,
        ),
        child: ShimmerBorder(
          isActive: true,
          strokeWidth: 1.0,
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          child: interactiveCard,
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        left: isPinnedSection ? 4 : 14,
        right: 4,
        bottom: 1,
      ),
      child: interactiveCard,
    );
  }
}


