import { Router } from 'express';
import * as repo from './repository.js';

export const router = Router();

const MAX_LIMIT = 4000;
const DEFAULT_LIMIT = 2000;
// Guard against "give me every stall in Warsaw" — bbox must be a local view.
// ~0.05 deg lat ≈ 5.5 km; lng a bit wider. Keeps payloads to a city district.
const MAX_BBOX_DEG = 0.06;

function parseNum(v) {
  if (v === undefined) return undefined;
  const n = Number(v);
  return Number.isFinite(n) ? n : NaN;
}

function clamp(n, min, max) {
  return Math.min(Math.max(n, min), max);
}

function parseStatuses(raw) {
  if (!raw) return undefined;
  const list = String(raw).split(',').map((s) => s.trim()).filter(Boolean);
  const invalid = list.filter((s) => !repo.SPACE_STATUSES.includes(s));
  if (invalid.length) {
    const err = new Error(`invalid status(es): ${invalid.join(', ')}`);
    err.status = 400;
    throw err;
  }
  return list.length ? list : undefined;
}

// Parse and validate a "minLng,minLat,maxLng,maxLat" bbox.
function parseBbox(raw) {
  if (!raw) {
    const err = new Error('bbox is required (minLng,minLat,maxLng,maxLat)');
    err.status = 400;
    throw err;
  }
  const parts = String(raw).split(',').map(Number);
  if (parts.length !== 4 || parts.some((n) => !Number.isFinite(n))) {
    const err = new Error('bbox must be minLng,minLat,maxLng,maxLat');
    err.status = 400;
    throw err;
  }
  let [minLng, minLat, maxLng, maxLat] = parts;
  if (minLng > maxLng) [minLng, maxLng] = [maxLng, minLng];
  if (minLat > maxLat) [minLat, maxLat] = [maxLat, minLat];
  if (maxLng - minLng > MAX_BBOX_DEG || maxLat - minLat > MAX_BBOX_DEG) {
    const err = new Error(`bbox too large; max ${MAX_BBOX_DEG} deg per side (zoom in)`);
    err.status = 422;
    throw err;
  }
  return { minLng, minLat, maxLng, maxLat };
}

// GET /spaces?bbox=minLng,minLat,maxLng,maxLat&status=&limit=
router.get('/', async (req, res, next) => {
  try {
    const bbox = parseBbox(req.query.bbox);
    const statuses = parseStatuses(req.query.status);
    const limit = clamp(parseNum(req.query.limit) || DEFAULT_LIMIT, 1, MAX_LIMIT);
    const items = await repo.findInBbox({ ...bbox, statuses, limit });
    res.json({ count: items.length, capped: items.length >= limit, items });
  } catch (err) {
    next(err);
  }
});

// GET /spaces/count?bbox=... — cheap "how many stalls here" probe
router.get('/count', async (req, res, next) => {
  try {
    const bbox = parseBbox(req.query.bbox);
    res.json(await repo.countInBbox(bbox));
  } catch (err) {
    next(err);
  }
});

// POST /spaces/:id/report  { status: "free"|"occupied", clientId? }
router.post('/:id/report', async (req, res, next) => {
  try {
    const status = (req.body?.status || '').toString();
    if (!repo.SPACE_STATUSES.includes(status)) {
      return res.status(400).json({ error: 'status must be free, occupied or unknown' });
    }
    const updated = await repo.report({
      spaceId: req.params.id,
      status,
      clientId: req.body?.clientId,
    });
    if (!updated) return res.status(404).json({ error: 'not found' });
    res.json(updated);
  } catch (err) {
    if (err.code === '22P02') return res.status(400).json({ error: 'invalid id' });
    next(err);
  }
});
