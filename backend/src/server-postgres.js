require('dotenv').config({ path: require('node:path').resolve(__dirname, '..', '.env') });

const fs = require('node:fs');
const path = require('node:path');
const express = require('express');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { Pool } = require('pg');

const app = express();
app.disable('etag'); // API responses must never be served as a cached 304 with an empty body
app.use((req, res, next) => { if (req.path.startsWith('/api')) res.set('Cache-Control', 'no-store'); next(); });
const port = Number(process.env.PORT || 5521);
const jwtSecret = process.env.JWT_SECRET || 'local-development-only';
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.PGSSL === 'true' ? { rejectUnauthorized: false } : undefined,
  connectionTimeoutMillis: 10000,
});
pool.on('error', (error) => console.error('Postgres pool error (idle client):', error.message));
app.use(cors());
app.use(express.json({ limit: '1mb' }));
app.use((req, res, next) => {
  const startedAt = Date.now();
  res.on('finish', () => {
    console.log('[req]', req.method, req.originalUrl, '->', res.statusCode, (Date.now() - startedAt) + 'ms');
  });
  next();
});

const publicUser = (user) => ({ id: user.id, name: user.name, email: user.email, role: user.role_code, department: user.department, isActive: user.is_active });
const calculated = (row) => ({ ...row, difference: row.actual_qty - row.target_qty, achievement: row.target_qty ? row.actual_qty / row.target_qty * 100 : 0 });
const publicEmployee = (employee) => ({ id: employee.id, employeeNo: employee.employee_no, name: employee.name, department: employee.department, jobTitle: employee.job_title, category: employee.category, shiftName: employee.shift_name, startDate: employee.start_date || null, notes: employee.notes || null, isActive: employee.is_active });
const attendanceStatuses = new Set(['PRESENT', 'LATE', 'MISSION', 'LEAVE', 'ABSENT_EXCUSED', 'ABSENT_UNEXCUSED']);
const publicAttendance = (record) => {
  const employee = record.employee || record;
  return { id: record.id, shiftId: record.shift_id, employeeId: record.employee_id, employee: publicEmployee(employee), attendanceDate: record.attendance_date, shiftName: record.shift_name, status: record.status, checkIn: record.check_in, checkOut: record.check_out, notes: record.notes, updatedBy: record.updated_by, updatedAt: record.updated_at || null };
};
const publicProductGuide = (product) => ({ id: product.id, productCode: product.product_code, name: product.name, department: product.department, rawMaterial: product.raw_material, packWeight: product.pack_weight, packSize: product.pack_size, size: product.size, temperature: product.temperature, lineSpeed: product.line_speed, machineSettings: product.machine_settings, operatingTime: product.operating_time, instructions: product.instructions, steps: product.steps_json || [], imageUrl: product.image_url, isActive: product.is_active });
const publicFridge = (fridge) => ({ id: fridge.id, fridgeNo: fridge.fridge_no, name: fridge.name, minTemp: fridge.min_temp, maxTemp: fridge.max_temp, isActive: fridge.is_active });
const publicReceipt = (receipt) => ({ id: receipt.id, receiptDate: receipt.receipt_date, receiptTime: receipt.receipt_time, materialName: receipt.material_name, supplier: receipt.supplier, supplierCode: receipt.supplier_code, grossWeight: Number(receipt.gross_weight), discountRate: Number(receipt.discount_rate), discountAmount: Number(receipt.discount_amount), netWeight: Number(receipt.net_weight), defects: receipt.defects, notes: receipt.notes, createdBy: receipt.created_by });
const publicPackagingReceipt = (receipt) => ({ id: receipt.id, receiptDate: receipt.receipt_date, receiptTime: receipt.receipt_time, supplier: receipt.supplier, itemName: receipt.item_name, itemCode: receipt.item_code, quantity: Number(receipt.quantity), unit: receipt.unit, receiptNo: receipt.receipt_no, notes: receipt.notes, createdBy: receipt.created_by });
const publicContainerLoading = (row) => ({ id: row.id, shiftId: row.shift_id, containerNo: row.container_no, productName: row.product_name, containerTempBefore: Number(row.container_temperature_before), productTemp: Number(row.product_temperature), containerTempAfter: Number(row.container_temperature_after), cartons: Number(row.cartons_quantity), quantity: Number(row.quantity), loadedAt: row.loaded_at, notes: row.notes, createdBy: row.created_by, createdAt: row.created_at });
function attendanceSummary(rows) {
  const present = rows.filter((row) => ['PRESENT', 'LATE'].includes(row.status)).length;
  const absent = rows.filter((row) => ['ABSENT_EXCUSED', 'ABSENT_UNEXCUSED'].includes(row.status)).length;
  return { total: rows.length, present, absent, late: rows.filter((row) => row.status === 'LATE').length, attendanceRate: rows.length ? present / rows.length * 100 : 0, absenceRate: rows.length ? absent / rows.length * 100 : 0 };
}
function auth(req, res, next) {
  const value = req.headers.authorization || '';
  const token = value.startsWith('Bearer ') ? value.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'AUTH_REQUIRED' });
  try { req.user = jwt.verify(token, jwtSecret); return next(); } catch { return res.status(401).json({ error: 'INVALID_TOKEN' }); }
}
function roles(...allowed) { return (req, res, next) => allowed.includes(req.user.role) ? next() : res.status(403).json({ error: 'FORBIDDEN' }); }
const attendanceRoles = ['SYSTEM_ADMIN', 'SHIFT_MANAGER', 'SECURITY'];
const productionRoles = ['SYSTEM_ADMIN', 'SHIFT_MANAGER', 'PRODUCTION', 'PRODUCTION_ENGINEER'];
const qualityRoles = ['SYSTEM_ADMIN', 'SHIFT_MANAGER', 'QUALITY', 'QUALITY_ENGINEER'];
const containerReadRoles = ['SYSTEM_ADMIN', 'SHIFT_MANAGER', 'QUALITY', 'QUALITY_ENGINEER'];
const containerWriteRoles = ['SYSTEM_ADMIN', 'QUALITY', 'QUALITY_ENGINEER'];
const guideReadRoles = ['SYSTEM_ADMIN', 'SHIFT_MANAGER', 'PRODUCTION', 'PRODUCTION_ENGINEER', 'QUALITY', 'QUALITY_ENGINEER'];
const receiptReadRoles = ['SYSTEM_ADMIN', 'SHIFT_MANAGER', 'WAREHOUSE', 'PRODUCTION_ENGINEER'];
const reportRoles = ['SYSTEM_ADMIN', 'SHIFT_MANAGER', 'PRODUCTION_ENGINEER', 'QUALITY_ENGINEER'];
async function one(text, params = []) { const result = await pool.query(text, params); return result.rows[0]; }
async function many(text, params = []) { const result = await pool.query(text, params); return result.rows; }
async function audit(userId, entityType, entityId, action, data, oldData = null) { await pool.query('INSERT INTO audit_logs(user_id, entity_type, entity_id, action, old_data_json, new_data_json) VALUES ($1, $2, $3, $4, $5, $6)', [userId, entityType, entityId, action, oldData ? JSON.stringify(oldData) : null, JSON.stringify(data)]); }
async function buildReport(shiftId) {
  const shift = await one('SELECT s.*, u.name AS manager_name FROM shifts s LEFT JOIN users u ON u.id = s.manager_id WHERE s.id = $1', [shiftId]);
  if (!shift) return null;
  const [attendance, productionRows, quality, downtimeRows, maintenanceRows, fridgeRows, attendanceRecords, supplies, inventoryRows, notifications, problems, containerRows, rawReceipts, packagingReceipts] = await Promise.all([
    one('SELECT COALESCE(SUM(required_count),0)::int AS required, COALESCE(SUM(present_count),0)::int AS present, COALESCE(SUM(absent_count),0)::int AS absent, COALESCE(SUM(late_count),0)::int AS late FROM attendance WHERE shift_id = $1', [shiftId]),
    many('SELECT * FROM production_hourly WHERE shift_id = $1 ORDER BY hour_started_at, id', [shiftId]),
    one('SELECT COALESCE(SUM(inspected_qty),0)::int AS inspected, COALESCE(SUM(accepted_qty),0)::int AS accepted, COALESCE(SUM(rejected_qty),0)::int AS rejected FROM quality_checks WHERE shift_id = $1', [shiftId]),
    many('SELECT * FROM downtime WHERE shift_id = $1 ORDER BY id', [shiftId]),
    many('SELECT * FROM maintenance_tickets WHERE shift_id = $1 ORDER BY id', [shiftId]),
    many('SELECT * FROM fridge_readings WHERE shift_id = $1 ORDER BY reading_date, reading_hour, id', [shiftId]),
    many(`SELECT ar.*, e.employee_no, e.name, e.department, e.job_title, e.category, e.shift_name AS employee_shift_name, e.is_active
      FROM attendance_records ar JOIN employees e ON e.id = ar.employee_id
      WHERE ar.shift_id = $1 ORDER BY e.name`, [shiftId]),
    many('SELECT * FROM supplies WHERE shift_id = $1 ORDER BY id', [shiftId]),
    many('SELECT * FROM inventory_transactions WHERE shift_id = $1 ORDER BY id', [shiftId]),
    many('SELECT * FROM notifications WHERE shift_id = $1 AND is_read = FALSE ORDER BY id DESC', [shiftId]),
    many('SELECT * FROM problems WHERE shift_id = $1 ORDER BY id DESC', [shiftId]),
    many('SELECT * FROM container_loadings WHERE shift_id = $1 ORDER BY loaded_at, id', [shiftId]),
    many('SELECT * FROM raw_receipts WHERE receipt_date = $1 ORDER BY id', [shift.shift_date]),
    many('SELECT * FROM packaging_receipts WHERE receipt_date = $1 ORDER BY id', [shift.shift_date]),
  ]);
  const production = productionRows.reduce((result, row) => ({
    target: result.target + Number(row.target_qty),
    actual: result.actual + Number(row.actual_qty),
    waste: result.waste + Number(row.waste_qty || 0),
    rejected: result.rejected + Number(row.rejected_qty || 0),
    downtime: result.downtime + Number(row.downtime_minutes || 0),
  }), { target: 0, actual: 0, waste: 0, rejected: 0, downtime: 0 });
  const downtime = {
    count: downtimeRows.length,
    minutes: downtimeRows.reduce((sum, row) => sum + Number(row.minutes || 0), 0),
    open_count: downtimeRows.filter((row) => row.status !== 'CLOSED').length,
  };
  const maintenance = {
    count: maintenanceRows.length,
    open_count: maintenanceRows.filter((row) => !['CLOSED', 'RESOLVED'].includes(row.status)).length,
  };
  const inventory = inventoryRows.reduce((result, row) => {
    const quantity = Number(row.quantity || 0);
    if (row.transaction_type === 'RECEIPT') result.received += quantity;
    if (row.transaction_type === 'ISSUE') result.issued += quantity;
    if (row.transaction_type === 'RETURN') result.returned += quantity;
    return result;
  }, { received: 0, issued: 0, returned: 0 });
  const fridge = {
    required: 40,
    completed: fridgeRows.length,
    missing: Math.max(0, 40 - fridgeRows.length),
    normal: fridgeRows.filter((row) => Number(row.temperature) <= -10).length,
    defrost: fridgeRows.filter((row) => Number(row.temperature) > -10).length,
    rows: fridgeRows.map((row) => ({ ...row, status: Number(row.temperature) > -10 ? 'DEFROST' : 'NORMAL' })),
  };
  const productionByDepartment = {};
  const productionByProduct = {};
  for (const row of productionRows) {
    const department = row.department || 'PACKING';
    productionByDepartment[department] = (productionByDepartment[department] || 0) + Number(row.actual_qty || 0);
    productionByProduct[row.product_name] = (productionByProduct[row.product_name] || 0) + Number(row.actual_qty || 0);
  }
  const attendanceRate = attendance.required ? Number(attendance.present) / Number(attendance.required) * 100 : 0;
  const absenceRate = attendance.required ? Number(attendance.absent) / Number(attendance.required) * 100 : 0;
  const achievement = production.target ? production.actual / production.target * 100 : 0;
  const openingBalanceRow = await one("SELECT value FROM app_settings WHERE key = 'inventory_opening_balance'");
  const openingBalance = Number(openingBalanceRow?.value ?? 0);
  const rejectionRate = Number(quality.inspected) ? Number(quality.rejected) / Number(quality.inspected) * 100 : 0;
  const start = shift.opened_at || `${shift.shift_date}T${shift.starts_at}:00`;
  const end = shift.closed_at || `${shift.shift_date}T${shift.ends_at}:00`;
  const durationMinutes = Date.parse(end) >= Date.parse(start) ? Math.round((Date.parse(end) - Date.parse(start)) / 60000) : null;
  return {
    shift: { ...shift, duration_minutes: durationMinutes },
    generated_at: new Date().toISOString(),
    attendance_rate: attendanceRate,
    absence_rate: absenceRate,
    achievement,
    rejection_rate: rejectionRate,
    supply_total: supplies.reduce((sum, row) => sum + Number(row.quantity || 0), 0),
    inventory_balance: openingBalance + inventory.received - inventory.issued + inventory.returned,
    attendance_records: attendanceRecords.map((row) => ({
      ...row,
      employee: publicEmployee({
        id: row.employee_id,
        employee_no: row.employee_no,
        name: row.name,
        department: row.department,
        job_title: row.job_title,
        category: row.category,
        shift_name: row.employee_shift_name,
        is_active: row.is_active,
      }),
    })),
    production_by_department: productionByDepartment,
    production_by_product: productionByProduct,
    downtime_rows: downtimeRows,
    maintenance_rows: maintenanceRows,
    fridge,
    alerts: notifications,
    raw_receipts: rawReceipts.map(publicReceipt),
    packaging_receipts: packagingReceipts.map(publicPackagingReceipt),
    container_loadings: containerRows.map(publicContainerLoading),
    problems,
    supplies,
    inventory,
    production: { ...production, target: Number(production.target), actual: Number(production.actual), waste: Number(production.waste), rejected: Number(production.rejected), downtime: Number(production.downtime) },
    attendance: { required: Number(attendance.required), present: Number(attendance.present), absent: Number(attendance.absent), late: Number(attendance.late) },
    quality: { inspected: Number(quality.inspected), accepted: Number(quality.accepted), rejected: Number(quality.rejected) },
    downtime,
    maintenance,
    notifications: notifications,
    containers: { count: containerRows.length },
    production_rows: productionRows.map(calculated),
  };
}
async function editableShift(req, res, shiftId) {
  const shift = await one('SELECT * FROM shifts WHERE id = $1', [shiftId]);
  if (!shift) { res.status(404).json({ error: 'SHIFT_NOT_FOUND' }); return null; }
  if (['COMPLETED', 'APPROVED', 'CLOSED'].includes(shift.status)) {
    const reason = String(req.body?.exceptionReason || '').trim();
    if (req.user.role !== 'SHIFT_MANAGER' || !reason) {
      res.status(409).json({ error: 'SHIFT_CLOSED', message: 'الوردية مغلقة وتحتاج تعديلًا استثنائيًا بسبب موثق' });
      return null;
    }
    req.exceptionReason = reason;
  }
  return shift;
}
app.use((req, res, next) => {
  if (!['POST', 'PATCH', 'PUT', 'DELETE'].includes(req.method)) return next();
  const match = req.path.match(/^\/api\/shifts\/(\d+)\/(production|attendance|quality\/fridge-readings|downtime|maintenance|inventory|supplies|problems|container-loadings)(?:\/|$)/);
  if (!match) return next();
  auth(req, res, async () => {
    try {
      if (!await editableShift(req, res, Number(match[1]))) return;
      next();
    } catch (error) { next(error); }
  });
});

app.get('/api/health', async (_req, res) => {
  try { await pool.query('SELECT 1'); res.json({ ok: true, service: 'wardia-shift-api', storage: 'postgresql', time: new Date().toISOString() }); }
  catch { res.status(503).json({ ok: false, storage: 'postgresql' }); }
});
app.post('/api/auth/login', async (req, res, next) => {
  try {
    const email = String(req.body?.email || '').trim();
    const password = String(req.body?.password || '');
    const user = await one('SELECT * FROM users WHERE email = $1 AND is_active = TRUE', [email]);
    if (!user || !bcrypt.compareSync(password, user.password_hash)) return res.status(401).json({ error: 'INVALID_CREDENTIALS' });
    const token = jwt.sign({ sub: user.id, role: user.role_code, email: user.email }, jwtSecret, { expiresIn: '8h' });
    await audit(user.id, 'AUTH', user.id, 'LOGIN', { email: user.email });
    return res.json({ token, user: publicUser(user) });
  } catch (error) { return next(error); }
});
app.get('/api/me', auth, async (req, res, next) => { try { const user = await one('SELECT * FROM users WHERE id = $1', [req.user.sub]); res.json({ user: publicUser(user) }); } catch (error) { next(error); } });
app.get('/api/shifts/current', auth, async (_req, res, next) => { try { res.json({ shift: await one("SELECT s.*, u.name AS manager_name FROM shifts s LEFT JOIN users u ON u.id = s.manager_id ORDER BY CASE WHEN s.status = 'RUNNING' THEN 0 ELSE 1 END, s.id DESC LIMIT 1") }); } catch (error) { next(error); } });
app.get('/api/shifts/history', auth, roles('SYSTEM_ADMIN', 'SHIFT_MANAGER', 'PRODUCTION_ENGINEER', 'QUALITY_ENGINEER'), async (req, res, next) => {
  try {
    const rows = await many(`SELECT s.*
      FROM shifts s
      WHERE ($1::date IS NULL OR s.shift_date >= $1::date)
        AND ($2::date IS NULL OR s.shift_date <= $2::date)
        AND ($3::text IS NULL OR s.shift_no ILIKE $3)
      ORDER BY s.shift_date DESC, s.id DESC`, [
      req.query.from || null,
      req.query.to || null,
      req.query.number ? `%${req.query.number}%` : null,
    ]);
    const reports = [];
    for (const shift of rows) {
      const report = await buildReport(shift.id);
      if (!req.query.department || Object.prototype.hasOwnProperty.call(report.production_by_department, req.query.department)) {
        reports.push(report);
      }
    }
    res.json({ rows: reports });
  } catch (error) { next(error); }
});

app.get('/api/shifts/:id/dashboard', auth, async (req, res, next) => {
  try {
    const id = req.params.id;
    const shift = await one('SELECT * FROM shifts WHERE id = $1', [id]);
    if (!shift) return res.status(404).json({ error: 'SHIFT_NOT_FOUND' });
    const attendance = await one('SELECT COALESCE(SUM(required_count),0)::int required, COALESCE(SUM(present_count),0)::int present, COALESCE(SUM(absent_count),0)::int absent, COALESCE(SUM(late_count),0)::int late FROM attendance WHERE shift_id = $1', [id]);
    const production = await one('SELECT COALESCE(SUM(target_qty),0)::int target, COALESCE(SUM(actual_qty),0)::int actual, COALESCE(SUM(waste_qty),0)::int waste, COALESCE(SUM(rejected_qty),0)::int rejected, COALESCE(SUM(downtime_minutes),0)::int downtime FROM production_hourly WHERE shift_id = $1', [id]);
    const quality = await one('SELECT COALESCE(SUM(inspected_qty),0)::int inspected, COALESCE(SUM(accepted_qty),0)::int accepted, COALESCE(SUM(rejected_qty),0)::int rejected FROM quality_checks WHERE shift_id = $1', [id]);
    const downtime = await one("SELECT COUNT(*)::int count, COALESCE(SUM(minutes),0)::int minutes, COUNT(*) FILTER (WHERE status != 'CLOSED')::int open_count FROM downtime WHERE shift_id = $1", [id]);
    const maintenance = await one("SELECT COUNT(*)::int count, COUNT(*) FILTER (WHERE status NOT IN ('CLOSED','RESOLVED'))::int open_count FROM maintenance_tickets WHERE shift_id = $1", [id]);
    const inventory = await one("SELECT COALESCE(SUM(quantity) FILTER (WHERE transaction_type = 'RECEIPT'),0)::numeric received, COALESCE(SUM(quantity) FILTER (WHERE transaction_type = 'ISSUE'),0)::numeric issued, COALESCE(SUM(quantity) FILTER (WHERE transaction_type = 'RETURN'),0)::numeric returned FROM inventory_transactions WHERE shift_id = $1", [id]);
    const fridges = await one("SELECT COUNT(*)::int AS required, COUNT(DISTINCT CONCAT(fridge_id, ':', reading_date, ':', reading_hour))::int AS completed, COUNT(*) FILTER (WHERE temperature > -10)::int AS defrost FROM fridge_readings WHERE shift_id = $1", [id]);
    const containers = await one('SELECT COUNT(*)::int AS count FROM container_loadings WHERE shift_id = $1', [id]);
    const notifications = await many('SELECT * FROM notifications WHERE shift_id = $1 AND is_read = FALSE ORDER BY id DESC', [id]);
    if (req.user.role === 'SECURITY') return res.json({ shift, attendance, notifications: notifications.filter((item) => String(item.title).includes('حضور') || String(item.title).includes('غياب')) });
    if (['QUALITY', 'QUALITY_ENGINEER'].includes(req.user.role)) return res.json({ shift, quality, fridges: { required: 40, completed: Number(fridges.completed), missing: Math.max(0, 40 - Number(fridges.completed)), defrost: Number(fridges.defrost) }, containers, notifications: notifications.filter((item) => String(item.title).includes('جودة') || String(item.title).includes('Defrost') || String(item.title).includes('ثلاجة')) });
    if (['PRODUCTION', 'PRODUCTION_ENGINEER'].includes(req.user.role)) return res.json({ shift, production, downtime, maintenance, notifications });
    res.json({ shift, attendance, production, quality, downtime, maintenance, inventory, notifications });
  } catch (error) { next(error); }
});
app.get('/api/shifts/:id/production/hourly', auth, roles(...productionRoles), async (req, res, next) => { try { const rows = await many('SELECT * FROM production_hourly WHERE shift_id = $1 AND ($2::text IS NULL OR department = $2) ORDER BY hour_started_at', [req.params.id, req.query.department || null]); const totals = rows.reduce((result, row) => ({ target: result.target + row.target_qty, actual: result.actual + row.actual_qty, downtime: result.downtime + row.downtime_minutes, hours: result.hours + 1, products: result.products.add(row.product_name) }), { target: 0, actual: 0, downtime: 0, hours: 0, products: new Set() }); res.json({ rows: rows.map(calculated), summary: { target: totals.target, actual: totals.actual, achievement: totals.target ? totals.actual / totals.target * 100 : 0, downtime: totals.downtime, hours: totals.hours, products: totals.products.size } }); } catch (error) { next(error); } });
app.post('/api/shifts/:id/production/hourly', auth, roles(...productionRoles), async (req, res, next) => {
  try {
    const b = req.body || {};
    if (!b.lineCode || !b.productName || !b.hourStartedAt || !Number.isInteger(b.targetQty) || b.targetQty <= 0 || !Number.isInteger(b.actualQty) || b.actualQty < 0) return res.status(400).json({ error: 'INVALID_PRODUCTION_DATA' });
    const row = await one(`INSERT INTO production_hourly(shift_id,department,line_code,machine_name,product_name,workers_count,hour_started_at,target_qty,actual_qty,waste_qty,rejected_qty,downtime_minutes,downtime_reason,notes) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14) RETURNING *`, [req.params.id, ['PACKING', 'IQF'].includes(String(b.department)) ? b.department : 'PACKING', b.lineCode, b.machineName || null, b.productName, b.workersCount || 0, b.hourStartedAt, b.targetQty, b.actualQty, b.wasteQty || 0, b.rejectedQty || 0, b.downtimeMinutes || 0, b.downtimeReason || null, b.notes || null]);
    await audit(req.user.sub, 'PRODUCTION_HOURLY', row.id, 'CREATE', b);
    if (b.actualQty / b.targetQty < 0.9) await pool.query("INSERT INTO notifications(shift_id,severity,title,body) VALUES($1,'WARNING',$2,$3)", [req.params.id, 'الإنتاج أقل من المستهدف', `ساعة ${b.hourStartedAt} أقل من 90%`]);
    res.status(201).json({ row: calculated(row) });
  } catch (error) { next(error); }
});
app.get('/api/shifts/:id/attendance', auth, roles(...attendanceRoles), async (req, res, next) => { try { res.json({ rows: await many('SELECT * FROM attendance WHERE shift_id = $1 ORDER BY id DESC', [req.params.id]) }); } catch (error) { next(error); } });
app.post('/api/shifts/:id/attendance', auth, roles('SHIFT_MANAGER', 'SECURITY', 'SYSTEM_ADMIN'), async (req, res, next) => { try { const b = req.body || {}; const row = await one('INSERT INTO attendance(shift_id,department,required_count,present_count,absent_count,late_count,overtime_count,notes) VALUES($1,$2,$3,$4,$5,$6,$7,$8) RETURNING *', [req.params.id, b.department, b.requiredCount, b.presentCount, b.absentCount, b.lateCount || 0, b.overtimeCount || 0, b.notes || null]); await audit(req.user.sub, 'ATTENDANCE', row.id, 'CREATE', b); res.status(201).json({ row, attendanceRate: row.required_count ? row.present_count / row.required_count * 100 : 0, absenceRate: row.required_count ? row.absent_count / row.required_count * 100 : 0 }); } catch (error) { next(error); } });
app.get('/api/employees', auth, async (req, res, next) => { try { const includeInactive = String(req.query.includeInactive || '') === 'true' && ['SYSTEM_ADMIN', 'SHIFT_MANAGER', 'SECURITY'].includes(req.user.role); res.json({ rows: await many(`SELECT * FROM employees WHERE ($1::boolean OR is_active = TRUE) ORDER BY name`, [includeInactive]).then((rows) => rows.map(publicEmployee)) }); } catch (error) { next(error); } });
app.post('/api/employees', auth, roles('SYSTEM_ADMIN', 'SHIFT_MANAGER', 'SECURITY'), async (req, res, next) => {
  try {
    const b = req.body || {};
    if (!b.employeeNo || !b.name || !b.department || !b.jobTitle || !b.category || !b.shiftName) return res.status(400).json({ error: 'INVALID_EMPLOYEE_DATA' });
    const employee = await one('INSERT INTO employees(employee_no,name,department,job_title,category,shift_name,start_date,notes,is_active) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING *', [String(b.employeeNo).trim(), String(b.name).trim(), String(b.department).trim(), String(b.jobTitle).trim(), String(b.category).trim(), String(b.shiftName).trim(), b.startDate || null, b.notes || null, b.isActive === undefined ? true : Boolean(b.isActive)]);
    await audit(req.user.sub, 'EMPLOYEE', employee.id, 'CREATE', publicEmployee(employee));
    res.status(201).json({ employee: publicEmployee(employee) });
  } catch (error) { if (error.code === '23505') return res.status(409).json({ error: 'EMPLOYEE_NO_EXISTS' }); next(error); }
});
app.patch('/api/employees/:id', auth, roles('SYSTEM_ADMIN', 'SHIFT_MANAGER', 'SECURITY'), async (req, res, next) => {
  try {
    const b = req.body || {};
    const employee = await one('UPDATE employees SET name=COALESCE($1,name), department=COALESCE($2,department), job_title=COALESCE($3,job_title), category=COALESCE($4,category), shift_name=COALESCE($5,shift_name), start_date=COALESCE($6,start_date), notes=COALESCE($7,notes), is_active=COALESCE($8,is_active) WHERE id=$9 RETURNING *', [b.name || null, b.department || null, b.jobTitle || null, b.category || null, b.shiftName || null, b.startDate || null, b.notes || null, b.isActive === undefined ? null : Boolean(b.isActive), req.params.id]);
    if (!employee) return res.status(404).json({ error: 'EMPLOYEE_NOT_FOUND' });
    await audit(req.user.sub, 'EMPLOYEE', employee.id, 'UPDATE', publicEmployee(employee));
    res.json({ employee: publicEmployee(employee) });
  } catch (error) { next(error); }
});
app.get('/api/shifts/:id/attendance/records', auth, roles(...attendanceRoles), async (req, res, next) => {
  try {
    const rows = await many(`SELECT ar.*, e.employee_no, e.name, e.department, e.job_title, e.category, e.shift_name AS employee_shift_name, e.is_active
      FROM attendance_records ar JOIN employees e ON e.id = ar.employee_id
      WHERE ar.shift_id = $1 AND ($2::date IS NULL OR ar.attendance_date = $2::date) AND ($3::text IS NULL OR e.department = $3) AND ($4::text IS NULL OR e.job_title = $4) AND ($5::text IS NULL OR ar.status = $5)
      ORDER BY e.name`, [req.params.id, req.query.date || null, req.query.department || null, req.query.jobTitle || null, req.query.status || null]);
    res.json({ rows: rows.map((row) => publicAttendance({ ...row, employee: { id: row.employee_id, employee_no: row.employee_no, name: row.name, department: row.department, job_title: row.job_title, category: row.category, shift_name: row.employee_shift_name, is_active: row.is_active } })), summary: attendanceSummary(rows) });
  } catch (error) { next(error); }
});
app.post('/api/shifts/:id/attendance/records', auth, roles('SHIFT_MANAGER', 'SECURITY', 'SYSTEM_ADMIN'), async (req, res, next) => {
  try {
    const b = req.body || {};
    if (!b.employeeId || !b.attendanceDate || !attendanceStatuses.has(String(b.status))) return res.status(400).json({ error: 'INVALID_ATTENDANCE_RECORD' });
    const employee = await one('SELECT * FROM employees WHERE id = $1 AND is_active = TRUE', [b.employeeId]);
    if (!employee) return res.status(400).json({ error: 'EMPLOYEE_NOT_FOUND' });
    const row = await one('INSERT INTO attendance_records(shift_id,employee_id,attendance_date,shift_name,status,check_in,check_out,notes,updated_by) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING *', [req.params.id, b.employeeId, b.attendanceDate, b.shiftName || 'الثانية', b.status, b.checkIn || null, b.checkOut || null, b.notes || null, req.user.sub]);
    await audit(req.user.sub, 'ATTENDANCE_RECORD', row.id, 'CREATE', b);
    res.status(201).json({ row: publicAttendance({ ...row, employee }) });
  } catch (error) { if (error.code === '23505') return res.status(409).json({ error: 'ATTENDANCE_RECORD_EXISTS' }); next(error); }
});
app.patch('/api/shifts/:id/attendance/records/:recordId', auth, roles('SHIFT_MANAGER', 'SECURITY', 'SYSTEM_ADMIN'), async (req, res, next) => {
  try {
    const existing = await one('SELECT ar.*, e.* FROM attendance_records ar JOIN employees e ON e.id = ar.employee_id WHERE ar.id = $1 AND ar.shift_id = $2', [req.params.recordId, req.params.id]);
    if (!existing) return res.status(404).json({ error: 'ATTENDANCE_RECORD_NOT_FOUND' });
    const b = req.body || {};
    const status = b.status === undefined ? existing.status : String(b.status);
    if (!attendanceStatuses.has(status)) return res.status(400).json({ error: 'INVALID_ATTENDANCE_STATUS' });
    const oldData = publicAttendance({ ...existing, employee: existing });
    const row = await one('UPDATE attendance_records SET status=$1, check_in=$2, check_out=$3, notes=$4, updated_by=$5, updated_at=now() WHERE id=$6 RETURNING *', [status, b.checkIn === undefined ? existing.check_in : b.checkIn || null, b.checkOut === undefined ? existing.check_out : b.checkOut || null, b.notes === undefined ? existing.notes : b.notes || null, req.user.sub, req.params.recordId]);
    const newData = publicAttendance({ ...row, employee: existing });
    await audit(req.user.sub, 'ATTENDANCE_RECORD', row.id, 'UPDATE', newData, oldData);
    res.json({ row: newData });
  } catch (error) { next(error); }
});
app.get('/api/products/guides', auth, roles(...guideReadRoles), async (req, res, next) => { try { const query = `%${String(req.query.q || '')}%`; const rows = await many('SELECT * FROM product_guides WHERE is_active = TRUE AND (name ILIKE $1 OR product_code ILIKE $1) AND ($2::text IS NULL OR department = $2) ORDER BY name', [query, req.query.department || null]); res.json({ rows: rows.map(publicProductGuide) }); } catch (error) { next(error); } });
app.post('/api/products/guides', auth, roles('PRODUCTION', 'PRODUCTION_ENGINEER', 'SYSTEM_ADMIN'), async (req, res, next) => { try { const b = req.body || {}; if (!b.productCode || !b.name || !['PACKING', 'IQF'].includes(String(b.department))) return res.status(400).json({ error: 'INVALID_PRODUCT_GUIDE' }); const row = await one('INSERT INTO product_guides(product_code,name,department,raw_material,pack_weight,pack_size,size,temperature,line_speed,machine_settings,operating_time,instructions,steps_json,image_url) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14) RETURNING *', [b.productCode, b.name, b.department, b.rawMaterial || '', b.packWeight || null, b.packSize || '', b.size || '', b.temperature || null, b.lineSpeed || null, b.machineSettings || '', b.operatingTime || '', b.instructions || '', JSON.stringify(Array.isArray(b.steps) ? b.steps : []), b.imageUrl || null]); await audit(req.user.sub, 'PRODUCT_GUIDE', row.id, 'CREATE', publicProductGuide(row)); res.status(201).json({ product: publicProductGuide(row) }); } catch (error) { if (error.code === '23505') return res.status(409).json({ error: 'PRODUCT_CODE_EXISTS' }); next(error); } });
app.patch('/api/products/guides/:id', auth, roles('PRODUCTION', 'PRODUCTION_ENGINEER', 'SYSTEM_ADMIN'), async (req, res, next) => { try { const b = req.body || {}; if (!b.name || !['PACKING', 'IQF'].includes(String(b.department))) return res.status(400).json({ error: 'INVALID_PRODUCT_GUIDE' }); const old = await one('SELECT * FROM product_guides WHERE id = $1', [req.params.id]); if (!old) return res.status(404).json({ error: 'PRODUCT_GUIDE_NOT_FOUND' }); const row = await one('UPDATE product_guides SET name=$1, department=$2, raw_material=$3, pack_weight=$4, pack_size=$5, size=$6, temperature=$7, line_speed=$8, machine_settings=$9, operating_time=$10, instructions=$11, steps_json=$12, image_url=$13, updated_at=now() WHERE id=$14 RETURNING *', [b.name, b.department, b.rawMaterial || '', b.packWeight || null, b.packSize || '', b.size || '', b.temperature || null, b.lineSpeed || null, b.machineSettings || '', b.operatingTime || '', b.instructions || '', JSON.stringify(Array.isArray(b.steps) ? b.steps : []), b.imageUrl || null, req.params.id]); await audit(req.user.sub, 'PRODUCT_GUIDE', row.id, 'UPDATE', { old: publicProductGuide(old), new: publicProductGuide(row) }); res.json({ product: publicProductGuide(row) }); } catch (error) { next(error); } });
app.get('/api/quality/fridges', auth, roles(...qualityRoles), async (_req, res, next) => { try { res.json({ rows: (await many('SELECT * FROM fridges WHERE is_active = TRUE ORDER BY name')).map(publicFridge) }); } catch (error) { next(error); } });
app.post('/api/quality/fridges', auth, roles('QUALITY', 'QUALITY_ENGINEER', 'SYSTEM_ADMIN'), async (req, res, next) => {
  try {
    const b = req.body || {};
    if (!b.fridgeNo || !b.name) return res.status(400).json({ error: 'INVALID_FRIDGE' });
    const fridge = await one('INSERT INTO fridges(fridge_no,name,min_temp,max_temp,is_active) VALUES($1,$2,$3,$4,TRUE) RETURNING *', [b.fridgeNo, b.name, b.minTemp ?? null, b.maxTemp ?? null]);
    await audit(req.user.sub, 'FRIDGE', fridge.id, 'CREATE', publicFridge(fridge));
    res.status(201).json({ fridge: publicFridge(fridge) });
  } catch (error) {
    if (error.code === '23505') return res.status(409).json({ error: 'FRIDGE_NO_EXISTS' });
    next(error);
  }
});
app.get('/api/shifts/:id/container-loadings', auth, roles(...containerReadRoles), async (req, res, next) => {
  try {
    const rows = await many('SELECT * FROM container_loadings WHERE shift_id = $1 ORDER BY loaded_at DESC, id DESC', [req.params.id]);
    res.json({ rows: rows.map(publicContainerLoading), summary: { count: rows.length } });
  } catch (error) { next(error); }
});
app.post('/api/shifts/:id/container-loadings', auth, roles(...containerWriteRoles), async (req, res, next) => {
  try {
    const shift = await editableShift(req, res, req.params.id);
    if (!shift) return;
    const b = req.body || {};
    const numeric = ['containerTempBefore', 'productTemp', 'containerTempAfter', 'cartons', 'quantity'];
    if (!b.containerNo || !b.productName || numeric.some((key) => !Number.isFinite(Number(b[key])))) {
      return res.status(400).json({ error: 'INVALID_CONTAINER_LOADING' });
    }
    const row = await one(`INSERT INTO container_loadings
      (shift_id,container_no,product_name,container_temperature_before,product_temperature,container_temperature_after,cartons_quantity,quantity,loaded_at,notes,created_by)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) RETURNING *`, [
      shift.id,
      String(b.containerNo).trim(),
      String(b.productName).trim(),
      Number(b.containerTempBefore),
      Number(b.productTemp),
      Number(b.containerTempAfter),
      Number(b.cartons),
      Number(b.quantity),
      b.loadedAt || new Date().toISOString(),
      b.notes || null,
      req.user.sub,
    ]);
    await audit(req.user.sub, 'CONTAINER_LOADING', row.id, 'CREATE', publicContainerLoading(row));
    res.status(201).json({ row: publicContainerLoading(row) });
  } catch (error) { next(error); }
});
app.get('/api/shifts/:id/quality/fridge-readings', auth, roles(...qualityRoles), async (req, res, next) => { try { const rows = await many('SELECT r.*, f.name AS fridge_name FROM fridge_readings r JOIN fridges f ON f.id = r.fridge_id WHERE r.shift_id = $1 AND ($2::date IS NULL OR r.reading_date = $2::date) ORDER BY r.reading_date, r.reading_hour', [req.params.id, req.query.date || null]); const normalized = rows.map((row) => ({ ...row, status: Number(row.temperature) > -10 ? 'DEFROST' : 'NORMAL' })); const defrost = normalized.filter((row) => row.status === 'DEFROST').length; const required = 40; res.json({ rows: normalized.map((row) => ({ ...row, fridge: { name: row.fridge_name }, readingDate: row.reading_date, readingHour: row.reading_hour })), summary: { required, completed: rows.length, missing: Math.max(0, required - rows.length), compliance: Math.min(100, rows.length / required * 100), defrost } }); } catch (error) { next(error); } });
app.post('/api/shifts/:id/quality/fridge-readings', auth, roles('QUALITY', 'QUALITY_ENGINEER', 'SHIFT_MANAGER', 'SYSTEM_ADMIN'), async (req, res, next) => {
  try {
    const b = req.body || {};
    const temperature = Number(b.temperature);
    if (!b.fridgeId || !b.readingDate || !b.readingHour || !Number.isFinite(temperature)) {
      return res.status(400).json({ error: 'INVALID_FRIDGE_READING' });
    }
    const isDefrost = temperature > -10;
    const status = isDefrost ? 'DEFROST' : 'NORMAL';
    const row = await one('INSERT INTO fridge_readings(shift_id,fridge_id,reading_date,reading_hour,temperature,status,engineer_id,notes) VALUES($1,$2,$3,$4,$5,$6,$7,$8) RETURNING *', [req.params.id, b.fridgeId, b.readingDate, b.readingHour, temperature, status, req.user.sub, b.notes || null]);
    await audit(req.user.sub, 'FRIDGE_READING', row.id, 'CREATE', { ...b, calculatedStatus: status, defrostRequired: isDefrost });
    if (isDefrost && b.status !== 'DEFROST') {
      await pool.query("INSERT INTO notifications(shift_id,severity,title,body) VALUES($1,'WARNING',$2,$3)", [req.params.id, 'تسجيل حالة Defrost مطلوب', 'درجة الحرارة أكبر من -10°C']);
    }
    const repeated = await one('SELECT COUNT(*)::int AS count FROM fridge_readings WHERE shift_id = $1 AND fridge_id = $2 AND reading_date = $3 AND temperature > -10', [req.params.id, b.fridgeId, b.readingDate]);
    if (isDefrost && Number(repeated.count) >= 2) {
      const severity = Number(repeated.count) >= 3 ? 'CRITICAL' : 'WARNING';
      await pool.query('INSERT INTO notifications(shift_id,severity,title,body) VALUES($1,$2,$3,$4)', [req.params.id, severity, 'تكرار Defrost', `الثلاجة ${b.fridgeId} دخلت Defrost ${repeated.count} مرات اليوم`]);
      await audit(req.user.sub, 'FRIDGE', b.fridgeId, 'DEFROST_REPEAT', { date: b.readingDate, count: Number(repeated.count) });
    }
    res.status(201).json({ row: { ...row, status }, defrostRequired: isDefrost, repeatDefrost: Number(repeated.count) >= 2, defrostCount: Number(repeated.count) });
  } catch (error) { next(error); }
});
const receiptReport = async (req, res, next) => { try { const rows = await many('SELECT * FROM raw_receipts WHERE ($1::date IS NULL OR receipt_date >= $1::date) AND ($2::date IS NULL OR receipt_date <= $2::date) AND ($3::text IS NULL OR supplier = $3) AND ($4::text IS NULL OR material_name = $4) ORDER BY receipt_date DESC, id DESC', [req.query.from || null, req.query.to || null, req.query.supplier || null, req.query.material || null]); const totals = rows.reduce((result, row) => ({ count: result.count + 1, gross: result.gross + Number(row.gross_weight), discount: result.discount + Number(row.discount_amount), net: result.net + Number(row.net_weight), rates: result.rates + Number(row.discount_rate), suppliers: result.suppliers.add(row.supplier) }), { count: 0, gross: 0, discount: 0, net: 0, rates: 0, suppliers: new Set() }); res.json({ rows: rows.map(publicReceipt), summary: { count: totals.count, gross: totals.gross, discount: totals.discount, net: totals.net, averageDiscountRate: totals.count ? totals.rates / totals.count : 0, suppliers: totals.suppliers.size } }); } catch (error) { next(error); } };
app.get('/api/receipts', auth, roles(...receiptReadRoles), receiptReport);
app.get('/api/reports/receipts', auth, roles(...receiptReadRoles), receiptReport);
app.post('/api/receipts', auth, roles('WAREHOUSE', 'SHIFT_MANAGER', 'SYSTEM_ADMIN'), async (req, res, next) => { try { const b = req.body || {}; const gross = Number(b.grossWeight); const rate = Number(b.discountRate || 0); if (!b.materialName || !b.supplier || !Number.isFinite(gross) || gross <= 0 || rate < 0 || rate > 100) return res.status(400).json({ error: 'INVALID_RECEIPT' }); const discount = gross * rate / 100; const row = await one('INSERT INTO raw_receipts(receipt_date,receipt_time,material_name,supplier,supplier_code,gross_weight,discount_rate,discount_amount,net_weight,defects,notes,created_by) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) RETURNING *', [b.receiptDate || new Date().toISOString().slice(0, 10), b.receiptTime || new Date().toTimeString().slice(0, 5), b.materialName, b.supplier, b.supplierCode || null, gross, rate, discount, gross - discount, b.defects || '', b.notes || '', req.user.sub]); await audit(req.user.sub, 'RAW_RECEIPT', row.id, 'CREATE', publicReceipt(row)); res.status(201).json({ receipt: publicReceipt(row) }); } catch (error) { next(error); } });
app.get('/api/receipts/packaging', auth, roles(...receiptReadRoles), async (req, res, next) => { try { const rows = await many('SELECT * FROM packaging_receipts WHERE ($1::date IS NULL OR receipt_date >= $1::date) AND ($2::date IS NULL OR receipt_date <= $2::date) AND ($3::text IS NULL OR supplier = $3) AND ($4::text IS NULL OR item_name = $4) ORDER BY receipt_date DESC, id DESC', [req.query.from || null, req.query.to || null, req.query.supplier || null, req.query.item || null]); const suppliers = new Set(rows.map((row) => row.supplier)); res.json({ rows: rows.map(publicPackagingReceipt), summary: { count: rows.length, quantity: rows.reduce((sum, row) => sum + Number(row.quantity), 0), suppliers: suppliers.size } }); } catch (error) { next(error); } });
app.post('/api/receipts/packaging', auth, roles('WAREHOUSE', 'SHIFT_MANAGER', 'SYSTEM_ADMIN'), async (req, res, next) => { try { const b = req.body || {}; const quantity = Number(b.quantity); if (!b.supplier || !b.itemName || !b.unit || !Number.isFinite(quantity) || quantity <= 0) return res.status(400).json({ error: 'INVALID_PACKAGING_RECEIPT' }); const row = await one('INSERT INTO packaging_receipts(receipt_date,receipt_time,supplier,item_name,item_code,quantity,unit,receipt_no,notes,created_by) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING *', [b.receiptDate || new Date().toISOString().slice(0, 10), b.receiptTime || new Date().toTimeString().slice(0, 5), b.supplier, b.itemName, b.itemCode || null, quantity, b.unit, b.receiptNo || null, b.notes || '', req.user.sub]); await audit(req.user.sub, 'PACKAGING_RECEIPT', row.id, 'CREATE', publicPackagingReceipt(row)); res.status(201).json({ receipt: publicPackagingReceipt(row) }); } catch (error) { next(error); } });

app.get('/api/users', auth, roles('SYSTEM_ADMIN'), async (_req, res, next) => { try { res.json({ rows: (await many('SELECT id,name,email,role_code,department,is_active,created_at FROM users ORDER BY id DESC')).map(publicUser) }); } catch (error) { next(error); } });
app.post('/api/users', auth, roles('SYSTEM_ADMIN'), async (req, res, next) => { try { const b = req.body || {}; if (!b.name || !b.email || !b.password || !b.roleCode) return res.status(400).json({ error: 'INVALID_USER_DATA' }); const user = await one('INSERT INTO users(name,email,password_hash,role_code,department) VALUES($1,$2,$3,$4,$5) RETURNING id,name,email,role_code,department,is_active', [b.name, b.email, bcrypt.hashSync(b.password, 10), b.roleCode, b.department || null]); await audit(req.user.sub, 'USER', user.id, 'CREATE', publicUser(user)); res.status(201).json({ user: publicUser(user) }); } catch (error) { if (error.code === '23505') return res.status(409).json({ error: 'EMAIL_EXISTS' }); next(error); } });
app.patch('/api/users/:id/status', auth, roles('SYSTEM_ADMIN'), async (req, res, next) => { try { const user = await one('UPDATE users SET is_active = $1 WHERE id = $2 RETURNING id,name,email,role_code,department,is_active', [Boolean(req.body?.isActive), req.params.id]); await audit(req.user.sub, 'USER', user.id, 'STATUS_UPDATE', publicUser(user)); res.json({ user: publicUser(user) }); } catch (error) { next(error); } });
app.get('/api/roles', auth, roles('SYSTEM_ADMIN'), async (_req, res, next) => { try { res.json({ rows: await many('SELECT code,name FROM roles ORDER BY id') }); } catch (error) { next(error); } });
app.get('/api/settings/inventory-opening-balance', auth, roles('SYSTEM_ADMIN', 'SHIFT_MANAGER', 'WAREHOUSE'), async (req, res, next) => {
  try {
    const row = await one("SELECT value FROM app_settings WHERE key = 'inventory_opening_balance'");
    res.json({ openingBalance: Number(row?.value ?? 0) });
  } catch (error) { next(error); }
});
app.patch('/api/settings/inventory-opening-balance', auth, roles('SYSTEM_ADMIN'), async (req, res, next) => {
  try {
    const value = Number(req.body?.openingBalance);
    if (!Number.isFinite(value) || value < 0) return res.status(400).json({ error: 'INVALID_OPENING_BALANCE' });
    await pool.query("INSERT INTO app_settings(key,value,updated_at,updated_by) VALUES('inventory_opening_balance',$1,now(),$2) ON CONFLICT(key) DO UPDATE SET value=$1, updated_at=now(), updated_by=$2", [String(value), req.user.sub]);
    await audit(req.user.sub, 'SETTING', 0, 'UPDATE_INVENTORY_OPENING_BALANCE', { openingBalance: value });
    res.json({ openingBalance: value });
  } catch (error) { next(error); }
});

app.post('/api/shifts', auth, roles('SHIFT_MANAGER', 'SYSTEM_ADMIN'), async (req, res, next) => { try { const b = req.body || {}; const shiftNo = String(b.shiftNo || '').trim(); const date = b.shiftDate || new Date().toISOString().slice(0, 10); if (!shiftNo) return res.status(400).json({ error: 'INVALID_SHIFT' }); const shift = await one('INSERT INTO shifts(shift_no,shift_date,starts_at,ends_at,status,manager_id,opened_at) VALUES($1,$2,$3,$4,\'RUNNING\',$5,now()) RETURNING *', [shiftNo, date, b.startsAt || '16:00', b.endsAt || '00:00', req.user.sub]); await audit(req.user.sub, 'SHIFT', shift.id, 'OPEN', shift); res.status(201).json({ shift }); } catch (error) { if (error.code === '23505') return res.status(409).json({ error: 'SHIFT_NO_EXISTS' }); next(error); } });
app.get('/api/shifts/:id/close-review', auth, roles('SHIFT_MANAGER', 'SYSTEM_ADMIN'), async (req, res, next) => { try { const shift = await one('SELECT * FROM shifts WHERE id = $1', [req.params.id]); if (!shift) return res.status(404).json({ error: 'SHIFT_NOT_FOUND' }); const [attendance, production, fridges, downtime, quality, maintenance, receipts, problems] = await Promise.all([one('SELECT COUNT(*)::int AS count FROM attendance WHERE shift_id=$1', [req.params.id]), one('SELECT COUNT(*)::int AS count FROM production_hourly WHERE shift_id=$1', [req.params.id]), one('SELECT COUNT(*)::int AS count FROM fridge_readings WHERE shift_id=$1', [req.params.id]), one("SELECT COUNT(*)::int AS count FROM downtime WHERE shift_id=$1 AND status <> 'CLOSED'", [req.params.id]), one('SELECT COUNT(*)::int AS count FROM quality_checks WHERE shift_id=$1', [req.params.id]), one("SELECT COUNT(*)::int AS count FROM maintenance_tickets WHERE shift_id=$1 AND status NOT IN ('CLOSED','RESOLVED')", [req.params.id]), one('SELECT COUNT(*)::int AS count FROM raw_receipts WHERE receipt_date=$1', [shift.shift_date]), one("SELECT COUNT(*)::int AS count FROM problems WHERE shift_id=$1 AND status NOT IN ('RESOLVED','CLOSED')", [req.params.id])]); const item = (label, count, required = false) => ({ key: label, label, status: count > 0 && required ? 'COMPLETE' : count > 0 ? 'WARNING' : 'PROBLEM', detail: String(count) }); const items = [item('الحضور', attendance.count, true), item('الإنتاج', production.count, true), item('قراءات الثلاجات', fridges.count, true), item('التوقفات المفتوحة', downtime.count), item('الجودة', quality.count, true), item('أعطال الصيانة المفتوحة', maintenance.count), item('الاستلامات', receipts.count), item('المشاكل المفتوحة', problems.count)]; res.json({ review: { shift, items, hasProblems: items.some((row) => row.status === 'PROBLEM' || row.status === 'WARNING') } }); } catch (error) { next(error); } });
app.get('/api/shifts/:id/problems', auth, roles('SYSTEM_ADMIN', 'SHIFT_MANAGER', 'PRODUCTION', 'PRODUCTION_ENGINEER', 'QUALITY', 'QUALITY_ENGINEER', 'MAINTENANCE', 'WAREHOUSE'), async (req, res, next) => { try { res.json({ rows: await many('SELECT * FROM problems WHERE shift_id=$1 ORDER BY id DESC', [req.params.id]) }); } catch (error) { next(error); } });
app.post('/api/shifts/:id/problems/from-notification/:notificationId', auth, roles('SYSTEM_ADMIN', 'SHIFT_MANAGER', 'PRODUCTION', 'PRODUCTION_ENGINEER', 'QUALITY', 'QUALITY_ENGINEER', 'MAINTENANCE', 'WAREHOUSE'), async (req, res, next) => { try { const shift = await editableShift(req, res, req.params.id); if (!shift) return; const notification = await one('SELECT * FROM notifications WHERE id=$1 AND shift_id=$2', [req.params.notificationId, shift.id]); if (!notification) return res.status(404).json({ error: 'NOTIFICATION_NOT_FOUND' }); const severity = notification.severity === 'CRITICAL' ? 'HIGH' : notification.severity === 'WARNING' ? 'MEDIUM' : 'LOW'; const row = await one('INSERT INTO problems(shift_id,title,department,problem_date,problem_time,severity,status,notes,created_by,source_notification_id) VALUES($1,$2,$3,$4,$5,$6,\'OPEN\',$7,$8,$9) RETURNING *', [shift.id, notification.title, req.body?.department || 'إدارة الوردية', shift.shift_date, new Date().toTimeString().slice(0, 5), severity, notification.body, req.user.sub, notification.id]); await audit(req.user.sub, 'PROBLEM', row.id, 'CREATE_FROM_NOTIFICATION', { notificationId: notification.id, row }); res.status(201).json({ row }); } catch (error) { next(error); } });
app.post('/api/shifts/:id/problems', auth, roles('SYSTEM_ADMIN', 'SHIFT_MANAGER', 'PRODUCTION', 'PRODUCTION_ENGINEER', 'QUALITY', 'QUALITY_ENGINEER', 'MAINTENANCE', 'WAREHOUSE'), async (req, res, next) => { try { const shift = await editableShift(req, res, req.params.id); if (!shift) return; const b = req.body || {}; if (!b.title || !b.department || !['HIGH', 'MEDIUM', 'LOW'].includes(String(b.severity))) return res.status(400).json({ error: 'INVALID_PROBLEM' }); const row = await one('INSERT INTO problems(shift_id,title,department,line_code,machine_name,problem_date,problem_time,severity,owner,action_taken,status,notes,created_by) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13) RETURNING *', [shift.id, b.title, b.department, b.lineCode || null, b.machineName || null, b.problemDate || shift.shift_date, b.problemTime || new Date().toTimeString().slice(0, 5), b.severity, b.owner || null, b.actionTaken || null, b.status || 'OPEN', b.notes || null, req.user.sub]); await audit(req.user.sub, 'PROBLEM', row.id, 'CREATE', row); res.status(201).json({ row }); } catch (error) { next(error); } });
app.patch('/api/shifts/:id/problems/:problemId', auth, roles('SYSTEM_ADMIN', 'SHIFT_MANAGER', 'PRODUCTION', 'PRODUCTION_ENGINEER', 'QUALITY', 'QUALITY_ENGINEER', 'MAINTENANCE', 'WAREHOUSE'), async (req, res, next) => { try { const shift = await editableShift(req, res, req.params.id); if (!shift) return; const old = await one('SELECT * FROM problems WHERE id=$1 AND shift_id=$2', [req.params.problemId, shift.id]); if (!old) return res.status(404).json({ error: 'PROBLEM_NOT_FOUND' }); const b = req.body || {}; const status = b.status || old.status; const row = await one("UPDATE problems SET title=COALESCE($1,title), department=COALESCE($2,department), line_code=COALESCE($3,line_code), machine_name=COALESCE($4,machine_name), severity=COALESCE($5,severity), owner=COALESCE($6,owner), action_taken=COALESCE($7,action_taken), status=$8, resolved_at=CASE WHEN $8 IN ('RESOLVED','CLOSED') THEN COALESCE(resolved_at,now()) ELSE NULL END, notes=COALESCE($9,notes), updated_by=$10 WHERE id=$11 RETURNING *", [b.title, b.department, b.lineCode, b.machineName, b.severity, b.owner, b.actionTaken, status, b.notes, req.user.sub, req.params.problemId]); await audit(req.user.sub, 'PROBLEM', row.id, req.exceptionReason ? 'EXCEPTION_UPDATE' : 'UPDATE', row, old); res.json({ row }); } catch (error) { next(error); } });
app.get('/api/shifts/:id/report', auth, roles(...reportRoles), async (req, res, next) => {
  try {
    const report = await buildReport(req.params.id);
    if (!report) return res.status(404).json({ error: 'SHIFT_NOT_FOUND' });
    res.json({ report });
  } catch (error) { next(error); }
});
app.get('/api/shifts/:id/report.csv', auth, roles(...reportRoles), async (req, res, next) => {
  try {
    const report = await buildReport(req.params.id);
    if (!report) return res.status(404).json({ error: 'SHIFT_NOT_FOUND' });
    const csvCell = (value) => `"${String(value ?? '').replaceAll('"', '""')}"`;
    const rows = [
      ['الساعة', 'القسم', 'الخط', 'المنتج', 'المستهدف', 'الإنتاج الفعلي', 'الفرق', 'نسبة التحقيق'],
      ...report.production_rows.map((row) => [
        row.hour_started_at,
        row.department || 'PACKING',
        row.line_code,
        row.product_name,
        row.target_qty,
        row.actual_qty,
        row.actual_qty - row.target_qty,
        `${Number(row.achievement).toFixed(1)}%`,
      ]),
    ];
    const csv = `\uFEFF${rows.map((row) => row.map(csvCell).join(',')).join('\r\n')}`;
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', `attachment; filename="shift-${report.shift.shift_no}.csv"`);
    res.send(csv);
  } catch (error) { next(error); }
});
app.get('/api/shifts/:id/report.html', auth, roles(...reportRoles), async (req, res, next) => {
  try {
    const report = await buildReport(req.params.id);
    if (!report) return res.status(404).json({ error: 'SHIFT_NOT_FOUND' });
    const escapeHtml = (value) => String(value ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
    const percent = (value) => `${Number(value || 0).toFixed(1)}%`;
    const table = report.production_rows.map((row) => `<tr><td>${escapeHtml(row.hour_started_at)}</td><td>${escapeHtml(row.department || 'PACKING')}</td><td>${escapeHtml(row.line_code)}</td><td>${escapeHtml(row.product_name)}</td><td>${row.target_qty}</td><td>${row.actual_qty}</td><td>${percent(row.achievement)}</td></tr>`).join('');
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.send(`<!doctype html><html dir="rtl" lang="ar"><head><meta charset="utf-8"><title>تقرير ${escapeHtml(report.shift.shift_no)}</title><style>body{font-family:Arial,sans-serif;padding:32px;color:#1f2933}h1{color:#0e7c66}.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:12px}.card{border:1px solid #d9e0d6;border-radius:8px;padding:14px}.value{font-size:22px;font-weight:bold}table{border-collapse:collapse;width:100%;margin-top:24px}td,th{border:1px solid #d9e0d6;padding:8px;text-align:right}@media print{button{display:none}}</style></head><body><h1>تقرير الوردية الثانية</h1><p>${escapeHtml(report.shift.shift_no)} · ${escapeHtml(report.shift.shift_date)}</p><div class="grid"><div class="card">الحضور<div class="value">${percent(report.attendance_rate)}</div></div><div class="card">الإنتاج<div class="value">${report.production.actual} / ${report.production.target}</div></div><div class="card">تحقيق المستهدف<div class="value">${percent(report.achievement)}</div></div><div class="card">نسبة الرفض<div class="value">${percent(report.rejection_rate)}</div></div></div><table><thead><tr><th>الساعة</th><th>القسم</th><th>الخط</th><th>المنتج</th><th>المستهدف</th><th>الفعلي</th><th>التحقيق</th></tr></thead><tbody>${table}</tbody></table><script>window.print()</script></body></html>`);
  } catch (error) { next(error); }
});
app.patch('/api/shifts/:id/status', auth, roles('SHIFT_MANAGER', 'SYSTEM_ADMIN'), async (req, res, next) => { try { const status = String(req.body?.status || ''); if (!['RUNNING','PAUSED','COMPLETED','APPROVED'].includes(status)) return res.status(400).json({ error: 'INVALID_SHIFT_STATUS' }); const current = await one('SELECT * FROM shifts WHERE id=$1', [req.params.id]); if (!current) return res.status(404).json({ error: 'SHIFT_NOT_FOUND' }); if (['COMPLETED','APPROVED','CLOSED'].includes(current.status)) return res.status(409).json({ error: 'SHIFT_ALREADY_CLOSED' }); const closeNotes = String(req.body?.closeNotes || '').trim(); if (status === 'COMPLETED' && req.body?.closeDespiteIssues === true && !closeNotes) return res.status(400).json({ error: 'CLOSE_NOTES_REQUIRED' }); const nextStatus = status === 'COMPLETED' ? 'CLOSED' : status; const shift = await one('UPDATE shifts SET status = $1, closed_at = CASE WHEN $1 = \'CLOSED\' THEN now() ELSE closed_at END, approved_at = CASE WHEN $1 = \'APPROVED\' THEN now() ELSE approved_at END WHERE id = $2 RETURNING *', [nextStatus, req.params.id]); await audit(req.user.sub, 'SHIFT', shift.id, `STATUS_${nextStatus}`, { status: nextStatus, closeNotes }); res.json({ shift }); } catch (error) { next(error); } });
app.get('/api/shifts/:id/audit-log', auth, roles('SYSTEM_ADMIN', 'SHIFT_MANAGER', 'PRODUCTION_ENGINEER', 'QUALITY_ENGINEER'), async (_req, res, next) => { try { res.json({ rows: await many('SELECT a.*,u.name AS user_name FROM audit_logs a LEFT JOIN users u ON u.id=a.user_id ORDER BY a.id DESC LIMIT 200') }); } catch (error) { next(error); } });
const readModuleRoles = { quality: qualityRoles, supplies: ['SYSTEM_ADMIN', 'SHIFT_MANAGER', 'WAREHOUSE', 'PRODUCTION_ENGINEER'], downtime: productionRoles, maintenance: ['SYSTEM_ADMIN', 'SHIFT_MANAGER', 'MAINTENANCE', 'PRODUCTION', 'PRODUCTION_ENGINEER'], inventory: ['SYSTEM_ADMIN', 'SHIFT_MANAGER', 'WAREHOUSE'] };
for (const [name, pathName] of [['quality_checks', 'quality'], ['supplies', 'supplies'], ['downtime', 'downtime'], ['maintenance_tickets', 'maintenance'], ['inventory_transactions', 'inventory']]) app.get(`/api/shifts/:id/${pathName}`, auth, roles(...readModuleRoles[pathName]), async (req, res, next) => { try { res.json({ rows: await many(`SELECT * FROM ${name} WHERE shift_id = $1 ORDER BY id DESC`, [req.params.id]) }); } catch (error) { next(error); } });
app.post('/api/shifts/:id/supplies', auth, roles('SYSTEM_ADMIN', 'SHIFT_MANAGER', 'WAREHOUSE', 'PRODUCTION_ENGINEER'), async (req, res, next) => { try { const b = req.body || {}; const quantity = Number(b.quantity); if (!b.supplier || !b.materialName || !b.unit || !Number.isFinite(quantity) || quantity <= 0) return res.status(400).json({ error: 'INVALID_SUPPLY' }); const row = await one('INSERT INTO supplies(shift_id,supplier,material_name,quantity,unit,batch_no,status,notes) VALUES($1,$2,$3,$4,$5,$6,$7,$8) RETURNING *', [req.params.id, b.supplier, b.materialName, quantity, b.unit, b.batchNo || null, b.status || 'PENDING', b.notes || null]); await audit(req.user.sub, 'SUPPLY', row.id, 'CREATE', row); res.status(201).json({ row }); } catch (error) { next(error); } });
app.post('/api/shifts/:id/downtime', auth, roles(...productionRoles), async (req, res, next) => { try { const b = req.body || {}; const minutes = Number(b.minutes); if (!b.lineCode || !b.machineName || !b.reasonType || !Number.isInteger(minutes) || minutes <= 0) return res.status(400).json({ error: 'INVALID_DOWNTIME' }); const row = await one('INSERT INTO downtime(shift_id,line_code,machine_name,minutes,reason_type,status,action_taken) VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING *', [req.params.id, b.lineCode, b.machineName, minutes, b.reasonType, b.status || 'OPEN', b.actionTaken || null]); await audit(req.user.sub, 'DOWNTIME', row.id, 'CREATE', row); if (minutes > 15) await pool.query("INSERT INTO notifications(shift_id,severity,title,body) VALUES($1,'WARNING',$2,$3)", [req.params.id, 'توقف خط الإنتاج لمدة طويلة', `${b.lineCode} · ${minutes} دقيقة`]); res.status(201).json({ row }); } catch (error) { next(error); } });
app.post('/api/shifts/:id/maintenance', auth, roles('SYSTEM_ADMIN', 'SHIFT_MANAGER', 'MAINTENANCE', 'PRODUCTION', 'PRODUCTION_ENGINEER'), async (req, res, next) => { try { const b = req.body || {}; if (!b.ticketNo || !b.lineCode || !b.machineName || !b.description) return res.status(400).json({ error: 'INVALID_MAINTENANCE' }); const row = await one('INSERT INTO maintenance_tickets(shift_id,ticket_no,line_code,machine_name,severity,description,status,action_taken) VALUES($1,$2,$3,$4,$5,$6,$7,$8) RETURNING *', [req.params.id, b.ticketNo, b.lineCode, b.machineName, b.severity || 'MEDIUM', b.description, b.status || 'OPEN', b.actionTaken || null]); await audit(req.user.sub, 'MAINTENANCE', row.id, 'CREATE', row); res.status(201).json({ row }); } catch (error) { next(error); } });
app.post('/api/shifts/:id/inventory', auth, roles('SYSTEM_ADMIN', 'SHIFT_MANAGER', 'WAREHOUSE'), async (req, res, next) => { try { const b = req.body || {}; const quantity = Number(b.quantity); if (!b.materialName || !['RECEIPT', 'ISSUE', 'RETURN'].includes(String(b.transactionType)) || !Number.isFinite(quantity) || quantity <= 0) return res.status(400).json({ error: 'INVALID_INVENTORY' }); const row = await one('INSERT INTO inventory_transactions(shift_id,material_name,transaction_type,quantity,unit,reference_no,notes) VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING *', [req.params.id, b.materialName, b.transactionType, quantity, b.unit || 'kg', b.referenceNo || null, b.notes || null]); await audit(req.user.sub, 'INVENTORY', row.id, 'CREATE', row); res.status(201).json({ row }); } catch (error) { next(error); } });
app.get('/api/shifts/:id/notifications', auth, async (req, res, next) => { try { let rows = await many('SELECT * FROM notifications WHERE shift_id = $1 ORDER BY id DESC', [req.params.id]); if (req.user.role === 'SECURITY') rows = rows.filter((item) => String(item.title).includes('حضور') || String(item.title).includes('غياب')); if (['QUALITY', 'QUALITY_ENGINEER'].includes(req.user.role)) rows = rows.filter((item) => String(item.title).includes('جودة') || String(item.title).includes('Defrost') || String(item.title).includes('ثلاجة')); res.json({ rows }); } catch (error) { next(error); } });
app.patch('/api/notifications/:id/read', auth, async (req, res, next) => { try { await pool.query('UPDATE notifications SET is_read=TRUE WHERE id=$1', [req.params.id]); res.json({ ok: true }); } catch (error) { next(error); } });
// Serve the built Flutter web app from backend/public, if present (see
// `flutter build web` step in the deploy docs). API routes above always take
// priority; this only serves the app shell for everything else.
const publicDir = path.resolve(__dirname, '..', 'public');
const publicDirExists = fs.existsSync(publicDir);
console.log('[static] publicDir =', publicDir, '| exists =', publicDirExists, '| __dirname =', __dirname);
if (publicDirExists) {
  try { console.log('[static] contents =', fs.readdirSync(publicDir)); } catch (e) { console.log('[static] readdir error', e.message); }
  app.use(express.static(publicDir, {
    etag: false,
    lastModified: false,
    setHeaders: (res) => res.set('Cache-Control', 'no-cache'),
  }));
  app.get(/^(?!\/api).*/, (req, res, next) => {
    res.set('Cache-Control', 'no-cache');
    res.sendFile(path.join(publicDir, 'index.html'), { etag: false, lastModified: false }, (err) => { if (err) next(err); });
  });
} else {
  try { console.log('[static] backend dir contents =', fs.readdirSync(path.resolve(__dirname, '..'))); } catch (e) { console.log('[static] backend readdir error', e.message); }
}

app.use((error, _req, res, _next) => { console.error(error); res.status(500).json({ error: 'INTERNAL_SERVER_ERROR' }); });

async function ensureSchemaAndSeed() {
  const schema = fs.readFileSync(path.resolve(__dirname, '..', 'schema.postgres.full.sql'), 'utf8');
  await pool.query(schema);
  await pool.query(`INSERT INTO roles(code,name) VALUES ('SYSTEM_ADMIN','System Admin'),('SHIFT_MANAGER','Shift Manager'),('SECURITY','Security'),('QUALITY','Quality'),('QUALITY_ENGINEER','Quality Engineer'),('PRODUCTION','Production'),('PRODUCTION_ENGINEER','Production Engineer'),('MAINTENANCE','Maintenance'),('WAREHOUSE','Warehouse') ON CONFLICT(code) DO NOTHING`);
  const password = bcrypt.hashSync(process.env.SEED_ADMIN_PASSWORD || 'Admin@123456', 10);
  await pool.query(`INSERT INTO users(name,email,password_hash,role_code,department) VALUES ('مدير النظام','admin@wardia.app',$1,'SYSTEM_ADMIN','إدارة النظام'),('محمد حمدي','manager@wardia.app',$2,'SHIFT_MANAGER','إدارة الوردية') ON CONFLICT(email) DO NOTHING`, [password, bcrypt.hashSync('123456', 10)]);
  const demoUsers = [
    ['مدير الوردية التجريبي', 'shift.manager@wardia.app', 'Shift@123456', 'SHIFT_MANAGER', 'إدارة الوردية'],
    ['مهندس الإنتاج التجريبي', 'production.engineer@wardia.app', 'Production@123456', 'PRODUCTION_ENGINEER', 'الإنتاج'],
    ['مهندس الجودة التجريبي', 'quality.engineer@wardia.app', 'Quality@123456', 'QUALITY_ENGINEER', 'الجودة'],
    ['فرد الأمن التجريبي', 'security@wardia.app', 'Security@123456', 'SECURITY', 'الأمن'],
  ];
  for (const [name, email, plainPassword, role, department] of demoUsers) await pool.query('INSERT INTO users(name,email,password_hash,role_code,department) VALUES($1,$2,$3,$4,$5) ON CONFLICT(email) DO NOTHING', [name, email, bcrypt.hashSync(plainPassword, 10), role, department]);
    await pool.query("INSERT INTO app_settings(key,value) VALUES('inventory_opening_balance','0') ON CONFLICT(key) DO NOTHING");
await pool.query(`INSERT INTO shifts(shift_no,shift_date,starts_at,ends_at,status,manager_id,opened_at) SELECT 'SHIFT-2026-08-21-02','2026-08-21','16:00','00:00','RUNNING',id,now() FROM users WHERE email='manager@wardia.app' ON CONFLICT(shift_no) DO NOTHING`);
}

// Start listening immediately so Railway's healthcheck can reach /api/health
// as soon as the process is up, instead of waiting on schema/seed queries
// that depend on the database being reachable (which can take longer than
// the healthcheck timeout, or hang indefinitely if DATABASE_URL/PGSSL/network
// are misconfigured). Schema/seed setup then runs in the background; it is
// idempotent (IF NOT EXISTS / ON CONFLICT DO NOTHING everywhere) so it is
// safe to retry on every boot and safe to fail without crashing the server.
app.listen(port, '0.0.0.0', () => {
  console.log(`Wardia PostgreSQL API listening on http://0.0.0.0:${port}`);
  ensureSchemaAndSeed()
    .then(() => console.log('Schema check and seed data: OK'))
    .catch((error) => {
      console.error('Schema/seed setup failed (server keeps running, /api/health will report DB status):', error.message);
    });
});
