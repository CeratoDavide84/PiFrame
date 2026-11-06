import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/daemon/daemon_providers.dart';
import '../../data/daemon/pcp_client.dart';
import '../../data/language/language_settings.dart';

final usageAnalyticsProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) async {
    final client = ref.watch(pcpClientProvider);
    final connection = ref.watch(connectionStateProvider);
    if (client == null || connection.value != DaemonConnectionState.connected) {
      throw StateError('disconnected');
    }
    final result = await client.getUsageAnalytics().timeout(
      const Duration(seconds: 60),
    );
    return Map<String, dynamic>.from(result['data'] as Map? ?? result);
  },
);

class UsageSection extends ConsumerStatefulWidget {
  const UsageSection({super.key});
  @override
  ConsumerState<UsageSection> createState() => _UsageSectionState();
}

class _UsageSectionState extends ConsumerState<UsageSection> {
  int period = 7;
  bool showAll = false;

  @override
  Widget build(BuildContext context) {
    final italian = ref.watch(appLanguageProvider) == AppLanguage.it;
    String tr(String it, String en) => italian ? it : en;
    final tokens = context.tokens;
    final usage = ref.watch(usageAnalyticsProvider);
    return usage.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr(
                'Dati non disponibili. Verifica la connessione al daemon aggiornato.',
                'Data unavailable. Check the connection to the updated daemon.',
              ),
              textAlign: TextAlign.center,
            ),
            TextButton(
              onPressed: () => ref.invalidate(usageAnalyticsProvider),
              child: Text(tr('Riprova', 'Retry')),
            ),
          ],
        ),
      ),
      data: (data) {
        final now = DateTime.now().toUtc();
        final today = DateTime.utc(now.year, now.month, now.day);
        final dates = List.generate(
          period,
          (i) => today
              .subtract(Duration(days: period - i - 1))
              .toIso8601String()
              .substring(0, 10),
        );
        final accepted = dates.toSet();
        final sessions = <_UsageSession>[];
        for (final raw in (data['sessions'] as List? ?? [])) {
          if (raw is! Map) continue;
          final rows = (raw['days'] as List? ?? [])
              .whereType<Map>()
              .where((r) => accepted.contains(r['date']))
              .toList();
          if (rows.isNotEmpty) sessions.add(_UsageSession(raw, rows));
        }
        sessions.sort((a, b) => b.cost.compareTo(a.cost));
        final rows = sessions.expand((s) => s.rows).toList();
        final total = rows.fold<double>(
          0,
          (sum, r) => sum + _number(r['cost']),
        );
        final costCount = rows.fold<int>(
          0,
          (sum, r) => sum + _number(r['costCount']).toInt(),
        );
        final messages = rows.fold<int>(
          0,
          (sum, r) => sum + _number(r['messages']).toInt(),
        );
        final totalTokens = rows.fold<int>(
          0,
          (sum, r) => sum + _number(r['tokens']).toInt(),
        );
        final tokenCount = rows.fold<int>(
          0,
          (sum, r) => sum + _number(r['tokenCount']).toInt(),
        );
        final tools = rows.fold<int>(0, (sum, r) => sum + _toolCount(r));
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    tr('Utilizzo', 'Usage'),
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: tr('Aggiorna', 'Refresh'),
                  onPressed: () => ref.invalidate(usageAnalyticsProvider),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            Text(
              tr(
                'Analisi delle sessioni Pi locali · date UTC',
                'Local Pi session analytics · UTC dates',
              ),
              style: TextStyle(color: tokens.textSecondary),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                for (final n in [7, 30])
                  ChoiceChip(
                    key: ValueKey('global-usage-$n'),
                    label: Text('$n ${tr('g', 'd')}'),
                    selected: period == n,
                    onSelected: (_) => setState(() => period = n),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _Metric(
                  tr('Costo riportato', 'Reported cost'),
                  costCount == 0
                      ? '—'
                      : '\$${total.toStringAsFixed(4)}${costCount < messages ? ' *' : ''}',
                ),
                _Metric(
                  tr('Token', 'Tokens'),
                  tokenCount == 0
                      ? '—'
                      : '$totalTokens${tokenCount < messages ? ' *' : ''}',
                ),
                _Metric(
                  tr('Messaggi assistente', 'Assistant messages'),
                  '$messages',
                ),
                _Metric(tr('Chiamate strumenti', 'Tool calls'), '$tools'),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              tr(
                'Crediti, fatturazione e limiti del provider non sono disponibili. I costi sono quelli riportati da Pi e non corrispondono necessariamente agli addebiti. L’asterisco (*) indica dati parziali.',
                'Provider credits, billing and limits are unavailable. Costs are reported by Pi and do not necessarily equal charges. An asterisk (*) marks partial data.',
              ),
              style: TextStyle(color: tokens.textMuted, fontSize: 12),
            ),
            if (_number(data['unreadable']) > 0 || _number(data['undated']) > 0)
              Text(
                tr(
                  'Alcuni file non sono leggibili o contengono messaggi senza data; tali dati sono esclusi.',
                  'Some files could not be read or contain undated messages; those records are excluded.',
                ),
                style: TextStyle(color: tokens.warning, fontSize: 12),
              ),
            const SizedBox(height: 24),
            _Chart(
              title: tr('Cronologia dei costi', 'Cost history'),
              subtitle: tr(
                'Costi riportati per modello',
                'Reported costs by model',
              ),
              dates: dates,
              rows: rows,
              metric: _ChartMetric.cost,
              italian: italian,
            ),
            const SizedBox(height: 24),
            Text(
              tr('Sessioni principali', 'Top sessions'),
              style: TextStyle(
                color: tokens.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            Text(
              tr(
                'Costi e attività nel periodo selezionato',
                'Costs and activity in the selected period',
              ),
              style: TextStyle(color: tokens.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 8),
            if (sessions.isEmpty)
              Text(
                tr(
                  'Nessuna attività registrata nel periodo.',
                  'No activity recorded in this period.',
                ),
              ),
            for (final session in sessions.take(showAll ? sessions.length : 5))
              Card(
                color: tokens.surfaceElevated,
                child: ExpansionTile(
                  title: Text(
                    session.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    session.child
                        ? tr('Sessione figlia', 'Child session')
                        : tr('Sessione', 'Session'),
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Text(
                    session.costCount == 0
                        ? '—'
                        : '\$${session.cost.toStringAsFixed(4)}${session.costCount < session.messages ? ' *' : ''}',
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${tr('Messaggi', 'Messages')}: ${session.messages} · Token: ${session.tokenCount == 0 ? '—' : '${session.tokens}${session.tokenCount < session.messages ? ' *' : ''}'} · ${tr('Strumenti', 'Tools')}: ${session.tools}',
                          ),
                          for (final e in session.models.entries)
                            Text(
                              '${e.key}: ${e.value} ${tr('messaggi', 'messages')} · ${session.modelCostLabel(e.key)}',
                              style: TextStyle(
                                color: tokens.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if (sessions.length > 5)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => showAll = !showAll),
                  child: Text(
                    showAll
                        ? tr('Mostra meno', 'Show less')
                        : tr('Mostra tutte', 'Show all'),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            _Chart(
              title: tr('Attività degli strumenti', 'Tool activity'),
              subtitle: tr(
                'Chiamate agli strumenti registrate nei messaggi assistente',
                'Tool calls recorded in assistant messages',
              ),
              dates: dates,
              rows: rows,
              metric: _ChartMetric.tools,
              italian: italian,
            ),
            const SizedBox(height: 24),
            _Chart(
              title: tr('Messaggi', 'Messages'),
              subtitle: tr(
                'Messaggi assistente per modello',
                'Assistant messages by model',
              ),
              dates: dates,
              rows: rows,
              metric: _ChartMetric.messages,
              italian: italian,
            ),
            const SizedBox(height: 12),
            Text(
              tr(
                'Le sessioni figlie sono elencate separatamente; ogni file viene conteggiato una volta. La cronologia comprende anche i rami conservati nei file Pi.',
                'Child sessions are listed separately; each file is counted once. History includes branches retained in Pi files.',
              ),
              style: TextStyle(color: tokens.textMuted, fontSize: 11),
            ),
          ],
        );
      },
    );
  }
}

double _number(dynamic n) => n is num && n.isFinite ? n.toDouble() : 0;
int _toolCount(Map row) =>
    (row['tools'] is Map ? (row['tools'] as Map).values : const []).fold<int>(
      0,
      (sum, n) => sum + _number(n).toInt(),
    );

class _UsageSession {
  _UsageSession(Map raw, this.rows)
    : name = '${raw['name'] ?? raw['id']}',
      child = raw['isSubsession'] == true;
  final String name;
  final bool child;
  final List<Map> rows;
  double get cost => rows.fold(0, (s, r) => s + _number(r['cost']));
  int get costCount =>
      rows.fold(0, (s, r) => s + _number(r['costCount']).toInt());
  int get messages =>
      rows.fold(0, (s, r) => s + _number(r['messages']).toInt());
  int get tokens => rows.fold(0, (s, r) => s + _number(r['tokens']).toInt());
  int get tools => rows.fold(0, (s, r) => s + _toolCount(r));
  int get tokenCount =>
      rows.fold(0, (s, r) => s + _number(r['tokenCount']).toInt());
  String modelCostLabel(String model) {
    final matching = rows.where((r) => r['model'] == model);
    final count = matching.fold<int>(
      0,
      (s, r) => s + _number(r['costCount']).toInt(),
    );
    final messages = matching.fold<int>(
      0,
      (s, r) => s + _number(r['messages']).toInt(),
    );
    final total = matching.fold<double>(0, (s, r) => s + _number(r['cost']));
    return count == 0
        ? '—'
        : '\$${total.toStringAsFixed(4)}${count < messages ? ' *' : ''}';
  }

  Map<String, int> get models {
    final result = <String, int>{};
    for (final r in rows) {
      final key = '${r['model']}';
      result[key] = (result[key] ?? 0) + _number(r['messages']).toInt();
    }
    return result;
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: 170,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surfaceElevated,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(t.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: t.textSecondary, fontSize: 11)),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

enum _ChartMetric { cost, tools, messages }

class _Chart extends StatelessWidget {
  const _Chart({
    required this.title,
    required this.subtitle,
    required this.dates,
    required this.rows,
    required this.metric,
    required this.italian,
  });
  final String title, subtitle;
  final List<String> dates;
  final List<Map> rows;
  final _ChartMetric metric;
  final bool italian;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final totals = <String, Map<String, double>>{for (final d in dates) d: {}};
    for (final r in rows) {
      final day = totals[r['date']];
      if (day == null) continue;
      if (metric == _ChartMetric.tools) {
        if (r['tools'] is Map) {
          for (final e in (r['tools'] as Map).entries) {
            final key = '${e.key}';
            day[key] = (day[key] ?? 0) + _number(e.value);
          }
        }
      } else {
        final key = '${r['model']}';
        day[key] =
            (day[key] ?? 0) +
            _number(r[metric == _ChartMetric.cost ? 'cost' : 'messages']);
      }
    }
    String tooltip(String date) {
      final dayRows = rows.where((r) => r['date'] == date);
      final sum = totals[date]!.values.fold<double>(0, (a, b) => a + b);
      if (metric != _ChartMetric.cost) {
        return '$date: ${sum.toStringAsFixed(0)}';
      }
      final count = dayRows.fold<int>(
        0,
        (a, r) => a + _number(r['costCount']).toInt(),
      );
      final messages = dayRows.fold<int>(
        0,
        (a, r) => a + _number(r['messages']).toInt(),
      );
      return count == 0
          ? '$date: —'
          : '$date: \$${sum.toStringAsFixed(4)}${count < messages ? ' *' : ''}';
    }

    final seriesTotals = <String, double>{};
    for (final d in totals.values) {
      for (final e in d.entries) {
        seriesTotals[e.key] = (seriesTotals[e.key] ?? 0) + e.value;
      }
    }
    final names =
        seriesTotals.keys.where((key) => seriesTotals[key]! > 0).toList()
          ..sort((a, b) => seriesTotals[b]!.compareTo(seriesTotals[a]!));
    const colors = [
      Color(0xff4285e8),
      Color(0xffffa15c),
      Color(0xff71d395),
      Color(0xffe891c5),
      Color(0xffae92f0),
    ];
    final shown = names.take(4).toList();
    if (names.length > 4) shown.add(italian ? 'Altro' : 'Other');
    final maximum = totals.values.fold<double>(0, (m, d) {
      final n = d.values.fold<double>(0, (a, b) => a + b);
      return n > m ? n : m;
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: t.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        Text(subtitle, style: TextStyle(color: t.textSecondary, fontSize: 12)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: t.surfaceElevated,
            border: Border.all(color: t.border),
            borderRadius: BorderRadius.circular(t.radiusMd),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (maximum == 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Text(
                    metric == _ChartMetric.cost &&
                            rows.any((r) => _number(r['costCount']) > 0)
                        ? (italian
                              ? 'Costi riportati nel periodo: \$0.0000'
                              : 'Reported costs in this period: \$0.0000')
                        : (italian
                              ? 'Nessun dato disponibile nel periodo.'
                              : 'No data available in this period.'),
                    style: TextStyle(color: t.textMuted),
                  ),
                )
              else ...[
                SizedBox(
                  height: 120,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final date in dates)
                        Expanded(
                          child: Tooltip(
                            message: tooltip(date),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  for (var i = shown.length - 1; i >= 0; i--)
                                    Builder(
                                      builder: (context) {
                                        final value = i == 4
                                            ? totals[date]!.entries
                                                  .where(
                                                    (e) => !shown
                                                        .take(4)
                                                        .contains(e.key),
                                                  )
                                                  .fold<double>(
                                                    0,
                                                    (a, e) => a + e.value,
                                                  )
                                            : (totals[date]![shown[i]] ?? 0);
                                        return Container(
                                          height: value / maximum * 120,
                                          color: colors[i],
                                        );
                                      },
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      dates.first,
                      style: TextStyle(color: t.textMuted, fontSize: 10),
                    ),
                    Text(
                      dates.last,
                      style: TextStyle(color: t.textMuted, fontSize: 10),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < shown.length; i++)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: colors[i],
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            shown[i],
                            style: TextStyle(
                              color: t.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
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
}
