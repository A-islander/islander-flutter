import 'package:flutter/material.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('在？看看饼？')),
      body: const Center(child: Text('Cookie 管理（开发中）')),
    );
  }
}
