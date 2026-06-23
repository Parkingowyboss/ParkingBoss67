"""Shared helpers for ParkingBoss data import scripts."""
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
