import 'package:gym_api/entities/point_entity.dart';

class ChildEntity {
  final String name;
  final String id;
  final List<PointEntity> points;
  ChildEntity({
    required this.id,
    required this.name,
    required this.points,
  });

  @override
  String toString() {
    return 'ChildEntity(id: $id, name: $name points: $points)';
  }
}
