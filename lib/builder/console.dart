import 'dart:collection';
import 'package:flutter/foundation.dart';

class ExecutionEntry {
  const ExecutionEntry({
    required this.time,
    required this.run,
    required this.event,
    required this.step,
    required this.status,
    required this.message,
    this.elapsed,
  });
  final DateTime time;
  final int run;
  final String event;
  final String step;
  final String status;
  final String message;
  final Duration? elapsed;
}

/// Session diagnostics deliberately omit request bodies, headers and values.
/// One bounded ring for the app prevents forgotten bots from growing memory.
class BuilderConsole extends ChangeNotifier {
  static final shared = BuilderConsole();
  final Queue<(String, ExecutionEntry)> _entries = Queue();
  int _run = 0;
  int nextRun() => ++_run;
  List<ExecutionEntry> entries(String bot) =>
      _entries
          .where((e) => e.$1 == bot)
          .map((e) => e.$2)
          .toList()
          .reversed
          .toList();
  void add(String bot, ExecutionEntry entry) {
    _entries.add((bot, entry));
    while (_entries.where((e) => e.$1 == bot).length > 200) {
      _entries.remove(_entries.firstWhere((e) => e.$1 == bot));
    }
    while (_entries.length > 1000) {
      _entries.removeFirst();
    }
    notifyListeners();
  }

  void clear(String bot) {
    _entries.removeWhere((e) => e.$1 == bot);
    notifyListeners();
  }
}
