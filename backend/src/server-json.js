require('dotenv').config({ path: require('node:path').resolve(__dirname, '..', '.env') });
const express = require('express');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const store = require('./store');

const app = express();
const port = Number(process.env.PORT || 5521);
const jwtSecret = process.env.JWT_SECRET || 'local-development-secret-change-me';
app.use(cors()); app.use(express.json({ limit: '1mb' }));
const publicUser = (user) => ({ id: user.id, name: user.name, email: user.email, role: user.role_code, department: user.department, isActive: user.is_active });
const calculated = (row) => ({ ...row, difference: row.actual_qty - row.target_qty, achievement: row.target_qty ? row.actual_qty / row.target_qty * 100 : 0 });
const publicEmployee = (employee) => ({ id: employee.id, employeeNo: employee.employee_no, name: employee.name, department: employee.department, jobTitle: employee.job_title, category: employee.category, shiftName: employee.shift_name, startDate: employee.start_date || null, notes: employee.notes || null, isActive: employee.is_active });
const publicProductGuide = (product) => ({ id: product.id, productCode: product.product_code, name: product.name, department: product.department, rawMaterial: product.raw_material, packWeight: product.pack_weight, packSize: product.pack_size, size: product.size, temperature: product.temperature, lineSpeed: product.line_speed, machineSettings: product.machine_settings, operatingTime: product.operating_time, instructions: product.instructions, steps: product.steps || [], imageUrl: product.image_url, isActive: product.is_active });
const publicFridge = (fridge) => ({ id: fridge.id, fridgeNo: fridge.fridge_no, name: fridge.name, minTemp: fridge.min_temp, maxTemp: fridge.max_temp, isActive: fridge.is_active });
const publicReceipt = (receipt) => ({ id: receipt.id, receiptDate: receipt.receipt_date, receiptTime: receipt.receipt_time, materialName: receipt.material_name, supplier: receipt.supplier, supplierCode: receipt.supplier_code, grossWeight: receipt.gross_weight, discountRate: receipt.discount_rate, discountAmount: receipt.discount_amount, netWeight: receipt.net_weight, defects: receipt.defects, notes: receipt.notes, createdBy: receipt.created_by });
const publicPackagingReceipt = (receipt) => ({ id: receipt.id, receiptDate: receipt.receipt_date, receiptTime: receipt.receipt_time, supplier: receipt.supplier, itemName: receipt.item_name, itemCode: receipt.item_code, quantity: receipt.quantity, unit: receipt.unit, receiptNo: receipt.receipt_no, notes: receipt.notes, createdBy: receipt.created_by });
const publicContainerLoading = (row) => ({ id: row.id, shiftId: row.shift_id, containerNo: row.container_no, productName: row.product_name, containerTempBefore: row.container_temp_before, productTemp: row.product_temp, containerTempAfter: row.container_temp_after, cartons: row.cartons, quantity: row.quantity, loadedAt: row.loaded_at, notes: row.notes, createdBy: row.created_by, createdAt: row.created_at });
const attendanceStatuses = new Set(['PRESENT', 'LATE', 'MISSION', 'LEAVE', 'ABSENT_EXCUSED', 'ABSENT_UNEXCUSED']);
const publicAttendance = (record) => {
  const employee = record.employee || store.employeeById(record.employee_id) || record;
  return { id: record.id, shiftId: record.shift_id, employeeId: record.employee_id, employee: publicEmployee(employee), attendanceDate: record.attendance_date, shiftName: record.shift_name, status: record.status, checkIn: record.check_in, checkOut: record.check_out, notes: record.notes, updatedBy: record.updated_by, updatedAt: record.updated_at || null };
};
function attendanceSummary(rows) {
  const presentRows = rows.filter((row) => ['PRESENT', 'LATE'].includes(row.status));
  const absentRows = rows.filter((row) => ['ABSENT_EXCUSED', 'ABSENT_UNEXCUSED'].includes(row.status));
  return {
    total: rows.length,
    present: presentRows.length,
    absent: absentRows.length,
    late: rows.filter((row) => row.status === 'LATE').length,
    attendanceRate: rows.length ? presentRows.length / rows.length * 100 : 0,
    absenceRate: rows.length ? absentRows.length / rows.length * 100 : 0,
  };
}
function auth(req, res, next) { const value = req.headers.authorization || ''; const token = value.startsWith('Bearer ') ? value.slice(7) : null; if (!token) return res.status(401).json({ error: 'AUTH_REQUIRED' }); try { req.user = jwt.verify(token, jwtSecret); return next(); } catch { return res.status(401).json({ error: 'INVALID_TOKEN' }); } }
function roles(...allowed) { return (req, res, next) => allowed.includes(req.user.role) ? next() : res.status(403).json({ error: 'FORBIDDEN' }); }
const attendanceRoles = ['SYSTEM_ADMIN', 'SHIFT_MANAGER', 'SECURITY'];
const productionRoles = ['SYSTEM_ADMIN', 'SHIFT_MANAGER', 'PRODUCTION', 'PRODUCTION_ENGINEER'];
const qualityRoles = ['SYSTEM_ADMIN', 'SHIFT_MANAGER', 'QUALITY', 'QUALITY_ENGINEER'];
const containerReadRoles = ['SYSTEM_ADMIN', 'SHIFT_MANAGER', 'QUALITY', 'QUALITY_ENGINEER'];
const containerWriteRoles = ['SYSTEM_ADMIN', 'QUALITY', 'QUALITY_ENGINEER'];
const guideReadRoles = ['SYSTEM_ADMIN', 'SHIFT_MANAGER', 'PRODUCTION', 'PRODUCTION_ENGINEER', 'QUALITY', 'QUALITY_ENGINEER'];
const receiptReadRoles = ['SYSTEM_ADMIN', 'SHIFT_MANAGER', 'WAREHOUSE', 'PRODUCTION_ENGINEER'];
const reportRoles = ['SYSTEM_ADMIN', 'SHIFT_MANAGER', 'PRODUCTION_ENGINEER', 'QUALITY_ENGINEER'];
function shiftOr404(req, res) { const shift = store.shiftById(req.params.id); if (!shift) res.status(404).json({ error: 'SHIFT_NOT_FOUND' }); return shift; }
function editableShift(req, res, shiftId) {
  const shift = store.shiftById(shiftId);
  if (!shift) { res.status(404).json({ error: 'SHIFT_NOT_FOUND' }); return null; }
  if (store.isShiftClosed(shift)) {
    const reason = String(req.body?.exceptionReason || '').trim();
    if (req.user.role !== 'SHIFT_MANAGER' || !reason) { res.status(409).json({ error: 'SHIFT_CLOSED', message: 'الوردية مغلقة وتحتاج تعديلًا استثنائيًا بسبب موثق' }); return null; }
    req.exceptionReason = reason;
  }
  return shift;
}
function auditMutation(req, entityType, entityId, action, data) {
  store.auditChange(req.user.sub, entityType, entityId, req.exceptionReason ? `EXCEPTION_${action}` : action, null, { ...data, ...(req.exceptionReason ? { exceptionReason: req.exceptionReason } : {}) });
}
function checklist(shiftId) {
  const data = store.dashboard(shiftId);
  const report = store.report(shiftId);
  const hasAttendance = data.attendance.required > 0 || store.list('attendance_records', shiftId).length > 0;
  const hasProduction = data.production.target > 0 || store.list('production', shiftId).length > 0;
  const openProblems = store.list('problems', shiftId).filter((row) => !['RESOLVED', 'CLOSED'].includes(row.status));
  const items = [
    { key: 'attendance', label: 'العمالة', status: hasAttendance ? 'COMPLETE' : 'MISSING', detail: `${data.attendance.present} حاضر · ${data.attendance.absent} غائب · ${data.attendance.late} متأخر` },
    { key: 'production', label: 'الإنتاج', status: hasProduction ? 'COMPLETE' : 'MISSING', detail: `${data.production.actual} / ${data.production.target} · ${report.achievement.toFixed(1)}%` },
    { key: 'fridges', label: 'الثلاجات', status: report.fridge.missing ? 'WARNING' : 'COMPLETE', detail: `${report.fridge.completed} / ${report.fridge.required} قراءة` },
    { key: 'downtime', label: 'التوقفات', status: data.downtime.open_count ? 'PROBLEM' : 'COMPLETE', detail: `${data.downtime.count} بلاغ · ${data.downtime.minutes} دقيقة${data.downtime.open_count ? ' · يوجد توقف مفتوح' : ''}` },
    { key: 'quality', label: 'الجودة', status: data.quality.inspected ? 'COMPLETE' : 'WARNING', detail: `${data.quality.inspected} فحص · ${data.quality.rejected} مرفوض` },
    { key: 'maintenance', label: 'الصيانة', status: data.maintenance.open_count ? 'WARNING' : 'COMPLETE', detail: `${data.maintenance.count} بلاغ · ${data.maintenance.open_count} مفتوح` },
    { key: 'receipts', label: 'الاستلامات', status: report.raw_receipts.length + report.packaging_receipts.length ? 'COMPLETE' : 'WARNING', detail: `${report.raw_receipts.length + report.packaging_receipts.length} استلام` },
    { key: 'problems', label: 'المشاكل المفتوحة', status: openProblems.length ? 'PROBLEM' : 'COMPLETE', detail: `${openProblems.length} مشكلة مفتوحة` },
  ];
  return { shift: report.shift, items, hasProblems: items.some((item) => item.status !== 'COMPLETE'), report };
}
app.use((req, res, next) => {
  if (!['POST', 'PATCH', 'PUT', 'DELETE'].includes(req.method)) return next();
  const match = req.path.match(/^\/api\/shifts\/(\d+)\/(production|attendance|quality\/fridge-readings|downtime|maintenance|inventory|supplies|problems)(?:\/|$)/);
  if (!match) return next();
  auth(req, res, () => {
    if (!editableShift(req, res, Number(match[1]))) return;
    next();
  });
});

app.get('/api/health', (_req, res) => res.json({ ok: true, service: 'wardia-shift-api', storage: 'persistent-json', time: new Date().toISOString() }));
app.post('/api/auth/login', (req, res) => { const email = String(req.body?.email || '').trim(); const password = String(req.body?.password || ''); const user = store.userByEmail(email); if (!user || !bcrypt.compareSync(password, user.password_hash)) return res.status(401).json({ error: 'INVALID_CREDENTIALS' }); const token = jwt.sign({ sub: user.id, role: user.role_code, email: user.email }, jwtSecret, { expiresIn: '8h' }); store.audit(user.id, 'AUTH', user.id, 'LOGIN', { email: user.email }); return res.json({ token, user: publicUser(user) }); });
app.get('/api/me', auth, (req, res) => res.json({ user: publicUser(store.userById(req.user.sub)) }));
app.get('/api/roles', auth, roles('SYSTEM_ADMIN'), (_req, res) => res.json({ rows: store.state.roles }));
app.get('/api/users', auth, roles('SYSTEM_ADMIN'), (_req, res) => res.json({ rows: store.state.users.map(publicUser) }));
app.post('/api/users', auth, roles('SYSTEM_ADMIN'), (req, res) => {
  const b = req.body || {};
  if (!b.name || !b.email || !b.password || !b.roleCode) return res.status(400).json({ error: 'INVALID_USER_DATA' });
  if (store.state.users.some((user) => user.email.toLowerCase() === String(b.email).toLowerCase())) return res.status(409).json({ error: 'EMAIL_EXISTS' });
  const user = { id: Math.max(0, ...store.state.users.map((item) => item.id)) + 1, name: b.name, email: b.email, password_hash: bcrypt.hashSync(b.password, 10), role_code: b.roleCode, department: b.department || null, is_active: true };
  store.state.users.push(user); store.persist(); store.audit(req.user.sub, 'USER', user.id, 'CREATE', publicUser(user));
  res.status(201).json({ user: publicUser(user) });
});
app.patch('/api/users/:id/status', auth, roles('SYSTEM_ADMIN'), (req, res) => {
  const user = store.userById(req.params.id);
  if (!user) return res.status(404).json({ error: 'USER_NOT_FOUND' });
  user.is_active = Boolean(req.body?.isActive); store.persist(); store.audit(req.user.sub, 'USER', user.id, 'STATUS_UPDATE', publicUser(user));
  return res.json({ user: publicUser(user) });
});
app.get('/api/shifts/current', auth, (_req, res) => res.json({ shift: store.currentShift() || [...store.state.shifts].sort((a, b) => b.id - a.id)[0] || null }));
app.post('/api/shifts', auth, roles('SHIFT_MANAGER', 'SYSTEM_ADMIN'), (req, res) => {
  const b = req.body || {};
  const date = String(b.shiftDate || new Date().toISOString().slice(0, 10));
  const number = String(b.shiftNo || `SHIFT-${date}-02`);
  if (store.state.shifts.some((shift) => shift.shift_no === number)) return res.status(409).json({ error: 'SHIFT_NO_EXISTS' });
  const shift = store.add('shifts', { shift_no: number, shift_date: date, starts_at: b.startsAt || '16:00', ends_at: b.endsAt || '00:00', status: 'RUNNING', manager_id: req.user.sub, opened_at: new Date().toISOString() });
  store.audit(req.user.sub, 'SHIFT', shift.id, 'OPEN', shift);
  res.status(201).json({ shift });
});
app.get('/api/shifts/:id/close-review', auth, roles('SHIFT_MANAGER', 'SYSTEM_ADMIN'), (req, res) => {
  const shift = shiftOr404(req, res); if (!shift) return;
  res.json({ review: checklist(shift.id) });
});
app.get('/api/shifts/history', auth, roles('SYSTEM_ADMIN', 'SHIFT_MANAGER', 'PRODUCTION_ENGINEER', 'QUALITY_ENGINEER'), (req, res) => {
  const query = req.query || {};
  const rows = [...store.state.shifts].filter((shift) => (!query.from || shift.shift_date >= String(query.from)) && (!query.to || shift.shift_date <= String(query.to)) && (!query.number || String(shift.shift_no).toLowerCase().includes(String(query.number).toLowerCase())) && (!query.name || String(shift.name || shift.shift_no).toLowerCase().includes(String(query.name).toLowerCase())) && (!query.department || store.list('production', shift.id).some((row) => (row.department || 'PACKING') === String(query.department))));
  res.json({ rows: rows.sort((a, b) => b.shift_date.localeCompare(a.shift_date) || b.id - a.id).map((shift) => store.report(shift.id)) });
});
app.get('/api/shifts/:id/dashboard', auth, (req, res) => { const shift = shiftOr404(req, res); if (!shift) return; const data = store.dashboard(shift.id); if (req.user.role === 'SECURITY') return res.json({ shift, attendance: data.attendance, notifications: data.notifications.filter((item) => String(item.title).includes('حضور') || String(item.title).includes('غياب')) }); if (['QUALITY', 'QUALITY_ENGINEER'].includes(req.user.role)) return res.json({ shift, quality: data.quality, fridges: data.fridges, containers: data.containers, notifications: data.notifications.filter((item) => String(item.title).includes('جودة') || String(item.title).includes('Defrost') || String(item.title).includes('ثلاجة')) }); if (['PRODUCTION', 'PRODUCTION_ENGINEER'].includes(req.user.role)) return res.json({ shift, production: data.production, downtime: data.downtime, maintenance: data.maintenance, notifications: data.notifications }); res.json({ shift, ...data }); });
app.get('/api/shifts/:id/report', auth, roles(...reportRoles), (req, res) => { const shift = shiftOr404(req, res); if (!shift) return; res.json({ report: store.report(shift.id) }); });
app.get('/api/shifts/:id/report.csv', auth, roles(...reportRoles), (req, res) => {
  const report = store.report(req.params.id);
  const rows = [['الساعة', 'الخط', 'المنتج', 'المستهدف', 'الإنتاج الفعلي', 'الفرق', 'نسبة التحقيق'], ...report.production_rows.map((row) => [row.hour_started_at, row.line_code, row.product_name, row.target_qty, row.actual_qty, row.actual_qty - row.target_qty, row.achievement.toFixed(1) + '%'])];
  const csv = '\uFEFF' + rows.map((row) => row.map((cell) => `"${String(cell).replaceAll('"', '""')}"`).join(',')).join('\r\n');
  res.setHeader('Content-Type', 'text/csv; charset=utf-8');
  res.setHeader('Content-Disposition', `attachment; filename="shift-${report.shift.shift_no}.csv"`);
  res.send(csv);
});
app.get('/api/shifts/:id/report.html', auth, roles(...reportRoles), (req, res) => {
  const report = store.report(req.params.id);
  const percent = (value) => `${Number(value).toFixed(1)}%`;
  const table = report.production_rows.map((row) => `<tr><td>${row.hour_started_at}</td><td>${row.line_code}</td><td>${row.product_name}</td><td>${row.target_qty}</td><td>${row.actual_qty}</td><td>${percent(row.achievement)}</td></tr>`).join('');
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.send(`<!doctype html><html dir="rtl" lang="ar"><head><meta charset="utf-8"><title>تقرير ${report.shift.shift_no}</title><style>body{font-family:Arial,sans-serif;padding:32px;color:#1f2933}h1{color:#0e7c66}.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:12px}.card{border:1px solid #d9e0d6;border-radius:8px;padding:14px}.value{font-size:22px;font-weight:bold}table{border-collapse:collapse;width:100%;margin-top:24px}td,th{border:1px solid #d9e0d6;padding:8px;text-align:right}@media print{button{display:none}}</style></head><body><h1>تقرير الوردية الثانية</h1><p>${report.shift.shift_no} · ${report.shift.shift_date}</p><div class="grid"><div class="card">الحضور<div class="value">${percent(report.attendance_rate)}</div></div><div class="card">الإنتاج<div class="value">${report.production.actual} / ${report.production.target}</div></div><div class="card">تحقيق المستهدف<div class="value">${percent(report.achievement)}</div></div><div class="card">نسبة الرفض<div class="value">${percent(report.rejection_rate)}</div></div></div><table><thead><tr><th>الساعة</th><th>الخط</th><th>المنتج</th><th>المستهدف</th><th>الفعلي</th><th>التحقيق</th></tr></thead><tbody>${table}</tbody></table><script>window.print()</script></body></html>`);
});
app.patch('/api/shifts/:id/status', auth, roles('SHIFT_MANAGER', 'SYSTEM_ADMIN'), (req, res) => {
  const allowed = ['RUNNING', 'PAUSED', 'COMPLETED', 'APPROVED'];
  const status = String(req.body?.status || '');
  if (!allowed.includes(status)) return res.status(400).json({ error: 'INVALID_SHIFT_STATUS' });
  const shift = shiftOr404(req, res); if (!shift) return;
  if (['COMPLETED', 'APPROVED', 'CLOSED'].includes(shift.status)) return res.status(409).json({ error: 'SHIFT_ALREADY_CLOSED' });
  const closeNotes = String(req.body?.closeNotes || '').trim();
  if (status === 'COMPLETED' && req.body?.closeDespiteIssues === true && !closeNotes) return res.status(400).json({ error: 'CLOSE_NOTES_REQUIRED' });
  const nextStatus = status === 'COMPLETED' ? 'CLOSED' : status;
  const updated = store.updateShift(req.params.id, { status: nextStatus, ...(status === 'COMPLETED' ? { closed_at: new Date().toISOString(), close_notes: closeNotes || null } : {}), ...(status === 'APPROVED' ? { approved_at: new Date().toISOString() } : {}) });
  store.audit(req.user.sub, 'SHIFT', updated.id, `STATUS_${nextStatus}`, { status: nextStatus, closeNotes, checklist: status === 'COMPLETED' ? checklist(updated.id).items : undefined });
  res.json({ shift: updated });
});
app.get('/api/shifts/:id/problems', auth, roles('SYSTEM_ADMIN', 'SHIFT_MANAGER', 'PRODUCTION', 'PRODUCTION_ENGINEER', 'QUALITY', 'QUALITY_ENGINEER', 'MAINTENANCE', 'WAREHOUSE'), (req, res) => {
  const shift = shiftOr404(req, res); if (!shift) return;
  res.json({ rows: store.list('problems', shift.id).sort((a, b) => b.id - a.id) });
});
app.post('/api/shifts/:id/problems/from-notification/:notificationId', auth, roles('SYSTEM_ADMIN', 'SHIFT_MANAGER', 'PRODUCTION', 'PRODUCTION_ENGINEER', 'QUALITY', 'QUALITY_ENGINEER', 'MAINTENANCE', 'WAREHOUSE'), (req, res) => {
  const shift = editableShift(req, res, req.params.id); if (!shift) return;
  const notification = store.state.notifications.find((item) => item.id === Number(req.params.notificationId) && item.shift_id === shift.id);
  if (!notification) return res.status(404).json({ error: 'NOTIFICATION_NOT_FOUND' });
  const row = store.add('problems', { shift_id: shift.id, title: notification.title, department: req.body?.department || 'إدارة الوردية', line_code: req.body?.lineCode || null, machine_name: req.body?.machineName || null, problem_date: shift.shift_date, problem_time: new Date().toTimeString().slice(0, 5), severity: notification.severity === 'CRITICAL' ? 'HIGH' : notification.severity === 'WARNING' ? 'MEDIUM' : 'LOW', owner: null, action_taken: null, status: 'OPEN', resolved_at: null, notes: notification.body, created_by: req.user.sub, source_notification_id: notification.id });
  auditMutation(req, 'PROBLEM', row.id, 'CREATE_FROM_NOTIFICATION', { notificationId: notification.id, row });
  res.status(201).json({ row });
});
app.post('/api/shifts/:id/problems', auth, roles('SYSTEM_ADMIN', 'SHIFT_MANAGER', 'PRODUCTION', 'PRODUCTION_ENGINEER', 'QUALITY', 'QUALITY_ENGINEER', 'MAINTENANCE', 'WAREHOUSE'), (req, res) => {
  const shift = editableShift(req, res, req.params.id); if (!shift) return;
  const b = req.body || {};
  if (!b.title || !b.department || !b.severity) return res.status(400).json({ error: 'INVALID_PROBLEM' });
  const allowedSeverity = ['HIGH', 'MEDIUM', 'LOW'];
  if (!allowedSeverity.includes(String(b.severity))) return res.status(400).json({ error: 'INVALID_PROBLEM_SEVERITY' });
  const row = store.add('problems', { shift_id: shift.id, title: String(b.title).trim(), department: String(b.department).trim(), line_code: b.lineCode || null, machine_name: b.machineName || null, problem_date: b.problemDate || shift.shift_date, problem_time: b.problemTime || new Date().toTimeString().slice(0, 5), severity: b.severity, owner: b.owner || null, action_taken: b.actionTaken || null, status: b.status || 'OPEN', resolved_at: null, notes: b.notes || null, created_by: req.user.sub });
  auditMutation(req, 'PROBLEM', row.id, 'CREATE', row);
  res.status(201).json({ row });
});
app.patch('/api/shifts/:id/problems/:problemId', auth, roles('SYSTEM_ADMIN', 'SHIFT_MANAGER', 'PRODUCTION', 'PRODUCTION_ENGINEER', 'QUALITY', 'QUALITY_ENGINEER', 'MAINTENANCE', 'WAREHOUSE'), (req, res) => {
  const shift = editableShift(req, res, req.params.id); if (!shift) return;
  const row = store.state.problems.find((item) => item.id === Number(req.params.problemId) && item.shift_id === shift.id);
  if (!row) return res.status(404).json({ error: 'PROBLEM_NOT_FOUND' });
  const oldData = { ...row };
  const b = req.body || {};
  Object.assign(row, { title: b.title ?? row.title, department: b.department ?? row.department, line_code: b.lineCode ?? row.line_code, machine_name: b.machineName ?? row.machine_name, severity: b.severity ?? row.severity, owner: b.owner ?? row.owner, action_taken: b.actionTaken ?? row.action_taken, status: b.status ?? row.status, resolved_at: ['RESOLVED', 'CLOSED'].includes(String(b.status || row.status)) ? (b.resolvedAt || row.resolved_at || new Date().toISOString()) : null, notes: b.notes ?? row.notes, updated_by: req.user.sub });
  store.persist();
  store.auditChange(req.user.sub, 'PROBLEM', row.id, req.exceptionReason ? 'EXCEPTION_UPDATE' : 'UPDATE', oldData, { ...row, ...(req.exceptionReason ? { exceptionReason: req.exceptionReason } : {}) });
  res.json({ row });
});
app.get('/api/shifts/:id/production/hourly', auth, roles(...productionRoles), (req, res) => {
  const department = req.query.department ? String(req.query.department) : null;
  const rows = store.list('production', req.params.id).filter((row) => !department || (row.department || 'PACKING') === department).sort((a, b) => a.hour_started_at.localeCompare(b.hour_started_at)).map(calculated);
  const summary = rows.reduce((result, row) => ({ target: result.target + row.target_qty, actual: result.actual + row.actual_qty, downtime: result.downtime + (row.downtime_minutes || 0), hours: result.hours + 1, products: result.products.add(row.product_name) }), { target: 0, actual: 0, downtime: 0, hours: 0, products: new Set() });
  res.json({ rows, summary: { target: summary.target, actual: summary.actual, achievement: summary.target ? summary.actual / summary.target * 100 : 0, downtime: summary.downtime, hours: summary.hours, products: summary.products.size } });
});
app.post('/api/shifts/:id/production/hourly', auth, roles(...productionRoles), (req, res) => { const shift = editableShift(req, res, req.params.id); if (!shift) return; const b = req.body || {}; const department = ['PACKING', 'IQF'].includes(String(b.department)) ? String(b.department) : 'PACKING'; if (!b.lineCode || !b.productName || !b.hourStartedAt || !Number.isInteger(b.targetQty) || b.targetQty <= 0 || !Number.isInteger(b.actualQty) || b.actualQty < 0) return res.status(400).json({ error: 'INVALID_PRODUCTION_DATA' }); const row = store.add('production', { shift_id: shift.id, department, line_code: b.lineCode, machine_name: b.machineName || null, product_name: b.productName, workers_count: b.workersCount || 0, hour_started_at: b.hourStartedAt, target_qty: b.targetQty, actual_qty: b.actualQty, waste_qty: b.wasteQty || 0, rejected_qty: b.rejectedQty || 0, downtime_minutes: b.downtimeMinutes || 0, downtime_reason: b.downtimeReason || null, notes: b.notes || null }); auditMutation(req, 'PRODUCTION_HOURLY', row.id, 'CREATE', b); if (b.actualQty / b.targetQty < 0.9) store.add('notifications', { shift_id: shift.id, severity: 'WARNING', title: 'الإنتاج أقل من المستهدف', body: `ساعة ${b.hourStartedAt} أقل من 90%`, is_read: false }); res.status(201).json({ row: calculated(row) }); });
app.get('/api/products/guides', auth, roles(...guideReadRoles), (req, res) => { const q = String(req.query.q || '').trim().toLowerCase(); const department = String(req.query.department || ''); const rows = store.state.product_guides.filter((product) => product.is_active !== false && (!q || product.name.toLowerCase().includes(q) || product.product_code.toLowerCase().includes(q)) && (!department || product.department === department)); res.json({ rows: rows.map(publicProductGuide) }); });
app.post('/api/products/guides', auth, roles('PRODUCTION', 'PRODUCTION_ENGINEER', 'SYSTEM_ADMIN'), (req, res) => { const b = req.body || {}; if (!b.productCode || !b.name || !['PACKING', 'IQF'].includes(String(b.department))) return res.status(400).json({ error: 'INVALID_PRODUCT_GUIDE' }); if (store.state.product_guides.some((product) => product.product_code.toLowerCase() === String(b.productCode).toLowerCase())) return res.status(409).json({ error: 'PRODUCT_CODE_EXISTS' }); const product = store.add('product_guides', { product_code: b.productCode, name: b.name, department: b.department, raw_material: b.rawMaterial || '', pack_weight: b.packWeight || null, pack_size: b.packSize || '', size: b.size || '', temperature: b.temperature || null, line_speed: b.lineSpeed || null, machine_settings: b.machineSettings || '', operating_time: b.operatingTime || '', instructions: b.instructions || '', steps: Array.isArray(b.steps) ? b.steps : [], image_url: b.imageUrl || null, is_active: true }); store.audit(req.user.sub, 'PRODUCT_GUIDE', product.id, 'CREATE', publicProductGuide(product)); res.status(201).json({ product: publicProductGuide(product) }); });
app.patch('/api/products/guides/:id', auth, roles('PRODUCTION', 'PRODUCTION_ENGINEER', 'SYSTEM_ADMIN'), (req, res) => { const product = store.state.product_guides.find((item) => item.id === Number(req.params.id)); if (!product) return res.status(404).json({ error: 'PRODUCT_GUIDE_NOT_FOUND' }); const oldData = publicProductGuide({ ...product }); const b = req.body || {}; Object.assign(product, { name: b.name ?? product.name, department: b.department ?? product.department, raw_material: b.rawMaterial ?? product.raw_material, pack_weight: b.packWeight ?? product.pack_weight, pack_size: b.packSize ?? product.pack_size, size: b.size ?? product.size, temperature: b.temperature ?? product.temperature, line_speed: b.lineSpeed ?? product.line_speed, machine_settings: b.machineSettings ?? product.machine_settings, operating_time: b.operatingTime ?? product.operating_time, instructions: b.instructions ?? product.instructions, steps: Array.isArray(b.steps) ? b.steps : product.steps, image_url: b.imageUrl ?? product.image_url }); store.persist(); store.auditChange(req.user.sub, 'PRODUCT_GUIDE', product.id, 'UPDATE', oldData, publicProductGuide(product)); res.json({ product: publicProductGuide(product) }); });
app.get('/api/quality/fridges', auth, roles(...qualityRoles), (_req, res) => res.json({ rows: store.state.fridges.filter((fridge) => fridge.is_active !== false).map(publicFridge) }));
app.post('/api/quality/fridges', auth, roles('QUALITY', 'QUALITY_ENGINEER', 'SYSTEM_ADMIN'), (req, res) => { const b = req.body || {}; if (!b.fridgeNo || !b.name) return res.status(400).json({ error: 'INVALID_FRIDGE' }); const fridge = store.add('fridges', { fridge_no: b.fridgeNo, name: b.name, min_temp: b.minTemp ?? null, max_temp: b.maxTemp ?? null, is_active: true }); store.audit(req.user.sub, 'FRIDGE', fridge.id, 'CREATE', publicFridge(fridge)); res.status(201).json({ fridge: publicFridge(fridge) }); });
app.get('/api/shifts/:id/container-loadings', auth, roles(...containerReadRoles), (req, res) => {
  const shift = shiftOr404(req, res); if (!shift) return;
  res.json({ rows: store.list('container_loadings', shift.id).sort((a, b) => b.id - a.id).map(publicContainerLoading), summary: { count: store.list('container_loadings', shift.id).length } });
});
app.post('/api/shifts/:id/container-loadings', auth, roles(...containerWriteRoles), (req, res) => {
  const shift = editableShift(req, res, req.params.id); if (!shift) return;
  const b = req.body || {};
  const numericFields = ['containerTempBefore', 'productTemp', 'containerTempAfter', 'cartons', 'quantity'];
  if (!b.containerNo || !b.productName || numericFields.some((key) => !Number.isFinite(Number(b[key])))) return res.status(400).json({ error: 'INVALID_CONTAINER_LOADING' });
  const row = store.add('container_loadings', {
    shift_id: shift.id,
    container_no: String(b.containerNo).trim(),
    product_name: String(b.productName).trim(),
    container_temp_before: Number(b.containerTempBefore),
    product_temp: Number(b.productTemp),
    container_temp_after: Number(b.containerTempAfter),
    cartons: Number(b.cartons),
    quantity: Number(b.quantity),
    loaded_at: b.loadedAt || new Date().toISOString(),
    notes: b.notes || null,
    created_by: req.user.sub,
  });
  store.audit(req.user.sub, 'CONTAINER_LOADING', row.id, 'CREATE', publicContainerLoading(row));
  res.status(201).json({ row: publicContainerLoading(row) });
});
app.get('/api/shifts/:id/quality/fridge-readings', auth, roles(...qualityRoles), (req, res) => { const readings = store.list('fridge_readings', req.params.id).filter((row) => (!req.query.date || row.reading_date === String(req.query.date)) && (!req.query.fridgeId || row.fridge_id === Number(req.query.fridgeId)) && (!req.query.status || row.status === String(req.query.status))).map((row) => ({ ...row, fridge: publicFridge(store.state.fridges.find((fridge) => fridge.id === row.fridge_id)), readingDate: row.reading_date, readingHour: row.reading_hour, temperature: row.temperature, status: Number(row.temperature) > -10 ? 'DEFROST' : 'NORMAL' })); const defrost = readings.filter((row) => row.status === 'DEFROST').length; const required = 40; res.json({ rows: readings, summary: { required, completed: readings.length, missing: Math.max(0, required - readings.length), compliance: Math.min(100, readings.length / required * 100), defrost } }); });
app.post('/api/shifts/:id/quality/fridge-readings', auth, roles('QUALITY', 'QUALITY_ENGINEER', 'SHIFT_MANAGER', 'SYSTEM_ADMIN'), (req, res) => { const b = req.body || {}; const fridge = store.state.fridges.find((item) => item.id === Number(b.fridgeId)); if (!fridge || !b.readingDate || !b.readingHour || typeof b.temperature !== 'number') return res.status(400).json({ error: 'INVALID_FRIDGE_READING' }); const isDefrost = b.temperature > -10; const status = isDefrost ? 'DEFROST' : 'NORMAL'; const row = store.add('fridge_readings', { shift_id: Number(req.params.id), fridge_id: fridge.id, reading_date: b.readingDate, reading_hour: b.readingHour, temperature: b.temperature, status, engineer_id: req.user.sub, notes: b.notes || null }); store.audit(req.user.sub, 'FRIDGE_READING', row.id, 'CREATE', { ...b, calculatedStatus: status, defrostRequired: isDefrost }); if (isDefrost && b.status !== 'DEFROST') store.add('notifications', { shift_id: Number(req.params.id), severity: 'WARNING', title: 'تسجيل حالة Defrost مطلوب', body: `${fridge.name} عند ${b.temperature}°C تحتاج تسجيل Defrost`, is_read: false }); const previous = store.list('fridge_readings', req.params.id).filter((item) => item.fridge_id === fridge.id && item.reading_date === b.readingDate && Number(item.temperature) > -10); if (previous.length >= 2) { store.add('notifications', { shift_id: Number(req.params.id), severity: previous.length >= 3 ? 'CRITICAL' : 'WARNING', title: 'تكرار Defrost', body: `${fridge.name} دخلت Defrost ${previous.length} مرات اليوم`, is_read: false }); store.audit(req.user.sub, 'FRIDGE', fridge.id, 'DEFROST_REPEAT', { date: b.readingDate, count: previous.length }); } res.status(201).json({ row: { ...row, status }, defrostRequired: isDefrost, repeatDefrost: previous.length >= 2, defrostCount: previous.length }); });
const receiptReport = (req, res) => { const rows = store.state.raw_receipts.filter((row) => (!req.query.from || row.receipt_date >= String(req.query.from)) && (!req.query.to || row.receipt_date <= String(req.query.to)) && (!req.query.supplier || row.supplier === String(req.query.supplier)) && (!req.query.material || row.material_name === String(req.query.material))); const summary = rows.reduce((result, row) => ({ count: result.count + 1, gross: result.gross + Number(row.gross_weight), discount: result.discount + Number(row.discount_amount), net: result.net + Number(row.net_weight), discountRate: result.discountRate + Number(row.discount_rate) }), { count: 0, gross: 0, discount: 0, net: 0, discountRate: 0 }); res.json({ rows: rows.map(publicReceipt), summary: { ...summary, averageDiscountRate: summary.count ? summary.discountRate / summary.count : 0, suppliers: new Set(rows.map((row) => row.supplier)).size } }); };
app.get('/api/receipts', auth, roles(...receiptReadRoles), receiptReport);
app.post('/api/receipts', auth, roles('WAREHOUSE', 'SHIFT_MANAGER', 'SYSTEM_ADMIN'), (req, res) => { const b = req.body || {}; const gross = Number(b.grossWeight); const rate = Number(b.discountRate || 0); if (!b.materialName || !b.supplier || !Number.isFinite(gross) || gross <= 0 || !Number.isFinite(rate) || rate < 0 || rate > 100) return res.status(400).json({ error: 'INVALID_RECEIPT' }); const discount = gross * rate / 100; const row = store.add('raw_receipts', { receipt_date: b.receiptDate || new Date().toISOString().slice(0, 10), receipt_time: b.receiptTime || new Date().toTimeString().slice(0, 5), material_name: b.materialName, supplier: b.supplier, supplier_code: b.supplierCode || null, gross_weight: gross, discount_rate: rate, discount_amount: discount, net_weight: gross - discount, defects: b.defects || '', notes: b.notes || '', created_by: req.user.sub }); store.audit(req.user.sub, 'RAW_RECEIPT', row.id, 'CREATE', publicReceipt(row)); res.status(201).json({ receipt: publicReceipt(row) }); });
app.get('/api/receipts/packaging', auth, roles(...receiptReadRoles), (req, res) => { const rows = store.state.packaging_receipts.filter((row) => (!req.query.from || row.receipt_date >= String(req.query.from)) && (!req.query.to || row.receipt_date <= String(req.query.to)) && (!req.query.supplier || row.supplier === String(req.query.supplier)) && (!req.query.item || row.item_name === String(req.query.item))); const summary = rows.reduce((result, row) => ({ count: result.count + 1, quantity: result.quantity + Number(row.quantity), suppliers: result.suppliers.add(row.supplier) }), { count: 0, quantity: 0, suppliers: new Set() }); res.json({ rows: rows.map(publicPackagingReceipt), summary: { count: summary.count, quantity: summary.quantity, suppliers: summary.suppliers.size } }); });
app.post('/api/receipts/packaging', auth, roles('WAREHOUSE', 'SHIFT_MANAGER', 'SYSTEM_ADMIN'), (req, res) => { const b = req.body || {}; const quantity = Number(b.quantity); if (!b.supplier || !b.itemName || !b.unit || !Number.isFinite(quantity) || quantity <= 0) return res.status(400).json({ error: 'INVALID_PACKAGING_RECEIPT' }); const row = store.add('packaging_receipts', { receipt_date: b.receiptDate || new Date().toISOString().slice(0, 10), receipt_time: b.receiptTime || new Date().toTimeString().slice(0, 5), supplier: b.supplier, item_name: b.itemName, item_code: b.itemCode || null, quantity, unit: b.unit, receipt_no: b.receiptNo || null, notes: b.notes || '', created_by: req.user.sub }); store.audit(req.user.sub, 'PACKAGING_RECEIPT', row.id, 'CREATE', publicPackagingReceipt(row)); res.status(201).json({ receipt: publicPackagingReceipt(row) }); });
app.get('/api/reports/receipts', auth, roles(...receiptReadRoles), receiptReport);
app.get('/api/shifts/:id/attendance', auth, roles(...attendanceRoles), (req, res) => res.json({ rows: store.list('attendance', req.params.id) }));
app.post('/api/shifts/:id/attendance', auth, roles('SHIFT_MANAGER', 'SECURITY', 'SYSTEM_ADMIN'), (req, res) => { const shift = editableShift(req, res, req.params.id); if (!shift) return; const b = req.body || {}; if (!b.department || !Number.isInteger(b.requiredCount) || !Number.isInteger(b.presentCount) || !Number.isInteger(b.absentCount) || b.requiredCount < 0 || b.presentCount < 0 || b.absentCount < 0) return res.status(400).json({ error: 'INVALID_ATTENDANCE_DATA' }); const row = store.add('attendance', { shift_id: shift.id, department: b.department, required_count: b.requiredCount, present_count: b.presentCount, absent_count: b.absentCount, late_count: b.lateCount || 0, overtime_count: b.overtimeCount || 0, notes: b.notes || null }); auditMutation(req, 'ATTENDANCE', row.id, 'CREATE', b); res.status(201).json({ row, attendanceRate: row.required_count ? row.present_count / row.required_count * 100 : 0, absenceRate: row.required_count ? row.absent_count / row.required_count * 100 : 0 }); });
app.get('/api/employees', auth, roles('SYSTEM_ADMIN', 'SHIFT_MANAGER', 'SECURITY', 'PRODUCTION_ENGINEER', 'QUALITY_ENGINEER'), (req, res) => {
  const includeInactive = String(req.query.includeInactive || '') === 'true' && ['SYSTEM_ADMIN', 'SHIFT_MANAGER', 'SECURITY'].includes(req.user.role);
  const rows = store.state.employees.filter((employee) => includeInactive || employee.is_active !== false);
  res.json({ rows: rows.map(publicEmployee) });
});
app.post('/api/employees', auth, roles('SYSTEM_ADMIN', 'SHIFT_MANAGER', 'SECURITY'), (req, res) => {
  const b = req.body || {};
  if (!b.employeeNo || !b.name || !b.department || !b.jobTitle || !b.category || !b.shiftName) return res.status(400).json({ error: 'INVALID_EMPLOYEE_DATA' });
  if (store.state.employees.some((employee) => employee.employee_no.toLowerCase() === String(b.employeeNo).trim().toLowerCase())) return res.status(409).json({ error: 'EMPLOYEE_NO_EXISTS' });
  const employee = store.add('employees', { employee_no: String(b.employeeNo).trim(), name: String(b.name).trim(), department: String(b.department).trim(), job_title: String(b.jobTitle).trim(), category: String(b.category).trim(), shift_name: String(b.shiftName).trim(), start_date: b.startDate || null, notes: b.notes || null, is_active: b.isActive === undefined ? true : Boolean(b.isActive) });
  store.audit(req.user.sub, 'EMPLOYEE', employee.id, 'CREATE', publicEmployee(employee));
  res.status(201).json({ employee: publicEmployee(employee) });
});
app.patch('/api/employees/:id', auth, roles('SYSTEM_ADMIN', 'SHIFT_MANAGER', 'SECURITY'), (req, res) => {
  const employee = store.employeeById(req.params.id);
  if (!employee) return res.status(404).json({ error: 'EMPLOYEE_NOT_FOUND' });
  const b = req.body || {};
  const oldData = publicEmployee({ ...employee });
  Object.assign(employee, {
    name: b.name ?? employee.name,
    department: b.department ?? employee.department,
    job_title: b.jobTitle ?? employee.job_title,
    category: b.category ?? employee.category,
    shift_name: b.shiftName ?? employee.shift_name,
    start_date: b.startDate ?? employee.start_date ?? null,
    notes: b.notes ?? employee.notes ?? null,
    is_active: b.isActive === undefined ? employee.is_active : Boolean(b.isActive),
  });
  store.persist();
  store.auditChange(req.user.sub, 'EMPLOYEE', employee.id, 'UPDATE', oldData, publicEmployee(employee));
  res.json({ employee: publicEmployee(employee) });
});
app.get('/api/shifts/:id/attendance/records', auth, roles(...attendanceRoles), (req, res) => {
  const shiftId = Number(req.params.id);
  const query = req.query || {};
  const rows = store.list('attendance_records', shiftId).filter((record) => {
    const employee = store.employeeById(record.employee_id);
    return (!query.date || record.attendance_date === String(query.date)) &&
      (!query.department || employee?.department === String(query.department)) &&
      (!query.jobTitle || employee?.job_title === String(query.jobTitle)) &&
      (!query.status || record.status === String(query.status));
  });
  res.json({ rows: rows.map(publicAttendance), summary: attendanceSummary(rows) });
});
app.post('/api/shifts/:id/attendance/records', auth, roles('SHIFT_MANAGER', 'SECURITY', 'SYSTEM_ADMIN'), (req, res) => {
  const shift = editableShift(req, res, req.params.id); if (!shift) return;
  const b = req.body || {};
  const employee = store.employeeById(b.employeeId);
  if (!employee || !b.attendanceDate || !attendanceStatuses.has(String(b.status))) return res.status(400).json({ error: 'INVALID_ATTENDANCE_RECORD' });
  const shiftId = Number(req.params.id);
  const duplicate = store.list('attendance_records', shiftId).find((record) => record.employee_id === Number(b.employeeId) && record.attendance_date === String(b.attendanceDate));
  if (duplicate) return res.status(409).json({ error: 'ATTENDANCE_RECORD_EXISTS' });
  const row = store.add('attendance_records', { shift_id: shiftId, employee_id: employee.id, attendance_date: String(b.attendanceDate), shift_name: b.shiftName || 'الثانية', status: String(b.status), check_in: b.checkIn || null, check_out: b.checkOut || null, notes: b.notes || null, updated_by: req.user.sub });
  store.audit(req.user.sub, 'ATTENDANCE_RECORD', row.id, 'CREATE', publicAttendance(row));
  res.status(201).json({ row: publicAttendance(row) });
});
app.patch('/api/shifts/:id/attendance/records/:recordId', auth, roles('SHIFT_MANAGER', 'SECURITY', 'SYSTEM_ADMIN'), (req, res) => {
  const shift = editableShift(req, res, req.params.id); if (!shift) return;
  const row = store.attendanceRecordById(req.params.recordId);
  if (!row || row.shift_id !== Number(req.params.id)) return res.status(404).json({ error: 'ATTENDANCE_RECORD_NOT_FOUND' });
  const b = req.body || {};
  const nextStatus = b.status === undefined ? row.status : String(b.status);
  if (!attendanceStatuses.has(nextStatus)) return res.status(400).json({ error: 'INVALID_ATTENDANCE_STATUS' });
  const oldData = publicAttendance({ ...row });
  Object.assign(row, { status: nextStatus, check_in: b.checkIn === undefined ? row.check_in : b.checkIn || null, check_out: b.checkOut === undefined ? row.check_out : b.checkOut || null, notes: b.notes === undefined ? row.notes : b.notes || null, updated_by: req.user.sub, updated_at: new Date().toISOString() });
  store.persist();
  store.auditChange(req.user.sub, 'ATTENDANCE_RECORD', row.id, 'UPDATE', oldData, publicAttendance(row));
  res.json({ row: publicAttendance(row) });
});
const readModuleRoles = { quality: qualityRoles, supplies: ['SYSTEM_ADMIN', 'SHIFT_MANAGER', 'WAREHOUSE', 'PRODUCTION_ENGINEER'], downtime: productionRoles, maintenance: ['SYSTEM_ADMIN', 'SHIFT_MANAGER', 'MAINTENANCE', 'PRODUCTION', 'PRODUCTION_ENGINEER'], inventory: ['SYSTEM_ADMIN', 'SHIFT_MANAGER', 'WAREHOUSE'] };
for (const [name, pathName] of [['quality', 'quality'], ['supplies', 'supplies'], ['downtime', 'downtime'], ['maintenance', 'maintenance'], ['inventory', 'inventory']]) app.get(`/api/shifts/:id/${pathName}`, auth, roles(...readModuleRoles[name]), (req, res) => res.json({ rows: store.list(name, req.params.id) }));
app.post('/api/shifts/:id/supplies', auth, roles('SYSTEM_ADMIN', 'SHIFT_MANAGER', 'WAREHOUSE', 'PRODUCTION_ENGINEER'), (req, res) => { const b = req.body || {}; const quantity = Number(b.quantity); if (!b.supplier || !b.materialName || !b.unit || !Number.isFinite(quantity) || quantity <= 0) return res.status(400).json({ error: 'INVALID_SUPPLY' }); const row = store.add('supplies', { shift_id: Number(req.params.id), supplier: b.supplier, material_name: b.materialName, quantity, unit: b.unit, batch_no: b.batchNo || null, status: b.status || 'PENDING', notes: b.notes || null }); store.audit(req.user.sub, 'SUPPLY', row.id, 'CREATE', row); res.status(201).json({ row }); });
app.post('/api/shifts/:id/downtime', auth, roles(...productionRoles), (req, res) => { const b = req.body || {}; const minutes = Number(b.minutes); if (!b.lineCode || !b.machineName || !b.reasonType || !Number.isInteger(minutes) || minutes <= 0) return res.status(400).json({ error: 'INVALID_DOWNTIME' }); const row = store.add('downtime', { shift_id: Number(req.params.id), line_code: b.lineCode, machine_name: b.machineName, minutes, reason_type: b.reasonType, status: b.status || 'OPEN', action_taken: b.actionTaken || null }); store.audit(req.user.sub, 'DOWNTIME', row.id, 'CREATE', row); if (minutes > 15) store.add('notifications', { shift_id: Number(req.params.id), severity: 'WARNING', title: 'توقف خط الإنتاج لمدة طويلة', body: `${b.lineCode} · ${minutes} دقيقة`, is_read: false }); res.status(201).json({ row }); });
app.post('/api/shifts/:id/maintenance', auth, roles('SYSTEM_ADMIN', 'SHIFT_MANAGER', 'MAINTENANCE', 'PRODUCTION', 'PRODUCTION_ENGINEER'), (req, res) => { const b = req.body || {}; if (!b.ticketNo || !b.lineCode || !b.machineName || !b.description) return res.status(400).json({ error: 'INVALID_MAINTENANCE' }); const row = store.add('maintenance', { shift_id: Number(req.params.id), ticket_no: b.ticketNo, line_code: b.lineCode, machine_name: b.machineName, severity: b.severity || 'MEDIUM', description: b.description, status: b.status || 'OPEN', action_taken: b.actionTaken || null }); store.audit(req.user.sub, 'MAINTENANCE', row.id, 'CREATE', row); res.status(201).json({ row }); });
app.post('/api/shifts/:id/inventory', auth, roles('SYSTEM_ADMIN', 'SHIFT_MANAGER', 'WAREHOUSE'), (req, res) => { const b = req.body || {}; const quantity = Number(b.quantity); if (!b.materialName || !['RECEIPT', 'ISSUE', 'RETURN'].includes(String(b.transactionType)) || !Number.isFinite(quantity) || quantity <= 0) return res.status(400).json({ error: 'INVALID_INVENTORY' }); const row = store.add('inventory', { shift_id: Number(req.params.id), material_name: b.materialName, transaction_type: b.transactionType, quantity, unit: b.unit || 'kg', reference_no: b.referenceNo || null, notes: b.notes || null, created_by: req.user.sub }); store.audit(req.user.sub, 'INVENTORY', row.id, 'CREATE', row); res.status(201).json({ row }); });
app.get('/api/shifts/:id/notifications', auth, (req, res) => { let rows = store.list('notifications', req.params.id); if (req.user.role === 'SECURITY') rows = rows.filter((item) => String(item.title).includes('حضور') || String(item.title).includes('غياب')); if (['QUALITY', 'QUALITY_ENGINEER'].includes(req.user.role)) rows = rows.filter((item) => String(item.title).includes('جودة') || String(item.title).includes('Defrost') || String(item.title).includes('ثلاجة')); res.json({ rows }); });
app.get('/api/shifts/:id/audit-log', auth, roles('SYSTEM_ADMIN', 'SHIFT_MANAGER', 'PRODUCTION_ENGINEER', 'QUALITY_ENGINEER'), (_req, res) => res.json({ rows: store.state.audit }));
app.patch('/api/notifications/:id/read', auth, (req, res) => { const row = store.state.notifications.find((item) => item.id === Number(req.params.id)); if (row) { row.is_read = true; store.persist(); } res.json({ ok: true }); });
app.use((error, _req, res, _next) => { console.error(error); res.status(500).json({ error: 'INTERNAL_SERVER_ERROR' }); });
app.listen(port, '0.0.0.0', () => console.log(`Wardia API listening on http://0.0.0.0:${port}`));
