import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../services/image_processor.dart';
import '../theme/app_theme.dart';

class AutoSplitScreen extends StatefulWidget {
  const AutoSplitScreen({super.key});

  @override
  State<AutoSplitScreen> createState() => _AutoSplitScreenState();
}

class _AutoSplitScreenState extends State<AutoSplitScreen> {
  String? _selectedImagePath;
  String? _outputDir;
  int? _imageWidth;
  int? _imageHeight;
  bool _isProcessing = false;
  bool _isDetecting = false;
  double _progress = 0;
  List<String> _resultPaths = [];
  GridDetectionResult? _gridResult;
  int _sensitivity = 50;

  // Manual override values
  int _manualCols = 0;
  int _manualRows = 0;
  bool _useManualOverride = false;

  // File naming
  final _idController = TextEditingController();

  // Resize option
  bool _enableResize = false;
  final _resizeWidthController = TextEditingController(text: '32');
  final _resizeHeightController = TextEditingController(text: '32');

  // White background removal
  bool _removeWhiteBg = false;
  double _whiteTolerance = 20;

  @override
  void dispose() {
    _idController.dispose();
    _resizeWidthController.dispose();
    _resizeHeightController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Chọn ảnh sprite sheet để tách tự động',
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'bmp', 'gif', 'webp'],
    );
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      setState(() {
        _selectedImagePath = path;
        _outputDir = p.join(
            p.dirname(path), '${p.basenameWithoutExtension(path)}_auto_split');
        _resultPaths = [];
        _gridResult = null;
        _useManualOverride = false;
      });
      // Get image dimensions
      final size = await ImageProcessor.getImageSize(path);
      if (size != null) {
        setState(() {
          _imageWidth = size.width;
          _imageHeight = size.height;
        });
      }
      // Auto-detect grid
      _detectGrid();
    }
  }

  Future<void> _detectGrid() async {
    if (_selectedImagePath == null) return;
    setState(() {
      _isDetecting = true;
      _gridResult = null;
    });

    try {
      final result = await ImageProcessor.autoDetectGrid(
        inputPath: _selectedImagePath!,
        sensitivity: _sensitivity,
      );
      setState(() {
        _gridResult = result;
        _isDetecting = false;
        _manualCols = result.cols;
        _manualRows = result.rows;
      });
    } catch (e) {
      setState(() => _isDetecting = false);
      _showError('Lỗi phát hiện lưới: $e');
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

  Future<void> _startAutoSplit() async {
    if (_selectedImagePath == null || _outputDir == null) return;

    List<int> hLines;
    List<int> vLines;

    if (_useManualOverride && _imageWidth != null && _imageHeight != null) {
      // Generate grid lines from manual cols/rows
      vLines = [];
      hLines = [];
      for (int i = 1; i < _manualCols; i++) {
        vLines.add((_imageWidth! * i / _manualCols).round());
      }
      for (int i = 1; i < _manualRows; i++) {
        hLines.add((_imageHeight! * i / _manualRows).round());
      }
    } else if (_gridResult != null) {
      hLines = _gridResult!.horizontalLines;
      vLines = _gridResult!.verticalLines;
    } else {
      _showError('Chưa phát hiện được lưới. Vui lòng thử lại.');
      return;
    }

    setState(() {
      _isProcessing = true;
      _progress = 0;
      _resultPaths = [];
    });

    try {
      final paths = await ImageProcessor.autoSplitImage(
        inputPath: _selectedImagePath!,
        outputDir: _outputDir!,
        horizontalLines: hLines,
        verticalLines: vLines,
        namePrefix: _idController.text.trim().isNotEmpty
            ? _idController.text.trim()
            : null,
        removeWhiteBg: _removeWhiteBg,
        whiteTolerance: _whiteTolerance.round(),
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

      // Resize if enabled
      int resizedCount = 0;
      if (_enableResize && paths.isNotEmpty) {
        final rw = int.tryParse(_resizeWidthController.text) ?? 0;
        final rh = int.tryParse(_resizeHeightController.text) ?? 0;
        if (rw > 0 && rh > 0) {
          setState(() {
            _isProcessing = true;
            _progress = 0;
          });

          final resizeDir = '${_outputDir!}_resize';
          final resizeDirObj = Directory(resizeDir);
          if (!resizeDirObj.existsSync()) {
            resizeDirObj.createSync(recursive: true);
          }

          for (int i = 0; i < paths.length; i++) {
            setState(() {
              _progress = (i + 1) / paths.length;
            });

            final outputPath = p.join(resizeDir, p.basename(paths[i]));
            await ImageProcessor.resizeSingle(
              inputPath: paths[i],
              outputPath: outputPath,
              width: rw,
              height: rh,
            );
            resizedCount++;
          }

          setState(() => _isProcessing = false);
        }
      }

      if (mounted) {
        final msg = resizedCount > 0
            ? 'Đã tách ${paths.length} ảnh + resize $resizedCount ảnh!'
            : 'Đã tách thành ${paths.length} ảnh!';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: AppTheme.success),
                const SizedBox(width: 12),
                Text(msg,
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
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final settingsWidth =
            constraints.maxWidth > 800 ? 400.0 : constraints.maxWidth * 0.45;
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
            icon: Icons.image_search,
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
                        const Icon(Icons.insert_photo,
                            size: 16, color: AppTheme.warning),
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
                  label: Text(
                      _selectedImagePath == null ? 'Chọn ảnh' : 'Đổi ảnh'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.warning,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Detection settings
          _buildCard(
            title: 'Phát hiện lưới',
            icon: Icons.auto_awesome,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Sensitivity slider
                Row(
                  children: [
                    const Icon(Icons.tune, size: 14, color: AppTheme.textMuted),
                    const SizedBox(width: 8),
                    const Text('Độ nhạy',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                    const Spacer(),
                    Text('$_sensitivity%',
                        style: const TextStyle(
                            color: AppTheme.warning,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
                SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: AppTheme.warning,
                    inactiveTrackColor: AppTheme.bgSurface,
                    thumbColor: AppTheme.warning,
                    overlayColor: AppTheme.warning.withValues(alpha: 0.2),
                    trackHeight: 4,
                  ),
                  child: Slider(
                    value: _sensitivity.toDouble(),
                    min: 10,
                    max: 100,
                    divisions: 18,
                    onChanged: (v) {
                      setState(() => _sensitivity = v.round());
                    },
                    onChangeEnd: (_) {
                      if (_selectedImagePath != null) _detectGrid();
                    },
                  ),
                ),

                if (_isDetecting)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.warning,
                          ),
                        ),
                        SizedBox(width: 10),
                        Text('Đang phân tích...',
                            style: TextStyle(
                                color: AppTheme.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),

                if (_gridResult != null && !_isDetecting) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppTheme.success.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.check_circle,
                                size: 16, color: AppTheme.success),
                            const SizedBox(width: 8),
                            const Text('Đã phát hiện lưới',
                                style: TextStyle(
                                    color: AppTheme.success,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _buildDetectionInfo(),
                      ],
                    ),
                  ),
                ],

                // Manual override section
                if (_gridResult != null) ...[
                  const SizedBox(height: 14),
                  InkWell(
                    onTap: () {
                      setState(
                          () => _useManualOverride = !_useManualOverride);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _useManualOverride
                            ? AppTheme.warning.withValues(alpha: 0.1)
                            : AppTheme.bgSurface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _useManualOverride
                              ? AppTheme.warning.withValues(alpha: 0.3)
                              : AppTheme.border,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _useManualOverride
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                            size: 18,
                            color: _useManualOverride
                                ? AppTheme.warning
                                : AppTheme.textMuted,
                          ),
                          const SizedBox(width: 8),
                          const Text('Chỉnh tay số cột/hàng',
                              style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                  if (_useManualOverride) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildCounterField(
                            label: 'Số cột',
                            value: _manualCols,
                            onChanged: (v) =>
                                setState(() => _manualCols = v),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildCounterField(
                            label: 'Số hàng',
                            value: _manualRows,
                            onChanged: (v) =>
                                setState(() => _manualRows = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppTheme.warning.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.grid_on,
                              size: 14, color: AppTheme.warning),
                          const SizedBox(width: 8),
                          Text(
                            '$_manualCols × $_manualRows = ${_manualCols * _manualRows} mảnh',
                            style: const TextStyle(
                              color: AppTheme.warning,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
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
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11),
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
          const SizedBox(height: 16),

          // File naming
          _buildCard(
            title: 'Đặt tên file',
            icon: Icons.drive_file_rename_outline,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _idController,
                  style: const TextStyle(
                      color: AppTheme.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'ID (ví dụ: 2)',
                    labelStyle: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12),
                    hintText: 'Nhập ID...',
                    hintStyle: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 13),
                    prefixIcon: const Icon(Icons.tag,
                        size: 16, color: AppTheme.warning),
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
                      borderSide:
                          const BorderSide(color: AppTheme.warning),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.bgSurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 12, color: AppTheme.textMuted),
                          SizedBox(width: 6),
                          Text('Ví dụ tên file:',
                              style: TextStyle(
                                  color: AppTheme.textMuted, fontSize: 10)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _buildNamePreviewChip(_getPreviewName(1)),
                          _buildNamePreviewChip(_getPreviewName(2)),
                          _buildNamePreviewChip(_getPreviewName(3)),
                          const Text('...',
                              style: TextStyle(
                                  color: AppTheme.textMuted, fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Resize option
          _buildCard(
            title: 'Resize sau khi tách',
            icon: Icons.photo_size_select_small,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: () {
                    setState(() => _enableResize = !_enableResize);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _enableResize
                          ? AppTheme.accent.withValues(alpha: 0.1)
                          : AppTheme.bgSurface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _enableResize
                            ? AppTheme.accent.withValues(alpha: 0.3)
                            : AppTheme.border,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _enableResize
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          size: 18,
                          color: _enableResize
                              ? AppTheme.accent
                              : AppTheme.textMuted,
                        ),
                        const SizedBox(width: 8),
                        const Text('Tạo thêm bản resize',
                            style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 12)),
                      ],
                    ),
                  ),
                ),
                if (_enableResize) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _resizeWidthController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                              color: AppTheme.textPrimary, fontSize: 14),
                          decoration: InputDecoration(
                            labelText: 'Rộng (px)',
                            labelStyle: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11),
                            prefixIcon: const Icon(Icons.width_normal,
                                size: 14, color: AppTheme.accent),
                            filled: true,
                            fillColor: AppTheme.bgSurface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                                  const BorderSide(color: AppTheme.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                                  const BorderSide(color: AppTheme.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                                  const BorderSide(color: AppTheme.accent),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('×',
                            style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 18,
                                fontWeight: FontWeight.w300)),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _resizeHeightController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                              color: AppTheme.textPrimary, fontSize: 14),
                          decoration: InputDecoration(
                            labelText: 'Cao (px)',
                            labelStyle: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11),
                            prefixIcon: const Icon(Icons.height,
                                size: 14, color: AppTheme.accent),
                            filled: true,
                            fillColor: AppTheme.bgSurface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                                  const BorderSide(color: AppTheme.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                                  const BorderSide(color: AppTheme.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                                  const BorderSide(color: AppTheme.accent),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Quick presets
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _buildResizePreset('16×16', 16, 16),
                      _buildResizePreset('24×24', 24, 24),
                      _buildResizePreset('32×32', 32, 32),
                      _buildResizePreset('48×48', 48, 48),
                      _buildResizePreset('64×64', 64, 64),
                      _buildResizePreset('96×96', 96, 96),
                      _buildResizePreset('128×128', 128, 128),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppTheme.accent.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            size: 12, color: AppTheme.accent),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Ảnh gốc giữ nguyên, bản resize lưu vào thư mục "${p.basename(_outputDir ?? "")}_resize"',
                            style: const TextStyle(
                                color: AppTheme.accent, fontSize: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // White background removal card
          _buildCard(
            title: 'Khử nền trắng',
            icon: Icons.auto_fix_normal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: () {
                    setState(() => _removeWhiteBg = !_removeWhiteBg);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _removeWhiteBg
                          ? AppTheme.success.withValues(alpha: 0.1)
                          : AppTheme.bgSurface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _removeWhiteBg
                            ? AppTheme.success.withValues(alpha: 0.3)
                            : AppTheme.border,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _removeWhiteBg
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          size: 18,
                          color: _removeWhiteBg
                              ? AppTheme.success
                              : AppTheme.textMuted,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Khử nền trắng → trong suốt',
                                  style: TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 12)),
                              Text('Output sẽ lưu dưới dạng PNG',
                                  style: TextStyle(
                                      color: AppTheme.textMuted,
                                      fontSize: 10)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_removeWhiteBg) ...[
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Mức hiệu chỉnh (tolerance):',
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 11)),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.success.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color:
                                  AppTheme.success.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          '${_whiteTolerance.round()}',
                          style: const TextStyle(
                              color: AppTheme.success,
                              fontSize: 12,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _whiteTolerance,
                    min: 1,
                    max: 100,
                    divisions: 99,
                    activeColor: AppTheme.success,
                    inactiveColor: AppTheme.border,
                    onChanged: (v) => setState(() => _whiteTolerance = v),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Chặt (1)',
                          style: TextStyle(
                              color: AppTheme.textMuted, fontSize: 10)),
                      const Text('Chỉ trắng thuần',
                          style: TextStyle(
                              color: AppTheme.textMuted, fontSize: 10)),
                      const Text('Rộng (100)',
                          style: TextStyle(
                              color: AppTheme.textMuted, fontSize: 10)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppTheme.warning.withValues(alpha: 0.2)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.tips_and_updates,
                            size: 12, color: AppTheme.warning),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Low = chỉ xóa trắng thuần. High = xóa cả gần-trắng (có thể ảnh hưởng viền).',
                            style: TextStyle(
                                color: AppTheme.warning, fontSize: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Start button
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _selectedImagePath != null &&
                      !_isProcessing &&
                      (_gridResult != null || _useManualOverride)
                  ? _startAutoSplit
                  : null,
              icon: _isProcessing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_fix_high, size: 18),
              label:
                  Text(_isProcessing ? 'Đang tách...' : 'Tách tự động'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.warning,
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
                valueColor:
                    const AlwaysStoppedAnimation(AppTheme.warning),
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

  Widget _buildDetectionInfo() {
    final g = _gridResult!;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildInfoChip(
                  Icons.view_column, 'Cột', '${g.cols}'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildInfoChip(
                  Icons.table_rows, 'Hàng', '${g.rows}'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildInfoChip(
                  Icons.width_normal, 'Rộng', '${g.cellWidth}px'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildInfoChip(
                  Icons.height, 'Cao', '${g.cellHeight}px'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildInfoChip(
          Icons.grid_view,
          'Tổng mảnh',
          '${g.cols * g.rows}',
        ),
      ],
    );
  }

  Widget _buildInfoChip(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.textMuted),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textMuted, fontSize: 10)),
          const SizedBox(width: 4),
          Text(value,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  String _getPreviewName(int index) {
    final id = _idController.text.trim();
    final ext = _selectedImagePath != null
        ? p.extension(_selectedImagePath!).toLowerCase()
        : '.png';
    if (id.isNotEmpty) {
      return '$id\$$index$ext';
    } else {
      final baseName = _selectedImagePath != null
          ? p.basenameWithoutExtension(_selectedImagePath!)
          : 'image';
      return '${baseName}_0_${index - 1}$ext';
    }
  }

  Widget _buildResizePreset(String label, int w, int h) {
    final isSelected = _resizeWidthController.text == w.toString() &&
        _resizeHeightController.text == h.toString();
    return InkWell(
      onTap: () {
        setState(() {
          _resizeWidthController.text = w.toString();
          _resizeHeightController.text = h.toString();
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

  Widget _buildNamePreviewChip(String name) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.25)),
      ),
      child: Text(name,
          style: const TextStyle(
              color: AppTheme.warning,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace')),
    );
  }

  Widget _buildCounterField({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 10)),
                SizedBox(
                  height: 30, // constrain height to fit in row without layout breaking
                  child: TextFormField(
                    key: ValueKey('counter-$label-$value'),
                    initialValue: value.toString(),
                    keyboardType: TextInputType.number,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (val) {
                      final parsed = int.tryParse(val);
                      if (parsed != null && parsed >= 0) {
                        onChanged(parsed);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          Column(
            children: [
              InkWell(
                onTap: () => onChanged(value + 1),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  child: const Icon(Icons.add, size: 16,
                      color: AppTheme.textSecondary),
                ),
              ),
              InkWell(
                onTap: () {
                  if (value > 1) onChanged(value - 1);
                },
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  child: const Icon(Icons.remove, size: 16,
                      color: AppTheme.textSecondary),
                ),
              ),
            ],
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
      child: _selectedImagePath == null
          ? _buildEmptyPreview()
          : _resultPaths.isNotEmpty
              ? _buildResultsGrid()
              : _buildImagePreviewWithGrid(),
    );
  }

  Widget _buildEmptyPreview() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_awesome, size: 56,
              color: AppTheme.warning.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          const Text('Chọn ảnh sprite sheet để phân tích tự động',
              style:
                  TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
          const SizedBox(height: 8),
          const Text(
              'Thuật toán sẽ tự phát hiện các đường lưới\nvà tách thành từng ô vuông',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildImagePreviewWithGrid() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppTheme.border)),
          ),
          child: Row(
            children: [
              const Icon(Icons.preview, size: 18, color: AppTheme.warning),
              const SizedBox(width: 8),
              const Text('Xem trước lưới đã phát hiện',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  )),
              if (_gridResult != null) ...[
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_currentCols} × ${_currentRows} lưới',
                    style: const TextStyle(
                      color: AppTheme.warning,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return _buildGridOverlayPreview(constraints);
              },
            ),
          ),
        ),
      ],
    );
  }

  int get _currentCols =>
      _useManualOverride ? _manualCols : (_gridResult?.cols ?? 1);
  int get _currentRows =>
      _useManualOverride ? _manualRows : (_gridResult?.rows ?? 1);

  Widget _buildGridOverlayPreview(BoxConstraints constraints) {
    if (_selectedImagePath == null) return const SizedBox();

    return Stack(
      alignment: Alignment.center,
      children: [
        // Image
        Image.file(
          File(_selectedImagePath!),
          fit: BoxFit.contain,
          errorBuilder: (_, e, st) => const Center(
            child: Text('Không thể hiển thị ảnh',
                style: TextStyle(color: AppTheme.textMuted)),
          ),
        ),
        // Grid overlay
        if (_gridResult != null || _useManualOverride)
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, innerConstraints) {
                return CustomPaint(
                  painter: _GridPainter(
                    cols: _currentCols,
                    rows: _currentRows,
                    imageWidth: _imageWidth ?? 1,
                    imageHeight: _imageHeight ?? 1,
                    containerWidth: innerConstraints.maxWidth,
                    containerHeight: innerConstraints.maxHeight,
                  ),
                );
              },
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
              const Icon(Icons.check_circle,
                  size: 18, color: AppTheme.success),
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
                        bottom: 0,
                        left: 0,
                        right: 0,
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
              Icon(icon, size: 16, color: AppTheme.warning),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
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
}

/// Custom painter for drawing grid overlay on image preview
class _GridPainter extends CustomPainter {
  final int cols;
  final int rows;
  final int imageWidth;
  final int imageHeight;
  final double containerWidth;
  final double containerHeight;

  _GridPainter({
    required this.cols,
    required this.rows,
    required this.imageWidth,
    required this.imageHeight,
    required this.containerWidth,
    required this.containerHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Calculate how the image fits in the container (BoxFit.contain)
    final imageAspect = imageWidth / imageHeight;
    final containerAspect = containerWidth / containerHeight;

    double displayWidth, displayHeight;
    double offsetX, offsetY;

    if (imageAspect > containerAspect) {
      displayWidth = containerWidth;
      displayHeight = containerWidth / imageAspect;
      offsetX = 0;
      offsetY = (containerHeight - displayHeight) / 2;
    } else {
      displayHeight = containerHeight;
      displayWidth = containerHeight * imageAspect;
      offsetX = (containerWidth - displayWidth) / 2;
      offsetY = 0;
    }

    final paint = Paint()
      ..color = const Color(0xAAFF9500)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Draw vertical lines
    for (int i = 1; i < cols; i++) {
      final x = offsetX + (displayWidth * i / cols);
      canvas.drawLine(
        Offset(x, offsetY),
        Offset(x, offsetY + displayHeight),
        paint,
      );
    }

    // Draw horizontal lines
    for (int i = 1; i < rows; i++) {
      final y = offsetY + (displayHeight * i / rows);
      canvas.drawLine(
        Offset(offsetX, y),
        Offset(offsetX + displayWidth, y),
        paint,
      );
    }

    // Draw border
    final borderPaint = Paint()
      ..color = const Color(0x66FF9500)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    canvas.drawRect(
      Rect.fromLTWH(offsetX, offsetY, displayWidth, displayHeight),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) {
    return oldDelegate.cols != cols ||
        oldDelegate.rows != rows ||
        oldDelegate.containerWidth != containerWidth ||
        oldDelegate.containerHeight != containerHeight;
  }
}
