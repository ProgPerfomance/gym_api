import 'child_entity.dart';

class ItemEntity {
  final String? activeChild;
  final String id;
  final List<ChildEntity> childrens;

  ItemEntity({
    required this.childrens,
    required this.id,
    this.activeChild,
  });

  @override
  String toString() {
    return '''
ItemEntity(
  id: $id,
  childrens: [${childrens.map((c) => c.toString()).join(', ')}]
)''';
  }
}
