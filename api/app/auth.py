import os

from fastapi import Header, HTTPException


def require_api_key(x_api_key: str = Header(default="")):
    """Reject the request unless X-API-Key matches the API_KEY environment variable."""
    expected = os.environ.get("API_KEY", "")
    if not expected or x_api_key != expected:
        raise HTTPException(status_code=401, detail="invalid api key")
