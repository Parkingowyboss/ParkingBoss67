"""Generate individual on-street parking stalls from OSM road parking tags.

On-street parking in OSM is described on the road *way* (parking:lane:* legacy
schema and the newer parking:left/right/both schema) — not as points. This
script slices each parking lane into individual stalls, offset to the correct
side of the road, and stores them as source='street'.

It is a FULL REFRESH of street-generated stalls: every run deletes the previous
source='street' rows (and their reports) and regenerates. Mapped stalls
(source='osm') are untouched.

Usage:
    python generate_street_spaces.py
"""
import math
import sys

import requests

from common import WARSAW_BBOX, connect

OVERPASS_URL = "https://overpass-api.de/api/interpreter"
HEADERS = {"User-Agent": "ParkingBoss/0.1 (+https://github.com/Parkingowyboss/ParkingBoss67)"}

# Along-kerb footprint per vehicle, in metres, by orientation.
SLOT_LEN = {"parallel": 5.2, "diagonal": 3.1, "perpendicular": 2.6}
# Lateral offset from the road centreline to the parked-car row, in metres.
OFFSET_M = 4.0
# Sanity cap on stalls generated per side of one way.
MAX_PER_SIDE = 250

# Values that mean "no parking here" (or mapped separately — skip to avoid dupes).
NO_VALUES = {"no", "none", "no_parking", "no_stopping", "separate"}

OVERPASS_QUERY = """
[out:json][timeout:240];
(
  way["highway"]["parking:lane:both"]({bbox});
  way["highway"]["parking:lane:left"]({bbox});
  way["highway"]["parking:lane:right"]({bbox});
  way["highway"]["parking:both"]({bbox});
  way["highway"]["parking:left"]({bbox});
  way["highway"]["parking:right"]({bbox});
);
out geom;
""".strip()


def _bbox_str():
    s, w, n, e = WARSAW_BBOX
    return f"{s},{w},{n},{e}"


def fetch():
    print("[street] querying Overpass for on-street parking...")
    resp = requests.post(
        OVERPASS_URL,
        data={"data": OVERPASS_QUERY.format(bbox=_bbox_str())},
        headers=HEADERS,
        timeout=300,
    )
    resp.raise_for_status()
    return resp.json().get("elements", [])


def _orientation(value):
    """Map a tag value to an orientation, or None if it means 'no parking'."""
    if value is None:
        return None
    v = value.strip().lower()
    if v in NO_VALUES:
        return None
    if v in SLOT_LEN:  # parallel | diagonal | perpendicular
        return v
    # present but unspecified (lane, street_side, on_kerb, yes, marked, ...)
    return "parallel"


def _int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def side_config(tags, side):
    """Return {'orientation', 'capacity'} for one side, or None if no parking.

    Prefers the newer parking:<side>/parking:both schema, falls back to the
    legacy parking:lane:<side>/parking:lane:both schema.
    """
    # --- new schema ---
    new_val = tags.get(f"parking:{side}", tags.get("parking:both"))
    if new_val is not None:
        orient = _orientation(new_val)
        if orient is None:
            return None
        orient = (
            tags.get(f"parking:{side}:orientation")
            or tags.get("parking:both:orientation")
            or orient
        )
        if orient not in SLOT_LEN:
            orient = "parallel"
        cap = _int(tags.get(f"parking:{side}:capacity") or tags.get("parking:both:capacity"))
        return {"orientation": orient, "capacity": cap}

    # --- legacy schema ---
    legacy_val = tags.get(f"parking:lane:{side}", tags.get("parking:lane:both"))
    orient = _orientation(legacy_val)
    if orient is None:
        return None
    cap = _int(
        tags.get(f"parking:lane:{side}:capacity")
        or tags.get("parking:lane:both:capacity")
    )
    return {"orientation": orient, "capacity": cap}


def _to_local(geometry):
    """Project lat/lon nodes to local metres around the first node."""
    lat0 = geometry[0]["lat"]
    lon0 = geometry[0]["lon"]
    cos0 = math.cos(math.radians(lat0))
    pts = [
        (
            (g["lon"] - lon0) * 111_320 * cos0,
            (g["lat"] - lat0) * 111_320,
        )
        for g in geometry
    ]
    return pts, lat0, lon0, cos0


def _to_geo(x, y, lat0, lon0, cos0):
    return (lat0 + y / 111_320, lon0 + x / (111_320 * cos0))


def stalls_for_side(geometry, side, cfg, way_id):
    """Place evenly-spaced, side-offset stall points along a way."""
    pts, lat0, lon0, cos0 = _to_local(geometry)
    # Cumulative segment lengths.
    seglen, total = [], 0.0
    for i in range(len(pts) - 1):
        dx = pts[i + 1][0] - pts[i][0]
        dy = pts[i + 1][1] - pts[i][1]
        d = math.hypot(dx, dy)
        seglen.append(d)
        total += d
    if total < 1.0:
        return []

    slot = SLOT_LEN[cfg["orientation"]]
    n = cfg["capacity"] if cfg["capacity"] else int(total // slot)
    n = max(0, min(n, MAX_PER_SIDE))
    if n == 0:
        return []

    spacing = total / n
    sign = 1.0 if side == "left" else -1.0
    rows = []
    for i in range(n):
        target = (i + 0.5) * spacing
        # Walk to the segment containing `target`.
        acc, seg = 0.0, 0
        while seg < len(seglen) - 1 and acc + seglen[seg] < target:
            acc += seglen[seg]
            seg += 1
        seg_d = seglen[seg] or 1e-9
        frac = (target - acc) / seg_d
        x0, y0 = pts[seg]
        x1, y1 = pts[seg + 1]
        px = x0 + (x1 - x0) * frac
        py = y0 + (y1 - y0) * frac
        # Unit direction of travel, then left/right normal.
        dx, dy = (x1 - x0) / seg_d, (y1 - y0) / seg_d
        nx, ny = (-dy * sign, dx * sign)  # left normal is (-dy, dx)
        ox, oy = px + nx * OFFSET_M, py + ny * OFFSET_M
        lat, lng = _to_geo(ox, oy, lat0, lon0, cos0)
        rows.append({
            "lat": lat,
            "lng": lng,
            "source": "street",
            "source_id": f"street/way/{way_id}/{side}/{i}",
        })
    return rows


def build(elements):
    rows = []
    for el in elements:
        if el.get("type") != "way":
            continue
        geometry = el.get("geometry") or []
        if len(geometry) < 2:
            continue
        tags = el.get("tags", {})
        for side in ("left", "right"):
            cfg = side_config(tags, side)
            if cfg:
                rows.extend(stalls_for_side(geometry, side, cfg, el["id"]))
    return rows


INSERT = """
    INSERT INTO parking_spaces (lat, lng, source, source_id)
    VALUES (%(lat)s, %(lng)s, %(source)s, %(source_id)s);
"""


def main():
    elements = fetch()
    print(f"[street] {len(elements)} parking-tagged ways fetched")
    rows = build(elements)
    print(f"[street] {len(rows)} on-street stalls generated")
    if not rows:
        print("[street] nothing to generate")
        return
    with connect() as conn:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM parking_spaces WHERE source = 'street';")
            cur.executemany(INSERT, rows)
        conn.commit()
    print(f"[street] inserted {len(rows)} on-street stalls (full refresh)")


if __name__ == "__main__":
    try:
        main()
    except requests.HTTPError as e:
        print(f"[street] HTTP error: {e}", file=sys.stderr)
        sys.exit(1)
