import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/features/settings/usage_section.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

void main() {
  testWidgets('usage settings filter sessions and update totals', (
    tester,
  ) async {
    final now = DateTime.now().toUtc();
    final day = DateTime.utc(now.year, now.month, now.day);
    String date(DateTime d) => d.toIso8601String().substring(0, 10);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          usageAnalyticsProvider.overrideWith(
            (ref) async => {
              'sessions': [
                {
                  'id': 'one',
                  'name': 'Sessione prova',
                  'days': [
                    {
                      'date': date(day),
                      'model': 'test-model',
                      'cost': 1.0,
                      'costCount': 1,
                      'tokens': 12,
                      'messages': 1,
                      'tools': {'read': 1},
                    },
                    {
                      'date': date(day.subtract(const Duration(days: 10))),
                      'model': 'test-model',
                      'cost': 2.0,
                      'costCount': 1,
                      'tokens': 5,
                      'messages': 1,
                      'tools': {},
                    },
                  ],
                },
              ],
            },
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [FrameTokens.dark],
          ),
          home: const Scaffold(body: UsageSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('\$1.0000'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('global-usage-30')));
    await tester.pumpAndSettle();
    expect(find.text('\$3.0000'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Sessione prova'),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Sessione prova'), findsOneWidget);
    await tester.tap(find.text('Sessione prova'));
    await tester.pumpAndSettle();
    expect(find.textContaining('test-model: 2'), findsOneWidget);
  });
}
