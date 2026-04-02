import 'dart:io';

class MetaCleanupService {
  const MetaCleanupService._();

  /// Global toggle for auto cleanup when users pick a folder.
  static bool autoCleanupOnFolderPick = true;

  /// Cleans .meta files only when [autoCleanupOnFolderPick] is enabled.
  /// Returns `null` when auto-cleanup is disabled.
  static Future<int?> cleanupMetaFilesOnFolderPick(String directoryPath) async {
    if (!autoCleanupOnFolderPick) {
      return null;
    }

    return deleteMetaFilesRecursively(directoryPath);
  }

  /// Deletes all .meta files in [directoryPath] and its subfolders.
  static Future<int> deleteMetaFilesRecursively(String directoryPath) async {
    final rootDir = Directory(directoryPath);
    if (!await rootDir.exists()) {
      return 0;
    }

    int deletedCount = 0;
    await for (final entity in rootDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) {
        continue;
      }

      if (!entity.path.toLowerCase().endsWith('.meta')) {
        continue;
      }

      try {
        await entity.delete();
        deletedCount++;
      } catch (_) {
        // Skip locked/inaccessible files and keep cleaning the rest.
      }
    }

    return deletedCount;
  }
}
