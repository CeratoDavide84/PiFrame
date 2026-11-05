import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame/app/desktop_chrome.dart';
import 'package:pi_frame/ui/precision.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

final _motionTheme = ThemeSpec(
  id: 'test',
  name: 'test',
  variant: 'light',
).toThemeData();

Widget themed(Widget child, {bool reduced = false}) => MaterialApp(
  theme: _motionTheme,
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: Scaffold(body: child),
  ),
);

void main() {
  testWidgets(
    'startup is once-only and pointer input completes it without blocking the action',
    (tester) async {
      var actions = 0;
      await tester.pumpWidget(
        themed(
          LaunchReveal(
            child: Column(
              children: [
                const PiFrameMark(),
                FilledButton(
                  onPressed: () => actions++,
                  child: const Text('Azione'),
                ),
              ],
            ),
          ),
        ),
      );
      final fade = find.byKey(const ValueKey('launch-opacity'));
      expect(tester.widget<FadeTransition>(fade).opacity.value, lessThan(1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(
        tester.widget<FadeTransition>(fade).opacity.value,
        greaterThan(0.82),
      );
      await tester.tap(find.text('Azione'));
      await tester.pump();
      expect(actions, 1);
      expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.binding.transientCallbackCount, 0);
    },
  );
  testWidgets('startup settles at 620ms and does not replay on rebuild', (
    tester,
  ) async {
    await tester.pumpWidget(themed(const LaunchReveal(child: PiFrameMark())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 620));
    await tester.pump();
    expect(
      tester
          .widget<FadeTransition>(find.byKey(const ValueKey('launch-opacity')))
          .opacity
          .value,
      1,
    );
    await tester.pumpWidget(
      themed(
        const LaunchReveal(
          child: Row(children: [PiFrameMark(), Text('Sessione')]),
        ),
      ),
    );
    expect(
      tester
          .widget<FadeTransition>(find.byKey(const ValueKey('launch-opacity')))
          .opacity
          .value,
      1,
    );
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });
  testWidgets('reduced motion suppresses startup movement and press scaling', (
    tester,
  ) async {
    await tester.pumpWidget(
      themed(
        const LaunchReveal(
          child: PressFeedback(
            child: SizedBox(width: 60, height: 40, child: Text('Azione')),
          ),
        ),
        reduced: true,
      ),
    );
    expect(
      tester
          .widget<SlideTransition>(
            find.byKey(const ValueKey('launch-transform')),
          )
          .position
          .value,
      Offset.zero,
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Azione')),
    );
    await tester.pump();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    await gesture.up();
    expect(tester.binding.transientCallbackCount, 0);
  });
  testWidgets(
    'press feedback responds to pointer down, not keyboard activation',
    (tester) async {
      await tester.pumpWidget(
        themed(
          PressFeedback(
            child: FilledButton(
              autofocus: true,
              onPressed: () {},
              child: const Text('Invia'),
            ),
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Invia')),
      );
      await tester.pump();
      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
        0.97,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    },
  );
  testWidgets('caption drag region starts native window movement', (
    tester,
  ) async {
    final calls = <String>[];
    const channel = MethodChannel('window_manager');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      return call.method == 'isFullScreen' ? false : null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      themed(
        ProviderScope(
          overrides: [desktopChromeProvider.overrideWithValue(true)],
          child: const DesktopDragRegion(
            child: SizedBox(width: 240, height: 44),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      const Offset(100, 22),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(24, 18));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(calls, contains('startDragging'));
  });

  testWidgets('caption controls call native minimize, maximize and close', (
    tester,
  ) async {
    final calls = <String>[];
    const channel = MethodChannel('window_manager');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      return call.method == 'isMaximized' ? false : null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(child: themed(const DesktopCaptionButtons())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Riduci a icona'));
    await tester.tap(find.byTooltip('Massimizza finestra'));
    await tester.tap(find.byTooltip('Chiudi finestra'));
    await tester.pump();
    expect(
      calls,
      containsAllInOrder(['isMaximized', 'minimize', 'maximize', 'close']),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
