import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as image;

import 'ports.dart';

const widgetRowsSlot = '/*widget-rows*/[]';
const maxWidgetRows = 10;
const _maxPreviewSize = 64;

bool widgetHtmlFits(String html) {
  final bytes = utf8.encode(html);
  return bytes.length <= 32768 &&
      !bytes.contains(0) &&
      ZLibEncoder(level: 9).convert(bytes).length <= 4096;
}

Future<String?> embedWidgetRows(
  String html,
  List<Json> rows,
  List<Uint8List?> sources,
) => Isolate.run(() => _embedWidgetRows(html, rows, sources));

String? _embedWidgetRows(
  String html,
  List<Json> rows,
  List<Uint8List?> sources,
) {
  String insert(List<String?> images) {
    final encoded = jsonEncode([
      for (final (index, row) in rows.indexed)
        {
          ...row,
          if (index < images.length && images[index] != null)
            'thumbnail': images[index],
        },
    ]).replaceAll('<', r'\u003c');
    return html.replaceFirst(widgetRowsSlot, encoded);
  }

  final plain = insert([]);
  if (!widgetHtmlFits(plain)) return null;
  final previews = sources.map(_preview).toList(growable: false);
  if (previews.every((preview) => preview == null)) return plain;

  List<String?> images = [];
  for (final (size, quality) in [
    (_maxPreviewSize, 46),
    (48, 44),
    (32, 42),
    (28, 39),
    (24, 35),
    (20, 32),
  ]) {
    images = previews.map((preview) {
      if (preview == null) return null;
      final resized = size == _maxPreviewSize
          ? preview
          : _resize(preview, size);
      final bytes = image.encodeJpg(
        resized,
        quality: quality,
        chroma: image.JpegChroma.yuv420,
      );
      return 'data:image/jpeg;base64,${base64Encode(bytes)}';
    }).toList();
    final candidate = insert(images);
    if (widgetHtmlFits(candidate)) return candidate;
  }

  // Keep all rows and as many thumbnails as the remaining HTML budget allows.
  for (var index = images.length - 1; index >= 0; index--) {
    if (images[index] == null) continue;
    images[index] = null;
    final candidate = insert(images);
    if (widgetHtmlFits(candidate)) return candidate;
  }
  return plain;
}

image.Image? _preview(Uint8List? bytes) {
  if (bytes == null) return null;
  try {
    final decoder = image.JpegDecoder();
    final info = decoder.startDecode(bytes);
    if (info == null || info.width * info.height > 4096 * 4096) return null;
    final source = decoder.decodeFrame(0);
    if (source == null) return null;
    return _resize(source, _maxPreviewSize)..exif = image.ExifData();
  } catch (_) {
    return null;
  }
}

image.Image _resize(image.Image source, int size) => image.copyResize(
  source,
  width: source.width >= source.height ? size : null,
  height: source.height > source.width ? size : null,
  interpolation: image.Interpolation.average,
);
