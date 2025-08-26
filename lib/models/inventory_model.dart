import 'package:yaml/yaml.dart';

class InventoryItem {
  final String id; // must match LearnEquipmentModel.id
  final String name; // display name
  final String cabinet; // where it's stored (e.g., "C3", "A-12")
  final int quantity; // current stock count

  const InventoryItem({
    required this.id,
    required this.name,
    required this.cabinet,
    required this.quantity,
  });

  factory InventoryItem.fromYaml(YamlMap yaml) => InventoryItem(
    id: yaml['id'] as String,
    name: yaml['name'] as String,
    cabinet: (yaml['cabinet'] as String?) ?? '',
    quantity: (yaml['quantity'] as num?)?.toInt() ?? 0,
  );
}
