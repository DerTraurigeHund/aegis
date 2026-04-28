"""E2E Encryption middleware for FastAPI.

Intercepts requests/responses and decrypts/encrypts automatically.
Health endpoint stays unencrypted for discovery.
"""

import json

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response, JSONResponse

import crypto

# Paths that stay unencrypted (add web paths for browser compatibility)
PLAIN_PATHS = {"/health", "/docs", "/openapi.json", "/redoc", "/", "/style.css", "/app.js", "/dashboard"}


class E2EEncryptionMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        # Skip OPTIONS, public paths, and web frontend requests
        skip_e2e = (
            request.method == "OPTIONS"
            or request.url.path in PLAIN_PATHS
            or request.url.path.startswith("/web/")
            or request.headers.get("User-Agent", "").startswith("Mozilla")  # Browser
        )
        if skip_e2e:
            return await call_next(request)

        # Get API key from header (already validated by auth middleware)
        api_key = request.headers.get("X-API-Key")
        if not api_key:
            return await call_next(request)

        # --- Decrypt incoming request body ---
        if request.method in ("POST", "PUT", "PATCH"):
            try:
                body = await request.body()
                if body:
                    parsed = json.loads(body)
                    if crypto.is_encrypted_payload(parsed):
                        decrypted = crypto.decrypt(parsed, api_key)
                        request._body = json.dumps(decrypted).encode("utf-8")
                    # else: unencrypted — allow for backwards compat
            except Exception as e:
                return JSONResponse(
                    status_code=400,
                    content={"success": False, "error": f"Decryption failed: {e}"},
                )

        # Call the actual route handler
        response = await call_next(request)

        # --- Encrypt outgoing response body ---
        if api_key:
            try:
                body_chunks = []
                async for chunk in response.body_iterator:
                    if isinstance(chunk, str):
                        body_chunks.append(chunk.encode("utf-8"))
                    else:
                        body_chunks.append(chunk)
                raw_body = b"".join(body_chunks)

                if raw_body:
                    parsed = json.loads(raw_body)
                    encrypted = crypto.encrypt(parsed, api_key)
                    # Build fresh JSONResponse (gets correct Content-Length)
                    return JSONResponse(
                        status_code=response.status_code,
                        content=encrypted,
                    )
            except Exception:
                pass

        return response
