import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../theme/app_theme.dart';

class RenameScreen extends StatefulWidget {
  const RenameScreen({super.key});

  @override
  State<RenameScreen> createState() => _RenameScreenState();
}

class _RenameScreenState extends State<RenameScreen> {
  String? _selectedDir;
  List<_FileEntry> _files = [];
  final _newPrefixController = TextEditingController();
  bool _isProcessing = false;
  List<_RenameResult>? _results;

  // Detected prefix
  String? _detectedPrefix;

  @override
  void dispose() {
    _newPrefixController.dispose();
    super.dispose();
  }

  Future<void> _pickDir() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Chọn thư mục chứa file cần rename',
    );
    if (result != null) {
      setState(() {
        _selectedDir = result;
        _results = null;
      });
      await _scanFiles();
    }
  }

  Future<void> _scanFiles() async {
    if (_selectedDir == null) return;
    final dir = Directory(_selectedDir!);
    final entries = <_FileEntry>[];

    await for (final entity in dir.list(recursive: false, followLinks: false)) {
      if (entity is File) {
        final name = p.basenameWithoutExtension(entity.path);
        final ext = p.extension(entity.path);

        // Parse pattern: {prefix}${number} or {prefix}$number
        final dollarIndex = name.indexOf('\$');
        if (dollarIndex > 0) {
          final prefix = name.substring(0, dollarIndex);
          final suffix = name.substring(dollarIndex); // includes $
          entries.add(_FileEntry(
            path: entity.path,
            prefix: prefix,
            suffix: suffix,
            ext: ext,
          ));
        } else {
          // Files without $ pattern - still show them
          entries.add(_FileEntry(
            path: entity.path,
            prefix: name,
            suffix: '',
            ext: ext,
          ));
        }
      }
    }

    // Sort by name
    entries.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

    // Auto-detect the most common prefix
    final prefixCounts = <String, int>{};
    for (final e in entries) {
      if (e.suffix.isNotEmpty) {
        prefixCounts[e.prefix] = (prefixCounts[e.prefix] ?? 0) + 1;
      }
    }

    String? mostCommonPrefix;
    int maxCount = 0;
    prefixCounts.forEach((prefix, count) {
      if (count > maxCount) {
        maxCount = count;
        mostCommonPrefix = prefix;
      }
    });

    setState(() {
      _files = entries;
      _detectedPrefix = mostCommonPrefix;
    });
  }

  List<_FileEntry> get _matchingFiles {
    if (_detectedPrefix == null) return [];
    return _files
        .where((f) => f.prefix == _detectedPrefix && f.suffix.isNotEmpty)
        .toList();
  }

  Future<void> _startRename() async {
    final newPrefix = _newPrefixController.text.trim();
    if (newPrefix.isEmpty) {
      _showError('Vui lòng nhập prefix mới');
      return;
    }
    if (_detectedPrefix == null) {
      _showError('Không tìm thấy file phù hợp');
      return;
    }

    final filesToRename = _matchingFiles;
    if (filesToRename.isEmpty) {
      _showError('Không có file nào để rename');
      return;
    }

    setState(() {
      _isProcessing = true;
      _results = null;
    });

    final results = <_RenameResult>[];
    for (final file in filesToRename) {
      final oldPath = file.path;
      final newName = '$newPrefix${file.suffix}${file.ext}';
      final newPath = p.join(p.dirname(oldPath), newName);

      try {
        // Check if destination already exists
        if (File(newPath).existsSync() && oldPath != newPath) {
          results.add(_RenameResult(
            oldName: p.basename(oldPath),
            newName: newName,
            success: false,
            error: 'File đã tồn tại',
          ));
          continue;
        }

        File(oldPath).renameSync(newPath);
        results.add(_RenameResult(
          oldName: p.basename(oldPath),
          newName: newName,
          success: true,
        ));
      } catch (e) {
        results.add(_RenameResult(
          oldName: p.basename(oldPath),
          newName: newName,
          success: false,
          error: e.toString(),
        ));
      }
    }

    setState(() {
      _isProcessing = false;
      _results = results;
    });

    // Rescan files
    await _scanFiles();

    if (mounted) {
      final successCount = results.where((r) => r.success).length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: AppTheme.success),
              const SizedBox(width: 12),
              Text('Đã rename $successCount/${results.length} file!',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
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
            constraints.maxWidth > 800 ? 380.0 : constraints.maxWidth * 0.45;
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: settingsWidth,
                child: _buildSettingsPanel(),
              ),
              const SizedBox(width: 24),
              Expanded(child: _buildPreviewPanel()),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSettingsPanel() {
    final matching = _matchingFiles;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Folder selector
          _buildCard(
            title: 'Thư mục',
            icon: Icons.folder_special,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_selectedDir != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.bgSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.folder,
                            size: 16, color: AppTheme.accentLight),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.basename(_selectedDir!),
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${_files.length} file tổng cộng',
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
                  onPressed: _isProcessing ? null : _pickDir,
                  icon: const Icon(Icons.folder_open, size: 16),
                  label: Text(_selectedDir == null
                      ? 'Chọn thư mục'
                      : 'Đổi thư mục'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentLight,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Detected prefix
          if (_detectedPrefix != null) ...[
            _buildCard(
              title: 'Prefix hiện tại',
              icon: Icons.label,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Current prefix display
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.danger.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppTheme.danger.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.danger,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _detectedPrefix!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${matching.length} file khớp',
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'VD: $_detectedPrefix\$1, $_detectedPrefix\$2...',
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Other prefixes if any
                  if (_files.where((f) => f.suffix.isNotEmpty).map((f) => f.prefix).toSet().length > 1) ...[
                    const SizedBox(height: 10),
                    const Text('Chọn prefix khác:',
                        style: TextStyle(
                            color: AppTheme.textMuted, fontSize: 10)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _files
                          .where((f) => f.suffix.isNotEmpty)
                          .map((f) => f.prefix)
                          .toSet()
                          .map((prefix) => _buildPrefixChip(prefix))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // New prefix input
          if (_detectedPrefix != null)
            _buildCard(
              title: 'Rename thành',
              icon: Icons.drive_file_rename_outline,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _newPrefixController,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                    ),
                    decoration: InputDecoration(
                      labelText: 'Prefix mới',
                      labelStyle: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12),
                      hintText: 'VD: 5',
                      hintStyle: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 16),
                      prefixIcon: const Icon(Icons.edit,
                          size: 16, color: AppTheme.success),
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
                        borderSide: const BorderSide(color: AppTheme.success),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (_newPrefixController.text.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppTheme.success.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.preview,
                                  size: 12, color: AppTheme.success),
                              SizedBox(width: 6),
                              Text('Xem trước:',
                                  style: TextStyle(
                                      color: AppTheme.success,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ...matching.take(4).map((f) {
                            final newName =
                                '${_newPrefixController.text.trim()}${f.suffix}${f.ext}';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      p.basename(f.path),
                                      style: const TextStyle(
                                        color: AppTheme.danger,
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                        decoration: TextDecoration.lineThrough,
                                        decorationColor: AppTheme.danger,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const Padding(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 8),
                                    child: Icon(Icons.arrow_forward,
                                        size: 12,
                                        color: AppTheme.textMuted),
                                  ),
                                  Expanded(
                                    child: Text(
                                      newName,
                                      style: const TextStyle(
                                        color: AppTheme.success,
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          if (matching.length > 4)
                            Text(
                              '... và ${matching.length - 4} file nữa',
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

          // Start button
          if (_detectedPrefix != null)
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: !_isProcessing &&
                        _newPrefixController.text.trim().isNotEmpty &&
                        matching.isNotEmpty
                    ? _startRename
                    : null,
                icon: _isProcessing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.drive_file_rename_outline, size: 18),
                label: Text(_isProcessing
                    ? 'Đang rename...'
                    : 'Rename ${matching.length} file'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.success,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPrefixChip(String prefix) {
    final isSelected = _detectedPrefix == prefix;
    final count =
        _files.where((f) => f.prefix == prefix && f.suffix.isNotEmpty).length;
    return InkWell(
      onTap: () {
        setState(() => _detectedPrefix = prefix);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.danger.withValues(alpha: 0.2)
              : AppTheme.bgSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppTheme.danger : AppTheme.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              prefix,
              style: TextStyle(
                color: isSelected ? AppTheme.danger : AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '($count)',
              style: TextStyle(
                color: isSelected
                    ? AppTheme.danger.withValues(alpha: 0.7)
                    : AppTheme.textMuted,
                fontSize: 10,
              ),
            ),
          ],
        ),
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
      child: _selectedDir == null
          ? _buildEmptyPreview()
          : _results != null
              ? _buildResultsView()
              : _buildFileListView(),
    );
  }

  Widget _buildEmptyPreview() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.drive_file_rename_outline,
              size: 56, color: AppTheme.success.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          const Text('Chọn thư mục chứa file cần rename',
              style:
                  TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
          const SizedBox(height: 8),
          const Text(
              'Hỗ trợ đổi prefix của file theo mẫu\nVD: 8\$1.png → 5\$1.png',
              style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                  fontFamily: 'monospace'),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildFileListView() {
    final matching = _matchingFiles;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppTheme.border)),
          ),
          child: Row(
            children: [
              const Icon(Icons.list, size: 18, color: AppTheme.accentLight),
              const SizedBox(width: 8),
              Text(
                  '${_files.length} file — ${matching.length} file khớp pattern',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  )),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _files.length,
            itemBuilder: (context, index) {
              final file = _files[index];
              final isMatching = file.prefix == _detectedPrefix &&
                  file.suffix.isNotEmpty;
              return Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isMatching
                      ? AppTheme.danger.withValues(alpha: 0.06)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: isMatching
                      ? Border.all(
                          color: AppTheme.danger.withValues(alpha: 0.15))
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      isMatching ? Icons.check_circle : Icons.circle_outlined,
                      size: 14,
                      color: isMatching
                          ? AppTheme.danger
                          : AppTheme.textMuted,
                    ),
                    const SizedBox(width: 10),
                    if (isMatching) ...[
                      // Highlight prefix
                      Text(
                        file.prefix,
                        style: const TextStyle(
                          color: AppTheme.danger,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'monospace',
                        ),
                      ),
                      Text(
                        '${file.suffix}${file.ext}',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ] else
                      Text(
                        p.basename(file.path),
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                          fontFamily: 'monospace',
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

  Widget _buildResultsView() {
    final successCount = _results!.where((r) => r.success).length;
    final failCount = _results!.where((r) => !r.success).length;
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
              Text(
                  'Kết quả: $successCount thành côngrename${failCount > 0 ? ', $failCount lỗi' : ''}',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  )),
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
            padding: const EdgeInsets.all(12),
            itemCount: _results!.length,
            itemBuilder: (context, index) {
              final result = _results![index];
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: result.success
                      ? AppTheme.success.withValues(alpha: 0.06)
                      : AppTheme.danger.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: result.success
                        ? AppTheme.success.withValues(alpha: 0.2)
                        : AppTheme.danger.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      result.success ? Icons.check_circle : Icons.error,
                      size: 14,
                      color: result.success
                          ? AppTheme.success
                          : AppTheme.danger,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                result.oldName,
                                style: TextStyle(
                                  color: result.success
                                      ? AppTheme.textMuted
                                      : AppTheme.danger,
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  decoration: result.success
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                              const Padding(
                                padding:
                                    EdgeInsets.symmetric(horizontal: 6),
                                child: Icon(Icons.arrow_forward,
                                    size: 10,
                                    color: AppTheme.textMuted),
                              ),
                              Text(
                                result.newName,
                                style: TextStyle(
                                  color: result.success
                                      ? AppTheme.success
                                      : AppTheme.textMuted,
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          if (result.error != null)
                            Text(
                              result.error!,
                              style: const TextStyle(
                                  color: AppTheme.danger, fontSize: 10),
                            ),
                        ],
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
              Icon(icon, size: 16, color: AppTheme.success),
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

class _FileEntry {
  final String path;
  final String prefix;
  final String suffix; // e.g. "$1", "$2"
  final String ext;

  _FileEntry({
    required this.path,
    required this.prefix,
    required this.suffix,
    required this.ext,
  });
}

class _RenameResult {
  final String oldName;
  final String newName;
  final bool success;
  final String? error;

  _RenameResult({
    required this.oldName,
    required this.newName,
    required this.success,
    this.error,
  });
}
