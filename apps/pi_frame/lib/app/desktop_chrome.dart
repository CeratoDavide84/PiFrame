import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:window_manager/window_manager.dart';

import '../data/language/language_settings.dart';
import '../data/window/window_state_service.dart';

// Set only after successful native initialization. Web and widget tests do not
// call platform channels or pretend to own an operating-system window.
final desktopChromeProvider = Provider<bool>((ref) => false);
final desktopWindowLifecycleProvider = Provider<bool>((ref) => false);

class DesktopDragRegion extends ConsumerWidget {
  final Widget child;
  const DesktopDragRegion({super.key, required this.child});
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(desktopChromeProvider) ? DragToMoveArea(child: child) : child;
}

class DesktopCaptionButtons extends ConsumerStatefulWidget {
  final Future<bool> Function()? onCloseRequested;
  const DesktopCaptionButtons({super.key, this.onCloseRequested});
  @override
  ConsumerState<DesktopCaptionButtons> createState() =>
      _DesktopCaptionButtonsState();
}

class _DesktopCaptionButtonsState extends ConsumerState<DesktopCaptionButtons>
    with WindowListener {
  bool _maximized = false;
  bool _closing = false;
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.setPreventClose(widget.onCloseRequested != null);
    _refresh();
  }

  @override
  void onWindowClose() async {
    if (_closing || widget.onCloseRequested == null) return;
    _closing = true;
    final allow = await widget.onCloseRequested!.call();
    if (allow) {
      // Persist the final geometry (including maximized/fullscreen) before the process exits.
      await WindowStateService.instance.recordCurrentWindowState();
      await windowManager.setPreventClose(false);
      await windowManager.close();
    }
    _closing = false;
  }

  Future<void> _refresh() async {
    final maximized = await windowManager.isMaximized();
    if (mounted) setState(() => _maximized = maximized);
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _maximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _maximized = false);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isItalian = ref.watch(appLanguageProvider) == AppLanguage.it;
    final tokens = context.tokens;
    Widget button(
      String label,
      IconData icon,
      VoidCallback action, {
      bool close = false,
    }) => Tooltip(
      message: label,
      child: SizedBox(
        width: 40,
        height: 38,
        child: TextButton(
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            foregroundColor: tokens.textPrimary,
            shape: const RoundedRectangleBorder(),
            overlayColor: close ? tokens.signalDanger : tokens.textPrimary,
          ),
          onPressed: action,
          child: Icon(icon, size: 14),
        ),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(
          isItalian ? 'Riduci a icona' : 'Minimize',
          Icons.remove,
          () => windowManager.minimize(),
        ),
        button(
          _maximized
              ? (isItalian ? 'Ripristina finestra' : 'Restore window')
              : (isItalian ? 'Massimizza finestra' : 'Maximize window'),
          _maximized ? Icons.filter_none : Icons.crop_square,
          () => _maximized
              ? windowManager.unmaximize()
              : windowManager.maximize(),
        ),
        button(
          isItalian ? 'Chiudi finestra' : 'Close window',
          Icons.close,
          () => windowManager.close(),
          close: true,
        ),
      ],
    );
  }
}
