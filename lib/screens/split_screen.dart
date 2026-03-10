import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../services/image_processor.dart';
import '../theme/app_theme.dart';

class SplitScreen extends StatefulWidget {
  const SplitScreen({super.key});

  @override
  State<SplitScreen> createState() => _SplitScreenState();
}

class _SplitScreenState extends State<SplitScreen> {
  String? _selectedImagePath;
  String? _outputDir;
  int _tileWidth = 256;
  int _tileHeight = 256;
  int? _imageWidth;
  int? _imageHeight;
  bool _isProcessing = false;
  double _progress = 0;
  List<String> _resultPaths = [];
  final _widthController = TextEditingController(text: '256');
  final _heightController = TextEditingController(text: '256');

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Chọn ảnh để tách',
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'bmp', 'gif', 'webp'],
    );
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      setState(() {
        _selectedImagePath = path;
        _outputDir = p.join(p.dirname(path), '${p.basenameWithoutExtension(path)}_split');
        _resultPaths = [];
      });
      // Get image dimensions
      final size = await ImageProcessor.getImageSize(path);
      if (size != null) {
        setState(() {
          _imageWidth = size.width;
          _imageHeight = size.height;
        });
      }
    }
  }

  Future<void> _pickOutputDir() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Chọn thư mục xuất',
    );
    if (result != null) {
      setState(() {
        _outputDir = result;
      });
    }
  }

  Future<void> _startSplit() async {
    if (_selectedImagePath == null || _outputDir == null) return;
    _tileWidth = int.tryParse(_widthController.text) ?? 256;
    _tileHeight = int.tryParse(_heightController.text) ?? 256;

    if (_tileWidth <= 0 || _tileHeight <= 0) {
      _showError('Kích thước phải lớn hơn 0');
      return;
    }

    setState(() {
      _isProcessing = true;
      _progress = 0;
      _resultPaths = [];
    });

    try {
      final paths = await ImageProcessor.splitImage(
        inputPath: _selectedImagePath!,
        tileWidth: _tileWidth,
        tileHeight: _tileHeight,
        outputDir: _outputDir!,
        onProgress: (current, total) {
          setState(() {
            _progress = current / total;
          });
        },
      );
      setState(() {
        _resultPaths = paths;
        _isProcessing = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: AppTheme.success),
                const SizedBox(width: 12),
                Text('Đã tách thành ${paths.length} ảnh!',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
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
    _widthController.dispose();
    _heightController.dispose();
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
              // Right panel: Preview & Results
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
          // Image selector
          _buildCard(
            title: 'Ảnh nguồn',
            icon: Icons.image,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_selectedImagePath != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.bgSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.insert_photo, size: 16, color: AppTheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.basename(_selectedImagePath!),
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (_imageWidth != null && _imageHeight != null)
                                Text(
                                  '$_imageWidth × $_imageHeight px',
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
                  const SizedBox(height: 10),
                ],
                ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _pickImage,
                  icon: const Icon(Icons.add_photo_alternate, size: 16),
                  label: Text(_selectedImagePath == null ? 'Chọn ảnh' : 'Đổi ảnh'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Tile size
          _buildCard(
            title: 'Kích thước mỗi mảnh',
            icon: Icons.grid_view,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _widthController,
                        label: 'Chiều rộng (px)',
                        icon: Icons.width_normal,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('×', style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 20,
                        fontWeight: FontWeight.w300,
                      )),
                    ),
                    Expanded(
                      child: _buildTextField(
                        controller: _heightController,
                        label: 'Chiều cao (px)',
                        icon: Icons.height,
                      ),
                    ),
                  ],
                ),
                if (_imageWidth != null && _imageHeight != null) ...[
                  const SizedBox(height: 12),
                  _buildInfoRow(),
                ],
                const SizedBox(height: 12),
                // Quick presets
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildPresetChip('64×64', 64, 64),
                    _buildPresetChip('128×128', 128, 128),
                    _buildPresetChip('256×256', 256, 256),
                    _buildPresetChip('512×512', 512, 512),
                    _buildPresetChip('1024×1024', 1024, 1024),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Output directory
          _buildCard(
            title: 'Thư mục xuất',
            icon: Icons.folder_open,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_outputDir != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.bgSurface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Text(
                      _outputDir!,
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: _isProcessing ? null : _pickOutputDir,
                  icon: const Icon(Icons.folder_outlined, size: 16),
                  label: const Text('Chọn thư mục'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Start button
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _selectedImagePath != null && !_isProcessing
                  ? _startSplit
                  : null,
              icon: _isProcessing
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.content_cut, size: 18),
              label: Text(_isProcessing ? 'Đang tách...' : 'Bắt đầu tách ảnh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
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
                valueColor: const AlwaysStoppedAnimation(AppTheme.accent),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${(_progress * 100).toStringAsFixed(0)}%',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
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
      child: _selectedImagePath == null
          ? _buildEmptyPreview()
          : _resultPaths.isNotEmpty
              ? _buildResultsGrid()
              : _buildImagePreview(),
    );
  }

  Widget _buildEmptyPreview() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.content_cut, size: 56,
              color: AppTheme.accent.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          const Text('Chọn ảnh để bắt đầu tách',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildImagePreview() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppTheme.border)),
          ),
          child: const Row(
            children: [
              Icon(Icons.preview, size: 18, color: AppTheme.accent),
              SizedBox(width: 8),
              Text('Xem trước', style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              )),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Image.file(
              File(_selectedImagePath!),
              fit: BoxFit.contain,
              errorBuilder: (_, e, st) => const Center(
                child: Text('Không thể hiển thị ảnh',
                    style: TextStyle(color: AppTheme.textMuted)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultsGrid() {
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
              Text('Kết quả: ${_resultPaths.length} mảnh',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  )),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() => _resultPaths = []);
                },
                icon: const Icon(Icons.arrow_back, size: 14),
                label: const Text('Quay lại'),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: _resultPaths.length,
            itemBuilder: (context, index) {
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.border),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(
                        File(_resultPaths[index]),
                        fit: BoxFit.cover,
                        cacheWidth: 200,
                        errorBuilder: (_, e, st) => Container(
                          color: AppTheme.bgSurface,
                          child: const Icon(Icons.broken_image,
                              color: AppTheme.textMuted),
                        ),
                      ),
                      Positioned(
                        bottom: 0, left: 0, right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          color: Colors.black54,
                          child: Text(
                            p.basename(_resultPaths[index]),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 9),
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
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

  Widget _buildCard({
    required String title,
    required IconData icon,
    required Widget child,
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
              Icon(icon, size: 16, color: AppTheme.accent),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              )),
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
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
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
          borderSide: const BorderSide(color: AppTheme.accent),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Widget _buildInfoRow() {
    final tw = int.tryParse(_widthController.text) ?? 256;
    final th = int.tryParse(_heightController.text) ?? 256;
    final cols = tw > 0 ? (_imageWidth! / tw).ceil() : 0;
    final rows = th > 0 ? (_imageHeight! / th).ceil() : 0;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.grid_on, size: 14, color: AppTheme.accent),
          const SizedBox(width: 8),
          Text(
            'Sẽ tạo $cols × $rows = ${cols * rows} mảnh',
            style: const TextStyle(
              color: AppTheme.accent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(String label, int w, int h) {
    final isSelected = _widthController.text == w.toString() &&
        _heightController.text == h.toString();
    return InkWell(
      onTap: () {
        setState(() {
          _widthController.text = w.toString();
          _heightController.text = h.toString();
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.accent.withValues(alpha: 0.2)
              : AppTheme.bgSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppTheme.accent : AppTheme.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppTheme.accent : AppTheme.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
