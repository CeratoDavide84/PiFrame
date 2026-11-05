import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import '../../data/platform/platform_environment.dart';
import '../../data/language/language_settings.dart';

import 'mcp_servers_dialog.dart';
import '../../ui/frame_snack_bar.dart';

class PiCommandItem {
  final String label;
  final String command;
  final List<String> args;
  final String description;
  final IconData icon;
  final bool isPrimary;

  const PiCommandItem({
    required this.label,
    required this.command,
    required this.args,
    required this.description,
    required this.icon,
    this.isPrimary = false,
  });
}

const List<PiCommandItem> kBuiltinPiCommands = [
  PiCommandItem(
    label: 'Aggiorna Pi CLI',
    command: 'pi update',
    args: ['update'],
    description: "Aggiorna l'eseguibile di Pi all'ultima versione stabile disponibile.",
    icon: Icons.system_update_alt,
    isPrimary: true,
  ),
  PiCommandItem(
    label: 'Aggiorna Estensioni',
    command: 'pi update --extensions',
    args: ['update', '--extensions'],
    description: 'Aggiorna tutti i pacchetti ed estensioni utente installati.',
    icon: Icons.extension_outlined,
    isPrimary: true,
  ),
  PiCommandItem(
    label: 'Aggiorna Catalogo Modelli',
    command: 'pi update --models',
    args: ['update', '--models'],
    description: 'Sincronizza e aggiorna il catalogo dei modelli AI supportati.',
    icon: Icons.psychology_outlined,
  ),
  PiCommandItem(
    label: 'Aggiorna Tutto',
    command: 'pi update --all',
    args: ['update', '--all'],
    description: 'Aggiorna contemporaneamente Pi CLI e tutte le estensioni installate.',
    icon: Icons.auto_awesome,
  ),
  PiCommandItem(
    label: 'Elenco Estensioni',
    command: 'pi list',
    args: ['list'],
    description: 'Visualizza tutte le estensioni e i pacchetti utente attualmente installati.',
    icon: Icons.list_alt,
  ),
  PiCommandItem(
    label: 'Stato Server MCP',
    command: 'pi mcp list',
    args: ['mcp', 'list'],
    description: 'Verifica la connessione, lo stato e gli strumenti dei server MCP configurati.',
    icon: Icons.hub_outlined,
  ),
  PiCommandItem(
    label: 'Modelli Disponibili',
    command: 'pi --list-models',
    args: ['--list-models'],
    description: 'Elenca tutti i modelli LLM disponibili per il coding assistant.',
    icon: Icons.view_list_outlined,
  ),
  PiCommandItem(
    label: 'Versione Pi CLI',
    command: 'pi --version',
    args: ['--version'],
    description: 'Controlla la versione corrente di Pi installata nel sistema.',
    icon: Icons.info_outline,
  ),
];

class PiCliSection extends ConsumerStatefulWidget {
  final FrameTokens tokens;
  final VoidCallback? onRecheck;

  const PiCliSection({
    super.key,
    required this.tokens,
    this.onRecheck,
  });

  @override
  ConsumerState<PiCliSection> createState() => _PiCliSectionState();
}

class _PiCliSectionState extends ConsumerState<PiCliSection> {
  String _tr(String it, String en) => ref.read(appLanguageProvider) == AppLanguage.it ? it : en;
  (String, String) _commandText(PiCommandItem item) {
    if (ref.read(appLanguageProvider) == AppLanguage.it) return (item.label, item.description);
    return switch (item.command) {
      'pi update' => ('Update Pi CLI', 'Update Pi to the latest stable version.'),
      'pi update --extensions' => ('Update extensions', 'Update all installed user packages and extensions.'),
      'pi update --models' => ('Update model catalog', 'Synchronize and update the supported AI model catalog.'),
      'pi update --all' => ('Update all', 'Update Pi CLI and all installed extensions.'),
      'pi list' => ('List extensions', 'Show all installed user extensions and packages.'),
      'pi mcp list' => ('MCP server status', 'Check connections, status and tools of configured MCP servers.'),
      'pi --list-models' => ('Available models', 'List available LLM models for the coding assistant.'),
      'pi --version' => ('Pi CLI version', 'Check the installed Pi version.'),
      _ => (item.label, item.description),
    };
  }
  final TextEditingController _customCmdController = TextEditingController();
  final ScrollController _logScrollController = ScrollController();

  bool _isExecuting = false;
  String? _currentCommand;
  String _consoleOutput = '';
  int? _exitCode;
  DateTime? _startTime;
  Duration? _executionDuration;
  Process? _activeProcess;

  @override
  void dispose() {
    _customCmdController.dispose();
    _logScrollController.dispose();
    _activeProcess?.kill();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _executeCommand(String displayCmd, List<String> args) async {
    if (_isExecuting) return;
    // Shell commands run on the host only; the browser cannot spawn processes.
    if (kIsWeb) {
      setState(() {
        _consoleOutput =
            _tr('I comandi Pi sono disponibili solo nell\'app desktop.', 'Pi commands are available only in the desktop app.');
        _exitCode = -1;
      });
      return;
    }

    setState(() {
      _isExecuting = true;
      _currentCommand = displayCmd;
      _consoleOutput = '\$ $displayCmd\n';
      _exitCode = null;
      _startTime = DateTime.now();
      _executionDuration = null;
    });

    try {
      final Process process;
      final piExe = PlatformEnvironment.findExecutable('pi');
      if (Platform.isWindows) {
        process = await Process.start(
          'cmd.exe',
          ['/c', piExe ?? 'pi', ...args],
          environment: PlatformEnvironment.environment,
          runInShell: true,
        );
      } else {
        if (piExe != null) {
          process = await Process.start(
            piExe,
            args,
            environment: PlatformEnvironment.environment,
            runInShell: false,
          );
        } else {
          process = await Process.start(
            'pi',
            args,
            environment: PlatformEnvironment.environment,
            runInShell: true,
          );
        }
      }

      _activeProcess = process;

      final stdoutSub = process.stdout
          .transform(utf8.decoder)
          .listen((data) {
        if (!mounted) return;
        setState(() {
          _consoleOutput += data;
        });
        _scrollToBottom();
      });

      final stderrSub = process.stderr
          .transform(utf8.decoder)
          .listen((data) {
        if (!mounted) return;
        setState(() {
          _consoleOutput += data;
        });
        _scrollToBottom();
      });

      final code = await process.exitCode;
      await stdoutSub.cancel();
      await stderrSub.cancel();

      if (!mounted) return;
      final duration = _startTime != null
          ? DateTime.now().difference(_startTime!)
          : null;

      setState(() {
        _exitCode = code;
        _isExecuting = false;
        _activeProcess = null;
        _executionDuration = duration;
        _consoleOutput += '\n[Processo completato con codice $code in ${duration?.inMilliseconds ?? 0}ms]\n';
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isExecuting = false;
        _activeProcess = null;
        _exitCode = -1;
        _consoleOutput += _tr('\nErrore durante l\'esecuzione del comando: $e\n', '\nCommand failed: $e\n');
      });
      _scrollToBottom();
    }
  }

  void _runCustomCommand() {
    final raw = _customCmdController.text.trim();
    if (raw.isEmpty) return;

    final parts = raw.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return;

    final display = 'pi $raw';
    _executeCommand(display, parts);
  }

  void _copyConsoleOutput() {
    if (_consoleOutput.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _consoleOutput));
    FrameSnackBar.show(
      context,
      message: _tr('Output del comando copiato negli appunti', 'Command output copied to clipboard'),
      duration: const Duration(seconds: 2),
    );
  }

  void _clearConsoleOutput() {
    setState(() {
      _consoleOutput = '';
      _currentCommand = null;
      _exitCode = null;
      _executionDuration = null;
    });
  }

  void _cancelActiveProcess() {
    if (_activeProcess != null) {
      _activeProcess!.kill();
      setState(() {
        _consoleOutput += _tr('\n[Comando interrotto dall\'utente]\n', '\n[Command stopped by user]\n');
        _isExecuting = false;
        _activeProcess = null;
      });
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appLanguageProvider);
    final tokens = widget.tokens;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Title & Description
        Row(
          children: [
            Icon(Icons.terminal, color: tokens.accent, size: 22),
            const SizedBox(width: 10),
            Text(
              _tr('Interfaccia Pi CLI', 'Pi CLI interface'),
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _tr('Esegui comandi e aggiornamenti ufficiali di Pi Coding Agent direttamente da PiFrame.', 'Run official Pi Coding Agent commands and updates directly from PiFrame.'),
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 20),

        // Section: Fast Commands Grid
        Text(
          _tr('COMANDI RAPIDI', 'QUICK COMMANDS'),
          style: TextStyle(
            color: tokens.displayText,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final cmd in kBuiltinPiCommands)
              _buildActionCard(tokens, cmd),
          ],
        ),

        const SizedBox(height: 24),

        // Section: Custom Command Line
        Text(
          _tr('COMANDO PERSONALIZZATO', 'CUSTOM COMMAND'),
          style: TextStyle(
            color: tokens.displayText,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: tokens.surfaceElevated,
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            border: Border.all(color: tokens.border),
          ),
          child: Row(
            children: [
              Text(
                'pi ',
                style: TextStyle(
                  color: tokens.accent,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  fontFamily: tokens.monoFontFamily,
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _customCmdController,
                  enabled: !_isExecuting,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 13,
                    fontFamily: tokens.monoFontFamily,
                  ),
                  decoration: InputDecoration(
                    hintText: _tr('es. update --force, auth check, mcp login <server>...', 'e.g. update --force, auth check, mcp login <server>...'),
                    hintStyle: TextStyle(
                      color: tokens.textMuted,
                      fontSize: 12,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onSubmitted: (_) => _runCustomCommand(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: tokens.accent,
                  foregroundColor: tokens.surface,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                  ),
                ),
                onPressed: _isExecuting ? null : _runCustomCommand,
                icon: const Icon(Icons.play_arrow, size: 16),
                label: Text(_tr('Esegui', 'Run')),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Console Output Window
        Row(
          children: [
            Text(
              _tr('OUTPUT CONSOLE', 'CONSOLE OUTPUT'),
              style: TextStyle(
                color: tokens.displayText,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(width: 10),
            if (_isExecuting) ...[
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: tokens.accent,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _tr('In esecuzione ${_currentCommand ?? ""}...', 'Running ${_currentCommand ?? ""}...'),
                style: TextStyle(color: tokens.accent, fontSize: 11),
              ),
              const Spacer(),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: tokens.danger,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _cancelActiveProcess,
                icon: const Icon(Icons.stop, size: 14),
                label: Text(_tr('Interrompi', 'Stop')),
              ),
            ] else if (_exitCode != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _exitCode == 0
                      ? tokens.success.withValues(alpha: 0.15)
                      : tokens.danger.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                  border: Border.all(
                    color: _exitCode == 0 ? tokens.success : tokens.danger,
                  ),
                ),
                child: Text(
                  _exitCode == 0 ? _tr('Successo (0)', 'Success (0)') : _tr('Codice $_exitCode', 'Exit code $_exitCode'),
                  style: TextStyle(
                    color: _exitCode == 0 ? tokens.success : tokens.danger,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_executionDuration != null) ...[
                const SizedBox(width: 8),
                Text(
                  '${(_executionDuration!.inMilliseconds / 1000).toStringAsFixed(2)}s',
                  style: TextStyle(color: tokens.textMuted, fontSize: 11),
                ),
              ],
              const Spacer(),
            ] else
              const Spacer(),
            if (_consoleOutput.isNotEmpty) ...[
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                tooltip: _tr('Copia output', 'Copy output'),
                icon: const Icon(Icons.copy, size: 15),
                onPressed: _copyConsoleOutput,
              ),
              const SizedBox(width: 6),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                tooltip: _tr('Cancella output', 'Clear output'),
                icon: const Icon(Icons.clear_all, size: 16),
                onPressed: _clearConsoleOutput,
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),

        Container(
          height: 240,
          decoration: BoxDecoration(
            color: tokens.chassis,
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            border: Border.all(color: tokens.borderStrong),
          ),
          child: _consoleOutput.isEmpty && !_isExecuting
              ? Center(
                  child: Text(
                    _tr('Nessun output. Seleziona un comando sopra o digita un comando personalizzato per iniziare.', 'No output. Select a command above or enter a custom command to get started.'),
                    style: TextStyle(color: tokens.textMuted, fontSize: 12),
                  ),
                )
              : Scrollbar(
                  controller: _logScrollController,
                  child: SingleChildScrollView(
                    controller: _logScrollController,
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      _consoleOutput,
                      style: TextStyle(
                        color: tokens.displayText,
                        fontSize: 12,
                        height: 1.4,
                        fontFamily: tokens.monoFontFamily,
                      ),
                    ),
                  ),
                ),
        ),

        const SizedBox(height: 24),

        // System verification footer
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            border: Border.all(color: tokens.border),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle_outline, size: 18, color: tokens.success),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _tr('PiFrame utilizza il comando `pi` configurato nel PATH di sistema.', 'PiFrame uses the `pi` command configured in the system PATH.'),
                  style: TextStyle(color: tokens.textMuted, fontSize: 12),
                ),
              ),
              if (widget.onRecheck != null)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.refresh, size: 14),
                  label: Text(_tr('Ricontrolla', 'Check again')),
                  onPressed: widget.onRecheck,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionCard(FrameTokens tokens, PiCommandItem item) {
    final isSelected = _currentCommand == item.command;
    final isRunning = isSelected && _isExecuting;
    final isMcpCard = item.command == 'pi mcp list';

    final cardContent = Container(
      width: 440,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: item.isPrimary
            ? tokens.surfaceElevated
            : tokens.surface,
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        border: Border.all(
          color: isMcpCard
              ? tokens.syntaxFunction.withValues(alpha: 0.5)
              : item.isPrimary
                  ? tokens.accent.withValues(alpha: 0.5)
                  : tokens.border,
          width: (item.isPrimary || isMcpCard) ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isMcpCard
                      ? tokens.syntaxFunction.withValues(alpha: 0.15)
                      : item.isPrimary
                          ? tokens.accent.withValues(alpha: 0.15)
                          : tokens.displaySurface,
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                ),
                child: Icon(
                  item.icon,
                  size: 16,
                  color: isMcpCard
                      ? tokens.syntaxFunction
                      : item.isPrimary
                          ? tokens.accent
                          : tokens.displayText,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _commandText(item).$1,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.command,
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: 11,
                        fontFamily: tokens.monoFontFamily,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isMcpCard) ...[
                OutlinedButton(
                  key: const ValueKey('btn-manage-mcp-servers'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: tokens.syntaxFunction,
                    side: BorderSide(color: tokens.syntaxFunction.withValues(alpha: 0.5)),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                    ),
                  ),
                  onPressed: () => McpServersDialog.show(context, tokens),
                  child: Text(_tr('Gestisci', 'Manage'), style: const TextStyle(fontSize: 11)),
                ),
                const SizedBox(width: 6),
              ],
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: item.isPrimary
                      ? tokens.accent
                      : tokens.surfaceElevated,
                  foregroundColor: item.isPrimary
                      ? tokens.surface
                      : tokens.textPrimary,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    side: item.isPrimary
                        ? BorderSide.none
                        : BorderSide(color: tokens.border),
                  ),
                ),
                onPressed: _isExecuting
                    ? null
                    : () => _executeCommand(item.command, item.args),
                icon: isRunning
                    ? SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: item.isPrimary
                              ? tokens.surface
                              : tokens.accent,
                        ),
                      )
                    : const Icon(Icons.play_arrow, size: 14),
                label: Text(isRunning ? _tr('In corso...', 'Running...') : _tr('Esegui', 'Run')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _commandText(item).$2,
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: 12,
              height: 1.3,
            ),
          ),
        ],
      ),
    );

    if (isMcpCard) {
      return Material(
        key: const ValueKey('pi-cli-card-pi-mcp-list'),
        type: MaterialType.transparency,
        child: Tooltip(
          message: _tr('Clicca sulla scheda per visualizzare e abilitare/disabilitare i server MCP', 'Click the card to view and enable or disable MCP servers'),
          child: InkWell(
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            onTap: () => McpServersDialog.show(context, tokens),
            child: cardContent,
          ),
        ),
      );
    }

    return cardContent;
  }
}
