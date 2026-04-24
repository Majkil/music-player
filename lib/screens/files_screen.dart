import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:audiotags/audiotags.dart';
import 'package:path/path.dart' as p;
import '../models/song.dart';
import '../models/excluded_folder.dart';
import '../services/objectbox_service.dart';
import '../services/audio_handler.dart';
import 'player_screen.dart';
import 'excluded_folders_screen.dart';

class FilesScreen extends StatefulWidget {
  final MusicAudioHandler audioHandler;
  final ObjectBoxService objectBoxService;

  const FilesScreen({
    super.key,
    required this.audioHandler,
    required this.objectBoxService,
  });

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Song> _songs = [];
  bool _isLoading = false;
  final Set<int> _selectedIds = {};
  bool _isSelectionMode = false;

  static const _supportedExtensions = [
    '.mp3',
    '.m4a',
    '.wav',
    '.flac',
    '.ogg',
    '.aac',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadSongsFromDb();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadSongsFromDb() {
    setState(() {
      _songs = widget.objectBoxService.getAllSongs();
    });
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      if (await Permission.audio.request().isGranted ||
          await Permission.storage.request().isGranted ||
          await Permission.manageExternalStorage.request().isGranted) {
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Storage permissions are required for syncing'),
          ),
        );
      }
    }
  }

  Future<void> _pickDirectory() async {
    await _requestPermissions();
    final selectedDir = await FilePicker.getDirectoryPath();
    if (selectedDir != null) {
      setState(() => _isLoading = true);
      await _scanFolder(selectedDir);
      setState(() => _isLoading = false);
      _loadSongsFromDb();
    }
  }

  Future<void> _syncMusic() async {
    await _requestPermissions();
    setState(() => _isLoading = true);

    try {
      final List<String> pathsToScan = [
        '/storage/emulated/0/Music',
        '/storage/emulated/0/Download',
        '/storage/emulated/0/Audio',
      ];

      for (var path in pathsToScan) {
        await _scanFolder(path);
      }

      _loadSongsFromDb();
    } catch (e) {
      debugPrint('Sync error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _scanFolder(String path) async {
    final dir = Directory(path);
    if (!dir.existsSync()) return;

    final excludedFolders = widget.objectBoxService
        .getExcludedFolders()
        .map((e) => e.path)
        .toList();
    final List<Song> foundSongs = [];
    final cacheDir = await getTemporaryDirectory();

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final filePath = entity.path;
        if (excludedFolders.any((excluded) => filePath.startsWith(excluded)))
          continue;

        final ext = p.extension(filePath).toLowerCase();
        if (_supportedExtensions.contains(ext)) {
          final existingSong = widget.objectBoxService.getSongByPath(filePath);
          if (existingSong == null || existingSong.albumArt == null) {
            String title = p.basenameWithoutExtension(filePath);
            String artist = 'Unknown Artist';
            String? artworkPath;

            try {
              final tags = await AudioTags.read(filePath);
              if (tags != null) {
                if (tags.title != null && tags.title!.isNotEmpty)
                  title = tags.title!;
                if (tags.trackArtist != null && tags.trackArtist!.isNotEmpty)
                  artist = tags.trackArtist!;

                if (tags.pictures.isNotEmpty) {
                  final hash = md5.convert(utf8.encode(filePath)).toString();
                  final artFile = File('${cacheDir.path}/art_$hash.jpg');
                  await artFile.writeAsBytes(tags.pictures.first.bytes);
                  artworkPath = artFile.path;
                }
              }
            } catch (e) {
              debugPrint('Error reading tags for $filePath: $e');
            }

            if (existingSong != null) {
              existingSong.title = title;
              existingSong.artist = artist;
              existingSong.albumArt = artworkPath;
              widget.objectBoxService.putSongs([existingSong]);
            } else {
              foundSongs.add(
                Song(
                  title: title,
                  artist: artist,
                  filePath: filePath,
                  albumArt: artworkPath,
                ),
              );
            }
          }
        }
      }
    }

    if (foundSongs.isNotEmpty) {
      widget.objectBoxService.putSongs(foundSongs);
    }
  }

  void _playSong(Song song) async {
    final mediaItems = _songs.map((s) {
      return MediaItem(
        id: s.filePath,
        title: s.title,
        artist: s.artist,
        artUri: s.albumArt != null ? Uri.file(s.albumArt!) : null,
      );
    }).toList();

    final initialIndex = _songs.indexWhere((s) => s.filePath == song.filePath);
    await widget.audioHandler.loadQueue(mediaItems, initialIndex: initialIndex);
    await widget.audioHandler.play();

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerScreen(audioHandler: widget.audioHandler),
        ),
      );
    }
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.add(id);
        _isSelectionMode = true;
      }
    });
  }

  void _deleteSelected() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Songs'),
        content: Text('Remove ${_selectedIds.length} songs from the library?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              widget.objectBoxService.removeSongs(_selectedIds.toList());
              setState(() {
                _selectedIds.clear();
                _isSelectionMode = false;
              });
              _loadSongsFromDb();
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      drawer: _buildDrawer(),
      appBar: AppBar(
        title: _isSelectionMode
            ? Text('${_selectedIds.length} selected')
            : const Text('Music Player'),
        backgroundColor: const Color(0xFF1A1A2E),
        actions: [
          if (_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.redAccent),
              onPressed: _deleteSelected,
            )
          else
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () {
                showSearch(
                  context: context,
                  delegate: SongSearchDelegate(
                    objectBoxService: widget.objectBoxService,
                    onSongSelect: _playSong,
                  ),
                );
              },
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF6C63FF),
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Folders'),
            Tab(text: 'Artists'),
          ],
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabController,
            children: [
              _AllSongsTab(
                songs: _songs,
                selectedIds: _selectedIds,
                isSelectionMode: _isSelectionMode,
                onTap: _playSong,
                onLongPress: _toggleSelection,
              ),
              _FoldersTab(
                songs: _songs,
                objectBoxService: widget.objectBoxService,
                onFolderExclude: (path) {
                  widget.objectBoxService.excludeFolder(path);
                  _loadSongsFromDb();
                },
              ),
              _ArtistsTab(songs: _songs, onTap: _playSong),
            ],
          ),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
            ),
        ],
      ),
      bottomNavigationBar: _buildMiniPlayer(),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF1A1A2E),
      child: ListView(
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Color(0xFF6C63FF)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'Music Player',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text('v1.1.0', style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.folder_open, color: Colors.white),
            title: const Text(
              'Pick Folder',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Manually select a folder to scan',
              style: TextStyle(color: Colors.white60),
            ),
            onTap: () {
              Navigator.pop(context);
              _pickDirectory();
            },
          ),
          ListTile(
            leading: const Icon(Icons.sync, color: Colors.white),
            title: const Text(
              'Sync Music',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Scan device for new files',
              style: TextStyle(color: Colors.white60),
            ),
            onTap: () {
              Navigator.pop(context);
              _syncMusic();
            },
          ),
          ListTile(
            leading: const Icon(Icons.folder_off, color: Colors.white),
            title: const Text(
              'Excluded Folders',
              style: TextStyle(color: Colors.white),
            ),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ExcludedFoldersScreen(
                    objectBoxService: widget.objectBoxService,
                  ),
                ),
              ).then((_) => _loadSongsFromDb());
            },
          ),
          const Divider(color: Colors.white24),
          ListTile(
            leading: const Icon(Icons.settings, color: Colors.white),
            title: const Text(
              'Settings',
              style: TextStyle(color: Colors.white),
            ),
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget? _buildMiniPlayer() {
    return StreamBuilder<MediaItem?>(
      stream: widget.audioHandler.mediaItem,
      builder: (context, snapshot) {
        final mediaItem = snapshot.data;
        if (mediaItem == null) return const SizedBox.shrink();

        return StreamBuilder<PlaybackState>(
          stream: widget.audioHandler.playbackState,
          builder: (context, stateSnapshot) {
            final playing = stateSnapshot.data?.playing ?? false;
            if (stateSnapshot.data?.processingState ==
                AudioProcessingState.idle) {
              return const SizedBox.shrink();
            }

            return GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      PlayerScreen(audioHandler: widget.audioHandler),
                ),
              ),
              child: Container(
                height: 64,
                decoration: const BoxDecoration(
                  color: Color(0xFF1A1A2E),
                  border: Border(
                    top: BorderSide(color: Color(0xFF6C63FF), width: 1),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(4),
                        image: mediaItem.artUri != null
                            ? DecorationImage(
                                image: FileImage(
                                  File(mediaItem.artUri!.toFilePath()),
                                ),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: mediaItem.artUri == null
                          ? const Icon(
                              Icons.music_note,
                              color: Color(0xFF6C63FF),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        mediaItem.title,
                        style: const TextStyle(color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        playing ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                      ),
                      onPressed: playing
                          ? widget.audioHandler.pause
                          : widget.audioHandler.play,
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
}

class _AllSongsTab extends StatelessWidget {
  final List<Song> songs;
  final Set<int> selectedIds;
  final bool isSelectionMode;
  final Function(Song) onTap;
  final Function(int) onLongPress;

  const _AllSongsTab({
    required this.songs,
    required this.selectedIds,
    required this.isSelectionMode,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty)
      return const Center(
        child: Text('No songs found', style: TextStyle(color: Colors.white54)),
      );

    return ListView.builder(
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final song = songs[index];
        final isSelected = selectedIds.contains(song.id);

        return ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF6C63FF) : Colors.white10,
              borderRadius: BorderRadius.circular(8),
              image: song.albumArt != null
                  ? DecorationImage(
                      image: FileImage(File(song.albumArt!)),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: isSelected
                ? const Icon(Icons.check, color: Colors.white)
                : (song.albumArt == null
                      ? const Icon(Icons.music_note, color: Colors.white)
                      : null),
          ),
          title: Text(song.title, style: const TextStyle(color: Colors.white)),
          subtitle: Text(
            song.artist,
            style: const TextStyle(color: Colors.white60),
          ),
          onTap: () => isSelectionMode ? onLongPress(song.id) : onTap(song),
          onLongPress: () => onLongPress(song.id),
          selected: isSelected,
          selectedTileColor: Colors.white.withAlpha(10),
        );
      },
    );
  }
}

class _FoldersTab extends StatelessWidget {
  final List<Song> songs;
  final ObjectBoxService objectBoxService;
  final Function(String) onFolderExclude;

  const _FoldersTab({
    required this.songs,
    required this.objectBoxService,
    required this.onFolderExclude,
  });

  @override
  Widget build(BuildContext context) {
    final Map<String, List<Song>> folderGroups = {};
    for (var song in songs) {
      final folder = p.dirname(song.filePath);
      folderGroups.putIfAbsent(folder, () => []).add(song);
    }

    final folders = folderGroups.keys.toList()..sort();

    return ListView.builder(
      itemCount: folders.length,
      itemBuilder: (context, index) {
        final folderPath = folders[index];
        final folderName = p.basename(folderPath);
        final folderSongs = folderGroups[folderPath]!;
        final count = folderSongs.length;

        // Find first song with artwork
        final songWithArt = folderSongs.firstWhere(
          (s) => s.albumArt != null,
          orElse: () => folderSongs.first,
        );

        return ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(4),
              image: songWithArt.albumArt != null
                  ? DecorationImage(
                      image: FileImage(File(songWithArt.albumArt!)),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: songWithArt.albumArt == null
                ? const Icon(Icons.folder, color: Color(0xFF6C63FF))
                : null,
          ),
          title: Text(folderName, style: const TextStyle(color: Colors.white)),
          subtitle: Text(
            folderPath,
            style: const TextStyle(color: Colors.white60),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(
            '$count',
            style: const TextStyle(color: Colors.white38),
          ),
          onLongPress: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Exclude Folder'),
                content: const Text(
                  'Do you want to exclude this folder from scanning?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () {
                      onFolderExclude(folderPath);
                      Navigator.pop(context);
                    },
                    child: const Text(
                      'Exclude',
                      style: TextStyle(color: Colors.orange),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ArtistsTab extends StatelessWidget {
  final List<Song> songs;
  final Function(Song) onTap;

  const _ArtistsTab({required this.songs, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final Map<String, List<Song>> artistGroups = {};
    for (var song in songs) {
      artistGroups.putIfAbsent(song.artist, () => []).add(song);
    }

    final artists = artistGroups.keys.toList()..sort();

    return ListView.builder(
      itemCount: artists.length,
      itemBuilder: (context, index) {
        final artist = artists[index];
        final artistSongs = artistGroups[artist]!;

        // Find first song with artwork
        final songWithArt = artistSongs.firstWhere(
          (s) => s.albumArt != null,
          orElse: () => artistSongs.first,
        );

        return ExpansionTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(20), // Circular for artists
              image: songWithArt.albumArt != null
                  ? DecorationImage(
                      image: FileImage(File(songWithArt.albumArt!)),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: songWithArt.albumArt == null
                ? const Icon(Icons.person, color: Color(0xFFE91E63))
                : null,
          ),
          title: Text(artist, style: const TextStyle(color: Colors.white)),
          subtitle: Text(
            '${artistSongs.length} songs',
            style: const TextStyle(color: Colors.white54),
          ),
          children: artistSongs
              .map(
                (song) => ListTile(
                  leading: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(4),
                      image: song.albumArt != null
                          ? DecorationImage(
                              image: FileImage(File(song.albumArt!)),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: song.albumArt == null
                        ? const Icon(
                            Icons.music_note,
                            color: Colors.white54,
                            size: 16,
                          )
                        : null,
                  ),
                  title: Text(
                    song.title,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  onTap: () => onTap(song),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class SongSearchDelegate extends SearchDelegate {
  final ObjectBoxService objectBoxService;
  final Function(Song) onSongSelect;

  SongSearchDelegate({
    required this.objectBoxService,
    required this.onSongSelect,
  });

  @override
  ThemeData appBarTheme(BuildContext context) {
    return Theme.of(context).copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        hintStyle: TextStyle(color: Colors.white54),
      ),
      textTheme: const TextTheme(titleLarge: TextStyle(color: Colors.white)),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    final results = objectBoxService.searchSongs(query);
    if (results.isEmpty) {
      return const Center(
        child: Text('No songs found', style: TextStyle(color: Colors.white54)),
      );
    }

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final song = results[index];
        return ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(4),
              image: song.albumArt != null
                  ? DecorationImage(
                      image: FileImage(File(song.albumArt!)),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: song.albumArt == null
                ? const Icon(Icons.music_note, color: Color(0xFF6C63FF))
                : null,
          ),
          title: Text(song.title, style: const TextStyle(color: Colors.white)),
          subtitle: Text(
            song.artist,
            style: const TextStyle(color: Colors.white60),
          ),
          onTap: () {
            onSongSelect(song);
            close(context, null);
          },
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.isEmpty) {
      return const Center(
        child: Text(
          'Search by title or artist',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }
    return buildResults(context);
  }
}
