import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/duplicate_group.dart';
import '../services/image_scanner.dart';
import '../services/meta_cleanup_service.dart';
import '../theme/app_theme.dart';
import '../widgets/duplicate_group_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  String? _selectedPath;
  bool _isScanning = false;
  List<DuplicateGroup> _duplicateGroups = [];
  ScanProgress? _currentProgress;
  final ImageScanner _scanner = ImageScanner();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(
      begin: 0.4,
      end: 1.0,
    ).animate(_pulseController);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _pickDirectory() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Chọn thư mục chứa ảnh',
    );
    if (result == null) return;

    final deletedMetaFiles =
        await MetaCleanupService.cleanupMetaFilesOnFolderPick(result);
    if (!mounted) return;

    setState(() {
      _selectedPath = result;
      _duplicateGroups = [];
      _currentProgress = null;
    });

    if (deletedMetaFiles != null) {
      final cleaned = deletedMetaFiles > 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                cleaned ? Icons.cleaning_services : Icons.info_outline,
                color: cleaned ? AppTheme.warning : AppTheme.textSecondary,
              ),
              const SizedBox(width: 12),
              Text(
                cleaned
                    ? 'Đã xóa $deletedMetaFiles file .meta trong thư mục đã chọn'
                    : 'Không có file .meta trong thư mục đã chọn',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _startScan() async {
    if (_selectedPath == null) return;

    setState(() {
      _isScanning = true;
      _duplicateGroups = [];
      _currentProgress = null;
    });

    final groups = await _scanner.findDuplicates(_selectedPath!, (progress) {
      setState(() {
        _currentProgress = progress;
      });
    });

    setState(() {
      _duplicateGroups = groups;
      _isScanning = false;
    });
  }

  void _cancelScan() {
    _scanner.cancel();
    setState(() {
      _isScanning = false;
    });
  }

  void _autoSelectAll() {
    for (final group in _duplicateGroups) {
      group.autoSelectDuplicates();
    }
    setState(() {});
  }

  void _deselectAll() {
    for (final group in _duplicateGroups) {
      group.deselectAll();
    }
    setState(() {});
  }

  int get _totalSelected {
    int count = 0;
    for (final group in _duplicateGroups) {
      count += group.selectedCount;
    }
    return count;
  }

  int get _totalSavings {
    int savings = 0;
    for (final group in _duplicateGroups) {
      savings += group.potentialSavings;
    }
    return savings;
  }

  Future<void> _deleteSelected() async {
    final count = _totalSelected;
    if (count == 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppTheme.border),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.danger, size: 28),
            SizedBox(width: 12),
            Text(
              'Xác nhận xóa',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bạn có chắc chắn muốn xóa $count ảnh đã chọn?',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.danger.withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: AppTheme.danger, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Thao tác này không thể hoàn tác. Các ảnh sẽ bị xóa vĩnh viễn.',
                      style: TextStyle(
                        color: AppTheme.danger,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.delete, size: 16),
                const SizedBox(width: 6),
                Text('Xóa $count ảnh'),
              ],
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final deleted = await ImageScanner.deleteSelectedImages(_duplicateGroups);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: AppTheme.success),
                const SizedBox(width: 12),
                Text(
                  'Đã xóa thành công $deleted ảnh!',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        );
        // Re-scan
        _startScan();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildAppBar(),
          Expanded(
            child: _isScanning
                ? _buildScanningView()
                : _duplicateGroups.isEmpty
                ? _buildEmptyView()
                : _buildResultsView(),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      decoration: const BoxDecoration(
        color: AppTheme.bgDark,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          // Logo
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primary, AppTheme.accent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.find_replace,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Duplicate Cleaner',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              Text(
                'Tìm và xóa ảnh trùng lặp',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
            ],
          ),
          const Spacer(),
          // Directory selector
          if (_selectedPath != null) ...[
            Container(
              constraints: const BoxConstraints(maxWidth: 350),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.bgSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.folder_open,
                    size: 16,
                    color: AppTheme.warning,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _selectedPath!,
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
            const SizedBox(width: 12),
          ],
          OutlinedButton.icon(
            onPressed: _isScanning ? null : _pickDirectory,
            icon: const Icon(Icons.folder_outlined, size: 16),
            label: Text(_selectedPath == null ? 'Chọn thư mục' : 'Đổi'),
          ),
          if (_selectedPath != null) ...[
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _isScanning ? _cancelScan : _startScan,
              icon: Icon(_isScanning ? Icons.stop : Icons.search, size: 16),
              label: Text(_isScanning ? 'Dừng' : 'Quét ảnh'),
              style: _isScanning
                  ? ElevatedButton.styleFrom(backgroundColor: AppTheme.danger)
                  : null,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScanningView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated scanning icon
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppTheme.primary.withValues(
                        alpha: _pulseAnimation.value * 0.3,
                      ),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.radar,
                  size: 48,
                  color: AppTheme.primary,
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          const Text(
            'Đang quét ảnh...',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 24),
          if (_currentProgress != null) ...[
            SizedBox(
              width: 400,
              child: Column(
                children: [
                  // Progress bar
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: AppTheme.bgSurface,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _currentProgress!.progress,
                        backgroundColor: Colors.transparent,
                        valueColor: const AlwaysStoppedAnimation(
                          AppTheme.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_currentProgress!.scannedFiles} / ${_currentProgress!.totalFiles} ảnh',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '${(_currentProgress!.progress * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          color: AppTheme.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_currentProgress!.currentFile.isNotEmpty)
                    Text(
                      _currentProgress!.currentFile,
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.bgCard,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.content_copy,
                          size: 16,
                          color: AppTheme.danger,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Tìm thấy ${_currentProgress!.duplicateGroupsFound} nhóm trùng',
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
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  AppTheme.primary.withValues(alpha: 0.2),
                  AppTheme.accent.withValues(alpha: 0.1),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Icon(
              _selectedPath == null
                  ? Icons.folder_outlined
                  : Icons.image_search,
              size: 52,
              color: AppTheme.primary.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            _selectedPath == null
                ? 'Chọn thư mục để bắt đầu'
                : _currentProgress != null
                ? 'Không tìm thấy ảnh trùng lặp! 🎉'
                : 'Nhấn "Quét ảnh" để tìm ảnh trùng',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _selectedPath == null
                ? 'Ứng dụng sẽ quét toàn bộ ảnh trong thư mục và tìm các ảnh giống nhau'
                : _currentProgress != null
                ? 'Tất cả ảnh trong thư mục đều là duy nhất'
                : 'Quá trình quét có thể mất vài phút tùy số lượng ảnh',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
          if (_selectedPath == null) ...[
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _pickDirectory,
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text('Chọn thư mục'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResultsView() {
    return Column(
      children: [
        // Stats bar
        _buildStatsBar(),
        // Duplicate groups list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: _duplicateGroups.length,
            itemBuilder: (context, index) {
              return DuplicateGroupCard(
                group: _duplicateGroups[index],
                groupIndex: index,
                onChanged: () => setState(() {}),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatsBar() {
    final totalDuplicates = _duplicateGroups.fold(
      0,
      (sum, g) => sum + g.images.length - 1,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: AppTheme.bgCard,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          _buildStatChip(
            Icons.group_work,
            '${_duplicateGroups.length}',
            'Nhóm trùng',
            AppTheme.primary,
          ),
          const SizedBox(width: 16),
          _buildStatChip(
            Icons.photo_library,
            '$totalDuplicates',
            'Ảnh trùng',
            AppTheme.danger,
          ),
          const SizedBox(width: 16),
          _buildStatChip(
            Icons.check_circle_outline,
            '$_totalSelected',
            'Đã chọn xóa',
            AppTheme.warning,
          ),
          const SizedBox(width: 16),
          _buildStatChip(
            Icons.savings,
            _formatSize(_totalSavings),
            'Tiết kiệm',
            AppTheme.success,
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: _autoSelectAll,
            icon: const Icon(Icons.auto_fix_high, size: 16),
            label: const Text('Chọn tất cả bản trùng'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _deselectAll,
            icon: const Icon(Icons.deselect, size: 16),
            label: const Text('Bỏ chọn'),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _totalSelected > 0 ? _deleteSelected : null,
            icon: const Icon(Icons.delete_sweep, size: 16),
            label: Text('Xóa $_totalSelected ảnh'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _totalSelected > 0
                  ? AppTheme.danger
                  : AppTheme.bgSurface,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(
    IconData icon,
    String value,
    String label,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
              ),
            ],
          ),
        ],
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
