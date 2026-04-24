import 'package:objectbox/objectbox.dart';

@Entity()
class ExcludedFolder {
  @Id()
  int id = 0;
  
  @Index()
  String path;

  ExcludedFolder({this.id = 0, required this.path});
}
