import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/split_screen.dart';
import 'screens/auto_split_screen.dart';
import 'screens/merge_screen.dart';
import 'screens/resize_screen.dart';
import 'screens/rename_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DuplicateCleanerApp());
}

class DuplicateCleanerApp extends StatelessWidget {
  const DuplicateCleanerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Image Toolkit',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  static const _navItems = [
    _NavItem(
      icon: Icons.find_replace,
      activeIcon: Icons.find_replace,
      label: 'Tìm trùng',
      color: AppTheme.danger,
    ),
    _NavItem(
      icon: Icons.content_cut_outlined,
      activeIcon: Icons.content_cut,
      label: 'Tách ảnh',
      color: AppTheme.accent,
    ),
    _NavItem(
      icon: Icons.auto_awesome_outlined,
      activeIcon: Icons.auto_awesome,
      label: 'Tách tự động',
      color: AppTheme.warning,
    ),
    _NavItem(
      icon: Icons.merge_outlined,
      activeIcon: Icons.merge,
      label: 'Gộp ảnh',
      color: AppTheme.primary,
    ),
    _NavItem(
      icon: Icons.photo_size_select_large_outlined,
      activeIcon: Icons.photo_size_select_large,
      label: 'Resize ảnh',
      color: AppTheme.primaryLight,
    ),
    _NavItem(
      icon: Icons.drive_file_rename_outline,
      activeIcon: Icons.drive_file_rename_outline,
      label: 'Rename file',
      color: AppTheme.accentLight,
    ),
  ];

  final _screens = const [
    HomeScreen(),
    SplitScreen(),
    AutoSplitScreen(),
    MergeScreen(),
    ResizeScreen(),
    RenameScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          _buildSidebar(),
          // Content
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: _screens,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 220,
      decoration: const BoxDecoration(
        color: AppTheme.bgCard,
        border: Border(
          right: BorderSide(color: AppTheme.border),
        ),
      ),
      child: Column(
        children: [
          // App logo
          Container(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.primary, AppTheme.accent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.auto_fix_high,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Image Toolkit',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        'Công cụ xử lý ảnh',
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: AppTheme.border, height: 1),
          const SizedBox(height: 12),
          // Nav items
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: _navItems.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                final isSelected = _selectedIndex == index;
                return _buildNavItem(item, isSelected, () {
                  setState(() => _selectedIndex = index);
                });
              }).toList(),
            ),
          ),
          const Spacer(),
          // Footer
          Container(
            padding: const EdgeInsets.all(16),
            child: const Text(
              'v1.0.0',
              style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
      _NavItem item, bool isSelected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? item.color.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: isSelected
                  ? Border.all(color: item.color.withValues(alpha: 0.25))
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  isSelected ? item.activeIcon : item.icon,
                  size: 20,
                  color: isSelected ? item.color : AppTheme.textSecondary,
                ),
                const SizedBox(width: 12),
                Text(
                  item.label,
                  style: TextStyle(
                    color:
                        isSelected ? item.color : AppTheme.textSecondary,
                    fontSize: 13,
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                if (isSelected) ...[
                  const Spacer(),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: item.color,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: item.color.withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final Color color;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.color,
  });
}
