import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_chrome.dart';
import '../ui/precision.dart';
import '../data/daemon/daemon_providers.dart';
import '../data/daemon/pcp_client.dart';
import '../data/language/language_settings.dart';
import '../data/theme/theme_providers.dart';
import '../features/sessions_sidebar/sessions_sidebar.dart';
import '../features/sessions_sidebar/session_actions.dart';
import '../features/transcript/transcript_view.dart';
import '../features/transcript/chat_drop_target.dart';
import '../features/composer/composer.dart';
import '../features/context_panel/context_panel.dart';
import '../features/workspace/pane_drag_state.dart';
import '../features/workspace/repository_workspace.dart';
import '../features/browser/browser_models.dart';
import '../features/browser/browser_controller.dart';
import '../features/browser/web_browser_pane.dart';
import '../features/command_palette/command_palette.dart';
import '../features/settings/settings_view.dart';
import '../data/notifications/notification_providers.dart';
import '../data/notifications/session_notification_watcher.dart';
import '../data/notifications/taskbar_status_reporter.dart';
import '../features/settings/updates_watcher.dart';
import '../data/update/update_providers.dart';
import '../features/session_changes/session_changes_provider.dart';
import '../features/session_changes/session_changes_pane.dart';
import '../data/pi_install/pi_install_service.dart';
import '../features/dialogs/pi_install_dialog.dart';
import '../features/updates/startup_update_banner.dart';
import '../features/updates/startup_updates_watcher.dart';
import '../data/window/window_state_service.dart';
import '../data/layout/layout_store.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});
  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WindowListener, WidgetsBindingObserver {
  String _tr(String italian, String english) =>
      ref.read(appLanguageProvider) == AppLanguage.it ? italian : english;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _closingWindow = false;
  late final bool _handlesNativeClose;
  late final bool _hasWindowListener;
  bool _creating = false;
  WorkspacePane _compactPane = WorkspacePane.chat;
  WorkspacePane _companionPane = WorkspacePane.repository;
  final Map<WorkspacePane, bool> _paneVisibility = {
    WorkspacePane.repository: true,
    WorkspacePane.chat: true,
    WorkspacePane.git: true,
  };
  final Map<WorkspacePane, double> _paneWeights = {
    WorkspacePane.repository: 32,
    WorkspacePane.chat: 44,
    WorkspacePane.git: 24,
  };
  final Set<WorkspacePane> _collapsedPanes = {};
  final Map<WorkspacePane, double> _savedPaneWeights = {
    WorkspacePane.repository: 32,
    WorkspacePane.chat: 44,
    WorkspacePane.git: 24,
  };
  bool _sidebarCollapsed = false;
  bool? _preReviewSidebarCollapsed;
  Map<WorkspacePane, bool>? _preReviewPaneVisibility;
  Map<WorkspacePane, double>? _preReviewPaneWeights;

  void _enterReviewMode() {
    _preReviewSidebarCollapsed ??= _sidebarCollapsed;
    _preReviewPaneVisibility ??= Map.from(_paneVisibility);
    _preReviewPaneWeights ??= Map.from(_paneWeights);

    setState(() {
      _sidebarCollapsed = true; // Minimize Sessions pane
      _paneVisibility[WorkspacePane.repository] = false; // Hide Repository pane
      _paneVisibility[WorkspacePane.chat] = true;
      _paneVisibility[WorkspacePane.git] =
          true; // Use Git slot for Review Changes
      _paneWeights[WorkspacePane.chat] = 50.0;
      _paneWeights[WorkspacePane.git] = 50.0;
      _collapsedPanes.remove(WorkspacePane.chat);
      _collapsedPanes.remove(WorkspacePane.git);
    });
  }

  void _exitReviewMode() {
    setState(() {
      if (_preReviewSidebarCollapsed != null) {
        _sidebarCollapsed = _preReviewSidebarCollapsed!;
      }
      if (_preReviewPaneVisibility != null) {
        _paneVisibility.clear();
        _paneVisibility.addAll(_preReviewPaneVisibility!);
      }
      if (_preReviewPaneWeights != null) {
        _paneWeights.clear();
        _paneWeights.addAll(_preReviewPaneWeights!);
      }
      _preReviewSidebarCollapsed = null;
      _preReviewPaneVisibility = null;
      _preReviewPaneWeights = null;
    });
    _persistLayout();
  }

  // Review mode temporarily replaces the layout; persist only the user's own layout.
  void _persistLayout() {
    if (_preReviewPaneVisibility != null) return;
    LayoutStore.instance.save({
      'visibility': {
        for (final pane in WorkspacePane.values) pane.name: _paneVisibility[pane] ?? true,
      },
      'sidebarCollapsed': _sidebarCollapsed,
    });
  }

  // Restores hidden panes after restart; keeps at least one pane visible and the companion valid.
  void _applyPersistedLayout() {
    final saved = LayoutStore.instance.load();
    final visibility = saved['visibility'];
    if (visibility is Map) {
      for (final pane in WorkspacePane.values) {
        final value = visibility[pane.name];
        if (value is bool) _paneVisibility[pane] = value;
      }
    }
    if (saved['sidebarCollapsed'] is bool) {
      _sidebarCollapsed = saved['sidebarCollapsed'] as bool;
    }
    if (!_paneVisibility.containsValue(true)) {
      _paneVisibility[WorkspacePane.chat] = true;
    }
    final remaining = _visiblePanes();
    if (!remaining.contains(_compactPane)) _compactPane = remaining.first;
    if (!remaining.contains(_companionPane)) {
      _companionPane = remaining.firstWhere(
        (item) => item != WorkspacePane.chat,
        orElse: () => remaining.first,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applyPersistedLayout();
    final desktopLifecycle = ref.read(desktopWindowLifecycleProvider);
    _handlesNativeClose = desktopLifecycle && defaultTargetPlatform != TargetPlatform.windows;
    _hasWindowListener = desktopLifecycle;
    if (_hasWindowListener) {
      windowManager.addListener(this);
      if (_handlesNativeClose) {
        unawaited(windowManager.setPreventClose(true));
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkFirstRunPiInstall();
    });
  }

  Future<void> _checkFirstRunPiInstall() async {
    final service = ref.read(piInstallServiceProvider);
    final isFirst = await service.isFirstRun();
    if (!isFirst || !mounted) return;
    final isInstalled = await service.isPiInstalled();
    if (!isInstalled && mounted) {
      await PiInstallDialog.show(context);
    }
  }

  @override
  void onWindowFocus() {
    ref.read(appFocusProvider.notifier).state = true;
  }

  @override
  void onWindowBlur() {
    ref.read(appFocusProvider.notifier).state = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(appFocusProvider.notifier).state = true;
    } else {
      ref.read(appFocusProvider.notifier).state = false;
    }
  }

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    ref.read(activeThemeSpecProvider.notifier).onPlatformBrightnessChanged(
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
  }

  @override
  void onWindowResize() {
    WindowStateService.instance.debounceRecordCurrentState();
  }

  @override
  void onWindowMove() {
    WindowStateService.instance.debounceRecordCurrentState();
  }

  @override
  void onWindowEnterFullScreen() {
    WindowStateService.instance.recordCurrentWindowState();
  }

  @override
  void onWindowLeaveFullScreen() {
    WindowStateService.instance.recordCurrentWindowState();
  }

  @override
  void onWindowMaximize() {
    WindowStateService.instance.recordCurrentWindowState();
  }

  @override
  void onWindowUnmaximize() {
    WindowStateService.instance.recordCurrentWindowState();
  }

  @override
  void onWindowClose() async {
    if (_closingWindow || !_handlesNativeClose) return;
    _closingWindow = true;
    try {
      unawaited(WindowStateService.instance.recordCurrentWindowState());
      final allowClose = await resolveDirtyRepository(
        context,
        ref,
        ref.read(activeSessionIdProvider),
      );
      if (!mounted || !allowClose) return;
      await windowManager.setPreventClose(false);
      await windowManager.close();
    } finally {
      _closingWindow = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_hasWindowListener) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  void _palette() => CommandPalette.show(
    context,
    onOpenSettings: () => ref.read(showSettingsProvider.notifier).state = true,
  );
  Future<void> _create() async {
    if (_creating) return;
    setState(() => _creating = true);
    await createSession(context, ref);
    if (mounted) setState(() => _creating = false);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appLanguageProvider);
    ref.listen<bool>(isReviewingChangesProvider, (prev, next) {
      if (next) {
        _enterReviewMode();
      } else {
        _exitReviewMode();
      }
    });

    final tokens = context.tokens;
    final activeId = ref.watch(activeSessionIdProvider);
    final settings = ref.watch(showSettingsProvider);
    final connection =
        ref.watch(connectionStateProvider).value ??
        DaemonConnectionState.disconnected;
    final connected = connection == DaemonConnectionState.connected;
    final width = MediaQuery.sizeOf(context).width;
    final showSessionRail = width >= 1560;
    final nativeChrome = ref.watch(desktopChromeProvider);
    Widget workArea() => activeId == null
        ? _welcome(tokens, !showSessionRail, connected)
        : ChatDropTarget(
            key: ValueKey('chat_drop_target_$activeId'),
            sessionId: activeId,
            child: Column(
              children: [
                Expanded(
                  child: TranscriptView(
                    key: ValueKey('transcript_$activeId'),
                    sessionId: activeId,
                  ),
                ),
                Composer(
                  key: ValueKey('composer_$activeId'),
                  sessionId: activeId,
                ),
              ],
            ),
          );

    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.keyK &&
            (HardwareKeyboard.instance.isMetaPressed ||
                HardwareKeyboard.instance.isControlPressed)) {
          _palette();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: tokens.background,
        drawer: Drawer(
          width: 280,
          child: SessionsSidebar(
            onSessionSelected: () => _scaffoldKey.currentState?.closeDrawer(),
          ),
        ),
        endDrawer: activeId == null
            ? null
            : Drawer(
                width: width < 420 ? width - 24 : 320,
                child: SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _tr('Area di lavoro', 'Workspace'),
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            IconButton(
                              tooltip: _tr('Chiudi workspace', 'Close workspace'),
                              icon: const Icon(Icons.close),
                              onPressed: () =>
                                  _scaffoldKey.currentState?.closeEndDrawer(),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ContextPanel(
                          key: ValueKey('drawer-context_$activeId'),
                          sessionId: activeId,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        body: Stack(
          children: [
            const SessionNotificationWatcher(),
            const TaskbarStatusReporter(),
            const UpdatesPeriodicWatcher(),
            const StartupUpdatesWatcher(),
            SafeArea(
              child: Column(
                children: [
                  Container(
                    height: 42,
                    margin: EdgeInsets.fromLTRB(
                      width < 600 ? 12 : 8,
                      width < 600 ? 6 : 4,
                      width < 600 ? 12 : 8,
                      4,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.chassis,
                      borderRadius: BorderRadius.circular(tokens.radiusMd),
                      border: Border.all(color: tokens.border),
                    ),
                    child: Row(
                      children: [
                        if (!kIsWeb &&
                            defaultTargetPlatform == TargetPlatform.macOS &&
                            nativeChrome)
                          const SizedBox(width: 76),
                        if (!showSessionRail)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: _tr('Apri sessioni', 'Open sessions'),
                            icon: const Icon(Icons.menu, size: 17),
                            onPressed: () =>
                                _scaffoldKey.currentState?.openDrawer(),
                          ),
                        Expanded(
                          child: DesktopDragRegion(
                            child: Padding(
                              padding: EdgeInsets.only(
                                left: showSessionRail ? 16 : 4,
                              ),
                              child: Row(
                                children: [
                                  const PiFrameMark(size: 18),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: const BrandWordmark(size: 15),
                                    ),
                                  ),
                                  if (width > 920) ...[
                                    const SizedBox(width: 20),
                                    Icon(
                                      connected ? Icons.link : Icons.link_off,
                                      size: 14,
                                      color: tokens.textMuted,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      connected ? _tr('Pi locale', 'Local Pi') : _tr('Non connesso', 'Disconnected'),
                                      style: TextStyle(
                                        color: tokens.textMuted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (width > 680)
                          PressFeedback(
                            child: TextButton.icon(
                              onPressed: _palette,
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                foregroundColor: tokens.textSecondary,
                              ),
                              icon: const Icon(Icons.search, size: 15),
                              label: Text(
                                _tr('Comandi', 'Commands'),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        if (width >= 900 && activeId != null && !settings)
                          PopupMenuButton<WorkspacePane>(
                            tooltip: _tr('Mostra o nascondi pannelli', 'Show or hide panels'),
                            icon: const Icon(
                              Icons.view_column_outlined,
                              size: 16,
                            ),
                            padding: EdgeInsets.zero,
                            onSelected: _togglePane,
                            itemBuilder: (context) => [
                              for (final pane in WorkspacePane.values)
                                PopupMenuItem(
                                  value: pane,
                                  child: Row(
                                    children: [
                                      Icon(
                                        _paneVisibility[pane] == true
                                            ? Icons.check_box_outlined
                                            : Icons.check_box_outline_blank,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(_paneLabel(pane)),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          tooltip:
                              Theme.of(context).brightness == Brightness.light
                              ? _tr('Tema scuro', 'Dark theme')
                              : _tr('Tema chiaro', 'Light theme'),
                          icon: Icon(
                            Theme.of(context).brightness == Brightness.light
                                ? Icons.dark_mode_outlined
                                : Icons.light_mode_outlined,
                            size: 16,
                          ),
                          onPressed: () => ref
                              .read(activeThemeSpecProvider.notifier)
                              .setTheme(
                                Theme.of(context).brightness == Brightness.light
                                    ? 'piframe-dark'
                                    : 'piframe-light',
                              ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          tooltip: _tr('Impostazioni', 'Settings'),
                          icon: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              const Icon(Icons.settings_outlined, size: 16),
                              Positioned(
                                top: -2,
                                right: -2,
                                child: Consumer(
                                  builder: (context, ref, _) {
                                    if (!ref.watch(hasUpdateBadgeProvider)) {
                                      return const SizedBox.shrink();
                                    }
                                    return Container(
                                      width: 7,
                                      height: 7,
                                      decoration: BoxDecoration(
                                        color: tokens.accent,
                                        shape: BoxShape.circle,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                          onPressed: () =>
                              ref.read(showSettingsProvider.notifier).state =
                                  !settings,
                        ),
                        if (activeId != null && !settings)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            tooltip: _tr('Modello e azioni sessione', 'Model and session actions'),
                            icon: const Icon(Icons.tune, size: 16),
                            onPressed: () =>
                                _scaffoldKey.currentState?.openEndDrawer(),
                          ),
                        if (nativeChrome &&
                            defaultTargetPlatform == TargetPlatform.windows) ...[
                          Container(
                            width: 1,
                            height: 18,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            color: tokens.borderStrong,
                          ),
                          DesktopCaptionButtons(
                            onCloseRequested: () =>
                                resolveDirtyRepository(context, ref, activeId),
                          ),
                        ] else
                          const SizedBox(width: 6),
                      ],
                    ),
                  ),
                  if (!connected)
                    Container(
                      color: tokens.signalWarning.withValues(alpha: 0.16),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.link_off, size: 17, color: tokens.warning),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              connection == DaemonConnectionState.reconnecting
                                  ? _tr('Riconnessione al daemon in corso...', 'Reconnecting to the daemon...')
                                  : _tr('Daemon non raggiungibile. Le sessioni restano gestite da Pi.', 'Daemon unavailable. Sessions remain managed by Pi.'),
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: tokens.textPrimary,
                            ),
                            onPressed: () =>
                                ref.invalidate(daemonEndpointProvider),
                            child: Text(_tr('Riprova', 'Retry')),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: settings
                        ? SettingsView(
                            initialTabIndex:
                                ref.watch(settingsTabIndexProvider),
                            onClose: () =>
                                ref.read(showSettingsProvider.notifier).state =
                                    false,
                          )
                        : Row(
                            children: [
                              if (showSessionRail)
                                _sidebarCollapsed
                                    ? _collapsedSidebarStrip(tokens)
                                    : _bentoPane(
                                        SizedBox(
                                          width: 280,
                                          child: SessionsSidebar(
                                            onCollapse: () {
                                              setState(() => _sidebarCollapsed = true);
                                              _persistLayout();
                                            },
                                          ),
                                        ),
                                      ),
                              Expanded(
                                child: activeId == null
                                    ? RepaintBoundary(child: workArea())
                                    : _workspace(activeId, width, workArea),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
            const StartupUpdateBanner(),
          ],
        ),
      ),
    );
  }

  Widget _workspace(String sessionId, double width, Widget Function() chat) {
    final isReviewing = ref.watch(isReviewingChangesProvider);
    final visible = _visiblePanes(chatFirst: width < 900);
    final companions = visible
        .where((pane) => pane != WorkspacePane.chat)
        .toList();
    final companionTabs =
        width >= 900 && width < 1440 && companions.length > 1
            ? companions
            : null;
    final selectedCompanion = companions.contains(_companionPane)
        ? _companionPane
        : (companions.isNotEmpty ? companions.first : null);

    final panes = <WorkspacePane, Widget>{
      WorkspacePane.repository: RepositoryPane(
        key: ValueKey('repo_$sessionId'),
        sessionId: sessionId,
        onCollapse: () => _collapsePane(WorkspacePane.repository),
        companionTabs: companionTabs,
        activeCompanionTab: selectedCompanion,
        onSelectCompanionTab: (pane) => setState(() => _companionPane = pane),
      ),
      WorkspacePane.chat: chat(),
      WorkspacePane.git: isReviewing
          ? SessionChangesPane(
              key: ValueKey('review_changes_$sessionId'),
              sessionId: sessionId,
              onClose: () =>
                  ref.read(isReviewingChangesProvider.notifier).state = false,
              companionTabs: companionTabs,
              activeCompanionTab: selectedCompanion,
              onSelectCompanionTab: (pane) =>
                  setState(() => _companionPane = pane),
            )
          : (ref.watch(browserPaneSupportedProvider) &&
                  ref.watch(rightPaneModeProvider) == RightPaneMode.browser
              ? WebBrowserPane(
                  key: ValueKey('browser_$sessionId'),
                  sessionId: sessionId,
                  onCollapse: () => _collapsePane(WorkspacePane.git),
                  companionTabs: companionTabs,
                  activeCompanionTab: selectedCompanion,
                  onSelectCompanionTab: (pane) =>
                      setState(() => _companionPane = pane),
                )
              : GitChangesPane(
                  key: ValueKey('git_$sessionId'),
                  sessionId: sessionId,
                  onCollapse: () => _collapsePane(WorkspacePane.git),
                  companionTabs: companionTabs,
                  activeCompanionTab: selectedCompanion,
                  onSelectCompanionTab: (pane) =>
                      setState(() => _companionPane = pane),
                )),
    };

    if (width < 900) {
      final selected = visible.contains(_compactPane)
          ? _compactPane
          : visible.first;
      return Column(
        children: [
          _paneSelector(
            visible,
            selected,
            (pane) => setState(() => _compactPane = pane),
            showLayoutMenu: true,
          ),
          Expanded(
            child: IndexedStack(
              index: visible.indexOf(selected),
              children: [for (final pane in visible) _bentoPane(panes[pane]!)],
            ),
          ),
        ],
      );
    }

    if (width < 1440 && _paneVisibility[WorkspacePane.chat] == true) {
      if (companions.isNotEmpty && selectedCompanion != null) {
        return _resizablePaneRow(
          [WorkspacePane.chat, selectedCompanion],
          panes,
        );
      }
    }

    return _resizablePaneRow(visible, panes);
  }

  List<WorkspacePane> _visiblePanes({bool chatFirst = false}) {
    final order = chatFirst
        ? WorkspacePane.values
        : const [
            WorkspacePane.repository,
            WorkspacePane.chat,
            WorkspacePane.git,
          ];
    return order.where((pane) => _paneVisibility[pane] == true).toList();
  }

  String _paneLabel(WorkspacePane pane) => switch (pane) {
    WorkspacePane.chat => 'Chat',
    WorkspacePane.repository => 'Repository',
    WorkspacePane.git => ref.watch(isReviewingChangesProvider)
        ? 'Review Changes'
        : (ref.watch(browserPaneSupportedProvider) &&
                  ref.watch(rightPaneModeProvider) == RightPaneMode.browser
            ? 'Web Browser'
            : 'Git Changes'),
  };

  void _togglePane(WorkspacePane pane) {
    final visible = _visiblePanes();
    if (_paneVisibility[pane] == true && visible.length <= 1) return;
    setState(() {
      final nowVisible = !(_paneVisibility[pane] ?? false);
      _paneVisibility[pane] = nowVisible;
      if (nowVisible) {
        _collapsedPanes.remove(pane);
      }
      final remaining = _visiblePanes();
      if (!remaining.contains(_compactPane)) _compactPane = remaining.first;
      if (!remaining.contains(_companionPane)) {
        _companionPane = remaining.firstWhere(
          (item) => item != WorkspacePane.chat,
          orElse: () => remaining.first,
        );
      }
    });
    _persistLayout();
  }

  Widget _bentoPane(Widget child) {
    final tokens = context.tokens;
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 600;
    return RepaintBoundary(
      child: Padding(
        padding: isMobile
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
            : const EdgeInsets.all(3),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: tokens.surface,
            border: Border.all(color: tokens.border),
            borderRadius: BorderRadius.circular(
              isMobile ? tokens.radiusMd : tokens.radiusLg,
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  void _collapsePane(WorkspacePane pane) {
    final visible = _visiblePanes();
    final openPanes = visible
        .where((p) => !_collapsedPanes.contains(p))
        .toList();
    if (openPanes.length <= 1) return; // Always keep at least one pane open

    setState(() {
      _savedPaneWeights[pane] = _paneWeights[pane] ?? 30;
      _collapsedPanes.add(pane);

      final remaining = openPanes.where((p) => p != pane).toList();
      if (remaining.isNotEmpty) {
        final freed = _paneWeights[pane] ?? 30;
        final extra = freed / remaining.length;
        for (final rem in remaining) {
          _paneWeights[rem] = (_paneWeights[rem] ?? 30) + extra;
        }
      }
    });
  }

  void _expandPane(WorkspacePane pane) {
    if (!_collapsedPanes.contains(pane)) return;
    setState(() {
      _collapsedPanes.remove(pane);
      final visible = _visiblePanes();
      final openOthers = visible
          .where((p) => p != pane && !_collapsedPanes.contains(p))
          .toList();

      final restoreWeight = (_savedPaneWeights[pane] ?? 30).clamp(15.0, 50.0);
      _paneWeights[pane] = restoreWeight;

      if (openOthers.isNotEmpty) {
        final totalOther = openOthers.fold<double>(
          0.0,
          (sum, p) => sum + (_paneWeights[p] ?? 30),
        );
        final targetOther = (100.0 - restoreWeight).clamp(20.0, 85.0);
        final factor = totalOther > 0 ? targetOther / totalOther : 1.0;
        for (final other in openOthers) {
          _paneWeights[other] = ((_paneWeights[other] ?? 30) * factor).clamp(
            10.0,
            85.0,
          );
        }
      }
    });
  }

  Widget _collapsedPaneStrip(WorkspacePane pane) {
    final tokens = context.tokens;
    final isLeft = pane == WorkspacePane.repository;
    final isBrowser = pane == WorkspacePane.git &&
        !ref.watch(isReviewingChangesProvider) &&
        ref.watch(browserPaneSupportedProvider) &&
        ref.watch(rightPaneModeProvider) == RightPaneMode.browser;
    final iconData = switch (pane) {
      WorkspacePane.repository => Icons.folder_outlined,
      WorkspacePane.git =>
        isBrowser ? Icons.language_outlined : Icons.source_outlined,
      WorkspacePane.chat => Icons.chat_bubble_outline,
    };
    final expandIcon = isLeft ? Icons.chevron_right : Icons.chevron_left;
    final label = _paneLabel(pane).toUpperCase();

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Container(
          width: 34,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: tokens.surface,
            border: Border.all(color: tokens.border),
            borderRadius: BorderRadius.circular(tokens.radiusLg),
          ),
          child: Column(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                tooltip: _tr('Espandi pannello ${_paneLabel(pane)}', 'Expand ${_paneLabel(pane)} panel'),
                icon: Icon(expandIcon, size: 18, color: tokens.accent),
                onPressed: () => _expandPane(pane),
              ),
              const SizedBox(height: 6),
              Icon(iconData, size: 15, color: tokens.textMuted),
              const SizedBox(height: 12),
              Expanded(
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _collapsedSidebarStrip(FrameTokens tokens) {
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Container(
          width: 36,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: tokens.surface,
            border: Border.all(color: tokens.border),
            borderRadius: BorderRadius.circular(tokens.radiusLg),
          ),
          child: Column(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(),
                tooltip: _tr('Espandi barra sessioni', 'Expand sessions sidebar'),
                icon: Icon(Icons.chevron_right, size: 18, color: tokens.accent),
                onPressed: () {
                  setState(() => _sidebarCollapsed = false);
                  _persistLayout();
                },
              ),
              const SizedBox(height: 8),
              const PiFrameMark(size: 20),
              const SizedBox(height: 12),
              Icon(
                Icons.chat_bubble_outline,
                size: 15,
                color: tokens.textMuted,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Center(
                    child: Text(
                      _tr('SESSIONI', 'SESSIONS'),
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resizablePaneRow(
    List<WorkspacePane> panes,
    Map<WorkspacePane, Widget> contents,
  ) {
    if (panes.isEmpty) return const SizedBox.shrink();
    if (panes.length == 1 && _collapsedPanes.isEmpty) {
      return _bentoPane(contents[panes.single]!);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        const dividerWidth = 8.0;
        final collapsedCount = panes
            .where((p) => _collapsedPanes.contains(p))
            .length;
        const collapsedWidth = 40.0;
        final availableWidth =
            constraints.maxWidth -
            dividerWidth * (panes.length - 1) -
            (collapsedWidth * collapsedCount);

        return Row(
          children: [
            for (var index = 0; index < panes.length; index++) ...[
              if (_collapsedPanes.contains(panes[index]))
                _collapsedPaneStrip(panes[index])
              else
                Expanded(
                  flex: (_paneWeights[panes[index]] ?? 1)
                      .round()
                      .clamp(1, 100)
                      .toInt(),
                  child: _bentoPane(contents[panes[index]]!),
                ),
              if (index < panes.length - 1)
                MouseRegion(
                  key: ValueKey(
                    'pane-divider-${panes[index]}-${panes[index + 1]}',
                  ),
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (_) =>
                        ref.read(paneDraggingProvider.notifier).state = true,
                    onHorizontalDragEnd: (_) =>
                        ref.read(paneDraggingProvider.notifier).state = false,
                    onHorizontalDragCancel: () =>
                        ref.read(paneDraggingProvider.notifier).state = false,
                    onHorizontalDragUpdate: (details) => _resizeAdjacent(
                      panes[index],
                      panes[index + 1],
                      details.delta.dx,
                      availableWidth,
                    ),
                    child: SizedBox(
                      width: dividerWidth,
                      child: Center(
                        child: Container(
                          width: 1,
                          height: 40,
                          color: context.tokens.borderStrong,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  void _resizeAdjacent(
    WorkspacePane left,
    WorkspacePane right,
    double delta,
    double availableWidth,
  ) {
    if (_collapsedPanes.contains(left)) {
      if (delta > 6) {
        _expandPane(left);
      }
      return;
    }
    if (_collapsedPanes.contains(right)) {
      if (delta < -6) {
        _expandPane(right);
      }
      return;
    }

    final leftWeight = _paneWeights[left] ?? 1;
    final rightWeight = _paneWeights[right] ?? 1;
    final total = leftWeight + rightWeight;
    if (availableWidth <= 0 || total <= 0) return;

    final minimum = total * 0.15;
    final candidateLeft = leftWeight + delta / availableWidth * total;

    final openCount = _visiblePanes()
        .where((p) => !_collapsedPanes.contains(p))
        .length;
    if (openCount > 1) {
      if (candidateLeft < minimum) {
        _collapsePane(left);
        return;
      }
      if (total - candidateLeft < minimum) {
        _collapsePane(right);
        return;
      }
    }

    final nextLeft = candidateLeft.clamp(minimum, total - minimum).toDouble();
    setState(() {
      _paneWeights[left] = nextLeft;
      _paneWeights[right] = total - nextLeft;
    });
  }

  Widget _paneSelector(
    List<WorkspacePane> panes,
    WorkspacePane selected,
    ValueChanged<WorkspacePane> onSelected, {
    bool showLayoutMenu = false,
  }) {
    final tokens = context.tokens;
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 600;
    final isBrowser = ref.watch(browserPaneSupportedProvider) &&
        ref.watch(rightPaneModeProvider) == RightPaneMode.browser;
    String label(WorkspacePane pane) => switch (pane) {
      WorkspacePane.chat => 'Chat',
      WorkspacePane.repository => 'File',
      WorkspacePane.git => isBrowser ? 'Web Browser' : 'Git Changes',
    };
    return Container(
      height: 44,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 6, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.chassis,
        border: Border(bottom: BorderSide(color: tokens.borderStrong)),
      ),
      child: Row(
        children: [
          for (final pane in panes)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Semantics(
                  button: true,
                  selected: pane == selected,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      foregroundColor: pane == selected
                          ? tokens.displayText
                          : tokens.textPrimary,
                      backgroundColor: pane == selected
                          ? tokens.displaySurface
                          : tokens.chassis,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                        side: BorderSide(
                          color: pane == selected
                              ? tokens.borderStrong
                              : tokens.border,
                        ),
                      ),
                    ),
                    onPressed: () => onSelected(pane),
                    child: Text(
                      label(pane),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
          if (showLayoutMenu)
            PopupMenuButton<WorkspacePane>(
              tooltip: _tr('Mostra o nascondi pannelli', 'Show or hide panels'),
              onSelected: _togglePane,
              itemBuilder: (context) => [
                for (final pane in WorkspacePane.values)
                  PopupMenuItem(
                    value: pane,
                    child: Row(
                      children: [
                        Icon(
                          _paneVisibility[pane] == true
                              ? Icons.check_box_outlined
                              : Icons.check_box_outline_blank,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(_paneLabel(pane)),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  bool _isSubsession(Map<String, dynamic> session) {
    if (session['isSubsession'] == true) return true;
    final parentSession = (session['parentSession'] ?? '').toString().trim();
    if (parentSession.isNotEmpty) return true;
    final name = (session['name'] ?? '').toString().toLowerCase();
    final id = (session['id'] ?? '').toString().toLowerCase();
    return name.contains('worker#') ||
        id.contains('worker#') ||
        name.contains('#') ||
        id.contains('#') ||
        name.startsWith('subagent') ||
        id.startsWith('subagent');
  }

  String _sessionFolder(Map<String, dynamic> session) {
    final gitRoot = (session['gitRoot'] ?? '').toString().trim();
    return gitRoot.isNotEmpty ? gitRoot : (session['cwd'] ?? '').toString();
  }

  int _sessionTimestamp(Map<String, dynamic> s) {
    final raw = s['updatedAt'] ?? s['mtime'] ?? s['createdAt'] ?? s['ts'];
    if (raw is num) return raw.toInt();
    if (raw is String) {
      final parsedNum = int.tryParse(raw);
      if (parsedNum != null) return parsedNum;
      final parsedDate = DateTime.tryParse(raw);
      if (parsedDate != null) return parsedDate.millisecondsSinceEpoch;
    }
    return 0;
  }

  Widget _buildRecentSessionsSection(
    FrameTokens tokens,
    List<Map<String, dynamic>> sessions,
    bool compact,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.history, size: 16, color: tokens.accent),
            const SizedBox(width: 8),
            Text(
              _tr('Sessioni recenti', 'Recent sessions'),
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: tokens.surfaceElevated,
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                border: Border.all(color: tokens.border),
              ),
              child: Text(
                'Quick Launch',
                style: TextStyle(
                  color: tokens.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            children: [
              for (final session in sessions)
                _buildQuickLaunchSessionCard(tokens, session),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickLaunchSessionCard(
    FrameTokens tokens,
    Map<String, dynamic> session,
  ) {
    final id = (session['id'] ?? '').toString();
    final name = (session['name'] ?? id).toString();
    final folder = _sessionFolder(session);
    final folderDisplay = folder.isNotEmpty ? folder : _tr('Nessuna cartella', 'No folder');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey('quick-launch-session-$id'),
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          onTap: () async {
            if (await switchSessionSafely(context, ref, id)) {
              ref.read(activeSessionIdProvider.notifier).state = id;
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: BorderRadius.circular(tokens.radiusMd),
              border: Border.all(color: tokens.border),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: tokens.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                  ),
                  child: Icon(
                    Icons.chat_bubble_outline,
                    size: 16,
                    color: tokens.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        folderDisplay,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: 11,
                          fontFamily: tokens.monoFontFamily,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  Icons.arrow_forward,
                  size: 14,
                  color: tokens.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _welcome(FrameTokens tokens, bool narrow, bool connected) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 640;
          final wide = constraints.maxWidth >= 960;

          final sessionsList = (ref.watch(sessionListProvider).value ?? const [])
              .where((s) => !_isSubsession(s))
              .toList();

          sessionsList.sort((a, b) {
            final tsB = _sessionTimestamp(b);
            final tsA = _sessionTimestamp(a);
            if (tsB != 0 || tsA != 0) return tsB.compareTo(tsA);
            return 0;
          });

          final recentSessions = sessionsList.take(5).toList();

          final startContent = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PiFrameMark(size: compact ? 48 : 64),
              const SizedBox(height: 32),
              Text(
                _tr('Nuova\nsessione.', 'New\nsession.'),
                style: TextStyle(
                  fontFamily: tokens.headingFontFamily,
                  fontSize: compact ? 56 : 84,
                  height: 0.95,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.0,
                  color: tokens.textPrimary,
                ),
              ),
              const SizedBox(height: 24),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Text(
                  _tr('Scegli una conversazione o inizia a lavorare con Pi. Il lavoro continua anche quando chiudi la finestra.', 'Choose a conversation or start working with Pi. Work continues even when you close the window.'),
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 14.5,
                    height: 1.55,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  PressFeedback(
                    child: FilledButton.icon(
                      onPressed: connected && !_creating ? _create : null,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(
                        _creating ? _tr('Creazione...', 'Creating...') : _tr('Nuova sessione', 'New session'),
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: narrow
                        ? () => _scaffoldKey.currentState?.openDrawer()
                        : _palette,
                    icon: const Icon(Icons.search, size: 18),
                    label: Text(
                      narrow ? _tr('Esplora sessioni', 'Browse sessions') : _tr('Cerca nei comandi', 'Search commands'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Text(
                _tr('Ctrl / Cmd + K · Comandi', 'Ctrl / Cmd + K · Commands'),
                style: TextStyle(color: tokens.textMuted, fontSize: 12),
              ),
            ],
          );

          final recentContent = recentSessions.isEmpty
              ? const SizedBox.shrink()
              : _buildRecentSessionsSection(tokens, recentSessions, compact);

          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: EdgeInsets.all(compact ? 24 : 48),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(flex: 5, child: startContent),
                          const SizedBox(width: 48),
                          Expanded(flex: 6, child: recentContent),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          startContent,
                          if (recentSessions.isNotEmpty) ...[
                            const SizedBox(height: 40),
                            recentContent,
                          ],
                        ],
                      ),
              ),
            ),
          );
        },
      );
}
