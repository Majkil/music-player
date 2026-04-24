import 'package:flutter/material.dart';
import '../models/excluded_folder.dart';
import '../services/objectbox_service.dart';

class ExcludedFoldersScreen extends StatefulWidget {
  final ObjectBoxService objectBoxService;

  const ExcludedFoldersScreen({super.key, required this.objectBoxService});

  @override
  State<ExcludedFoldersScreen> createState() => _ExcludedFoldersScreenState();
}

class _ExcludedFoldersScreenState extends State<ExcludedFoldersScreen> {
  List<ExcludedFolder> _excludedFolders = [];

  @override
  void initState() {
    super.initState();
    _loadExcluded();
  }

  void _loadExcluded() {
    setState(() {
      _excludedFolders = widget.objectBoxService.getExcludedFolders();
    });
  }

  void _removeExclusion(String path) {
    widget.objectBoxService.includeFolder(path);
    _loadExcluded();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Folder re-included: $path')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        title: const Text('Excluded Folders'),
        backgroundColor: const Color(0xFF1A1A2E),
      ),
      body: _excludedFolders.isEmpty
          ? const Center(child: Text('No excluded folders', style: TextStyle(color: Colors.white54)))
          : ListView.builder(
              itemCount: _excludedFolders.length,
              itemBuilder: (context, index) {
                final folder = _excludedFolders[index];
                return ListTile(
                  leading: const Icon(Icons.folder_off, color: Colors.orangeAccent),
                  title: Text(folder.path, style: const TextStyle(color: Colors.white), overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    onPressed: () => _removeExclusion(folder.path),
                  ),
                );
              },
            ),
    );
  }
}
