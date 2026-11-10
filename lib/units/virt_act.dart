import 'package:bottogram/units/virt_rmu.dart';
import 'package:hive/hive.dart';
import 'package:televerse/televerse.dart';

part 'virt_act.adapter.dart';

class VirtAct {
  VirtActType type;
  String text;
  VirtRMU? rmu;
  Map<String, dynamic> config = {};

  VirtAct({required this.type, required this.text});

  Future<void> run(Context ctx) async {
    switch (type) {
      case VirtActType.reply:
        await ctx.reply(text, replyMarkup: rmu?.hydrate());
        break;
      case VirtActType.dice:
        await ctx.replyWithDice();
      default:
        throw StateError('This action requires the builder execution session.');
    }
  }
}

// Existing indexes are part of the on-disk format. Append new kinds only.
enum VirtActType {
  reply,
  dice,
  editText,
  editKeyboard,
  callbackAnswer,
  inlineAnswer,
  photo,
  video,
  document,
  audio,
  voice,
  animation,
  sticker,
  deleteMessage,
  pinMessage,
  http,
  setVariable,
  incrementVariable,
  condition,
  wait,
  sql,
  renderList,
}

class VirtActTypeAdapter extends TypeAdapter<VirtActType> {
  @override
  final typeId = 31;

  @override
  VirtActType read(BinaryReader reader) {
    int index = reader.readByte();
    return VirtActType.values[index];
  }

  @override
  void write(BinaryWriter writer, VirtActType obj) {
    writer.writeByte(obj.index);
  }
}
