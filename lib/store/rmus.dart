import 'package:bottogram/units/virt_rmu.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive/hive.dart';

class RMUsCubit extends Cubit<List<VirtRMU>> {
  static const String boxName = 'rmusBox';
  Box<dynamic>? _box;
  late final Future<void> _ready;
  Future<void> get ready => _ready;
  Future<void> _tail = Future.value();
  String? lastError;

  RMUsCubit() : super([]) {
    _ready = _initBox();
  }

  Future<void> _initBox() async {
    try {
      _box = await Hive.openBox(boxName);
      emit(_box!.values.cast<VirtRMU>().toList());
    } catch (_) {
      lastError =
          'Template storage could not be opened. Reopen Bottogram to try again.';
      emit([]);
    }
  }

  Future<void> _mutate(Future<void> Function() action) {
    final operation = _tail.then((_) async {
      await ready;
      if (_box == null || lastError != null) {
        throw StateError(lastError ?? 'Template storage is unavailable.');
      }
      await action();
    });
    _tail = operation.then((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  Future<void> add(VirtRMU rmu) => _mutate(() async {
    await _box!.add(rmu);
    emit([...state, rmu]);
  });

  Future<void> remove(VirtRMU rmu) => _mutate(() async {
    final index = _box!.values.toList().indexOf(rmu);
    if (index < 0) return;
    await _box!.deleteAt(index);
    emit(state.where((item) => item != rmu).toList());
  });

  void update() => emit(List.of(state));

  Future<void> reset() => _mutate(() async {
    await _box!.clear();
    emit([]);
  });

  @override
  Future<void> close() async {
    await ready;
    await _tail;
    await super.close();
  }
}
