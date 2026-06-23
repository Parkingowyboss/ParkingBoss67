import { query } from '../db/pool.js';

export const LOCATION_TYPES = [
  'parking_public',
  'parking_private',
  'ev_charger',
  'gas_station',
];

// Columns returned to clients. distance_m is appended by spatial queries.
const SELECT_COLS = `
  id, type, name, address, lat, lng,
  total_spots, available_spots, price_per_hour, currency,
  open_hours, amenities, source, last_updated
`;

/**
 * Locations within `radius` metres of (lat, lng), nearest first.
 * @param {{lat:number, lng:number, radius:number, types?:string[], limit:number}} opts
 */
export async function findNearby({ lat, lng, radius, types, limit }) {
  const params = [lng, lat, radius];
  let typeFilter = '';
  if (types && types.length) {
    params.push(types);
    typeFilter = `AND type = ANY($${params.length})`;
  }
  params.push(limit);

  const sql = `
    SELECT ${SELECT_COLS},
           ST_Distance(geom::geography, ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography) AS distance_m
    FROM locations
    WHERE ST_DWithin(geom::geography, ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography, $3)
      ${typeFilter}
    ORDER BY distance_m ASC
    LIMIT $${params.length};
  `;
  const { rows } = await query(sql, params);
  return rows;
}

export async function findById(id) {
  const sql = `SELECT ${SELECT_COLS} FROM locations WHERE id = $1;`;
  const { rows } = await query(sql, [id]);
  return rows[0] || null;
}

/**
 * Fuzzy search by name/address using pg_trgm similarity.
 * @param {{q:string, limit:number}} opts
 */
export async function search({ q, limit }) {
  const sql = `
    SELECT ${SELECT_COLS},
           GREATEST(
             similarity(coalesce(name, ''), $1),
             similarity(coalesce(address, ''), $1)
           ) AS score
    FROM locations
    WHERE name ILIKE '%' || $1 || '%'
       OR address ILIKE '%' || $1 || '%'
    ORDER BY score DESC
    LIMIT $2;
  `;
  const { rows } = await query(sql, [q, limit]);
  return rows;
}
