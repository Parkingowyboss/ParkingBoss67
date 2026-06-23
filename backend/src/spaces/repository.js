import { query } from '../db/pool.js';

export const SPACE_STATUSES = ['free', 'occupied', 'unknown'];

const SELECT_COLS = `
  id, lat, lng, ref, fee, disabled, status, status_updated_at
`;

/**
 * Stalls whose point falls inside the given bounding box.
 * @param {{minLng,minLat,maxLng,maxLat:number, statuses?:string[], limit:number}} o
 */
export async function findInBbox({ minLng, minLat, maxLng, maxLat, statuses, limit }) {
  const params = [minLng, minLat, maxLng, maxLat];
  let statusFilter = '';
  if (statuses && statuses.length) {
    params.push(statuses);
    statusFilter = `AND status = ANY($${params.length})`;
  }
  params.push(limit);

  const sql = `
    SELECT ${SELECT_COLS}
    FROM parking_spaces
    WHERE geom && ST_MakeEnvelope($1, $2, $3, $4, 4326)
      ${statusFilter}
    LIMIT $${params.length};
  `;
  const { rows } = await query(sql, params);
  return rows;
}

/** Count stalls in a bbox, by status — lets the client decide whether to render. */
export async function countInBbox({ minLng, minLat, maxLng, maxLat }) {
  const sql = `
    SELECT status, count(*)::int AS n
    FROM parking_spaces
    WHERE geom && ST_MakeEnvelope($1, $2, $3, $4, 4326)
    GROUP BY status;
  `;
  const { rows } = await query(sql, [minLng, minLat, maxLng, maxLat]);
  const counts = { free: 0, occupied: 0, unknown: 0, total: 0 };
  for (const r of rows) {
    counts[r.status] = r.n;
    counts.total += r.n;
  }
  return counts;
}

/**
 * Record a crowd-sourced report and denormalize the new status onto the stall.
 * Returns the updated stall, or null if the id doesn't exist.
 */
export async function report({ spaceId, status, clientId }) {
  const exists = await query('SELECT 1 FROM parking_spaces WHERE id = $1', [spaceId]);
  if (!exists.rowCount) return null;

  await query(
    `INSERT INTO space_reports (space_id, status, client_id) VALUES ($1, $2, $3)`,
    [spaceId, status, clientId || null]
  );
  const { rows } = await query(
    `UPDATE parking_spaces
       SET status = $2, status_source = 'user', status_updated_at = now()
     WHERE id = $1
     RETURNING ${SELECT_COLS}`,
    [spaceId, status]
  );
  return rows[0] || null;
}
