import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/daemon/daemon_locator.dart';
import '../../data/daemon/daemon_providers.dart';
import '../../data/daemon/pcp_client.dart';
import '../../data/terminal/terminal_settings.dart';
import '../../data/theme/theme_providers.dart';
import '../../data/notifications/notification_providers.dart';
import '../../data/language/language_settings.dart';
import 'diagnostics.dart';
import 'pi_cli_section.dart';
import 'remote_section.dart';
import 'updates_section.dart';
import 'theme_editor_dialog.dart';
import '../../ui/frame_snack_bar.dart';

/// `dart:io` Platform throws `UnsupportedError` on the web build, so every OS
/// branch in settings goes through this web-safe helper.
bool get _isWindowsOs => !kIsWeb && Platform.isWindows;

class SettingsView extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  final int initialTabIndex;

  const SettingsView({
    super.key,
    required this.onClose,
    this.initialTabIndex = 0,
  });

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView>
    with SingleTickerProviderStateMixin {
  String _tr(String it, String en) =>
      ref.read(appLanguageProvider) == AppLanguage.it ? it : en;
  late TabController _tabController;
  int _workerIdleTimeoutMinutes = 30;
  bool _isLoadingConfig = true;
  String? _configStatusMessage;
  bool _isLoadingPackages = true;
  bool _isWorkingWithPackage = false;
  bool _isRestartingDaemon = false;
  String? _packageError;
  List<Map<String, dynamic>> _packages = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 9,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _fetchDaemonConfig();
    _fetchPiPackages();
  }

  Future<void> _fetchDaemonConfig() async {
    final client = ref.read(pcpClientProvider);
    if (client == null) {
      if (mounted) {
        setState(() => _isLoadingConfig = false);
      }
      return;
    }

    try {
      final res = await client.getDaemonConfig().timeout(
        const Duration(seconds: 4),
      );
      final data = res['data'] as Map<String, dynamic>? ?? res;
      final ms = (data['workerIdleTimeoutMs'] as num?)?.toInt() ?? 1800000;
      if (mounted) {
        setState(() {
          _workerIdleTimeoutMinutes = (ms / 60000).round();
          _isLoadingConfig = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingConfig = false;
        });
      }
    }
  }

  Future<void> _restartDaemon() async {
    setState(() => _isRestartingDaemon = true);
    try {
      final endpoint = await DaemonLocator.restartDaemon();
      if (mounted) {
        if (endpoint != null) {
          ref.invalidate(daemonEndpointProvider);
          _fetchDaemonConfig();
          _fetchPiPackages();
          FrameSnackBar.show(context, message: 'Daemon riavviato con successo');
        } else {
          FrameSnackBar.show(context, message: 'Riavvio daemon non riuscito');
        }
      }
    } catch (e) {
      if (mounted) {
        FrameSnackBar.show(context, message: 'Errore durante il riavvio: $e');
      }
    } finally {
      if (mounted) setState(() => _isRestartingDaemon = false);
    }
  }

  Future<void> _fetchPiPackages() async {
    final client = ref.read(pcpClientProvider);
    if (client == null) {
      if (mounted) {
        setState(() {
          _packages = [];
          _packageError = 'Daemon non connesso';
          _isLoadingPackages = false;
        });
      }
      return;
    }
    setState(() {
      _isLoadingPackages = true;
      _packageError = null;
    });
    try {
      final result = await client.listPiPackages();
      final data = result['data'] as Map<String, dynamic>? ?? result;
      final packages = (data['packages'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      if (mounted) setState(() => _packages = packages);
    } catch (error) {
      if (mounted) setState(() => _packageError = error.toString());
    } finally {
      if (mounted) setState(() => _isLoadingPackages = false);
    }
  }

  Future<bool> _confirmPackageAction(
    String title,
    String message,
    String confirmation,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_tr('Annulla', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(confirmation),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _performPackageAction(
    String source,
    Future<Map<String, dynamic>> Function(PcpClient client) action, {
    required String successMessage,
  }) async {
    final client = ref.read(pcpClientProvider);
    if (client == null || _isWorkingWithPackage) return;
    setState(() => _isWorkingWithPackage = true);
    try {
      await action(client);
      if (mounted) {
        FrameSnackBar.show(
          context,
          message: _tr(
            '$successMessage: $source. Riavvia Pi per applicare le modifiche.',
            '$successMessage: $source. Restart Pi to apply the changes.',
          ),
        );
      }
      await _fetchPiPackages();
    } catch (error) {
      if (mounted) {
        FrameSnackBar.show(
          context,
          message: _tr(
            'Operazione sul pacchetto non riuscita: $error',
            'Package operation failed: $error',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isWorkingWithPackage = false);
    }
  }

  Future<void> _updatePackage(Map<String, dynamic> package) async {
    final source = package['source'].toString();
    if (!await _confirmPackageAction(
      _tr('Aggiornare il pacchetto?', 'Update package?'),
      _tr(
        'Pi aggiornerà $source usando il package manager installato. Il codice aggiornato verrà caricato al prossimo avvio di Pi.',
        'Pi will update $source using the installed package manager. Updated code will load the next time Pi starts.',
      ),
      _tr('Aggiorna', 'Update'),
    )) {
      return;
    }
    await _performPackageAction(
      source,
      (client) => client.updatePiPackage(source),
      successMessage: _tr('Pacchetto aggiornato', 'Package updated'),
    );
  }

  Future<void> _removePackage(Map<String, dynamic> package) async {
    final source = package['source'].toString();
    if (!await _confirmPackageAction(
      _tr('Rimuovere il pacchetto?', 'Remove package?'),
      _tr(
        'Pi rimuoverà $source dalle impostazioni utente e dalla directory dei pacchetti. Le cronologie delle sessioni non vengono modificate.',
        'Pi will remove $source from user settings and the package directory. Session histories will not be changed.',
      ),
      _tr('Rimuovi', 'Remove'),
    )) {
      return;
    }
    await _performPackageAction(
      source,
      (client) => client.removePiPackage(source),
      successMessage: _tr('Pacchetto rimosso', 'Package removed'),
    );
  }

  Future<void> _pinPackage(Map<String, dynamic> package) async {
    final source = package['source'].toString();
    final currentVersion =
        (package['pinnedVersion'] ?? package['version'] ?? '').toString();
    var version = currentVersion;
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(_tr('Blocca versione npm', 'Pin npm version')),
          content: TextFormField(
            initialValue: currentVersion,
            onChanged: (value) => setDialogState(() => version = value.trim()),
            decoration: InputDecoration(
              labelText: _tr('Versione semver', 'Semver version'),
              hintText: '1.2.3',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_tr('Annulla', 'Cancel')),
            ),
            FilledButton(
              onPressed: version.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, version),
              child: Text(_tr('Blocca', 'Pin')),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    if (!await _confirmPackageAction(
      _tr('Confermare versione bloccata?', 'Confirm pinned version?'),
      _tr(
        '$source verrà impostato sulla versione $selected.',
        '$source will be set to version $selected.',
      ),
      _tr('Blocca versione', 'Pin version'),
    )) {
      return;
    }
    await _performPackageAction(
      source,
      (client) => client.pinPiPackage(source, selected),
      successMessage: _tr('Versione bloccata', 'Version pinned'),
    );
  }

  Widget _packageList(FrameTokens tokens) {
    if (_isLoadingPackages) {
      return Center(child: CircularProgressIndicator(color: tokens.accent));
    }
    if (_packageError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_packageError!, style: TextStyle(color: tokens.danger)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _fetchPiPackages,
              icon: const Icon(Icons.refresh),
              label: Text(_tr('Riprova', 'Retry')),
            ),
          ],
        ),
      );
    }
    if (_packages.isEmpty) {
      return Center(
        child: Text(
          _tr(
            'Nessun pacchetto Pi utente installato.',
            'No user Pi packages installed.',
          ),
          style: TextStyle(color: tokens.textMuted),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          _tr('Pacchetti Pi installati', 'Installed Pi packages'),
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _tr(
            'Pacchetti utente globali, gestiti dal package manager Pi. Modifiche attive al prossimo avvio di Pi.',
            'Global user packages managed by the Pi package manager. Changes take effect the next time Pi starts.',
          ),
          style: TextStyle(color: tokens.textMuted, fontSize: 12),
        ),
        if (_isWorkingWithPackage) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(color: tokens.accent),
        ],
        const SizedBox(height: 16),
        for (final package in _packages) _buildPackageCard(tokens, package),
      ],
    );
  }

  Widget _buildPackageCard(FrameTokens tokens, Map<String, dynamic> package) {
    final source = package['source']?.toString() ?? '';
    final name = package['name']?.toString() ?? source;
    final version =
        package['version']?.toString() ??
        _tr('versione sconosciuta', 'unknown version');
    final pin = package['pinnedVersion']?.toString();
    final supportsPin = source.startsWith('npm:');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(tokens.radiusMd),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.extension_outlined, color: tokens.accent, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '$version${pin == null ? '' : ' · pinned $pin'} · $source',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: 10,
                      fontFamily: tokens.monoFontFamily,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: _tr('Aggiorna $name', 'Update $name'),
              onPressed: _isWorkingWithPackage
                  ? null
                  : () => _updatePackage(package),
              icon: const Icon(Icons.system_update_alt, size: 18),
            ),
            if (supportsPin)
              IconButton(
                tooltip: _tr('Blocca versione $name', 'Pin $name version'),
                onPressed: _isWorkingWithPackage
                    ? null
                    : () => _pinPackage(package),
                icon: const Icon(Icons.push_pin_outlined, size: 18),
              ),
            IconButton(
              tooltip: _tr('Rimuovi $name', 'Remove $name'),
              onPressed: _isWorkingWithPackage
                  ? null
                  : () => _removePackage(package),
              icon: Icon(Icons.delete_outline, size: 18, color: tokens.danger),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateTimeout(int newMinutes) async {
    final client = ref.read(pcpClientProvider);
    if (client == null) return;

    setState(() {
      _workerIdleTimeoutMinutes = newMinutes;
      _configStatusMessage = _tr('Salvataggio in corso...', 'Saving...');
    });

    try {
      await client.setDaemonConfig({'workerIdleTimeoutMs': newMinutes * 60000});
      if (mounted) {
        setState(() {
          _configStatusMessage = _tr(
            'Timeout aggiornato con successo!',
            'Timeout updated successfully!',
          );
        });
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() => _configStatusMessage = null);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _configStatusMessage = _tr('Errore: $e', 'Error: $e');
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<DaemonConnectionState>>(connectionStateProvider, (
      prev,
      next,
    ) {
      if (next.value == DaemonConnectionState.connected) {
        _fetchDaemonConfig();
        _fetchPiPackages();
      }
    });

    final tokens = context.tokens;
    final strings = ref.watch(appStringsProvider);
    final endpointAsync = ref.watch(daemonEndpointProvider);
    final endpoint = endpointAsync.value;

    return Container(
      color: tokens.background,
      child: Column(
        children: [
          // Top Navigation Header
          Container(
            margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: tokens.surfaceElevated,
              borderRadius: BorderRadius.circular(tokens.radiusLg),
              border: Border.all(color: tokens.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      tooltip: strings.backToChatTooltip,
                      color: tokens.displayText,
                      onPressed: widget.onClose,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        strings.settingsTitle,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.displayText,
                          fontSize: 28,
                          height: 1,
                          fontFamily: tokens.headingFontFamily,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  indicatorColor: tokens.signalWarning,
                  labelColor: tokens.displayText,
                  unselectedLabelColor: tokens.displayText.withValues(
                    alpha: 0.72,
                  ),
                  labelStyle: TextStyle(
                    fontFamily: tokens.uiFontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.7,
                  ),
                  tabs: [
                    Tab(text: strings.tabPiCli),
                    Tab(text: strings.tabPackages),
                    Tab(text: strings.tabDaemon),
                    Tab(text: strings.tabAppearance),
                    Tab(text: strings.tabPrivacy),
                    Tab(text: strings.tabDiagnostics),
                    Tab(text: strings.tabUpdates),
                    Tab(text: strings.tabTerminal),
                    Tab(text: strings.tabRemote),
                  ],
                ),
              ],
            ),
          ),

          // Tab views
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: TabBarView(
                  controller: _tabController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    // -------------------------------------------------------------
                    // Tab 1: Pi CLI
                    // -------------------------------------------------------------
                    PiCliSection(
                      tokens: tokens,
                      onRecheck: () {
                        ref.invalidate(daemonEndpointProvider);
                      },
                    ),

                    // -------------------------------------------------------------
                    // Tab 2: Pacchetti Pi
                    // -------------------------------------------------------------
                    _packageList(tokens),

                    // -------------------------------------------------------------
                    // Tab 3: Daemon
                    // -------------------------------------------------------------
                    ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        Text(
                          _tr('Stato del Daemon pi-agentd', 'pi-agentd status'),
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _tr(
                            'Il daemon locale gestisce i processi Pi worker, il journal e il protocollo PCP/1.',
                            'The local daemon manages Pi workers, the journal and the PCP/1 protocol.',
                          ),
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildInfoCard(tokens, [
                          _buildInfoRow(
                            tokens,
                            _tr('Porta HTTP/WS', 'HTTP/WS port'),
                            endpoint != null
                                ? '127.0.0.1:${endpoint.port}'
                                : _tr('In connessione...', 'Connecting...'),
                          ),
                          _buildInfoRow(
                            tokens,
                            _tr('Stato', 'Status'),
                            endpoint == null
                                ? _tr('Non connesso', 'Disconnected')
                                : _tr('Endpoint rilevato', 'Endpoint detected'),
                          ),
                          _buildInfoRow(
                            tokens,
                            _tr('Protocollo', 'Protocol'),
                            _tr('PCP/1 (JSON testuale)', 'PCP/1 (text JSON)'),
                          ),
                        ]),
                        const SizedBox(height: 24),
                        Text(
                          _tr(
                            'Timeout Inattività Worker (D9)',
                            'Worker idle timeout (D9)',
                          ),
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _tr(
                            'Dopo quanto tempo di inattività i processi Pi in idle vengono terminati per risparmiare risorse (i worker occupati non vengono mai terminati).',
                            'How long idle Pi workers remain before stopping to save resources (busy workers are never stopped).',
                          ),
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _isLoadingConfig
                            ? Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: tokens.accent,
                                    ),
                                  ),
                                ),
                              )
                            : Wrap(
                                spacing: 16,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: tokens.surfaceElevated,
                                      borderRadius: BorderRadius.circular(
                                        tokens.radiusMd,
                                      ),
                                      border: Border.all(color: tokens.border),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<int>(
                                        borderRadius: BorderRadius.circular(
                                          tokens.radiusMd,
                                        ),
                                        value: _workerIdleTimeoutMinutes,
                                        dropdownColor: tokens.surfaceElevated,
                                        style: TextStyle(
                                          color: tokens.textPrimary,
                                          fontSize: 14,
                                        ),
                                        items: [
                                          DropdownMenuItem(
                                            value: 0,
                                            child: Text(
                                              _tr(
                                                'Mai (0 min)',
                                                'Never (0 min)',
                                              ),
                                            ),
                                          ),
                                          DropdownMenuItem(
                                            value: 5,
                                            child: Text(
                                              _tr('5 minuti', '5 minutes'),
                                            ),
                                          ),
                                          DropdownMenuItem(
                                            value: 15,
                                            child: Text(
                                              _tr('15 minuti', '15 minutes'),
                                            ),
                                          ),
                                          DropdownMenuItem(
                                            value: 30,
                                            child: Text(
                                              _tr(
                                                '30 minuti (Default)',
                                                '30 minutes (default)',
                                              ),
                                            ),
                                          ),
                                          DropdownMenuItem(
                                            value: 60,
                                            child: Text(
                                              _tr(
                                                '1 ora (60 min)',
                                                '1 hour (60 min)',
                                              ),
                                            ),
                                          ),
                                          DropdownMenuItem(
                                            value: 120,
                                            child: Text(
                                              _tr(
                                                '2 ore (120 min)',
                                                '2 hours (120 min)',
                                              ),
                                            ),
                                          ),
                                        ],
                                        onChanged: (val) {
                                          if (val != null) _updateTimeout(val);
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  if (_configStatusMessage != null)
                                    Text(
                                      _configStatusMessage!,
                                      style: TextStyle(
                                        color: tokens.textPrimary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                        const SizedBox(height: 24),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: tokens.surfaceElevated,
                              foregroundColor: tokens.textPrimary,
                            ),
                            icon: _isRestartingDaemon
                                ? SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: tokens.accent,
                                    ),
                                  )
                                : const Icon(Icons.restart_alt, size: 16),
                            label: Text(
                              _isRestartingDaemon
                                  ? _tr('Riavvio in corso...', 'Restarting...')
                                  : _tr('Riavvia Daemon', 'Restart daemon'),
                            ),
                            onPressed: _isRestartingDaemon
                                ? null
                                : _restartDaemon,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          _tr(
                            'Notifiche di Sistema (macOS, Windows, Linux)',
                            'System notifications (macOS, Windows, Linux)',
                          ),
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _tr(
                            'Invia notifiche di sistema quando l\'agente completa una risposta o richiede una scelta/conferma e l\'applicazione non è a fuoco.',
                            'Send system notifications when the agent finishes a response or requests a choice or confirmation while the application is not focused.',
                          ),
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Material(
                          type: MaterialType.transparency,
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              _tr(
                                'Notifiche di sistema quando l\'app non è a fuoco',
                                'System notifications when the app is not focused',
                              ),
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: 13,
                              ),
                            ),
                            value: ref.watch(notificationsEnabledProvider),
                            activeThumbColor: tokens.accent,
                            onChanged: (val) {
                              ref
                                      .read(
                                        notificationsEnabledProvider.notifier,
                                      )
                                      .state =
                                  val;
                            },
                          ),
                        ),
                      ],
                    ),

                    // -------------------------------------------------------------
                    // Tab 4: Aspetto
                    // -------------------------------------------------------------
                    Consumer(
                      builder: (context, ref, _) {
                        final activeTheme = ref.watch(activeThemeSpecProvider);
                        final settings = ref.watch(themeSettingsProvider);
                        final repo = ref.watch(themeRepositoryProvider);
                        final themes = repo.availableThemes;
                        final darkThemes = themes
                            .where((t) => t.variant == 'dark')
                            .toList();
                        final lightThemes = themes
                            .where((t) => t.variant == 'light')
                            .toList();

                        return ListView(
                          padding: const EdgeInsets.all(24),
                          children: [
                            Text(
                              strings.languageSectionTitle,
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              strings.languageSectionSubtitle,
                              style: TextStyle(
                                color: tokens.textMuted,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: tokens.surfaceElevated,
                                borderRadius: BorderRadius.circular(
                                  tokens.radiusMd,
                                ),
                                border: Border.all(color: tokens.border),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<AppLanguage>(
                                  key: const ValueKey(
                                    'settings-language-dropdown',
                                  ),
                                  isExpanded: true,
                                  value: ref.watch(appLanguageProvider),
                                  dropdownColor: tokens.surfaceElevated,
                                  style: TextStyle(
                                    color: tokens.textPrimary,
                                    fontSize: 13,
                                    fontFamily: tokens.uiFontFamily,
                                  ),
                                  items: AppLanguage.values.map((lang) {
                                    return DropdownMenuItem<AppLanguage>(
                                      value: lang,
                                      child: Row(
                                        children: [
                                          Text(
                                            lang.flag,
                                            style: const TextStyle(
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(lang.label),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (newLang) {
                                    if (newLang != null) {
                                      ref
                                          .read(appLanguageProvider.notifier)
                                          .setLanguage(newLang);
                                    }
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              strings.appearanceTitle,
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              strings.appearanceSubtitle,
                              style: TextStyle(
                                color: tokens.textMuted,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: tokens.surfaceElevated,
                                borderRadius: BorderRadius.circular(
                                  tokens.radiusMd,
                                ),
                                border: Border.all(color: tokens.border),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          strings.useSystemTheme,
                                          style: TextStyle(
                                            color: tokens.textPrimary,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          strings.useSystemThemeSubtitle,
                                          style: TextStyle(
                                            color: tokens.textMuted,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    key: const ValueKey(
                                      'settings-theme-system-switch',
                                    ),
                                    value: settings.useSystemTheme,
                                    onChanged: (val) {
                                      ref
                                          .read(themeSettingsProvider.notifier)
                                          .setUseSystemTheme(val);
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (!settings.useSystemTheme) ...[
                              Text(
                                strings.selectActiveTheme,
                                style: TextStyle(
                                  color: tokens.textSecondary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: tokens.surfaceElevated,
                                  borderRadius: BorderRadius.circular(
                                    tokens.radiusMd,
                                  ),
                                  border: Border.all(color: tokens.border),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    key: const ValueKey(
                                      'settings-theme-dropdown',
                                    ),
                                    isExpanded: true,
                                    borderRadius: BorderRadius.circular(
                                      tokens.radiusMd,
                                    ),
                                    value: activeTheme.id,
                                    dropdownColor: tokens.surfaceElevated,
                                    style: TextStyle(
                                      color: tokens.textPrimary,
                                      fontSize: 13,
                                      fontFamily: tokens.uiFontFamily,
                                    ),
                                    items: themes.map((t) {
                                      return DropdownMenuItem<String>(
                                        value: t.id,
                                        child: Text(
                                          '${t.name} (${t.variant})',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (newId) {
                                      if (newId != null) {
                                        ref
                                            .read(
                                              activeThemeSpecProvider.notifier,
                                            )
                                            .setTheme(newId);
                                      }
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        strings.defaultDarkTheme,
                                        style: TextStyle(
                                          color: tokens.textSecondary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: tokens.surfaceElevated,
                                          borderRadius: BorderRadius.circular(
                                            tokens.radiusMd,
                                          ),
                                          border: Border.all(
                                            color: tokens.border,
                                          ),
                                        ),
                                        child: DropdownButtonHideUnderline(
                                          child: DropdownButton<String>(
                                            isExpanded: true,
                                            borderRadius: BorderRadius.circular(
                                              tokens.radiusMd,
                                            ),
                                            value:
                                                darkThemes.any(
                                                  (t) =>
                                                      t.id ==
                                                      settings
                                                          .defaultDarkThemeId,
                                                )
                                                ? settings.defaultDarkThemeId
                                                : (darkThemes.isNotEmpty
                                                      ? darkThemes.first.id
                                                      : null),
                                            dropdownColor:
                                                tokens.surfaceElevated,
                                            style: TextStyle(
                                              color: tokens.textPrimary,
                                              fontSize: 13,
                                              fontFamily: tokens.uiFontFamily,
                                            ),
                                            items: darkThemes.map((t) {
                                              return DropdownMenuItem<String>(
                                                value: t.id,
                                                child: Text(
                                                  t.name,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              );
                                            }).toList(),
                                            onChanged: (newId) {
                                              if (newId != null) {
                                                ref
                                                    .read(
                                                      themeSettingsProvider
                                                          .notifier,
                                                    )
                                                    .setDefaultDarkTheme(newId);
                                              }
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        strings.defaultLightTheme,
                                        style: TextStyle(
                                          color: tokens.textSecondary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: tokens.surfaceElevated,
                                          borderRadius: BorderRadius.circular(
                                            tokens.radiusMd,
                                          ),
                                          border: Border.all(
                                            color: tokens.border,
                                          ),
                                        ),
                                        child: DropdownButtonHideUnderline(
                                          child: DropdownButton<String>(
                                            isExpanded: true,
                                            borderRadius: BorderRadius.circular(
                                              tokens.radiusMd,
                                            ),
                                            value:
                                                lightThemes.any(
                                                  (t) =>
                                                      t.id ==
                                                      settings
                                                          .defaultLightThemeId,
                                                )
                                                ? settings.defaultLightThemeId
                                                : (lightThemes.isNotEmpty
                                                      ? lightThemes.first.id
                                                      : null),
                                            dropdownColor:
                                                tokens.surfaceElevated,
                                            style: TextStyle(
                                              color: tokens.textPrimary,
                                              fontSize: 13,
                                              fontFamily: tokens.uiFontFamily,
                                            ),
                                            items: lightThemes.map((t) {
                                              return DropdownMenuItem<String>(
                                                value: t.id,
                                                child: Text(
                                                  t.name,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              );
                                            }).toList(),
                                            onChanged: (newId) {
                                              if (newId != null) {
                                                ref
                                                    .read(
                                                      themeSettingsProvider
                                                          .notifier,
                                                    )
                                                    .setDefaultLightTheme(
                                                      newId,
                                                    );
                                              }
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  key: const ValueKey(
                                    'settings-open-theme-editor-btn',
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: tokens.accent),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        tokens.radiusSm,
                                      ),
                                    ),
                                  ),
                                  icon: Icon(
                                    Icons.palette_outlined,
                                    size: 16,
                                    color: tokens.accent,
                                  ),
                                  label: Text(
                                    strings.openThemeEditorBtn,
                                    style: TextStyle(
                                      color: tokens.accent,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  onPressed: () {
                                    ThemeEditorDialog.show(context);
                                  },
                                ),
                                OutlinedButton.icon(
                                  key: const ValueKey(
                                    'settings-import-theme-btn',
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(
                                      color: tokens.borderStrong,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        tokens.radiusSm,
                                      ),
                                    ),
                                  ),
                                  icon: Icon(
                                    Icons.file_upload_outlined,
                                    size: 16,
                                    color: tokens.accent,
                                  ),
                                  label: Text(
                                    strings.importThemeBtn,
                                    style: TextStyle(
                                      color: tokens.textPrimary,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  onPressed: () async {
                                    try {
                                      final file = await openFile(
                                        acceptedTypeGroups: [
                                          const XTypeGroup(
                                            label: 'Tema JSON (*.json)',
                                            extensions: ['json'],
                                          ),
                                        ],
                                      );
                                      if (file == null || !context.mounted) {
                                        return;
                                      }
                                      final content = await file.readAsString();
                                      final importedSpec = await ref
                                          .read(
                                            activeThemeSpecProvider.notifier,
                                          )
                                          .importThemeFromJson(content);
                                      if (context.mounted) {
                                        FrameSnackBar.show(
                                          context,
                                          message: _tr(
                                            'Tema "${importedSpec.name}" importato e attivato con successo!',
                                            'Theme "${importedSpec.name}" imported and applied successfully!',
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        FrameSnackBar.show(
                                          context,
                                          message: _tr(
                                            'Errore durante l\'importazione del tema: $e',
                                            'Failed to import theme: $e',
                                          ),
                                        );
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _buildInfoCard(tokens, [
                              _buildInfoRow(
                                tokens,
                                _tr('Tema attivo', 'Active theme'),
                                '${activeTheme.name} (v${activeTheme.version})',
                              ),
                              _buildInfoRow(
                                tokens,
                                _tr('Densità layout', 'Layout density'),
                                _tr(
                                  'Confortevole (Predefinita 1.0x)',
                                  'Comfortable (default 1.0x)',
                                ),
                              ),
                              _buildInfoRow(
                                tokens,
                                _tr('Caratteri', 'Fonts'),
                                '${activeTheme.toTokens().uiFontFamily} (UI) · ${activeTheme.toTokens().monoFontFamily} (${_tr('Codice', 'Code')})',
                              ),
                            ]),
                            if (activeTheme.diagnostics.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Text(
                                _tr('Diagnostica tema:', 'Theme diagnostics:'),
                                style: TextStyle(
                                  color: tokens.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              ...activeTheme.diagnostics.map(
                                (d) => Text(
                                  '• $d',
                                  style: TextStyle(
                                    color: tokens.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),

                    // -------------------------------------------------------------
                    // Tab 5: Privacy (D16 — Zero Telemetry)
                    // -------------------------------------------------------------
                    ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.shield_outlined,
                              size: 24,
                              color: tokens.textPrimary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _tr(
                                  'Informativa sulla Privacy e Tracciamento',
                                  'Privacy and tracking',
                                ),
                                style: TextStyle(
                                  color: tokens.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: tokens.surfaceElevated,
                            borderRadius: BorderRadius.circular(
                              tokens.radiusSm,
                            ),
                            border: Border.all(color: tokens.border),
                          ),
                          child: Text(
                            _tr(
                              'PiFrame non invia alcun dato di utilizzo a server remoti. I log restano sul tuo computer; puoi esportarli manualmente dalla sezione Diagnostica per condividerli con chi ti assiste.',
                              'PiFrame does not send usage data to remote servers. Logs remain on your computer; you can export them manually from Diagnostics to share with support.',
                            ),
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: 14,
                              height: 1.6,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _tr(
                            '• Zero telemetria, zero analytics di terze parti (nessun Google Analytics, Mixpanel o Sentry).\n'
                                '• Comunicazione locale confinata all\'interfaccia loopback 127.0.0.1 con token di autenticazione 256 bit.\n'
                                '• Nessuna modifica ai file di sessione o configurazioni originali di Pi in ~/.pi/.',
                            '• No telemetry or third-party analytics (no Google Analytics, Mixpanel or Sentry).\n• Local communication is confined to loopback 127.0.0.1 with a 256-bit authentication token.\n• No changes to original Pi session files or configuration in ~/.pi/.',
                          ),
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 12,
                            height: 1.8,
                          ),
                        ),
                      ],
                    ),

                    // -------------------------------------------------------------
                    // Tab 6: Diagnostica Locale & Export Bundle (D16)
                    // -------------------------------------------------------------
                    const DiagnosticsSection(),

                    // -------------------------------------------------------------
                    // Tab 7: Aggiornamenti Ufficiali GitHub
                    // -------------------------------------------------------------
                    const UpdatesSection(),

                    // -------------------------------------------------------------
                    // Tab 8: Terminale & Ambiente di Esecuzione
                    // -------------------------------------------------------------
                    _buildTerminalSettingsTab(tokens),

                    // -------------------------------------------------------------
                    // Tab 9: Accesso Remoto Sicuro
                    // -------------------------------------------------------------
                    const RemoteSection(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTerminalSettingsTab(FrameTokens tokens) {
    final termSettings = ref.watch(terminalSettingsProvider);
    final notifier = ref.read(terminalSettingsProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          _tr(
            'Terminale & Ambiente di Esecuzione',
            'Terminal & execution environment',
          ),
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _tr(
            'Scegli se utilizzare il terminale integrato direttamente nell\'interfaccia o aprire il terminale nativo del sistema operativo (es. Windows Terminal, PowerShell, CMD, WSL, o un eseguibile personalizzato).',
            'Choose the integrated terminal or a native system terminal (e.g. Windows Terminal, PowerShell, CMD, WSL or a custom executable).',
          ),
          style: TextStyle(color: tokens.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 20),

        // Section 1: Modalità di esecuzione
        Text(
          _tr('MODALITÀ PREFERITA', 'PREFERRED MODE'),
          style: TextStyle(
            color: tokens.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: tokens.surfaceElevated,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            border: Border.all(color: tokens.border),
          ),
          child: RadioGroup<TerminalMode>(
            groupValue: termSettings.mode,
            onChanged: (mode) {
              if (mode != null) notifier.setMode(mode);
            },
            child: Column(
              children: [
                RadioListTile<TerminalMode>(
                  value: TerminalMode.integrated,
                  activeColor: tokens.accent,
                  title: Text(
                    _tr(
                      'Terminale integrato (in PiFrame)',
                      'Integrated terminal (in PiFrame)',
                    ),
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    _tr(
                      'Scrivi direttamente nella finestra di terminale integrata, con cronologia frecce su/giù e supporto shell di sistema.',
                      'Type directly in the integrated terminal, with up/down history and system shell support.',
                    ),
                    style: TextStyle(color: tokens.textMuted, fontSize: 11),
                  ),
                ),
                Divider(color: tokens.border, height: 1),
                RadioListTile<TerminalMode>(
                  value: TerminalMode.native,
                  activeColor: tokens.accent,
                  title: Text(
                    _tr(
                      'Terminale nativo OS (applicazione esterna)',
                      'Native system terminal (external application)',
                    ),
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    _tr(
                      'Apre una finestra di terminale esterna nativa direttamente nella cartella del repository.',
                      'Opens an external terminal directly in the repository folder.',
                    ),
                    style: TextStyle(color: tokens.textMuted, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Section 2: Scelta applicazione terminale nativo
        Text(
          _tr(
            'APPLICAZIONE TERMINALE NATIVO (OS)',
            'NATIVE TERMINAL APPLICATION',
          ),
          style: TextStyle(
            color: tokens.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: tokens.surfaceElevated,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            border: Border.all(color: tokens.border),
          ),
          child: RadioGroup<NativeTerminalApp>(
            groupValue: termSettings.nativeApp,
            onChanged: (app) {
              if (app != null) notifier.setNativeApp(app);
            },
            child: Column(
              children: [
                RadioListTile<NativeTerminalApp>(
                  value: NativeTerminalApp.systemDefault,
                  activeColor: tokens.accent,
                  title: Text(
                    _isWindowsOs
                        ? _tr(
                            'Predefinito di sistema (Windows Terminal wt.exe / shell predefinita)',
                            'System default (Windows Terminal wt.exe / default shell)',
                          )
                        : _tr(
                            'Terminale predefinito di sistema',
                            'System default terminal',
                          ),
                    style: TextStyle(color: tokens.textPrimary, fontSize: 13),
                  ),
                ),
                if (_isWindowsOs) ...[
                  Divider(color: tokens.border, height: 1),
                  RadioListTile<NativeTerminalApp>(
                    value: NativeTerminalApp.powershell,
                    activeColor: tokens.accent,
                    title: Text(
                      'PowerShell (powershell.exe)',
                      style: TextStyle(color: tokens.textPrimary, fontSize: 13),
                    ),
                  ),
                  Divider(color: tokens.border, height: 1),
                  RadioListTile<NativeTerminalApp>(
                    value: NativeTerminalApp.cmd,
                    activeColor: tokens.accent,
                    title: Text(
                      'Command Prompt (cmd.exe)',
                      style: TextStyle(color: tokens.textPrimary, fontSize: 13),
                    ),
                  ),
                  Divider(color: tokens.border, height: 1),
                  RadioListTile<NativeTerminalApp>(
                    value: NativeTerminalApp.wsl,
                    activeColor: tokens.accent,
                    title: Text(
                      'WSL (Windows Subsystem for Linux)',
                      style: TextStyle(color: tokens.textPrimary, fontSize: 13),
                    ),
                  ),
                ],
                Divider(color: tokens.border, height: 1),
                RadioListTile<NativeTerminalApp>(
                  value: NativeTerminalApp.custom,
                  activeColor: tokens.accent,
                  title: Text(
                    _tr(
                      'Applicazione o eseguibile personalizzato',
                      'Custom application or executable',
                    ),
                    style: TextStyle(color: tokens.textPrimary, fontSize: 13),
                  ),
                  subtitle: termSettings.nativeApp == NativeTerminalApp.custom
                      ? Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller:
                                      TextEditingController(
                                          text: termSettings.customPath,
                                        )
                                        ..selection = TextSelection.collapsed(
                                          offset:
                                              termSettings.customPath.length,
                                        ),
                                  style: TextStyle(
                                    color: tokens.textPrimary,
                                    fontSize: 12,
                                    fontFamily: tokens.monoFontFamily,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: _isWindowsOs
                                        ? 'C:\\Percorso\\A\\terminal.exe'
                                        : '/usr/bin/alacritty',
                                    isDense: true,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                        tokens.radiusSm,
                                      ),
                                    ),
                                  ),
                                  onSubmitted: (val) =>
                                      notifier.setCustomPath(val.trim()),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.folder_open, size: 14),
                                label: Text(_tr('Sfoglia', 'Browse')),
                                onPressed: () async {
                                  final file = await openFile(
                                    acceptedTypeGroups: [
                                      const XTypeGroup(
                                        label: 'Eseguibile',
                                        extensions: ['exe', 'bat', 'cmd', 'sh'],
                                      ),
                                    ],
                                  );
                                  if (file != null) {
                                    notifier.setCustomPath(file.path);
                                  }
                                },
                              ),
                            ],
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Test action button
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: tokens.accent,
              foregroundColor: tokens.surface,
            ),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(
              _tr(
                'Testa apertura terminale nativo',
                'Test native terminal launch',
              ),
            ),
            onPressed: () async {
              final launched = await launchNativeTerminal(
                cwd: Directory.current.path,
                nativeApp: termSettings.nativeApp,
                customPath: termSettings.customPath,
              );
              if (mounted) {
                FrameSnackBar.show(
                  context,
                  message: launched
                      ? _tr(
                          'Terminale nativo avviato con successo!',
                          'Native terminal started successfully!',
                        )
                      : _tr(
                          'Impossibile avviare il terminale con la configurazione scelta.',
                          'Unable to start the terminal with the selected configuration.',
                        ),
                );
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(FrameTokens tokens, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.border),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildInfoRow(FrameTokens tokens, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final labelWidget = Text(
            label,
            style: TextStyle(color: tokens.textSecondary, fontSize: 13),
          );
          final valueWidget = Text(
            value,
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          );
          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [labelWidget, const SizedBox(height: 4), valueWidget],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: labelWidget),
              const SizedBox(width: 24),
              Expanded(flex: 2, child: valueWidget),
            ],
          );
        },
      ),
    );
  }
}
