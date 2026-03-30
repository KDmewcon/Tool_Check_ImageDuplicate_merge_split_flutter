import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../services/image_processor.dart';
import '../theme/app_theme.dart';

class ResizeScreen extends StatefulWidget {
  const ResizeScreen({super.key});

  @override
  State<ResizeScreen> createState() => _ResizeScreenState();
}

class _ScaleOption {
  final String folderName;
  final double percentage;
  final String label;
  bool enabled;

  _ScaleOption({
    required this.folderName,
    required this.percentage,
    required this.label,
    this.enabled = true,
  });
}

class _ResizeScreenState extends State<ResizeScreen> {
  String? _selectedDir;
  List<String> _imageFiles = [];
  bool _isProcessing = false;
  double _progress = 0;
  String _currentFile = '';
  Map<String, List<String>>? _results;

  final List<_ScaleOption> _scaleOptions = [
    _ScaleOption(folderName: 'x3', percentage: 0.75, label: '75%'),
    _ScaleOption(folderName: 'x2', percentage: 0.50, label: '50%'),
    _ScaleOption(folderName: 'x1', percentage: 0.25, label: '25%'),
  ];

  Future<void> _pickSourceDir() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Chọn thư mục ảnh gốc (x4)',
    );
    if (result != null) {
      setState(() {
        _selectedDir = result;
        _results = null;
      });
      await _scanImages();
    }
  }

  Future<void> _scanImages() async {
    if (_selectedDir == null) return;
    final dir = Directory(_selectedDir!);
    final files = <String>[];

    await for (final entity in dir.list(recursive: false, followLinks: false)) {
      if (entity is! File) continue;
      final ext = p.extension(entity.path).toLowerCase();
      if (['.png', '.jpg', '.jpeg', '.bmp', '.gif', '.webp'].contains(ext)) {
        files.add(entity.path);
      }
    }

    files.sort((a, b) => p.basename(a).compareTo(p.basename(b)));
    setState(() => _imageFiles = files);
  }

  Future<void> _startResize() async {
    if (_selectedDir == null || _imageFiles.isEmpty) return;

    final enabledScales = _scaleOptions
        .where((s) => s.enabled)
        .map((s) => ResizeScale(
              folderName: s.folderName,
              percentage: s.percentage,
            ))
        .toList();

    if (enabledScales.isEmpty) {
      _showError('Chọn ít nhất một mức resize');
      return;
    }

    setState(() {
      _isProcessing = true;
      _progress = 0;
      _currentFile = '';
      _results = null;
    });

    try {
      final results = await ImageProcessor.resizeBatch(
        sourceDir: _selectedDir!,
        scales: enabledScales,
        onProgress: (current, total, file) {
          setState(() {
            _progress = total > 0 ? current / total : 0;
            _currentFile = file;
          });
        },
      );
      setState(() {
        _results = results;
        _isProcessing = false;
      });

      if (mounted) {
        var totalFiles = 0;
        results.forEach((_, files) => totalFiles += files.length);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: AppTheme.success),
                const SizedBox(width: 12),
                Text(
                  'Đã tạo $totalFiles ảnh trong ${results.length} thư mục!',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      _showError(e.toString());
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: AppTheme.danger),
            const SizedBox(width: 12),
            Expanded(child: Text(msg)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 1180;
        final pagePadding = constraints.maxWidth < 880 ? 16.0 : 24.0;
        final panelGap = constraints.maxWidth < 880 ? 16.0 : 24.0;
        final settingsWidth =
            (constraints.maxWidth * 0.36).clamp(360.0, 440.0);

        return Padding(
          padding: EdgeInsets.all(pagePadding),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (currentChild, previousChildren) {
              return Stack(
                alignment: Alignment.topCenter,
                children: [
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              );
            },
            child: SizedBox(
              key: isCompact
                  ? const ValueKey('compact-layout')
                  : const ValueKey('wide-layout'),
              width: constraints.maxWidth - (pagePadding * 2),
              height: constraints.maxHeight - (pagePadding * 2),
              child: isCompact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _buildSettingsPanel()),
                        SizedBox(height: panelGap),
                        Expanded(child: _buildPreviewPanel()),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: settingsWidth,
                          child: _buildSettingsPanel(),
                        ),
                        SizedBox(width: panelGap),
                        Expanded(child: _buildPreviewPanel()),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSettingsPanel() {
    return SingleChildScrollView(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCard(
              title: 'Thư mục gốc (x4)',
              icon: Icons.folder_special,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildAnimatedVisibility(
                    visible: _selectedDir != null,
                    child: Padding(
                      key: ValueKey(_selectedDir ?? 'selected-dir'),
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.bgSurface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.folder,
                                size: 16, color: AppTheme.primaryLight),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.basename(_selectedDir ?? ''),
                                    style: const TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${_imageFiles.length} ảnh',
                                    style: const TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _pickSourceDir,
                    icon: const Icon(Icons.folder_open, size: 16),
                    label: Text(
                      _selectedDir == null ? 'Chọn thư mục x4' : 'Đổi thư mục',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryLight,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildCard(
              title: 'Mức resize',
              icon: Icons.photo_size_select_large,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'x4',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Gốc - 100%',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        const Icon(Icons.star, size: 14, color: AppTheme.primary),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Row(
                    children: [
                      Icon(Icons.arrow_downward,
                          size: 12, color: AppTheme.textMuted),
                      SizedBox(width: 4),
                      Text(
                        'Sẽ tạo các thư mục:',
                        style:
                            TextStyle(color: AppTheme.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._scaleOptions.map(_buildScaleOptionTile),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildAnimatedVisibility(
              visible: _selectedDir != null,
              child: _selectedDir == null
                  ? const SizedBox.shrink(key: ValueKey('empty-output'))
                  : Column(
                      key: ValueKey('output-$_selectedDir'),
                      children: [
                        _buildCard(
                          title: 'Thư mục xuất',
                          icon: Icons.output,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ..._scaleOptions.where((s) => s.enabled).map((s) {
                                final outputDir = p.join(
                                    p.dirname(_selectedDir!), s.folderName);
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _getScaleColor(s.percentage)
                                              .withValues(alpha: 0.2),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          s.folderName,
                                          style: TextStyle(
                                            color: _getScaleColor(s.percentage),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          outputDir,
                                          style: const TextStyle(
                                            color: AppTheme.textSecondary,
                                            fontSize: 10,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
            ),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _selectedDir != null &&
                        _imageFiles.isNotEmpty &&
                        !_isProcessing &&
                        _scaleOptions.any((s) => s.enabled)
                    ? _startResize
                    : null,
                icon: _isProcessing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.photo_size_select_large, size: 18),
                label: Text(_isProcessing ? 'Dang resize...' : 'Bat dau resize'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            _buildAnimatedVisibility(
              visible: _isProcessing,
              child: Padding(
                key: ValueKey('progress-${_progress.toStringAsFixed(2)}'),
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _progress,
                        backgroundColor: AppTheme.bgSurface,
                        valueColor:
                            const AlwaysStoppedAnimation(AppTheme.primary),
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${(_progress * 100).toStringAsFixed(0)}% - $_currentFile',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedVisibility({
    required bool visible,
    required Widget child,
  }) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SizeTransition(
            sizeFactor: animation,
            axisAlignment: -1,
            child: child,
          ),
        );
      },
      child: visible
          ? child
          : const SizedBox.shrink(
              key: ValueKey('hidden'),
            ),
    );
  }

  Widget _buildScaleOptionTile(_ScaleOption option) {
    final color = _getScaleColor(option.percentage);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: _isProcessing
            ? null
            : () {
                setState(() => option.enabled = !option.enabled);
              },
        borderRadius: BorderRadius.circular(12),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          scale: option.enabled ? 1 : 0.985,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: option.enabled
                  ? color.withValues(alpha: 0.1)
                  : AppTheme.bgSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: option.enabled
                    ? color.withValues(alpha: 0.38)
                    : AppTheme.border,
                width: option.enabled ? 1.4 : 1,
              ),
              boxShadow: option.enabled
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.12),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: option.enabled
                        ? color.withValues(alpha: 0.18)
                        : Colors.transparent,
                    border: Border.all(
                      color: option.enabled ? color : AppTheme.textMuted,
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    option.enabled ? Icons.check : Icons.add,
                    size: 13,
                    color: option.enabled ? color : AppTheme.textMuted,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    option.folderName,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.label,
                        style: TextStyle(
                          color: option.enabled
                              ? AppTheme.textPrimary
                              : AppTheme.textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        option.enabled
                            ? 'Tao ban ${option.folderName} voi ${(option.percentage * 100).toInt()}% kich thuoc'
                            : 'Bo qua muc ${option.folderName}',
                        style: TextStyle(
                          color: option.enabled
                              ? AppTheme.textSecondary
                              : AppTheme.textMuted,
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getScaleColor(double percentage) {
    if (percentage >= 0.75) return AppTheme.success;
    if (percentage >= 0.50) return AppTheme.accent;
    return AppTheme.warning;
  }

  Widget _buildPreviewPanel() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: _selectedDir == null
            ? const KeyedSubtree(
                key: ValueKey('empty-preview'),
                child: _ResizeEmptyPreview(),
              )
            : _results != null
                ? KeyedSubtree(
                    key: ValueKey('results-view'),
                    child: _buildResultsView(),
                  )
                : KeyedSubtree(
                    key: ValueKey('list-view'),
                    child: _buildFileListPreview(),
                  ),
      ),
    );
  }

  Widget _buildFileListPreview() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = (constraints.maxWidth / 180).floor().clamp(2, 6);
        final childAspectRatio = constraints.maxWidth < 760 ? 0.9 : 0.96;

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppTheme.border)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.image, size: 18, color: AppTheme.primaryLight),
                  const SizedBox(width: 8),
                  Text(
                    '${_imageFiles.length} ảnh trong thư mục gốc',
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _imageFiles.isEmpty
                  ? const Center(
                      child: Text(
                        'Không tìm thấy ảnh',
                        style: TextStyle(color: AppTheme.textMuted),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: childAspectRatio,
                      ),
                      itemCount: _imageFiles.length,
                      itemBuilder: (context, index) {
                        return _buildImageTile(_imageFiles[index]);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildResultsView() {
    final entries = _results!.entries.toList();
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppTheme.border)),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle, size: 18, color: AppTheme.success),
              const SizedBox(width: 8),
              Text(
                'Đã tạo ${entries.length} thư mục resize',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() => _results = null);
                },
                icon: const Icon(Icons.arrow_back, size: 14),
                label: const Text('Quay lại'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              final folderName = entry.key;
              final files = entry.value;
              final option = _scaleOptions.firstWhere(
                (s) => s.folderName == folderName,
                orElse: () => _ScaleOption(
                  folderName: folderName,
                  percentage: 0.5,
                  label: '',
                ),
              );
              final color = _getScaleColor(option.percentage);

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppTheme.bgSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.08),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(11),
                          topRight: Radius.circular(11),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              folderName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${option.label} - ${files.length} ảnh',
                            style: TextStyle(
                              color: color,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          Icon(Icons.check_circle, size: 16, color: color),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 100,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.all(8),
                        itemCount: files.length,
                        itemBuilder: (context, fileIndex) {
                          return Container(
                            width: 80,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(7),
                              child: Image.file(
                                File(files[fileIndex]),
                                fit: BoxFit.cover,
                                cacheWidth: 100,
                                errorBuilder: (_, __, ___) => Container(
                                  color: AppTheme.bgSurface,
                                  child: const Icon(
                                    Icons.broken_image,
                                    color: AppTheme.textMuted,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildImageTile(String path) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
        color: AppTheme.bgSurface,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(path),
              fit: BoxFit.cover,
              cacheWidth: 240,
              errorBuilder: (_, __, ___) => Container(
                color: AppTheme.bgSurface,
                child: const Icon(
                  Icons.broken_image,
                  color: AppTheme.textMuted,
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.0),
                      Colors.black.withValues(alpha: 0.68),
                    ],
                  ),
                ),
                child: Text(
                  p.basename(path),
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppTheme.primaryLight),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _ResizeEmptyPreview extends StatelessWidget {
  const _ResizeEmptyPreview();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primary.withValues(alpha: 0.26),
                    AppTheme.accent.withValues(alpha: 0.14),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Icon(
                Icons.photo_size_select_large,
                size: 40,
                color: AppTheme.primary.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Chọn thư mục ảnh gốc (x4)',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'App sẽ tạo các thư mục x3, x2, x1 với ảnh đã resize tương ứng',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
