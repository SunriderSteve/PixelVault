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
