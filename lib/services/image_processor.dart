import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Data class for split operation - must be top-level for Isolate
class _SplitParams {
  final String inputPath;
  final int tileWidth;
  final int tileHeight;
  final String outputDir;

  _SplitParams({
    required this.inputPath,
    required this.tileWidth,
    required this.tileHeight,
    required this.outputDir,
  });
}

/// Data class for merge operation - must be top-level for Isolate
class _MergeParams {
  final List<String> inputPaths;
  final int columns;
  final String outputPath;
  final int spacing;

  _MergeParams({
    required this.inputPaths,
    required this.columns,
    required this.outputPath,
    required this.spacing,
  });
}

/// Top-level function: split image in isolate
List<String> _splitInIsolate(_SplitParams params) {
  final file = File(params.inputPath);
  final bytes = file.readAsBytesSync();
  final image = img.decodeImage(bytes);
  if (image == null) throw Exception('Không thể đọc ảnh');

  final cols = (image.width / params.tileWidth).ceil();
  final rows = (image.height / params.tileHeight).ceil();

  final outDir = Directory(params.outputDir);
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }

  final baseName = p.basenameWithoutExtension(params.inputPath);
  final ext = p.extension(params.inputPath).toLowerCase();
  final outputPaths = <String>[];

  for (int row = 0; row < rows; row++) {
    for (int col = 0; col < cols; col++) {
      final x = col * params.tileWidth;
      final y = row * params.tileHeight;
      final w = (x + params.tileWidth > image.width)
          ? image.width - x
          : params.tileWidth;
      final h = (y + params.tileHeight > image.height)
          ? image.height - y
          : params.tileHeight;

      final tile = img.copyCrop(image, x: x, y: y, width: w, height: h);

      final outputName = '${baseName}_${row}_$col$ext';
      final outputPath = p.join(params.outputDir, outputName);

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

      File(outputPath).writeAsBytesSync(encoded);
      outputPaths.add(outputPath);
    }
  }

  return outputPaths;
}

/// Top-level function: merge images in isolate
String _mergeInIsolate(_MergeParams params) {
  final images = <img.Image>[];
  for (final path in params.inputPaths) {
    final file = File(path);
    final bytes = file.readAsBytesSync();
    final image = img.decodeImage(bytes);
    if (image != null) {
      images.add(image);
    }
  }

  if (images.isEmpty) throw Exception('Không thể đọc ảnh nào');

  final columns = params.columns;
  final rows = (images.length / columns).ceil();

  // Calculate cell size
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
      colWidths.reduce((a, b) => a + b) + params.spacing * (columns - 1);
  final totalHeight =
      rowHeights.reduce((a, b) => a + b) + params.spacing * (rows - 1);

  final bgColor = img.ColorRgba8(0, 0, 0, 0);

  final output = img.Image(
    width: totalWidth,
    height: totalHeight,
    numChannels: 4,
  );
  img.fill(output, color: bgColor);

  for (int i = 0; i < images.length; i++) {
    final col = i % columns;
    final row = i ~/ columns;

    int x = 0;
    for (int c = 0; c < col; c++) {
      x += colWidths[c] + params.spacing;
    }
    int y = 0;
    for (int r = 0; r < row; r++) {
      y += rowHeights[r] + params.spacing;
    }

    final offsetX = (colWidths[col] - images[i].width) ~/ 2;
    final offsetY = (rowHeights[row] - images[i].height) ~/ 2;

    img.compositeImage(output, images[i],
        dstX: x + offsetX, dstY: y + offsetY);
  }

  final ext = p.extension(params.outputPath).toLowerCase();
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

  File(params.outputPath).writeAsBytesSync(encoded);
  return params.outputPath;
}

class ImageProcessor {
  /// Split an image into tiles - runs in background isolate
  static Future<List<String>> splitImage({
    required String inputPath,
    required int tileWidth,
    required int tileHeight,
    required String outputDir,
    void Function(int current, int total)? onProgress,
  }) async {
    // Run heavy image processing in a separate isolate
    final result = await Isolate.run(() {
      return _splitInIsolate(_SplitParams(
        inputPath: inputPath,
        tileWidth: tileWidth,
        tileHeight: tileHeight,
        outputDir: outputDir,
      ));
    });
    // Report completion
    onProgress?.call(result.length, result.length);
    return result;
  }

  /// Get image dimensions - lightweight, runs on main thread
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

  /// Merge multiple images into one - runs in background isolate
  static Future<String> mergeImages({
    required List<String> inputPaths,
    required int columns,
    required String outputPath,
    int spacing = 0,
    void Function(int current, int total)? onProgress,
  }) async {
    if (inputPaths.isEmpty) throw Exception('Không có ảnh để gộp');

    // Run heavy image processing in a separate isolate
    final result = await Isolate.run(() {
      return _mergeInIsolate(_MergeParams(
        inputPaths: inputPaths,
        columns: columns,
        outputPath: outputPath,
        spacing: spacing,
      ));
    });
    onProgress?.call(inputPaths.length, inputPaths.length);
    return result;
  }
}
