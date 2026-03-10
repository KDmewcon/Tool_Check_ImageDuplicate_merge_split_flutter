import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../services/image_processor.dart';
import '../theme/app_theme.dart';

class MergeScreen extends StatefulWidget {
  const MergeScreen({super.key});

  @override
  State<MergeScreen> createState() => _MergeScreenState();
}

class _MergeScreenState extends State<MergeScreen> {
  final List<String> _imagePaths = [];
  String? _outputPath;
  int _columns = 2;
  int _spacing = 0;
  bool _isProcessing = false;
  double _progress = 0;
  String? _resultPath;
  final _columnsController = TextEditingController(text: '2');
  final _spacingController = TextEditingController(text: '0');

  Future<void> _pickImages() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Chọn ảnh để gộp',
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'bmp', 'gif', 'webp'],
      allowMultiple: true,
    );
    if (result != null) {
      final paths = result.paths.whereType<String>().toList();
      if (paths.isNotEmpty) {
        setState(() {
          _imagePaths.addAll(paths);
          _resultPath = null;
          _outputPath ??= p.join(p.dirname(paths.first), 'merged_output.png');
        });
      }
    }
  }

  void _removeImage(int index) {
    setState(() {
      _imagePaths.removeAt(index);
      _resultPath = null;
    });
  }

  void _clearAll() {
    setState(() {
      _imagePaths.clear();
      _resultPath = null;
    });
  }

  void _reorderImages(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _imagePaths.removeAt(oldIndex);
      _imagePaths.insert(newIndex, item);
      _resultPath = null;
    });
  }

  Future<void> _pickOutputPath() async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Lưu ảnh gộp',
      fileName: 'merged_output.png',
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'bmp'],
    );
    if (result != null) {
      setState(() {
        _outputPath = result;
      });
    }
  }

  Future<void> _startMerge() async {
    if (_imagePaths.isEmpty || _outputPath == null) return;
    _columns = int.tryParse(_columnsController.text) ?? 2;
    _spacing = int.tryParse(_spacingController.text) ?? 0;

    if (_columns <= 0) {
      _showError('Số cột phải lớn hơn 0');
      return;
    }

    setState(() {
      _isProcessing = true;
      _progress = 0;
      _resultPath = null;
    });

    try {
      final path = await ImageProcessor.mergeImages(
        inputPaths: _imagePaths,
        columns: _columns,
        outputPath: _outputPath!,
        spacing: _spacing,
        onProgress: (current, total) {
          setState(() {
            _progress = current / total;
          });
        },
      );
      setState(() {
        _resultPath = path;
        _isProcessing = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: AppTheme.success),
                const SizedBox(width: 12),
                const Text('Gộp ảnh thành công!',
                    style: TextStyle(fontWeight: FontWeight.w600)),
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
    if (mounted) {
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
  }

  @override
  void dispose() {
    _columnsController.dispose();
    _spacingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final settingsWidth = constraints.maxWidth > 800 ? 380.0 : constraints.maxWidth * 0.45;
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left panel: Settings
              SizedBox(
                width: settingsWidth,
                child: _buildSettingsPanel(),
              ),
              const SizedBox(width: 24),
              // Right panel: Preview
              Expanded(child: _buildPreviewPanel()),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSettingsPanel() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Image list
          _buildCard(
            title: 'Danh sách ảnh (${_imagePaths.length})',
            icon: Icons.collections,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_imagePaths.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.delete_sweep,
                        size: 18, color: AppTheme.danger),
                    onPressed: _clearAll,
                    tooltip: 'Xóa tất cả',
                  ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_imagePaths.isNotEmpty) ...[
                  Container(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: ReorderableListView.builder(
                      shrinkWrap: true,
                      buildDefaultDragHandles: true,
                      itemCount: _imagePaths.length,
                      onReorder: _reorderImages,
                      itemBuilder: (context, index) {
                        return _buildImageItem(index, key: ValueKey(_imagePaths[index] + index.toString()));
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _pickImages,
                  icon: const Icon(Icons.add_photo_alternate, size: 16),
                  label: const Text('Thêm ảnh'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Layout settings
          _buildCard(
            title: 'Bố cục',
            icon: Icons.dashboard,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _columnsController,
                        label: 'Số cột',
                        icon: Icons.view_column,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildTextField(
                        controller: _spacingController,
                        label: 'Khoảng cách (px)',
                        icon: Icons.space_bar,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Quick presets
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildPresetChip('1 cột', 1),
                    _buildPresetChip('2 cột', 2),
                    _buildPresetChip('3 cột', 3),
                    _buildPresetChip('4 cột', 4),
                    _buildPresetChip('5 cột', 5),
                  ],
                ),
                if (_imagePaths.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildLayoutInfo(),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Output
          _buildCard(
            title: 'Xuất file',
            icon: Icons.save_alt,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_outputPath != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.bgSurface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Text(
                      _outputPath!,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: _isProcessing ? null : _pickOutputPath,
                  icon: const Icon(Icons.folder_outlined, size: 16),
                  label: const Text('Chọn nơi lưu'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Merge button
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed:
                  _imagePaths.length >= 2 && !_isProcessing ? _startMerge : null,
              icon: _isProcessing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.merge, size: 18),
              label: Text(_isProcessing
                  ? 'Đang gộp...'
                  : 'Gộp ${_imagePaths.length} ảnh'),
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
            const SizedBox(height: 6),
            Text(
              '${(_progress * 100).toStringAsFixed(0)}%',
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildImageItem(int index, {Key? key}) {
    final path = _imagePaths[index];
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          // Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 36,
              height: 36,
              child: Image.file(
                File(path),
                fit: BoxFit.cover,
                cacheWidth: 72,
                errorBuilder: (_, e, st) => Container(
                  color: AppTheme.bgCard,
                  child:
                      const Icon(Icons.broken_image, size: 16, color: AppTheme.textMuted),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Index badge
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: AppTheme.primary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // File name
          Expanded(
            child: Text(
              p.basename(path),
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Remove button
          IconButton(
            icon: const Icon(Icons.close, size: 14, color: AppTheme.textMuted),
            onPressed: () => _removeImage(index),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewPanel() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: _resultPath != null
          ? _buildResultPreview()
          : _imagePaths.isEmpty
              ? _buildEmptyPreview()
              : _buildGridPreview(),
    );
  }

  Widget _buildEmptyPreview() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.merge, size: 56,
              color: AppTheme.primary.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          const Text('Thêm ảnh để bắt đầu gộp',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
          const SizedBox(height: 8),
          const Text('Kéo thả để sắp xếp thứ tự',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildGridPreview() {
    final cols = int.tryParse(_columnsController.text) ?? 2;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppTheme.border)),
          ),
          child: Row(
            children: [
              const Icon(Icons.preview, size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              const Text('Xem trước bố cục',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  )),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$cols cột × ${(_imagePaths.length / cols).ceil()} hàng',
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols.clamp(1, 10),
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _imagePaths.length,
            itemBuilder: (context, index) {
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.border),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(
                        File(_imagePaths[index]),
                        fit: BoxFit.cover,
                        cacheWidth: 300,
                        errorBuilder: (_, e, st) => Container(
                          color: AppTheme.bgSurface,
                          child: const Icon(Icons.broken_image,
                              color: AppTheme.textMuted),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildResultPreview() {
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
              const Text('Kết quả gộp ảnh',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  )),
              const Spacer(),
              Text(
                p.basename(_resultPath!),
                style:
                    const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: InteractiveViewer(
              maxScale: 5,
              child: Image.file(
                File(_resultPath!),
                fit: BoxFit.contain,
                errorBuilder: (_, e, st) => const Center(
                  child: Text('Không thể hiển thị ảnh',
                      style: TextStyle(color: AppTheme.textMuted)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCard({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
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
              Icon(icon, size: 16, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  )),
              if (trailing != null) ...[
                const Spacer(),
                trailing,
              ],
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        prefixIcon: Icon(icon, size: 16, color: AppTheme.textMuted),
        filled: true,
        fillColor: AppTheme.bgSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.primary),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Widget _buildPresetChip(String label, int cols) {
    final isSelected = _columnsController.text == cols.toString();
    return InkWell(
      onTap: () {
        setState(() {
          _columnsController.text = cols.toString();
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withValues(alpha: 0.2)
              : AppTheme.bgSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildLayoutInfo() {
    final cols = int.tryParse(_columnsController.text) ?? 2;
    final rows = cols > 0 ? (_imagePaths.length / cols).ceil() : 0;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.grid_on, size: 14, color: AppTheme.primary),
          const SizedBox(width: 8),
          Text(
            '${_imagePaths.length} ảnh → $cols cột × $rows hàng',
            style: const TextStyle(
              color: AppTheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
