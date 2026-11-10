import 'package:bottogram/units/virt_event.dart';
import 'package:bottogram/utils/valid.dart';
import 'package:hive/hive.dart';
import 'package:televerse/telegram.dart';
import 'package:televerse/televerse.dart';

part 'virt_rmu.adapter.dart';

abstract class VirtRMU {
  String? name;
  ReplyMarkup hydrate();
  VirtRMUType get type;
  VirtRMU copy(String name);
  int callsEvent(VirtEvent ev);
}

enum VirtRMUType { none, keyboard, inlineKeyboard }

class VirtRMUKeyboard implements VirtRMU {
  @override
  String? name;
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
  VirtRMU copy(String name) =>
      VirtRMUKeyboard()
        ..items = List.of(items)
        ..name = name;
  @override
  int callsEvent(VirtEvent ev) {
    if (ev.type != VirtEventType.text) return 0;
    return items.where((item) => item == ev.query).length;
  }
}

class VirtRMUInlineKeyboard implements VirtRMU {
  @override
  String? name;
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
  VirtRMU copy(String name) =>
      VirtRMUInlineKeyboard()
        ..items =
            items
                .map(
                  (item) =>
                      item == null ? null : KeyValue(item.key, item.value),
                )
                .toList()
        ..name = name;
  @override
  int callsEvent(VirtEvent ev) {
    if (ev.type != VirtEventType.callbackQuery) return 0;
    return items.where((item) => item?.value == ev.query).length;
  }
}

class KeyValue {
  String key;
  String value;
  KeyValue(this.key, this.value);
}
