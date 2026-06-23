-- ParkingBoss schema (PostgreSQL + PostGIS)
-- Idempotent: safe to run repeatedly.

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pg_trgm;  -- fuzzy text search for /search

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'location_type') THEN
    CREATE TYPE location_type AS ENUM (
      'parking_public',
      'parking_private',
      'ev_charger',
      'gas_station'
    );
  END IF;
END$$;

CREATE TABLE IF NOT EXISTS locations (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  type            location_type NOT NULL,
  name            VARCHAR(255),
  address         TEXT,
  lat             DOUBLE PRECISION NOT NULL,
  lng             DOUBLE PRECISION NOT NULL,
  total_spots     INTEGER,
  available_spots INTEGER,
  price_per_hour  NUMERIC(6, 2),
  currency        VARCHAR(3) NOT NULL DEFAULT 'PLN',
  open_hours      JSONB,
  amenities       JSONB,
  -- provenance: where this record came from, e.g. 'osm', 'openchargemap'
  source          VARCHAR(32) NOT NULL DEFAULT 'manual',
  source_id       VARCHAR(128),
  last_updated    TIMESTAMPTZ NOT NULL DEFAULT now(),
  geom            GEOMETRY(Point, 4326) NOT NULL
);

-- Spatial index: powers GET /locations?lat&lng&radius (ST_DWithin)
CREATE INDEX IF NOT EXISTS locations_geom_idx ON locations USING GIST (geom);

-- Filter by type quickly
CREATE INDEX IF NOT EXISTS locations_type_idx ON locations (type);

-- Fuzzy name/address search for /search
CREATE INDEX IF NOT EXISTS locations_name_trgm_idx ON locations USING GIN (name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS locations_address_trgm_idx ON locations USING GIN (address gin_trgm_ops);

-- Dedupe imports: one row per (source, source_id)
CREATE UNIQUE INDEX IF NOT EXISTS locations_source_unique_idx
  ON locations (source, source_id)
  WHERE source_id IS NOT NULL;

-- Keep geom in sync with lat/lng on insert/update.
CREATE OR REPLACE FUNCTION locations_sync_geom() RETURNS trigger AS $$
BEGIN
  NEW.geom := ST_SetSRID(ST_MakePoint(NEW.lng, NEW.lat), 4326);
  NEW.last_updated := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS locations_geom_trigger ON locations;
CREATE TRIGGER locations_geom_trigger
  BEFORE INSERT OR UPDATE OF lat, lng ON locations
  FOR EACH ROW EXECUTE FUNCTION locations_sync_geom();
