const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {
  collectionToTable,
  migrationOrder,
  mapRow,
  readSource,
  validateSource,
  comparableRow,
} = require('../src/migration-lib');

const root = path.resolve(__dirname, '..');
const dataFile = path.join(root, 'data', 'wardia.json');
const schemaFile = path.join(root, 'schema.postgres.full.sql');
const postgresApi = fs.readFileSync(path.join(root, 'src', 'server-postgres.js'), 'utf8');
const jsonApi = fs.readFileSync(path.join(root, 'src', 'server-json.js'), 'utf8');

test('source JSON validation is read-only and reports unique IDs', () => {
  const before = fs.readFileSync(dataFile, 'utf8');
  const data = readSource(dataFile);
  const result = validateSource(data);
  const after = fs.readFileSync(dataFile, 'utf8');
  assert.equal(result.valid, true, result.errors.join('\n'));
  assert.deepEqual(data.employees.map((row) => row.id), [1, 2, 3, 4, 5, 6]);
  assert.deepEqual(data.notifications.map((row) => row.id), [1, 2, 3, 5]);
  assert.equal(after, before);
});

test('every source collection has a PostgreSQL target table', () => {
  const data = readSource(dataFile);
  assert.deepEqual(Object.keys(collectionToTable).sort(), migrationOrder.slice().sort());
  for (const collection of migrationOrder) {
    assert.ok(Array.isArray(data[collection]), `${collection} is missing from source`);
    assert.match(fs.readFileSync(schemaFile, 'utf8'), new RegExp(`CREATE TABLE IF NOT EXISTS ${collectionToTable[collection]}\\s*\\(`));
  }
});

test('container loading maps legacy JSON names to canonical PostgreSQL names', () => {
  const row = mapRow('container_loadings', {
    id: 4,
    shift_id: 1,
    container_no: 'C-04',
    product_name: 'فراولة',
    container_temp_before: -18,
    product_temp: -16,
    container_temp_after: -17,
    cartons: 100,
    quantity: 950,
  });
  assert.equal(row.container_temperature_before, -18);
  assert.equal(row.product_temperature, -16);
  assert.equal(row.container_temperature_after, -17);
  assert.equal(row.cartons_quantity, 100);
});

test('comparison ignores database-generated timestamps but keeps business fields', () => {
  const source = { id: 1, shift_id: 1, line_code: 'LINE-01', product_name: 'X', hour_started_at: '16:00', target_qty: 10, actual_qty: 9 };
  const target = { ...mapRow('production', source), created_at: new Date(), updated_at: new Date() };
  assert.deepEqual(comparableRow('production', source), comparableRow('production', target));
  assert.notDeepEqual(comparableRow('production', source), comparableRow('production', { ...target, actual_qty: 8 }));
});

test('date-only comparison preserves the PostgreSQL calendar date', () => {
  const source = { id: 1, shift_no: 'S-1', shift_date: '2026-08-21', starts_at: '16:00', ends_at: '00:00', status: 'RUNNING' };
  const target = { ...mapRow('shifts', source), shift_date: new Date(2026, 7, 21) };
  assert.deepEqual(comparableRow('shifts', source), comparableRow('shifts', target));
});

test('PostgreSQL API contains JSON parity routes and PostgreSQL-only table mappings', () => {
  for (const route of [
    "/api/shifts/history",
    "/api/shifts/:id/report.csv",
    "/api/shifts/:id/report.html",
    "/api/quality/fridges",
    "/api/shifts/:id/container-loadings",
  ]) {
    assert.ok(postgresApi.includes(route), `missing PostgreSQL route ${route}`);
  }
  for (const table of ['quality_checks', 'maintenance_tickets', 'inventory_transactions', 'container_loadings']) {
    assert.ok(postgresApi.includes(table), `missing PostgreSQL table ${table}`);
  }
  assert.match(postgresApi, /temperature > -10/);
  assert.match(jsonApi, /temperature > -10/);
});
