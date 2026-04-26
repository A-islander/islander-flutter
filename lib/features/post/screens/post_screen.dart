import 'package:flutter/material.dart';

class PostScreen extends StatelessWidget {
  final int postId;

  const PostScreen({super.key, required this.postId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('看串中')),
      body: Center(child: Text('帖子详情 #$postId（开发中）')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: '说点什么...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.send, color: Color(0xFF4DB6AC)),
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }
}
