import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

/// Called before the first upgraded bot write. The app data directory already
/// belongs to the current user; Unix snapshots additionally restrict permissions.
Future<void> ensureBuilderSnapshot(Box box) async {
  final sourcePath = box.path;
  if (sourcePath == null || box.isEmpty) return;
  final root = Directory(
    p.join(p.dirname(sourcePath), 'builder_upgrade_backup'),
  );
  final marker = File(p.join(root.path, 'completed.json'));
  if (await marker.exists()) {
    final data = jsonDecode(await marker.readAsString()) as Map;
    if (!await File(data['path'] as String).exists()) {
      throw const FileSystemException('The pre-builder backup is missing.');
    }
    return;
  }
  await box.flush();
  final dir = Directory(
    p.join(root.path, DateTime.now().toUtc().microsecondsSinceEpoch.toString()),
  );
  await dir.create(recursive: true);
  if (!Platform.isWindows) {
    for (final path in [root.path, dir.path]) {
      final result = await Process.run('chmod', ['700', path]);
      if (result.exitCode != 0) {
        throw const FileSystemException(
          'Could not protect the pre-builder backup.',
        );
      }
    }
  }
  final source = File(sourcePath),
      target = File(p.join(dir.path, p.basename(sourcePath)));
  await source.copy(target.path);
  if (!Platform.isWindows &&
      (await Process.run('chmod', ['600', target.path])).exitCode != 0) {
    throw const FileSystemException(
      'Could not protect the pre-builder backup.',
    );
  }
  final original = await sha256.bind(source.openRead()).first,
      snapshot = await sha256.bind(target.openRead()).first;
  if (original != snapshot) {
    throw const FileSystemException('Pre-builder backup verification failed.');
  }
  await marker.writeAsString(
    jsonEncode({'path': target.path, 'sha256': snapshot.toString()}),
    flush: true,
  );
  if (!Platform.isWindows) await Process.run('chmod', ['600', marker.path]);
}
