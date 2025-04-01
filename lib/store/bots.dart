import 'package:bottogram/units/virt_bot.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive/hive.dart';

// Cubit for managing state
class BotsCubit extends Cubit<List<VirtBot>> {
  static const String boxName = 'botsBox';
  Box? _box;

  BotsCubit() : super([]) {
    // _initBox();
  }

  // Initialize Hive box
  Future<void> _initBox() async {
    _box = await Hive.openBox(boxName);
    List<dynamic>? boxJSON = _box?.get('bots');
    if (boxJSON == null) return; // nothing
    var bots =
        boxJSON.map((boxItemJSON) => VirtBot.fromJSON(boxItemJSON)).toList();
    emit(bots); // Emit the saved value to Cubit's state
  }

  // Add a bot to the list and persist it
  void addBot(VirtBot bot) {
    final updatedList = List<VirtBot>.from(state)..add(bot);
    emit(updatedList);
    _box?.put('bots', updatedList); // Persist the updated list
  }

  // Remove a bot from the list and persist it
  void removeBot(VirtBot bot) async {
    await bot.stop();
    final updatedList = List<VirtBot>.from(state)..remove(bot);
    emit(updatedList);
    _box?.put('bots', updatedList); // Persist the updated list
  }

  // Update the list and persist it
  void update() {
    final updatedList = List<VirtBot>.from(state);
    emit(updatedList);
    _box?.put('bots', updatedList); // Clear the saved list
  }

  // Reset the list and persist it
  void reset() {
    emit([]);
    _box?.put('bots', []); // Clear the saved list
  }
}
