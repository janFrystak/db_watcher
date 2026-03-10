import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

void main() => runApp(MaterialApp(home: SqlManagerScreen()));

class SqlManagerScreen extends StatefulWidget {
  const SqlManagerScreen({super.key}); 

  @override
  State<SqlManagerScreen> createState() => _SqlManagerScreenState();
}


class _SqlManagerScreenState extends State<SqlManagerScreen> {
  final String sharedPath = p.join(Directory.current.path, '../shared');
  late StreamController<Map<String, dynamic>> _metadataController;
  late DirectoryWatcher _watcher;

  @override
  void initState() {
    super.initState();
    _metadataController = StreamController.broadcast();
    _initWatcher();
    _loadMetadata(); // Načíst data při startu
  }

  void _initWatcher() {
    _watcher = DirectoryWatcher(sharedPath);
    _watcher.events.listen((event) async {
      if (event.path.endsWith('.sql') || event.path.endsWith('metadata.json')) {
        await _handleFileChange(event);
      }
    });
  }

  Future<void> _handleFileChange(WatchEvent event) async {
    final metadataFile = File(p.join(sharedPath, 'metadata.json'));
    
    // Pokud přibyl SQL, dopíšeme ho do JSONu (pokud tam není)
    if (event.type == ChangeType.ADD && event.path.endsWith('.sql')) {
      Map<String, dynamic> data = await _readJson(metadataFile);
      String name = p.basename(event.path);
      if (!data.containsKey(name)) {
        data[name] = {
          'displayName': name,
          'date': DateTime.now().toString().split('.')[0],
          'desc': 'Nový soubor...'
        };
        await metadataFile.writeAsString(jsonEncode(data));
      }
    }
    _loadMetadata(); // Refresh streamu pro UI
  }

  Future<void> _loadMetadata() async {
    final file = File(p.join(sharedPath, 'metadata.json'));
    _metadataController.add(await _readJson(file));
  }

  Future<Map<String, dynamic>> _readJson(File file) async {
    if (!await file.exists()) return {};
    return jsonDecode(await file.readAsString());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('SQL Manager'),
        actions: [
          IconButton(icon: Icon(Icons.login), onPressed: () => _showLogin(context)),
        ],
      ),
      body: StreamBuilder<Map<String, dynamic>>(
        stream: _metadataController.stream,
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(child: Text('Žádné SQL soubory nenalezeny'));
          }
          final items = snapshot.data!;
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              String key = items.keys.elementAt(index);
              var item = items[key];
              return Card(
                margin: EdgeInsets.all(8),
                child: ListTile(
                  title: Text(item['displayName']),
                  subtitle: Text("${item['date']} - ${item['desc']}"),
                  trailing: Icon(Icons.edit),
                  onTap: () => /* TODO: Otevřít editaci */ print("Edit $key"),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showLogin(BuildContext context) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text("DB Login"),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(decoration: InputDecoration(labelText: "Host")),
          TextField(decoration: InputDecoration(labelText: "User")),
          TextField(decoration: InputDecoration(labelText: "Pass", ), obscureText: true),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text("Save"))],
      ),
    );
  }
}
