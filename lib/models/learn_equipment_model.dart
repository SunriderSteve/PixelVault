import 'package:yaml/yaml.dart';

class Equipment {
  final String id;
  final String name;
  final String category;
  final String description;
  final String storage;
  final Map<String, String> functions;
  final List<String> images;
  final List<String> related;

  Equipment({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.storage,
    required this.functions,
    required this.images,
    required this.related,
  });

  /// Factory constructor that converts a loaded YAML map into an Equipment object
  factory Equipment.fromYaml(YamlMap yaml) {
    return Equipment(
      id: yaml['id'] as String,
      name: yaml['name'] as String,
      category: yaml['category'] as String,
      description: yaml['description'] as String,
      storage: yaml['storage'] as String,
      functions: Map<String, String>.from(yaml['functions'] ?? {}),
      images: List<String>.from(yaml['images'] ?? []),
      related: List<String>.from(yaml['related'] ?? []),
    );
  }
}
