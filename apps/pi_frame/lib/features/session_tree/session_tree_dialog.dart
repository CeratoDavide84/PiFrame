import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../data/language/language_settings.dart';

class SessionTreeDialog extends ConsumerStatefulWidget {
  final String sessionId;

  const SessionTreeDialog({super.key, required this.sessionId});

  static Future<void> show(BuildContext context, {required String sessionId}) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => SessionTreeDialog(sessionId: sessionId),
    );
  }

  @override
  ConsumerState<SessionTreeDialog> createState() => _SessionTreeDialogState();
}

class _SessionTreeDialogState extends ConsumerState<SessionTreeDialog> {
  String _tr(String it, String en) => ref.read(appLanguageProvider) == AppLanguage.it ? it : en;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _treeData;

  @override
  void initState() {
    super.initState();
    _loadTree();
  }

  Future<void> _loadTree() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final client = ref.read(pcpClientProvider);
    if (client == null) {
      setState(() {
        _loading = false;
        _error = _tr('Daemon non connesso', 'Daemon disconnected');
      });
      return;
    }

    try {
      final res = await client.getSessionTree(widget.sessionId);
      final data = res['data'] as Map<String, dynamic>? ?? res;
      setState(() {
        _loading = false;
        _treeData = data;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appLanguageProvider);
    final tokens = context.tokens;

    return Dialog(
      backgroundColor: tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        side: BorderSide(color: tokens.border, width: 1),
      ),
      child: Container(
        width: 600,
        height: 520,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.account_tree_outlined,
                      color: tokens.accent,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _tr('Albero della Sessione', 'Session tree'),
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: Icon(Icons.close, color: tokens.textMuted, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _tr('Sessione: ${widget.sessionId}', 'Session: ${widget.sessionId}'),
              style: TextStyle(color: tokens.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Divider(color: tokens.border, height: 1),
            const SizedBox(height: 12),

            // Content
            Expanded(child: _buildBody(tokens)),

            const SizedBox(height: 12),
            Divider(color: tokens.border, height: 1),
            const SizedBox(height: 12),

            // Footer
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: tokens.accent),
                  icon: const Icon(Icons.refresh, size: 14),
                  label: Text(_tr('Ricarica', 'Reload'), style: const TextStyle(fontSize: 12)),
                  onPressed: _loadTree,
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: tokens.accent,
                    foregroundColor: tokens.surface,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(_tr('Chiudi', 'Close'), style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(FrameTokens tokens) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: tokens.accent, strokeWidth: 2),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: tokens.danger, size: 28),
            const SizedBox(height: 8),
            Text(
              _tr('Errore: $_error', 'Error: $_error'),
              style: TextStyle(color: tokens.danger, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final treeList =
        _treeData?['tree'] as List<dynamic>? ??
        _treeData?['nodes'] as List<dynamic>? ??
        [];

    if (treeList.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.device_hub, color: tokens.textMuted, size: 36),
            const SizedBox(height: 10),
            Text(
              _tr('Nessun ramo secondario per questa sessione.', 'No secondary branches for this session.'),
              style: TextStyle(color: tokens.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              _tr('Tutti i messaggi appartengono al ramo principale.', 'All messages belong to the main branch.'),
              style: TextStyle(color: tokens.textMuted, fontSize: 11),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: treeList.length,
      itemBuilder: (context, index) {
        final node = treeList[index];
        final nodeMap = node is Map<String, dynamic>
            ? node
            : <String, dynamic>{};
        final nodeId = nodeMap['id']?.toString() ?? 'nodo_$index';
        final role = nodeMap['role']?.toString() ?? 'entry';
        final summary =
            nodeMap['summary']?.toString() ??
            nodeMap['text']?.toString() ??
            nodeId;
        final isLeaf = nodeMap['isLeaf'] == true;
        final isActive = nodeMap['isActive'] == true;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isActive ? tokens.surfaceElevated : tokens.surface,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            border: Border.all(
              color: isActive ? tokens.accent : tokens.border,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isActive
                    ? Icons.radio_button_checked
                    : (isLeaf ? Icons.nature : Icons.commit),
                color: isActive ? tokens.accent : tokens.textMuted,
                size: 16,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          role.toUpperCase(),
                          style: TextStyle(
                            color: tokens.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: tokens.surfaceElevated,
                              borderRadius: BorderRadius.circular(
                                tokens.radiusSm,
                              ),
                              border: Border.all(color: tokens.border),
                            ),
                            child: Text(
                              _tr('ATTIVO', 'ACTIVE'),
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: tokens.textPrimary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Text(
                nodeId.length > 8 ? nodeId.substring(0, 8) : nodeId,
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
