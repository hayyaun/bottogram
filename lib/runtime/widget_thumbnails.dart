import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as image;

import 'ports.dart';

const widgetRowsSlot = '/*widget-rows*/[]';
const maxWidgetRows = 10;
const _previewSize = 64;
const _highResolutionSize = 128;
const _widgetRowsDataKey = '_bottogramRows';

typedef WidgetRows = ({String html, Json data});

bool widgetHtmlFits(String html) {
  final bytes = utf8.encode(html);
  return bytes.length <= 32768 &&
      !bytes.contains(0) &&
      ZLibEncoder(level: 9).convert(bytes).length <= 4096;
}

Future<WidgetRows?> embedWidgetRows(
  String html,
  Json data,
  List<Json> rows,
  List<Uint8List?> sources, {
  bool allowWebp = false,
}) => Isolate.run(
  () => _embedWidgetRows(html, data, rows, sources, allowWebp: allowWebp),
);

WidgetRows? _embedWidgetRows(
  String html,
  Json data,
  List<Json> rows,
  List<Uint8List?> sources, {
  required bool allowWebp,
}) {
  final previews = sources
      .map((source) => _preview(source, allowWebp: allowWebp))
      .toList(growable: false);
  final hasHighResolution = previews.any(
    (photo) => photo?.highResolution != null,
  );
  final packedData = {...data, _widgetRowsDataKey: rows};
  final usePackedData =
      hasHighResolution &&
      !data.containsKey(_widgetRowsDataKey) &&
      utf8.encode(jsonEncode(packedData)).length <= 1024;
  final widgetData = usePackedData ? packedData : data;

  String insert(List<String?> images) {
    if (usePackedData) {
      final photos = jsonEncode(images);
      return html.replaceFirst(
        widgetRowsSlot,
        '''((rows, photos) => rows.map((row, i) =>
  photos[i] ? {...row, thumbnail: photos[i]} : row
))(JSON.parse(TelegramWidget.chatData || '{}').$_widgetRowsDataKey || [], $photos)''',
      );
    }
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
  if (previews.every((preview) => preview == null)) {
    return (html: plain, data: widgetData);
  }

  final levels = <List<String?>>[];
  String? fitted;
  for (final (size, quality, format) in [
    if (hasHighResolution) ...[
      (_highResolutionSize, 50, 'webp'),
      (_highResolutionSize, 20, 'webp'),
    ],
    (_previewSize, 62, 'jpeg'),
    if (allowWebp) (_previewSize, 65, 'webp'),
    if (hasHighResolution) ...[
      (_highResolutionSize, 5, 'webp'),
      (_highResolutionSize, 2, 'webp'),
    ],
    (_previewSize, 46, 'jpeg'),
    if (allowWebp) ...[
      (_previewSize, 45, 'webp'),
      (_previewSize, 35, 'webp'),
      (_previewSize, 25, 'webp'),
      (48, 55, 'webp'),
    ],
    (48, 44, 'jpeg'),
    if (allowWebp) (48, 45, 'webp'),
    (40, 43, 'jpeg'),
    (32, 42, 'jpeg'),
    (28, 39, 'jpeg'),
    (24, 35, 'jpeg'),
    (20, 32, 'jpeg'),
  ]) {
    final images = previews.map((preview) {
      if (preview == null) return null;
      final highResolution = size == _highResolutionSize
          ? preview.highResolution
          : null;
      final resized = size >= _previewSize
          ? highResolution ?? preview.standard
          : _resize(preview.standard, size);
      final bytes = format == 'webp'
          ? image.encodeWebP(
              resized,
              lossless: false,
              quality: size == _highResolutionSize && highResolution == null
                  ? 35
                  : quality,
              method: highResolution == null ? 4 : 6,
            )
          : image.encodeJpg(
              resized,
              quality: quality,
              chroma: image.JpegChroma.yuv420,
            );
      return 'data:image/$format;base64,${base64Encode(bytes)}';
    }).toList();
    levels.add(images);
    final candidate = insert(images);
    if (widgetHtmlFits(candidate)) {
      fitted = candidate;
      break;
    }
  }

  final images = levels.removeLast();
  if (fitted == null) {
    // Keep all rows and as many thumbnails as the HTML budget allows.
    for (var index = images.length - 1; index >= 0; index--) {
      if (images[index] == null) continue;
      images[index] = null;
      final candidate = insert(images);
      if (widgetHtmlFits(candidate)) {
        fitted = candidate;
        break;
      }
    }
  }

  // Improve one photo at a time, testing each upgrade against the whole widget.
  var best = fitted ?? plain;
  for (final (index, original) in images.indexed) {
    if (original == null) continue;
    for (final level in levels) {
      final sharper = level[index];
      if (sharper == null || sharper == original) continue;
      images[index] = sharper;
      final candidate = insert(images);
      if (widgetHtmlFits(candidate)) {
        best = candidate;
        break;
      }
      images[index] = original;
    }
  }
  return (html: best, data: widgetData);
}

({image.Image standard, image.Image? highResolution})? _preview(
  Uint8List? bytes, {
  required bool allowWebp,
}) {
  if (bytes == null) return null;
  try {
    final decoder = image.JpegDecoder(maxPixels: 4096 * 4096);
    final info = decoder.startDecode(bytes);
    if (info == null || info.width * info.height > 4096 * 4096) return null;
    final source = decoder.decodeFrame(0);
    if (source == null) return null;
    return (
      standard: _resize(source, _previewSize)..exif = image.ExifData(),
      highResolution:
          allowWebp &&
              (source.width >= _highResolutionSize ||
                  source.height >= _highResolutionSize)
          ? (_resize(source, _highResolutionSize)..exif = image.ExifData())
          : null,
    );
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
