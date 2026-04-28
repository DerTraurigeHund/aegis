"""End-to-End Encryption for API communication (AES-256-GCM).

Uses PBKDF2 to derive a 256-bit key from the API key.
Each request/response gets a random 12-byte nonce.
Payload format: {"nonce": "<base64>", "ciphertext": "<base64>"}
"""

import base64
import hashlib
import json
import os
import struct

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.hazmat.primitives import hashes

# Fixed salt for key derivation (32 bytes, public — the secret is the API key)
_SALT = b"ServerMonitor-E2E-Salt-v1- Fixed"
_ITERATIONS = 100_000


def derive_key(api_key: str) -> bytes:
    """Derive a 256-bit AES key from the API key using PBKDF2."""
    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA256(),
        length=32,
        salt=_SALT,
        iterations=_ITERATIONS,
    )
    return kdf.derive(api_key.encode("utf-8"))


def encrypt(data: dict, api_key: str) -> dict:
    """Encrypt a dict payload. Returns {"nonce": "...", "ciphertext": "..."}."""
    key = derive_key(api_key)
    nonce = os.urandom(12)
    aesgcm = AESGCM(key)
    plaintext = json.dumps(data, ensure_ascii=False).encode("utf-8")
    # Associate data: nonce itself (binds nonce to ciphertext)
    ct = aesgcm.encrypt(nonce, plaintext, associated_data=nonce)
    return {
        "nonce": base64.b64encode(nonce).decode("ascii"),
        "ciphertext": base64.b64encode(ct).decode("ascii"),
    }


def decrypt(payload: dict, api_key: str) -> dict:
    """Decrypt a {"nonce": "...", "ciphertext": "..."} payload. Returns the original dict."""
    key = derive_key(api_key)
    nonce = base64.b64decode(payload["nonce"])
    ct = base64.b64decode(payload["ciphertext"])
    aesgcm = AESGCM(key)
    plaintext = aesgcm.decrypt(nonce, ct, associated_data=nonce)
    return json.loads(plaintext.decode("utf-8"))


def is_encrypted_payload(body) -> bool:
    """Check if a body looks like an encrypted payload."""
    if isinstance(body, dict):
        return "nonce" in body and "ciphertext" in body and len(body) == 2
    return False
