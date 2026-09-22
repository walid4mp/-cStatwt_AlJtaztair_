const { spawnSync } = require('child_process');
const path = require('path');
const { PrismaClient } = require('@prisma/client');
const bcrypt = require('bcryptjs');

async function main() {
  if (String(process.env.DEDICATED_DATABASE || '').toLowerCase() !== 'true') {
    throw new Error('BOOTSTRAP_ABORTED: Set DEDICATED_DATABASE=true only when DATABASE_URL points to the dedicated Sawt Aljazair PostgreSQL database.');
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
  try {
    const email = String(process.env.TEST_ACCOUNT_EMAIL || 'sawt.test.2026@example.com').trim().toLowerCase();
    const username = String(process.env.TEST_ACCOUNT_USERNAME || 'sawt_test_2026').trim();
    const displayName = String(process.env.TEST_ACCOUNT_NAME || 'Sawt Aljazair Test').trim();
    const wilaya = String(process.env.TEST_ACCOUNT_WILAYA || 'وهران').trim();
    const password = String(process.env.TEST_ACCOUNT_PASSWORD || 'SawtTest@2026!');
    const passwordHash = await bcrypt.hash(password, 12);

    const existing = await prisma.user.findFirst({ where: { OR: [{ email }, { username }] } });
    if (existing) {
      console.log(`Test account already exists: ${email}`);
    } else {
      const user = await prisma.user.create({
        data: {
          username,
          displayName,
          email,
          passwordHash,
          role: 'USER',
          isVerified: false,
          bio: 'حساب تجريبي لصوت الجزائر'
        }
      });
      await prisma.sawtAljazairProfile.upsert({
        where: { userId: user.id },
        create: { userId: user.id, displayName, wilaya },
        update: { displayName, wilaya }
      });
      console.log(`Test account created: ${email}`);
    }
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((e) => { console.error(e); process.exit(1); });
