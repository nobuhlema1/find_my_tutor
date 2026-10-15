import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Find My Tutor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue)),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _status = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _testDatabase();
  }

  Future<void> _testDatabase() async {
    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'test.db');
      final db = await openDatabase(
        path,
        version: 1,
        onCreate: (db, version) async {
          await db.execute(
              'CREATE TABLE test(id INTEGER PRIMARY KEY, name TEXT)');
        },
      );
      await db.insert('test', {'name': 'SQLite works!'});
      final result = await db.query('test');
      setState(() => _status = 'DB OK: ${result.first['name']}');
    } catch (e) {
      setState(() => _status = 'DB Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.school, size: 100, color: Colors.blue),
            const SizedBox(height: 20),
            const Text('Find My Tutor',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(_status, textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }
}