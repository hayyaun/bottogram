import 'package:bottogram/utils/valid.dart';
import 'package:hive/hive.dart';
import 'package:televerse/telegram.dart';
import 'package:televerse/televerse.dart';

part 'virt_rmu.g.dart';

abstract class VirtRMU {
  String? name;
  ReplyMarkup hydrate();
  VirtRMUType get type;
  VirtRMU copy(String name);
}

enum VirtRMUType { none, keyboard, inlineKeyboard }

@HiveType(typeId: 41)
class VirtRMUKeyboard implements VirtRMU {
  @HiveField(0)
  List<String?> items = [];
  @HiveField(1)
  @override
  String? name;

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

  @override
  VirtRMU copy(String name) {
    final rmu = VirtRMUKeyboard();
    rmu.items = items;
    rmu.name = name;
    return rmu;
  }
}

@HiveType(typeId: 42)
class VirtRMUInlineKeyboard implements VirtRMU {
  @HiveField(0)
  List<MapEntry<String, String>?> items = [];
  @HiveField(1)
  @override
  String? name;

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

  @override
  VirtRMU copy(String name) {
    final rmu = VirtRMUInlineKeyboard();
    rmu.items = items;
    rmu.name = name;
    return rmu;
  }
}
