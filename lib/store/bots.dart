import 'dart:async';
import 'dart:io';

import 'package:bottogram/units/virt_bot.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// Cubit for managing state
class BotsCubit extends Cubit<List<VirtBot>> {
  static const String boxName = 'botsbox';
  static const String importBoxName = 'importBox';
  static const String exportBoxName = 'exportBox';
  Box<VirtBot>? _box;

  BotsCubit(BuildContext ctx) : super([]) {
    _initBox();
  }

  // Initialize Hive box
  Future<void> _initBox() async {
    _box = await Hive.openBox<VirtBot>(boxName);
    final data = _box!.values.toList();
    debugPrint('✅ Bots: ${data.length}');
    final bots = data.cast<VirtBot>();
    emit(bots);
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

  // Other methods

  Future<ShareResult?> share(List<int> items) async {
    try {
      final tempBox = await Hive.openBox<VirtBot>(exportBoxName);
      await tempBox.clear();
      for (final i in items) {
        tempBox.add(state[i]);
      }
      final dir = await getApplicationDocumentsDirectory();
      final file = XFile('${dir.path}/$exportBoxName.hive');
      final formattedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final subject = 'Bottogram Data - $formattedDate';
      return await Share.shareXFiles([file], subject: subject);
    } catch (err) {
      debugPrint('❌ Share > $err');
      return null;
    }
  }

  Future<void> import() async {
    try {
      if (!await pickAndSaveFile()) throw 'Cant make temp file!'; // makes temp
      final tempBox = await Hive.openBox<VirtBot>(importBoxName);
      final data = tempBox.values.toList();
      debugPrint('✅ Importing > ${data.length}');
      final bots = data.cast<VirtBot>();
      final updatedList = List<VirtBot>.from(state)..addAll(bots);
      emit(updatedList);
    } catch (err) {
      debugPrint('❌ Import > $err');
      return;
    }
  }

  Future<bool> pickAndSaveFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      dialogTitle: 'Pick a backup file',
      type: FileType.any,
    );
    if (result == null || result.files.single.path == null) {
      debugPrint('❌ No file selected.');
      return false;
    }
    final selectedFile = File(result.files.single.path!);
    final appDocDir = await getApplicationDocumentsDirectory();
    final targetFile = File('${appDocDir.path}/$importBoxName.hive');
    await selectedFile.copy(targetFile.path); // create/overwrite
    debugPrint('✅ File copied to: ${targetFile.path}');
    return true;
  }
}
