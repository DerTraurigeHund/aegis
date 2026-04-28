import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/project.dart';
import 'crypto.dart';

class ApiService {
  final http.Client _client = http.Client();
  final CryptoService _crypto;

  ApiService({CryptoService? crypto}) : _crypto = crypto ?? cryptoService;

  Future<bool> healthCheck(String baseUrl) async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Map<String, String> _headers(String apiKey) => {
    'Content-Type': 'application/json',
    'X-API-Key': apiKey,
  };

  /// Decode a response body, handling E2E encryption automatically.
  Future<dynamic> _decodeResponse(http.Response response, String apiKey) async {
    if (response.statusCode >= 400) {
      try {
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic> && isEncryptedPayload(body)) {
          final decrypted = await _crypto.decryptPayload(body, apiKey);
          throw Exception(decrypted['error'] ?? 'Request failed');
        }
        throw Exception(body['error'] ?? 'Request failed (${response.statusCode})');
      } catch (e) {
        if (e is Exception) rethrow;
        throw Exception('Request failed (${response.statusCode})');
      }
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    // Auto-decrypt if encrypted (key is now cached — sub-millisecond!)
    if (isEncryptedPayload(body)) {
      return await _crypto.decryptPayload(body, apiKey);
    }

    return body;
  }

  /// Encrypt request body (key is now cached — sub-millisecond!).
  Future<String> _encodeBody(Map<String, dynamic> data, String apiKey) async {
    final encrypted = await _crypto.encryptPayload(data, apiKey);
    return jsonEncode(encrypted);
  }

  // ─── Projects ───

  Future<List<Project>> getProjects(String baseUrl, String apiKey) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/projects'),
      headers: _headers(apiKey),
    );
    final body = await _decodeResponse(response, apiKey);
    final List data = body['data'] ?? [];
    return data.map((p) => Project.fromJson(p)).toList();
  }

  Future<Project> createProject(String baseUrl, String apiKey, Map<String, dynamic> project) async {
    final body = await _encodeBody(project, apiKey);
    final response = await _client.post(
      Uri.parse('$baseUrl/projects'),
      headers: _headers(apiKey),
      body: body,
    );
    final decoded = await _decodeResponse(response, apiKey);
    return Project.fromJson(decoded['data']);
  }

  Future<Project> getProject(String baseUrl, String apiKey, int id) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/projects/$id'),
      headers: _headers(apiKey),
    );
    final body = await _decodeResponse(response, apiKey);
    return Project.fromJson(body['data']);
  }

  Future<Project> updateProject(String baseUrl, String apiKey, int id, Map<String, dynamic> data) async {
    final body = await _encodeBody(data, apiKey);
    final response = await _client.put(
      Uri.parse('$baseUrl/projects/$id'),
      headers: _headers(apiKey),
      body: body,
    );
    final decoded = await _decodeResponse(response, apiKey);
    return Project.fromJson(decoded['data']);
  }

  Future<void> deleteProject(String baseUrl, String apiKey, int id) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/projects/$id'),
      headers: _headers(apiKey),
    );
    await _decodeResponse(response, apiKey);
  }

  // ─── Actions ───

  Future<void> startProject(String baseUrl, String apiKey, int id) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/projects/$id/start'),
      headers: _headers(apiKey),
    );
    await _decodeResponse(response, apiKey);
  }

  Future<void> stopProject(String baseUrl, String apiKey, int id) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/projects/$id/stop'),
      headers: _headers(apiKey),
    );
    await _decodeResponse(response, apiKey);
  }

  Future<void> restartProject(String baseUrl, String apiKey, int id) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/projects/$id/restart'),
      headers: _headers(apiKey),
    );
    await _decodeResponse(response, apiKey);
  }

  // ─── Events & Logs ───

  Future<List<Map<String, dynamic>>> getEvents(String baseUrl, String apiKey, int projectId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/projects/$projectId/events'),
      headers: _headers(apiKey),
    );
    final body = await _decodeResponse(response, apiKey);
    return List<Map<String, dynamic>>.from(body['data'] ?? []);
  }

  Future<List<String>> getLogs(String baseUrl, String apiKey, int projectId, {int lines = 50}) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/projects/$projectId/logs?lines=$lines'),
      headers: _headers(apiKey),
    );
    final body = await _decodeResponse(response, apiKey);
    return List<String>.from(body['data'] ?? []);
  }

  // ─── Devices ───

  Future<void> registerDevice(String baseUrl, String apiKey, String token, {String platform = 'android'}) async {
    final body = await _encodeBody({'token': token, 'platform': platform}, apiKey);
    final response = await _client.post(
      Uri.parse('$baseUrl/devices/register'),
      headers: _headers(apiKey),
      body: body,
    );
    await _decodeResponse(response, apiKey);
  }

  // ─── System Stats (Server Load) ───

  Future<Map<String, dynamic>> getSystemStats(String baseUrl, String apiKey) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/system/stats'),
      headers: _headers(apiKey),
    );
    final body = await _decodeResponse(response, apiKey);
    return body['data'];
  }

  // ─── Project Stats ───

  Future<Map<String, dynamic>> getStats(String baseUrl, String apiKey, int projectId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/projects/$projectId/stats'),
      headers: _headers(apiKey),
    );
    final body = await _decodeResponse(response, apiKey);
    return body['data'];
  }

  /// Access the underlying [CryptoService] (e.g. to call [CryptoService.clearCache]).
  CryptoService get crypto => _crypto;
}
