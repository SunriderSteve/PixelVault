import 'package:yaml/yaml.dart';

class AdminConfigModel {
  final String gistId;
  final String gistFile;
  final String gistRawUrl;
  final int pollSeconds;
  final String accessToken;
  final String shootsFile;
  final String shootsRawUrl;

  const AdminConfigModel({
    required this.gistId,
    required this.gistFile,
    required this.gistRawUrl,
    required this.pollSeconds,
    required this.accessToken,
    required this.shootsFile,
    required this.shootsRawUrl,
  });

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
    final g = (y['gist'] as YamlMap?) ?? YamlMap();

    return AdminConfigModel(
      gistId: (g['id'] as String?) ?? '',
      gistFile: (g['file'] as String?) ?? 'inventory_mutable.yaml',
      gistRawUrl: (g['raw_url'] as String?) ?? '',
      pollSeconds: (g['poll_seconds'] as int?) ?? 5,
      accessToken: caesarCipherDecode(
        (g['access_token'] as String?) ?? '',
        g['caesar_shift'] is int ? -(g['caesar_shift'] as int) : 0,
      ),
      shootsFile: (g['shoots_file'] as String?) ?? 'production_shoots.yaml',
      shootsRawUrl: (g['shoots_raw_url'] as String?) ?? '',
    );
  }
}
