import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:xterm/xterm.dart';

import '../../data/terminal/terminal_settings.dart';
import '../../data/language/language_settings.dart';

class TerminalTabSession {
  final String id;
  String title;
  final String shellName;
  final Terminal terminal;
  Process? process;
  bool isRunning = false;
  int? exitCode;
  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;

  final List<String> history = [];
  String currentInput = '';
  int historyIndex = -1;

  TerminalTabSession({
    required this.id,
    required this.title,
    required this.shellName,
    required this.terminal,
  });

  void dispose() {
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    try {
      process?.kill();
    } catch (_) {}
  }

  void handleInput(String data) {
    // Handle Ctrl+C (character code 3)
    if (data == '\x03') {
      try {
        process?.stdin.add([3]);
      } catch (_) {}
      terminal.write('^C\r\n');
      currentInput = '';
      historyIndex = history.length;
      return;
    }

    // Handle Ctrl+L (character code 12 - form feed / clear screen)
    if (data == '\x0c') {
      terminal.buffer.clear();
      terminal.setCursor(0, 0);
      return;
    }

    // Handle Arrow Up (\x1b[A)
    if (data == '\x1b[A') {
      if (history.isNotEmpty) {
        if (historyIndex == -1 || historyIndex > history.length) {
          historyIndex = history.length;
        }
        if (historyIndex > 0) {
          historyIndex--;
          _replaceCurrentLine(history[historyIndex]);
        }
      }
      return;
    }

    // Handle Arrow Down (\x1b[B)
    if (data == '\x1b[B') {
      if (history.isNotEmpty && historyIndex < history.length - 1) {
        historyIndex++;
        _replaceCurrentLine(history[historyIndex]);
      } else if (historyIndex == history.length - 1) {
        historyIndex = history.length;
        _replaceCurrentLine('');
      }
      return;
    }

    // Process character sequence
    for (int i = 0; i < data.length; i++) {
      final char = data[i];
      final code = char.codeUnitAt(0);

      // Backspace (\x08 or \x7f)
      if (code == 8 || code == 127) {
        if (currentInput.isNotEmpty) {
          currentInput = currentInput.substring(0, currentInput.length - 1);
          terminal.write('\b \b');
        }
      }
      // Enter (\r or \n)
      else if (code == 10 || code == 13) {
        terminal.write('\r\n');
        final lineToSend = currentInput;
        currentInput = '';
        if (lineToSend.trim().isNotEmpty) {
          history.add(lineToSend);
        }
        historyIndex = history.length;
        try {
          process?.stdin.writeln(lineToSend);
        } catch (_) {}
      }
      // Tab (\t)
      else if (code == 9) {
        currentInput += '\t';
        terminal.write('\t');
      }
      // Skip ANSI escape codes starting with 27
      else if (code == 27) {
        continue;
      }
      // Regular printable characters
      else if (code >= 32) {
        currentInput += char;
        terminal.write(char);
      }
    }
  }

  void _replaceCurrentLine(String newLine) {
    if (currentInput.isNotEmpty) {
      terminal.write('\b \b' * currentInput.length);
    }
    currentInput = newLine;
    terminal.write(newLine);
  }

  void sendCommand(String command) {
    final trimmed = command.trim();
    if (trimmed.isNotEmpty) {
      history.add(trimmed);
      historyIndex = history.length;
    }
    terminal.write('$command\r\n');
    try {
      process?.stdin.writeln(command);
    } catch (_) {}
  }
}

class IntegratedTerminalPanel extends ConsumerStatefulWidget {
  final String cwd;
  final FrameTokens tokens;
  final VoidCallback onCollapseDownward;
  final VoidCallback onClose;

  const IntegratedTerminalPanel({
    super.key,
    required this.cwd,
    required this.tokens,
    required this.onCollapseDownward,
    required this.onClose,
  });

  @override
  ConsumerState<IntegratedTerminalPanel> createState() =>
      _IntegratedTerminalPanelState();
}

class _IntegratedTerminalPanelState
    extends ConsumerState<IntegratedTerminalPanel> {
  String _tr(String it, String en) =>
      ref.read(appLanguageProvider) == AppLanguage.it ? it : en;
  final List<TerminalTabSession> _tabs = [];
  int _activeTabIndex = 0;
  int _counter = 0;
  late final FocusNode _terminalFocusNode;

  @override
  void initState() {
    super.initState();
    _terminalFocusNode = FocusNode();
    _createNewTab();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _terminalFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _terminalFocusNode.dispose();
    for (final tab in _tabs) {
      tab.dispose();
    }
    super.dispose();
  }

  TerminalTheme _buildTerminalTheme(FrameTokens tokens) {
    return TerminalTheme(
      cursor: tokens.accent,
      selection: tokens.accent.withValues(alpha: 0.35),
      foreground: tokens.displayText,
      background: tokens.chassis,
      black: tokens.surface,
      white: tokens.displayText,
      red: tokens.danger,
      green: tokens.success,
      yellow: tokens.warning,
      blue: tokens.info,
      magenta: tokens.accent,
      cyan: tokens.info,
      brightBlack: tokens.textMuted,
      brightRed: tokens.danger,
      brightGreen: tokens.success,
      brightYellow: tokens.warning,
      brightBlue: tokens.info,
      brightMagenta: tokens.accent,
      brightCyan: tokens.info,
      brightWhite: tokens.textPrimary,
      searchHitBackground: tokens.accent.withValues(alpha: 0.3),
      searchHitBackgroundCurrent: tokens.accent.withValues(alpha: 0.6),
      searchHitForeground: tokens.displayText,
    );
  }

  Map<String, String>? _parseWslPath(String path) {
    final normalized =
        path.trim().replaceFirst(RegExp(r'^[\\/]+'), '//').replaceAll('\\', '/');
    final match = RegExp(
      r'^//(wsl(?:\.localhost|\$))/([^/]+)(?:/(.*))?$',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (match == null) return null;
    final distro = match.group(2)!;
    final rest = match.group(3) ?? '';
    final linuxPath = '/$rest'.replaceAll(RegExp(r'/+'), '/');
    return {
      'distro': distro,
      'linuxPath': linuxPath.length > 1 && linuxPath.endsWith('/')
          ? linuxPath.substring(0, linuxPath.length - 1)
          : linuxPath,
    };
  }

  void _createNewTab({String? preferredShell}) {
    _counter++;
    final String shellExe;
    final List<String> shellArgs;
    final String shellName;

    if (Platform.isWindows) {
      final wslInfo = _parseWslPath(widget.cwd);
      final shouldUseWsl = preferredShell == 'wsl' ||
          (preferredShell == null && wslInfo != null);

      if (shouldUseWsl && wslInfo != null) {
        shellExe = 'wsl.exe';
        shellArgs = ['-d', wslInfo['distro']!, '--cd', wslInfo['linuxPath']!];
        shellName = 'WSL (${wslInfo['distro']})';
      } else if (preferredShell == 'cmd') {
        shellExe = 'cmd.exe';
        shellArgs = ['/k'];
        shellName = 'cmd';
      } else {
        shellExe = 'powershell.exe';
        shellArgs = ['-NoLogo'];
        shellName = 'PowerShell';
      }
    } else if (Platform.isMacOS) {
      final envShell = Platform.environment['SHELL'] ?? '/bin/zsh';
      shellExe = envShell;
      shellArgs = ['-l'];
      shellName = envShell.split('/').last;
    } else {
      final envShell = Platform.environment['SHELL'] ?? '/bin/bash';
      shellExe = envShell;
      shellArgs = ['-i'];
      shellName = envShell.split('/').last;
    }

    final terminal = Terminal(
      maxLines: 10000,
    );

    final session = TerminalTabSession(
      id: 'term_$_counter',
      title: '$shellName $_counter',
      shellName: shellName,
      terminal: terminal,
    );

    setState(() {
      _tabs.add(session);
      _activeTabIndex = _tabs.length - 1;
    });
    _terminalFocusNode.requestFocus();

    _startProcessForTab(session, shellExe, shellArgs);
  }

  Future<void> _startProcessForTab(
    TerminalTabSession session,
    String executable,
    List<String> args,
  ) async {
    final isWsl = executable.toLowerCase() == 'wsl.exe';
    final effectiveCwd = !isWsl &&
            widget.cwd.isNotEmpty &&
            Directory(widget.cwd).existsSync()
        ? widget.cwd
        : Directory.current.path;

    final displayDir = isWsl && widget.cwd.isNotEmpty ? widget.cwd : effectiveCwd;
    session.terminal.write(
      _tr('Avvio sessione terminale in: $displayDir\r\n\r\n', 'Starting terminal session in: $displayDir\r\n\r\n'),
    );

    try {
      final process = await Process.start(
        executable,
        args,
        workingDirectory: isWsl ? null : effectiveCwd,
        runInShell: false,
      );

      session.process = process;
      session.isRunning = true;

      session.terminal.onOutput = (data) {
        session.handleInput(data);
      };

      session._stdoutSub = process.stdout.listen((bytes) {
        if (!mounted) return;
        session.terminal.write(utf8.decode(bytes, allowMalformed: true));
      });

      session._stderrSub = process.stderr.listen((bytes) {
        if (!mounted) return;
        session.terminal.write(utf8.decode(bytes, allowMalformed: true));
      });

      process.exitCode.then((code) {
        if (!mounted) return;
        setState(() {
          session.isRunning = false;
          session.exitCode = code;
        });
        session.terminal.write(
          '\r\n[Processo terminato con codice $code]\r\n',
        );
      });
    } catch (e) {
      if (!mounted) return;
      session.terminal.write(
        _tr('Impossibile avviare il processo della shell ($executable): $e\r\n', 'Unable to start shell process ($executable): $e\r\n'),
      );
      setState(() {
        session.isRunning = false;
        session.exitCode = -1;
      });
    }
  }

  void _closeTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    final closing = _tabs[index];
    closing.dispose();

    setState(() {
      _tabs.removeAt(index);
      if (_tabs.isEmpty) {
        widget.onClose();
      } else {
        if (_activeTabIndex >= _tabs.length) {
          _activeTabIndex = _tabs.length - 1;
        }
      }
    });
  }

  void _clearScreen() {
    if (_tabs.isEmpty) return;
    final currentTab = _tabs[_activeTabIndex];
    currentTab.terminal.buffer.clear();
    currentTab.terminal.setCursor(0, 0);
  }

  void _sendInterrupt() {
    if (_tabs.isEmpty) return;
    _tabs[_activeTabIndex].handleInput('\x03');
  }

  void _openInNativeTerminal() {
    final termSettings = ref.read(terminalSettingsProvider);
    launchNativeTerminal(
      cwd: widget.cwd,
      nativeApp: termSettings.nativeApp,
      customPath: termSettings.customPath,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appLanguageProvider);
    final tokens = widget.tokens;

    if (_tabs.isEmpty) {
      return Container(
        color: tokens.chassis,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _tr('Nessun terminale aperto', 'No terminal open'),
                style: TextStyle(color: tokens.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: tokens.accent,
                  foregroundColor: tokens.surface,
                ),
                onPressed: () => _createNewTab(),
                icon: const Icon(Icons.add, size: 16),
                label: Text(_tr('Apri nuovo terminale', 'Open new terminal')),
              ),
            ],
          ),
        ),
      );
    }

    final activeTab = _tabs[_activeTabIndex];

    return Container(
      decoration: BoxDecoration(
        color: tokens.chassis,
        border: Border(
          top: BorderSide(color: tokens.borderStrong, width: 1),
        ),
      ),
      child: Column(
        children: [
          // -------------------------------------------------------------
          // Top Tab Bar & Actions
          // -------------------------------------------------------------
          Container(
            height: 36,
            decoration: BoxDecoration(
              color: tokens.surface,
              border: Border(
                bottom: BorderSide(color: tokens.border, width: 1),
              ),
            ),
            child: Row(
              children: [
                // Scrollable Tabs
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _tabs.length,
                    itemBuilder: (context, index) {
                      final tab = _tabs[index];
                      final isSelected = index == _activeTabIndex;

                      return InkWell(
                        onTap: () {
                          setState(() => _activeTabIndex = index);
                          _terminalFocusNode.requestFocus();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? tokens.chassis
                                : tokens.surface,
                            border: Border(
                              right: BorderSide(color: tokens.border),
                              bottom: isSelected
                                    ? BorderSide(color: tokens.accent, width: 2)
                                    : BorderSide.none,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.terminal,
                                size: 14,
                                color: isSelected
                                    ? tokens.accent
                                    : tokens.textMuted,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                tab.title,
                                style: TextStyle(
                                  color: isSelected
                                      ? tokens.displayText
                                      : tokens.textMuted,
                                  fontSize: 11,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () => _closeTab(index),
                                borderRadius: BorderRadius.circular(tokens.radiusSm),
                                child: Padding(
                                  padding: const EdgeInsets.all(2.0),
                                  child: Icon(
                                    Icons.close,
                                    size: 13,
                                    color: tokens.textMuted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // "+" Add Tab Button
                PopupMenuButton<String>(
                  tooltip: _tr('Nuovo terminale', 'New terminal'),
                  icon: Icon(Icons.add, size: 16, color: tokens.displayText),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onSelected: (val) {
                    if (val == 'default') {
                      _createNewTab();
                    } else {
                      _createNewTab(preferredShell: val);
                    }
                  },
                  itemBuilder: (context) {
                    final wslInfo = Platform.isWindows ? _parseWslPath(widget.cwd) : null;
                    return [
                      if (wslInfo != null)
                        PopupMenuItem(
                          value: 'wsl',
                          child: Row(
                            children: [
                              const Icon(Icons.terminal, size: 15),
                              const SizedBox(width: 8),
                              Text(_tr('Nuovo terminale WSL (${wslInfo['distro']})', 'New WSL terminal (${wslInfo['distro']})')),
                            ],
                          ),
                        ),
                      PopupMenuItem(
                        value: 'default',
                        child: Row(
                          children: [
                            const Icon(Icons.terminal, size: 15),
                            const SizedBox(width: 8),
                            Text(
                              Platform.isWindows
                                  ? _tr('Nuovo terminale (PowerShell)', 'New terminal (PowerShell)')
                                  : _tr('Nuovo terminale', 'New terminal'),
                            ),
                          ],
                        ),
                      ),
                      if (Platform.isWindows)
                        PopupMenuItem(
                          value: 'cmd',
                          child: Row(
                            children: [
                              const Icon(Icons.terminal, size: 15),
                              const SizedBox(width: 8),
                              Text(_tr('Prompt dei comandi (cmd)', 'Command Prompt (cmd)')),
                            ],
                          ),
                        ),
                    ];
                  },
                ),

                const SizedBox(width: 4),

                // Interrupt button (Ctrl+C)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  tooltip: _tr('Interrompi processo (Ctrl+C)', 'Interrupt process (Ctrl+C)'),
                  icon: Icon(Icons.stop_circle_outlined, size: 15, color: tokens.danger),
                  onPressed: _sendInterrupt,
                ),

                const SizedBox(width: 4),

                // Clear screen action
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  tooltip: _tr('Pulisci schermo (Clear)', 'Clear screen'),
                  icon: const Icon(Icons.block, size: 14),
                  onPressed: _clearScreen,
                ),

                const SizedBox(width: 4),

                // Open in Native Terminal action
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  tooltip: _tr('Apri nel terminale nativo (OS)', 'Open in system terminal'),
                  icon: const Icon(Icons.open_in_new, size: 14),
                  onPressed: _openInNativeTerminal,
                ),

                const SizedBox(width: 4),

                // Collapse Downward Button
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  tooltip: _tr('Collassa in basso', 'Collapse to bottom'),
                  icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                  onPressed: widget.onCollapseDownward,
                ),

                const SizedBox(width: 4),

                // Close Button
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  tooltip: _tr('Chiudi terminale', 'Close terminal'),
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: widget.onClose,
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),

          // -------------------------------------------------------------
          // Terminal View Body (Direct Interactive Typing)
          // -------------------------------------------------------------
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _terminalFocusNode.requestFocus(),
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                color: tokens.chassis,
                child: TerminalView(
                  activeTab.terminal,
                  focusNode: _terminalFocusNode,
                  theme: _buildTerminalTheme(tokens),
                  textStyle: TerminalStyle(
                    fontSize: 12,
                    fontFamily: tokens.monoFontFamily,
                  ),
                  autofocus: true,
                  hardwareKeyboardOnly: !kIsWeb,
                  onKeyEvent: _handleTerminalKeyEvent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  KeyEventResult _handleTerminalKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    if (_tabs.isEmpty || _activeTabIndex >= _tabs.length) {
      return KeyEventResult.ignored;
    }
    final activeTab = _tabs[_activeTabIndex];

    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;
    final isMeta = HardwareKeyboard.instance.isMetaPressed;

    // Ctrl+C: Interrupt
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyC) {
      activeTab.handleInput('\x03');
      return KeyEventResult.handled;
    }

    // Ctrl+L: Clear screen
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyL) {
      activeTab.handleInput('\x0c');
      return KeyEventResult.handled;
    }

    // Ctrl+V: Paste from clipboard
    if ((isCtrl || isMeta) && event.logicalKey == LogicalKeyboardKey.keyV) {
      Clipboard.getData('text/plain').then((clip) {
        if (clip?.text != null && clip!.text!.isNotEmpty) {
          activeTab.handleInput(clip.text!);
        }
      });
      return KeyEventResult.handled;
    }

    // Enter / Return
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      activeTab.handleInput('\r');
      return KeyEventResult.handled;
    }

    // Backspace
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      activeTab.handleInput('\x08');
      return KeyEventResult.handled;
    }

    // Tab
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      activeTab.handleInput('\t');
      return KeyEventResult.handled;
    }

    // Arrow Up / Down
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      activeTab.handleInput('\x1b[A');
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      activeTab.handleInput('\x1b[B');
      return KeyEventResult.handled;
    }

    // Printable characters
    if (!isCtrl && !isAlt && !isMeta) {
      final character = event.character;
      if (character != null && character.isNotEmpty) {
        activeTab.handleInput(character);
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }
}
