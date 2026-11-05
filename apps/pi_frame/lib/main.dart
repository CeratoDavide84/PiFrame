import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

import 'app/desktop_chrome.dart';
import 'ui/precision.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'data/theme/theme_providers.dart';
import 'data/language/language_settings.dart';
import 'data/notifications/desktop_notification_service.dart';
import 'data/window/window_state_service.dart';
import 'ui/startup_assemble_animation.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final isWindows =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  final isMacOS =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
  final customDesktopChrome = isWindows || isMacOS;
  final desktopWindowLifecycle = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);
  if (desktopWindowLifecycle) {
    await windowManager.ensureInitialized();
    await windowManager.setTitle('PiFrame');
    await windowManager.setMinimumSize(const Size(680, 480));
    if (isWindows) {
      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );
    } else if (isMacOS) {
      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: true,
      );
    }
    await DesktopNotificationService.instance.initialize();
    await WindowStateService.instance.restoreWindow();
  }
  runApp(
    ProviderScope(
      overrides: [
        desktopChromeProvider.overrideWithValue(customDesktopChrome),
        desktopWindowLifecycleProvider.overrideWithValue(desktopWindowLifecycle),
      ],
      child: const PiFrameApp(),
    ),
  );
}

class PiFrameApp extends ConsumerWidget {
  const PiFrameApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeData = ref.watch(currentThemeDataProvider);
    final language = ref.watch(appLanguageProvider);

    return MaterialApp.router(
      title: 'PiFrame',
      locale: Locale(language.code),
      supportedLocales: const [Locale('it'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter,
      theme: themeData,
      builder: (context, child) => LaunchReveal(
        child: StartupAssembleOverlay(
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
