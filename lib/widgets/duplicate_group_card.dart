import 'package:flutter/material.dart';
import '../models/duplicate_group.dart';
import '../theme/app_theme.dart';
import 'image_preview_dialog.dart';

class DuplicateGroupCard extends StatelessWidget {
  final DuplicateGroup group;
  final int groupIndex;
  final VoidCallback onChanged;

  const DuplicateGroupCard({
    super.key,
    required this.group,
    required this.groupIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppTheme.border),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.primary, AppTheme.primaryLight],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Nhóm ${groupIndex + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.copy_all, size: 14, color: AppTheme.danger),
                      const SizedBox(width: 4),
                      Text(
                        '${group.images.length} ảnh trùng',
                        style: const TextStyle(
                          color: AppTheme.danger,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (group.selectedCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Tiết kiệm: ${_formatSize(group.potentialSavings)}',
                      style: const TextStyle(
                        color: AppTheme.warning,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                _buildActionButton(
                  'Chọn bản trùng',
                  Icons.auto_fix_high,
                  () {
                    group.autoSelectDuplicates();
                    onChanged();
                  },
                ),
                const SizedBox(width: 4),
                _buildActionButton(
                  'Bỏ chọn tất cả',
                  Icons.deselect,
                  () {
                    group.deselectAll();
                    onChanged();
                  },
                ),
              ],
            ),
          ),
          // Images grid
          Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = constraints.maxWidth > 900
                    ? 5
                    : constraints.maxWidth > 600
                        ? 4
                        : 3;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: group.images.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final image = entry.value;
                    final width =
                        (constraints.maxWidth - (crossAxisCount - 1) * 12) /
                            crossAxisCount;
                    return SizedBox(
                      width: width,
                      child: _ImageTile(
                        image: image,
                        isOriginal: idx == 0,
                        onChanged: onChanged,
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(String tooltip, IconData icon, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppTheme.bgSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.border),
          ),
          child: Icon(icon, size: 16, color: AppTheme.textSecondary),
        ),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class _ImageTile extends StatefulWidget {
  final DuplicateImageInfo image;
  final bool isOriginal;
  final VoidCallback onChanged;

  const _ImageTile({
    required this.image,
    required this.isOriginal,
    required this.onChanged,
  });

  @override
  State<_ImageTile> createState() => _ImageTileState();
}

class _ImageTileState extends State<_ImageTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () {
          setState(() {
            widget.image.selected = !widget.image.selected;
          });
          widget.onChanged();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.image.selected
                  ? AppTheme.danger
                  : _isHovered
                      ? AppTheme.primaryLight
                      : AppTheme.border,
              width: widget.image.selected ? 2 : 1,
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    )
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Stack(
              children: [
                // Image thumbnail
                AspectRatio(
                  aspectRatio: 1,
                  child: Image.file(
                    widget.image.file,
                    fit: BoxFit.cover,
                    cacheWidth: 300,
                    errorBuilder: (_, e, st) => Container(
                      color: AppTheme.bgSurface,
                      child: const Icon(
                        Icons.broken_image,
                        color: AppTheme.textMuted,
                        size: 32,
                      ),
                    ),
                  ),
                ),
                // Selected overlay
                if (widget.image.selected)
                  Positioned.fill(
                    child: Container(
                      color: AppTheme.danger.withValues(alpha: 0.3),
                      child: const Center(
                        child: Icon(
                          Icons.delete_outline,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                // Original badge
                if (widget.isOriginal && !widget.image.selected)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'GỐC',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                // Checkbox
                Positioned(
                  top: 6,
                  right: 6,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _isHovered || widget.image.selected ? 1.0 : 0.0,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: widget.image.selected
                            ? AppTheme.danger
                            : Colors.black54,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: widget.image.selected
                              ? AppTheme.danger
                              : Colors.white54,
                          width: 1.5,
                        ),
                      ),
                      child: widget.image.selected
                          ? const Icon(Icons.check,
                              size: 14, color: Colors.white)
                          : null,
                    ),
                  ),
                ),
                // Preview button
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _isHovered ? 1.0 : 0.0,
                    child: GestureDetector(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (_) => ImagePreviewDialog(
                            imageFile: widget.image.file,
                            fileName: widget.image.name,
                            fileSize: widget.image.sizeFormatted,
                            filePath: widget.image.path,
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.zoom_in,
                            size: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ),
                // File info
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.8),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.image.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          widget.image.sizeFormatted,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
