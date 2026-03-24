import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'services/file_sync_service.dart';
import 'package:postgres/postgres.dart';
import 'package:mysql_client/mysql_client.dart';

void main() {
  runApp(const MaterialApp(
    home: SqlManagerScreen(),
    debugShowCheckedModeBanner: false,
  ));
}

class SqlManagerScreen extends StatefulWidget {
  const SqlManagerScreen({super.key});

  @override
  State<SqlManagerScreen> createState() => _SqlManagerScreenState();
}

class _SqlManagerScreenState extends State<SqlManagerScreen> {
  late final FileSyncService _fileService;
  late final String _memPath;
  bool _showDeleted = false;

  Map<String, String> _dbConfig = {
    'type': 'MySQL',
    'host': '',
    'user': '',
    'pass': '',
    'dbName': ''
  };

  File get _dbConfigFile => File(p.join(_memPath, 'db_config.json'));

  Future<void> _saveDbConfig() async {
    await _dbConfigFile.writeAsString(jsonEncode(_dbConfig), flush: true);
  }

  Future<void> _loadDbConfig() async {
    if (!_dbConfigFile.existsSync()) return;
    try {
      final raw = jsonDecode(await _dbConfigFile.readAsString());
      setState(() {
        _dbConfig = Map<String, String>.from(raw);
      });
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    final sharedPath = p.join(Directory.current.path, 'shared');
    _memPath = p.join(Directory.current.path, 'mem');
    _fileService = FileSyncService(sharedPath: sharedPath, memPath: _memPath);
    _fileService.init();
    _loadDbConfig();
  }

  @override
  void dispose() {
    _fileService.dispose();
    super.dispose();
  }

  Future<void> _uploadToDb(String fileName) async {
    if (_dbConfig['host']!.isEmpty) {
      _showSnackBar('Nejdříve nastavte DB připojení!');
      return;
    }

    final file = File(p.join(_fileService.sharedPath, fileName));
    final sql = await file.readAsString();
    final dbType = _dbConfig['type'];

    try {
      _showSnackBar('Odesílám do $dbType...');

      if (dbType == 'MySQL') {
        await _executeMysql(sql);
      } else if (dbType == 'PostgreSQL') {
        await _executePostgres(sql);
      }

      // FIX 3: success snackbar only fires if no exception was thrown
      await _fileService.markUploaded(fileName);
      if (mounted) _showSnackBar('$fileName úspěšně nahrán!');
    } catch (e) {
      if (mounted) _showSnackBar('Chyba: $e', isError: true);
    }
  }

  Future<void> _executeMysql(String sql) async {
    final conn = await MySQLConnection.createConnection(
      host: _dbConfig['host']!,
      port: 3306,
      userName: _dbConfig['user']!,
      password: _dbConfig['pass']!,
      databaseName: _dbConfig['dbName'],
    );
    await conn.connect();

    // FIX 4: split multi-statement SQL and execute each separately
    final statements = sql
        .split(';')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    for (final stmt in statements) {
      await conn.execute(stmt);
    }

    await conn.close();
  }

  Future<void> _executePostgres(String sql) async {
    final connection = await Connection.open(
      Endpoint(
        host: _dbConfig['host']!,
        database: _dbConfig['dbName']!,
        username: _dbConfig['user'],
        password: _dbConfig['pass'],
      ),
      // FIX 1: Neon requires SSL — was SslMode.disable
      settings: const ConnectionSettings(sslMode: SslMode.require),
    );

    // FIX 4: split multi-statement SQL and execute each separately
    final statements = sql
        .split(';')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    for (final stmt in statements) {
      await connection.execute(stmt);
    }

    await connection.close();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SQL Sync Tool'),
        backgroundColor: Colors.blueGrey[900],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_showDeleted ? Icons.visibility : Icons.visibility_off),
            tooltip: _showDeleted ? 'Skrýt smazané' : 'Zobrazit smazané',
            color: _showDeleted ? Colors.orange : null,
            onPressed: () => setState(() => _showDeleted = !_showDeleted),
          ),
          IconButton(
            icon: const Icon(Icons.settings_input_component),
            tooltip: 'Nastavení databáze',
            onPressed: () => _showDbSettings(),
          ),
        ],
      ),
      body: StreamBuilder<Map<String, dynamic>>(
        stream: _fileService.metadataStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Složka /shared je prázdná'));
          }

          final allKeys = snapshot.data!;
          final displayedKeys = allKeys.keys.where((k) {
            final isDeleted = allKeys[k]['isDeleted'] == true;
            return _showDeleted ? true : !isDeleted;
          }).toList();

          if (displayedKeys.isEmpty) {
            return const Center(child: Text('Všechny soubory jsou v koši.'));
          }

          return ListView.builder(
            itemCount: displayedKeys.length,
            itemBuilder: (context, index) {
              final key = displayedKeys.elementAt(index);
              final meta = allKeys[key];
              final bool isDeleted = meta['isDeleted'] == true;

              return Card(
                color: isDeleted ? Colors.grey.shade200.withValues(alpha: 0.6) : null,
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: ListTile(
                  leading: Icon(
                    Icons.storage,
                    color: isDeleted ? Colors.grey : Colors.blue,
                  ),
                  title: Text(
                    meta['displayName'] ?? key,
                    style: TextStyle(
                      color: isDeleted ? Colors.grey : Colors.black87,
                      decoration: isDeleted ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(meta['desc']),
                      if (meta['lastUploadedAt'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.cloud_done, size: 13, color: Colors.green),
                              const SizedBox(width: 4),
                              Text(
                                'Uploaded ${meta['lastUploadedAt']}',
                                style: const TextStyle(fontSize: 11, color: Colors.green),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isDeleted) ...[
                        IconButton(
                          icon: const Icon(Icons.upload, color: Colors.green),
                          tooltip: 'Upload to DB',
                          onPressed: () => _uploadToDb(key),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          tooltip: 'Edit Metadata',
                          onPressed: () => _showEditDialog(key, meta),
                        ),
                      ],
                      IconButton(
                        icon: Icon(
                          isDeleted ? Icons.restore : Icons.delete_outline,
                          color: isDeleted ? Colors.blue : Colors.red,
                        ),
                        tooltip: isDeleted ? 'Obnovit' : 'Smazat',
                        onPressed: () {
                          if (isDeleted) {
                            _fileService.restoreEntry(key);
                          } else {
                            _confirmDelete(key);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _confirmDelete(String key) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Smazat záznam?'),
        content: Text('Chcete odstranit metadata pro $key? (Soubor na disku zůstane)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Zrušit')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              _fileService.deleteEntry(key);
              Navigator.pop(ctx);
            },
            child: const Text('Smazat'),
          ),
        ],
      ),
    );
  }

  void _showDbSettings() {
    final hostCtrl = TextEditingController(text: _dbConfig['host']);
    final userCtrl = TextEditingController(text: _dbConfig['user']);
    final passCtrl = TextEditingController(text: _dbConfig['pass']);
    // FIX 2: dbName controller was missing — field existed but was never saved
    final dbNameCtrl = TextEditingController(text: _dbConfig['dbName']);

    String selectedType = _dbConfig['type'] ?? 'MySQL';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Konfigurace DB'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedType,
                decoration: const InputDecoration(labelText: 'Typ databáze'),
                items: const [
                  DropdownMenuItem(value: 'MySQL', child: Text('MySQL')),
                  DropdownMenuItem(value: 'PostgreSQL', child: Text('PostgreSQL')),
                ],
                onChanged: (val) {
                  setDialogState(() => selectedType = val!);
                },
              ),
              TextField(
                  controller: hostCtrl,
                  decoration: const InputDecoration(labelText: 'Host (IP/Doména)')),
              TextField(
                  controller: userCtrl,
                  decoration: const InputDecoration(labelText: 'Uživatel')),
              TextField(
                  controller: passCtrl,
                  decoration: const InputDecoration(labelText: 'Heslo'),
                  obscureText: true),
              // FIX 2: dbName field was in the form but controller was never wired up
              TextField(
                  controller: dbNameCtrl,
                  decoration: const InputDecoration(labelText: 'Název databáze')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Zrušit')),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _dbConfig = {
                    'type': selectedType,
                    'host': hostCtrl.text,
                    'user': userCtrl.text,
                    'pass': passCtrl.text,
                    // FIX 2: actually persist dbName
                    'dbName': dbNameCtrl.text,
                  };
                });
                _saveDbConfig();
                Navigator.pop(ctx);
              },
              child: const Text('Uložit'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(String key, dynamic meta) {
    final nameCtrl = TextEditingController(text: meta['displayName']);
    final descCtrl = TextEditingController(text: meta['desc']);
    final fileCtrl = TextEditingController(text: p.basename(meta['originalPath']));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Editovat metadata: $key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Zobrazované jméno')),
            TextField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: 'Popis')),
            TextField(
                controller: fileCtrl,
                decoration: const InputDecoration(labelText: 'Soubor'),
                readOnly: true),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              _fileService.updateEntry(key, nameCtrl.text, descCtrl.text);
              Navigator.pop(ctx);
            },
            child: const Text('Uložit'),
          )
        ],
      ),
    );
  }
}