"""Import individual parking stalls (amenity=parking_space) in Warsaw from OSM,
with their real footprint geometry.

Ways mapped as areas keep their actual polygon outline; nodes get a small
synthetic stall rectangle. One row per stall in parking_spaces.

Usage:
    python import_parking_spaces.py
"""
import sys

import requests

from common import (
    WARSAW_BBOX,
    centroid,
    connect,
    local_frame,
    polygon_wkt,
    rect_ring,
)

OVERPASS_URL = "https://overpass-api.de/api/interpreter"
HEADERS = {"User-Agent": "ParkingBoss/0.1 (+https://github.com/Parkingowyboss/ParkingBoss67)"}

# Default stall footprint for nodes (no mapped polygon), metres.
NODE_LEN = 4.8
NODE_WID = 2.4

OVERPASS_QUERY = """
[out:json][timeout:240];
(
  node["amenity"="parking_space"]({bbox});
  way["amenity"="parking_space"]({bbox});
);
out geom;
""".strip()


def _bbox_str():
    s, w, n, e = WARSAW_BBOX
    return f"{s},{w},{n},{e}"


def fetch():
    print("[spaces] querying Overpass for parking_space (with geometry)...")
    resp = requests.post(
        OVERPASS_URL,
        data={"data": OVERPASS_QUERY.format(bbox=_bbox_str())},
        headers=HEADERS,
        timeout=300,
    )
    resp.raise_for_status()
    return resp.json().get("elements", [])


def _bool(tags, key):
    v = tags.get(key)
    if v in ("yes", "true", "1", "designated"):
        return True
    if v in ("no", "false", "0"):
        return False
    return None


def _node_outline(lat, lon):
    """A small north-aligned stall rectangle around a node."""
    to_m, to_geo = local_frame(lat, lon)
    ring_m = rect_ring(0.0, 0.0, 0.0, 1.0, NODE_LEN, NODE_WID)  # long axis north
    ring = [to_geo(x, y) for x, y in ring_m]
    return polygon_wkt(ring)


def normalize(elements):
    rows = []
    for el in elements:
        tags = el.get("tags", {})
        base = {
            "source": "osm",
            "source_id": f"{el['type']}/{el['id']}",
            "ref": tags.get("ref"),
            "fee": _bool(tags, "fee"),
            "disabled": _bool(tags, "wheelchair") or (tags.get("parking_space") == "disabled") or None,
        }

        if el.get("type") == "node":
            lat, lon = el.get("lat"), el.get("lon")
            if lat is None or lon is None:
                continue
            base.update(lat=lat, lng=lon, outline=_node_outline(lat, lon))
            rows.append(base)
        else:
            geometry = el.get("geometry") or []
            ring = [(g["lat"], g["lon"]) for g in geometry if g.get("lat") is not None]
            if len(ring) < 3:
                continue
            clat, clng = centroid(ring)
            base.update(lat=clat, lng=clng, outline=polygon_wkt(ring))
            rows.append(base)
    return rows


UPSERT = """
    INSERT INTO parking_spaces (lat, lng, source, source_id, ref, fee, disabled, outline)
    VALUES (%(lat)s, %(lng)s, %(source)s, %(source_id)s, %(ref)s, %(fee)s, %(disabled)s,
            ST_GeomFromText(%(outline)s, 4326))
    ON CONFLICT (source, source_id) WHERE source_id IS NOT NULL
    DO UPDATE SET
        lat = EXCLUDED.lat,
        lng = EXCLUDED.lng,
        ref = EXCLUDED.ref,
        fee = EXCLUDED.fee,
        disabled = EXCLUDED.disabled,
        outline = EXCLUDED.outline,
        last_updated = now();
"""


def main():
    elements = fetch()
    print(f"[spaces] {len(elements)} elements fetched")
    rows = normalize(elements)
    n_poly = sum(1 for el in elements if el.get("type") == "way")
    print(f"[spaces] {len(rows)} stalls ({n_poly} with real polygons)")
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
