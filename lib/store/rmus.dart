import 'package:bottogram/units/virt_rmu.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive/hive.dart';

// Cubit for managing state
class RMUsCubit extends Cubit<List<VirtRMU>> {
  static const String boxName = 'rmusBox';
  Box? _box;

  RMUsCubit() : super([]) {
    _initBox();
  }

  // Initialize Hive box
  Future<void> _initBox() async {
    _box = await Hive.openBox(boxName);
    List<dynamic>? boxJSON = _box?.values.toList();
    if (boxJSON == null) return; // nothing
    debugPrint('✅ rmus: ${boxJSON.length}');
    var rmus = boxJSON.toList().cast<VirtRMU>();
    emit(rmus); // Emit the saved value to Cubit's state
  }

  // Add a rmu to the list and persist it
  void add(VirtRMU rmu) async {
    final updatedList = List<VirtRMU>.from(state)..add(rmu);
    emit(updatedList);
    await _box?.add(rmu); // Persist the updated list
  }

  // Remove a rmu from the list and persist it
  void remove(VirtRMU rmu) async {
    final updatedList = List<VirtRMU>.from(state)..remove(rmu);
    emit(updatedList);
    final index = _box?.values.toList().cast<VirtRMU>().indexOf(rmu);
    if (index != null) await _box?.deleteAt(index); // Persist the updated list
  }

  // Update the list and persist it
  void update() {
    final updatedList = List<VirtRMU>.from(state);
    emit(updatedList);
  }

  // Reset the list and persist it
  void reset() {
    emit([]);
    _box?.clear();
  }
}
