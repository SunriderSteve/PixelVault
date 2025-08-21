import 'package:yaml/yaml.dart';

class ScenarioSection {
  final String title;
  final List<String> images;
  final String body;

  const ScenarioSection({
    required this.title,
    required this.images,
    required this.body,
  });

  factory ScenarioSection.fromYaml(YamlMap m) => ScenarioSection(
    title: (m['title'] as String?) ?? '',
    images: List<String>.from(m['images'] ?? const []),
    body: (m['body'] as String?) ?? '',
  );
}

class ScenarioGuide {
  final String id;
  final String name; // display title
  final String description; // short overview
  final List<String> covers; // one or more cover images
  final List<ScenarioSection> sections;
  final List<String> related; // related equipment ids

  const ScenarioGuide({
    required this.id,
    required this.name,
    required this.description,
    required this.covers,
    required this.sections,
    required this.related,
  });

  factory ScenarioGuide.fromYaml(YamlMap yaml) {
    final secs = (yaml['sections'] as YamlList? ?? YamlList())
        .map((s) => ScenarioSection.fromYaml(s as YamlMap))
        .toList(growable: false);

    return ScenarioGuide(
      id: yaml['id'] as String,
      name: yaml['name'] as String,
      description: (yaml['description'] as String?) ?? '',
      covers: List<String>.from(yaml['covers'] ?? const []),
      sections: secs,
      related: List<String>.from(yaml['related'] ?? const []), // NEW
    );
  }
}
