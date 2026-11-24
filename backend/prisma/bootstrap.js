const { spawnSync } = require('child_process');
const path = require('path');
const { PrismaClient } = require('@prisma/client');

async function main() {
  if (String(process.env.DEDICATED_DATABASE || '').toLowerCase() !== 'true') {
    throw new Error('BOOTSTRAP_ABORTED: add the environment variable DEDICATED_DATABASE=true in Render (Environment tab). Use it only when DATABASE_URL points to the PostgreSQL database dedicated to Sawt Aljazair.');
  }
  if (!process.env.DATABASE_URL) throw new Error('DATABASE_URL is required');

  const prismaBin = path.join(__dirname, '..', 'node_modules', '.bin', 'prisma');
  console.log('Initializing dedicated Sawt Aljazair database schema...');
  const result = spawnSync(prismaBin, ['db', 'push', '--skip-generate'], { stdio: 'inherit', env: process.env });
  if (result.status !== 0) throw new Error(`PRISMA_DB_PUSH_FAILED: exit code ${result.status}`);

  const prisma = new PrismaClient();
  // Never continue with an API that cannot see the core application tables.
  // This prevents confusing 404/P2021 errors when Render points to the wrong database.
  const coreTables = await prisma.$queryRawUnsafe(`SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND table_name IN ('User','Report','Post','SawtAljazairProfile') ORDER BY table_name`);
  const found = coreTables.map(x => x.table_name);
  console.log(`Core database tables detected: ${found.join(', ') || '(none)'}`);
  for (const required of ['User','Report','SawtAljazairProfile']) {
    if (!found.includes(required)) throw new Error(`DATABASE_SCHEMA_INCOMPLETE: required table public."${required}" was not found after prisma db push`);
  }
  await prisma.$disconnect();
}

main().catch((e) => { console.error(e); process.exit(1); });
