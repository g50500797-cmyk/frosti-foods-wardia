require('dotenv').config({ path: require('node:path').resolve(__dirname, '..', '.env') });

const path = require('node:path');
const { Pool } = require('pg');
const {
  collectionToTable,
  migrationOrder,
  mapRow,
  validTimestamp,
  readSource,
  validateSource,
  comparableRow,
} = require('./migration-lib');

const dataFile = path.resolve(__dirname, '..', 'data', 'wardia.json');
const mode = String(process.env.MIGRATION_MODE || '').toUpperCase()
  || (process.argv.includes('--validate-only')
    ? 'VALIDATE'
    : process.argv.includes('--dry-run')
      ? 'DRY_RUN'
      : process.argv.includes('--test') ? 'TEST' : 'APPLY');

function connectionHost(connectionString) {
  try { return new URL(connectionString).hostname; } catch { return ''; }
}

function assertSafeConnection(connectionString) {
  if (!connectionString) throw new Error('A database connection string is required for this mode');
  const host = connectionHost(connectionString);
  const isSupabase = /supabase/i.test(host);
  if (mode === 'TEST' && isSupabase) {
    throw new Error('TEST mode refuses Supabase connections; use a local/test PostgreSQL database');
  }
  if (mode === 'APPLY' && isSupabase && process.env.ALLOW_SUPABASE_MIGRATION !== 'true') {
    throw new Error('Supabase migration is blocked; explicit approval is required');
  }
}

function insertPlan(collection, row, options = {}) {
  const table = collectionToTable[collection];
  const values = mapRow(collection, row, options);
  const columns = Object.keys(values);
  return {
    table,
    columns,
    values: columns.map((column) => {
      const value = values[column];
      return ['steps_json', 'old_data_json', 'new_data_json'].includes(column)
        ? JSON.stringify(value)
        : value;
    }),
    sql: `INSERT INTO ${table} (${columns.join(', ')}) VALUES (${columns.map((_, index) => `$${index + 1}`).join(', ')})`,
  };
}

async function setSequences(client) {
  const tables = [...new Set(Object.values(collectionToTable))];
  for (const table of tables) {
    const sequence = (await client.query(
      'SELECT pg_get_serial_sequence($1, $2) AS sequence',
      [table, 'id'],
    )).rows[0].sequence;
    if (!sequence) continue;
    const maxId = (await client.query(`SELECT MAX(id) AS max_id FROM ${table}`)).rows[0].max_id;
    await client.query('SELECT setval($1::regclass, $2, $3)', [sequence, maxId || 1, Boolean(maxId)]);
  }
}

const sourceTimestampKeys = ['created_at', 'createdAt', 'timestamp', 'reading_time', 'readingTime'];

function hasSourceTimestamp(row) {
  return sourceTimestampKeys.some((key) => validTimestamp(row[key]));
}

function generatedCreatedAt(collection, row, plan) {
  if (!plan.columns.includes('created_at') || hasSourceTimestamp(row)) return null;
  return { collection, id: row.id, field: 'created_at', value: plan.values[plan.columns.indexOf('created_at')] };
}

async function verify(client, data, options = {}) {
  const mismatches = [];
  for (const collection of migrationOrder) {
    const table = collectionToTable[collection];
    const sourceRows = data[collection].map((row) => mapRow(collection, row, options));
    const targetRows = (await client.query(`SELECT * FROM ${table}`)).rows;
    if (sourceRows.length !== targetRows.length) {
      mismatches.push(`${collection}: count ${sourceRows.length} != ${targetRows.length}`);
    }

    const sourceIds = sourceRows.map((row) => Number(row.id)).sort((a, b) => a - b);
    const targetIds = targetRows.map((row) => Number(row.id)).sort((a, b) => a - b);
    if (JSON.stringify(sourceIds) !== JSON.stringify(targetIds)) {
      mismatches.push(`${collection}: ID set differs`);
    }

    const targetById = new Map(targetRows.map((row) => [Number(row.id), row]));
    for (const sourceRow of sourceRows) {
      const targetRow = targetById.get(Number(sourceRow.id));
      if (!targetRow) continue;
      if (JSON.stringify(comparableRow(collection, sourceRow))
        !== JSON.stringify(comparableRow(collection, targetRow))) {
        mismatches.push(`${collection} id ${sourceRow.id}: important fields differ`);
        if (mismatches.length > 50) return mismatches;
      }
    }
  }
  return mismatches;
}

async function migrate(data) {
  const connectionString = mode === 'TEST'
    ? process.env.TEST_DATABASE_URL
    : process.env.DATABASE_URL;
  assertSafeConnection(connectionString);
  const pool = new Pool({
    connectionString,
    ssl: process.env.PGSSL === 'true' ? { rejectUnauthorized: false } : undefined,
  });
  const client = await pool.connect();
  const fallbackAt = new Date().toISOString();
  const generatedTimestamps = [];
  let committed = false;
  try {
    await client.query('BEGIN');
    const inserted = {};
    for (const collection of migrationOrder) {
      inserted[collection] = 0;
      for (const row of data[collection]) {
        const plan = insertPlan(collection, row, { fallbackAt });
        const generated = generatedCreatedAt(collection, row, plan);
        if (generated) generatedTimestamps.push(generated);
        try {
          await client.query(plan.sql, plan.values);
        } catch (error) {
          error.message = `Migration conflict/error in ${collection} id ${row.id} (${plan.table}): ${error.message}`;
          throw error;
        }
        inserted[collection] += 1;
      }
    }
    await setSequences(client);
    await client.query('COMMIT');
    committed = true;
    const mismatches = await verify(client, data, { fallbackAt });
    if (mismatches.length) {
      const error = new Error(`Verification failed after COMMIT:\n${mismatches.join('\n')}`);
      error.mismatches = mismatches;
      throw error;
    }
    return { inserted, mismatches: [], verified: true, generatedTimestamps };
  } catch (error) {
    if (!committed) await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
    await pool.end();
  }
}

function dryRun(data) {
  const fallbackAt = new Date().toISOString();
  const generatedTimestamps = [];
  let plannedRows = 0;
  for (const collection of migrationOrder) {
    for (const row of data[collection]) {
      const plan = insertPlan(collection, row, { fallbackAt });
      plannedRows += 1;
      const generated = generatedCreatedAt(collection, row, plan);
      if (generated) generatedTimestamps.push(generated);
    }
  }
  return { plannedRows, generatedTimestamps, databaseWrites: false };
}

async function main() {
  const data = readSource(dataFile);
  const validation = validateSource(data);
  console.log(JSON.stringify({
    mode,
    source: dataFile,
    valid: validation.valid,
    errors: validation.errors,
    collections: Object.fromEntries(migrationOrder.map((name) => [name, Array.isArray(data[name]) ? data[name].length : 0])),
  }, null, 2));
  if (!validation.valid) throw new Error('Source validation failed; no database operation was attempted');
  if (mode === 'VALIDATE') return;
  if (mode === 'DRY_RUN') {
    console.log(JSON.stringify(dryRun(data), null, 2));
    return;
  }
  if (!['TEST', 'APPLY'].includes(mode)) {
    throw new Error(`Unsupported MIGRATION_MODE=${mode}; use VALIDATE, DRY_RUN, TEST, or APPLY`);
  }
  const result = await migrate(data);
  console.log(JSON.stringify(result, null, 2));
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.stack || error.message);
    process.exitCode = 1;
  });
}

module.exports = { insertPlan, setSequences, verify, migrate, dryRun, main };
