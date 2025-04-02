import 'package:bottogram/utils/valid.dart';
import 'package:hive/hive.dart';
import 'package:televerse/telegram.dart';
import 'package:televerse/televerse.dart';

part 'virt_rmu.g.dart';

abstract class VirtRMU {
  ReplyMarkup hydrate();
  VirtRMUType get type;
}

enum VirtRMUType { none, keyboard, inlineKeyboard }

@HiveType(typeId: 41)
class VirtRMUKeyboard implements VirtRMU {
  @HiveField(0)
  List<String?> items = [];

  @override
  get type => VirtRMUType.keyboard;

  @override
  ReplyMarkup hydrate() {
    var rmu = Keyboard();
    for (final item in items) {
      if (item == null) {
        rmu = rmu.row();
        continue;
      }
      rmu = rmu.text(item);
    }
    return rmu;
  }
}

@HiveType(typeId: 42)
class VirtRMUInlineKeyboard implements VirtRMU {
  @HiveField(0)
  List<MapEntry<String, String>?> items = [];

  @override
  get type => VirtRMUType.inlineKeyboard;

  @override
  ReplyMarkup hydrate() {
    var rmu = InlineKeyboard();
    for (final item in items) {
      if (item == null) {
        rmu = rmu.row();
      } else if (isValidUrl(item.value)) {
        rmu = rmu.addUrl(item.key, item.value);
      } else {
        rmu = rmu.add(item.key, item.value);
      }
    }
    return rmu;
  }
}
