import 'package:bottogram/units/virt_rmu.dart';
import 'package:hive/hive.dart';
import 'package:televerse/televerse.dart';

part 'virt_act.g.dart';

@HiveType(typeId: 30)
class VirtAct {
  @HiveField(0)
  VirtActType type;
  @HiveField(1)
  String text;
  @HiveField(2)
  VirtRMU? rmu;

  VirtAct({required this.type, required this.text});

  Future<void> run(Context ctx) async {
    switch (type) {
      case VirtActType.reply:
        await ctx.reply(text, replyMarkup: rmu?.hydrate());
        break;
      case VirtActType.dice:
        await ctx.replyWithDice();
    }
  }
}

enum VirtActType { reply, dice }

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
