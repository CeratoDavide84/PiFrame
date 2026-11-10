import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'theme_spec.dart';
import 'vscode_theme_converter.dart';

class ThemeRepository {
  final Map<String, ThemeSpec> _rawThemes = {};
  final Map<String, ThemeSpec> _resolvedThemes = {};
  String _activeThemeId = 'piframe-dark';
  final _controller = StreamController<List<ThemeSpec>>.broadcast();
  StreamSubscription<FileSystemEvent>? _watcherSubscription;

  ThemeRepository() {
    _registerBuiltIns();
  }

  void _registerBuiltIns() {
    final darkBuiltIn = ThemeSpec(
      id: 'piframe-dark',
      name: 'PiFrame Dark',
      author: 'PiFrame',
      version: '1.0.0',
      variant: 'dark',
    );
    final codexDarkBuiltIn = ThemeSpec(
      id: 'codex-dark',
      name: 'Codex Dark',
      author: 'PiFrame',
      version: '1.0.0',
      variant: 'dark',
      extendsTheme: 'piframe-dark',
      rawColors: {
        'background': '#171717',
        'chassis': '#1b1b1b',
        'displaySurface': '#212121',
        'displayText': '#f2f2f2',
        'surface': '#1d1d1d',
        'surfaceElevated': '#252525',
        'overlay': '#000000aa',
        'border': '#343434',
        'borderStrong': '#484848',
        'textPrimary': '#f0f0f0',
        'textSecondary': '#b7b7b7',
        'textMuted': '#888888',
        'accent': '#6aa5ff',
        'accentContrast': '#101010',
        'focusRing': '#6aa5ff',
        'success': '#75c995',
        'warning': '#e7b864',
        'danger': '#f07b72',
        'info': '#7eb6ff',
        'agentWorking': '#7eb6ff',
        'agentRetrying': '#e7b864',
        'agentCompacting': '#6aa5ff',
        'agentSettled': '#75c995',
        'agentAwaitingUser': '#e7b864',
        'agentError': '#f07b72',
        'userBubble': '#303030',
        'thinking': '#9b9b9b',
        'diffAddedBg': '#75c99526',
        'diffAddedFg': '#75c995',
        'diffRemovedBg': '#f07b7226',
        'diffRemovedFg': '#f07b72',
        'diffContextFg': '#a0a0a0',
      },
      rawSyntax: {
        'keyword': '#8ab4f8',
        'string': '#a8d5a2',
        'number': '#e6c07b',
        'comment': '#858585',
        'function': '#d2a8ff',
        'type': '#78c4c4',
        'variable': '#e6e6e6',
        'operator': '#b7b7b7',
        'punctuation': '#999999',
        'invalid': '#f07b72',
      },
      rawTypography: {
        'uiFontFamily': 'Segoe UI',
        'headingFontFamily': 'Segoe UI',
      },
      rawRadii: {'sm': 6.0, 'md': 9.0, 'lg': 12.0, 'pill': 999.0},
    );
    final mochaBuiltIn = ThemeSpec(
      id: 'catppuccin-mocha',
      name: 'Catppuccin Mocha',
      author: 'Catppuccin Org',
      version: '1.0.0',
      variant: 'dark',
      rawColors: {
        'background': '#1e1e2e',
        'surface': '#181825',
        'surfaceElevated': '#313244',
        'border': '#45475a',
        'borderStrong': '#585b70',
        'textPrimary': '#cdd6f4',
        'textSecondary': '#bac2de',
        'textMuted': '#a6adc8',
        'accent': '#cba6f7',
        'accentContrast': '#11111b',
        'focusRing': '#cba6f7',
        'success': '#a6e3a1',
        'warning': '#f9e2af',
        'danger': '#f38ba8',
        'info': '#89b4fa',
        'userBubble': '#313244',
        'thinking': '#b4befe',
      },
    );
    final nordDarkBuiltIn = ThemeSpec(
      id: 'nord-dark',
      name: 'Nord Dark',
      author: 'Arctic Ice Studio',
      version: '1.0.0',
      variant: 'dark',
      rawColors: {
        'background': '#2e3440',
        'surface': '#3b4252',
        'surfaceElevated': '#434c5e',
        'border': '#4c566a',
        'borderStrong': '#5e81ac',
        'textPrimary': '#eceff4',
        'textSecondary': '#e5e9f0',
        'textMuted': '#d8dee9',
        'accent': '#88c0d0',
        'accentContrast': '#2e3440',
        'focusRing': '#88c0d0',
        'success': '#a3be8c',
        'warning': '#ebcb8b',
        'danger': '#bf616a',
        'info': '#81a1c1',
        'userBubble': '#434c5e',
        'thinking': '#b48ead',
      },
    );
    final lightBuiltIn = ThemeSpec(
      id: 'piframe-light',
      name: 'PiFrame Light',
      author: 'PiFrame',
      version: '1.0.0',
      variant: 'light',
    );
    final latteBuiltIn = ThemeSpec(
      id: 'catppuccin-latte',
      name: 'Catppuccin Latte',
      author: 'Catppuccin Org',
      version: '1.0.0',
      variant: 'light',
      rawColors: {
        'background': '#eff1f5',
        'surface': '#e6e9ef',
        'surfaceElevated': '#dce0e8',
        'border': '#ccd0da',
        'borderStrong': '#bcc0cc',
        'textPrimary': '#4c4f69',
        'textSecondary': '#5c5f77',
        'textMuted': '#6c6f85',
        'accent': '#8839ef',
        'accentContrast': '#eff1f5',
        'focusRing': '#8839ef',
        'success': '#40a02b',
        'warning': '#df8e1d',
        'danger': '#d20f39',
        'info': '#1e66f5',
        'userBubble': '#dce0e8',
        'thinking': '#7287fd',
      },
    );
    final solarLightBuiltIn = ThemeSpec(
      id: 'solar-light',
      name: 'Solar Light',
      author: 'Ethan Schoonover',
      version: '1.0.0',
      variant: 'light',
      rawColors: {
        'background': '#fdf6e3',
        'surface': '#eee8d5',
        'surfaceElevated': '#e0dac6',
        'border': '#93a1a1',
        'borderStrong': '#657b83',
        'textPrimary': '#073642',
        'textSecondary': '#586e75',
        'textMuted': '#657b83',
        'accent': '#268bd2',
        'accentContrast': '#fdf6e3',
        'focusRing': '#268bd2',
        'success': '#859900',
        'warning': '#b58900',
        'danger': '#dc322f',
        'info': '#2aa198',
        'userBubble': '#eee8d5',
        'thinking': '#6c71c4',
      },
    );

    _rawThemes['piframe-dark'] = darkBuiltIn;
    _rawThemes['codex-dark'] = codexDarkBuiltIn;
    _rawThemes['catppuccin-mocha'] = mochaBuiltIn;
    _rawThemes['nord-dark'] = nordDarkBuiltIn;
    _rawThemes['piframe-light'] = lightBuiltIn;
    _rawThemes['catppuccin-latte'] = latteBuiltIn;
    _rawThemes['solar-light'] = solarLightBuiltIn;
    _resolveAll();
  }

  String get activeThemeId => _activeThemeId;
  ThemeSpec get activeTheme =>
      _resolvedThemes[_activeThemeId] ?? _resolvedThemes['piframe-dark']!;

  List<ThemeSpec> get availableThemes => _resolvedThemes.values.toList();
  Stream<List<ThemeSpec>> watch() => _controller.stream;

  bool hasTheme(String id) =>
      _resolvedThemes.containsKey(id) || _rawThemes.containsKey(id);

  void setActiveTheme(String id) {
    if (_resolvedThemes.containsKey(id) && _activeThemeId != id) {
      _activeThemeId = id;
      if (!_controller.isClosed) {
        _controller.add(availableThemes);
      }
    }
  }

  ThemeSpec? registerThemeJson(String jsonString) {
    try {
      final spec = VsCodeThemeConverter.parseAnyThemeJson(jsonString);
      _rawThemes[spec.id] = spec;
      _resolveAll();
      return _resolvedThemes[spec.id] ?? spec;
    } catch (e) {
      debugPrint('Error parsing theme JSON: $e');
      return null;
    }
  }

  void registerTheme(ThemeSpec spec) {
    _rawThemes[spec.id] = spec;
    _resolveAll();
  }

  void _resolveAll() {
    _resolvedThemes.clear();
    for (final id in _rawThemes.keys) {
      _resolvedThemes[id] = _resolveTheme(id, <String>{}, 0);
    }
    if (!_controller.isClosed) {
      _controller.add(availableThemes);
    }
  }

  ThemeSpec _resolveTheme(String id, Set<String> visited, int depth) {
    final raw = _rawThemes[id];
    if (raw == null) {
      return _rawThemes['piframe-dark']!;
    }

    if (raw.extendsTheme == null || raw.extendsTheme!.isEmpty) {
      return raw;
    }

    final parentId = raw.extendsTheme!;
    if (visited.contains(parentId) || depth >= 3) {
      // Cycle or depth limit exceeded
      raw.diagnostics.add(
          'Inheritance cycle or max depth exceeded for theme "$id" extending "$parentId". Aborting inheritance.');
      return raw;
    }

    visited.add(id);
    final parentResolved = _resolveTheme(parentId, visited, depth + 1);
    return ThemeSpec.merge(parentResolved, raw);
  }

  void watchDirectory(Directory dir) {
    if (!dir.existsSync()) return;
    try {
      _watcherSubscription?.cancel();
      _watcherSubscription = dir.watch().listen((event) {
        if (event.path.endsWith('.json')) {
          _reloadFromDirectory(dir);
        }
      });
    } catch (e) {
      debugPrint('ThemeDirectory watcher error: $e');
    }
  }

  void _reloadFromDirectory(Directory dir) {
    try {
      final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json'));
      for (final file in files) {
        final content = file.readAsStringSync();
        registerThemeJson(content);
      }
    } catch (e) {
      debugPrint('Failed to reload themes from directory: $e');
    }
  }

  void dispose() {
    _watcherSubscription?.cancel();
    _controller.close();
  }
}
