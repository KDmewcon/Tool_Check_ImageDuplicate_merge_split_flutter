import 'dart:io';

class DuplicateImageInfo {
  final File file;
  final String hash;
  final int size;
  final DateTime modified;
  bool selected;

  DuplicateImageInfo({
    required this.file,
    required this.hash,
    required this.size,
    required this.modified,
    this.selected = false,
  });

  String get name => file.uri.pathSegments.last;
  String get path => file.path;

  String get sizeFormatted {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class DuplicateGroup {
  final String hash;
  final List<DuplicateImageInfo> images;

  DuplicateGroup({
    required this.hash,
    required this.images,
  });

  int get totalSize => images.fold(0, (sum, img) => sum + img.size);
  int get selectedCount => images.where((img) => img.selected).length;

  int get potentialSavings {
    final selectedImages = images.where((img) => img.selected).toList();
    return selectedImages.fold(0, (sum, img) => sum + img.size);
  }

  void autoSelectDuplicates() {
    for (int i = 0; i < images.length; i++) {
      images[i].selected = i > 0;
    }
  }

  void selectAll() {
    for (var img in images) {
      img.selected = true;
    }
  }

  void deselectAll() {
    for (var img in images) {
      img.selected = false;
    }
  }
}
