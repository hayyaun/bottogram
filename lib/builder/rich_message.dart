import 'dart:convert';

import 'package:televerse/telegram.dart';
import 'package:televerse/televerse.dart' show InputFile;

import 'values.dart';

/// Builds typed Telegram blocks from resolved action data. Text values are
/// passed as literal text, so a binding cannot inject markup or another block.
abstract final class BuilderRichMessage {
  static InputRichMessage build(Object? data, {bool draft = false}) {
    var count = 0;
    var textLength = 0;
    RichText plain(Object? value) {
      final text = BuilderValues.scalar(value);
      textLength += text.length;
      if (text.trim().isEmpty || textLength > 16384) {
        throw const BuilderFailure('Rich message text is empty or too long.');
      }
      return RichText.plain(text: text);
    }

    List<dynamic> array(Object? value, int limit) {
      if (value is! List || value.isEmpty || value.length > limit) {
        throw const BuilderFailure('A rich message block has an invalid list.');
      }
      return value;
    }

    Uri url(Object? value, {bool photo = false}) {
      final uri = value is String ? Uri.tryParse(value) : null;
      if (uri == null ||
          (photo
              ? uri.scheme != 'https'
              : !{'http', 'https'}.contains(uri.scheme)) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw const BuilderFailure('Rich messages require valid web URLs.');
      }
      return uri;
    }

    InputRichBlock picture(Object? value) => InputRichBlock.photo(
      photo: InputMediaPhoto(
        media: InputFile.fromUrl(url(value, photo: true).toString()),
      ),
    );

    RichMessageButton button(Object? value) {
      if (value is! Map) {
        throw const BuilderFailure(
          'A rich button requires a label and action.',
        );
      }
      final data = value['callback_data'];
      final link = value['url'];
      if ((data == null) == (link == null) ||
          (data != null &&
              (data is! String ||
                  data.isEmpty ||
                  utf8.encode(data).length > 64))) {
        throw const BuilderFailure(
          'A rich button needs a URL or 1–64 bytes of callback data.',
        );
      }
      return RichMessageButton(
        text: plain(value['text']),
        style: switch (value['style']) {
          null => null,
          'primary' => StyleType.primary,
          'success' => StyleType.success,
          'danger' => StyleType.danger,
          'link' when data != null => StyleType.link,
          _ => throw const BuilderFailure('Invalid rich button style.'),
        },
        url: link == null ? null : url(link).toString(),
        callbackData: data as String?,
      );
    }

    late InputRichBlock Function(Object?, int) block;
    List<InputRichBlock> blocks(Object? values, int depth) {
      if (depth > 3) {
        throw const BuilderFailure(
          'Rich message blocks are nested too deeply.',
        );
      }
      return [for (final value in array(values, 50)) block(value, depth)];
    }

    // Assigned before compiling the top-level array; details recurse via blocks.
    block = (Object? value, int depth) {
      if (++count > 100 || value is! Map) {
        throw const BuilderFailure(
          'A rich message may contain up to 100 blocks.',
        );
      }
      return switch (value['type']) {
        'heading' => InputRichBlock.heading(
          text: plain(value['text']),
          size: 2,
        ),
        'paragraph' => InputRichBlock.paragraph(text: plain(value['text'])),
        'footer' => InputRichBlock.footer(text: plain(value['text'])),
        'details' => InputRichBlock.details(
          summary: plain(value['summary']),
          blocks: blocks(value['blocks'], depth + 1),
        ),
        'list' => InputRichBlock.list(
          items: [
            for (final item in array(value['items'], 50))
              InputRichBlockListItem(
                blocks: [InputRichBlock.paragraph(text: plain(item))],
              ),
          ],
        ),
        'table' => InputRichBlock.table(
          isBordered: true,
          isStriped: true,
          isCompact: true,
          cells: [
            for (final (index, row) in array(value['rows'], 51).indexed)
              [
                for (final cell in array(row, 8))
                  RichBlockTableCell(
                    text: plain(cell),
                    isHeader: index == 0 ? true : null,
                    align: 'left',
                    valign: 'middle',
                  ),
              ],
          ],
        ),
        'photo' when !draft => picture(value['url']),
        'collage' when !draft => InputRichBlock.collage(
          blocks: [
            for (final source in array(value['urls'], 10)) picture(source),
          ],
        ),
        'buttons' when !draft => InputRichBlock.buttons(
          buttons: array(value['buttons'], 8).map(button).toList(),
        ),
        'thinking' when draft => InputRichBlock.thinking(
          text: plain(value['text']),
        ),
        _ => throw const BuilderFailure('Unsupported rich message block.'),
      };
    };

    return InputRichMessage(blocks: blocks(data, 0));
  }
}
