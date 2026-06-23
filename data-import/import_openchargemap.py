"""Import EV charging stations in Warsaw from OpenChargeMap.

Requires a free API key: https://openchargemap.org/site/develop/api
Set OCM_API_KEY in the environment or .env.

Usage:
    python import_openchargemap.py
"""
import json
import os
import sys

import requests

from common import WARSAW_BBOX, connect, upsert_locations

OCM_URL = "https://api.openchargemap.io/v3/poi"


def fetch():
    api_key = os.environ.get("OCM_API_KEY", "")
    if not api_key:
        print("[ocm] WARNING: OCM_API_KEY not set; requests may be rate-limited or rejected", file=sys.stderr)
    # OCM uses (lat, lng) center + distance, or a bounding box param.
    s, w, n, e = WARSAW_BBOX
    params = {
        "output": "json",
        "countrycode": "PL",
        "boundingbox": f"({n},{w}),({s},{e})",  # (topright? OCM: (lat,lng),(lat,lng))
        "maxresults": 5000,
        "compact": "true",
        "verbose": "false",
        "key": api_key,
    }
    print("[ocm] querying OpenChargeMap...")
    resp = requests.get(OCM_URL, params=params, timeout=120)
    resp.raise_for_status()
    return resp.json()


def _address(addr_info):
    if not addr_info:
        return None
    parts = [addr_info.get("AddressLine1"), addr_info.get("Town")]
    addr = ", ".join(p for p in parts if p)
    return addr or None


def normalize(pois):
    rows = []
    for poi in pois:
        addr_info = poi.get("AddressInfo") or {}
        lat = addr_info.get("Latitude")
        lng = addr_info.get("Longitude")
        if lat is None or lng is None:
            continue
        connections = poi.get("Connections") or []
        total = sum(c.get("Quantity") or 1 for c in connections) or None
        amenities = {
            "connections": [
                {
                    "type": (c.get("ConnectionType") or {}).get("Title"),
                    "power_kw": c.get("PowerKW"),
                    "quantity": c.get("Quantity"),
                }
                for c in connections
            ],
            "operator": (poi.get("OperatorInfo") or {}).get("Title"),
        }
        rows.append({
            "type": "ev_charger",
            "name": addr_info.get("Title"),
            "address": _address(addr_info),
            "lat": lat,
            "lng": lng,
            "total_spots": total,
            "amenities": json.dumps(amenities),
            "source": "openchargemap",
            "source_id": str(poi.get("ID")),
        })
    return rows


def main():
    pois = fetch()
    print(f"[ocm] {len(pois)} POIs fetched")
    rows = normalize(pois)
    print(f"[ocm] {len(rows)} rows after normalization")
    if not rows:
        print("[ocm] nothing to import")
        return
    with connect() as conn:
        n = upsert_locations(conn, rows)
    print(f"[ocm] upserted {n} locations")


if __name__ == "__main__":
    try:
        main()
    except requests.HTTPError as e:
        print(f"[ocm] HTTP error: {e}", file=sys.stderr)
        sys.exit(1)
