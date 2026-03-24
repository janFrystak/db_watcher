import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

class FileSyncService {
  final String sharedPath;
  final String memPath;
  final _metadataController = StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription? _watcherSubscription;

  FileSyncService({required this.sharedPath, required this.memPath});

  Stream<Map<String, dynamic>> get metadataStream => _metadataController.stream;

  void init() {
    _ensureDirsExist();
    scanExistingFiles();
    _startWatching();
    refresh();
  }

  void _ensureDirsExist() {
    Directory(sharedPath).createSync(recursive: true);
    Directory(memPath).createSync(recursive: true);
  }

  File get _metadataFile => File(p.join(memPath, 'metadata.json'));

  void _startWatching() {
    final watcher = DirectoryWatcher(sharedPath);
    _watcherSubscription = watcher.events.listen((event) async {
      if (event.type == ChangeType.ADD && event.path.endsWith('.sql')) {
        await _autoLogNewFile(event.path);
      }
      refresh();
    });
  }

  Future<void> scanExistingFiles() async {
    final dir = Directory(sharedPath);
    if (dir.existsSync()) {
      final entities = dir.listSync();
      for (var entity in entities) {
        if (entity is File && entity.path.endsWith('.sql')) {
          await _autoLogNewFile(entity.path);
        }
      }
      refresh();
    }
  }

  Future<void> _autoLogNewFile(String filePath) async {
    final data = await _readJson();
    final fileName = p.basename(filePath);

    if (!data.containsKey(fileName)) {
      data[fileName] = {
        'displayName': fileName,
        'date': DateTime.now().toString().substring(0, 16),
        'desc': 'Nový SQL skript...',
        'version': '1.0.0',
        'originalPath': filePath,
        'isDeleted': false,
        'lastUploadedAt': null,
      };
      await _metadataFile.writeAsString(jsonEncode(data), flush: true);
    }
  }

  Future<void> markUploaded(String key) async {
    final data = await _readJson();
    if (data.containsKey(key)) {
      data[key]['lastUploadedAt'] = DateTime.now().toString().substring(0, 16);
      await _metadataFile.writeAsString(jsonEncode(data), flush: true);
      refresh();
    }
  }

  Future<void> restoreEntry(String key) async {
    final data = await _readJson();
    if (data.containsKey(key)) {
      data[key]['isDeleted'] = false;
      await _metadataFile.writeAsString(jsonEncode(data), flush: true);
      refresh();
    }
  }

  Future<void> refresh() async {
    _metadataController.add(await _readJson());
  }

  Future<Map<String, dynamic>> _readJson() async {
    if (!_metadataFile.existsSync()) return {};
    try {
      return jsonDecode(await _metadataFile.readAsString());
    } catch (_) {
      return {};
    }
  }

  Future<void> deleteEntry(String key) async {
    final data = await _readJson();
    if (data.containsKey(key)) {
      data[key]['isDeleted'] = true;
      await _metadataFile.writeAsString(jsonEncode(data), flush: true);
      refresh();
    }
  }

  Future<void> updateEntry(String key, String newName, String newDesc) async {
    final data = await _readJson();
    if (data.containsKey(key)) {
      data[key]['displayName'] = newName;
      data[key]['desc'] = newDesc;
      await _metadataFile.writeAsString(jsonEncode(data), flush: true);
      refresh();
    }
  }

  void dispose() {
    _watcherSubscription?.cancel();
    _metadataController.close();
  }
}