import 'package:flutter/material.dart';
import 'package:sqflite_learning/first_db/first_db.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await myFirstDatabase();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(title: 'Sqflite learning');
  }
}
