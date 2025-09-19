import 'package:yaml/yaml.dart';

class AdminConfigModel {
  final String gistId;
  final String gistFile;
  final String gistRawUrl;
  final int pollSeconds;
  final String accessToken;

  const AdminConfigModel({
    required this.gistId,
    required this.gistFile,
    required this.gistRawUrl,
    required this.pollSeconds,
    required this.accessToken,
  });

  factory AdminConfigModel.fromYaml(String yamlString) {
    final y = loadYaml(yamlString) as YamlMap;
    final g = (y['gist'] as YamlMap?) ?? YamlMap();

    return AdminConfigModel(
      gistId: (g['id'] as String?) ?? '',
      gistFile: (g['file'] as String?) ?? 'inventory_mutable.yaml',
      gistRawUrl: (g['raw_url'] as String?) ?? '',
      pollSeconds: (g['poll_seconds'] as int?) ?? 5,
      accessToken: (g['access_token'] as String?) ?? '',
    );
  }
}
