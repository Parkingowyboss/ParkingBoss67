"""Import individual parking stalls (amenity=parking_space) in Warsaw from OSM.

These are one-feature-per-painted-stall, unlike amenity=parking (whole lots).
Coverage is partial — only lots someone mapped stall-by-stall — which is why
the crowd-sourced occupancy layer matters.

Usage:
    python import_parking_spaces.py
"""
import sys

import psycopg
import requests

from common import WARSAW_BBOX, connect

OVERPASS_URL = "https://overpass-api.de/api/interpreter"
HEADERS = {"User-Agent": "ParkingBoss/0.1 (+https://github.com/Parkingowyboss/ParkingBoss67)"}

OVERPASS_QUERY = """
[out:json][timeout:180];
(
  node["amenity"="parking_space"]({bbox});
  way["amenity"="parking_space"]({bbox});
);
out center tags;
""".strip()


def _bbox_str():
    s, w, n, e = WARSAW_BBOX
    return f"{s},{w},{n},{e}"


def fetch():
    print("[spaces] querying Overpass for parking_space...")
    resp = requests.post(
        OVERPASS_URL,
        data={"data": OVERPASS_QUERY.format(bbox=_bbox_str())},
        headers=HEADERS,
        timeout=240,
    )
    resp.raise_for_status()
    return resp.json().get("elements", [])


def _coords(el):
    if el.get("type") == "node":
        return el.get("lat"), el.get("lon")
    center = el.get("center") or {}
    return center.get("lat"), center.get("lon")


def _bool(tags, key):
    v = tags.get(key)
    if v in ("yes", "true", "1", "designated"):
        return True
    if v in ("no", "false", "0"):
        return False
    return None


def normalize(elements):
    rows = []
    for el in elements:
        lat, lng = _coords(el)
        if lat is None or lng is None:
            continue
        tags = el.get("tags", {})
        rows.append({
            "lat": lat,
            "lng": lng,
            "source": "osm",
            "source_id": f"{el['type']}/{el['id']}",
            "ref": tags.get("ref"),
            "fee": _bool(tags, "fee"),
            # accessible stall: capacity:disabled or parking_space=disabled
            "disabled": _bool(tags, "wheelchair") or (tags.get("parking_space") == "disabled") or None,
        })
    return rows


UPSERT = """
    INSERT INTO parking_spaces (lat, lng, source, source_id, ref, fee, disabled, geom)
    VALUES (%(lat)s, %(lng)s, %(source)s, %(source_id)s, %(ref)s, %(fee)s, %(disabled)s,
            ST_SetSRID(ST_MakePoint(%(lng)s, %(lat)s), 4326))
    ON CONFLICT (source, source_id) WHERE source_id IS NOT NULL
    DO UPDATE SET
        lat = EXCLUDED.lat,
        lng = EXCLUDED.lng,
        ref = EXCLUDED.ref,
        fee = EXCLUDED.fee,
        disabled = EXCLUDED.disabled,
        geom = EXCLUDED.geom,
        last_updated = now();
"""


def main():
    elements = fetch()
    print(f"[spaces] {len(elements)} elements fetched")
    rows = normalize(elements)
    print(f"[spaces] {len(rows)} stalls after normalization")
    if not rows:
        print("[spaces] nothing to import")
        return
    with connect() as conn:
        with conn.cursor() as cur:
            for r in rows:
                cur.execute(UPSERT, r)
        conn.commit()
    print(f"[spaces] upserted {len(rows)} parking stalls")


if __name__ == "__main__":
    try:
        main()
    except requests.HTTPError as e:
        print(f"[spaces] HTTP error: {e}", file=sys.stderr)
        sys.exit(1)
