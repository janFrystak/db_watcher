import 'dart:io';
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
  
 
  Map<String, String> _dbConfig = {'host': '', 'user': '', 'pass': ''};

  @override
  void initState() {
    super.initState();
    final sharedPath = p.join(Directory.current.path, 'shared');
     final memPath = p.join(Directory.current.path, 'mem');

    _fileService = FileSyncService(
      sharedPath: sharedPath,
      memPath: memPath);
    _fileService.init();
  }

  @override
  void dispose() {
    _fileService.dispose();
    super.dispose();
  }

  // Simulace nahrání do DB
  Future<void> _uploadToDb(String fileName) async {
    if (_dbConfig['host']!.isEmpty) {
      _showSnackBar('Nejdříve nastavte DB připojení!');
      return;
    }

    // Načtení obsahu SQL souboru
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

      _showSnackBar('$fileName úspěšně nahrán!');
    } catch (e) {
      _showSnackBar('Chyba: $e', isError: true);
    }

    if (mounted) {
      _showSnackBar('$fileName úspěšně nahrán!');
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
  await conn.execute(sql);
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
    settings: const ConnectionSettings(sslMode: SslMode.disable),
  );
  await connection.execute(sql);
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
          // Tlačítko pro nastavení DB v pravém horním rohu
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
            return const Center(child: Text('Čekám na .sql soubory v /shared...'));
          }

          final items = snapshot.data!;
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final key = items.keys.elementAt(index);
              final meta = items[key];
              
              return Card(
                margin: const EdgeInsets.all(8),
                child: ListTile(
                  leading: const Icon(Icons.storage, color: Colors.blue),
                  title: Text(meta['displayName']),
                  subtitle: Text(meta['desc']),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.upload, color: Colors.green),
                        onPressed: () => _uploadToDb(key),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _showEditDialog(key, meta),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: ()=> _confirmDelete(key),
                      )
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
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
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
            TextField(controller: hostCtrl, decoration: const InputDecoration(labelText: 'Host (IP/Doména)')),
            TextField(controller: userCtrl, decoration: const InputDecoration(labelText: 'Uživatel')),
            TextField(controller: passCtrl, decoration: const InputDecoration(labelText: 'Heslo'), obscureText: true),
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
                };
              });
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

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Editovat metadata: $key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Zobrazované jméno')),
            TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Popis')),
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
