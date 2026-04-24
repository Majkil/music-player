import 'package:path_provider/path_provider.dart';
import '../models/song.dart';
import '../models/excluded_folder.dart';
import '../objectbox.g.dart';

class ObjectBoxService {
  late final Store _store;
  late final Box<Song> _songBox;
  late final Box<ExcludedFolder> _excludedBox;

  static ObjectBoxService? _instance;

  ObjectBoxService._();

  static Future<ObjectBoxService> getInstance() async {
    if (_instance != null) return _instance!;
    _instance = ObjectBoxService._();
    await _instance!._init();
    return _instance!;
  }

  Future<void> _init() async {
    final dir = await getApplicationDocumentsDirectory();
    final storePath = '${dir.path}/objectbox';

    if (Store.isOpen(storePath)) {
      _store = Store.attach(getObjectBoxModel(), storePath);
    } else {
      _store = await openStore(directory: storePath);
    }

    _songBox = _store.box<Song>();
    _excludedBox = _store.box<ExcludedFolder>();
  }

  Box<Song> get songBox => _songBox;
  Box<ExcludedFolder> get excludedBox => _excludedBox;
  Store get store => _store;

  /// Add or update songs in the database
  void putSongs(List<Song> songs) {
    _songBox.putMany(songs);
  }

  /// Get all songs from the database sorted by title
  List<Song> getAllSongs() {
    final query = _songBox.query().order(Song_.title).build();
    final songs = query.find();
    query.close();
    return songs;
  }

  /// Clear all songs
  void clearSongs() {
    _songBox.removeAll();
  }

  /// Remove specific songs by ID
  void removeSongs(List<int> ids) {
    _songBox.removeMany(ids);
  }

  /// Find a song by file path
  Song? getSongByPath(String filePath) {
    final query = _songBox.query(Song_.filePath.equals(filePath)).build();
    final result = query.findFirst();
    query.close();
    return result;
  }

  /// Search for songs by title or artist
  List<Song> searchSongs(String queryText) {
    final query = _songBox
        .query(
          Song_.title
              .contains(queryText, caseSensitive: false)
              .or(Song_.artist.contains(queryText, caseSensitive: false)),
        )
        .build();
    final results = query.find();
    query.close();
    return results;
  }

  /// Check if a folder is excluded
  bool isFolderExcluded(String folderPath) {
    final query = _excludedBox
        .query(ExcludedFolder_.path.equals(folderPath))
        .build();
    final exists = query.count() > 0;
    query.close();
    return exists;
  }

  /// Add a folder to excluded list
  void excludeFolder(String folderPath) {
    if (!isFolderExcluded(folderPath)) {
      _excludedBox.put(ExcludedFolder(path: folderPath));
    }
  }

  /// Remove a folder from excluded list
  void includeFolder(String folderPath) {
    final query = _excludedBox
        .query(ExcludedFolder_.path.equals(folderPath))
        .build();
    final folder = query.findFirst();
    if (folder != null) {
      _excludedBox.remove(folder.id);
    }
    query.close();
  }

  /// Get list of all excluded folders
  List<ExcludedFolder> getExcludedFolders() {
    return _excludedBox.getAll();
  }

  void close() {
    _store.close();
  }
}
