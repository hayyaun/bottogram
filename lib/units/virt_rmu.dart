import 'package:hive/hive.dart';
import 'package:televerse/telegram.dart';
import 'package:televerse/televerse.dart';

part 'virt_rmu.g.dart';

@HiveType(typeId: 3)
class VirtRmu {
  @HiveField(0)
  List<String?> items = [];
  @HiveField(1)
  var type = VirtRMUType.keyboard;

  ReplyMarkup hydrate() {
    switch (type) {
      case VirtRMUType.keyboard:
        var rmu = Keyboard();
        for (final item in items) {
          if (item == null) {
            rmu = rmu.row();
            continue;
          }
          rmu = rmu.text(item);
        }
        return rmu;

      case VirtRMUType.inlineKeyboard:
        var rmu = InlineKeyboard();
        // TODO
        return rmu;
    }
  }
}

enum VirtRMUType { keyboard, inlineKeyboard }

class VirtRMUTypeAdapter extends TypeAdapter<VirtRMUType> {
  @override
  final typeId = 31;

  @override
  VirtRMUType read(BinaryReader reader) {
    int index = reader.readByte();
    return VirtRMUType.values[index];
  }

  @override
  void write(BinaryWriter writer, VirtRMUType obj) {
    writer.writeByte(obj.index);
  }
}
