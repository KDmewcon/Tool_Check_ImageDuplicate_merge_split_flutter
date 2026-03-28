import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import '../services/image_processor.dart';
import '../theme/app_theme.dart';

class CropRestoreScreen extends StatefulWidget {
  const CropRestoreScreen({super.key});

  @override
  State<CropRestoreScreen> createState() => _CropRestoreScreenState();
}

class _CropRestoreScreenState extends State<CropRestoreScreen> {
  String? _sourceDir;
  List<_ImageInfo> _images = [];

  int _cropTop = 1;
  int _cropBottom = 1;
  int _cropLeft = 1;
  int _cropRight = 1;
  bool _linkSides = true;

  String? _outputDir;
  bool _overwriteOriginal = false;

  bool _isProcessing = false;
  double _progress = 0;
  int _doneCount = 0;
  List<_ProcessResult> _results = [];

  Future<void> _pickSourceDir() async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Chọn thư mục chứa ảnh sprite',
    );
    if (dir != null) {
      setState(() {
        _sourceDir = dir;
        _results = [];
      });
      await _scanImages();
    }
  }

  Future<void> _pickOutputDir() async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Chọn thư mục xuất',
    );
    if (dir != null) setState(() => _outputDir = dir);
  }

  Future<void> _scanImages() async {
    if (_sourceDir == null) return;
    final dir = Directory(_sourceDir!);
    final images = <_ImageInfo>[];
    const exts = {'.png', '.jpg', '.jpeg', '.bmp', '.gif', '.webp'};

    await for (final entity in dir.list(recursive: false, followLinks: false)) {
      if (entity is File) {
        final ext = p.extension(entity.path).toLowerCase();
        if (exts.contains(ext)) {
          int w = 0, h = 0;
          try {
            final bytes = entity.readAsBytesSync();
            final decoded = img.decodeImage(bytes);
            if (decoded != null) {
              w = decoded.width;
              h = decoded.height;
            }
          } catch (_) {}
          images.add(_ImageInfo(path: entity.path, width: w, height: h));
        }
      }
    }

    images.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    setState(() => _images = images);
  }

  Future<void> _startProcess() async {
    if (_images.isEmpty) return;

    final effectiveOutputDir =
        _overwriteOriginal ? null : (_outputDir ?? '${_sourceDir!}_cropped');

    if (!_overwriteOriginal && effectiveOutputDir != null) {
      final outDirObj = Directory(effectiveOutputDir);
      if (!outDirObj.existsSync()) {
        outDirObj.createSync(recursive: true);
      }
    }

    setState(() {
      _isProcessing = true;
      _progress = 0;
      _doneCount = 0;
      _results = [];
    });

    final results = <_ProcessResult>[];

    for (int i = 0; i < _images.length; i++) {
      final image = _images[i];
      final fileName = p.basename(image.path);
      final outputPath = _overwriteOriginal
          ? image.path
          : p.join(effectiveOutputDir!, fileName);

      try {
        await ImageProcessor.cropAndRestore(
          inputPath: image.path,
          outputPath: outputPath,
          cropTop: _cropTop,
          cropBottom: _cropBottom,
          cropLeft: _cropLeft,
          cropRight: _cropRight,
        );
        final cropW = image.width - _cropLeft - _cropRight;
        final cropH = image.height - _cropTop - _cropBottom;
        results.add(_ProcessResult(
          fileName: fileName,
          success: true,
          detail: image.width > 0
              ? '${image.width}×${image.height} → ${cropW}×${cropH} → ${image.width}×${image.height}'
              : 'Xong',
        ));
      } catch (e) {
        results.add(_ProcessResult(
          fileName: fileName,
          success: false,
          detail: e.toString().split('\n').first,
        ));
      }

      setState(() {
        _doneCount = i + 1;
        _progress = (i + 1) / _images.length;
        _results = List.from(results);
      });
    }

    setState(() => _isProcessing = false);

    if (mounted) {
      final ok = results.where((r) => r.success).length;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle, color: AppTheme.success),
          const SizedBox(width: 12),
          Text('Xong! $ok/${results.length} ảnh',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      ));
    }
  }

  void _setCropAll(int value) {
    setState(() {
      _cropTop = value;
      _cropBottom = value;
      _cropLeft = value;
      _cropRight = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final sw = constraints.maxWidth > 800 ? 360.0 : constraints.maxWidth * 0.42;
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: sw, child: _buildSettings()),
            const SizedBox(width: 24),
            Expanded(child: _buildRightPanel()),
          ],
        ),
      );
    });
  }

  Widget _buildSettings() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Source folder
          _card(
            title: 'Thư mục ảnh',
            icon: Icons.folder_special,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_sourceDir != null) ...[
                  _infoBox(
                      icon: Icons.folder,
                      iconColor: AppTheme.accentLight,
                      text: p.basename(_sourceDir!),
                      sub: '${_images.length} ảnh tìm thấy'),
                  const SizedBox(height: 10),
                ],
                OutlinedButton.icon(
                  onPressed: _isProcessing ? null : _pickSourceDir,
                  icon: const Icon(Icons.folder_open, size: 16),
                  label: Text(_sourceDir == null ? 'Chọn thư mục' : 'Đổi thư mục'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Crop settings
          _card(
            title: 'Pixel cần cắt',
            icon: Icons.crop,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Link toggle
                _toggle(
                  icon: _linkSides ? Icons.link : Icons.link_off,
                  label: _linkSides ? 'Tất cả 4 cạnh bằng nhau' : 'Cài riêng từng cạnh',
                  active: _linkSides,
                  color: AppTheme.primary,
                  onTap: () => setState(() => _linkSides = !_linkSides),
                ),
                const SizedBox(height: 14),
                if (_linkSides) ...[
                  _cropRow('Tất cả', _cropTop, _setCropAll),
                ] else ...[
                  _cropRow('Trên', _cropTop, (v) => setState(() => _cropTop = v)),
                  const SizedBox(height: 8),
                  _cropRow('Dưới', _cropBottom, (v) => setState(() => _cropBottom = v)),
                  const SizedBox(height: 8),
                  _cropRow('Trái', _cropLeft, (v) => setState(() => _cropLeft = v)),
                  const SizedBox(height: 8),
                  _cropRow('Phải', _cropRight, (v) => setState(() => _cropRight = v)),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [1, 2, 3, 4, 8].map((n) => _presetChip('${n}px', n)).toList(),
                ),
                if (_images.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _previewCalcBox(_images.first),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Output
          _card(
            title: 'Thư mục xuất',
            icon: Icons.output,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _toggle(
                  icon: _overwriteOriginal ? Icons.warning_amber : Icons.save_alt,
                  label: _overwriteOriginal ? 'Ghi đè file gốc' : 'Lưu vào thư mục khác',
                  active: _overwriteOriginal,
                  color: AppTheme.danger,
                  onTap: () => setState(() => _overwriteOriginal = !_overwriteOriginal),
                ),
                if (!_overwriteOriginal) ...[
                  const SizedBox(height: 10),
                  if (_outputDir != null) ...[
                    _infoBox(
                        icon: Icons.folder,
                        iconColor: AppTheme.success,
                        text: p.basename(_outputDir!),
                        sub: 'Thư mục xuất đã chọn'),
                    const SizedBox(height: 8),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _sourceDir != null
                            ? 'Mặc định: ${p.basename(_sourceDir!)}_cropped'
                            : 'Mặc định: tên_gốc_cropped',
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: _isProcessing ? null : _pickOutputDir,
                    icon: const Icon(Icons.folder_open, size: 16),
                    label: Text(_outputDir == null ? 'Chọn thư mục xuất' : 'Đổi thư mục'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _images.isNotEmpty && !_isProcessing ? _startProcess : null,
              icon: _isProcessing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.crop_rotate, size: 18),
              label: Text(_isProcessing
                  ? 'Đang xử lý $_doneCount/${_images.length}...'
                  : 'Crop & Restore ${_images.length} ảnh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          if (_isProcessing) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _progress,
                backgroundColor: AppTheme.bgSurface,
                valueColor: const AlwaysStoppedAnimation(AppTheme.primary),
                minHeight: 6,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _previewCalcBox(_ImageInfo image) {
    final afterW = image.width - _cropLeft - _cropRight;
    final afterH = image.height - _cropTop - _cropBottom;
    final ok = image.width == 0 || (afterW > 0 && afterH > 0);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.info_outline, size: 12, color: AppTheme.primary),
            SizedBox(width: 6),
            Text('Ví dụ với ảnh đầu tiên:',
                style: TextStyle(
                    color: AppTheme.primary, fontSize: 10, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 6),
          if (image.width == 0)
            const Text('Không đọc được kích thước',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11))
          else
            Text(
              ok
                  ? '${image.width}×${image.height}  →  cắt  →  ${afterW}×${afterH}  →  zoom  →  ${image.width}×${image.height}'
                  : '❌ Crop quá lớn! (${image.width}×${image.height})',
              style: TextStyle(
                color: ok ? AppTheme.primary : AppTheme.danger,
                fontSize: 11,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }

  Widget _toggle({
    required IconData icon,
    required String label,
    required bool active,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.1) : AppTheme.bgSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: active ? color.withValues(alpha: 0.3) : AppTheme.border),
        ),
        child: Row(children: [
          Icon(icon, size: 16, color: active ? color : AppTheme.textMuted),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  color: active ? color : AppTheme.textSecondary, fontSize: 12)),
        ]),
      ),
    );
  }

  Widget _cropRow(String label, int value, void Function(int) onChanged) {
    return Row(
      children: [
        SizedBox(
            width: 48,
            child: Text(label,
                style:
                    const TextStyle(color: AppTheme.textSecondary, fontSize: 11))),
        const SizedBox(width: 8),
        _stepBtn(Icons.remove, value > 0 ? () => onChanged(value - 1) : null),
        const SizedBox(width: 8),
        Container(
          width: 56,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: AppTheme.bgSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border)),
          child: Text('$value px',
              style: const TextStyle(
                  color: AppTheme.warning,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace')),
        ),
        const SizedBox(width: 8),
        _stepBtn(Icons.add, value < 64 ? () => onChanged(value + 1) : null),
      ],
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
            color: onTap != null
                ? AppTheme.primary.withValues(alpha: 0.12)
                : AppTheme.bgSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.border)),
        child: Icon(icon,
            size: 16,
            color: onTap != null ? AppTheme.primary : AppTheme.textMuted),
      ),
    );
  }

  Widget _presetChip(String label, int value) {
    final isSelected = _linkSides && _cropTop == value;
    return InkWell(
      onTap: () => _setCropAll(value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primary.withValues(alpha: 0.2)
                : AppTheme.bgSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: isSelected ? AppTheme.primary : AppTheme.border)),
        child: Text(label,
            style: TextStyle(
                color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _infoBox(
      {required IconData icon,
      required Color iconColor,
      required String text,
      required String sub}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: AppTheme.bgSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border)),
      child: Row(children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(text,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis),
            Text(sub,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 11)),
          ]),
        ),
      ]),
    );
  }

  Widget _buildRightPanel() {
    return Container(
      decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border)),
      child: _sourceDir == null
          ? _buildEmpty()
          : _results.isNotEmpty
              ? _buildResults()
              : _buildImageList(),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.crop_rotate,
              size: 56, color: AppTheme.primary.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          const Text('Chọn thư mục chứa sprite',
              style:
                  TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
          const SizedBox(height: 8),
          const Text(
            'Cắt N pixel viền → zoom về size gốc\nNearest-neighbor — giữ chất lượng pixel art',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildImageList() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.border))),
          child: Row(children: [
            const Icon(Icons.image, size: 18, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text('${_images.length} ảnh trong thư mục',
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _images.length,
            itemBuilder: (context, i) {
              final image = _images[i];
              final afterW = image.width - _cropLeft - _cropRight;
              final afterH = image.height - _cropTop - _cropBottom;
              final valid = image.width == 0 || (afterW > 0 && afterH > 0);
              return Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                    color: valid
                        ? Colors.transparent
                        : AppTheme.danger.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: valid
                        ? null
                        : Border.all(
                            color: AppTheme.danger.withValues(alpha: 0.2))),
                child: Row(
                  children: [
                    Icon(
                      valid ? Icons.crop_rotate : Icons.error_outline,
                      size: 14,
                      color: valid ? AppTheme.primary : AppTheme.danger,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(p.basename(image.path),
                            style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 12,
                                fontFamily: 'monospace'),
                            overflow: TextOverflow.ellipsis)),
                    if (image.width > 0)
                      Text('${image.width}×${image.height}',
                          style: const TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 11,
                              fontFamily: 'monospace')),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildResults() {
    final ok = _results.where((r) => r.success).length;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.border))),
          child: Row(
            children: [
              Icon(
                ok == _results.length ? Icons.check_circle : Icons.warning_amber,
                size: 18,
                color: ok == _results.length ? AppTheme.success : AppTheme.warning,
              ),
              const SizedBox(width: 8),
              Text('Kết quả: $ok/${_results.length} ảnh thành công',
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () => setState(() => _results = []),
                icon: const Icon(Icons.refresh, size: 14),
                label: const Text('Xử lý lại'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _results.length,
            itemBuilder: (context, i) {
              final r = _results[i];
              return Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: r.success
                        ? AppTheme.success.withValues(alpha: 0.05)
                        : AppTheme.danger.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: r.success
                            ? AppTheme.success.withValues(alpha: 0.15)
                            : AppTheme.danger.withValues(alpha: 0.2))),
                child: Row(children: [
                  Icon(
                      r.success ? Icons.check_circle : Icons.error,
                      size: 14,
                      color: r.success ? AppTheme.success : AppTheme.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.fileName,
                              style: TextStyle(
                                  color: r.success
                                      ? AppTheme.textSecondary
                                      : AppTheme.danger,
                                  fontSize: 12,
                                  fontFamily: 'monospace')),
                          Text(r.detail,
                              style: TextStyle(
                                  color: r.success
                                      ? AppTheme.primary
                                      : AppTheme.textMuted,
                                  fontSize: 10)),
                        ]),
                  ),
                ]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _card(
      {required String title,
      required IconData icon,
      required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _ImageInfo {
  final String path;
  final int width;
  final int height;
  _ImageInfo({required this.path, required this.width, required this.height});
}

class _ProcessResult {
  final String fileName;
  final bool success;
  final String detail;
  _ProcessResult(
      {required this.fileName, required this.success, required this.detail});
}
