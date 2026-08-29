const fs = require('node:fs');
const path = require('node:path');
const bcrypt = require('bcryptjs');

const file = process.env.DB_FILE
  ? path.resolve(__dirname, '..', process.env.DB_FILE)
  : path.resolve(__dirname, '..', 'data', 'wardia.json');
fs.mkdirSync(path.dirname(file), { recursive: true });

const createSeed = () => ({
  roles: [
    ['SYSTEM_ADMIN', 'System Admin'], ['SHIFT_MANAGER', 'Shift Manager'],
    ['SECURITY', 'Security'], ['QUALITY', 'Quality'], ['QUALITY_ENGINEER', 'Quality Engineer'], ['PRODUCTION', 'Production'], ['PRODUCTION_ENGINEER', 'Production Engineer'],
    ['MAINTENANCE', 'Maintenance'], ['WAREHOUSE', 'Warehouse'],
  ].map(([code, name], index) => ({ id: index + 1, code, name })),
  users: [{ id: 1, name: 'محمد حمدي', email: 'manager@wardia.app', password_hash: bcrypt.hashSync('123456', 10), role_code: 'SHIFT_MANAGER', department: 'إدارة الوردية', is_active: true }],
  shifts: [{ id: 1, shift_no: 'SHIFT-2026-08-21-02', shift_date: '2026-08-21', starts_at: '16:00', ends_at: '00:00', status: 'RUNNING', manager_id: 1, opened_at: new Date().toISOString() }],
  attendance: [{ id: 1, shift_id: 1, department: 'الإنتاج', required_count: 5, present_count: 4, absent_count: 1, late_count: 1, overtime_count: 2 }],
  employees: [
    { id: 1, employee_no: 'EMP-001', name: 'أحمد سالم', department: 'الإنتاج', job_title: 'مشغل ماكينة', category: 'عمال', shift_name: 'الثانية', start_date: null, notes: null, is_active: true },
    { id: 2, employee_no: 'EMP-002', name: 'منى عادل', department: 'الجودة', job_title: 'مراقبة جودة', category: 'مهندسين', shift_name: 'الثانية', start_date: null, notes: null, is_active: true },
    { id: 3, employee_no: 'EMP-003', name: 'كريم فتحي', department: 'المخازن', job_title: 'أمين مخزن', category: 'عمال', shift_name: 'الثانية', start_date: null, notes: null, is_active: true },
    { id: 4, employee_no: 'EMP-004', name: 'سارة يوسف', department: 'التغليف', job_title: 'عامل تعبئة', category: 'عمال', shift_name: 'الثانية', start_date: null, notes: null, is_active: true },
    { id: 5, employee_no: 'EMP-005', name: 'محمد حمدي', department: 'الإنتاج', job_title: 'مشرف وردية', category: 'مشرفين', shift_name: 'الثانية', start_date: null, notes: null, is_active: true },
  ],
  attendance_records: [
    { id: 1, shift_id: 1, employee_id: 1, attendance_date: '2026-08-21', shift_name: 'الثانية', status: 'PRESENT', check_in: '15:52', check_out: null, notes: null, updated_by: 1 },
    { id: 2, shift_id: 1, employee_id: 2, attendance_date: '2026-08-21', shift_name: 'الثانية', status: 'PRESENT', check_in: '15:58', check_out: null, notes: null, updated_by: 1 },
    { id: 3, shift_id: 1, employee_id: 3, attendance_date: '2026-08-21', shift_name: 'الثانية', status: 'LATE', check_in: '16:18', check_out: null, notes: 'حضر بعد بداية الوردية', updated_by: 1 },
    { id: 4, shift_id: 1, employee_id: 4, attendance_date: '2026-08-21', shift_name: 'الثانية', status: 'ABSENT_UNEXCUSED', check_in: null, check_out: null, notes: null, updated_by: 1 },
    { id: 5, shift_id: 1, employee_id: 5, attendance_date: '2026-08-21', shift_name: 'الثانية', status: 'PRESENT', check_in: '15:45', check_out: null, notes: null, updated_by: 1 },
  ],
  product_guides: [
    { id: 1, product_code: 'FR-001', name: 'فراولة مجمدة', department: 'IQF', raw_material: 'فراولة طازجة', pack_weight: 1, pack_size: '1 كجم', size: 'متوسط', temperature: null, line_speed: null, machine_settings: '', operating_time: '', instructions: '', steps: ['تجهيز المادة الخام', 'فحص الجودة الأولي', 'ضبط نفق التجميد', 'بدء الإنتاج'], image_url: null, is_active: true },
    { id: 2, product_code: 'VG-001', name: 'خضروات مشكلة', department: 'PACKING', raw_material: 'خضروات مشكلة', pack_weight: 0.5, pack_size: '500 جم', size: 'متوسط', temperature: null, line_speed: null, machine_settings: '', operating_time: '', instructions: '', steps: ['تجهيز الخامات', 'ضبط ماكينة التعبئة', 'ضبط وزن العبوة', 'بدء الإنتاج'], image_url: null, is_active: true },
  ],
  fridges: [
    { id: 1, fridge_no: 'FR-01', name: 'ثلاجة المواد الخام', min_temp: null, max_temp: null, is_active: true },
    { id: 2, fridge_no: 'FR-02', name: 'ثلاجة المنتج النهائي', min_temp: null, max_temp: null, is_active: true },
    { id: 3, fridge_no: 'FR-03', name: 'نفق التجميد', min_temp: null, max_temp: null, is_active: true },
    { id: 4, fridge_no: 'FR-04', name: 'ثلاجة التشغيل 04', min_temp: null, max_temp: null, is_active: true },
    { id: 5, fridge_no: 'FR-05', name: 'ثلاجة التشغيل 05', min_temp: null, max_temp: null, is_active: true },
  ],
  fridge_readings: [
    { id: 1, shift_id: 1, fridge_id: 1, reading_date: '2026-08-21', reading_hour: '20:00', temperature: -8, status: 'NORMAL', engineer_id: 1, notes: null },
    { id: 2, shift_id: 1, fridge_id: 2, reading_date: '2026-08-21', reading_hour: '20:00', temperature: -12, status: 'DEFROST', engineer_id: 1, notes: 'تم تسجيل الديفروست' },
  ],
  raw_receipts: [
    { id: 1, receipt_date: '2026-08-20', receipt_time: '09:20', material_name: 'فراولة', supplier: 'مورد تجريبي', supplier_code: 'SUP-001', gross_weight: 1000, discount_rate: 5, discount_amount: 50, net_weight: 950, defects: 'لا يوجد', notes: '', created_by: 1 },
  ],
  packaging_receipts: [],
  production: [[16, '16:00', 850, 820], [17, '17:00', 850, 910], [18, '18:00', 850, 790], [19, '19:00', 850, 860], [20, '20:00', 850, 730]].map(([id, hour, target_qty, actual_qty]) => ({ id, shift_id: 1, department: 'PACKING', line_code: 'LINE-01', machine_name: 'ماكينة التعبئة', product_name: 'خضروات مشكلة', workers_count: 5, hour_started_at: hour, target_qty, actual_qty, waste_qty: 0, rejected_qty: 0, downtime_minutes: 0 })),
  quality: [{ id: 1, shift_id: 1, product_name: 'خضروات مشكلة', line_code: 'LINE-01', inspected_qty: 5700, accepted_qty: 5540, rejected_qty: 160, result: 'PASS', inspected_at: new Date().toISOString() }], supplies: [],
  downtime: [{ id: 1, shift_id: 1, line_code: 'LINE-01', machine_name: 'ماكينة التعبئة', minutes: 18, reason_type: 'BREAKDOWN', status: 'OPEN' }],
  maintenance: [{ id: 1, shift_id: 1, ticket_no: 'MT-204', line_code: 'LINE-01', machine_name: 'ماكينة التعبئة', severity: 'CRITICAL', description: 'توقف حساس التغذية', status: 'IN_PROGRESS' }, { id: 2, shift_id: 1, ticket_no: 'MT-205', line_code: 'LINE-01', machine_name: 'نفق التجميد', severity: 'MEDIUM', description: 'ارتفاع حرارة مؤقت', status: 'OPEN' }],
  inventory: [{ id: 1, shift_id: 1, material_name: 'فراولة مجمدة', transaction_type: 'ISSUE', quantity: 420, unit: 'kg' }, { id: 2, shift_id: 1, material_name: 'خضروات مشكلة', transaction_type: 'RECEIPT', quantity: 900, unit: 'kg' }],
  notifications: [{ id: 1, shift_id: 1, severity: 'WARNING', title: 'الإنتاج أقل من المستهدف', body: 'ساعة 20:00 أقل من 90%', is_read: false }, { id: 2, shift_id: 1, severity: 'WARNING', title: 'توقف خط الإنتاج لمدة طويلة', body: 'خط 01 · 18 دقيقة', is_read: false }, { id: 3, shift_id: 1, severity: 'CRITICAL', title: 'عطل يحتاج تدخل الصيانة', body: 'ماكينة التعبئة · مفتوح', is_read: false }],
  problems: [],
  container_loadings: [],
  audit: [],
  counters: { attendance: 1, attendance_record: 5, employee: 5, production: 20, product_guide: 2, fridge: 5, fridge_reading: 2, raw_receipt: 1, packaging_receipt: 0, quality: 1, supplies: 0, downtime: 1, maintenance: 2, inventory: 2, notification: 3, audit: 0, problem: 0, container_loading: 0, shift: 1 },
});

let state;
try { state = JSON.parse(fs.readFileSync(file, 'utf8')); } catch { state = createSeed(); persist(); }
let migrated = false;
if (!Array.isArray(state.employees)) { state.employees = createSeed().employees; migrated = true; }
if (!Array.isArray(state.attendance_records)) { state.attendance_records = createSeed().attendance_records; migrated = true; }
state.counters = state.counters || {};
for (const role of createSeed().roles) {
  if (!state.roles.some((existing) => existing.code === role.code)) {
    const nextRoleId = Math.max(0, ...state.roles.map((item) => Number(item.id) || 0)) + 1;
    state.roles.push({ ...role, id: nextRoleId });
    migrated = true;
  }
}
for (const [name, key] of [['product_guides', 'product_guide'], ['fridges', 'fridge'], ['fridge_readings', 'fridge_reading'], ['raw_receipts', 'raw_receipt'], ['packaging_receipts', 'packaging_receipt']]) {
  if (!Array.isArray(state[name])) { state[name] = createSeed()[name]; migrated = true; }
  const maximum = Math.max(0, ...state[name].map((row) => Number(row.id) || 0));
  if (!state.counters[key] || state.counters[key] < maximum) { state.counters[key] = maximum; migrated = true; }
}
if (!Array.isArray(state.problems)) { state.problems = []; migrated = true; }
const problemMaximum = Math.max(0, ...state.problems.map((row) => Number(row.id) || 0));
if (!state.counters.problem || state.counters.problem < problemMaximum) { state.counters.problem = problemMaximum; migrated = true; }
if (!Array.isArray(state.container_loadings)) { state.container_loadings = []; migrated = true; }
const containerLoadingMaximum = Math.max(0, ...state.container_loadings.map((row) => Number(row.id) || 0));
if (!state.counters.container_loading || state.counters.container_loading < containerLoadingMaximum) { state.counters.container_loading = containerLoadingMaximum; migrated = true; }
const shiftMaximum = Math.max(0, ...state.shifts.map((row) => Number(row.id) || 0));
if (!state.counters.shift || state.counters.shift < shiftMaximum) { state.counters.shift = shiftMaximum; migrated = true; }
const missingFridges = [
  { fridge_no: 'FR-04', name: 'ثلاجة التشغيل 04' },
  { fridge_no: 'FR-05', name: 'ثلاجة التشغيل 05' },
];
for (const fridge of missingFridges) {
  if (state.fridges.some((existing) => existing.fridge_no === fridge.fridge_no)) continue;
  state.fridges.push({ id: Math.max(0, ...state.fridges.map((item) => Number(item.id) || 0)) + 1, ...fridge, min_temp: null, max_temp: null, is_active: true });
  state.counters.fridge = Math.max(state.counters.fridge || 0, state.fridges[state.fridges.length - 1].id);
  migrated = true;
}
for (const employee of state.employees) {
  if (!Object.prototype.hasOwnProperty.call(employee, 'start_date')) { employee.start_date = null; migrated = true; }
  if (!Object.prototype.hasOwnProperty.call(employee, 'notes')) { employee.notes = null; migrated = true; }
}
for (const [key, collection] of [['employee', 'employees'], ['attendance_record', 'attendance_records']]) {
  const maximum = Math.max(0, ...state[collection].map((row) => Number(row.id) || 0));
  if (!state.counters[key] || state.counters[key] < maximum) { state.counters[key] = maximum; migrated = true; }
}
if (Array.isArray(state.fridge_readings)) {
  const usedIds = new Set();
  let nextReadingId = Math.max(0, ...state.fridge_readings.map((row) => Number(row.id) || 0));
  for (const reading of state.fridge_readings) {
    if (usedIds.has(Number(reading.id))) { reading.id = ++nextReadingId; migrated = true; }
    usedIds.add(Number(reading.id));
    const calculatedStatus = Number(reading.temperature) > -10 ? 'DEFROST' : 'NORMAL';
    if (reading.status !== calculatedStatus) { reading.status = calculatedStatus; migrated = true; }
  }
  if (state.counters.fridge_reading < nextReadingId) { state.counters.fridge_reading = nextReadingId; migrated = true; }
}
if (!state.production.some((row) => row.department === 'IQF')) {
  const startId = Math.max(0, ...state.production.map((row) => Number(row.id) || 0));
  state.production.push(
    { id: startId + 1, shift_id: 1, department: 'IQF', line_code: 'IQF-01', machine_name: 'نفق التجميد', product_name: 'فراولة مجمدة', workers_count: 5, hour_started_at: '18:00', target_qty: 700, actual_qty: 680, waste_qty: 0, rejected_qty: 0, downtime_minutes: 0 },
    { id: startId + 2, shift_id: 1, department: 'IQF', line_code: 'IQF-01', machine_name: 'نفق التجميد', product_name: 'فراولة مجمدة', workers_count: 5, hour_started_at: '19:00', target_qty: 700, actual_qty: 715, waste_qty: 0, rejected_qty: 0, downtime_minutes: 0 },
  );
  state.counters.production = startId + 2;
  migrated = true;
}
if (migrated) persist();
if (!state.users.some((user) => user.email.toLowerCase() === 'admin@wardia.app')) {
  state.users.push({ id: 2, name: 'مدير النظام', email: 'admin@wardia.app', password_hash: bcrypt.hashSync('Admin@123456', 10), role_code: 'SYSTEM_ADMIN', department: 'إدارة النظام', is_active: true });
  persist();
}
const demoUsers = [
  { name: 'مدير الوردية التجريبي', email: 'shift.manager@wardia.app', password: 'Shift@123456', role_code: 'SHIFT_MANAGER', department: 'إدارة الوردية' },
  { name: 'مهندس الإنتاج التجريبي', email: 'production.engineer@wardia.app', password: 'Production@123456', role_code: 'PRODUCTION_ENGINEER', department: 'الإنتاج' },
  { name: 'مهندس الجودة التجريبي', email: 'quality.engineer@wardia.app', password: 'Quality@123456', role_code: 'QUALITY_ENGINEER', department: 'الجودة' },
  { name: 'فرد الأمن التجريبي', email: 'security@wardia.app', password: 'Security@123456', role_code: 'SECURITY', department: 'الأمن' },
];
let demoUsersChanged = false;
for (const demo of demoUsers) {
  if (state.users.some((user) => user.email.toLowerCase() === demo.email)) continue;
  state.users.push({ id: Math.max(0, ...state.users.map((user) => Number(user.id) || 0)) + 1, name: demo.name, email: demo.email, password_hash: bcrypt.hashSync(demo.password, 10), role_code: demo.role_code, department: demo.department, is_active: true });
  demoUsersChanged = true;
}
if (demoUsersChanged) persist();
function persist() { fs.writeFileSync(file, JSON.stringify(state, null, 2), 'utf8'); }
function next(collection) { state.counters[collection] = (state.counters[collection] || 0) + 1; return state.counters[collection]; }
function userByEmail(email) { return state.users.find((u) => u.email.toLowerCase() === email.toLowerCase() && u.is_active); }
function userById(id) { return state.users.find((u) => u.id === Number(id)); }
function shiftById(id) { return state.shifts.find((s) => s.id === Number(id)); }
function currentShift() { return [...state.shifts].reverse().find((s) => s.status === 'RUNNING'); }
function isShiftClosed(shiftOrId) { const shift = typeof shiftOrId === 'object' ? shiftOrId : shiftById(shiftOrId); return !shift || ['COMPLETED', 'APPROVED', 'CLOSED'].includes(shift.status); }
function openShiftById(id) { const shift = shiftById(id); return shift && !isShiftClosed(shift) ? shift : null; }
function list(name, shiftId) { return state[name].filter((row) => row.shift_id === Number(shiftId)); }
function add(name, row) { const record = { id: next(name), ...row, created_at: new Date().toISOString() }; state[name].push(record); persist(); return record; }
function auditChange(userId, entityType, entityId, action, oldData, newData) { state.audit.unshift({ id: next('audit'), user_id: userId, entity_type: entityType, entity_id: entityId, action, old_data_json: oldData, new_data_json: newData, created_at: new Date().toISOString() }); persist(); }
function audit(userId, entityType, entityId, action, newData) { auditChange(userId, entityType, entityId, action, null, newData); }
function dashboard(shiftId) {
  const attendance = list('attendance', shiftId).reduce((a, r) => ({ required: a.required + r.required_count, present: a.present + r.present_count, absent: a.absent + r.absent_count, late: a.late + r.late_count }), { required: 0, present: 0, absent: 0, late: 0 });
  const production = list('production', shiftId).reduce((a, r) => ({ target: a.target + r.target_qty, actual: a.actual + r.actual_qty, waste: a.waste + r.waste_qty, rejected: a.rejected + r.rejected_qty, downtime: a.downtime + r.downtime_minutes }), { target: 0, actual: 0, waste: 0, rejected: 0, downtime: 0 });
  const quality = list('quality', shiftId).reduce((a, r) => ({ inspected: a.inspected + r.inspected_qty, accepted: a.accepted + r.accepted_qty, rejected: a.rejected + r.rejected_qty }), { inspected: 0, accepted: 0, rejected: 0 });
  const downtimeRows = list('downtime', shiftId); const maintenanceRows = list('maintenance', shiftId); const inventoryRows = list('inventory', shiftId);
  const fridgeRows = list('fridge_readings', shiftId);
  const problemRows = list('problems', shiftId);
  const notificationRows = list('notifications', shiftId).filter((n) => !n.is_read);
  return {
    attendance,
    production,
    quality,
    downtime: {
      count: downtimeRows.length,
      minutes: downtimeRows.reduce((a, r) => a + r.minutes, 0),
      open_count: downtimeRows.filter((r) => r.status !== 'CLOSED').length
    },
    maintenance: {
      count: maintenanceRows.length,
      open_count: maintenanceRows.filter((r) => !['CLOSED', 'RESOLVED'].includes(r.status)).length
    },
    inventory: {
      received: inventoryRows.filter((r) => r.transaction_type === 'RECEIPT').reduce((a, r) => a + r.quantity, 0),
      issued: inventoryRows.filter((r) => r.transaction_type === 'ISSUE').reduce((a, r) => a + r.quantity, 0),
      returned: inventoryRows.filter((r) => r.transaction_type === 'RETURN').reduce((a, r) => a + r.quantity, 0)
    },
    fridges: {
      required: 40,
      completed: fridgeRows.length,
      missing: Math.max(0, 40 - fridgeRows.length),
      defrost: fridgeRows.filter((r) => Number(r.temperature) > -10).length
    },
    problems: {
      count: problemRows.length,
      open_count: problemRows.filter((r) => !['RESOLVED', 'CLOSED'].includes(r.status)).length
    },
    containers: {
      count: list('container_loadings', shiftId).length
    },
    notifications: notificationRows
  };
}
function report(shiftId) {
  const shift = shiftById(shiftId);
  const totals = dashboard(shiftId);
  const productionRows = list('production', shiftId);
  const supplies = list('supplies', shiftId);
  const inventory = totals.inventory;
  const attendanceRecords = list('attendance_records', shiftId);
  const downtimeRows = list('downtime', shiftId);
  const maintenanceRows = list('maintenance', shiftId);
  const fridgeRows = list('fridge_readings', shiftId);
  const containerRows = list('container_loadings', shiftId);
  const productionByDepartment = productionRows.reduce((result, row) => { const key = row.department || 'PACKING'; result[key] = (result[key] || 0) + Number(row.actual_qty || 0); return result; }, {});
  const productionByProduct = productionRows.reduce((result, row) => { const key = row.product_name || 'غير محدد'; result[key] = (result[key] || 0) + Number(row.actual_qty || 0); return result; }, {});
  const manager = userById(shift?.manager_id);
  const start = shift?.opened_at || `${shift?.shift_date || ''}T${shift?.starts_at || '00:00'}:00`;
  const end = shift?.closed_at || `${shift?.shift_date || ''}T${shift?.ends_at || '00:00'}:00`;
  const durationMinutes = Date.parse(end) >= Date.parse(start) ? Math.round((Date.parse(end) - Date.parse(start)) / 60000) : null;
  return {
    shift: { ...shift, manager_name: manager?.name || null, duration_minutes: durationMinutes },
    generated_at: new Date().toISOString(),
    attendance_rate: totals.attendance.required ? totals.attendance.present / totals.attendance.required * 100 : 0,
    absence_rate: totals.attendance.required ? totals.attendance.absent / totals.attendance.required * 100 : 0,
    achievement: totals.production.target ? totals.production.actual / totals.production.target * 100 : 0,
    rejection_rate: totals.quality.inspected ? totals.quality.rejected / totals.quality.inspected * 100 : 0,
    supply_total: supplies.reduce((sum, row) => sum + row.quantity, 0),
    inventory_balance: 5840 + inventory.received - inventory.issued + inventory.returned,
    attendance_records: attendanceRecords.map((row) => ({ ...row, employee: employeeById(row.employee_id) || null })),
    production_by_department: productionByDepartment,
    production_by_product: productionByProduct,
    downtime_rows: downtimeRows,
    maintenance_rows: maintenanceRows,
    fridge: { required: 40, completed: fridgeRows.length, missing: Math.max(0, 40 - fridgeRows.length), normal: fridgeRows.filter((row) => Number(row.temperature) <= -10).length, defrost: fridgeRows.filter((row) => Number(row.temperature) > -10).length, rows: fridgeRows },
    alerts: list('notifications', shiftId).filter((row) => !row.is_read),
    raw_receipts: state.raw_receipts.filter((row) => row.shift_id === Number(shiftId) || (!row.shift_id && row.receipt_date === shift?.shift_date)),
    packaging_receipts: state.packaging_receipts.filter((row) => row.shift_id === Number(shiftId) || (!row.shift_id && row.receipt_date === shift?.shift_date)),
    container_loadings: containerRows,
    ...totals,
    production_rows: productionRows.map((row) => ({ ...row, achievement: row.target_qty ? row.actual_qty / row.target_qty * 100 : 0 })),
  };
}
function updateShift(id, patch) { const shift = shiftById(id); if (!shift) return null; Object.assign(shift, patch); persist(); return shift; }
function employeeById(id) { return state.employees.find((employee) => employee.id === Number(id)); }
function attendanceRecordById(id) { return state.attendance_records.find((record) => record.id === Number(id)); }
module.exports = { state, persist, next, userByEmail, userById, shiftById, currentShift, openShiftById, isShiftClosed, list, add, audit, auditChange, employeeById, attendanceRecordById, dashboard, report, updateShift };
