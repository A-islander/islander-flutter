import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../main.dart';

class PlateScreen extends ConsumerStatefulWidget {
  final int plateId;

  const PlateScreen({super.key, required this.plateId});

  @override
  ConsumerState<PlateScreen> createState() => _PlateScreenState();
}

class _PlateScreenState extends ConsumerState<PlateScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(plateProvider.notifier).fetchPlates());
  }

  @override
  Widget build(BuildContext context) {
    final plateState = ref.watch(plateProvider);
    final plateName = widget.plateId == 0
        ? '时间线'
        : ref.read(plateProvider.notifier).getPlateName(widget.plateId);

    return Scaffold(
      appBar: AppBar(title: Text(plateName)),
      body: plateState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : plateState.error != null
              ? Center(child: Text('Error: ${plateState.error}'))
              : const Center(child: Text('板块帖子列表（开发中）')),
      floatingActionButton: FloatingActionButton(
        shape: const CircleBorder(),
        onPressed: () {},
        child: const Icon(Icons.edit),
      ),
    );
  }
}
