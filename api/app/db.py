import sqlite3

COLUMNS = ("id", "ref", "status", "city")

SAMPLE = [
    (i, f"SW-{1000 + i}", "delivered" if i % 3 == 0 else "in_transit", "Chennai" if i % 2 else "Mumbai")
    for i in range(1, 26)
]

_conn = None


def get_conn():
    """One shared in-memory database, seeded with 25 sample shipments."""
    global _conn
    if _conn is None:
        _conn = sqlite3.connect(":memory:", check_same_thread=False)
        _conn.execute("CREATE TABLE shipments (id INTEGER PRIMARY KEY, ref TEXT, status TEXT, city TEXT)")
        _conn.executemany("INSERT INTO shipments VALUES (?, ?, ?, ?)", SAMPLE)
        _conn.commit()
    return _conn


def all_shipments():
    rows = get_conn().execute("SELECT id, ref, status, city FROM shipments ORDER BY id").fetchall()
    return [dict(zip(COLUMNS, r)) for r in rows]


def get_shipment(shipment_id):
    row = get_conn().execute(
        "SELECT id, ref, status, city FROM shipments WHERE id = ?", (shipment_id,)
    ).fetchone()
    return dict(zip(COLUMNS, row)) if row else None
