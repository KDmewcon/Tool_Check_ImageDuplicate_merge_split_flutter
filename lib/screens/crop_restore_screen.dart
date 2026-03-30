import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
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
  String? _selectedDir;
  List<String> _imageFiles = [];
  String? _previewImagePath;
  String? _outputDir;
  double _progress = 0;
  Uint8List? _previewBytes;    // original image bytes for display
  Uint8List? _resultBytes;     // result image bytes for display
  int _origW = 0;
  int _origH = 0;

  int _cropTop = 1;
  int _cropBottom = 1;
  int _cropLeft = 1;
  int _cropRight = 1;
  bool _linkSides = true;

  bool _isProcessing = false;
  bool _isDragging = false;

  Future<void> _pickDirectory() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Chọn thư mục chứa ảnh cần crop',
    );
    if (result != null) {
      _loadDirectory(result);
    }
  }

  void _loadDirectory(String dirPath) {
    setState(() {
      _selectedDir = dirPath;
      _outputDir = '${dirPath}_crop';
      _imageFiles = [];
      _previewImagePath = null;
      _previewBytes = null;
      _resultBytes = null;
      _origW = 0;
      _origH = 0;
    });
    
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return;
    
    final validExts = {'.png', '.jpg', '.jpeg', '.bmp', '.gif', '.webp'};
    final files = dir.listSync().whereType<File>().where((f) => 
        validExts.contains(p.extension(f.path).toLowerCase())
    ).map((f) => f.path).toList();
    
    setState(() {
      _imageFiles = files;
    });
    
    if (files.isNotEmpty) {
      _loadImage(files.first);
    } else {
      _showMsg('Không tìm thấy ảnh nào trong thư mục!', isError: true);
    }
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      // Clipboard text paste — try as file path
      if (data?.text != null) {
        final path = data!.text!.trim().replaceAll('"', '');
        if (File(path).existsSync()) {
          await _loadImage(path);
          return;
        }
      }
      _showMsg('Không tìm thấy ảnh trong clipboard.\nThử kéo thả hoặc dùng nút chọn file.', isError: true);
    } catch (e) {
      _showMsg('Lỗi: $e', isError: true);
    }
  }

  Future<void> _loadImage(String path) async {
    setState(() {
      _previewImagePath = path;
      _resultBytes = null;
    });
    try {
      final bytes = File(path).readAsBytesSync();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw Exception('Không đọc được ảnh');
      setState(() {
        _previewBytes = bytes;
        _origW = decoded.width;
        _origH = decoded.height;
      });
    } catch (e) {
      _showMsg('Lỗi đọc ảnh: $e', isError: true);
    }
  }

  Future<void> _processAll() async {
    if (_imageFiles.isEmpty || _origW == 0 || _outputDir == null) return;
    final cropW = _origW - _cropLeft - _cropRight;
    final cropH = _origH - _cropTop - _cropBottom;
    if (cropW <= 0 || cropH <= 0) {
      _showMsg('Crop quá lớn! Ảnh ${_origW}×${_origH} không đủ.', isError: true);
      return;
    }

    final outDir = Directory(_outputDir!);
    if (!outDir.existsSync()) outDir.createSync(recursive: true);

    setState(() {
      _isProcessing = true;
      _progress = 0;
      _resultBytes = null;
    });

    try {
      int success = 0;
      for (int i = 0; i < _imageFiles.length; i++) {
        setState(() => _progress = (i + 1) / _imageFiles.length);
        final input = _imageFiles[i];
        final ext = p.extension(input).toLowerCase();
        final baseName = p.basenameWithoutExtension(input);
        final output = p.join(_outputDir!, '$baseName$ext');

        await ImageProcessor.cropAndRestore(
          inputPath: input,
          outputPath: output,
          cropTop: _cropTop,
          cropBottom: _cropBottom,
          cropLeft: _cropLeft,
          cropRight: _cropRight,
        );
        success++;
      }

      setState(() {
        _isProcessing = false;
        if (_previewImagePath != null) {
             final ext = p.extension(_previewImagePath!).toLowerCase();
             final baseName = p.basenameWithoutExtension(_previewImagePath!);
             final out = p.join(_outputDir!, '$baseName$ext');
             if (File(out).existsSync()) {
                 _resultBytes = File(out).readAsBytesSync();
             }
        }
      });
      _showMsg('Đã xử lý xong $success ảnh! Đã lưu vào ${_outputDir!}');
    } catch (e) {
      setState(() => _isProcessing = false);
      _showMsg('Lỗi: $e', isError: true);
    }
  }

  void _showMsg(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(isError ? Icons.error : Icons.check_circle,
            color: isError ? AppTheme.danger : AppTheme.success),
        const SizedBox(width: 12),
        Expanded(child: Text(msg, style: const TextStyle(fontWeight: FontWeight.w500))),
      ]),
    ));
  }

  void _setCropAll(int v) => setState(() {
        _cropTop = v;
        _cropBottom = v;
        _cropLeft = v;
        _cropRight = v;
      });

  int get _afterW => _origW - _cropLeft - _cropRight;
  int get _afterH => _origH - _cropTop - _cropBottom;
  bool get _cropValid => _origW == 0 || (_afterW > 0 && _afterH > 0);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left panel: controls
          SizedBox(width: 300, child: _buildControls()),
          const SizedBox(width: 24),
          // Right panel: image preview
          Expanded(child: _buildPreviewArea()),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Pick image
          _card(
            title: 'Chon thư mục (hàng loạt)',
            icon: Icons.folder_special,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton.icon(
                  onPressed: _pickDirectory,
                  icon: const Icon(Icons.folder_open, size: 16),
                  label: const Text('Chọn thư mục'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _pasteFromClipboard,
                  icon: const Icon(Icons.content_paste, size: 16),
                  label: const Text('Paste đường dẫn'),
                ),
                if (_selectedDir != null || _imageFiles.isNotEmpty) ...[
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
                        Text(
                          _selectedDir != null ? p.basename(_selectedDir!) : p.basename(_previewImagePath ?? ''),
                          style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'monospace'),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_imageFiles.isNotEmpty)
                          Text(
                            '${_imageFiles.length} ảnh đã chọn',
                            style: const TextStyle(
                                color: AppTheme.textMuted, fontSize: 11),
                          ),
                        if (_origW > 0)
                          Text(
                            '${_origW} × ${_origH} px',
                            style: const TextStyle(
                                color: AppTheme.textMuted, fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                ],
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
                  label: _linkSides ? '4 cạnh bằng nhau' : 'Riêng từng cạnh',
                  active: _linkSides,
                  color: AppTheme.primary,
                  onTap: () => setState(() => _linkSides = !_linkSides),
                ),
                const SizedBox(height: 12),
                if (_linkSides) ...[
                  _cropRow('Tất cả', _cropTop, _setCropAll),
                ] else ...[
                  _cropRow('Trên ↑', _cropTop, (v) => setState(() => _cropTop = v)),
                  const SizedBox(height: 6),
                  _cropRow('Dưới ↓', _cropBottom, (v) => setState(() => _cropBottom = v)),
                  const SizedBox(height: 6),
                  _cropRow('Trái ←', _cropLeft, (v) => setState(() => _cropLeft = v)),
                  const SizedBox(height: 6),
                  _cropRow('Phải →', _cropRight, (v) => setState(() => _cropRight = v)),
                ],
                const SizedBox(height: 10),
                // Quick presets
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [1, 2, 3, 4, 8]
                      .map((n) => _presetChip('${n}px', n))
                      .toList(),
                ),
                // Preview calc
                if (_origW > 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _cropValid
                          ? AppTheme.primary.withValues(alpha: 0.08)
                          : AppTheme.danger.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: _cropValid
                              ? AppTheme.primary.withValues(alpha: 0.2)
                              : AppTheme.danger.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _cropValid
                              ? '${_origW}×${_origH}  ➜  $_afterW×$_afterH  ➜  ${_origW}×${_origH}'
                              : '❌ Crop quá lớn!',
                          style: TextStyle(
                            color: _cropValid
                                ? AppTheme.primary
                                : AppTheme.danger,
                            fontSize: 11,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (_cropValid && _origW > 0)
                          Text(
                            'cắt  →  zoom nearest-neighbor  →  giữ nguyên ${_origW}×${_origH}',
                            style: const TextStyle(
                                color: AppTheme.textMuted, fontSize: 10),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Process button
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _imageFiles.isNotEmpty && !_isProcessing && _cropValid
                  ? _processAll
                  : null,
              icon: _isProcessing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.crop_rotate, size: 18),
              label: Text(_isProcessing ? 'Đang xử lý ${(_progress * 100).toStringAsFixed(0)}%' : 'Crop & Restore (${_imageFiles.length})'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                textStyle: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewArea() {
    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (detail) {
        setState(() => _isDragging = false);
        final validExts = {'.png', '.jpg', '.jpeg', '.bmp', '.gif', '.webp'};
        List<String> validFiles = [];
        
        for (final xfile in detail.files) {
          if (Directory(xfile.path).existsSync()) {
            _loadDirectory(xfile.path);
            return; // Load entire directory if dropped
          } else if (validExts.contains(p.extension(xfile.path).toLowerCase())) {
            validFiles.add(xfile.path);
          }
        }
        
        if (validFiles.isNotEmpty) {
          setState(() {
            _selectedDir = p.dirname(validFiles.first);
            _outputDir = '${_selectedDir}_crop';
            _imageFiles = validFiles;
          });
          _loadImage(validFiles.first);
        } else {
          _showMsg('Vui lòng kéo ảnh hợp lệ hoặc một thư mục (PNG, JPG...)', isError: true);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isDragging
                ? AppTheme.primary
                : (_imageFiles.isEmpty
                    ? AppTheme.primary.withValues(alpha: 0.3)
                    : AppTheme.border),
            width: _isDragging ? 2.5 : 1.5,
          ),
          boxShadow: _isDragging
              ? [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.25),
                    blurRadius: 24,
                    spreadRadius: 2,
                  )
                ]
              : null,
        ),
        child: _imageFiles.isEmpty
            ? _buildEmpty()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header with size info
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: const BoxDecoration(
                      border:
                          Border(bottom: BorderSide(color: AppTheme.border)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.compare, size: 16, color: AppTheme.primary),
                      const SizedBox(width: 8),
                      const Text('So sánh trước / sau',
                          style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      const Spacer(),
                      if (_origW > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color:
                                    AppTheme.primary.withValues(alpha: 0.2)),
                          ),
                          child: Text('$_origW × $_origH px',
                              style: const TextStyle(
                                  color: AppTheme.primary,
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w600)),
                        ),
                    ]),
                  ),
                  Expanded(
                    child: _resultBytes == null
                        ? _buildSinglePreview()
                        : _buildBeforeAfter(),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            child: Icon(
              _isDragging ? Icons.download : Icons.crop_rotate,
              size: 64,
              color: _isDragging
                  ? AppTheme.primary
                  : AppTheme.primary.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _isDragging ? 'Thả ảnh vào đây!' : 'Kéo thả ảnh vào đây',
            style: TextStyle(
              color: _isDragging ? AppTheme.primary : AppTheme.textSecondary,
              fontSize: 18,
              fontWeight: _isDragging ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'hoặc dùng nút chọn file bên trái\n(PNG, JPG, BMP, GIF...)',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _pickDirectory,
            icon: const Icon(Icons.add_photo_alternate, size: 18),
            label: const Text('Chọn thư mục'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSinglePreview() {
    if (_previewBytes == null) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Text('GỐC',
              style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5)),
          const SizedBox(height: 8),
          Expanded(
            child: _imageBox(_previewBytes!, Colors.transparent),
          ),
        ],
      ),
    );
  }

  Widget _buildBeforeAfter() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Before
          Expanded(
            child: Column(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: AppTheme.danger.withValues(alpha: 0.2)),
                ),
                child: const Text('TRƯỚC',
                    style: TextStyle(
                        color: AppTheme.danger,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5)),
              ),
              const SizedBox(height: 8),
              Expanded(
                  child: _imageBox(_previewBytes!,
                      AppTheme.danger.withValues(alpha: 0.15))),
            ]),
          ),

          // Arrow
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.arrow_forward,
                    color: AppTheme.primary, size: 24),
                const SizedBox(height: 4),
                Text(
                  '-${_cropLeft + _cropRight}W\n-${_cropTop + _cropBottom}H\n→zoom',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 9,
                      fontFamily: 'monospace'),
                ),
              ],
            ),
          ),

          // After
          Expanded(
            child: Column(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: AppTheme.success.withValues(alpha: 0.2)),
                ),
                child: const Text('SAU',
                    style: TextStyle(
                        color: AppTheme.success,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5)),
              ),
              const SizedBox(height: 8),
              Expanded(
                  child: _imageBox(_resultBytes!,
                      AppTheme.success.withValues(alpha: 0.15))),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _imageBox(Uint8List imageBytes, Color borderColor) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: borderColor == Colors.transparent
                ? AppTheme.border
                : borderColor,
            width: 2),
        // Checkerboard hint via color
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          imageBytes,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.none, // pixel perfect display
        ),
      ),
    );
  }

  // ── Utils ──────────────────────────────────────────────────────────────────

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
          Icon(icon, size: 15, color: active ? color : AppTheme.textMuted),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  color: active ? color : AppTheme.textSecondary,
                  fontSize: 12)),
        ]),
      ),
    );
  }

  Widget _cropRow(String label, int value, void Function(int) onChanged) {
    return Row(children: [
      SizedBox(
          width: 56,
          child: Text(label,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 11))),
      const SizedBox(width: 6),
      _stepBtn(Icons.remove, value > 0 ? () => onChanged(value - 1) : null),
      const SizedBox(width: 6),
      Container(
        width: 52,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: AppTheme.bgSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.border)),
        child: Text('$value px',
            style: const TextStyle(
                color: AppTheme.warning,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace')),
      ),
      const SizedBox(width: 6),
      _stepBtn(Icons.add, value < 64 ? () => onChanged(value + 1) : null),
    ]);
  }

  Widget _stepBtn(IconData icon, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
            color: onTap != null
                ? AppTheme.primary.withValues(alpha: 0.12)
                : AppTheme.bgSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.border)),
        child: Icon(icon,
            size: 14,
            color: onTap != null ? AppTheme.primary : AppTheme.textMuted),
      ),
    );
  }

  Widget _presetChip(String label, int value) {
    final sel = _linkSides && _cropTop == value;
    return InkWell(
      onTap: () => _setCropAll(value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
            color: sel
                ? AppTheme.primary.withValues(alpha: 0.2)
                : AppTheme.bgSurface,
            borderRadius: BorderRadius.circular(8),
            border:
                Border.all(color: sel ? AppTheme.primary : AppTheme.border)),
        child: Text(label,
            style: TextStyle(
                color: sel ? AppTheme.primary : AppTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      ),
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
