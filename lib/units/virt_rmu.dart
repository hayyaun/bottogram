import 'package:bottogram/units/virt_event.dart';
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
  int callsEvent(VirtEvent ev);
}

enum VirtRMUType { none, keyboard, inlineKeyboard }

@HiveType(typeId: 41)
class VirtRMUKeyboard implements VirtRMU {
  @HiveField(0)
  @override
  String? name;

  @HiveField(1)
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

  @override
  VirtRMU copy(String name) {
    return VirtRMUKeyboard()
      ..items = items
      ..name = name;
  }

  @override
  int callsEvent(VirtEvent ev) {
    int count = 0;
    if (ev.type != VirtEventType.text) return count;
    for (final item in items) {
      if (item == ev.query) count++;
    }
    return count;
  }
}

@HiveType(typeId: 42)
class VirtRMUInlineKeyboard implements VirtRMU {
  @HiveField(0)
  @override
  String? name;

  @HiveField(1)
  List<KeyValue?> items = [];

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
    return VirtRMUInlineKeyboard()
      ..items = items
      ..name = name;
  }

  @override
  int callsEvent(VirtEvent ev) {
    int count = 0;
    if (ev.type != VirtEventType.callbackQuery) return count;
    for (final item in items) {
      if (item?.value == ev.query) count++;
    }
    return count;
  }
}

@HiveType(typeId: 43)
class KeyValue {
  @HiveField(0)
  String key;
  @HiveField(1)
  String value;

  KeyValue(this.key, this.value);
}
