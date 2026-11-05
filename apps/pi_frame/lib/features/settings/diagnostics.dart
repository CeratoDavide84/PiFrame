import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../app/app_version.dart';
import '../../data/daemon/daemon_providers.dart';
import '../../data/language/language_settings.dart';
import '../../data/daemon/pcp_client.dart';
import '../../ui/frame_snack_bar.dart';

/// Tests may label synthetic diagnostic fixtures without changing runtime UI.
final diagnosticsFixtureLabelProvider = Provider<String?>((ref) => null);

class DiagnosticsSection extends ConsumerStatefulWidget {
  const DiagnosticsSection({super.key});

  @override
  ConsumerState<DiagnosticsSection> createState() => _DiagnosticsSectionState();
}

class _DiagnosticsSectionState extends ConsumerState<DiagnosticsSection> {
  bool _isExporting = false;
  String? _exportSuccess;

  String _tr(String it, String en) =>
      ref.read(appLanguageProvider) == AppLanguage.it ? it : en;

  Future<void> _exportBundle() async {
    setState(() {
      _isExporting = true;
      _exportSuccess = null;
    });

    try {
      final sessions = await ref.read(sessionListProvider.future);
      final client = ref.read(pcpClientProvider);
      final activeId = ref.read(activeSessionIdProvider);

      Map<String, dynamic> daemonHealth = {};
      if (client != null) {
        try {
          final res = await client.getDaemonConfig();
          daemonHealth = res['data'] as Map<String, dynamic>? ?? res;
        } catch (_) {}
      }

      // Redacted Diagnostic Bundle (D16: strictly local, secrets scrubbed)
      final bundle = {
        'generatedAt': DateTime.now().toIso8601String(),
        'app': {'name': 'PiFrame', 'version': piFrameVersion, 'protocol': 1},
        'daemon': {
          'status': client?.state.toString() ?? 'unknown',
          'config': {
            'workerIdleTimeoutMs':
                daemonHealth['workerIdleTimeoutMs'] ?? 1800000,
          },
          'token': '[REDACTED]',
        },
        'environment': {
          'activeSessionId': activeId,
          'totalSessionsCount': sessions.length,
          'telemetry': 'DISABLED (D16: zero remote telemetry)',
        },
        'sessionsSummary': sessions
            .map(
              (s) => {
                'id': s['id'],
                'name': s['name'],
                'isActive': s['isActive'] ?? false,
                'messageCount': s['messageCount'],
              },
            )
            .toList(),
      };

      final jsonStr = const JsonEncoder.withIndent('  ').convert(bundle);
      await Clipboard.setData(ClipboardData(text: jsonStr));

      if (mounted) {
        setState(() {
          _isExporting = false;
          _exportSuccess = _tr(
            'Bundle diagnostico copiato negli appunti (tutti i segreti sono stati redatti con [REDACTED])',
            'Diagnostic bundle copied to clipboard (all secrets were redacted with [REDACTED])',
          );
        });

        FrameSnackBar.show(
          context,
          message: _tr(
            'Bundle diagnostico copiato negli appunti!',
            'Diagnostic bundle copied to clipboard!',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isExporting = false;
          _exportSuccess = _tr(
            'Errore durante esportazione: $e',
            'Export failed: $e',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appLanguageProvider);
    final tokens = context.tokens;
    final connState =
        ref.watch(connectionStateProvider).value ??
        DaemonConnectionState.disconnected;
    final sessions = ref.watch(sessionListProvider).value ?? [];
    final fixtureLabel = ref.watch(diagnosticsFixtureLabelProvider);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (fixtureLabel != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            color: tokens.signalWarning.withValues(alpha: 0.16),
            child: Row(
              children: [
                Icon(
                  Icons.science_outlined,
                  size: 16,
                  color: tokens.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    fixtureLabel,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        // Title & description
        Text(
          _tr(
            'Diagnostica locale e stato del sistema',
            'Local diagnostics & system status',
          ),
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _tr(
            'Tutti i dati di diagnostica rimangono confinati sulla tua macchina locale. In conformità con la politica di privacy D16, nessun dato viene mai trasmesso a server esterni.',
            'All diagnostic data stays on your local machine. In accordance with the D16 privacy policy, no data is ever sent to external servers.',
          ),
          style: TextStyle(
            color: tokens.textSecondary,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 20),

        // System state card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            border: Border.all(color: tokens.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _tr('STATO ATTUALE DEL RUNTIME', 'CURRENT RUNTIME STATUS'),
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              _buildMetricRow(
                _tr('Connessione daemon', 'Daemon connection'),
                connState.name.toUpperCase(),
                tokens,
                color: connState == DaemonConnectionState.connected
                    ? tokens.agentSettled
                    : tokens.warning,
              ),
              _buildMetricRow(
                _tr('Versione app PiFrame', 'PiFrame app version'),
                'v$piFrameVersion',
                tokens,
              ),
              _buildMetricRow(
                'Protocollo PCP',
                'PCP/1 (JSON over WebSocket)',
                tokens,
              ),
              _buildMetricRow(
                _tr('Sessioni archiviate', 'Stored sessions'),
                '${sessions.length}',
                tokens,
              ),
              _buildMetricRow(
                _tr('Telemetria remota', 'Remote telemetry'),
                _tr(
                  'DISABILITATA (Zero Analytics)',
                  'DISABLED (Zero analytics)',
                ),
                tokens,
                color: tokens.agentSettled,
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Export Diagnostic Bundle
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tokens.surfaceElevated,
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            border: Border.all(color: tokens.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.bug_report_outlined,
                    color: tokens.accent,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _tr(
                        'Esporta bundle diagnostico',
                        'Export diagnostic bundle',
                      ),
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _tr(
                  'Genera un rapporto diagnostico completo in formato JSON. Token, credenziali e percorsi sensibili vengono anonimizzati e oscurati prima della copia negli appunti.',
                  'Generate a full diagnostic report in JSON format. Tokens, credentials and sensitive paths are anonymized and redacted before being copied to the clipboard.',
                ),
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: tokens.accent,
                  foregroundColor: tokens.accentContrast,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                  ),
                ),
                icon: _isExporting
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: tokens.accentContrast,
                        ),
                      )
                    : const Icon(Icons.copy, size: 16),
                label: Text(
                  _isExporting
                      ? _tr('Generazione...', 'Generating...')
                      : _tr(
                          'Copia bundle diagnostico negli appunti',
                          'Copy diagnostic bundle to clipboard',
                        ),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: _isExporting ? null : _exportBundle,
              ),
              if (_exportSuccess != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 14,
                      color: tokens.agentSettled,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _exportSuccess!,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricRow(
    String label,
    String value,
    FrameTokens tokens, {
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final labelWidget = Text(
            label,
            style: TextStyle(color: tokens.textSecondary, fontSize: 13),
          );
          final valueText = Text(
            value,
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          );
          final valueWidget = color == null
              ? valueText
              : Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    border: Border.all(color: tokens.border),
                  ),
                  child: valueText,
                );
          if (constraints.maxWidth < 520) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [labelWidget, const SizedBox(height: 4), valueWidget],
              ),
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: labelWidget),
              const SizedBox(width: 16),
              Expanded(child: valueWidget),
            ],
          );
        },
      ),
    );
  }
}
