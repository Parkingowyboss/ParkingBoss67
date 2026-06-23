import 'dotenv/config';

function int(name, fallback) {
  const v = process.env[name];
  if (v === undefined || v === '') return fallback;
  const n = Number(v);
  return Number.isFinite(n) ? n : fallback;
}

export const config = {
  port: int('PORT', 3000),
  env: process.env.NODE_ENV || 'development',
  databaseUrl:
    process.env.DATABASE_URL ||
    'postgres://parkingboss:parkingboss@localhost:5432/parkingboss',
  corsOrigin: process.env.CORS_ORIGIN || '*',
  rateLimit: {
    windowMs: int('RATE_LIMIT_WINDOW_MS', 60_000),
    max: int('RATE_LIMIT_MAX', 120),
  },
  ocmApiKey: process.env.OCM_API_KEY || '',
};
