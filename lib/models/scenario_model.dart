import 'package:yaml/yaml.dart';

class Scenario {
  final String id;
  final String title;
  final String description;
  final String thumbnail;
  final List<String> equipment; // list of equipment IDs

  Scenario({
    required this.id,
    required this.title,
    required this.description,
    required this.thumbnail,
    required this.equipment,
  });

  factory Scenario.fromYaml(YamlMap yaml) => Scenario(
    id: yaml['id'] as String,
    title: yaml['title'] as String,
    description: yaml['description'] as String,
    thumbnail: yaml['thumbnail'] as String,
    equipment: List<String>.from(yaml['equipment'] ?? []),
  );
}
