import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

import 'package:aegis/services/crypto.dart';

void main() {
  group('CryptoService - AES-256-GCM Roundtrip', () {
    final crypto = CryptoService();
    final apiKey = 'test-api-key-12345';

    test('encrypt then decrypt returns original data', () async {
      final original = {
        'name': 'test-project',
        'type': 'shell',
        'config': {'command': 'npm start', 'cwd': '/opt/app'},
        'max_restarts': 3,
      };

      final encrypted = await crypto.encryptPayload(original, apiKey);
      expect(encrypted, contains('nonce'));
      expect(encrypted, contains('ciphertext'));
      expect(encrypted.length, equals(2));

      final decrypted = await crypto.decryptPayload(encrypted, apiKey);
      expect(decrypted, equals(original));
    });

    test('decrypt fails with wrong key then retry with clear cache', () async {
      final original = {'message': 'hello'};
      final encrypted = await crypto.encryptPayload(original, apiKey);

      // Should throw a user-friendly message, not a raw exception
      await expectLater(
        () => crypto.decryptPayload(encrypted, 'wrong-key'),
        throwsA(predicate((e) =>
            e is Exception && e.toString().contains('Decryption'))),
      );
    });

    test('large payload roundtrip works (isolate path)', () async {
      final original = {
        'data': 'x' * 3000,
        'nested': {
          'field': 'y' * 2000,
        },
      };

      final encrypted = await crypto.encryptPayload(original, apiKey);
      final decrypted = await crypto.decryptPayload(encrypted, apiKey);
      expect(decrypted, equals(original));
    });

    test('multiple sequential calls with same key', () async {
      for (var i = 0; i < 10; i++) {
        final data = {'counter': i, 'payload': 'msg-$i'};
        final encrypted = await crypto.encryptPayload(data, apiKey);
        final decrypted = await crypto.decryptPayload(encrypted, apiKey);
        expect(decrypted, equals(data));
      }
    });

    test('cache clear and retry works after wrong key', () async {
      final data = {'x': 1};
      final encrypted = await crypto.encryptPayload(data, apiKey);

      // First decrypt with cache cleared (simulates stale cache)
      crypto.clearCache(apiKey);
      final decrypted = await crypto.decryptPayload(encrypted, apiKey);
      expect(decrypted, equals(data));
    });
  });
}
