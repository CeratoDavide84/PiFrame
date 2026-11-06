import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/features/transcript/usage_history_chart.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

void main() {
  testWidgets(
    'filters dated costs by selected period and reports missing data',
    (tester) async {
      final now = DateTime.now().toUtc();
      final today = DateTime.utc(now.year, now.month, now.day);
      String date(DateTime d) => d.toIso8601String().substring(0, 10);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [FrameTokens.dark],
          ),
          home: Scaffold(
            body: UsageHistoryChart(
              italian: true,
              costByDay: {
                date(today): 0.5,
                date(today.subtract(const Duration(days: 10))): 1.0,
              },
            ),
          ),
        ),
      );
      expect(find.text('\$0.5000'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('usage-period-30')));
      await tester.pump();
      expect(find.text('\$1.5000'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [FrameTokens.dark],
          ),
          home: const Scaffold(
            body: UsageHistoryChart(italian: true, costByDay: null),
          ),
        ),
      );
      expect(
        find.text('Nessun costo datato disponibile nel periodo.'),
        findsOneWidget,
      );
    },
  );
}
