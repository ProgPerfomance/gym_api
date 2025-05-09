import 'item_entity.dart';

class SetEntity {
  final String? activeItem;
  final String id;
  final List<ItemEntity> items;

  SetEntity({
    required this.id,
    required this.items,
    this.activeItem,
  });

  @override
  String toString() {
    return '''
SetEntity(
  id: $id,
  items: [${items.map((i) => i.toString()).join(',\n')}]
)''';
  }
}
