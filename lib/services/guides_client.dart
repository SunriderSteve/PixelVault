// PixelVault — Guide YAML client.
//
// Fetches and writes guide YAML files (equipment, videography,
// scenarios) from the PixelVault-Data GitHub repository. Each guide
// category is stored as a multi-document YAML file (documents
// separated by `---`).

import '../models/admin_config_model.dart';
import 'github_repo_client.dart';

/// Fetches and writes guide YAML files from the GitHub repo.
/// One instance is owned by [DataRepository].
class GuidesClient {
  final AdminConfigModel admin;
  final GitHubRepoClient repo;

  const GuidesClient(this.admin, this.repo);

  // ── Public read API ────────────────────────────────────────────

  /// Fetch the raw YAML string for the equipment file.
  Future<String?> fetchEquipmentYaml() =>
      repo.readRaw(admin.equipmentFile);

  /// Fetch the raw YAML string for the videography guides file.
  Future<String?> fetchVideographyYaml() =>
      repo.readRaw(admin.videographyFile);

  /// Fetch the raw YAML string for the scenario guides file.
  Future<String?> fetchScenarioYaml() =>
      repo.readRaw(admin.scenarioFile);

  // ── Authenticated reads ────────────────────────────────────────

  /// Read the equipment file via API (fresh content + SHA for writes).
  Future<RepoFileResult?> readEquipmentViaApi(String token) =>
      repo.readViaApi(admin.equipmentFile, token);

  /// Read the shoots file via API.
  Future<RepoFileResult?> readShootsViaApi(String token) =>
      repo.readViaApi(admin.shootsFile, token);

  // ── Writes ─────────────────────────────────────────────────────

  /// Write the equipment YAML file back to the repo.
  Future<String> writeEquipmentYaml(
    String content, {
    required String sha,
    required String token,
    String message = 'Update equipment via PixelVault',
  }) =>
      repo.writeFile(
        admin.equipmentFile,
        content,
        sha: sha,
        token: token,
        message: message,
      );

  /// Write the shoots YAML file back to the repo.
  Future<String> writeShootsYaml(
    String content, {
    required String sha,
    required String token,
    String message = 'Update shoots via PixelVault',
  }) =>
      repo.writeFile(
        admin.shootsFile,
        content,
        sha: sha,
        token: token,
        message: message,
      );
}
