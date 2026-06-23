import { Router } from 'express';
import * as repo from './repository.js';

export const router = Router();

const MAX_RADIUS_M = 50_000;
const DEFAULT_RADIUS_M = 1_000;
const MAX_LIMIT = 500;
const DEFAULT_LIMIT = 100;

function parseNum(value) {
  if (value === undefined) return undefined;
  const n = Number(value);
  return Number.isFinite(n) ? n : NaN;
}

function clamp(n, min, max) {
  return Math.min(Math.max(n, min), max);
}

function parseTypes(raw) {
  if (!raw) return undefined;
  const types = String(raw)
    .split(',')
    .map((t) => t.trim())
    .filter(Boolean);
  const invalid = types.filter((t) => !repo.LOCATION_TYPES.includes(t));
  if (invalid.length) {
    const err = new Error(`invalid type(s): ${invalid.join(', ')}`);
    err.status = 400;
    throw err;
  }
  return types.length ? types : undefined;
}

// GET /locations?lat=&lng=&radius=&type=&limit=
router.get('/', async (req, res, next) => {
  try {
    const lat = parseNum(req.query.lat);
    const lng = parseNum(req.query.lng);
    if (lat === undefined || lng === undefined) {
      return res.status(400).json({ error: 'lat and lng are required' });
    }
    if (Number.isNaN(lat) || Number.isNaN(lng) || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      return res.status(400).json({ error: 'lat/lng out of range' });
    }

    const radius = clamp(parseNum(req.query.radius) || DEFAULT_RADIUS_M, 1, MAX_RADIUS_M);
    const limit = clamp(parseNum(req.query.limit) || DEFAULT_LIMIT, 1, MAX_LIMIT);
    const types = parseTypes(req.query.type);

    const items = await repo.findNearby({ lat, lng, radius, types, limit });
    res.json({ count: items.length, radius, items });
  } catch (err) {
    next(err);
  }
});

// GET /locations/search?q=&limit=
// (registered before /:id so "search" isn't treated as an id)
router.get('/search', async (req, res, next) => {
  try {
    const q = (req.query.q || '').toString().trim();
    if (q.length < 2) {
      return res.status(400).json({ error: 'q must be at least 2 characters' });
    }
    const limit = clamp(parseNum(req.query.limit) || 20, 1, 50);
    const items = await repo.search({ q, limit });
    res.json({ count: items.length, items });
  } catch (err) {
    next(err);
  }
});

// GET /locations/:id
router.get('/:id', async (req, res, next) => {
  try {
    const item = await repo.findById(req.params.id);
    if (!item) return res.status(404).json({ error: 'not found' });
    res.json(item);
  } catch (err) {
    // Invalid UUID → 400 rather than 500
    if (err.code === '22P02') return res.status(400).json({ error: 'invalid id' });
    next(err);
  }
});
