"""API-Key authentication middleware."""
from fastapi import Request, HTTPException
from starlette.middleware.base import BaseHTTPMiddleware
from database import get_db

# Paths that don't require auth
PUBLIC_PATHS = {"/health", "/docs", "/openapi.json", "/redoc"}


class ApiKeyMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        if request.url.path in PUBLIC_PATHS:
            return await call_next(request)

        # Also allow OPTIONS (CORS preflight)
        if request.method == "OPTIONS":
            return await call_next(request)

        api_key = request.headers.get("X-API-Key")
        if not api_key:
            raise HTTPException(status_code=401, detail="Missing X-API-Key header")

        db = await get_db()
        try:
            row = await db.execute_fetchall("SELECT value FROM settings WHERE key = 'api_key'")
            if not row or row[0]["value"] != api_key:
                raise HTTPException(status_code=401, detail="Invalid API key")
        finally:
            await db.close()

        return await call_next(request)
