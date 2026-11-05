import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:pi_frame/features/settings/pi_cli_section.dart';

void main() {
  testWidgets('PiCliSection renders all pi command buttons and custom input', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    const tokens = FrameTokens.dark;

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(
        home: Scaffold(
          body: PiCliSection(tokens: tokens),
        ),
      )),
    );
    await tester.pumpAndSettle();

    // Verify Title
    expect(find.text('Interfaccia Pi CLI'), findsOneWidget);

    // Verify Key Command Buttons
    expect(find.text('Aggiorna Pi CLI'), findsOneWidget);
    expect(find.text('pi update'), findsOneWidget);

    expect(find.text('Aggiorna Estensioni'), findsOneWidget);
    expect(find.text('pi update --extensions'), findsOneWidget);

    expect(find.text('Aggiorna Catalogo Modelli'), findsOneWidget);
    expect(find.text('pi update --models'), findsOneWidget);

    expect(find.text('Aggiorna Tutto'), findsOneWidget);
    expect(find.text('pi update --all'), findsOneWidget);

    expect(find.text('Elenco Estensioni'), findsOneWidget);
    expect(find.text('Stato Server MCP'), findsOneWidget);
    expect(find.text('Versione Pi CLI'), findsOneWidget);

    // Verify Custom Command Input
    expect(find.text('COMANDO PERSONALIZZATO'), findsOneWidget);
    expect(find.text('pi '), findsOneWidget);
    expect(find.text('Esegui'), findsWidgets);

    // Verify Output Console
    expect(find.text('OUTPUT CONSOLE'), findsOneWidget);
  });
}
