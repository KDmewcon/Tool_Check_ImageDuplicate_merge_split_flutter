import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import '../models/duplicate_group.dart';

class ScanProgress {
  final int totalFiles;
  final int scannedFiles;
  final String currentFile;
  final int duplicateGroupsFound;

  ScanProgress({
    required this.totalFiles,
    required this.scannedFiles,
    required this.currentFile,
    required this.duplicateGroupsFound,
  });

  double get progress =>
      totalFiles > 0 ? scannedFiles / totalFiles : 0.0;
}

/// Top-level function for computing file hash in isolate
Future<String> _computeHashInIsolate(String filePath) async {
  final file = File(filePath);
  final Uint8List bytes = await file.readAsBytes();
  final digest = md5.convert(bytes);
  return digest.toString();
}

class ImageScanner {
  static const Set<String> imageExtensions = {
    '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.tiff', '.tif',
    '.ico', '.svg', '.heic', '.heif', '.avif', '.raw', '.cr2', '.nef',
    '.arw', '.dng',
  };

  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
  }

  /// Get duplicate groups from a directory
  Future<List<DuplicateGroup>> findDuplicates(
    String directoryPath,
    void Function(ScanProgress)? onProgress,
  ) async {
    _cancelled = false;
    final dir = Directory(directoryPath);

    if (!await dir.exists()) {
      return [];
    }

    // Phase 1: Collect all image files
    final List<File> imageFiles = [];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (_cancelled) return [];
      if (entity is File) {
        final ext = p.extension(entity.path).toLowerCase();
        if (imageExtensions.contains(ext)) {
          imageFiles.add(entity);
        }
      }
    }

    if (imageFiles.isEmpty) return [];

    // Phase 2: Group by file size first (optimization)
    final Map<int, List<File>> sizeGroups = {};
    for (final file in imageFiles) {
      if (_cancelled) return [];
      try {
        final stat = await file.stat();
        sizeGroups.putIfAbsent(stat.size, () => []).add(file);
      } catch (_) {}
    }

    final potentialDuplicates = <File>[];
    for (final group in sizeGroups.values) {
      if (group.length > 1) {
        potentialDuplicates.addAll(group);
      }
    }

    if (potentialDuplicates.isEmpty) {
      onProgress?.call(ScanProgress(
        totalFiles: imageFiles.length,
        scannedFiles: imageFiles.length,
        currentFile: '',
        duplicateGroupsFound: 0,
      ));
      return [];
    }

    // Phase 3: Compute hashes in isolate (non-blocking!)
    final Map<String, List<DuplicateImageInfo>> hashGroups = {};
    int scanned = 0;
    int lastReported = 0;
    final stopwatch = Stopwatch()..start();

    for (final file in potentialDuplicates) {
      if (_cancelled) return [];

      try {
        // Run hash computation in a separate isolate to avoid blocking UI
        final hash = await Isolate.run(() => _computeHashInIsolate(file.path));
        final stat = await file.stat();

        final imageInfo = DuplicateImageInfo(
          file: file,
          hash: hash,
          size: stat.size,
          modified: stat.modified,
        );

        hashGroups.putIfAbsent(hash, () => []).add(imageInfo);
      } catch (_) {}

      scanned++;

      // Throttle progress updates - only report every 100ms or on last file
      // This prevents excessive setState calls which cause UI lag
      if (stopwatch.elapsedMilliseconds - lastReported > 100 ||
          scanned == potentialDuplicates.length) {
        lastReported = stopwatch.elapsedMilliseconds;
        onProgress?.call(ScanProgress(
          totalFiles: potentialDuplicates.length,
          scannedFiles: scanned,
          currentFile: p.basename(file.path),
          duplicateGroupsFound:
              hashGroups.values.where((g) => g.length > 1).length,
        ));
        // Allow UI thread to process
        await Future.delayed(Duration.zero);
      }
    }

    // Build duplicate groups
    final groups = <DuplicateGroup>[];
    for (final entry in hashGroups.entries) {
      if (entry.value.length > 1) {
        // Sort by modified date (oldest first)
        entry.value.sort((a, b) => a.modified.compareTo(b.modified));
        groups.add(DuplicateGroup(
          hash: entry.key,
          images: entry.value,
        ));
      }
    }

    // Sort groups by total size (largest first)
    groups.sort((a, b) => b.totalSize.compareTo(a.totalSize));
    return groups;
  }

  /// Delete selected images
  static Future<int> deleteSelectedImages(
      List<DuplicateGroup> groups) async {
    int deleted = 0;
    for (final group in groups) {
      for (final image in group.images) {
        if (image.selected) {
          try {
            await image.file.delete();
            deleted++;
          } catch (_) {}
        }
      }
    }
    return deleted;
  }
}
