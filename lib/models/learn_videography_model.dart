import 'package:yaml/yaml.dart';

class VideographyGuide {
  final String id;
  final String name;
  final List<String> coverImages;
  final List<GuideSection> sections;

  VideographyGuide({
    required this.id,
    required this.name,
    required this.coverImages,
    required this.sections,
  });

  factory VideographyGuide.fromYaml(YamlMap yaml) {
    final secs = (yaml['sections'] as YamlList).map((s) {
      final m = s as YamlMap;
      return GuideSection(
        title: m['title'] as String,
        images: List<String>.from(m['images'] ?? []),
        body: m['body'] as String,
      );
    }).toList();

    return VideographyGuide(
      id: yaml['id'] as String,
      name: yaml['name'] as String,
      coverImages: List<String>.from(yaml['coverImages'] ?? []),
      sections: secs,
    );
  }
}

class GuideSection {
  final String title;
  final List<String> images;
  final String body;
  GuideSection({required this.title, required this.images, required this.body});
}
