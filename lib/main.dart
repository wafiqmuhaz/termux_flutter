import 'package:flutter/material.dart';

import 'platform/shell_bridge.dart';
import 'terminal/terminal_controller.dart';
import 'terminal/terminal_widget.dart';

void main() {
  runApp(const TermuxFlutterApp());
}

class TermuxFlutterApp extends StatefulWidget {
  const TermuxFlutterApp({super.key});

  @override
  State<TermuxFlutterApp> createState() => _TermuxFlutterAppState();
}

class _TermuxFlutterAppState extends State<TermuxFlutterApp> {
  late final TerminalController controller;

  @override
  void initState() {
    super.initState();
    controller = TerminalController(ShellBridge());
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xff111111),
        body: SafeArea(
          child: TerminalWidget(controller: controller),
        ),
      ),
    );
  }
}
