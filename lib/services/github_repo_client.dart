// PixelVault — GitHub repository file client.
//
// Low-level read/write operations against a GitHub repository using
// both the raw CDN (fast reads) and the Contents API (fresh reads and
// writes). All YAML data and images are stored in a single public
// GitHub repo.
//
// Read paths:
//   • Raw CDN:  raw.githubusercontent.com/{owner}/{repo}/{branch}/{path}
//     Fast, served by CDN, can be briefly stale after a write.
//   • API:      api.github.com/repos/{owner}/{repo}/contents/{path}
//     Always fresh, returns content + SHA needed for writes.
//
// Write path:
//   PUT api.github.com/repos/{owner}/{repo}/contents/{path}
//   Requires the current file SHA (for optimistic concurrency) and a
//   commit message. Content is sent as base64.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/admin_config_model.dart';

/// Result of an authenticated API read. Carries both the decoded file
/// content and the SHA needed for a subsequent write.
class RepoFileResult {
  final String content;
  final String sha;
  const RepoFileResult({required this.content, required this.sha});
}

/// Result of a conditional (ETag-based) poll. Null means 304 — no
/// change since the last poll.
class RepoPollResult {
  final String content;
  final String? etag;
  const RepoPollResult({required this.content, this.etag});
}

/// A single file change to include in a batch commit. Either a text
/// write, a binary write, or a delete.
class BatchFileChange {
  final String path;
  final Uint8List? bytes; // binary writes
  final String? text;     // text writes
  final bool delete;

  const BatchFileChange.write({required this.path, required String content})
      : bytes = null,
        text = content,
        delete = false;

  const BatchFileChange.writeBinary({required this.path, required this.bytes})
      : text = null,
        delete = false;

  const BatchFileChange.delete({required this.path})
      : bytes = null,
        text = null,
        delete = true;
}

/// Low-level GitHub repo file operations. One instance shared across
/// all higher-level clients via [DataRepository].
class GitHubRepoClient {
  final AdminConfigModel admin;

  const GitHubRepoClient(this.admin);

  // ── Raw CDN reads ──────────────────────────────────────────────

  /// Fetch file content via the raw CDN. Cache-busted with a
  /// timestamp query param. Returns null on any failure.
  Future<String?> readRaw(String path) async {
    try {
      final uri = Uri.parse(admin.rawUrl(path)).replace(
        queryParameters: {
          't': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      );
      final resp = await http.get(uri);
      if (resp.statusCode == 200 && resp.body.isNotEmpty) {
        return resp.body;
      }
      debugPrint('repo raw non-OK ${resp.statusCode}: ${resp.reasonPhrase}');
      return null;
    } catch (e) {
      debugPrint('repo raw exception $e');
      return null;
    }
  }

  // ── Authenticated API reads ────────────────────────────────────

  /// Read a file via the Contents API. Returns content + SHA, or null
  /// on failure.
  Future<RepoFileResult?> readViaApi(String path, String token) async {
    try {
      final uri = Uri.parse('${admin.apiBaseUrl}/$path?ref=${admin.branch}');
      final resp = await http.get(uri, headers: _authHeaders(token));
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final content = _decodeContent(body);
        final sha = body['sha'] as String;
        return RepoFileResult(content: content, sha: sha);
      }
      debugPrint('repo api non-OK ${resp.statusCode}: ${resp.reasonPhrase}');
      return null;
    } catch (e) {
      debugPrint('repo api exception $e');
      return null;
    }
  }

  // ── Conditional polling ────────────────────────────────────────

  /// Poll a file via the raw CDN with ETag support. Returns null on
  /// 304 (not modified) so callers can skip processing. Returns the
  /// content + new ETag on 200.
  Future<RepoPollResult?> pollRaw(String path, {String? etag}) async {
    try {
      final uri = Uri.parse(admin.rawUrl(path)).replace(
        queryParameters: {
          't': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      );
      final headers = <String, String>{};
      if (etag != null) headers['If-None-Match'] = etag;

      final resp = await http.get(uri, headers: headers);
      if (resp.statusCode == 304) return null;
      if (resp.statusCode == 200 && resp.body.isNotEmpty) {
        return RepoPollResult(
          content: resp.body,
          etag: resp.headers['etag'],
        );
      }
      return null;
    } catch (e) {
      debugPrint('repo poll exception $e');
      return null;
    }
  }

  /// Poll via the authenticated API with ETag support. Returns null
  /// on 304. This is more reliable than raw polling for real-time data
  /// like production shoots.
  Future<RepoPollResult?> pollViaApi(
    String path,
    String token, {
    String? etag,
  }) async {
    try {
      final uri = Uri.parse('${admin.apiBaseUrl}/$path?ref=${admin.branch}');
      final headers = _authHeaders(token);
      if (etag != null) headers['If-None-Match'] = etag;

      final resp = await http.get(uri, headers: headers);
      if (resp.statusCode == 304) return null;
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        return RepoPollResult(
          content: _decodeContent(body),
          etag: resp.headers['etag'],
        );
      }
      return null;
    } catch (e) {
      debugPrint('repo api poll exception $e');
      return null;
    }
  }

  // ── Writes ─────────────────────────────────────────────────────

  /// Write (create or update) a file in the repo. Requires the current
  /// SHA of the file for updates; pass an empty string for new files.
  /// Returns the new SHA after the commit.
  Future<String> writeFile(
    String path,
    String content, {
    required String sha,
    required String token,
    String message = 'Update via PixelVault',
  }) async {
    final uri = Uri.parse('${admin.apiBaseUrl}/$path');
    final payload = <String, dynamic>{
      'message': message,
      'content': base64Encode(utf8.encode(content)),
      'branch': admin.branch,
    };
    if (sha.isNotEmpty) payload['sha'] = sha;

    final resp = await http.put(
      uri,
      headers: {
        ..._authHeaders(token),
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    if (resp.statusCode ~/ 100 != 2) {
      throw Exception(
        'repo write failed ($path): ${resp.statusCode} ${resp.body}',
      );
    }

    final respBody = jsonDecode(resp.body) as Map<String, dynamic>;
    final contentMap = respBody['content'] as Map<String, dynamic>?;
    return (contentMap?['sha'] as String?) ?? '';
  }

  /// Write (create or update) a binary file in the repo. Unlike
  /// [writeFile], this takes raw bytes and base64-encodes them directly
  /// without UTF-8 wrapping, so binary data (images) is not corrupted.
  Future<String> writeBinaryFile(
    String path,
    Uint8List bytes, {
    required String sha,
    required String token,
    String message = 'Upload via PixelVault',
  }) async {
    final uri = Uri.parse('${admin.apiBaseUrl}/$path');
    final payload = <String, dynamic>{
      'message': message,
      'content': base64Encode(bytes),
      'branch': admin.branch,
    };
    if (sha.isNotEmpty) payload['sha'] = sha;

    final resp = await http.put(
      uri,
      headers: {
        ..._authHeaders(token),
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    if (resp.statusCode ~/ 100 != 2) {
      throw Exception(
        'repo binary write failed ($path): ${resp.statusCode} ${resp.body}',
      );
    }

    final respBody = jsonDecode(resp.body) as Map<String, dynamic>;
    final contentMap = respBody['content'] as Map<String, dynamic>?;
    return (contentMap?['sha'] as String?) ?? '';
  }

  /// Delete a file from the repo. Requires the file's current SHA.
  Future<void> deleteFile(
    String path, {
    required String sha,
    required String token,
    String message = 'Delete via PixelVault',
  }) async {
    final uri = Uri.parse('${admin.apiBaseUrl}/$path');
    final request = http.Request('DELETE', uri);
    request.headers.addAll({
      ..._authHeaders(token),
      'Content-Type': 'application/json',
    });
    request.body = jsonEncode({
      'message': message,
      'sha': sha,
      'branch': admin.branch,
    });

    final streamed = await http.Client().send(request);
    if (streamed.statusCode ~/ 100 != 2) {
      final body = await streamed.stream.bytesToString();
      throw Exception(
        'repo delete failed ($path): ${streamed.statusCode} $body',
      );
    }
  }

  /// Get just the SHA of a file (convenience for delete operations).
  Future<String?> getFileSha(String path, String token) async {
    final result = await readViaApi(path, token);
    return result?.sha;
  }

  // ── Batched commits via Git Data API ───────────────────────────

  /// Commit multiple file changes (writes + deletes) in a single Git
  /// commit. This is atomic — callers see either all changes or none.
  ///
  /// Workflow: POST blobs (parallel) → GET ref → GET commit (base tree)
  /// → POST tree (with base_tree) → POST commit → PATCH ref.
  ///
  /// Retries on "not a fast forward" 422s (the branch head moved
  /// between our ref read and ref patch). Blobs are reused across
  /// retries since they're content-addressed.
  ///
  /// Returns the new commit SHA.
  Future<String> commitBatch(
    List<BatchFileChange> changes, {
    required String token,
    required String message,
  }) async {
    if (changes.isEmpty) throw ArgumentError('commitBatch: no changes');

    final gitApi = admin.gitApiBaseUrl;
    final headers = _authHeaders(token);
    final jsonHeaders = {
      ...headers,
      'Content-Type': 'application/json',
    };

    // Create blobs once — they're content-addressed, so GitHub
    // dedupes them even if we retry the tree/commit/ref steps.
    final writes = changes.where((c) => !c.delete).toList();
    final blobShas = await Future.wait(
      writes.map((c) => _createBlob(c, jsonHeaders)),
    );
    final blobShaByPath = <String, String>{
      for (int i = 0; i < writes.length; i++) writes[i].path: blobShas[i],
    };

    // Retry schedule tuned to GitHub's ref read-after-write replication
    // window. Back-to-back commits from the same client commonly see the
    // second ref read return a stale parent for ~1–5s before replicas
    // catch up, so we need a longer budget than a naive immediate retry.
    const List<int> backoffMs = [500, 1000, 2000, 3000, 5000];
    for (int attempt = 0;; attempt++) {
      try {
        return await _commitTreeAndRef(
          changes: changes,
          blobShaByPath: blobShaByPath,
          message: message,
          headers: headers,
          jsonHeaders: jsonHeaders,
          gitApi: gitApi,
        );
      } catch (e) {
        final msg = e.toString();
        final bool isFastForward =
            msg.contains('not a fast forward') ||
                msg.contains('Update is not a fast forward');
        if (!isFastForward || attempt >= backoffMs.length) rethrow;
        await Future.delayed(Duration(milliseconds: backoffMs[attempt]));
      }
    }
  }

  /// Inner helper for [commitBatch]: reads the current ref and base
  /// tree, builds a new tree/commit from the pre-created blobs, and
  /// fast-forwards the branch ref.
  Future<String> _commitTreeAndRef({
    required List<BatchFileChange> changes,
    required Map<String, String> blobShaByPath,
    required String message,
    required Map<String, String> headers,
    required Map<String, String> jsonHeaders,
    required String gitApi,
  }) async {
    // 1. Resolve the current branch head.
    final refResp = await http.get(
      Uri.parse('$gitApi/ref/heads/${admin.branch}'),
      headers: headers,
    );
    if (refResp.statusCode != 200) {
      throw Exception(
        'batch ref read failed: ${refResp.statusCode} ${refResp.body}',
      );
    }
    final refBody = jsonDecode(refResp.body) as Map<String, dynamic>;
    final parentCommitSha =
        (refBody['object'] as Map<String, dynamic>)['sha'] as String;

    // 2. Fetch the commit so we can base the new tree on its tree.
    final commitResp = await http.get(
      Uri.parse('$gitApi/commits/$parentCommitSha'),
      headers: headers,
    );
    if (commitResp.statusCode != 200) {
      throw Exception(
        'batch commit read failed: ${commitResp.statusCode} ${commitResp.body}',
      );
    }
    final commitBody = jsonDecode(commitResp.body) as Map<String, dynamic>;
    final baseTreeSha =
        (commitBody['tree'] as Map<String, dynamic>)['sha'] as String;

    // 3. Build the tree. For deletes, omit the sha (null) so the path
    // is removed from the new tree.
    final treeEntries = <Map<String, dynamic>>[];
    for (final change in changes) {
      treeEntries.add({
        'path': change.path,
        'mode': '100644',
        'type': 'blob',
        'sha': change.delete ? null : blobShaByPath[change.path],
      });
    }

    final treeResp = await http.post(
      Uri.parse('$gitApi/trees'),
      headers: jsonHeaders,
      body: jsonEncode({
        'base_tree': baseTreeSha,
        'tree': treeEntries,
      }),
    );
    if (treeResp.statusCode ~/ 100 != 2) {
      throw Exception(
        'batch tree create failed: ${treeResp.statusCode} ${treeResp.body}',
      );
    }
    final newTreeSha =
        (jsonDecode(treeResp.body) as Map<String, dynamic>)['sha'] as String;

    // 4. Create the commit.
    final newCommitResp = await http.post(
      Uri.parse('$gitApi/commits'),
      headers: jsonHeaders,
      body: jsonEncode({
        'message': message,
        'tree': newTreeSha,
        'parents': [parentCommitSha],
      }),
    );
    if (newCommitResp.statusCode ~/ 100 != 2) {
      throw Exception(
        'batch commit create failed: '
        '${newCommitResp.statusCode} ${newCommitResp.body}',
      );
    }
    final newCommitSha =
        (jsonDecode(newCommitResp.body) as Map<String, dynamic>)['sha']
            as String;

    // 5. Fast-forward the branch ref.
    final updateResp = await http.patch(
      Uri.parse('$gitApi/refs/heads/${admin.branch}'),
      headers: jsonHeaders,
      body: jsonEncode({'sha': newCommitSha}),
    );
    if (updateResp.statusCode ~/ 100 != 2) {
      throw Exception(
        'batch ref update failed: '
        '${updateResp.statusCode} ${updateResp.body}',
      );
    }

    return newCommitSha;
  }

  /// Create a blob from a BatchFileChange. Returns the blob SHA.
  Future<String> _createBlob(
    BatchFileChange change,
    Map<String, String> jsonHeaders,
  ) async {
    final encoded = change.bytes != null
        ? base64Encode(change.bytes!)
        : base64Encode(utf8.encode(change.text ?? ''));
    final resp = await http.post(
      Uri.parse('${admin.gitApiBaseUrl}/blobs'),
      headers: jsonHeaders,
      body: jsonEncode({'content': encoded, 'encoding': 'base64'}),
    );
    if (resp.statusCode ~/ 100 != 2) {
      throw Exception(
        'blob create failed (${change.path}): ${resp.statusCode} ${resp.body}',
      );
    }
    return (jsonDecode(resp.body) as Map<String, dynamic>)['sha'] as String;
  }

  // ── Helpers ────────────────────────────────────────────────────

  Map<String, String> _authHeaders(String token) => {
        'Authorization': 'token $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  /// Decode base64-encoded file content from the Contents API
  /// response. GitHub splits the content into lines, so we strip
  /// whitespace before decoding.
  String _decodeContent(Map<String, dynamic> body) {
    final raw = (body['content'] as String?) ?? '';
    return utf8.decode(base64Decode(raw.replaceAll(RegExp(r'\s'), '')));
  }
}
