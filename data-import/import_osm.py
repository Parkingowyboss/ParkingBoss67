"""Import parking lots and fuel stations in Warsaw from OpenStreetMap (Overpass API).

Usage:
    python import_osm.py
"""
import json
import sys

import requests

from common import WARSAW_BBOX, connect, upsert_locations

OVERPASS_URL = "https://overpass-api.de/api/interpreter"

# Overpass rejects the default python-requests UA with HTTP 406.
HEADERS = {"User-Agent": "ParkingBoss/0.1 (+https://github.com/Parkingowyboss/ParkingBoss67)"}

# amenity=parking -> parking, amenity=fuel -> gas_station
OVERPASS_QUERY = """
[out:json][timeout:120];
(
  node["amenity"="parking"]({bbox});
  way["amenity"="parking"]({bbox});
  node["amenity"="fuel"]({bbox});
  way["amenity"="fuel"]({bbox});
);
out center tags;
""".strip()


def _bbox_str():
    s, w, n, e = WARSAW_BBOX
    return f"{s},{w},{n},{e}"


def fetch():
    query = OVERPASS_QUERY.format(bbox=_bbox_str())
    print("[osm] querying Overpass API...")
    resp = requests.post(OVERPASS_URL, data={"data": query}, headers=HEADERS, timeout=180)
    resp.raise_for_status()
    return resp.json().get("elements", [])


def _coords(el):
    if el.get("type") == "node":
        return el.get("lat"), el.get("lon")
    center = el.get("center") or {}
    return center.get("lat"), center.get("lon")


def _classify(tags):
    amenity = tags.get("amenity")
    if amenity == "fuel":
        return "gas_station"
    # access=private/customers -> private parking, otherwise public
    access = tags.get("access")
    if access in ("private", "customers", "permit"):
        return "parking_private"
    return "parking_public"


def _address(tags):
    parts = [
        tags.get("addr:street"),
        tags.get("addr:housenumber"),
        tags.get("addr:city"),
    ]
    addr = " ".join(p for p in parts if p)
    return addr or None


def _int(tags, key):
    try:
        return int(tags[key])
    except (KeyError, ValueError, TypeError):
        return None


def normalize(elements):
    rows = []
    for el in elements:
        lat, lng = _coords(el)
        if lat is None or lng is None:
            continue
        tags = el.get("tags", {})
        loc_type = _classify(tags)
        amenities = {}
        for k in ("operator", "brand", "fee", "capacity:disabled", "surface"):
            if k in tags:
                amenities[k] = tags[k]
        rows.append({
            "type": loc_type,
            "name": tags.get("name") or tags.get("operator") or tags.get("brand"),
            "address": _address(tags),
            "lat": lat,
            "lng": lng,
            "total_spots": _int(tags, "capacity"),
            "open_hours": json.dumps({"raw": tags["opening_hours"]}) if "opening_hours" in tags else None,
            "amenities": json.dumps(amenities) if amenities else None,
            "source": "osm",
            "source_id": f"{el['type']}/{el['id']}",
        })
    return rows


def main():
    elements = fetch()
    print(f"[osm] {len(elements)} elements fetched")
    rows = normalize(elements)
    print(f"[osm] {len(rows)} rows after normalization")
    if not rows:
        print("[osm] nothing to import")
        return
    with connect() as conn:
        n = upsert_locations(conn, rows)
    print(f"[osm] upserted {n} locations")


if __name__ == "__main__":
    try:
        main()
    except requests.HTTPError as e:
        print(f"[osm] HTTP error: {e}", file=sys.stderr)
        sys.exit(1)
