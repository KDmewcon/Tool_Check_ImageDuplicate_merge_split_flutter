import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Result of grid auto-detection
class GridDetectionResult {
  final List<int> horizontalLines; // Y positions of horizontal grid lines
  final List<int> verticalLines;   // X positions of vertical grid lines
  final int cellWidth;
  final int cellHeight;
  final int cols;
  final int rows;
  final int imageWidth;
  final int imageHeight;

  GridDetectionResult({
    required this.horizontalLines,
    required this.verticalLines,
    required this.cellWidth,
    required this.cellHeight,
    required this.cols,
    required this.rows,
    required this.imageWidth,
    required this.imageHeight,
  });

  Map<String, dynamic> toMap() => {
    'horizontalLines': horizontalLines,
    'verticalLines': verticalLines,
    'cellWidth': cellWidth,
    'cellHeight': cellHeight,
    'cols': cols,
    'rows': rows,
    'imageWidth': imageWidth,
    'imageHeight': imageHeight,
  };

  static GridDetectionResult fromMap(Map<String, dynamic> map) {
    return GridDetectionResult(
      horizontalLines: List<int>.from(map['horizontalLines']),
      verticalLines: List<int>.from(map['verticalLines']),
      cellWidth: map['cellWidth'],
      cellHeight: map['cellHeight'],
      cols: map['cols'],
      rows: map['rows'],
      imageWidth: map['imageWidth'],
      imageHeight: map['imageHeight'],
    );
  }
}

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

/// Data class for auto-detect grid operation
class _AutoDetectParams {
  final String inputPath;
  final int sensitivity; // 0-100, higher = more sensitive to edges

  _AutoDetectParams({
    required this.inputPath,
    this.sensitivity = 50,
  });
}

/// Data class for auto-split operation
class _AutoSplitParams {
  final String inputPath;
  final String outputDir;
  final List<int> horizontalLines;
  final List<int> verticalLines;
  final String? namePrefix;
  final bool removeWhiteBg;
  final int whiteTolerance; // 0-255, how close to white to remove

  _AutoSplitParams({
    required this.inputPath,
    required this.outputDir,
    required this.horizontalLines,
    required this.verticalLines,
    this.namePrefix,
    this.removeWhiteBg = false,
    this.whiteTolerance = 20,
  });
}

/// Calculate color variance along a row of pixels
double _rowColorVariance(img.Image image, int y) {
  if (image.width <= 1) return 0;
  
  double sumR = 0, sumG = 0, sumB = 0, sumA = 0;
  final n = image.width.toDouble();
  
  for (int x = 0; x < image.width; x++) {
    final pixel = image.getPixel(x, y);
    sumR += pixel.r;
    sumG += pixel.g;
    sumB += pixel.b;
    sumA += pixel.a;
  }
  
  final avgR = sumR / n;
  final avgG = sumG / n;
  final avgB = sumB / n;
  final avgA = sumA / n;
  
  double variance = 0;
  for (int x = 0; x < image.width; x++) {
    final pixel = image.getPixel(x, y);
    variance += (pixel.r - avgR) * (pixel.r - avgR);
    variance += (pixel.g - avgG) * (pixel.g - avgG);
    variance += (pixel.b - avgB) * (pixel.b - avgB);
    variance += (pixel.a - avgA) * (pixel.a - avgA);
  }
  
  return variance / n;
}

/// Calculate color variance along a column of pixels
double _colColorVariance(img.Image image, int x) {
  if (image.height <= 1) return 0;
  
  double sumR = 0, sumG = 0, sumB = 0, sumA = 0;
  final n = image.height.toDouble();
  
  for (int y = 0; y < image.height; y++) {
    final pixel = image.getPixel(x, y);
    sumR += pixel.r;
    sumG += pixel.g;
    sumB += pixel.b;
    sumA += pixel.a;
  }
  
  final avgR = sumR / n;
  final avgG = sumG / n;
  final avgB = sumB / n;
  final avgA = sumA / n;
  
  double variance = 0;
  for (int y = 0; y < image.height; y++) {
    final pixel = image.getPixel(x, y);
    variance += (pixel.r - avgR) * (pixel.r - avgR);
    variance += (pixel.g - avgG) * (pixel.g - avgG);
    variance += (pixel.b - avgB) * (pixel.b - avgB);
    variance += (pixel.a - avgA) * (pixel.a - avgA);
  }
  
  return variance / n;
}

/// Find the best regular interval that matches the detected lines
int _findBestInterval(List<int> positions, int totalSize) {
  if (positions.isEmpty) return totalSize;
  if (positions.length == 1) return positions[0];
  
  // Calculate gaps between consecutive positions
  final gaps = <int>[];
  gaps.add(positions[0]); // gap from start to first line
  for (int i = 1; i < positions.length; i++) {
    gaps.add(positions[i] - positions[i - 1]);
  }
  
  // Find the most common gap (mode)
  final gapCounts = <int, int>{};
  for (final gap in gaps) {
    // Allow some tolerance - group nearby gaps
    bool found = false;
    for (final key in gapCounts.keys.toList()) {
      if ((gap - key).abs() <= 2) {
        gapCounts[key] = gapCounts[key]! + 1;
        found = true;
        break;
      }
    }
    if (!found) {
      gapCounts[gap] = 1;
    }
  }
  
  // Return the gap with the highest count
  int bestGap = gaps[0];
  int bestCount = 0;
  gapCounts.forEach((gap, count) {
    if (count > bestCount) {
      bestCount = count;
      bestGap = gap;
    }
  });
  
  return bestGap;
}


/// Top-level function: auto-detect grid in isolate
Map<String, dynamic> _autoDetectGridInIsolate(_AutoDetectParams params) {
  final file = File(params.inputPath);
  final bytes = file.readAsBytesSync();
  final image = img.decodeImage(bytes);
  if (image == null) throw Exception('Không thể đọc ảnh');

  final width = image.width;
  final height = image.height;
  
  // Sensitivity maps to threshold: higher sensitivity = higher threshold = easier to detect
  final thresholdBase = 500.0 + (params.sensitivity / 100.0) * 4500.0;
  
  // === Strategy 1: Find rows/columns with low color variance (uniform separator lines) ===
  
  // Scan all rows for potential horizontal separators
  final rowVariances = <double>[];
  for (int y = 0; y < height; y++) {
    rowVariances.add(_rowColorVariance(image, y));
  }
  
  // Scan all columns for potential vertical separators
  final colVariances = <double>[];
  for (int x = 0; x < width; x++) {
    colVariances.add(_colColorVariance(image, x));
  }
  
  // Find rows with variance significantly lower than average (potential separators)
  final avgRowVar = rowVariances.reduce((a, b) => a + b) / rowVariances.length;
  final avgColVar = colVariances.reduce((a, b) => a + b) / colVariances.length;
  
  // Use adaptive threshold
  final rowThreshold = min(thresholdBase, avgRowVar * 0.3);
  final colThreshold = min(thresholdBase, avgColVar * 0.3);
  
  // Find horizontal separator lines
  final hSeparators = <int>[];
  int y = 1; // Skip edges
  while (y < height - 1) {
    if (rowVariances[y] < rowThreshold) {
      // Find the middle of the separator band
      int start = y;
      while (y < height - 1 && rowVariances[y] < rowThreshold) {
        y++;
      }
      int end = y;
      hSeparators.add((start + end) ~/ 2);
    }
    y++;
  }
  
  // Find vertical separator lines
  final vSeparators = <int>[];
  int x = 1; // Skip edges
  while (x < width - 1) {
    if (colVariances[x] < colThreshold) {
      int start = x;
      while (x < width - 1 && colVariances[x] < colThreshold) {
        x++;
      }
      int end = x;
      vSeparators.add((start + end) ~/ 2);
    }
    x++;
  }
  
  // === Strategy 2: If variance-based detection found too few lines, try edge detection ===
  List<int> finalHLines = hSeparators;
  List<int> finalVLines = vSeparators;
  
  if (hSeparators.length < 2 && vSeparators.length < 2) {
    // Try edge-based detection: look for sharp color transitions
    // Compute row-to-row difference
    final rowDiffs = <double>[];
    for (int y = 0; y < height - 1; y++) {
      double diff = 0;
      for (int x = 0; x < width; x += max(1, width ~/ 50)) {
        final p1 = image.getPixel(x, y);
        final p2 = image.getPixel(x, y + 1);
        diff += (p1.r - p2.r).abs() + (p1.g - p2.g).abs() + (p1.b - p2.b).abs();
      }
      rowDiffs.add(diff);
    }
    
    final colDiffs = <double>[];
    for (int x = 0; x < width - 1; x++) {
      double diff = 0;
      for (int y = 0; y < height; y += max(1, height ~/ 50)) {
        final p1 = image.getPixel(x, y);
        final p2 = image.getPixel(x + 1, y);
        diff += (p1.r - p2.r).abs() + (p1.g - p2.g).abs() + (p1.b - p2.b).abs();
      }
      colDiffs.add(diff);
    }
    
    // Find peaks in row diffs (edge lines)
    if (rowDiffs.isNotEmpty) {
      final avgRowDiff = rowDiffs.reduce((a, b) => a + b) / rowDiffs.length;
      final edgeThreshold = avgRowDiff * 2.0;
      
      final hEdges = <int>[];
      for (int i = 5; i < rowDiffs.length - 5; i++) {
        if (rowDiffs[i] > edgeThreshold) {
          // Check if it's a local peak
          bool isPeak = true;
          for (int j = max(0, i - 3); j <= min(rowDiffs.length - 1, i + 3); j++) {
            if (j != i && rowDiffs[j] > rowDiffs[i]) {
              isPeak = false;
              break;
            }
          }
          if (isPeak) hEdges.add(i);
        }
      }
      if (hEdges.length > finalHLines.length) finalHLines = hEdges;
    }
    
    if (colDiffs.isNotEmpty) {
      final avgColDiff = colDiffs.reduce((a, b) => a + b) / colDiffs.length;
      final edgeThreshold = avgColDiff * 2.0;
      
      final vEdges = <int>[];
      for (int i = 5; i < colDiffs.length - 5; i++) {
        if (colDiffs[i] > edgeThreshold) {
          bool isPeak = true;
          for (int j = max(0, i - 3); j <= min(colDiffs.length - 1, i + 3); j++) {
            if (j != i && colDiffs[j] > colDiffs[i]) {
              isPeak = false;
              break;
            }
          }
          if (isPeak) vEdges.add(i);
        }
      }
      if (vEdges.length > finalVLines.length) finalVLines = vEdges;
    }
  }
  
  // === Strategy 3: If still no grid found, try to find by common tile sizes ===
  if (finalHLines.isEmpty && finalVLines.isEmpty) {
    // Try common tile sizes: check if the image dimensions are divisible by common sizes
    final commonSizes = [8, 16, 24, 32, 48, 64, 96, 128, 256, 512];
    
    // Find the largest common tile size that gives at least 2x2 grid
    int bestTileW = width;
    int bestTileH = height;
    
    for (final size in commonSizes.reversed) {
      if (width % size == 0 && width ~/ size >= 2) {
        bestTileW = size;
        break;
      }
    }
    
    for (final size in commonSizes.reversed) {
      if (height % size == 0 && height ~/ size >= 2) {
        bestTileH = size;
        break;
      }
    }
    
    // If we found good tile sizes, create grid lines
    if (bestTileW < width) {
      for (int i = bestTileW; i < width; i += bestTileW) {
        finalVLines.add(i);
      }
    }
    if (bestTileH < height) {
      for (int i = bestTileH; i < height; i += bestTileH) {
        finalHLines.add(i);
      }
    }
  }
  
  // Calculate cell dimensions
  final cellWidth = finalVLines.isNotEmpty
      ? _findBestInterval(finalVLines, width)
      : width;
  final cellHeight = finalHLines.isNotEmpty
      ? _findBestInterval(finalHLines, height)
      : height;
  
  final cols = cellWidth > 0 ? max(1, (width / cellWidth).round()) : 1;
  final rows = cellHeight > 0 ? max(1, (height / cellHeight).round()) : 1;
  
  // Regenerate clean, evenly-spaced grid lines
  final cleanVLines = <int>[];
  final cleanHLines = <int>[];
  
  for (int i = 1; i < cols; i++) {
    cleanVLines.add((width * i / cols).round());
  }
  for (int i = 1; i < rows; i++) {
    cleanHLines.add((height * i / rows).round());
  }

  return GridDetectionResult(
    horizontalLines: cleanHLines,
    verticalLines: cleanVLines,
    cellWidth: cellWidth,
    cellHeight: cellHeight,
    cols: cols,
    rows: rows,
    imageWidth: width,
    imageHeight: height,
  ).toMap();
}

/// Top-level function: auto-split image using detected grid lines
/// Remove white/near-white background from an image tile, making it transparent.
/// [tolerance] 0-255: how close to pure white a pixel must be to become transparent.
img.Image _removeWhiteBg(img.Image src, int tolerance) {
  // Ensure image has alpha channel
  final result = src.hasAlpha ? src.clone() : img.Image(
    width: src.width,
    height: src.height,
    numChannels: 4,
  );

  // Copy pixels if we created a new image
  if (!src.hasAlpha) {
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final p = src.getPixel(x, y);
        result.setPixel(x, y, img.ColorRgba8(
          p.r.toInt(), p.g.toInt(), p.b.toInt(), 255));
      }
    }
  }

  final threshold = 255 - tolerance;
  for (int y = 0; y < result.height; y++) {
    for (int x = 0; x < result.width; x++) {
      final pixel = result.getPixel(x, y);
      final r = pixel.r.toInt();
      final g = pixel.g.toInt();
      final b = pixel.b.toInt();
      // If pixel is near-white, set alpha to 0
      if (r >= threshold && g >= threshold && b >= threshold) {
        result.setPixel(x, y, img.ColorRgba8(r, g, b, 0));
      }
    }
  }
  return result;
}

List<String> _autoSplitInIsolate(_AutoSplitParams params) {
  final file = File(params.inputPath);
  final bytes = file.readAsBytesSync();
  final image = img.decodeImage(bytes);
  if (image == null) throw Exception('Không thể đọc ảnh');

  final outDir = Directory(params.outputDir);
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }

  final baseName = p.basenameWithoutExtension(params.inputPath);
  final ext = p.extension(params.inputPath).toLowerCase();
  final outputPaths = <String>[];
  final prefix = params.namePrefix;

  // Build the cut points including edges
  final xCuts = [0, ...params.verticalLines, image.width];
  final yCuts = [0, ...params.horizontalLines, image.height];

  int index = 1; // Sequential counter for naming
  for (int row = 0; row < yCuts.length - 1; row++) {
    for (int col = 0; col < xCuts.length - 1; col++) {
      final x = xCuts[col];
      final y = yCuts[row];
      final w = xCuts[col + 1] - x;
      final h = yCuts[row + 1] - y;

      if (w <= 0 || h <= 0) continue;

      img.Image tile = img.copyCrop(image, x: x, y: y, width: w, height: h);

      // Apply white background removal if requested
      if (params.removeWhiteBg) {
        tile = _removeWhiteBg(tile, params.whiteTolerance);
      }

      // Always use PNG when removing background (to preserve transparency)
      final finalExt = params.removeWhiteBg ? '.png' : ext;
      final outputName = (prefix != null && prefix.isNotEmpty)
          ? '$prefix\$$index$finalExt'
          : '${baseName}_${row}_$col$finalExt';
      final outputPath = p.join(params.outputDir, outputName);

      Uint8List encoded;
      switch (finalExt) {
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
      index++;
    }
  }

  return outputPaths;
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

  /// Auto-detect grid lines in an image - runs in background isolate
  static Future<GridDetectionResult> autoDetectGrid({
    required String inputPath,
    int sensitivity = 50,
  }) async {
    final resultMap = await Isolate.run(() {
      return _autoDetectGridInIsolate(_AutoDetectParams(
        inputPath: inputPath,
        sensitivity: sensitivity,
      ));
    });
    return GridDetectionResult.fromMap(resultMap);
  }

  /// Auto-split image using detected grid lines - runs in background isolate
  static Future<List<String>> autoSplitImage({
    required String inputPath,
    required String outputDir,
    required List<int> horizontalLines,
    required List<int> verticalLines,
    String? namePrefix,
    bool removeWhiteBg = false,
    int whiteTolerance = 20,
    void Function(int current, int total)? onProgress,
  }) async {
    final result = await Isolate.run(() {
      return _autoSplitInIsolate(_AutoSplitParams(
        inputPath: inputPath,
        outputDir: outputDir,
        horizontalLines: horizontalLines,
        verticalLines: verticalLines,
        namePrefix: namePrefix,
        removeWhiteBg: removeWhiteBg,
        whiteTolerance: whiteTolerance,
      ));
    });
    onProgress?.call(result.length, result.length);
    return result;
  }

  /// Resize a single image to specific pixel dimensions
  static Future<void> resizeSingle({
    required String inputPath,
    required String outputPath,
    required int width,
    required int height,
  }) async {
    await Isolate.run(() {
      final file = File(inputPath);
      final bytes = file.readAsBytesSync();
      final image = img.decodeImage(bytes);
      if (image == null) throw Exception('Không thể đọc ảnh: $inputPath');

      final resized = img.copyResize(image,
          width: width,
          height: height,
          interpolation: img.Interpolation.linear);

      final ext = p.extension(outputPath).toLowerCase();
      Uint8List encoded;
      switch (ext) {
        case '.png':
          encoded = img.encodePng(resized);
          break;
        case '.jpg':
        case '.jpeg':
          encoded = img.encodeJpg(resized, quality: 95);
          break;
        case '.bmp':
          encoded = img.encodeBmp(resized);
          break;
        case '.gif':
          encoded = img.encodeGif(resized);
          break;
        default:
          encoded = img.encodePng(resized);
          break;
      }

      File(outputPath).writeAsBytesSync(encoded);
    });
  }

  /// Batch resize images - creates scaled versions in sibling folders
  /// sourceDir is treated as the "x4" (100%) folder
  /// Creates x3 (75%), x2 (50%), x1 (25%) folders next to it
  static Future<Map<String, List<String>>> resizeBatch({
    required String sourceDir,
    required List<ResizeScale> scales,
    void Function(int current, int total, String currentFile)? onProgress,
  }) async {
    // Collect image files
    final dir = Directory(sourceDir);
    final imageFiles = <String>[];
    
    await for (final entity in dir.list(recursive: false, followLinks: false)) {
      if (entity is File) {
        final ext = p.extension(entity.path).toLowerCase();
        if (['.png', '.jpg', '.jpeg', '.bmp', '.gif', '.webp'].contains(ext)) {
          imageFiles.add(entity.path);
        }
      }
    }

    if (imageFiles.isEmpty) throw Exception('Không tìm thấy ảnh trong thư mục');

    final parentDir = p.dirname(sourceDir);
    final results = <String, List<String>>{};

    int processed = 0;
    final totalOps = imageFiles.length * scales.length;

    for (final scale in scales) {
      final outputDir = p.join(parentDir, scale.folderName);
      final outDirectory = Directory(outputDir);
      if (!outDirectory.existsSync()) {
        outDirectory.createSync(recursive: true);
      }

      final scaledPaths = <String>[];

      for (final imagePath in imageFiles) {
        onProgress?.call(processed, totalOps, p.basename(imagePath));

        final outputPath = p.join(outputDir, p.basename(imagePath));

        await Isolate.run(() {
          _resizeSingleInIsolate(
            imagePath,
            outputPath,
            scale.percentage,
          );
        });

        scaledPaths.add(outputPath);
        processed++;
        onProgress?.call(processed, totalOps, p.basename(imagePath));
      }

      results[scale.folderName] = scaledPaths;
    }

    return results;
  }

  /// Crop border pixels from an image then zoom back to original size.
  /// Uses nearest-neighbor interpolation — perfect for pixel art sprites.
  static Future<void> cropAndRestore({
    required String inputPath,
    required String outputPath,
    required int cropTop,
    required int cropBottom,
    required int cropLeft,
    required int cropRight,
  }) async {
    await Isolate.run(() => _cropRestoreInIsolate(CropRestoreParams(
          inputPath: inputPath,
          outputPath: outputPath,
          cropTop: cropTop,
          cropBottom: cropBottom,
          cropLeft: cropLeft,
          cropRight: cropRight,
        )));
  }
}

/// Scale configuration for resize
class ResizeScale {
  final String folderName;
  final double percentage; // 0.0 - 1.0

  const ResizeScale({
    required this.folderName,
    required this.percentage,
  });
}

/// Top-level function: resize a single image in isolate
void _resizeSingleInIsolate(
    String inputPath, String outputPath, double scale) {
  final file = File(inputPath);
  final bytes = file.readAsBytesSync();
  final image = img.decodeImage(bytes);
  if (image == null) throw Exception('Không thể đọc ảnh: $inputPath');

  final newWidth = (image.width * scale).round();
  final newHeight = (image.height * scale).round();

  if (newWidth <= 0 || newHeight <= 0) return;

  final resized = img.copyResize(image,
      width: newWidth,
      height: newHeight,
      interpolation: img.Interpolation.linear);

  final ext = p.extension(outputPath).toLowerCase();
  Uint8List encoded;
  switch (ext) {
    case '.png':
      encoded = img.encodePng(resized);
      break;
    case '.jpg':
    case '.jpeg':
      encoded = img.encodeJpg(resized, quality: 95);
      break;
    case '.bmp':
      encoded = img.encodeBmp(resized);
      break;
    case '.gif':
      encoded = img.encodeGif(resized);
      break;
    default:
      encoded = img.encodePng(resized);
      break;
  }

  File(outputPath).writeAsBytesSync(encoded);
}

// ─────────────────────────────────────────────────────────────────────────────
// Crop border + restore to original size (pixel-perfect upscale)
// ─────────────────────────────────────────────────────────────────────────────

class CropRestoreParams {
  final String inputPath;
  final String outputPath;
  final int cropTop;
  final int cropBottom;
  final int cropLeft;
  final int cropRight;

  CropRestoreParams({
    required this.inputPath,
    required this.outputPath,
    required this.cropTop,
    required this.cropBottom,
    required this.cropLeft,
    required this.cropRight,
  });
}

void _cropRestoreInIsolate(CropRestoreParams params) {
  final file = File(params.inputPath);
  final bytes = file.readAsBytesSync();
  final image = img.decodeImage(bytes);
  if (image == null) throw Exception('Không thể đọc ảnh: ${params.inputPath}');

  final origW = image.width;
  final origH = image.height;

  final cropX = params.cropLeft;
  final cropY = params.cropTop;
  final cropW = origW - params.cropLeft - params.cropRight;
  final cropH = origH - params.cropTop - params.cropBottom;

  if (cropW <= 0 || cropH <= 0) {
    throw Exception(
        'Crop quá lớn: ảnh ${origW}x$origH không thể cắt ${params.cropLeft}+${params.cropRight} ngang, ${params.cropTop}+${params.cropBottom} dọc');
  }

  // Step 1: Crop the border pixels
  final cropped = img.copyCrop(image, x: cropX, y: cropY, width: cropW, height: cropH);

  // Step 2: Zoom back to original size using nearest-neighbor (pixel perfect)
  final restored = img.copyResize(
    cropped,
    width: origW,
    height: origH,
    interpolation: img.Interpolation.nearest,
  );

  // Encode (always PNG to preserve any transparency)
  final ext = p.extension(params.outputPath).toLowerCase();
  Uint8List encoded;
  switch (ext) {
    case '.jpg':
    case '.jpeg':
      encoded = img.encodeJpg(restored, quality: 97);
      break;
    case '.bmp':
      encoded = img.encodeBmp(restored);
      break;
    case '.gif':
      encoded = img.encodeGif(restored);
      break;
    default:
      encoded = img.encodePng(restored);
      break;
  }

  File(params.outputPath).writeAsBytesSync(encoded);
}

