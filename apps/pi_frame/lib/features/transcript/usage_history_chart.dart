import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

/// Daily costs reported in the current Pi session, grouped by UTC date.
class UsageHistoryChart extends StatefulWidget {
  const UsageHistoryChart({
    super.key,
    required this.costByDay,
    required this.italian,
  });
  final dynamic costByDay;
  final bool italian;

  @override
  State<UsageHistoryChart> createState() => _UsageHistoryChartState();
}

class _UsageHistoryChartState extends State<UsageHistoryChart> {
  int days = 7;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final raw = widget.costByDay;
    final values = <String, double>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        if (entry.key is String &&
            entry.value is num &&
            (entry.value as num).isFinite &&
            (entry.value as num) >= 0) {
          values[entry.key as String] = (entry.value as num).toDouble();
        }
      }
    }
    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);
    final dates = List.generate(
      days,
      (i) => today.subtract(Duration(days: days - i - 1)),
    );
    String key(DateTime date) => date.toIso8601String().substring(0, 10);
    final daily = dates.map((date) => values[key(date)]).toList();
    final maxValue = daily.fold<double>(
      0,
      (max, value) => value != null && value > max ? value : max,
    );
    final total = daily.fold<double>(0, (sum, value) => sum + (value ?? 0));
    final hasData = daily.any((value) => value != null);
    final title = widget.italian
        ? 'Cronologia costi della sessione'
        : 'Session cost history';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(t.radiusSm),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              for (final period in [7, 30])
                TextButton(
                  key: ValueKey('usage-period-$period'),
                  onPressed: () => setState(() => days = period),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(30, 28),
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    foregroundColor: period == days ? t.accent : t.textMuted,
                  ),
                  child: Text(
                    '$period ${widget.italian ? 'g' : 'd'}',
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
            ],
          ),
          Text(
            widget.italian
                ? 'Costi riportati da Pi · date UTC · solo sessione corrente'
                : 'Costs reported by Pi · UTC dates · current session only',
            style: TextStyle(color: t.textMuted, fontSize: 10),
          ),
          const SizedBox(height: 8),
          if (!hasData)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                widget.italian
                    ? 'Nessun costo datato disponibile nel periodo.'
                    : 'No dated costs available in this period.',
                style: TextStyle(color: t.textSecondary, fontSize: 11),
              ),
            )
          else ...[
            Text(
              '\$${total.toStringAsFixed(4)}',
              key: const ValueKey('usage-period-total'),
              style: TextStyle(
                color: t.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 85,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < days; i++)
                    Expanded(
                      child: Tooltip(
                        message:
                            '${key(dates[i])}: ${daily[i] == null ? '—' : '\$${daily[i]!.toStringAsFixed(4)}'}',
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 1),
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              height: maxValue == 0
                                  ? 1
                                  : ((daily[i] ?? 0) / maxValue * 80).clamp(
                                      1.0,
                                      80.0,
                                    ),
                              decoration: BoxDecoration(
                                color: daily[i] == null ? t.border : t.accent,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(2),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  key(dates.first),
                  style: TextStyle(color: t.textMuted, fontSize: 9),
                ),
                Text(
                  key(dates.last),
                  style: TextStyle(color: t.textMuted, fontSize: 9),
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Text(
            widget.italian
                ? 'I crediti e i limiti del provider non sono disponibili; i costi senza data sono esclusi.'
                : 'Provider credits and limits are unavailable; costs without dates are excluded.',
            style: TextStyle(color: t.textMuted, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
