import 'package:objectbox/objectbox.dart';

@Entity()
class Song {
  @Id()
  int id = 0;

  String title;
  String artist;
  String filePath;
  int durationMs;
  String? albumArt;

  Song({
    this.id = 0,
    required this.title,
    this.artist = 'Unknown Artist',
    required this.filePath,
    this.durationMs = 0,
    this.albumArt,
  });

  @override
  String toString() => 'Song(id: $id, title: $title, artist: $artist)';
}
