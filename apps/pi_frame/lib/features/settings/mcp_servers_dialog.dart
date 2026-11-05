import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/language/language_settings.dart';
import '../../ui/frame_snack_bar.dart';

class McpServerItem {
  final String name;
  final String scope;
  final String sourcePath;
  final bool enabled;
  final String transport;
  final String state;
  final List<String> tools;
  final String? description;
  final String? error;

  const McpServerItem({
    required this.name,
    this.scope = 'global',
    required this.sourcePath,
    this.enabled = true,
    this.transport = '',
    this.state = 'unknown',
    this.tools = const [],
    this.description,
    this.error,
  });

  McpServerItem copyWith({
    String? name,
    String? scope,
    String? sourcePath,
    bool? enabled,
    String? transport,
    String? state,
    List<String>? tools,
    String? description,
    String? error,
  }) {
    return McpServerItem(
      name: name ?? this.name,
      scope: scope ?? this.scope,
      sourcePath: sourcePath ?? this.sourcePath,
      enabled: enabled ?? this.enabled,
      transport: transport ?? this.transport,
      state: state ?? this.state,
      tools: tools ?? this.tools,
      description: description ?? this.description,
      error: error ?? this.error,
    );
  }
}

class McpServersDialog extends ConsumerStatefulWidget {
  final FrameTokens tokens;
  final String? projectDir;
  final List<McpServerItem>? initialServers;

  const McpServersDialog({
    super.key,
    required this.tokens,
    this.projectDir,
    this.initialServers,
  });

  static Future<void> show(
    BuildContext context,
    FrameTokens tokens, {
    String? projectDir,
    List<McpServerItem>? initialServers,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => McpServersDialog(
        tokens: tokens,
        projectDir: projectDir,
        initialServers: initialServers,
      ),
    );
  }

  @override
  ConsumerState<McpServersDialog> createState() => _McpServersDialogState();
}

class _McpServersDialogState extends ConsumerState<McpServersDialog> {
  bool _isLoading = true;
  String? _errorMessage;
  List<McpServerItem> _servers = [];
  final Set<String> _togglingServers = {};
  final Set<String> _expandedTools = {};

  String _tr(String it, String en) =>
      ref.read(appLanguageProvider) == AppLanguage.it ? it : en;

  @override
  void initState() {
    super.initState();
    if (widget.initialServers != null) {
      _servers = List.from(widget.initialServers!);
      _isLoading = false;
    } else {
      _loadServers();
    }
  }

  String _getGlobalMcpConfigPath() {
    if (kIsWeb) return '';
    final home = Platform.isWindows
        ? (Platform.environment['USERPROFILE'] ??
              Platform.environment['HOME'] ??
              '')
        : (Platform.environment['HOME'] ?? '');
    return p.join(home, '.pi', 'agent', 'mcp.json');
  }

  Future<void> _loadServers() async {
    // MCP configuration lives on the host machine: browsers can only report
    // the servers the daemon already exposes.
    if (kIsWeb) {
      setState(() {
        _isLoading = false;
        _errorMessage = _tr(
          'La configurazione MCP è disponibile solo su desktop.',
          'MCP configuration is available on desktop only.',
        );
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final globalPath = _getGlobalMcpConfigPath();
      final serversMap = <String, McpServerItem>{};

      // 1. Read global config file directly
      final globalFile = File(globalPath);
      if (await globalFile.exists()) {
        try {
          final content = await globalFile.readAsString();
          final parsed = jsonDecode(content);
          if (parsed is Map && parsed['mcpServers'] is Map) {
            final mcpServers = parsed['mcpServers'] as Map;
            for (final entry in mcpServers.entries) {
              final name = entry.key.toString();
              final conf = entry.value;
              if (conf is Map) {
                final isEnabled =
                    conf['enabled'] != false && conf['disabled'] != true;
                final desc = conf['description']?.toString();
                final cmd =
                    conf['command']?.toString() ??
                    conf['url']?.toString() ??
                    '';
                final args = conf['args'] is List
                    ? (conf['args'] as List).map((e) => e.toString()).join(' ')
                    : '';
                final transport = args.isNotEmpty ? '$cmd $args' : cmd;

                serversMap[name] = McpServerItem(
                  name: name,
                  scope: 'global',
                  sourcePath: globalPath,
                  enabled: isEnabled,
                  transport: transport,
                  state: isEnabled ? 'unknown' : 'disabled',
                  description: desc,
                );
              }
            }
          }
        } catch (e) {
          debugPrint('Error parsing $globalPath: $e');
        }
      }

      // 2. Read local project config if available
      if (widget.projectDir != null && widget.projectDir!.isNotEmpty) {
        final projectPath = p.join(widget.projectDir!, '.pi', 'mcp.json');
        final projectFile = File(projectPath);
        if (await projectFile.exists()) {
          try {
            final content = await projectFile.readAsString();
            final parsed = jsonDecode(content);
            if (parsed is Map && parsed['mcpServers'] is Map) {
              final mcpServers = parsed['mcpServers'] as Map;
              for (final entry in mcpServers.entries) {
                final name = entry.key.toString();
                final conf = entry.value;
                if (conf is Map) {
                  final isEnabled =
                      conf['enabled'] != false && conf['disabled'] != true;
                  final desc = conf['description']?.toString();
                  final cmd =
                      conf['command']?.toString() ??
                      conf['url']?.toString() ??
                      '';
                  final args = conf['args'] is List
                      ? (conf['args'] as List)
                            .map((e) => e.toString())
                            .join(' ')
                      : '';
                  final transport = args.isNotEmpty ? '$cmd $args' : cmd;

                  // Project entry overrides global entry with same name
                  serversMap[name] = McpServerItem(
                    name: name,
                    scope: 'project',
                    sourcePath: projectPath,
                    enabled: isEnabled,
                    transport: transport.isNotEmpty
                        ? transport
                        : (serversMap[name]?.transport ?? ''),
                    state: isEnabled ? 'unknown' : 'disabled',
                    description: desc ?? serversMap[name]?.description,
                  );
                }
              }
            }
          } catch (e) {
            debugPrint('Error parsing $projectPath: $e');
          }
        }
      }

      // 3. Try to query live status from `pi mcp list --json`
      try {
        final result = Platform.isWindows
            ? await Process.run('cmd.exe', [
                '/c',
                'pi',
                'mcp',
                'list',
                '--json',
              ]).timeout(const Duration(seconds: 4))
            : await Process.run('pi', [
                'mcp',
                'list',
                '--json',
              ]).timeout(const Duration(seconds: 4));

        if (result.stdout != null) {
          final rawOutput = result.stdout.toString().trim();
          if (rawOutput.isNotEmpty) {
            final decoded = jsonDecode(rawOutput);
            if (decoded is Map && decoded['servers'] is List) {
              for (final item in decoded['servers'] as List) {
                if (item is Map) {
                  final name = item['name']?.toString() ?? '';
                  if (name.isEmpty) continue;

                  final enabled = item['enabled'] == true;
                  final state =
                      item['state']?.toString() ??
                      (enabled ? 'connected' : 'disabled');
                  final transport = item['transport']?.toString() ?? '';
                  final source = item['source']?.toString() ?? globalPath;
                  final scope = item['scope']?.toString() ?? 'global';
                  final error = item['error']?.toString();

                  final toolsList = <String>[];
                  if (item['tools'] is List) {
                    for (final t in item['tools'] as List) {
                      toolsList.add(t.toString());
                    }
                  }

                  final existing = serversMap[name];
                  serversMap[name] = McpServerItem(
                    name: name,
                    scope: scope,
                    sourcePath: source,
                    enabled: enabled,
                    transport: transport.isNotEmpty
                        ? transport
                        : (existing?.transport ?? ''),
                    state: state,
                    tools: toolsList.isNotEmpty
                        ? toolsList
                        : (existing?.tools ?? const []),
                    description: existing?.description,
                    error: error,
                  );
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Note: pi mcp list --json unavailable: $e');
      }

      if (mounted) {
        setState(() {
          _servers = serversMap.values.toList()
            ..sort((a, b) => a.name.compareTo(b.name));
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = _tr(
            'Impossibile caricare i server MCP: $e',
            'Unable to load MCP servers: $e',
          );
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleServer(McpServerItem server, bool newEnabled) async {
    setState(() {
      _togglingServers.add(server.name);
      final idx = _servers.indexWhere((s) => s.name == server.name);
      if (idx != -1) {
        _servers[idx] = _servers[idx].copyWith(
          enabled: newEnabled,
          state: newEnabled ? 'enabled' : 'disabled',
        );
      }
    });

    try {
      final file = File(server.sourcePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        final parsed = jsonDecode(content);
        if (parsed is Map) {
          final mcpServers =
              (parsed['mcpServers'] as Map?) ?? <String, dynamic>{};
          if (mcpServers.containsKey(server.name)) {
            final conf = mcpServers[server.name];
            if (conf is Map) {
              conf['enabled'] = newEnabled;
              conf.remove('disabled');
            }
          } else {
            mcpServers[server.name] = <String, dynamic>{'enabled': newEnabled};
          }
          parsed['mcpServers'] = mcpServers;
          await file.writeAsString(
            const JsonEncoder.withIndent('  ').convert(parsed),
          );
        }
      }
    } catch (e) {
      debugPrint(
        'Error updating server ${server.name} in ${server.sourcePath}: $e',
      );
      if (mounted) {
        FrameSnackBar.show(
          context,
          message: _tr('Errore nel salvataggio: $e', 'Save failed: $e'),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _togglingServers.remove(server.name);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appLanguageProvider);
    final tokens = widget.tokens;
    final enabledCount = _servers.where((s) => s.enabled).length;

    return Dialog(
      backgroundColor: tokens.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        side: BorderSide(color: tokens.borderStrong, width: 1.2),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 650),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: tokens.syntaxFunction.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                    ),
                    child: Icon(
                      Icons.hub_outlined,
                      size: 20,
                      color: tokens.syntaxFunction,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _tr(
                            'Server MCP disponibili',
                            'Available MCP servers',
                          ),
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _tr(
                            'Configura e attiva o disattiva i server MCP per il coding agent.',
                            'Configure and enable or disable MCP servers for the coding agent.',
                          ),
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: _tr('Aggiorna elenco', 'Refresh list'),
                    icon: Icon(
                      Icons.refresh,
                      size: 18,
                      color: tokens.textMuted,
                    ),
                    onPressed: _isLoading ? null : _loadServers,
                  ),
                  IconButton(
                    tooltip: _tr('Chiudi', 'Close'),
                    icon: Icon(Icons.close, size: 18, color: tokens.textMuted),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Divider(color: tokens.border, height: 1),
              const SizedBox(height: 12),

              // Content Area
              Expanded(
                child: _isLoading
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: tokens.accent,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _tr(
                                'Caricamento server MCP in corso...',
                                'Loading MCP servers...',
                              ),
                              style: TextStyle(
                                color: tokens.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      )
                    : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: tokens.danger,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      )
                    : _servers.isEmpty
                    ? _buildEmptyState(tokens)
                    : ListView.separated(
                        itemCount: _servers.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final server = _servers[index];
                          return _buildServerCard(tokens, server);
                        },
                      ),
              ),

              const SizedBox(height: 12),
              Divider(color: tokens.border, height: 1),
              const SizedBox(height: 12),

              // Footer
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _servers.isEmpty
                        ? _tr('0 server', '0 servers')
                        : _tr(
                            '$enabledCount su ${_servers.length} server attivi',
                            '$enabledCount of ${_servers.length} servers enabled',
                          ),
                    style: TextStyle(
                      color: tokens.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: tokens.accent,
                      foregroundColor: tokens.surface,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(_tr('Chiudi', 'Close')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(FrameTokens tokens) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.dns_outlined,
              size: 40,
              color: tokens.textMuted.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              _tr('Nessun server MCP configurato', 'No MCP servers configured'),
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _tr(
                'Aggiungi un server con "pi mcp add <nome> -- <comando>"\noppure modifica ~/.pi/agent/mcp.json.',
                'Add a server with "pi mcp add <name> -- <command>"\nor edit ~/.pi/agent/mcp.json.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerCard(FrameTokens tokens, McpServerItem server) {
    final isToggling = _togglingServers.contains(server.name);
    final isToolsExpanded = _expandedTools.contains(server.name);

    final statusColor = !server.enabled
        ? tokens.textMuted
        : server.state == 'connected'
        ? tokens.success
        : server.state == 'failed'
        ? tokens.danger
        : tokens.accent;

    final statusLabel = !server.enabled
        ? _tr('Disabilitato', 'Disabled')
        : server.state == 'connected'
        ? _tr('Connesso', 'Connected')
        : server.state == 'failed'
        ? _tr('Non connesso', 'Disconnected')
        : _tr('Abilitato', 'Enabled');

    return Container(
      decoration: BoxDecoration(
        color: server.enabled
            ? tokens.surface
            : tokens.surface.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        border: Border.all(
          color: server.enabled ? tokens.borderStrong : tokens.border,
          width: server.enabled ? 1.2 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // Checkbox to enable/disable
                SizedBox(
                  width: 24,
                  height: 24,
                  child: isToggling
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: tokens.accent,
                            ),
                          ),
                        )
                      : Checkbox(
                          key: ValueKey('mcp-checkbox-${server.name}'),
                          value: server.enabled,
                          activeColor: tokens.accent,
                          checkColor: tokens.surface,
                          side: BorderSide(
                            color: tokens.borderStrong,
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              tokens.radiusSm,
                            ),
                          ),
                          onChanged: (val) {
                            if (val != null) {
                              _toggleServer(server, val);
                            }
                          },
                        ),
                ),
                const SizedBox(width: 8),

                // Name & Badges
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          server.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: server.enabled
                                ? tokens.textPrimary
                                : tokens.textMuted,
                            fontFamily: tokens.monoFontFamily,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Status Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                          border: Border.all(
                            color: statusColor.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          statusLabel,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),

                      if (server.scope == 'project') ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.syntaxKeyword.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(
                              tokens.radiusSm,
                            ),
                            border: Border.all(
                              color: tokens.syntaxKeyword.withValues(
                                alpha: 0.3,
                              ),
                            ),
                          ),
                          child: Text(
                            'Progetto',
                            style: TextStyle(
                              color: tokens.syntaxKeyword,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Tool count chip / toggle
                if (server.tools.isNotEmpty)
                  InkWell(
                    onTap: () {
                      setState(() {
                        if (isToolsExpanded) {
                          _expandedTools.remove(server.name);
                        } else {
                          _expandedTools.add(server.name);
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.build_outlined,
                            size: 12,
                            color: tokens.syntaxFunction,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${server.tools.length} tool',
                            style: TextStyle(
                              color: tokens.syntaxFunction,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            isToolsExpanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            size: 14,
                            color: tokens.textMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Description if present
          if (server.description != null && server.description!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(44, 0, 12, 6),
              child: Text(
                server.description!,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
            ),

          // Transport snippet
          if (server.transport.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(44, 0, 12, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: tokens.surfaceElevated,
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                  border: Border.all(color: tokens.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        server.transport,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: 10,
                          fontFamily: tokens.monoFontFamily,
                        ),
                      ),
                    ),
                    Tooltip(
                      message: _tr('Copia comando', 'Copy command'),
                      child: InkWell(
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(text: server.transport),
                          );
                          FrameSnackBar.show(
                            context,
                            message: _tr('Comando copiato', 'Command copied'),
                            duration: const Duration(seconds: 1),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Icon(
                            Icons.copy_outlined,
                            size: 12,
                            color: tokens.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Expandable Tools list
          if (isToolsExpanded && server.tools.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(44, 0, 12, 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: tokens.surfaceElevated,
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                border: Border.all(color: tokens.border),
              ),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final tool in server.tools)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: tokens.syntaxFunction.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                        border: Border.all(
                          color: tokens.syntaxFunction.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        tool,
                        style: TextStyle(
                          color: tokens.syntaxFunction,
                          fontSize: 10,
                          fontFamily: tokens.monoFontFamily,
                        ),
                      ),
                    ),
                ],
              ),
            ),

          // Error box if present
          if (server.error != null && server.error!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(44, 0, 12, 8),
              child: Text(
                server.error!,
                style: TextStyle(color: tokens.danger, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}
