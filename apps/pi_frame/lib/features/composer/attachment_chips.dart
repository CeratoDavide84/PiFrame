import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/language/language_settings.dart';
import '../../domain/session/attachment_model.dart';

class WebLinkInputDialog extends ConsumerStatefulWidget {
  const WebLinkInputDialog({super.key});

  static Future<ChatAttachment?> show(BuildContext context) {
    return showDialog<ChatAttachment>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const WebLinkInputDialog(),
    );
  }

  @override
  ConsumerState<WebLinkInputDialog> createState() => _WebLinkInputDialogState();
}

class _WebLinkInputDialogState extends ConsumerState<WebLinkInputDialog> {
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();
  String? _error;

  String _tr(String it, String en) =>
      ref.read(appLanguageProvider) == AppLanguage.it ? it : en;

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final rawUrl = _urlController.text.trim();
    if (rawUrl.isEmpty) {
      setState(
        () => _error = _tr('Inserisci un URL valido', 'Enter a valid URL'),
      );
      return;
    }

    String formattedUrl = rawUrl;
    if (!formattedUrl.startsWith('http://') &&
        !formattedUrl.startsWith('https://')) {
      formattedUrl = 'https://$formattedUrl';
    }

    final uri = Uri.tryParse(formattedUrl);
    if (uri == null || !uri.hasAuthority) {
      setState(
        () => _error = _tr('Formato URL non valido', 'Invalid URL format'),
      );
      return;
    }

    final rawName = _nameController.text.trim();
    final name = rawName.isNotEmpty ? rawName : formattedUrl;

    Navigator.of(context).pop(
      ChatAttachment(
        id: 'att_link_${DateTime.now().microsecondsSinceEpoch}',
        type: AttachmentType.webLink,
        name: name,
        pathOrUrl: formattedUrl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appLanguageProvider);
    final tokens = context.tokens;
    return Dialog(
      backgroundColor: tokens.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        side: BorderSide(color: tokens.borderStrong),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: tokens.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                    ),
                    child: Icon(Icons.link, size: 18, color: tokens.accent),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _tr('Aggiungi link web', 'Add web link'),
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      fontFamily: tokens.headingFontFamily,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('weblink-dialog-url-field'),
                controller: _urlController,
                autofocus: true,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 13,
                  fontFamily: tokens.monoFontFamily,
                ),
                decoration: InputDecoration(
                  labelText: 'URL',
                  hintText: 'https://example.com/docs',
                  errorText: _error,
                  prefixIcon: const Icon(Icons.language, size: 16),
                  filled: true,
                  fillColor: tokens.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('weblink-dialog-name-field'),
                controller: _nameController,
                style: TextStyle(color: tokens.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  labelText: _tr(
                    'Titolo o etichetta (opzionale)',
                    'Title or label (optional)',
                  ),
                  hintText: _tr(
                    'Documentazione API, PR GitHub...',
                    'API documentation, GitHub PR...',
                  ),
                  prefixIcon: const Icon(Icons.label_outline, size: 16),
                  filled: true,
                  fillColor: tokens.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      _tr('Annulla', 'Cancel'),
                      style: TextStyle(color: tokens.textMuted),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    key: const ValueKey('weblink-dialog-submit-btn'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: tokens.accent,
                      foregroundColor: tokens.accentContrast,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                      ),
                    ),
                    onPressed: _submit,
                    child: Text(_tr('Aggiungi link', 'Add link')),
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

class ImagePreviewDialog extends ConsumerWidget {
  final String pathOrUrl;
  final String title;

  const ImagePreviewDialog({
    super.key,
    required this.pathOrUrl,
    required this.title,
  });

  static Future<void> show(
    BuildContext context, {
    required String pathOrUrl,
    required String title,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: context.tokens.overlay,
      barrierDismissible: true,
      builder: (ctx) => ImagePreviewDialog(pathOrUrl: pathOrUrl, title: title),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isItalian = ref.watch(appLanguageProvider) == AppLanguage.it;
    final tokens = context.tokens;

    return Dialog(
      key: const ValueKey('image-lightbox-dialog'),
      backgroundColor: tokens.background.withValues(alpha: 0),
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 780),
        child: Container(
          decoration: BoxDecoration(
            color: tokens.surface.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(tokens.radiusLg),
            border: Border.all(color: tokens.borderStrong),
            boxShadow: [
              BoxShadow(color: tokens.overlay, blurRadius: 24, spreadRadius: 4),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: tokens.border, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.image_outlined, size: 18, color: tokens.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            pathOrUrl,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: 10.5,
                              fontFamily: tokens.monoFontFamily,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: tokens.textMuted,
                      ),
                      tooltip: isItalian ? 'Chiudi anteprima' : 'Close preview',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              // Image Viewer with interactive pan & zoom
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(tokens.radiusLg),
                    bottomRight: Radius.circular(tokens.radiusLg),
                  ),
                  child: Container(
                    color: tokens.overlay,
                    child: InteractiveViewer(
                      maxScale: 5.0,
                      minScale: 0.5,
                      child: Center(
                        child: buildAttachmentImage(
                          pathOrUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (ctx, err, stack) =>
                              _buildError(tokens, isItalian),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError(FrameTokens tokens, bool isItalian) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.broken_image_outlined, size: 48, color: tokens.danger),
        const SizedBox(height: 8),
        Text(
          isItalian
              ? 'Impossibile caricare l\'immagine'
              : 'Unable to load image',
          style: TextStyle(color: tokens.textSecondary, fontSize: 13),
        ),
      ],
    );
  }
}

class AttachmentChip extends ConsumerWidget {
  final ChatAttachment attachment;
  final bool isEditable;
  final VoidCallback? onRemove;
  final VoidCallback? onImageTap;

  const AttachmentChip({
    super.key,
    required this.attachment,
    this.isEditable = false,
    this.onRemove,
    this.onImageTap,
  });

  Future<void> _handleLinkTap() async {
    final uri = Uri.tryParse(attachment.pathOrUrl);
    if (uri != null) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;

    if (attachment.isImage) {
      return _buildImageThumbnail(context, tokens, ref.watch(appLanguageProvider) == AppLanguage.it);
    }

    if (attachment.isWebLink) {
      return _buildWebLinkChip(context, tokens);
    }

    return _buildFileChip(context, tokens);
  }

  Widget _buildFileChip(BuildContext context, FrameTokens tokens) {
    return Container(
      key: ValueKey('attachment-file-${attachment.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tokens.surfaceElevated,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.borderStrong, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            attachment.type == AttachmentType.repoFile
                ? Icons.folder_outlined
                : Icons.insert_drive_file_outlined,
            size: 14,
            color: tokens.accent,
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: attachment.pathOrUrl,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                attachment.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  fontFamily: tokens.monoFontFamily,
                ),
              ),
            ),
          ),
          if (isEditable) ...[
            const SizedBox(width: 4),
            InkWell(
              key: ValueKey('attachment-remove-${attachment.id}'),
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              onTap: onRemove,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(Icons.close, size: 12, color: tokens.textMuted),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWebLinkChip(BuildContext context, FrameTokens tokens) {
    return InkWell(
      key: ValueKey('attachment-link-${attachment.id}'),
      borderRadius: BorderRadius.circular(tokens.radiusSm),
      onTap: isEditable ? null : _handleLinkTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: tokens.surfaceElevated,
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          border: Border.all(
            color: tokens.syntaxKeyword.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.link, size: 14, color: tokens.syntaxKeyword),
            const SizedBox(width: 6),
            Tooltip(
              message: attachment.pathOrUrl,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.syntaxKeyword,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    decoration: isEditable ? null : TextDecoration.underline,
                  ),
                ),
              ),
            ),
            if (isEditable) ...[
              const SizedBox(width: 4),
              InkWell(
                key: ValueKey('attachment-remove-${attachment.id}'),
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                onTap: onRemove,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.close, size: 12, color: tokens.textMuted),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildImageThumbnail(BuildContext context, FrameTokens tokens, bool isItalian) {
    return Stack(
      key: ValueKey('attachment-image-${attachment.id}'),
      clipBehavior: Clip.none,
      children: [
        Tooltip(
          message: isItalian ? '${attachment.name} (Clicca per ingrandire)' : '${attachment.name} (Click to enlarge)',
          child: InkWell(
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            onTap:
                onImageTap ??
                () => ImagePreviewDialog.show(
                  context,
                  pathOrUrl: attachment.pathOrUrl,
                  title: attachment.name,
                ),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                border: Border.all(color: tokens.borderStrong, width: 1.2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(tokens.radiusSm - 1),
                child: buildAttachmentImage(
                  attachment.pathOrUrl,
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, err, stack) => Icon(
                    Icons.image_not_supported_outlined,
                    size: 22,
                    color: tokens.textMuted,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (isEditable)
          Positioned(
            top: -4,
            right: -4,
            child: InkWell(
              key: ValueKey('attachment-remove-${attachment.id}'),
              borderRadius: BorderRadius.circular(10),
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: tokens.surfaceElevated,
                  shape: BoxShape.circle,
                  border: Border.all(color: tokens.borderStrong, width: 1),
                ),
                child: Icon(Icons.close, size: 10, color: tokens.textMuted),
              ),
            ),
          ),
      ],
    );
  }
}

Widget buildAttachmentImage(
  String pathOrUrl, {
  double? width,
  double? height,
  required BoxFit fit,
  required Widget Function(BuildContext, Object, StackTrace?) errorBuilder,
}) {
  if (pathOrUrl.startsWith('data:')) {
    final uri = Uri.tryParse(pathOrUrl);
    final bytes = uri?.data?.contentAsBytes();
    if (bytes != null) {
      return Image.memory(
        bytes,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: errorBuilder,
      );
    }
  }
  if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
    return Image.network(
      pathOrUrl,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: errorBuilder,
    );
  }
  if (!kIsWeb) {
    return Image.file(
      File(pathOrUrl),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: errorBuilder,
    );
  }
  return Builder(
    builder: (ctx) =>
        errorBuilder(ctx, StateError('Unsupported image source'), null),
  );
}

class AttachmentListBar extends StatelessWidget {
  final List<ChatAttachment> attachments;
  final bool isEditable;
  final void Function(ChatAttachment attachment)? onRemove;
  final void Function(ChatAttachment attachment)? onImageTap;

  const AttachmentListBar({
    super.key,
    required this.attachments,
    this.isEditable = false,
    this.onRemove,
    this.onImageTap,
  });

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final a in attachments)
            AttachmentChip(
              attachment: a,
              isEditable: isEditable,
              onRemove: onRemove != null ? () => onRemove!(a) : null,
              onImageTap: onImageTap != null ? () => onImageTap!(a) : null,
            ),
        ],
      ),
    );
  }
}
