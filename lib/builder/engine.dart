import 'dart:async';
import 'dart:convert';
import '../runtime/http_transport.dart';
import '../runtime/ports.dart';
import 'console.dart';
import 'list_renderer.dart';
import 'values.dart';

typedef BuilderJson = Map<String, dynamic>;

class BuilderStep {
  const BuilderStep(this.kind, this.text, this.config);
  final String kind;
  final String text;
  final BuilderJson config;
}

abstract interface class BuilderTelegram {
  Future<BuilderJson> execute(String kind, BuilderJson arguments);
}

abstract interface class BuilderVariables {
  Future<BuilderJson> read(String? userId);
  Future<dynamic> change(
    String? userId,
    String scope,
    String name,
    dynamic value, {
    bool increment = false,
  });
}

abstract interface class BuilderSqlVariables {
  Future<BuilderJson> query(String sql, List<dynamic> parameters);
}

class BuilderEngine {
  BuilderEngine({
    required this.botId,
    required this.telegram,
    required this.variables,
    required this.secret,
    BoundedJsonTransport? http,
    BuilderConsole? console,
  }) : http = http ?? BoundedJsonTransport(),
       console = console ?? BuilderConsole.shared;
  final String botId;
  final BuilderTelegram telegram;
  final BuilderVariables variables;
  final Future<String?> Function(String name) secret;
  final BoundedJsonTransport http;
  final BuilderConsole console;
  Future<void> _tail = Future.value();
  var _pending = 0;
  var _closed = false;
  final _stopped = Completer<void>();

  Future<void> run(
    String label,
    BuilderJson event,
    List<BuilderStep> source,
  ) async {
    if (_closed) return;
    final run = console.nextRun();
    void log(String step, String status, String message, [Duration? elapsed]) =>
        console.add(
          botId,
          ExecutionEntry(
            time: DateTime.now(),
            run: run,
            event: label,
            step: step,
            status: status,
            message: message,
            elapsed: elapsed,
          ),
        );
    if (_pending >= 32) {
      log('', 'error', 'The event queue is full (32 pending runs).');
      return;
    }
    if (source.length > 64) {
      log('', 'error', 'An event may have at most 64 actions.');
      return;
    }
    try {
      var size = 0;
      for (final step in source) {
        size += utf8
            .encode(
              jsonEncode({
                'kind': step.kind,
                'text': step.text,
                'config': step.config,
              }),
            )
            .length;
        if (size > 262144) {
          log('', 'error', 'Event configuration exceeds 256 KiB.');
          return;
        }
      }
    } catch (_) {
      log('', 'error', 'The event contains invalid action settings.');
      return;
    }
    // Snapshot definitions before queueing: editing an open form cannot alter a run.
    final steps = source
        .map(
          (s) => BuilderStep(
            s.kind,
            s.text,
            jsonDecode(jsonEncode(s.config)) as BuilderJson,
          ),
        )
        .toList();
    _pending++;
    final result = _tail.then((_) async {
      if (_closed) return;
      final userId = event['userId']?.toString();
      var current = '';
      try {
        if (steps.length > 64) {
          throw const BuilderFailure('An event may have at most 64 actions.');
        }
        final values = <String, dynamic>{
          'event': event,
          'steps': <String, dynamic>{},
          ...await variables.read(userId),
        };
        final names = <String>{};
        for (final (index, step) in steps.indexed) {
          final name = step.config['output']?.toString() ?? 'step${index + 1}';
          if (!BuilderValues.name.hasMatch(name) || !names.add(name)) {
            throw const BuilderFailure(
              'Each action needs a unique output name.',
            );
          }
        }
        var outputBytes = 0;
        log('', 'started', 'Event matched; ${steps.length} actions queued.');
        for (final (index, step) in steps.indexed) {
          if (_closed) return;
          current = (step.config['output'] as String?) ?? 'step${index + 1}';
          final clock = Stopwatch()..start();
          try {
            final when = step.config['when'];
            if (when is Map &&
                !_condition(Map<String, dynamic>.from(when), values)) {
              log(current, 'skipped', 'The action condition was false.');
              continue;
            }
            log(current, 'running', '${step.kind} started.');
            final output = await _execute(step, values);
            if (_closed) return;
            outputBytes += utf8.encode(jsonEncode(output)).length;
            if (outputBytes > 2 * 1024 * 1024) {
              throw const BuilderFailure(
                'This execution exceeds the 2 MiB action-output budget.',
              );
            }
            (values['steps'] as BuilderJson)[current] = output;
            log(
              current,
              'success',
              '${step.kind} completed${output['status'] is int ? ' (HTTP ${output['status']})' : ''}.',
              clock.elapsed,
            );
            if (step.kind == 'condition' &&
                output['matched'] == false &&
                step.config['stopIfFalse'] != false) {
              log('', 'completed', 'Stopped because the condition was false.');
              return;
            }
          } catch (error) {
            if (_closed) return;
            final message = error is BuilderFailure
                ? error.message
                : error is RuntimeFailure
                ? error.message
                : 'Action failed. Check its configuration, permissions and connection.';
            log(current, 'error', message, clock.elapsed);
            (values['steps'] as BuilderJson)[current] = {
              'ok': false,
              'error': message,
            };
            if (step.config['onError'] != 'continue') {
              log('', 'failed', 'Execution stopped at $current.');
              return;
            }
          }
        }
        log('', 'completed', 'Execution completed.');
      } catch (error) {
        if (!_closed) {
          log(
            current,
            'error',
            error is BuilderFailure
                ? error.message
                : 'Execution could not load its configuration or variables.',
          );
        }
      }
    });
    _tail = result.whenComplete(() => _pending--);
    await _tail;
  }

  bool _condition(BuilderJson condition, BuilderJson values) {
    var left = BuilderValues.resolve(condition['left'] ?? '', values);
    var right = BuilderValues.resolve(condition['right'] ?? '', values);
    if (left is num && right is String) right = num.tryParse(right) ?? right;
    if (right is num && left is String) left = num.tryParse(left) ?? left;
    if (left is bool && right is String && {'true', 'false'}.contains(right)) {
      right = right == 'true';
    }
    if (right is bool && left is String && {'true', 'false'}.contains(left)) {
      left = left == 'true';
    }
    return switch (condition['operator'] ?? 'equals') {
      'equals' => left == right,
      'notEquals' => left != right,
      'contains' => BuilderValues.scalar(
        left,
      ).contains(BuilderValues.scalar(right)),
      'greater' => _number(left) > _number(right),
      'less' => _number(left) < _number(right),
      _ => throw const BuilderFailure('Unknown condition operator.'),
    };
  }

  num _number(dynamic value) {
    final number = value is num ? value : num.tryParse(value.toString());
    if (number == null || !number.isFinite) {
      throw const BuilderFailure(
        'A numeric operation requires a finite number.',
      );
    }
    return number;
  }

  Future<BuilderJson> _execute(BuilderStep step, BuilderJson values) async {
    final config = step.config;
    if (step.kind == 'renderList') {
      return BuilderListRenderer.render(step, values);
    }
    String field(String name, [String fallback = '']) {
      final raw = config[name]?.toString() ?? '';
      return BuilderValues.text(raw.isEmpty ? fallback : raw, values);
    }

    if (step.kind == 'sql') {
      final data = variables;
      if (data is! BuilderSqlVariables) {
        throw const BuilderFailure('SQL storage is unavailable.');
      }
      final parameters = BuilderValues.json(
        config['parameters']?.toString() ?? '[]',
        values,
      );
      if (parameters is! List) {
        throw const BuilderFailure('SQL parameters must be a JSON array.');
      }
      return (data as BuilderSqlVariables).query(step.text, parameters);
    }
    if (step.kind == 'http') {
      final address = config['url']?.toString() ?? '';
      final uri = _url(address, values);
      final headersRaw = BuilderValues.json(
        config['headers']?.toString() ?? '{}',
        values,
      );
      if (headersRaw is! Map || headersRaw.values.any((v) => v is! String)) {
        throw const BuilderFailure(
          'API headers must be a JSON object of strings.',
        );
      }
      final headers = Map<String, String>.from(headersRaw);
      final secretName = config['credential']?.toString() ?? '';
      if (secretName.isNotEmpty) {
        if (!BuilderValues.name.hasMatch(secretName)) {
          throw const BuilderFailure('Invalid credential name.');
        }
        final token = await secret(secretName);
        if (token == null || token.isEmpty) {
          throw const BuilderFailure(
            'The selected API credential is unavailable.',
          );
        }
        headers['Authorization'] = 'Bearer $token';
      }
      final bodyText = config['body']?.toString() ?? '';
      final body = bodyText.trim().isEmpty
          ? null
          : BuilderValues.json(bodyText, values);
      if (_closed) throw const BuilderFailure('Bot stopped.');
      return http.request(
        config['method']?.toString() ?? 'GET',
        uri,
        headers,
        body: body,
      );
    }
    if (step.kind == 'setVariable' || step.kind == 'incrementVariable') {
      final scope = config['scope']?.toString() ?? 'user';
      final name = config['variable']?.toString() ?? '';
      final value = BuilderValues.resolve(step.text, values);
      final result = await variables.change(
        (values['event'] as BuilderJson)['userId']?.toString(),
        scope,
        name,
        step.kind == 'incrementVariable' ? _number(value) : value,
        increment: step.kind == 'incrementVariable',
      );
      (values[scope] as BuilderJson)[name] = result;
      return {'value': result};
    }
    if (step.kind == 'condition') {
      return {'matched': _condition(config, values)};
    }
    if (step.kind == 'wait') {
      final seconds = _number(BuilderValues.resolve(step.text, values));
      if (seconds < 0 || seconds > 60) {
        throw const BuilderFailure('Wait must be between 0 and 60 seconds.');
      }
      await Future.any([
        Future<void>.delayed(Duration(milliseconds: (seconds * 1000).round())),
        _stopped.future,
      ]);
      return {'ok': true};
    }
    final markdown = config['format'] == 'MarkdownV2';
    final event = values['event'] as BuilderJson;
    final arguments = <String, dynamic>{
      'text': BuilderValues.text(step.text, values, markdown: markdown),
      'format': markdown ? 'MarkdownV2' : null,
      'chatId': field('chatId', event['chatId']?.toString() ?? ''),
      'messageId': field('messageId', event['messageId']?.toString() ?? ''),
      'inlineMessageId':
          (config['messageId']?.toString() ?? '').isEmpty &&
              (config['chatId']?.toString() ?? '').isEmpty
          ? event['inlineMessageId']
          : null,
      'callbackId': event['callbackId'],
      'inlineQueryId': event['inlineQueryId'],
      'media': field('media'),
      'title': field('title', 'Result'),
      'showAlert': config['showAlert'] == true,
      'latitude': field('latitude'),
      'longitude': field('longitude'),
      if (config['keyboard'] != null ||
          (config['keyboardOutput']?.toString() ?? '').isNotEmpty)
        'keyboard': BuilderValues.resolve(
          (config['keyboardOutput']?.toString() ?? '').isNotEmpty
              ? config['keyboardOutput']
              : config['keyboard'],
          values,
        ),
    };
    if (_closed) throw const BuilderFailure('Bot stopped.');
    return telegram.execute(step.kind, arguments);
  }

  Uri _url(String source, BuilderJson values) {
    // URI components are escaped independently. Values cannot replace the host
    // or smuggle a query delimiter into a path parameter.
    final withoutReferences = source.replaceAll(
      BuilderValues.reference,
      'binding',
    );
    final parsed = Uri.tryParse(withoutReferences);
    final authorityEnd = source.indexOf(
      RegExp(r'[/\?#]'),
      source.indexOf('://') + 3,
    );
    final authority = authorityEnd == -1
        ? source
        : source.substring(0, authorityEnd);
    if (authority.contains('{{') ||
        parsed == null ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty ||
        parsed.hasFragment ||
        !{'https', 'http'}.contains(parsed.scheme)) {
      throw const BuilderFailure(
        'Enter an HTTP(S) API URL with a fixed host and no credentials or fragment.',
      );
    }
    final result = source.replaceAllMapped(
      BuilderValues.reference,
      (match) => Uri.encodeComponent(
        BuilderValues.scalar(BuilderValues.lookup(values, match[1]!)),
      ),
    );
    return Uri.parse(result);
  }

  Future<void> close() async {
    _closed = true;
    if (!_stopped.isCompleted) _stopped.complete();
    http.close();
    await _tail;
  }
}
