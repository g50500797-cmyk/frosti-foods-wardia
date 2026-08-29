const fs = require('node:fs');

const collectionToTable = Object.freeze({
  roles: 'roles',
  users: 'users',
  shifts: 'shifts',
  attendance: 'attendance',
  employees: 'employees',
  attendance_records: 'attendance_records',
  production: 'production_hourly',
  product_guides: 'product_guides',
  fridges: 'fridges',
  fridge_readings: 'fridge_readings',
  quality: 'quality_checks',
  raw_receipts: 'raw_receipts',
  packaging_receipts: 'packaging_receipts',
  supplies: 'supplies',
  downtime: 'downtime',
  maintenance: 'maintenance_tickets',
  inventory: 'inventory_transactions',
  notifications: 'notifications',
  problems: 'problems',
  container_loadings: 'container_loadings',
  audit: 'audit_logs',
});

const migrationOrder = Object.freeze([
  'roles',
  'users',
  'shifts',
  'employees',
  'attendance',
  'attendance_records',
  'product_guides',
  'fridges',
  'fridge_readings',
  'production',
  'quality',
  'raw_receipts',
  'packaging_receipts',
  'supplies',
  'downtime',
  'maintenance',
  'inventory',
  'notifications',
  'problems',
  'container_loadings',
  'audit',
]);

function asArray(value) {
  return Array.isArray(value) ? value : [];
}

function readSource(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function numberOrNull(value) {
  return value === undefined || value === null || value === '' ? null : Number(value);
}

function validTimestamp(value) {
  if (value === undefined || value === null || value === '') return null;
  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? null : value.toISOString();
  }
  const candidate = String(value);
  const parsed = Date.parse(candidate);
  return Number.isNaN(parsed) ? null : new Date(parsed).toISOString();
}

function resolveCreatedAt(row, fallbackAt) {
  return resolveTimestamp(row, fallbackAt, ['created_at', 'createdAt', 'timestamp', 'reading_time', 'readingTime']);
}

function resolveTimestamp(row, fallbackAt, keys) {
  for (const key of keys) {
    const resolved = validTimestamp(row[key]);
    if (resolved) return resolved;
  }
  return fallbackAt;
}

const dateOnlyFields = new Set([
  'shift_date',
  'start_date',
  'attendance_date',
  'receipt_date',
  'problem_date',
  'reading_date',
]);

const timestampFields = new Set([
  'created_at',
  'updated_at',
  'opened_at',
  'closed_at',
  'approved_at',
  'inspected_at',
  'received_at',
  'started_at',
  'ended_at',
  'reported_at',
  'repaired_at',
  'resolved_at',
  'loaded_at',
]);

function normalizeDateOnly(value) {
  if (value instanceof Date) {
    if (Number.isNaN(value.getTime())) return null;
    return [
      value.getFullYear(),
      String(value.getMonth() + 1).padStart(2, '0'),
      String(value.getDate()).padStart(2, '0'),
    ].join('-');
  }
  const text = String(value ?? '');
  const dateMatch = text.match(/^(\d{4}-\d{2}-\d{2})/);
  if (dateMatch) return dateMatch[1];
  const timestamp = validTimestamp(value);
  return timestamp ? timestamp.slice(0, 10) : value;
}

function normalizeComparableValue(key, value) {
  if (value === null || value === undefined) return null;
  if (dateOnlyFields.has(key)) return normalizeDateOnly(value);
  if (timestampFields.has(key)) return validTimestamp(value) || value;
  return value;
}

function validateSource(data) {
  const errors = [];
  for (const collection of migrationOrder) {
    if (!Array.isArray(data[collection])) errors.push(`${collection}: collection must be an array`);
  }

  for (const collection of migrationOrder) {
    const ids = new Set();
    for (const row of asArray(data[collection])) {
      if (!row || !Number.isInteger(Number(row.id)) || Number(row.id) <= 0) {
        errors.push(`${collection}: every row needs a positive integer id`);
        continue;
      }
      const id = Number(row.id);
      if (ids.has(id)) errors.push(`${collection}: duplicate id ${id}`);
      ids.add(id);
    }
  }

  const references = [
    ['shifts', 'manager_id', 'users'],
    ['attendance', 'shift_id', 'shifts'],
    ['attendance_records', 'shift_id', 'shifts'],
    ['attendance_records', 'employee_id', 'employees'],
    ['production', 'shift_id', 'shifts'],
    ['fridge_readings', 'shift_id', 'shifts'],
    ['fridge_readings', 'fridge_id', 'fridges'],
    ['fridge_readings', 'engineer_id', 'users'],
    ['quality', 'shift_id', 'shifts'],
    ['quality', 'created_by', 'users'],
    ['raw_receipts', 'created_by', 'users'],
    ['packaging_receipts', 'created_by', 'users'],
    ['supplies', 'shift_id', 'shifts'],
    ['downtime', 'shift_id', 'shifts'],
    ['maintenance', 'shift_id', 'shifts'],
    ['inventory', 'shift_id', 'shifts'],
    ['inventory', 'created_by', 'users'],
    ['notifications', 'shift_id', 'shifts'],
    ['problems', 'shift_id', 'shifts'],
    ['problems', 'created_by', 'users'],
    ['problems', 'updated_by', 'users'],
    ['problems', 'source_notification_id', 'notifications'],
    ['container_loadings', 'shift_id', 'shifts'],
    ['container_loadings', 'created_by', 'users'],
    ['audit', 'user_id', 'users'],
  ];
  for (const [collection, field, target] of references) {
    const targetIds = new Set(asArray(data[target]).map((row) => Number(row.id)));
    for (const row of asArray(data[collection])) {
      if (row[field] !== undefined && row[field] !== null && !targetIds.has(Number(row[field]))) {
        errors.push(`${collection} id ${row.id}: ${field} references missing ${target} id ${row[field]}`);
      }
    }
  }

  const attendanceStatuses = new Set(['PRESENT', 'LATE', 'MISSION', 'LEAVE', 'ABSENT_EXCUSED', 'ABSENT_UNEXCUSED']);
  for (const row of asArray(data.attendance_records)) {
    if (!attendanceStatuses.has(String(row.status))) errors.push(`attendance_records id ${row.id}: invalid status ${row.status}`);
  }
  for (const row of asArray(data.fridge_readings)) {
    if (!Number.isFinite(Number(row.temperature))) {
      errors.push(`fridge_readings id ${row.id}: invalid temperature`);
    } else {
      const calculatedStatus = Number(row.temperature) > -10 ? 'DEFROST' : 'NORMAL';
      if (row.status && row.status !== calculatedStatus) {
        errors.push(`fridge_readings id ${row.id}: status ${row.status} disagrees with calculated ${calculatedStatus}`);
      }
    }
  }
  for (const row of asArray(data.container_loadings)) {
    for (const field of ['container_temperature_before', 'product_temperature', 'container_temperature_after', 'cartons', 'quantity']) {
      if (!Number.isFinite(Number(row[field] ?? row[field.replace('temperature_', 'temp_')]))) {
        errors.push(`container_loadings id ${row.id}: invalid ${field}`);
      }
    }
  }
  return { valid: errors.length === 0, errors };
}

function mapRow(collection, row, options = {}) {
  const fallbackAt = options.fallbackAt || new Date().toISOString();
  switch (collection) {
    case 'roles':
      return { id: row.id, code: row.code, name: row.name };
    case 'users':
      return { id: row.id, name: row.name, email: row.email, password_hash: row.password_hash, role_code: row.role_code, department: row.department ?? null, is_active: row.is_active !== false, created_at: resolveCreatedAt(row, fallbackAt) };
    case 'shifts':
      return { id: row.id, shift_no: row.shift_no, shift_date: row.shift_date, starts_at: row.starts_at, ends_at: row.ends_at, status: row.status, manager_id: row.manager_id ?? null, opened_at: row.opened_at ?? null, closed_at: row.closed_at ?? null, approved_at: row.approved_at ?? null, created_at: resolveCreatedAt(row, fallbackAt) };
    case 'attendance':
      return { id: row.id, shift_id: row.shift_id, department: row.department, required_count: row.required_count, present_count: row.present_count, absent_count: row.absent_count, late_count: row.late_count ?? 0, overtime_count: row.overtime_count ?? 0, notes: row.notes ?? null, created_at: resolveCreatedAt(row, fallbackAt) };
    case 'employees':
      return { id: row.id, employee_no: row.employee_no, name: row.name, department: row.department, job_title: row.job_title, category: row.category, shift_name: row.shift_name, start_date: row.start_date ?? null, notes: row.notes ?? null, is_active: row.is_active !== false, created_at: resolveCreatedAt(row, fallbackAt) };
    case 'attendance_records':
      return { id: row.id, shift_id: row.shift_id, employee_id: row.employee_id, attendance_date: row.attendance_date, shift_name: row.shift_name, status: row.status, check_in: row.check_in ?? null, check_out: row.check_out ?? null, notes: row.notes ?? null, updated_by: row.updated_by ?? null, updated_at: row.updated_at ?? null, created_at: resolveCreatedAt(row, fallbackAt) };
    case 'production':
      return { id: row.id, shift_id: row.shift_id, department: row.department || 'PACKING', line_code: row.line_code, machine_name: row.machine_name ?? null, product_name: row.product_name, workers_count: row.workers_count ?? 0, hour_started_at: row.hour_started_at, target_qty: row.target_qty, actual_qty: row.actual_qty, waste_qty: row.waste_qty ?? 0, rejected_qty: row.rejected_qty ?? 0, downtime_minutes: row.downtime_minutes ?? 0, downtime_reason: row.downtime_reason ?? null, notes: row.notes ?? null, created_at: resolveCreatedAt(row, fallbackAt) };
    case 'product_guides':
      return { id: row.id, product_code: row.product_code, name: row.name, department: row.department, raw_material: row.raw_material ?? null, pack_weight: numberOrNull(row.pack_weight), pack_size: row.pack_size ?? null, size: row.size ?? null, temperature: row.temperature ?? null, line_speed: row.line_speed ?? null, machine_settings: row.machine_settings ?? null, operating_time: row.operating_time ?? null, instructions: row.instructions ?? null, steps_json: row.steps ?? row.steps_json ?? [], image_url: row.image_url ?? null, is_active: row.is_active !== false, created_at: resolveCreatedAt(row, fallbackAt) };
    case 'fridges':
      return { id: row.id, fridge_no: row.fridge_no, name: row.name, min_temp: numberOrNull(row.min_temp), max_temp: numberOrNull(row.max_temp), is_active: row.is_active !== false, created_at: resolveCreatedAt(row, fallbackAt) };
    case 'fridge_readings':
      return { id: row.id, shift_id: row.shift_id, fridge_id: row.fridge_id, reading_date: row.reading_date, reading_hour: row.reading_hour, temperature: Number(row.temperature), status: Number(row.temperature) > -10 ? 'DEFROST' : 'NORMAL', engineer_id: row.engineer_id ?? null, notes: row.notes ?? null, created_at: resolveCreatedAt(row, fallbackAt) };
    case 'quality':
      return { id: row.id, shift_id: row.shift_id, product_name: row.product_name, line_code: row.line_code, inspected_qty: row.inspected_qty, accepted_qty: row.accepted_qty, rejected_qty: row.rejected_qty, rejection_reason: row.rejection_reason ?? null, result: row.result || 'PENDING', inspected_at: resolveTimestamp(row, fallbackAt, ['inspected_at', 'created_at', 'createdAt', 'timestamp']), notes: row.notes ?? null, created_by: row.created_by ?? null, created_at: resolveCreatedAt(row, fallbackAt) };
    case 'raw_receipts':
      return { id: row.id, receipt_date: row.receipt_date, receipt_time: row.receipt_time, material_name: row.material_name, supplier: row.supplier, supplier_code: row.supplier_code ?? null, gross_weight: Number(row.gross_weight), discount_rate: Number(row.discount_rate ?? 0), discount_amount: Number(row.discount_amount), net_weight: Number(row.net_weight), defects: row.defects ?? null, notes: row.notes ?? null, created_by: row.created_by ?? null, created_at: resolveCreatedAt(row, fallbackAt) };
    case 'packaging_receipts':
      return { id: row.id, receipt_date: row.receipt_date, receipt_time: row.receipt_time, supplier: row.supplier, item_name: row.item_name, item_code: row.item_code ?? null, quantity: Number(row.quantity), unit: row.unit, receipt_no: row.receipt_no ?? null, notes: row.notes ?? null, created_by: row.created_by ?? null, created_at: resolveCreatedAt(row, fallbackAt) };
    case 'supplies':
      return { id: row.id, shift_id: row.shift_id, supplier: row.supplier, material_name: row.material_name, quantity: Number(row.quantity), unit: row.unit, batch_no: row.batch_no ?? null, status: row.status || 'PENDING', received_at: resolveTimestamp(row, fallbackAt, ['received_at', 'created_at', 'createdAt', 'timestamp']), approved_at: row.approved_at ?? null, notes: row.notes ?? null };
    case 'downtime':
      return { id: row.id, shift_id: row.shift_id, line_code: row.line_code, machine_name: row.machine_name, started_at: resolveTimestamp(row, fallbackAt, ['started_at', 'created_at', 'createdAt', 'timestamp']), ended_at: row.ended_at ?? null, minutes: Number(row.minutes), reason_type: row.reason_type, status: row.status || 'OPEN', action_taken: row.action_taken ?? null, created_at: resolveCreatedAt(row, fallbackAt) };
    case 'maintenance':
      return { id: row.id, shift_id: row.shift_id, ticket_no: row.ticket_no, line_code: row.line_code, machine_name: row.machine_name, severity: row.severity, description: row.description, status: row.status || 'OPEN', reported_at: resolveTimestamp(row, fallbackAt, ['reported_at', 'created_at', 'createdAt', 'timestamp']), repaired_at: row.repaired_at ?? null, action_taken: row.action_taken ?? null };
    case 'inventory':
      return { id: row.id, shift_id: row.shift_id, material_name: row.material_name, transaction_type: row.transaction_type, quantity: Number(row.quantity), unit: row.unit, reference_no: row.reference_no ?? null, created_at: resolveCreatedAt(row, fallbackAt), notes: row.notes ?? null, created_by: row.created_by ?? null };
    case 'notifications':
      return { id: row.id, shift_id: row.shift_id ?? null, severity: row.severity, title: row.title, body: row.body, is_read: row.is_read === true, created_at: resolveCreatedAt(row, fallbackAt) };
    case 'problems':
      return { id: row.id, shift_id: row.shift_id, title: row.title, department: row.department, line_code: row.line_code ?? null, machine_name: row.machine_name ?? null, problem_date: row.problem_date, problem_time: row.problem_time, severity: row.severity, owner: row.owner ?? null, action_taken: row.action_taken ?? null, status: row.status || 'OPEN', resolved_at: row.resolved_at ?? null, notes: row.notes ?? null, created_by: row.created_by ?? null, updated_by: row.updated_by ?? null, created_at: resolveCreatedAt(row, fallbackAt), source_notification_id: row.source_notification_id ?? null };
    case 'container_loadings':
      return { id: row.id, shift_id: row.shift_id, container_no: row.container_no, product_name: row.product_name, container_temperature_before: Number(row.container_temperature_before ?? row.container_temp_before), product_temperature: Number(row.product_temperature ?? row.product_temp), container_temperature_after: Number(row.container_temperature_after ?? row.container_temp_after), cartons_quantity: Number(row.cartons_quantity ?? row.cartons), quantity: Number(row.quantity), loaded_at: resolveTimestamp(row, fallbackAt, ['loaded_at', 'created_at', 'createdAt', 'timestamp']), notes: row.notes ?? null, created_by: row.created_by ?? null, created_at: resolveCreatedAt(row, fallbackAt) };
    case 'audit':
      return { id: row.id, user_id: row.user_id ?? null, entity_type: row.entity_type, entity_id: row.entity_id ?? null, action: row.action, old_data_json: row.old_data_json ?? null, new_data_json: row.new_data_json ?? null, reason: row.reason ?? null, created_at: resolveCreatedAt(row, fallbackAt) };
    default:
      throw new Error(`Unsupported collection: ${collection}`);
  }
}

function normalizeForCompare(value) {
  if (value === null || value === undefined) return null;
  if (value instanceof Date) return value.toISOString();
  if (typeof value === 'object') {
    if (Array.isArray(value)) return value.map(normalizeForCompare);
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, normalizeForCompare(value[key])]));
  }
  if (typeof value === 'number' && Number.isNaN(value)) return null;
  return String(value);
}

function comparableRow(collection, row) {
  const mapped = mapRow(collection, row);
  const withoutGenerated = { ...mapped };
  for (const key of ['created_at', 'updated_at', 'loaded_at', 'inspected_at', 'received_at', 'approved_at', 'reported_at', 'repaired_at', 'resolved_at', 'opened_at', 'closed_at', 'started_at', 'ended_at']) {
    delete withoutGenerated[key];
  }
  for (const key of Object.keys(withoutGenerated)) {
    withoutGenerated[key] = normalizeComparableValue(key, withoutGenerated[key]);
  }
  return normalizeForCompare(withoutGenerated);
}

module.exports = {
  collectionToTable,
  migrationOrder,
  mapRow,
  validTimestamp,
  readSource,
  validateSource,
  comparableRow,
};
