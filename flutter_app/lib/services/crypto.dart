/// End-to-End Encryption for API communication (AES-256-GCM).
///
/// ## Performance
///
/// **Key caching** — PBKDF2 key derivation (100k iterations) runs exactly once
/// per API key, then the AES key is reused for all subsequent calls.
///
/// **Hybrid execution** — small payloads (<2 KB) run inline since AES-GCM
/// takes <0.1 ms on modern mobile CPUs. Larger payloads are dispatched to a
/// fresh isolate to guarantee zero UI jank.
///
/// ## Error handling
///
/// Decryption errors auto-clear the key cache and retry once. If re-deriving
/// the key doesn't help, the error propagates to the caller with a clear
/// message — likely a mismatch between client and server API keys.
library;

import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

// ─── Constants ───

class _Constants {
  static const int iterations = 100000;
  static const int keyLength = 32;
  static const int nonceLength = 12;
  static final Uint8List salt =
      Uint8List.fromList(utf8.encode('ServerMonitor-E2E-Salt-v1- Fixed'));

  /// Payloads smaller than this run inline (no isolate overhead).
  static const int inlineThreshold = 2048;
}

// ─── Core crypto primitives (sync, fast once key is cached) ───

Uint8List _deriveKey(String apiKey) {
  final params = Pbkdf2Parameters(
      _Constants.salt, _Constants.iterations, _Constants.keyLength);
  final gen = KeyDerivator('SHA-256/HMAC/PBKDF2')..init(params);
  return gen.process(Uint8List.fromList(utf8.encode(apiKey)));
}

Map<String, dynamic> _encryptSync(String jsonData, Uint8List key) {
  final nonce = Uint8List.fromList(
    List.generate(_Constants.nonceLength, (_) => Random.secure().nextInt(256)),
  );
  final plaintext = Uint8List.fromList(utf8.encode(jsonData));

  final cipher = GCMBlockCipher(AESEngine())
    ..init(true, AEADParameters(KeyParameter(key), 128, nonce, nonce));
  final ciphertext = cipher.process(plaintext);

  return {
    'nonce': base64Encode(nonce),
    'ciphertext': base64Encode(ciphertext),
  };
}

String _decryptSync(Map<String, dynamic> payload, Uint8List key) {
  final nonce = base64Decode(payload['nonce'] as String);
  final ciphertext = base64Decode(payload['ciphertext'] as String);

  final cipher = GCMBlockCipher(AESEngine())
    ..init(false, AEADParameters(KeyParameter(key), 128, nonce, nonce));
  final plaintext = cipher.process(Uint8List.fromList(ciphertext));

  return utf8.decode(plaintext);
}

// ─── Isolate entry points (top-level, must be referentially transparent) ───

Map<String, dynamic> _encryptIsolate((String, Uint8List) args) {
  return _encryptSync(args.$1, args.$2);
}

Map<String, dynamic> _decryptIsolate((Map<String, dynamic>, Uint8List) args) {
  final plaintext = _decryptSync(args.$1, args.$2);
  return jsonDecode(plaintext) as Map<String, dynamic>;
}

Uint8List _deriveKeyIsolate(String apiKey) => _deriveKey(apiKey);

// ─── CryptoService with key cache ───

/// Service that caches derived AES keys per API key.
///
/// Usage: provide via `Provider<CryptoService>` and inject into `ApiService`.
class CryptoService {
  final Map<String, Uint8List> _keyCache = {};
  final Map<String, Future<Uint8List>> _pendingKeys = {};

  /// Returns the cached AES key for [apiKey], or derives it once in an isolate.
  Future<Uint8List> _getKey(String apiKey) async {
    // Fast path: already cached
    final cached = _keyCache[apiKey];
    if (cached != null) return cached;

    // Deduplicate concurrent first-access for the same apiKey
    final pending = _pendingKeys[apiKey];
    if (pending != null) return pending;

    final future = Isolate.run(() => _deriveKeyIsolate(apiKey));
    _pendingKeys[apiKey] = future;
    try {
      final key = await future;
      _keyCache[apiKey] = key;
      return key;
    } finally {
      _pendingKeys.remove(apiKey);
    }
  }

  /// Forget cached key(s). Call when the user changes or logs out an API key.
  void clearCache([String? apiKey]) {
    if (apiKey != null) {
      _keyCache.remove(apiKey);
    } else {
      _keyCache.clear();
    }
  }

  /// Encrypt [data] → `{"nonce": …, "ciphertext": …}`.
  ///
  /// Small payloads run inline (sub-millisecond). Large payloads use an isolate
  /// to guarantee the UI stays responsive.
  Future<Map<String, dynamic>> encryptPayload(
      Map<String, dynamic> data, String apiKey) async {
    final key = await _getKey(apiKey);
    final jsonStr = jsonEncode(data);

    if (jsonStr.length < _Constants.inlineThreshold) {
      return _encryptSync(jsonStr, key);
    }
    return Isolate.run(
      () => _encryptIsolate((jsonStr, key)),
    );
  }

  /// Decrypt an encrypted payload back to the original JSON map.
  ///
  /// On failure, invalidates the cached key and retries exactly once. This
  /// handles rare cases where the cached key may be stale (e.g. API key
  /// rotated server-side between encrypt/decrypt).
  Future<Map<String, dynamic>> decryptPayload(
      Map<String, dynamic> payload, String apiKey) async {
    try {
      return await _decryptOnce(payload, apiKey);
    } catch (e) {
      // Invalidate cache and try once more
      clearCache(apiKey);
      try {
        return await _decryptOnce(payload, apiKey);
      } catch (e2) {
        // Both attempts failed — key mismatch or corrupted payload
        throw Exception(
          'Entschlüsselung fehlgeschlagen. '
          'Überprüfe ob der API-Key auf dem Server noch aktuell ist.',
        );
      }
    }
  }

  Future<Map<String, dynamic>> _decryptOnce(
      Map<String, dynamic> payload, String apiKey) async {
    final key = await _getKey(apiKey);

    if (payload.toString().length < _Constants.inlineThreshold) {
      final decrypted = _decryptSync(payload, key);
      return jsonDecode(decrypted) as Map<String, dynamic>;
    }
    return Isolate.run(
      () => _decryptIsolate((payload, key)),
    );
  }
}

// ─── Singleton for legacy / convenience imports ───

final CryptoService cryptoService = CryptoService();

/// Legacy convenience wrapper. Prefer injecting [CryptoService] directly.
Future<Map<String, dynamic>> encryptPayload(
    Map<String, dynamic> data, String apiKey) {
  return cryptoService.encryptPayload(data, apiKey);
}

/// Legacy convenience wrapper. Prefer injecting [CryptoService] directly.
Future<Map<String, dynamic>> decryptPayload(
    Map<String, dynamic> payload, String apiKey) {
  return cryptoService.decryptPayload(payload, apiKey);
}

/// Lightweight check (sync) — does this response look like an encrypted payload?
bool isEncryptedPayload(Map<String, dynamic> body) {
  return body.containsKey('nonce') &&
      body.containsKey('ciphertext') &&
      body.length == 2;
}
