"""A tiny TTL cache."""
import time


class TTLCache:
    def __init__(self, ttl_seconds):
        self.ttl = ttl_seconds
        self._data = {}

    def put(self, key, value):
        self._data[key] = (value, time.monotonic())

    def get(self, key):
        item = self._data.get(key)
        if item is None:
            return None
        value, stored_at = item
        if time.monotonic() - stored_at >= self.ttl:
            del self._data[key]
            return None
        return value

    def __len__(self):
        return len(self._data)
