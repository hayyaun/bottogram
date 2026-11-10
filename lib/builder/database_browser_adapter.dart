import 'database_browser_source.dart';
import 'values.dart';

/// The main database worker supplies this capability. Keeping the adapter
/// callback-based lets the viewer share its isolation and packaging unchanged.
typedef DatabaseInspector =
    Future<Map<String, dynamic>> Function(
      String bot,
      String operation,
      Map<String, dynamic> arguments,
    );

class BotDatabaseBrowserSource implements DatabaseBrowserSource {
  BotDatabaseBrowserSource({
    required this.botId,
    required DatabaseInspector inspect,
  }) : _inspect = inspect {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(botId)) {
      throw const DatabaseBrowseException('Invalid bot database identity.');
    }
  }
  final String botId;
  final DatabaseInspector _inspect;
  Future<T> _read<T>(
    String operation,
    Map<String, dynamic> arguments,
    T Function(Map<String, dynamic>) decode,
  ) async {
    try {
      return decode(await _inspect(botId, operation, arguments));
    } on BuilderFailure catch (error) {
      throw DatabaseBrowseException(error.message);
    } on DatabaseBrowseException {
      rethrow;
    } catch (_) {
      // Raw native/database exceptions can contain SQL or bound values.
      throw const DatabaseBrowseException(
        'The database could not be read. Refresh and try again.',
      );
    }
  }

  @override
  Future<List<DatabaseTable>> tables() => _read(
    'tables',
    const {},
    (value) =>
        (value['tables'] as List)
            .map((v) => DatabaseTable.fromMap(v as Map))
            .toList(),
  );
  @override
  Future<int> count(String table) => _read('count', {'table': table}, (value) {
    final count = value['count'] as int;
    if (count < 0) throw const FormatException();
    return count;
  });
  @override
  Future<DatabaseTableSchema> schema(String table) =>
      _read('schema', {'table': table}, DatabaseTableSchema.fromMap);
  @override
  Future<DatabaseRowsPage> rows(DatabaseRowsRequest request) async {
    if (!{10, 25, 50}.contains(request.limit) ||
        request.offset < 0 ||
        request.filterValue.length > 4096) {
      throw const DatabaseBrowseException(
        'Choose a valid page size, offset and filter value.',
      );
    }
    return _read('rows', request.toMap(), (value) {
      final page = DatabaseRowsPage.fromMap(value);
      if (page.rows.length > request.limit) throw const FormatException();
      return page;
    });
  }
}
