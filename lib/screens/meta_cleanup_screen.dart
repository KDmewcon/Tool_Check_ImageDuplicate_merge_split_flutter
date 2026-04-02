import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../services/meta_cleanup_service.dart';
import '../theme/app_theme.dart';

class MetaCleanupScreen extends StatefulWidget {
  const MetaCleanupScreen({super.key});

  @override
  State<MetaCleanupScreen> createState() => _MetaCleanupScreenState();
}

class _MetaCleanupScreenState extends State<MetaCleanupScreen> {
  String? _selectedDir;
  int? _lastDeletedCount;
  bool _isCleaning = false;

  Future<void> _pickAndCleanup() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Chọn thư mục để dọn file .meta',
    );
    if (result == null) return;

    setState(() {
      _selectedDir = result;
    });

    await _runCleanup();
  }

  Future<void> _runCleanup() async {
    if (_selectedDir == null || _isCleaning) return;

    setState(() {
      _isCleaning = true;
    });

    final deletedCount = await MetaCleanupService.deleteMetaFilesRecursively(
      _selectedDir!,
    );
    if (!mounted) return;

    setState(() {
      _isCleaning = false;
      _lastDeletedCount = deletedCount;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              deletedCount > 0 ? Icons.cleaning_services : Icons.info_outline,
              color: deletedCount > 0
                  ? AppTheme.warning
                  : AppTheme.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                deletedCount > 0
                    ? 'Đã xóa $deletedCount file .meta trong tất cả thư mục con'
                    : 'Không tìm thấy file .meta trong thư mục đã chọn',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            children: [
              _buildCard(
                title: 'Dọn file .meta',
                icon: Icons.cleaning_services,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Xóa toàn bộ file .meta trong thư mục đã chọn và tất cả thư mục con.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_selectedDir != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.bgSurface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.folder_open,
                              size: 16,
                              color: AppTheme.warning,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _selectedDir!,
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_selectedDir != null) const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isCleaning ? null : _pickAndCleanup,
                            icon: const Icon(Icons.folder_special, size: 16),
                            label: const Text('Chọn thư mục và dọn'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.warning,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _selectedDir != null && !_isCleaning
                                ? _runCleanup
                                : null,
                            icon: const Icon(Icons.cleaning_services, size: 16),
                            label: const Text('Dọn lại thư mục đã chọn'),
                          ),
                        ),
                      ],
                    ),
                    if (_lastDeletedCount != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.bgSurface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.analytics_outlined,
                              size: 16,
                              color: AppTheme.accent,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Lần dọn gần nhất: $_lastDeletedCount file .meta',
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
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
              _buildCard(
                title: 'Tự động khi chọn thư mục',
                icon: Icons.settings_suggest,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile.adaptive(
                      value: MetaCleanupService.autoCleanupOnFolderPick,
                      activeThumbColor: AppTheme.warning,
                      activeTrackColor: AppTheme.warning.withValues(
                        alpha: 0.35,
                      ),
                      title: const Text(
                        'Bật tự dọn .meta ở các màn khác',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: const Text(
                        'Khi bật, lúc bạn chọn thư mục ở các công cụ khác thì .meta sẽ được dọn tự động.',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      contentPadding: EdgeInsets.zero,
                      onChanged: (value) {
                        setState(() {
                          MetaCleanupService.autoCleanupOnFolderPick = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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
              Text(
                title,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (_selectedDir != null) ...[
                const Spacer(),
                Text(
                  p.basename(_selectedDir!),
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
