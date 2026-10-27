import time

from app.cache import TTLCache


def test_get_returns_value():
    c = TTLCache(60)
    c.put("a", 1)
    assert c.get("a") == 1


def test_missing_key_is_none():
    assert TTLCache(60).get("zzz") is None


def test_entry_expires_after_ttl():
    c = TTLCache(0.05)
    c.put("a", 1)
    time.sleep(0.05)
    assert c.get("a") is None


def test_len_counts_entries():
    c = TTLCache(60)
    c.put("a", 1)
    c.put("b", 2)
    assert len(c) == 2
