CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;
CREATE TABLE IF NOT EXISTS roles (id BIGSERIAL PRIMARY KEY, code TEXT NOT NULL UNIQUE, name TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS users (id BIGSERIAL PRIMARY KEY, name TEXT NOT NULL, email CITEXT NOT NULL UNIQUE, password_hash TEXT NOT NULL, role_code TEXT NOT NULL REFERENCES roles(code), department TEXT, is_active BOOLEAN NOT NULL DEFAULT TRUE, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS shifts (id BIGSERIAL PRIMARY KEY, shift_no TEXT NOT NULL UNIQUE, shift_date DATE NOT NULL, starts_at TEXT NOT NULL, ends_at TEXT NOT NULL, status TEXT NOT NULL CHECK(status IN ('NOT_STARTED','RUNNING','PAUSED','COMPLETED','CLOSED','APPROVED')), manager_id BIGINT REFERENCES users(id), opened_at TIMESTAMPTZ, closed_at TIMESTAMPTZ, approved_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
ALTER TABLE shifts DROP CONSTRAINT IF EXISTS shifts_status_check;
ALTER TABLE shifts ADD CONSTRAINT shifts_status_check CHECK(status IN ('NOT_STARTED','RUNNING','PAUSED','COMPLETED','CLOSED','APPROVED'));
CREATE TABLE IF NOT EXISTS attendance (id BIGSERIAL PRIMARY KEY, shift_id BIGINT NOT NULL REFERENCES shifts(id), department TEXT NOT NULL, required_count INTEGER NOT NULL CHECK(required_count >= 0), present_count INTEGER NOT NULL CHECK(present_count >= 0), absent_count INTEGER NOT NULL CHECK(absent_count >= 0), late_count INTEGER NOT NULL CHECK(late_count >= 0), overtime_count INTEGER NOT NULL DEFAULT 0 CHECK(overtime_count >= 0), notes TEXT, approved_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS employees (id BIGSERIAL PRIMARY KEY, employee_no TEXT NOT NULL UNIQUE, name TEXT NOT NULL, department TEXT NOT NULL, job_title TEXT NOT NULL, category TEXT NOT NULL, shift_name TEXT NOT NULL, start_date DATE, notes TEXT, is_active BOOLEAN NOT NULL DEFAULT TRUE, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
ALTER TABLE employees ADD COLUMN IF NOT EXISTS start_date DATE;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS notes TEXT;
CREATE TABLE IF NOT EXISTS attendance_records (id BIGSERIAL PRIMARY KEY, shift_id BIGINT NOT NULL REFERENCES shifts(id), employee_id BIGINT NOT NULL REFERENCES employees(id), attendance_date DATE NOT NULL, shift_name TEXT NOT NULL, status TEXT NOT NULL CHECK(status IN ('PRESENT','LATE','MISSION','LEAVE','ABSENT_EXCUSED','ABSENT_UNEXCUSED')), check_in TEXT, check_out TEXT, notes TEXT, updated_by BIGINT REFERENCES users(id), created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ, UNIQUE(shift_id, employee_id, attendance_date));
CREATE TABLE IF NOT EXISTS product_guides (id BIGSERIAL PRIMARY KEY, product_code TEXT NOT NULL UNIQUE, name TEXT NOT NULL, department TEXT NOT NULL CHECK(department IN ('PACKING','IQF')), raw_material TEXT, pack_weight NUMERIC, pack_size TEXT, size TEXT, temperature TEXT, line_speed TEXT, machine_settings TEXT, operating_time TEXT, instructions TEXT, steps_json JSONB NOT NULL DEFAULT '[]', image_url TEXT, is_active BOOLEAN NOT NULL DEFAULT TRUE, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ);
CREATE TABLE IF NOT EXISTS fridges (id BIGSERIAL PRIMARY KEY, fridge_no TEXT NOT NULL UNIQUE, name TEXT NOT NULL, min_temp NUMERIC, max_temp NUMERIC, is_active BOOLEAN NOT NULL DEFAULT TRUE, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS fridge_readings (id BIGSERIAL PRIMARY KEY, shift_id BIGINT NOT NULL REFERENCES shifts(id), fridge_id BIGINT NOT NULL REFERENCES fridges(id), reading_date DATE NOT NULL, reading_hour TEXT NOT NULL, temperature NUMERIC NOT NULL, status TEXT NOT NULL CHECK(status IN ('NORMAL','DEFROST')), engineer_id BIGINT REFERENCES users(id), notes TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS raw_receipts (id BIGSERIAL PRIMARY KEY, receipt_date DATE NOT NULL, receipt_time TEXT NOT NULL, material_name TEXT NOT NULL, supplier TEXT NOT NULL, supplier_code TEXT, gross_weight NUMERIC NOT NULL CHECK(gross_weight > 0), discount_rate NUMERIC NOT NULL DEFAULT 0 CHECK(discount_rate >= 0 AND discount_rate <= 100), discount_amount NUMERIC NOT NULL, net_weight NUMERIC NOT NULL, defects TEXT, notes TEXT, created_by BIGINT REFERENCES users(id), created_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS packaging_receipts (id BIGSERIAL PRIMARY KEY, receipt_date DATE NOT NULL, receipt_time TEXT NOT NULL, supplier TEXT NOT NULL, item_name TEXT NOT NULL, item_code TEXT, quantity NUMERIC NOT NULL CHECK(quantity > 0), unit TEXT NOT NULL, receipt_no TEXT, notes TEXT, created_by BIGINT REFERENCES users(id), created_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS production_hourly (id BIGSERIAL PRIMARY KEY, shift_id BIGINT NOT NULL REFERENCES shifts(id), line_code TEXT NOT NULL, product_name TEXT NOT NULL, hour_started_at TEXT NOT NULL, target_qty INTEGER NOT NULL CHECK(target_qty > 0), actual_qty INTEGER NOT NULL CHECK(actual_qty >= 0), waste_qty INTEGER NOT NULL DEFAULT 0 CHECK(waste_qty >= 0), rejected_qty INTEGER NOT NULL DEFAULT 0 CHECK(rejected_qty >= 0), downtime_minutes INTEGER NOT NULL DEFAULT 0 CHECK(downtime_minutes >= 0), notes TEXT, approved_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
ALTER TABLE production_hourly ADD COLUMN IF NOT EXISTS department TEXT NOT NULL DEFAULT 'PACKING';
ALTER TABLE production_hourly ADD COLUMN IF NOT EXISTS machine_name TEXT;
ALTER TABLE production_hourly ADD COLUMN IF NOT EXISTS workers_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE production_hourly ADD COLUMN IF NOT EXISTS downtime_reason TEXT;
CREATE TABLE IF NOT EXISTS quality_checks (id BIGSERIAL PRIMARY KEY, shift_id BIGINT NOT NULL REFERENCES shifts(id), product_name TEXT NOT NULL, line_code TEXT NOT NULL, inspected_qty INTEGER NOT NULL CHECK(inspected_qty > 0), accepted_qty INTEGER NOT NULL CHECK(accepted_qty >= 0), rejected_qty INTEGER NOT NULL CHECK(rejected_qty >= 0), rejection_reason TEXT, result TEXT NOT NULL DEFAULT 'PENDING', inspected_at TIMESTAMPTZ NOT NULL DEFAULT now(), created_at TIMESTAMPTZ NOT NULL DEFAULT now());
ALTER TABLE quality_checks ADD COLUMN IF NOT EXISTS notes TEXT;
ALTER TABLE quality_checks ADD COLUMN IF NOT EXISTS created_by BIGINT REFERENCES users(id);
CREATE TABLE IF NOT EXISTS supplies (id BIGSERIAL PRIMARY KEY, shift_id BIGINT NOT NULL REFERENCES shifts(id), supplier TEXT NOT NULL, material_name TEXT NOT NULL, quantity NUMERIC NOT NULL CHECK(quantity > 0), unit TEXT NOT NULL, batch_no TEXT, status TEXT NOT NULL DEFAULT 'PENDING', received_at TIMESTAMPTZ NOT NULL DEFAULT now(), approved_at TIMESTAMPTZ, notes TEXT);
CREATE TABLE IF NOT EXISTS downtime (id BIGSERIAL PRIMARY KEY, shift_id BIGINT NOT NULL REFERENCES shifts(id), line_code TEXT NOT NULL, machine_name TEXT NOT NULL, started_at TIMESTAMPTZ NOT NULL DEFAULT now(), ended_at TIMESTAMPTZ, minutes INTEGER NOT NULL CHECK(minutes >= 0), reason_type TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'OPEN', action_taken TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS maintenance_tickets (id BIGSERIAL PRIMARY KEY, shift_id BIGINT NOT NULL REFERENCES shifts(id), ticket_no TEXT NOT NULL UNIQUE, line_code TEXT NOT NULL, machine_name TEXT NOT NULL, severity TEXT NOT NULL, description TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'OPEN', reported_at TIMESTAMPTZ NOT NULL DEFAULT now(), repaired_at TIMESTAMPTZ, action_taken TEXT);
CREATE TABLE IF NOT EXISTS inventory_transactions (id BIGSERIAL PRIMARY KEY, shift_id BIGINT NOT NULL REFERENCES shifts(id), material_name TEXT NOT NULL, transaction_type TEXT NOT NULL, quantity NUMERIC NOT NULL CHECK(quantity > 0), unit TEXT NOT NULL, reference_no TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), notes TEXT);
ALTER TABLE inventory_transactions ADD COLUMN IF NOT EXISTS created_by BIGINT REFERENCES users(id);
CREATE TABLE IF NOT EXISTS notifications (id BIGSERIAL PRIMARY KEY, shift_id BIGINT REFERENCES shifts(id), severity TEXT NOT NULL, title TEXT NOT NULL, body TEXT NOT NULL, is_read BOOLEAN NOT NULL DEFAULT FALSE, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS problems (id BIGSERIAL PRIMARY KEY, shift_id BIGINT NOT NULL REFERENCES shifts(id), title TEXT NOT NULL, department TEXT NOT NULL, line_code TEXT, machine_name TEXT, problem_date DATE NOT NULL, problem_time TEXT NOT NULL, severity TEXT NOT NULL CHECK(severity IN ('HIGH','MEDIUM','LOW')), owner TEXT, action_taken TEXT, status TEXT NOT NULL DEFAULT 'OPEN' CHECK(status IN ('OPEN','IN_PROGRESS','RESOLVED','CLOSED')), resolved_at TIMESTAMPTZ, notes TEXT, created_by BIGINT REFERENCES users(id), updated_by BIGINT REFERENCES users(id), created_at TIMESTAMPTZ NOT NULL DEFAULT now());
ALTER TABLE problems ADD COLUMN IF NOT EXISTS source_notification_id BIGINT REFERENCES notifications(id);
CREATE TABLE IF NOT EXISTS app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by BIGINT REFERENCES users(id));
CREATE TABLE IF NOT EXISTS audit_logs (id BIGSERIAL PRIMARY KEY, user_id BIGINT REFERENCES users(id), entity_type TEXT NOT NULL, entity_id BIGINT, action TEXT NOT NULL, old_data_json JSONB, new_data_json JSONB, reason TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS container_loadings (
  id BIGSERIAL PRIMARY KEY,
  shift_id BIGINT NOT NULL REFERENCES shifts(id),
  container_no TEXT NOT NULL,
  product_name TEXT NOT NULL,
  container_temperature_before NUMERIC NOT NULL,
  product_temperature NUMERIC NOT NULL,
  container_temperature_after NUMERIC NOT NULL,
  cartons_quantity NUMERIC NOT NULL CHECK(cartons_quantity >= 0),
  quantity NUMERIC NOT NULL CHECK(quantity >= 0),
  loaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  notes TEXT,
  created_by BIGINT REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_shifts_status_date ON shifts(status, shift_date);
CREATE INDEX IF NOT EXISTS idx_production_shift_hour ON production_hourly(shift_id, hour_started_at);
CREATE INDEX IF NOT EXISTS idx_attendance_shift ON attendance(shift_id);
CREATE INDEX IF NOT EXISTS idx_attendance_records_shift_date ON attendance_records(shift_id, attendance_date);
CREATE INDEX IF NOT EXISTS idx_attendance_records_employee ON attendance_records(employee_id);
CREATE INDEX IF NOT EXISTS idx_production_department_hour ON production_hourly(shift_id, hour_started_at, line_code);
CREATE INDEX IF NOT EXISTS idx_product_guides_department ON product_guides(department, name);
CREATE INDEX IF NOT EXISTS idx_fridge_readings_shift_date ON fridge_readings(shift_id, reading_date, reading_hour);
CREATE INDEX IF NOT EXISTS idx_raw_receipts_date_supplier_material ON raw_receipts(receipt_date, supplier, material_name);
CREATE INDEX IF NOT EXISTS idx_packaging_receipts_date_supplier_item ON packaging_receipts(receipt_date, supplier, item_name);
CREATE INDEX IF NOT EXISTS idx_notifications_shift_read ON notifications(shift_id, is_read);
CREATE INDEX IF NOT EXISTS idx_problems_shift_status ON problems(shift_id, status, severity);
CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_logs(created_at);
CREATE INDEX IF NOT EXISTS idx_container_loadings_shift ON container_loadings(shift_id, loaded_at);
