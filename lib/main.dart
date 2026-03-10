import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'services/file_sync_service.dart';

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
  
  // Dočasné uložení login údajů (v produkci použij flutter_secure_storage)
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nejdříve nastavte DB připojení!')),
      );
      return;
    }

    // Načtení obsahu SQL souboru
    final file = File(p.join(_fileService.sharedPath, fileName));
    final sql = await file.readAsString();

    debugPrint('Nahrávám na ${_dbConfig['host']} uživatelem ${_dbConfig['user']}...');
    debugPrint('SQL kód: ${sql.substring(0, sql.length > 30 ? 30 : sql.length)}...');

    // TODO: Zde použijte balíček 'postgres' nebo 'mysql_client'
    await Future.delayed(const Duration(seconds: 1)); // Simulace sítě

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$fileName úspěšně nahrán!')),
      );
    }
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
                        icon: const Icon(Icons.edit),
                        onPressed: () => _showEditDialog(key, meta),
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

  void _showDbSettings() {
    final hostCtrl = TextEditingController(text: _dbConfig['host']);
    final userCtrl = TextEditingController(text: _dbConfig['user']);
    final passCtrl = TextEditingController(text: _dbConfig['pass']);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Konfigurace DB'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                _dbConfig = {'host': hostCtrl.text, 'user': userCtrl.text, 'pass': passCtrl.text};
              });
              Navigator.pop(ctx);
            },
            child: const Text('Uložit'),
          ),
        ],
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
