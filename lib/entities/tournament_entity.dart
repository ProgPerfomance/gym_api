
import 'package:gym_api/entities/set_entity.dart';

class TournamentEntity {
  final String name;
  final String? activeSetId;
  final List<SetEntity> sets;

  TournamentEntity({
    this.activeSetId,
    required this.name,
    required this.sets,
  });

  @override
  String toString() {
    return '''
TournamentEntity(
  name: $name,
  sets: [${sets.map((s) => s.toString()).join(',\n')}]
)''';
  }
}
