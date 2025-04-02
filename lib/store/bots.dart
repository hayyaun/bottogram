import 'package:bottogram/units/virt_bot.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive/hive.dart';

// Cubit for managing state
class BotsCubit extends Cubit<List<VirtBot>> {
  static const String boxName = 'botsBox';
  Box? _box;

  BotsCubit(BuildContext ctx) : super([]) {
    _initBox();
  }

  // Initialize Hive box
  Future<void> _initBox() async {
    _box = await Hive.openBox(boxName);
    List<dynamic>? boxJSON = _box?.values.toList();
    if (boxJSON == null) return; // nothing
    if (kDebugMode) print('--> bots: ${boxJSON.length}');
    var bots = boxJSON.toList().cast<VirtBot>();
    emit(bots); // Emit the saved value to Cubit's state
  }

  // Add a bot to the list and persist it
  void add(VirtBot bot) async {
    final updatedList = List<VirtBot>.from(state)..add(bot);
    emit(updatedList);
    await _box?.add(bot); // Persist the updated list
  }

  // Remove a bot from the list and persist it
  void remove(VirtBot bot) async {
    await bot.stop();
    final updatedList = List<VirtBot>.from(state)..remove(bot);
    emit(updatedList);
    final index = _box?.values.toList().cast<VirtBot>().indexOf(bot);
    if (index != null) await _box?.deleteAt(index); // Persist the updated list
  }

  // Update the list and persist it
  void update() {
    final updatedList = List<VirtBot>.from(state);
    emit(updatedList);
  }

  // Reset the list and persist it
  void reset() {
    emit([]);
    _box?.clear();
  }
}
