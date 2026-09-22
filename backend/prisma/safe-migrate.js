const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient({ log: ['error'] });

const columns = [
  ['Comment', 'userId', 'TEXT'],
  ['Post', 'body', 'TEXT'],
  ['Message', 'conversationId', 'TEXT'],
  ['Message', 'body', 'TEXT'],
  ['Notification', 'title', 'TEXT'],
  ['Notification', 'body', 'TEXT'],
  ['VerificationRequest', 'reason', 'TEXT'],
  ['VerificationRequest', 'updatedAt', 'TIMESTAMP(3)']
];

async function ensureColumn(tx, table, column, type) {
  const exists = await tx.$queryRaw`
    SELECT 1 FROM pg_catalog.pg_attribute a
    JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname='public' AND c.relname=${table} AND a.attname=${column}
      AND a.attnum>0 AND NOT a.attisdropped LIMIT 1`;
  if (!exists.length) {
    await tx.$executeRawUnsafe(`ALTER TABLE public."${table}" ADD COLUMN IF NOT EXISTS "${column}" ${type}`);
    console.log(`Ensured nullable public."${table}"."${column}"`);
  } else {
    console.log(`Already present public."${table}"."${column}"`);
  }
}

async function assertColumn(tx, table, column) {
  const rows = await tx.$queryRaw`
    SELECT 1 FROM pg_catalog.pg_attribute a
    JOIN pg_catalog.pg_class c ON c.oid=a.attrelid
    JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relname=${table} AND a.attname=${column}
      AND a.attnum>0 AND NOT a.attisdropped LIMIT 1`;
  if (!rows.length) throw new Error(`SAFE_MIGRATION_VERIFY_FAILED: public."${table}"."${column}" missing`);
}

async function main() {
  const identity = await prisma.$queryRaw`SELECT current_database() AS database, current_schema() AS schema, current_user AS db_user, inet_server_addr()::text AS server_addr, inet_server_port() AS server_port`;
  console.log('Database target:', JSON.stringify(identity[0]));

  const userTable = await prisma.$queryRaw`SELECT to_regclass('public."User"')::text AS table_name`;
  if (!userTable[0]?.table_name) throw new Error('SAFE_MIGRATION_ABORTED: public."User" not found. No changes made.');

  const sharedDisplayName = await prisma.$queryRaw`SELECT 1 FROM pg_catalog.pg_attribute a JOIN pg_catalog.pg_class c ON c.oid=a.attrelid JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname='User' AND a.attname='displayName' AND a.attnum>0 AND NOT a.attisdropped LIMIT 1`;
  if (!sharedDisplayName.length) throw new Error('SAFE_MIGRATION_ABORTED: shared public."User"."displayName" is required by this deployment but was not found. No changes made.');
  console.log('Verified existing shared public."User"."displayName" column; no change made to User table.');

  await prisma.$transaction(async (tx) => {
    for (const [table, column, type] of columns) await ensureColumn(tx, table, column, type);

    // Isolate the display name for this app. This avoids changing the shared User table.
    await tx.$executeRawUnsafe(`CREATE TABLE IF NOT EXISTS public."SawtAljazairProfile" (\n      "id" TEXT NOT NULL PRIMARY KEY,\n      "userId" TEXT NOT NULL UNIQUE,\n      "displayName" TEXT,\n      "wilaya" TEXT,\n      "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,\n      "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP\n    )`);
    await tx.$executeRawUnsafe(`ALTER TABLE public."SawtAljazairProfile" ADD COLUMN IF NOT EXISTS "wilaya" TEXT`);
    console.log('Ensured isolated public."SawtAljazairProfile" table and wilaya');

    for (const [table, column] of columns) await assertColumn(tx, table, column);
    await assertColumn(tx, 'SawtAljazairProfile', 'wilaya');
  });

  // Fresh-connection verification after commit.
  for (const [table, column] of columns) await assertColumn(prisma, table, column);
  const profile = await prisma.$queryRaw`SELECT to_regclass('public."SawtAljazairProfile"')::text AS table_name`;
  if (!profile[0]?.table_name) throw new Error('SAFE_MIGRATION_POST_COMMIT_VERIFY_FAILED: profile table missing');
  await assertColumn(prisma, 'SawtAljazairProfile', 'wilaya');

  console.log('Safe migration completed and verified. No shared tables were dropped or reset. User.displayName is required by the existing shared User table; User.name and User.wilaya are isolated in SawtAljazairProfile.');
}

main().catch(e => { console.error(e); process.exitCode=1; }).finally(async()=>{ await prisma.$disconnect(); });
