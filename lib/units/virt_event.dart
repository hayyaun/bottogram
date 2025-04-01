import 'package:bottogram/units/virt_act.dart';
import 'package:hive/hive.dart';
import 'package:televerse/televerse.dart';

part 'virt_event.g.dart';

@HiveType(typeId: 1)
class VirtEvent extends HiveObject {
  static get commonCommands => ['start', 'help'];

  @HiveField(0)
  VirtEventType type;
  @HiveField(1)
  String query;
  @HiveField(2)
  List<VirtAct> acts = [VirtAct(text: "Hello!", type: VirtActType.reply)];

  VirtEvent({this.type = VirtEventType.command, required this.query});

  Future<void> callback(Context ctx) async {
    for (var act in acts) {
      await act.run(ctx);
    }
  }

  void add(Bot bot) async {
    switch (type) {
      case VirtEventType.command:
        return bot.command(query, callback);
      case VirtEventType.text:
        return bot.text(query, callback);
    }
  }
}

enum VirtEventType { command, text }

class VirtEventTypeAdapter extends TypeAdapter<VirtEventType> {
  @override
  final typeId = 11;

  @override
  VirtEventType read(BinaryReader reader) {
    int index = reader.readByte();
    return VirtEventType.values[index];
  }

  @override
  void write(BinaryWriter writer, VirtEventType obj) {
    writer.writeByte(obj.index);
  }
}
