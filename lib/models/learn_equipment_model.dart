import 'package:yaml/yaml.dart';

class EquipSection {
  final String title;
  final List<String> images;
  final String body;
  const EquipSection({
    required this.title,
    required this.images,
    required this.body,
  });

  factory EquipSection.fromYaml(YamlMap m) {
    return EquipSection(
      title: (m['title'] as String?) ?? '',
      images: List<String>.from(m['images'] ?? const []),
      body: (m['body'] as String?) ?? '',
    );
  }
}

class Equipment {
  final String id;
  final String name;
  final String category;
  final String brand;

  // Fields aligned with Videography guide structure
  final List<String> coverImages; // cover images for carousel
  final String description; // about/overview text
  final List<EquipSection> sections; // collapsible sections
  final List<String> related; // list of related equipment ids

  // Optional inventory metadata (integrated into equipment YAML)
  // If `cabinet` is omitted, it simply won't be shown.
  // If `quantity` is omitted, the item won't appear in the Inventory module.
  final String? cabinet;
  final int? quantity;

  Equipment({
    required this.id,
    required this.name,
    required this.category,
    required this.brand,
    this.cabinet,
    this.quantity,
    required this.coverImages,
    required this.description,
    required this.sections,
    required this.related,
  });

  factory Equipment.fromYaml(YamlMap yaml) {
    // Allow migration: treat legacy `images:` as `covers:` if `covers` is absent
    final cov = List<String>.from(yaml['covers'] ?? yaml['images'] ?? const []);

    final secsYaml = yaml['sections'] as YamlList?;
    final secs = secsYaml == null
        ? <EquipSection>[]
        : secsYaml
              .map((e) => EquipSection.fromYaml(e as YamlMap))
              .toList(growable: false);

    return Equipment(
      id: yaml['id'] as String,
      name: yaml['name'] as String,
      category: (yaml['category'] as String?) ?? '',
      brand: (yaml['brand'] as String?) ?? 'Unknown',
      coverImages: cov,
      description: (yaml['description'] as String?) ?? '',
      sections: secs,
      related: List<String>.from(yaml['related'] ?? const []),
      cabinet: yaml['cabinet'] as String?,
      quantity: (yaml['quantity'] as num?)?.toInt(),
    );
  }
}
