import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

class ImageProcessor {
  /// Split an image into tiles of given pixel dimensions.
  /// Returns list of output file paths.
  static Future<List<String>> splitImage({
    required String inputPath,
    required int tileWidth,
    required int tileHeight,
    required String outputDir,
    void Function(int current, int total)? onProgress,
  }) async {
    final file = File(inputPath);
    final bytes = await file.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) throw Exception('Không thể đọc ảnh');

    final cols = (image.width / tileWidth).ceil();
    final rows = (image.height / tileHeight).ceil();
    final total = cols * rows;

    // Create output directory
    final outDir = Directory(outputDir);
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }

    final baseName = p.basenameWithoutExtension(inputPath);
    final ext = p.extension(inputPath).toLowerCase();
    final outputPaths = <String>[];
    int current = 0;

    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final x = col * tileWidth;
        final y = row * tileHeight;
        final w = (x + tileWidth > image.width) ? image.width - x : tileWidth;
        final h = (y + tileHeight > image.height) ? image.height - y : tileHeight;

        final tile = img.copyCrop(image, x: x, y: y, width: w, height: h);

        final outputName = '${baseName}_${row}_$col$ext';
        final outputPath = p.join(outputDir, outputName);

        Uint8List encoded;
        switch (ext) {
          case '.png':
            encoded = img.encodePng(tile);
            break;
          case '.jpg':
          case '.jpeg':
            encoded = img.encodeJpg(tile, quality: 95);
            break;
          case '.bmp':
            encoded = img.encodeBmp(tile);
            break;
          case '.gif':
            encoded = img.encodeGif(tile);
            break;
          default:
            encoded = img.encodePng(tile);
            break;
        }

        await File(outputPath).writeAsBytes(encoded);
        outputPaths.add(outputPath);

        current++;
        onProgress?.call(current, total);
      }
    }

    return outputPaths;
  }

  /// Get image dimensions
  static Future<({int width, int height})?> getImageSize(String path) async {
    try {
      final file = File(path);
      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return null;
      return (width: image.width, height: image.height);
    } catch (_) {
      return null;
    }
  }

  /// Merge multiple images into one.
  /// [columns] determines how many images per row.
  /// [spacing] is the gap between images in pixels.
  static Future<String> mergeImages({
    required List<String> inputPaths,
    required int columns,
    required String outputPath,
    int spacing = 0,
    img.Color? backgroundColor,
    void Function(int current, int total)? onProgress,
  }) async {
    if (inputPaths.isEmpty) throw Exception('Không có ảnh để gộp');

    // Load all images
    final images = <img.Image>[];
    for (int i = 0; i < inputPaths.length; i++) {
      final file = File(inputPaths[i]);
      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image != null) {
        images.add(image);
      }
      onProgress?.call(i + 1, inputPaths.length + 1);
    }

    if (images.isEmpty) throw Exception('Không thể đọc ảnh nào');

    final rows = (images.length / columns).ceil();

    // Calculate cell size (max width/height in each column/row)
    final colWidths = List<int>.filled(columns, 0);
    final rowHeights = List<int>.filled(rows, 0);

    for (int i = 0; i < images.length; i++) {
      final col = i % columns;
      final row = i ~/ columns;
      if (images[i].width > colWidths[col]) {
        colWidths[col] = images[i].width;
      }
      if (images[i].height > rowHeights[row]) {
        rowHeights[row] = images[i].height;
      }
    }

    final totalWidth =
        colWidths.reduce((a, b) => a + b) + spacing * (columns - 1);
    final totalHeight =
        rowHeights.reduce((a, b) => a + b) + spacing * (rows - 1);

    final bgColor = backgroundColor ??
        img.ColorRgba8(0, 0, 0, 0);

    // Create output canvas
    final output = img.Image(
      width: totalWidth,
      height: totalHeight,
      numChannels: 4,
    );
    // Fill background
    img.fill(output, color: bgColor);

    // Place images
    for (int i = 0; i < images.length; i++) {
      final col = i % columns;
      final row = i ~/ columns;

      int x = 0;
      for (int c = 0; c < col; c++) {
        x += colWidths[c] + spacing;
      }
      int y = 0;
      for (int r = 0; r < row; r++) {
        y += rowHeights[r] + spacing;
      }

      // Center image in its cell
      final offsetX = (colWidths[col] - images[i].width) ~/ 2;
      final offsetY = (rowHeights[row] - images[i].height) ~/ 2;

      img.compositeImage(output, images[i],
          dstX: x + offsetX, dstY: y + offsetY);
    }

    // Encode and save
    final ext = p.extension(outputPath).toLowerCase();
    Uint8List encoded;
    switch (ext) {
      case '.jpg':
      case '.jpeg':
        encoded = img.encodeJpg(output, quality: 95);
        break;
      case '.bmp':
        encoded = img.encodeBmp(output);
        break;
      default:
        encoded = img.encodePng(output);
        break;
    }

    await File(outputPath).writeAsBytes(encoded);
    onProgress?.call(inputPaths.length + 1, inputPaths.length + 1);
    return outputPath;
  }
}
