import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

void main() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: const BackupDashboard(),
    ),
  );
}

class BackupDashboard extends StatefulWidget {
  const BackupDashboard({super.key});

  @override
  _BackupDashboardState createState() => _BackupDashboardState();
}

class _BackupDashboardState extends State<BackupDashboard> {
  String? pythonScriptPath;
  bool isRunning = false;
  bool isInitializing = true;

  final String configPath = "D:/Games/config.json";
  final String backupRoot = "D:/Games";

  @override
  void initState() {
    super.initState();
    _setupBackend();
  }

  Future<void> _setupBackend() async {
    final dir = Directory(backupRoot);
    if (!await dir.exists()) await dir.create(recursive: true);

    final configFile = File(configPath);
    if (!await configFile.exists()) {
      await configFile.writeAsString(jsonEncode({"games": []}));
    }

    pythonScriptPath = 'D:/Games/backup_tool.py';
    setState(() => isInitializing = false);
  }

  Future<Map<String, dynamic>> _loadConfig() async {
    final file = File(configPath);
    try {
      final content = await file.readAsString();
      return jsonDecode(content);
    } catch (e) {
      return {"games": []};
    }
  }

  Future<void> _saveConfig(Map<String, dynamic> config) async {
    await File(
      configPath,
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(config));
    setState(() {});
  }

  Future<void> _addGame(String name, String path) async {
    final config = await _loadConfig();
    (config['games'] as List).add({
      "name": name,
      "path": path,
      "last_hash": "",
      "last_backup": "",
      "last_zipped": "",
      "size": "Unknown",
    });
    await _saveConfig(config);
  }

  Future<void> _openBackupDir(String gameName) async {
    final path = "$backupRoot/$gameName".replaceAll('/', '\\');
    final dir = Directory(path);

    if (await dir.exists()) {
      await Process.run('explorer.exe', [path]);
    } else {
      _showMsg(
        "Backup directory does not exist yet. Run a backup first.",
        isError: true,
      );
    }
  }

  Future<void> _runProcess({String? forceTarget, String? zipTarget}) async {
    if (pythonScriptPath == null) return;

    setState(() => isRunning = true);
    try {
      List<String> args = [pythonScriptPath!];
      if (forceTarget != null) args.addAll(['--force', forceTarget]);
      if (zipTarget != null) args.addAll(['--zip', zipTarget]);

      final result = await Process.run(
        'python',
        args,
        workingDirectory: backupRoot,
      );

      if (result.exitCode == 0) {
        _showMsg("Operation Successful");
      } else {
        _showMsg("Error: ${result.stderr}", isError: true);
      }
    } catch (e) {
      _showMsg("Failed to run Python: $e", isError: true);
    } finally {
      setState(() => isRunning = false);
    }
  }

  void _showMsg(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isInitializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Game Backup Manager"),
        centerTitle: false, // Moved title to left to make room for buttons
        actions: [
          IconButton(
            icon: const Icon(Icons.add_box_rounded, color: Colors.indigoAccent),
            onPressed: () => _showAddDialog(),
            tooltip: "Add New Game",
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
            tooltip: "Refresh List",
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _buildActionHeader(),
          if (isRunning) const LinearProgressIndicator(),
          Expanded(child: _buildGameList()),
        ],
      ),
    );
  }

  // Horizontal scaling logic: Using Wrap instead of Row/Expanded
  Widget _buildActionHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      color: Colors.white.withOpacity(0.05),
      child: Wrap(
        spacing: 10, // horizontal gap
        runSpacing: 10, // vertical gap if wrapped
        alignment: WrapAlignment.start,
        children: [
          _headerBtn(
            "Sync All",
            Icons.sync,
            Colors.green[800]!,
            () => _runProcess(),
          ),
          _headerBtn(
            "Force All",
            Icons.bolt,
            Colors.orange[900]!,
            () => _runProcess(forceTarget: 'all'),
          ),
          _headerBtn(
            "Zip All",
            Icons.folder_zip,
            Colors.blue[800]!,
            () => _runProcess(zipTarget: 'all'),
          ),
        ],
      ),
    );
  }

  Widget _headerBtn(
    String label,
    IconData icon,
    Color col,
    VoidCallback? action,
  ) {
    return ElevatedButton.icon(
      onPressed: isRunning ? null : action,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 13)),
      style: ElevatedButton.styleFrom(
        backgroundColor: col,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Widget _buildGameList() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _loadConfig(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();
        final games = snapshot.data!['games'] as List;
        if (games.isEmpty)
          return const Center(child: Text("No games configured."));

        return ListView.builder(
          padding: const EdgeInsets.all(10),
          itemCount: games.length,
          itemBuilder: (context, i) {
            final game = games[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(
                        Icons.sports_esports,
                        size: 40,
                        color: Colors.indigo,
                      ),
                      title: Text(
                        game['name'],
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      subtitle: Text(
                        "Source: ${game['path']}\n"
                        "Size: ${game['size'] ?? 'N/A'}\n"
                        "Last Backup: ${game['last_backup']}\n"
                        "Last Zipped: ${game['last_zipped'] ?? 'Never'}",
                      ),
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        TextButton.icon(
                          onPressed: () => _openBackupDir(game['name']),
                          icon: const Icon(Icons.visibility, size: 18),
                          label: const Text("View Files"),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.grey[400],
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: isRunning
                              ? null
                              : () => _runProcess(forceTarget: game['name']),
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text("Force Folder"),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: isRunning
                              ? null
                              : () => _runProcess(zipTarget: game['name']),
                          icon: const Icon(Icons.archive, size: 18),
                          label: const Text("Force Zip"),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.blueAccent,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showAddDialog() {
    final nameCtrl = TextEditingController();
    final pathCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Add New Game"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: "Game Name"),
            ),
            TextField(
              controller: pathCtrl,
              decoration: const InputDecoration(labelText: "Full Source Path"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.isNotEmpty && pathCtrl.text.isNotEmpty) {
                _addGame(nameCtrl.text, pathCtrl.text);
                Navigator.pop(ctx);
              }
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }
}
