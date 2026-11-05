import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';

import '../../data/language/language_settings.dart';
import '../../data/theme/theme_providers.dart';
import '../../ui/frame_snack_bar.dart';

class ThemeEditorDialog extends ConsumerStatefulWidget {
  final ThemeSpec? initialTheme;

  const ThemeEditorDialog({super.key, this.initialTheme});

  static Future<void> show(BuildContext context, {ThemeSpec? initialTheme}) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ThemeEditorDialog(initialTheme: initialTheme),
    );
  }

  @override
  ConsumerState<ThemeEditorDialog> createState() => _ThemeEditorDialogState();
}

class _ThemeEditorDialogState extends ConsumerState<ThemeEditorDialog> {
  late TextEditingController _nameController;
  late String _selectedBaseThemeId;
  late String _variant;
  late Map<String, dynamic> _customColors;
  late Map<String, dynamic> _customSyntax;
  String? _errorMessage;
  bool _isSaving = false;

  String _tr(String it, String en) =>
      ref.read(appLanguageProvider) == AppLanguage.it ? it : en;

  @override
  void initState() {
    super.initState();
    final active =
        widget.initialTheme ??
        ref.read(activeThemeSpecProvider) ??
        ref.read(themeRepositoryProvider).activeTheme;
    _selectedBaseThemeId = active.id;
    _nameController = TextEditingController(text: '${active.name} (Custom)');
    _variant = active.variant;
    _customColors = Map<String, dynamic>.from(active.rawColors);
    _customSyntax = Map<String, dynamic>.from(active.rawSyntax);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _onBaseThemeChanged(ThemeSpec baseTheme) {
    setState(() {
      _selectedBaseThemeId = baseTheme.id;
      _variant = baseTheme.variant;
      _nameController.text = '${baseTheme.name} (Custom)';
      _customColors = Map<String, dynamic>.from(baseTheme.rawColors);
      _customSyntax = Map<String, dynamic>.from(baseTheme.rawSyntax);
    });
  }

  Color _resolveColor(String key, {bool isSyntax = false, Color? fallback}) {
    final hex = isSyntax ? _customSyntax[key] : _customColors[key];
    if (hex != null) {
      final parsed = parseHexColor(hex);
      if (parsed != null) return parsed;
    }
    return fallback ?? context.tokens.textMuted;
  }

  void _setColor(String key, Color color, {bool isSyntax = false}) {
    final hex =
        '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
    setState(() {
      if (isSyntax) {
        _customSyntax[key] = hex;
      } else {
        _customColors[key] = hex;
      }
    });
  }

  Future<void> _openColorPicker(
    String key,
    String title,
    Color currentColor, {
    bool isSyntax = false,
  }) async {
    final tokens = context.tokens;
    final hexController = TextEditingController(
      text:
          '#${currentColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
    );

    // Curated palette of modern vibrant and neutral colors
    final palette = [
      '#0F141C',
      '#161B22',
      '#1E232A',
      '#262C36',
      '#323945',
      '#4A5568',
      '#8B949E',
      '#C9D1D9',
      '#F0F6FC',
      '#58A6FF',
      '#388BFD',
      '#1F6FEB',
      '#3FB950',
      '#2EA043',
      '#238636',
      '#D29922',
      '#E3B341',
      '#F0883E',
      '#F85149',
      '#DA3633',
      '#A371F7',
      '#BC8CFF',
      '#DB61A2',
      '#56D364',
    ].map((h) => parseHexColor(h)!).toList();

    Color selectedColor = currentColor;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: tokens.surfaceElevated,
            title: Text(
              title,
              style: TextStyle(color: tokens.textPrimary, fontSize: 16),
            ),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: selectedColor,
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                          border: Border.all(
                            color: tokens.borderStrong,
                            width: 2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: hexController,
                          style: TextStyle(
                            fontFamily: tokens.monoFontFamily,
                            color: tokens.textPrimary,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            labelText: 'HEX (#RRGGBB)',
                            labelStyle: TextStyle(
                              color: tokens.textSecondary,
                              fontSize: 12,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                          onChanged: (val) {
                            final p = parseHexColor(val.trim());
                            if (p != null) {
                              setDialogState(() => selectedColor = p);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _tr('Colori Suggeriti', 'Suggested colors'),
                    style: TextStyle(
                      color: tokens.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: palette.map((color) {
                      final isSelected =
                          color.toARGB32() == selectedColor.toARGB32();
                      return InkWell(
                        onTap: () {
                          setDialogState(() {
                            selectedColor = color;
                            hexController.text =
                                '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
                          });
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isSelected ? tokens.accent : tokens.border,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: Text(
                  _tr('Annulla', 'Cancel'),
                  style: TextStyle(color: tokens.textMuted),
                ),
              ),
              FilledButton(
                onPressed: () {
                  _setColor(key, selectedColor, isSyntax: isSyntax);
                  Navigator.pop(dialogCtx);
                },
                child: Text(_tr('Applica', 'Apply')),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _saveAndApplyTheme() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(
        () => _errorMessage = _tr(
          'Il nome del tema non può essere vuoto',
          'Theme name cannot be empty',
        ),
      );
      return;
    }

    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');

    final id = 'custom-$slug';

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final spec = ThemeSpec(
        schemaVersion: 1,
        id: id,
        name: name,
        author: 'User',
        version: '1.0.0',
        variant: _variant,
        extendsTheme: _selectedBaseThemeId,
        rawColors: _customColors,
        rawSyntax: _customSyntax,
      );

      await ref.read(activeThemeSpecProvider.notifier).saveCustomTheme(spec);

      if (mounted) {
        Navigator.of(context).pop();
        FrameSnackBar.show(
          context,
          message: _tr(
            'Tema "$name" salvato e attivato con successo!',
            'Theme "$name" saved and applied successfully!',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = _tr(
            'Errore durante il salvataggio: $e',
            'Save failed: $e',
          );
          _isSaving = false;
        });
      }
    }
  }

  Widget _buildColorRow(
    String key,
    String label, {
    bool isSyntax = false,
    required FrameTokens tokens,
    Color? fallback,
  }) {
    final color = _resolveColor(
      key,
      isSyntax: isSyntax,
      fallback: fallback ?? tokens.textMuted,
    );
    final hexString =
        '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

    return InkWell(
      key: ValueKey('theme-editor-color-$key'),
      onTap: () => _openColorPicker(key, label, color, isSyntax: isSyntax),
      borderRadius: BorderRadius.circular(tokens.radiusSm),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          border: Border.all(color: tokens.border.withValues(alpha: 0.7)),
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: tokens.borderStrong),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Text(
              hexString,
              style: TextStyle(
                color: tokens.textMuted,
                fontFamily: tokens.monoFontFamily,
                fontSize: 11,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.colorize, size: 14, color: tokens.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _buildLivePreview(FrameTokens currentTokens) {
    // Generate simulated tokens from the user's customized colors
    final bg = _resolveColor('background', fallback: currentTokens.background);
    final surf = _resolveColor('surface', fallback: currentTokens.surface);
    final surfElev = _resolveColor(
      'surfaceElevated',
      fallback: currentTokens.surfaceElevated,
    );
    final brd = _resolveColor('border', fallback: currentTokens.border);
    final acc = _resolveColor('accent', fallback: currentTokens.accent);
    final accTxt = _resolveColor(
      'accentContrast',
      fallback: currentTokens.accentContrast,
    );
    final txtPrim = _resolveColor(
      'textPrimary',
      fallback: currentTokens.textPrimary,
    );
    final txtMut = _resolveColor(
      'textMuted',
      fallback: currentTokens.textMuted,
    );
    final succ = _resolveColor('success', fallback: currentTokens.success);
    final wrk = _resolveColor(
      'agentWorking',
      fallback: currentTokens.agentWorking,
    );

    final synKw = _resolveColor(
      'keyword',
      isSyntax: true,
      fallback: currentTokens.syntaxKeyword,
    );
    final synStr = _resolveColor(
      'string',
      isSyntax: true,
      fallback: currentTokens.syntaxString,
    );
    final synFn = _resolveColor(
      'function',
      isSyntax: true,
      fallback: currentTokens.syntaxFunction,
    );
    final synCm = _resolveColor(
      'comment',
      isSyntax: true,
      fallback: currentTokens.syntaxComment,
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(currentTokens.radiusMd),
        border: Border.all(color: brd, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.palette_outlined, size: 16, color: acc),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _tr('Anteprima Componenti', 'Component preview'),
                  style: TextStyle(
                    color: txtPrim,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    fontFamily: currentTokens.headingFontFamily,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: wrk.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: wrk),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: wrk,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _tr('In corso', 'Working'),
                      style: TextStyle(
                        color: wrk,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: surf,
              borderRadius: BorderRadius.circular(currentTokens.radiusSm),
              border: Border.all(color: brd),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tr('Scheda Bento & Superfici', 'Bento card & surfaces'),
                  style: TextStyle(
                    color: txtPrim,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _tr(
                    'Testo secondario / descrittivo del tema in modifica.',
                    'Secondary text describing the theme being edited.',
                  ),
                  style: TextStyle(color: txtMut, fontSize: 11),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: acc,
                        borderRadius: BorderRadius.circular(
                          currentTokens.radiusSm,
                        ),
                      ),
                      child: Text(
                        _tr('Pulsante Accento', 'Accent button'),
                        style: TextStyle(
                          color: accTxt,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: surfElev,
                        borderRadius: BorderRadius.circular(
                          currentTokens.radiusSm,
                        ),
                        border: Border.all(color: brd),
                      ),
                      child: Text(
                        _tr('Pulsante Secondario', 'Secondary button'),
                        style: TextStyle(color: txtPrim, fontSize: 11),
                      ),
                    ),
                    Icon(Icons.check_circle, size: 16, color: succ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: surfElev,
              borderRadius: BorderRadius.circular(currentTokens.radiusSm),
              border: Border.all(color: brd),
            ),
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontFamily: currentTokens.monoFontFamily,
                  fontSize: 11,
                ),
                children: [
                  TextSpan(
                    text: '// Codice di esempio\n',
                    style: TextStyle(color: synCm),
                  ),
                  TextSpan(
                    text: 'const ',
                    style: TextStyle(color: synKw, fontWeight: FontWeight.bold),
                  ),
                  TextSpan(
                    text: 'answer',
                    style: TextStyle(color: synFn),
                  ),
                  TextSpan(
                    text: ' = ',
                    style: TextStyle(color: txtPrim),
                  ),
                  TextSpan(
                    text: '"42"',
                    style: TextStyle(color: synStr),
                  ),
                  TextSpan(
                    text: ';',
                    style: TextStyle(color: txtPrim),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appLanguageProvider);
    final tokens = context.tokens;
    final strings = ref.watch(appStringsProvider);
    final repo = ref.watch(themeRepositoryProvider);
    final availableThemes = repo.availableThemes;

    return Dialog(
      backgroundColor: tokens.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        side: BorderSide(color: tokens.borderStrong),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(Icons.tune_rounded, color: tokens.accent, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.themeEditorTitle,
                          style: TextStyle(
                            color: tokens.displayText,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontFamily: tokens.headingFontFamily,
                          ),
                        ),
                        Text(
                          strings.themeEditorSubtitle,
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: tokens.textMuted),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(height: 24),

              // Controls: Base Theme selection & Theme Name
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.baseThemeLabel,
                          style: TextStyle(
                            color: tokens.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: tokens.surface,
                            borderRadius: BorderRadius.circular(
                              tokens.radiusSm,
                            ),
                            border: Border.all(color: tokens.border),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              key: const ValueKey('theme-editor-base-dropdown'),
                              isExpanded: true,
                              value: _selectedBaseThemeId,
                              dropdownColor: tokens.surfaceElevated,
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: 13,
                              ),
                              items: availableThemes.map((t) {
                                return DropdownMenuItem<String>(
                                  value: t.id,
                                  child: Text('${t.name} (${t.variant})'),
                                );
                              }).toList(),
                              onChanged: (id) {
                                if (id != null) {
                                  final selected = availableThemes.firstWhere(
                                    (t) => t.id == id,
                                  );
                                  _onBaseThemeChanged(selected);
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.themeNameLabel,
                          style: TextStyle(
                            color: tokens.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        TextField(
                          key: const ValueKey('theme-editor-name-input'),
                          controller: _nameController,
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            hintText: strings.themeNameHint,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.themeVariantLabel,
                          style: TextStyle(
                            color: tokens.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: tokens.surface,
                            borderRadius: BorderRadius.circular(
                              tokens.radiusSm,
                            ),
                            border: Border.all(color: tokens.border),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              key: const ValueKey(
                                'theme-editor-variant-dropdown',
                              ),
                              isExpanded: true,
                              value: _variant,
                              dropdownColor: tokens.surfaceElevated,
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: 13,
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: 'dark',
                                  child: Text(strings.variantDark),
                                ),
                                DropdownMenuItem(
                                  value: 'light',
                                  child: Text(strings.variantLight),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) setState(() => _variant = v);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Main customization body: split into editor lists on left, live preview on right
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Color Pickers List
                    Expanded(
                      flex: 6,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: tokens.surface.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(tokens.radiusMd),
                          border: Border.all(color: tokens.border),
                        ),
                        child: ListView(
                          children: [
                            Text(
                              strings.catSurfaces,
                              style: TextStyle(
                                color: tokens.accent,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            _buildColorRow(
                              'background',
                              _tr('Sfondo Principale', 'Main background'),
                              tokens: tokens,
                              fallback: tokens.background,
                            ),
                            _buildColorRow(
                              'surface',
                              _tr(
                                'Superficie Bento (Card)',
                                'Bento surface (cards)',
                              ),
                              tokens: tokens,
                              fallback: tokens.surface,
                            ),
                            _buildColorRow(
                              'surfaceElevated',
                              _tr(
                                'Superficie Elevata (Pannelli)',
                                'Elevated surface (panels)',
                              ),
                              tokens: tokens,
                              fallback: tokens.surfaceElevated,
                            ),
                            _buildColorRow(
                              'border',
                              _tr('Bordi & Separatori', 'Borders & separators'),
                              tokens: tokens,
                              fallback: tokens.border,
                            ),
                            _buildColorRow(
                              'borderStrong',
                              _tr('Bordi Evidenziati', 'Emphasized borders'),
                              tokens: tokens,
                              fallback: tokens.borderStrong,
                            ),

                            const SizedBox(height: 12),
                            Text(
                              strings.catAccents,
                              style: TextStyle(
                                color: tokens.accent,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            _buildColorRow(
                              'accent',
                              _tr(
                                'Colore Accento (Primario)',
                                'Accent color (primary)',
                              ),
                              tokens: tokens,
                              fallback: tokens.accent,
                            ),
                            _buildColorRow(
                              'accentContrast',
                              _tr('Testo su Accento', 'Text on accent'),
                              tokens: tokens,
                              fallback: tokens.accentContrast,
                            ),
                            _buildColorRow(
                              'focusRing',
                              _tr(
                                'Focus Ring / Selezione',
                                'Focus ring / selection',
                              ),
                              tokens: tokens,
                              fallback: tokens.focusRing,
                            ),

                            const SizedBox(height: 12),
                            Text(
                              strings.catText,
                              style: TextStyle(
                                color: tokens.accent,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            _buildColorRow(
                              'textPrimary',
                              _tr('Testo Primario', 'Primary text'),
                              tokens: tokens,
                              fallback: tokens.textPrimary,
                            ),
                            _buildColorRow(
                              'textSecondary',
                              _tr('Testo Secondario', 'Secondary text'),
                              tokens: tokens,
                              fallback: tokens.textSecondary,
                            ),
                            _buildColorRow(
                              'textMuted',
                              _tr('Testo Disattivato / Muted', 'Muted text'),
                              tokens: tokens,
                              fallback: tokens.textMuted,
                            ),

                            const SizedBox(height: 12),
                            Text(
                              strings.catAgent,
                              style: TextStyle(
                                color: tokens.accent,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            _buildColorRow(
                              'agentWorking',
                              _tr('Agente in Corso (Working)', 'Agent working'),
                              tokens: tokens,
                              fallback: tokens.agentWorking,
                            ),
                            _buildColorRow(
                              'agentSettled',
                              _tr('Agente Riposo (Settled)', 'Agent idle'),
                              tokens: tokens,
                              fallback: tokens.agentSettled,
                            ),
                            _buildColorRow(
                              'agentRetrying',
                              _tr(
                                'Agente Riprova (Retrying)',
                                'Agent retrying',
                              ),
                              tokens: tokens,
                              fallback: tokens.agentRetrying,
                            ),
                            _buildColorRow(
                              'agentCompacting',
                              _tr('Agente Compattazione', 'Agent compacting'),
                              tokens: tokens,
                              fallback: tokens.agentCompacting,
                            ),
                            _buildColorRow(
                              'danger',
                              _tr(
                                'Errore / Pericolo (Danger)',
                                'Error / danger',
                              ),
                              tokens: tokens,
                              fallback: tokens.danger,
                            ),

                            const SizedBox(height: 12),
                            Text(
                              strings.catSyntax,
                              style: TextStyle(
                                color: tokens.accent,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            _buildColorRow(
                              'keyword',
                              _tr('Parole Chiave (Keyword)', 'Keywords'),
                              isSyntax: true,
                              tokens: tokens,
                              fallback: tokens.syntaxKeyword,
                            ),
                            _buildColorRow(
                              'function',
                              _tr(
                                'Funzioni / Metodi (Function)',
                                'Functions / methods',
                              ),
                              isSyntax: true,
                              tokens: tokens,
                              fallback: tokens.syntaxFunction,
                            ),
                            _buildColorRow(
                              'string',
                              _tr('Stringhe (String)', 'Strings'),
                              isSyntax: true,
                              tokens: tokens,
                              fallback: tokens.syntaxString,
                            ),
                            _buildColorRow(
                              'number',
                              _tr('Numeri', 'Numbers'),
                              isSyntax: true,
                              tokens: tokens,
                              fallback: tokens.syntaxNumber,
                            ),
                            _buildColorRow(
                              'comment',
                              _tr('Commenti', 'Comments'),
                              isSyntax: true,
                              tokens: tokens,
                              fallback: tokens.syntaxComment,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Live Preview Column
                    Expanded(
                      flex: 5,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLivePreview(tokens),
                            if (_errorMessage != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                _errorMessage!,
                                style: TextStyle(
                                  color: tokens.danger,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              // Footer Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(strings.cancel),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    key: const ValueKey('theme-editor-save-btn'),
                    onPressed: _isSaving ? null : _saveAndApplyTheme,
                    icon: _isSaving
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              color: tokens.accentContrast,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.check, size: 16),
                    label: Text(strings.saveThemeAction),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
