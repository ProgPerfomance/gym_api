class PointEntity {
  final double point;
  final String master;

  PointEntity({
    required this.master,
    required this.point,
  });

  @override
  String toString() {
    return 'PointEntity(master: $master, point: $point)';
  }
}
