import 'package:bottogram/units/virt_act.dart';
import 'package:bottogram/units/virt_bot.dart';
import 'package:hive/hive.dart';
import 'package:televerse/televerse.dart';

part 'virt_event.g.dart';

@HiveType(typeId: 20)
class VirtEvent extends HiveObject {
  static List<String> get commonCommands => ['start', 'help'];

  @HiveField(0)
  VirtBot bot;
  @HiveField(1)
  VirtEventType type;
  @HiveField(2)
  String query;
  @HiveField(3)
  List<VirtAct> acts = [];

  VirtEvent({
    this.type = VirtEventType.command,
    required this.query,
    required this.bot,
  });

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
      case VirtEventType.callbackQuery:
        return bot.callbackQuery(query, (ctx) async {
          ctx.answerCallbackQuery(); // no await
          return await callback(ctx);
        });
      case VirtEventType.inlineQuery:
        return bot.inlineQuery(query, callback);
    }
  }
}

enum VirtEventType { command, text, callbackQuery, inlineQuery }

class VirtEventTypeAdapter extends TypeAdapter<VirtEventType> {
  @override
  final typeId = 21;

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
