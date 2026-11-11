import 'package:bottogram/units/virt_act.dart';
import 'package:hive/hive.dart';
import 'package:televerse/televerse.dart';
import '../builder/event_match.dart';

part 'virt_event.adapter.dart';

class VirtEvent extends HiveObject {
  VirtEventType type;
  String query;
  List<VirtAct> acts = [];
  Map<String, dynamic> config = {};
  Future<void> Function(Context)? _execute;

  VirtEvent({required this.type, required this.query});

  Future<void> callback(Context ctx) async {
    if (_execute != null) {
      await _execute!(ctx);
      return;
    }
    for (var act in acts) {
      await act.run(ctx);
    }
  }

  void add(Bot bot, {Future<void> Function(Context)? execute}) {
    _execute = execute;
    if (config.containsKey('match') &&
        {
          VirtEventType.text,
          VirtEventType.callbackQuery,
          VirtEventType.inlineQuery,
        }.contains(type)) {
      bot.filter(
        (ctx) {
          final input = switch (type) {
            VirtEventType.text => ctx.message?.text,
            VirtEventType.callbackQuery => ctx.callbackQuery?.data,
            VirtEventType.inlineQuery => ctx.inlineQuery?.query,
            _ => null,
          };
          return input != null &&
              BuilderEventMatch.remainder(
                    input,
                    query,
                    config['match'].toString(),
                  ) !=
                  null;
        },
        (ctx) async {
          if (type == VirtEventType.callbackQuery &&
              !acts.any((a) => a.type == VirtActType.callbackAnswer)) {
            await ctx.answerCallbackQuery();
          }
          await callback(ctx);
        },
      );
      return;
    }
    switch (type) {
      case VirtEventType.command:
        bot.command(query, callback);
      case VirtEventType.text:
        bot.text(query, callback);
      case VirtEventType.callbackQuery:
        bot.callbackQuery(query, (ctx) async {
          if (!acts.any((act) => act.type == VirtActType.callbackAnswer)) {
            await ctx.answerCallbackQuery();
          }
          return await callback(ctx);
        });
      case VirtEventType.inlineQuery:
        bot.inlineQuery(query, callback);
      case VirtEventType.polling:
        return;
    }
  }
}

enum VirtEventType { command, text, callbackQuery, inlineQuery, polling }

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
