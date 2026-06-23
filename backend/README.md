# ParkingBoss Backend

Node.js + Express API serving Warsaw parking, EV charger and gas station
locations from PostgreSQL + PostGIS. Covers ROADMAP steps 2–5.

## Prerequisites

- Node.js >= 20
- A PostgreSQL 16 + PostGIS database (use the bundled `docker-compose.yml`)
- Python 3.11+ for the data-import scripts

## Setup

```bash
# 1. Start the database (from repo root)
docker compose up -d

# 2. Configure and install
cd backend
cp .env.example .env
npm install

# 3. Create the schema
npm run db:migrate

# 4. Run the API
npm run dev        # auto-reload
# or: npm start
```

API is now on http://localhost:3000

## Load data (repo root → data-import/)

```bash
cd ../data-import
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
# set OCM_API_KEY in your environment or a .env for EV chargers
python import_osm.py             # parking + fuel stations from OpenStreetMap
python import_openchargemap.py   # EV chargers from OpenChargeMap
```

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Liveness + DB readiness |
| GET | `/locations?lat=&lng=&radius=&type=&limit=` | Locations within `radius` m of a point, nearest first. `type` is comma-separated. |
| GET | `/locations/search?q=&limit=` | Fuzzy search by name/address |
| GET | `/locations/:id` | Single location by UUID |
| GET | `/spaces?bbox=minLng,minLat,maxLng,maxLat&status=&limit=` | Individual stalls in a map rectangle (bbox capped to ~6 km/side) |
| GET | `/spaces/count?bbox=...` | Stall counts by status for a rectangle |
| POST | `/spaces/:id/report` | Crowd-sourced occupancy report `{ "status": "free"\|"occupied", "clientId": "..." }` |

`type` values: `parking_public`, `parking_private`, `ev_charger`, `gas_station`.
`status` values (stalls): `free`, `occupied`, `unknown`.

Load individual stalls with `python import_parking_spaces.py` (OSM `amenity=parking_space`).

Example:

```bash
curl "http://localhost:3000/locations?lat=52.2297&lng=21.0122&radius=1000&type=parking_public,ev_charger"
```
