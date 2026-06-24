"""Shared helpers for ParkingBoss data import scripts."""
import math
import os

import psycopg
from dotenv import load_dotenv

load_dotenv()

DATABASE_URL = os.environ.get(
    "DATABASE_URL",
    "postgres://parkingboss:parkingboss@localhost:5432/parkingboss",
)

# Warsaw bounding box (south, west, north, east) — used by Overpass queries.
WARSAW_BBOX = (52.03, 20.80, 52.40, 21.30)


def connect():
    return psycopg.connect(DATABASE_URL)


# ---------------------------------------------------------------------------
# Small-area geometry helpers (local equirectangular projection in metres).
# Accurate enough for individual parking-stall footprints.
# ---------------------------------------------------------------------------

_M_PER_DEG_LAT = 111_320.0


def local_frame(lat0, lon0):
    """Return (to_m, to_geo) converters around an anchor point."""
    cos0 = math.cos(math.radians(lat0))

    def to_m(lat, lon):
        return ((lon - lon0) * _M_PER_DEG_LAT * cos0, (lat - lat0) * _M_PER_DEG_LAT)

    def to_geo(x, y):
        return (lat0 + y / _M_PER_DEG_LAT, lon0 + x / (_M_PER_DEG_LAT * cos0))

    return to_m, to_geo


def rect_ring(cx, cy, ux, uy, length, width):
    """Corners of a rectangle centred at (cx,cy) in metres.

    (ux,uy) is the unit long-axis direction; `length` runs along it, `width`
    across it. Returns 5 (x,y) points (closed ring).
    """
    n = math.hypot(ux, uy) or 1.0
    ux, uy = ux / n, uy / n
    nx, ny = -uy, ux  # perpendicular unit
    hl, hw = length / 2.0, width / 2.0
    pts = [
        (cx + ux * hl + nx * hw, cy + uy * hl + ny * hw),
        (cx + ux * hl - nx * hw, cy + uy * hl - ny * hw),
        (cx - ux * hl - nx * hw, cy - uy * hl - ny * hw),
        (cx - ux * hl + nx * hw, cy - uy * hl + ny * hw),
    ]
    pts.append(pts[0])
    return pts


def polygon_wkt(coords):
    """WKT POLYGON from [(lat,lng), ...] (auto-closes the ring)."""
    ring = list(coords)
    if ring[0] != ring[-1]:
        ring.append(ring[0])
    body = ", ".join(f"{lng} {lat}" for lat, lng in ring)
    return f"POLYGON(({body}))"


def centroid(coords):
    """Average (lat, lng) of a list of (lat, lng) points."""
    n = len(coords)
    return (sum(c[0] for c in coords) / n, sum(c[1] for c in coords) / n)


def upsert_locations(conn, rows):
    """Insert/update locations keyed on (source, source_id).

    `rows` is a list of dicts with keys:
      type, name, address, lat, lng, total_spots, available_spots,
      price_per_hour, currency, open_hours (json str), amenities (json str),
      source, source_id
    Returns the number of rows affected.
    """
    sql = """
        INSERT INTO locations
            (type, name, address, lat, lng, total_spots, available_spots,
             price_per_hour, currency, open_hours, amenities, source, source_id, geom)
        VALUES
            (%(type)s, %(name)s, %(address)s, %(lat)s, %(lng)s, %(total_spots)s,
             %(available_spots)s, %(price_per_hour)s, %(currency)s,
             %(open_hours)s, %(amenities)s, %(source)s, %(source_id)s,
             ST_SetSRID(ST_MakePoint(%(lng)s, %(lat)s), 4326))
        ON CONFLICT (source, source_id) WHERE source_id IS NOT NULL
        DO UPDATE SET
            type = EXCLUDED.type,
            name = EXCLUDED.name,
            address = EXCLUDED.address,
            lat = EXCLUDED.lat,
            lng = EXCLUDED.lng,
            total_spots = EXCLUDED.total_spots,
            available_spots = EXCLUDED.available_spots,
            price_per_hour = EXCLUDED.price_per_hour,
            currency = EXCLUDED.currency,
            open_hours = EXCLUDED.open_hours,
            amenities = EXCLUDED.amenities,
            geom = EXCLUDED.geom,
            last_updated = now();
    """
    count = 0
    with conn.cursor() as cur:
        for r in rows:
            r.setdefault("currency", "PLN")
            for k in (
                "name", "address", "total_spots", "available_spots",
                "price_per_hour", "open_hours", "amenities", "source_id",
            ):
                r.setdefault(k, None)
            cur.execute(sql, r)
            count += 1
    conn.commit()
    return count
