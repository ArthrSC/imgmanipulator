import 'package:flutter/material.dart';
import 'ui/home_page.dart';

void main() => runApp(const ImgManipulatorApp());

class ImgManipulatorApp extends StatelessWidget {
  const ImgManipulatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ImgManipulator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      darkTheme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          useMaterial3: true,
          brightness: Brightness.dark),
      home: const HomePage(),
    );
  }
}
