import 'package:yaml/yaml.dart';

class AdminConfigModel {
  final String owner;
  final String repo;
  final String branch;
  final int pollSeconds;
  final String accessToken;

  // File paths relative to the repo root.
  final String equipmentFile;
  final String videographyFile;
  final String scenarioFile;
  final String shootsFile;

  const AdminConfigModel({
    required this.owner,
    required this.repo,
    required this.branch,
    required this.pollSeconds,
    required this.accessToken,
    required this.equipmentFile,
    required this.videographyFile,
    required this.scenarioFile,
    required this.shootsFile,
  });

  /// Base URL for raw file access via the GitHub CDN.
  String get rawBaseUrl =>
      'https://raw.githubusercontent.com/$owner/$repo/$branch';

  /// Construct a raw CDN URL for any repo-relative path.
  String rawUrl(String path) => '$rawBaseUrl/$path';

  /// Base URL for the GitHub Contents API.
  String get apiBaseUrl =>
      'https://api.github.com/repos/$owner/$repo/contents';

  // Rotates all printable ASCII (space ' ' = 32 .. '~' = 126)
  static String caesarCipherDecode(String text, int shift) {
    if (text.isEmpty || shift == 0) return text;

    // Normalise the shift to within 0–25
    final int normalizedShift = shift % 26;
    final StringBuffer buffer = StringBuffer();

    for (final int code in text.codeUnits) {
      // Uppercase A–Z
      if (code >= 65 && code <= 90) {
        const int base = 65;
        final int offset = (code - base + normalizedShift) % 26;
        buffer.writeCharCode(base + offset);
      }
      // Lowercase a–z
      else if (code >= 97 && code <= 122) {
        const int base = 97;
        final int offset = (code - base + normalizedShift) % 26;
        buffer.writeCharCode(base + offset);
      }
      // Non-letters: leave as-is
      else {
        buffer.writeCharCode(code);
      }
    }

    return buffer.toString();
  }

  factory AdminConfigModel.fromYaml(String yamlString) {
    final y = loadYaml(yamlString) as YamlMap;
    final g = (y['github'] as YamlMap?) ?? YamlMap();

    return AdminConfigModel(
      owner: (g['owner'] as String?) ?? '',
      repo: (g['repo'] as String?) ?? '',
      branch: (g['branch'] as String?) ?? 'main',
      pollSeconds: (g['poll_seconds'] as int?) ?? 5,
      accessToken: caesarCipherDecode(
        (g['access_token'] as String?) ?? '',
        g['caesar_shift'] is int ? -(g['caesar_shift'] as int) : 0,
      ),
      equipmentFile: (g['equipment_file'] as String?) ?? 'data/equipment.yaml',
      videographyFile:
          (g['videography_file'] as String?) ?? 'data/videography_guides.yaml',
      scenarioFile:
          (g['scenario_file'] as String?) ?? 'data/scenario_guides.yaml',
      shootsFile:
          (g['shoots_file'] as String?) ?? 'data/production_shoots.yaml',
    );
  }
}
