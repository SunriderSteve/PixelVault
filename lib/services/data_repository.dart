import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:yaml/yaml.dart';

import '../models/learn_equipment_model.dart';
import '../models/scenario_model.dart';

/// Loads all YAML files once at start-up and keeps them in memory.
/// Call `await DataRepository().init()` in main() *before* runApp().
class DataRepository {
  // ---------- singleton boilerplate ----------
  DataRepository._private();
  static final DataRepository _instance = DataRepository._private();
  factory DataRepository() => _instance;
  // -------------------------------------------

  late final Map<String, Equipment> _equipment;
  late final Map<String, Scenario> _scenarios;

  /// Reads every .yaml file under /data/equipment/ and /data/scenarios/
  Future<void> init() async {
    // 1. AssetManifest.json lists every file bundled by Flutter.
    final manifestContent = await rootBundle.loadString('AssetManifest.json');
    final manifestMap = jsonDecode(manifestContent) as Map<String, dynamic>;

    // 2. Prepare empty maps to fill.
    _equipment = {};
    _scenarios = {};

    // 3. Load equipment YAML files
    final equipPaths = manifestMap.keys.where(
      (p) => p.startsWith('data/learn_equipment/') && p.endsWith('.yaml'),
    );

    for (final path in equipPaths) {
      final yamlString = await rootBundle.loadString(path);
      final yamlMap = loadYaml(yamlString) as YamlMap;
      final eq = Equipment.fromYaml(yamlMap);
      _equipment[eq.id] = eq;
    }

    // 4. Load scenario YAML files
    final scenPaths = manifestMap.keys.where(
      (p) => p.startsWith('data/scenarios/') && p.endsWith('.yaml'),
    );

    for (final path in scenPaths) {
      final yamlString = await rootBundle.loadString(path);
      final yamlMap = loadYaml(yamlString) as YamlMap;
      final sc = Scenario.fromYaml(yamlMap);
      _scenarios[sc.id] = sc;
    }
  }

  // ---------- public helpers ----------
  List<Equipment> getAllEquipment() => _equipment.values.toList();
  List<Scenario> getAllScenarios() => _scenarios.values.toList();

  Equipment? getEquipment(String id) => _equipment[id];
  Scenario? getScenario(String id) => _scenarios[id];
}
