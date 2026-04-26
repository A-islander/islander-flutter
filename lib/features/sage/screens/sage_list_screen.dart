import 'package:flutter/material.dart';

class SageListScreen extends StatelessWidget {
  const SageListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('看看你都干了什么？')),
      body: const Center(child: Text('Sage 列表（开发中）')),
    );
  }
}
