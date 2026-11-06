import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../data/language/language_settings.dart';
import '../../ui/frame_snack_bar.dart';

class RemoteSection extends ConsumerStatefulWidget {
  const RemoteSection({super.key});

  @override
  ConsumerState<RemoteSection> createState() => _RemoteSectionState();
}

class _RemoteSectionState extends ConsumerState<RemoteSection> {
  String _tr(String it, String en) =>
      ref.read(appLanguageProvider) == AppLanguage.it ? it : en;
  bool _isLoading = true;
  bool _isToggling = false;
  String? _errorMessage;

  bool _enabled = false;
  String _state = 'stopped';
  String? _url;
  String _tunnelProvider = 'cloudflared';
  int? _localPort;
  String? _pairingUrl;
  int? _pairingExpiresAt;
  String _defaultMode = 'view';
  bool _cloudflaredInstalled = false;
  String? _cloudflaredPath;
  bool _isInstallingCloudflared = false;

  bool _tailscaleInstalled = false;
  bool _tailscaleRunning = false;
  String? _tailscaleHostname;
  String? _tailscaleDomain;
  bool _isInstallingTailscale = false;
  bool _isSavingTailscaleHostname = false;
  final _tailscaleHostnameController = TextEditingController();

  List<Map<String, dynamic>> _devices = [];

  Timer? _countdownTimer;
  StreamSubscription? _eventSub;

  final _customUrlController = TextEditingController();
  final _customCommandController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchStatus();
    _subscribeEvents();
  }

  void _startCountdownIfNeeded() {
    if (_countdownTimer != null || _pairingExpiresAt == null) return;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_pairingExpiresAt != null) {
        setState(() {});
      } else {
        _countdownTimer?.cancel();
        _countdownTimer = null;
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _eventSub?.cancel();
    _customUrlController.dispose();
    _customCommandController.dispose();
    _tailscaleHostnameController.dispose();
    super.dispose();
  }

  void _subscribeEvents() {
    final client = ref.read(pcpClientProvider);
    if (client == null) return;
    _eventSub = client.events('@daemon').listen((event) {
      if (event.type == 'remote.statusChanged') {
        _applyStatusData(event.payload);
      }
    });
  }

  void _applyStatusData(Map<String, dynamic> data) {
    if (!mounted) return;
    setState(() {
      _enabled = data['enabled'] as bool? ?? false;
      _state = data['state'] as String? ?? 'stopped';
      _url = data['url'] as String?;
      _tunnelProvider = data['tunnelProvider'] as String? ?? 'cloudflared';
      _cloudflaredInstalled = data['cloudflaredInstalled'] as bool? ?? false;
      _cloudflaredPath = data['cloudflaredPath'] as String?;

      final ts = data['tailscale'] as Map<String, dynamic>?;
      if (ts != null) {
        _tailscaleInstalled = ts['installed'] as bool? ?? false;
        _tailscaleRunning = ts['running'] as bool? ?? false;
        _tailscaleHostname = ts['hostname'] as String?;
        _tailscaleDomain = ts['domain'] as String?;
        if (_tailscaleHostname != null && _tailscaleHostnameController.text.isEmpty) {
          _tailscaleHostnameController.text = _tailscaleHostname!;
        }
      }

      _localPort = data['localPort'] as int?;
      _errorMessage = data['error'] as String?;

      final pairing = data['pairingPending'] as Map<String, dynamic>?;
      _pairingUrl = pairing?['url'] as String?;
      _pairingExpiresAt = pairing?['expiresAt'] as int?;
      _startCountdownIfNeeded();

      final options = data['options'] as Map<String, dynamic>?;
      if (options != null) {
        _defaultMode = options['defaultMode'] as String? ?? 'view';
      }

      final devs = data['devices'] as List?;
      _devices = devs != null
          ? devs.map((d) => Map<String, dynamic>.from(d as Map)).toList()
          : [];
      _isLoading = false;
    });
  }

  Future<void> _fetchStatus() async {
    final client = ref.read(pcpClientProvider);
    if (client == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final res = await client.getRemoteStatus();
      final data = res['data'] as Map<String, dynamic>? ?? res;
      _applyStatusData(data);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _installCloudflared() async {
    final client = ref.read(pcpClientProvider);
    if (client == null || _isInstallingCloudflared) return;

    setState(() {
      _isInstallingCloudflared = true;
      _errorMessage = null;
    });

    try {
      final res = await client.installCloudflared();
      final data = res['data'] as Map<String, dynamic>? ?? res;
      final installedPath = data['path'] as String? ?? '~/.piframe/bin/cloudflared';
      if (mounted) {
        final tokens = context.tokens;
        FrameSnackBar.show(
          context,
          message: _tr('cloudflared scaricato e pronto in $installedPath!', 'cloudflared downloaded and ready at $installedPath!'),
          backgroundColor: tokens.success,
        );
      }
      await _fetchStatus();
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = _tr('Errore durante l\'installazione di cloudflared: $e', 'Failed to install cloudflared: $e'));
      }
    } finally {
      if (mounted) {
        setState(() => _isInstallingCloudflared = false);
      }
    }
  }

  Future<void> _installTailscale() async {
    final client = ref.read(pcpClientProvider);
    if (client == null || _isInstallingTailscale) return;

    setState(() {
      _isInstallingTailscale = true;
      _errorMessage = null;
    });

    try {
      final res = await client.installTailscale();
      final data = res['data'] as Map<String, dynamic>? ?? res;
      if (mounted) {
        final tokens = context.tokens;
        FrameSnackBar.show(
          context,
          message: data['message'] as String? ?? _tr('Installazione di Tailscale avviata! Conferma il prompt di Windows.', 'Tailscale installation started! Confirm the Windows prompt.'),
          backgroundColor: tokens.accent,
        );
      }
      await _fetchStatus();
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = _tr('Errore durante l\'installazione di Tailscale: $e', 'Failed to install Tailscale: $e'));
      }
    } finally {
      if (mounted) {
        setState(() => _isInstallingTailscale = false);
      }
    }
  }

  Future<void> _saveTailscaleHostname() async {
    final client = ref.read(pcpClientProvider);
    final text = _tailscaleHostnameController.text.trim();
    if (client == null || text.isEmpty || _isSavingTailscaleHostname) return;

    setState(() {
      _isSavingTailscaleHostname = true;
      _errorMessage = null;
    });

    try {
      final res = await client.setTailscaleHostname(text);
      final data = res['data'] as Map<String, dynamic>? ?? res;
      if (mounted) {
        final tokens = context.tokens;
        FrameSnackBar.show(
          context,
          message: _tr('Nome host Tailscale aggiornato! Nuovo dominio: ${data['domain'] ?? text}', 'Tailscale hostname updated! New domain: ${data['domain'] ?? text}'),
          backgroundColor: tokens.success,
        );
      }
      await _fetchStatus();
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = _tr('Errore durante la ridenominazione: $e', 'Rename failed: $e'));
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingTailscaleHostname = false);
      }
    }
  }

  Future<void> _toggleRemote(bool enable) async {
    final client = ref.read(pcpClientProvider);
    if (client == null || _isToggling) return;

    if (enable && _tunnelProvider == 'tailscale' && !_tailscaleInstalled) {
      final shouldInstall = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(_tr('Tailscale non installato', 'Tailscale is not installed')),
          content: Text(_tr(
            'Per utilizzare il tunnel permanente Tailscale è necessario installare Tailscale sul PC.\n\n'
            'Vuoi avviare l\'installazione automatica adesso?',
            'Tailscale must be installed on this computer to use its permanent tunnel.\n\nStart automatic installation now?')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_tr('Annulla', 'Cancel'))),
            FilledButton.icon(
              icon: const Icon(Icons.download, size: 18),
              onPressed: () => Navigator.pop(ctx, true),
              label: Text(_tr('Installa Tailscale', 'Install Tailscale')),
            ),
          ],
        ),
      );
      if (shouldInstall == true) {
        await _installTailscale();
      }
      return;
    }

    if (enable && _tunnelProvider == 'cloudflared' && !_cloudflaredInstalled) {
      final shouldInstall = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(_tr('cloudflared richiesto', 'cloudflared required')),
          content: Text(_tr(
            'Per avviare la connessione remota con Cloudflare è necessario l\'eseguibile ufficiale cloudflared.\n\n'
            'Vuoi scaricarlo e installarlo automaticamente in ~/.piframe/bin/? Non richiede permessi di amministratore.',
            'The official cloudflared executable is required for a Cloudflare remote connection.\n\nDownload and install it automatically in ~/.piframe/bin/? Administrator permissions are not required.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_tr('Annulla', 'Cancel'))),
            FilledButton.icon(
              icon: const Icon(Icons.download, size: 18),
              onPressed: () => Navigator.pop(ctx, true),
              label: Text(_tr('Installa e Avvia', 'Install and start')),
            ),
          ],
        ),
      );
      if (shouldInstall == true) {
        await _installCloudflared();
        if (!_cloudflaredInstalled) return;
      } else {
        return;
      }
    }

    setState(() {
      _isToggling = true;
      _errorMessage = null;
    });

    try {
      if (enable) {
        final res = await client.startRemoteTunnel(
          tunnelProvider: _tunnelProvider,
          customUrl: _tunnelProvider == 'tailscale'
              ? (_tailscaleDomain != null ? 'https://$_tailscaleDomain' : null)
              : (_customUrlController.text.trim().isEmpty ? null : _customUrlController.text.trim()),
          customCommand: _customCommandController.text.trim().isEmpty ? null : _customCommandController.text.trim(),
        );
        final data = res['data'] as Map<String, dynamic>? ?? res;
        _applyStatusData(data);
      } else {
        final res = await client.stopRemoteTunnel();
        final data = res['data'] as Map<String, dynamic>? ?? res;
        _applyStatusData(data);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isToggling = false);
      }
    }
  }

  Future<void> _generateNewPairing() async {
    final client = ref.read(pcpClientProvider);
    if (client == null) return;
    try {
      final res = await client.generateRemotePairing(ttlMs: 5 * 60 * 1000);
      final data = res['data'] as Map<String, dynamic>? ?? res;
      if (mounted) {
        setState(() {
          _pairingUrl = data['url'] as String?;
          _pairingExpiresAt = data['expiresAt'] as int?;
          _startCountdownIfNeeded();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    }
  }

  Future<void> _revokeDevice(String deviceId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_tr('Revoca Dispositivo', 'Revoke device')),
        content: Text(_tr('Vuoi revocare l\'accesso a "$name"? La connessione verrà terminata immediatamente.', 'Revoke access for "$name"? Its connection will end immediately.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_tr('Annulla', 'Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_tr('Revoca', 'Revoke')),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final client = ref.read(pcpClientProvider);
    if (client == null) return;
    try {
      await client.revokeRemoteDevice(deviceId);
      await _fetchStatus();
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    }
  }

  Future<void> _revokeAllDevices() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_tr('Revoca Tutti i Dispositivi', 'Revoke all devices')),
        content: Text(_tr('Tutte le sessioni remote verranno disconnesse e i token invalidati immediatamente. Continuare?', 'All remote sessions will be disconnected and their tokens invalidated immediately. Continue?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_tr('Annulla', 'Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_tr('Revoca Tutti', 'Revoke all')),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final client = ref.read(pcpClientProvider);
    if (client == null) return;
    try {
      await client.revokeAllRemoteDevices();
      await _fetchStatus();
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    }
  }

  Future<void> _updateDefaultMode(String mode) async {
    final client = ref.read(pcpClientProvider);
    if (client == null) return;
    try {
      final res = await client.setRemoteOptions(defaultMode: mode);
      final data = res['data'] as Map<String, dynamic>? ?? res;
      _applyStatusData(data);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    }
  }

  Future<void> _changeDeviceMode(String deviceId, String currentMode, String newMode, String deviceName) async {
    if (newMode == currentMode) return;

    if (newMode == 'control') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(_tr('Conferma Modalità Controllo', 'Confirm control mode')),
          content: Text(_tr(
            'Stai concedendo i permessi di CONTROLLO COMPLETO a "$deviceName".\n\n'
            'Questo dispositivo potrà inviare prompt ed eseguire comandi sul tuo computer con gli stessi privilegi del tuo utente.',
            'You are granting FULL CONTROL to "$deviceName".\n\nThis device can send prompts and run commands on your computer with the same privileges as your user account.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_tr('Annulla', 'Cancel'))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(_tr('Concedi Controllo', 'Grant control')),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    final client = ref.read(pcpClientProvider);
    if (client == null) return;
    try {
      await client.setRemoteDeviceMode(deviceId: deviceId, mode: newMode);
      await _fetchStatus();
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    }
  }

  String _formatExpires(int? expiresAt) {
    if (expiresAt == null) return '';
    final diff = expiresAt - DateTime.now().millisecondsSinceEpoch;
    if (diff <= 0) return _tr('Scaduto', 'Expired');
    final mins = diff ~/ 60000;
    final secs = (diff % 60000) ~/ 1000;
    return _tr('Scade tra ${mins}m ${secs.toString().padLeft(2, '0')}s', 'Expires in ${mins}m ${secs.toString().padLeft(2, '0')}s');
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appLanguageProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tokens = context.tokens;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final isRunning = _state == 'running';
    final isStarting = _state == 'starting' || _isToggling;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Title & Description
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.phonelink_ring, size: 28, color: colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_tr('Connessione Remota Sicura', 'Secure remote connection'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    _tr('Accedi al tuo Pi dallo smartphone o dal browser in mobilità. Tunnel crittografato, associazione one-time via QR code con URL fragment (#pair=...), token per-dispositivo con scadenza e controllo granulare dei permessi (view o control).', 'Access Pi from your phone or browser on the go. Encrypted tunnel, one-time QR pairing via URL fragment (#pair=...), expiring per-device tokens and granular permissions (view or control).'),
                    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        if (_errorMessage != null)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colorScheme.error.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: colorScheme.error, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(_errorMessage!, style: TextStyle(color: colorScheme.onErrorContainer, fontSize: 13))),
              ],
            ),
          ),

        // Main Toggle Card
        Card(
          elevation: 0,
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(_tr('Abilita Accesso Remoto', 'Enable remote access'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 10),
                          _buildStatusBadge(colorScheme, tokens),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _enabled
                            ? _tr('Il listener remoto dedicato è attivo. Inquadra il QR code per associare un dispositivo.', 'The dedicated remote listener is active. Scan the QR code to pair a device.')
                            : _tr('Disattivato (opt-in). Nessuna connessione esterna è accettata.', 'Disabled (opt-in). No external connections are accepted.'),
                        style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _enabled,
                  onChanged: isStarting ? null : (val) => _toggleRemote(val),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Active Remote Connection Details
        if (_enabled && isRunning && _url != null) ...[
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_tr('Associa il tuo Smartphone', 'Pair your smartphone'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),

                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isCompact = constraints.maxWidth < 620;
                      final qrData = _pairingUrl ?? _url!;
                      final qrWidget = Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: tokens.surfaceElevated,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: tokens.overlay.withValues(alpha: 0.15),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: QrImageView(
                          data: qrData,
                          version: QrVersions.auto,
                          size: 160.0,
                          backgroundColor: tokens.surfaceElevated,
                          dataModuleStyle: QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: tokens.textPrimary,
                          ),
                          eyeStyle: QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: tokens.textPrimary,
                          ),
                        ),
                      );

                      final infoWidget = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_tr('1. Inquadra il QR con la fotocamera del telefono', '1. Scan the QR code with your phone camera'), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(_tr('Aprirà la webapp PiFrame con associazione sicura monouso via fragment crittografico.', 'This opens the PiFrame web app with secure, one-time pairing via a cryptographic fragment.'), style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 12),

                          if (_pairingExpiresAt != null) ...[
                            Row(
                              children: [
                                Icon(Icons.timer_outlined, size: 16, color: colorScheme.primary),
                                const SizedBox(width: 6),
                                Text(
                                  _formatExpires(_pairingExpiresAt),
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.primary),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                          ],

                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              OutlinedButton.icon(
                                icon: const Icon(Icons.refresh, size: 16),
                                label: Text(_tr('Nuovo codice QR', 'New QR code')),
                                onPressed: _generateNewPairing,
                              ),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.copy, size: 16),
                                label: Text(_tr('Copia Link di Associazione', 'Copy pairing link')),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: _pairingUrl ?? _url!));
                                  FrameSnackBar.show(
                                    context,
                                    message: _tr('Link di associazione copiato negli appunti!', 'Pairing link copied to clipboard!'),
                                  );
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.open_in_browser, size: 20),
                                tooltip: _tr('Apri nel browser', 'Open in browser'),
                                onPressed: () => launchUrl(Uri.parse(_url!)),
                              ),
                            ],
                          ),
                        ],
                      );

                      if (isCompact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(child: qrWidget),
                            const SizedBox(height: 16),
                            infoWidget,
                          ],
                        );
                      } else {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            qrWidget,
                            const SizedBox(width: 24),
                            Expanded(child: infoWidget),
                          ],
                        );
                      }
                    },
                  ),

                  const SizedBox(height: 16),
                  Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      Icon(Icons.link, size: 18, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(_tr('URL Pubblico: ', 'Public URL: '), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant)),
                      Expanded(
                        child: SelectableText(
                          _url!,
                          style: TextStyle(fontFamily: 'SourceCodePro', fontSize: 12, color: colorScheme.primary),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Security Guardrails & Default Mode Card
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_tr('Modalità Predefinita per Nuovi Dispositivi', 'Default mode for new devices'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(
                    _tr('I nuovi dispositivi associati ricevono questa modalità. Puoi modificarla per singolo dispositivo nella lista sottostante.', 'Newly paired devices receive this mode. You can change it for each device in the list below.'),
                    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'view',
                        label: Text(_tr('Visualizzazione (View)', 'View')),
                        icon: const Icon(Icons.visibility),
                      ),
                      ButtonSegment(
                        value: 'control',
                        label: Text(_tr('Controllo (Control)', 'Control')),
                        icon: const Icon(Icons.settings_remote),
                      ),
                    ],
                    selected: {_defaultMode},
                    onSelectionChanged: (set) {
                      if (set.isNotEmpty) _updateDefaultMode(set.first);
                    },
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _defaultMode == 'view'
                        ? _tr('La modalità View consente di consultare sessioni, log e file in sola lettura, con possibilità di abortire l\'agente in caso di emergenza. Nessun prompt o modifica consentita.', 'View mode provides read-only access to sessions, logs and files, and can abort the agent in an emergency. Prompts and modifications are not allowed.')
                        : _tr('La modalità Control consente di inviare messaggi, avviare sessioni ed eseguire azioni complete tramite l\'agente.', 'Control mode allows sending messages, starting sessions and performing full actions through the agent.'),
                    style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Paired Devices Management
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(_tr('Dispositivi Autorizzati (${_devices.length})', 'Authorized devices (${_devices.length})'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      if (_devices.isNotEmpty)
                        TextButton.icon(
                          icon: Icon(Icons.delete_forever, size: 16, color: colorScheme.error),
                          label: Text(_tr('Revoca Tutti', 'Revoke all'), style: TextStyle(color: colorScheme.error, fontSize: 12)),
                          onPressed: _revokeAllDevices,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (_devices.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        _tr('Nessun dispositivo autorizzato. Inquadra il QR code per associare il tuo smartphone.', 'No authorized devices. Scan the QR code to pair your smartphone.'),
                        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                      ),
                    )
                  else
                    ..._devices.map((dev) {
                      final name = dev['name'] as String? ?? _tr('Dispositivo Sconosciuto', 'Unknown device');
                      final deviceId = dev['deviceId'] as String? ?? '';
                      final mode = dev['mode'] as String? ?? 'view';
                      final ip = dev['remoteIp'] as String? ?? _tr('Locale', 'Local');
                      final lastUsed = dev['lastUsedAt'] as int?;
                      final expiresAt = dev['expiresAt'] as int?;
                      final lastStr = lastUsed != null
                          ? DateTime.fromMillisecondsSinceEpoch(lastUsed).toLocal().toString().split('.')[0]
                          : _tr('Mai', 'Never');
                      final expiresStr = expiresAt != null
                          ? DateTime.fromMillisecondsSinceEpoch(expiresAt).toLocal().toString().split(' ')[0]
                          : '-';

                      final isControl = mode == 'control';

                      return Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              name.contains('iOS') || name.contains('Android') ? Icons.smartphone : Icons.devices,
                              color: colorScheme.primary,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: isControl
                                              ? tokens.accent.withValues(alpha: 0.2)
                                              : tokens.info.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          isControl ? 'CONTROL' : 'VIEW',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: isControl ? tokens.accent : tokens.info,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _tr('IP: $ip • Ultima attività: $lastStr • Scade: $expiresStr', 'IP: $ip • Last active: $lastStr • Expires: $expiresStr'),
                                    style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            DropdownButton<String>(
                              value: mode,
                              underline: const SizedBox(),
                              items: [
                                DropdownMenuItem(value: 'view', child: Text(_tr('Visualizzazione', 'View'), style: const TextStyle(fontSize: 12))),
                                DropdownMenuItem(value: 'control', child: Text(_tr('Controllo', 'Control'), style: const TextStyle(fontSize: 12))),
                              ],
                              onChanged: (newMode) {
                                if (newMode != null) {
                                  _changeDeviceMode(deviceId, mode, newMode, name);
                                }
                              },
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: colorScheme.error,
                                side: BorderSide(color: colorScheme.error.withValues(alpha: 0.5)),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () => _revokeDevice(deviceId, name),
                              child: Text(_tr('Revoca', 'Revoke'), style: const TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        ],

        // Provider configuration
        const SizedBox(height: 20),
        Card(
          elevation: 0,
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_tr('Configurazione Provider Tunnel', 'Tunnel provider settings'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _tunnelProvider,
                      items: [
                        DropdownMenuItem(
                          value: 'tailscale',
                          child: Text(_tr('Tailscale (Consigliato: Permanente, Privato e Sicuro)', 'Tailscale (Recommended: permanent, private and secure)')),
                        ),
                        DropdownMenuItem(
                          value: 'cloudflared',
                          child: Text(_tr('Cloudflare Quick Tunnel (Temporaneo, nessun account)', 'Cloudflare Quick Tunnel (Temporary, no account)')),
                        ),
                        DropdownMenuItem(
                          value: 'custom',
                          child: Text(_tr('Altro Tunnel Personalizzato / Reverse Proxy', 'Other custom tunnel / reverse proxy')),
                        ),
                      ],
                      onChanged: _enabled ? null : (val) => setState(() => _tunnelProvider = val!),
                    ),
                  ),
                ),

                if (_tunnelProvider == 'tailscale') ...[
                  const SizedBox(height: 12),
                  if (!_tailscaleInstalled)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colorScheme.error.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: colorScheme.error, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _tr('Tailscale non è installato su questo computer', 'Tailscale is not installed on this computer'),
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.error),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _tr('Tailscale crea una rete privata sicura Mesh (WireGuard) tra i tuoi dispositivi con certificato HTTPS e nome di dominio fisso permanente.', 'Tailscale creates a secure private mesh network (WireGuard) between your devices with an HTTPS certificate and a permanent domain name.'),
                            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            icon: _isInstallingTailscale
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: tokens.accentContrast,
                                    ),
                                  )
                                : const Icon(Icons.download, size: 18),
                            label: Text(_isInstallingTailscale ? _tr('Avvio installazione...', 'Starting installation...') : _tr('Installa Tailscale automaticamente', 'Install Tailscale automatically')),
                            onPressed: _isInstallingTailscale ? null : _installTailscale,
                          ),
                        ],
                      ),
                    )
                  else if (!_tailscaleRunning)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: tokens.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: tokens.warning.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: tokens.warning, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _tr('Tailscale è installato ma non è connesso. Apri l\'app Tailscale ed effettua il login per attivare la rete.', 'Tailscale is installed but disconnected. Open the Tailscale app and sign in to activate the network.'),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: tokens.info.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: tokens.info.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.verified_user, color: tokens.info, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _tr('Tailscale è attivo e connesso', 'Tailscale is running and connected'),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: tokens.info,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_tailscaleDomain != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _tr('Indirizzo permanente: https://$_tailscaleDomain', 'Permanent address: https://$_tailscaleDomain'),
                              style: TextStyle(fontFamily: 'SourceCodePro', fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.primary),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Text(
                            _tr('Personalizza il nome host della macchina:', 'Customize this machine’s hostname:'),
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _tailscaleHostnameController,
                                  decoration: InputDecoration(
                                    labelText: _tr('Nome host Tailscale (es. pi-frame)', 'Tailscale hostname (e.g. pi-frame)'),
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              FilledButton(
                                onPressed: _isSavingTailscaleHostname ? null : _saveTailscaleHostname,
                                child: _isSavingTailscaleHostname
                                    ? SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: tokens.accentContrast,
                                        ),
                                      )
                                    : Text(_tr('Salva nome', 'Save name')),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],

                if (_tunnelProvider == 'cloudflared') ...[
                  const SizedBox(height: 12),
                  if (_cloudflaredInstalled)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: tokens.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: tokens.success.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline, color: tokens.success, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _tr('cloudflared rilevato e pronto all\'uso', 'cloudflared detected and ready'),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: tokens.success,
                                  ),
                                ),
                                if (_cloudflaredPath != null)
                                  Text(
                                    _cloudflaredPath!,
                                    style: TextStyle(fontFamily: 'SourceCodePro', fontSize: 11, color: colorScheme.onSurfaceVariant),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colorScheme.error.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: colorScheme.error, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _tr('Eseguibile cloudflared non trovato', 'cloudflared executable not found'),
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.error),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _tr('Per utilizzare i Quick Tunnel di Cloudflare è necessario l\'eseguibile ufficiale open-source di Cloudflare.', 'Cloudflare Quick Tunnels require the official open-source Cloudflare executable.'),
                            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            icon: _isInstallingCloudflared
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: tokens.accentContrast,
                                    ),
                                  )
                                : const Icon(Icons.download, size: 18),
                            label: Text(_isInstallingCloudflared ? _tr('Download e installazione in corso...', 'Downloading and installing...') : _tr('Installa cloudflared automaticamente', 'Install cloudflared automatically')),
                            onPressed: _isInstallingCloudflared ? null : _installCloudflared,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _tr('Verrà scaricato in ~/.piframe/bin/cloudflared senza richiedere permessi di amministratore o riavvii.', 'It will be downloaded to ~/.piframe/bin/cloudflared without administrator permissions or a restart.'),
                            style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                ],

                if (_localPort != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _tr('Porta del listener remoto dedicato: $_localPort (127.0.0.1:$_localPort)', 'Dedicated remote listener port: $_localPort (127.0.0.1:$_localPort)'),
                    style: TextStyle(fontFamily: 'SourceCodePro', fontSize: 12, color: colorScheme.primary),
                  ),
                ],

                if (_tunnelProvider == 'custom') ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: _customUrlController,
                    decoration: InputDecoration(
                      labelText: _tr('URL Pubblico HTTPS (es. https://my-node.ts.net)', 'Public HTTPS URL (e.g. https://my-node.ts.net)'),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _customCommandController,
                    decoration: InputDecoration(
                      labelText: _tr('Comando tunnel (eseguito senza shell, "\$PORT" sostituito con la porta listener)', 'Tunnel command (run without a shell; "\$PORT" is replaced with the listener port)'),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(ColorScheme colorScheme, FrameTokens tokens) {
    Color bg;
    Color fg;
    String label;

    switch (_state) {
      case 'running':
        bg = tokens.success.withValues(alpha: 0.2);
        fg = tokens.success;
        label = _tr('ATTIVO', 'ACTIVE');
        break;
      case 'starting':
        bg = tokens.warning.withValues(alpha: 0.2);
        fg = tokens.warning;
        label = _tr('AVVIO...', 'STARTING...');
        break;
      case 'error':
        bg = tokens.danger.withValues(alpha: 0.2);
        fg = tokens.danger;
        label = _tr('ERRORE', 'ERROR');
        break;
      default:
        bg = tokens.textMuted.withValues(alpha: 0.1);
        fg = tokens.textMuted;
        label = _tr('DISATTIVATO', 'DISABLED');
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }
}
