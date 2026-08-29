-- Production PostgreSQL reference schema. The local API uses the same relational model in SQLite.
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

CREATE TABLE IF NOT EXISTS roles (
  id BIGSERIAL PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  email CITEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  role_code TEXT NOT NULL REFERENCES roles(code),
  department TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS shifts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shift_no TEXT NOT NULL UNIQUE,
  shift_date DATE NOT NULL,
  starts_at TIMESTAMPTZ NOT NULL,
  ends_at TIMESTAMPTZ NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('NOT_STARTED', 'RUNNING', 'PAUSED', 'COMPLETED', 'APPROVED')),
  manager_id UUID REFERENCES users(id),
  opened_at TIMESTAMPTZ,
  closed_at TIMESTAMPTZ,
  approved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS employees (
  id BIGSERIAL PRIMARY KEY,
  employee_no TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  department TEXT NOT NULL,
  job_title TEXT NOT NULL,
  category TEXT NOT NULL,
  shift_name TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS attendance_records (
  id BIGSERIAL PRIMARY KEY,
  shift_id UUID NOT NULL REFERENCES shifts(id),
  employee_id BIGINT NOT NULL REFERENCES employees(id),
  attendance_date DATE NOT NULL,
  shift_name TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('PRESENT','LATE','MISSION','LEAVE','ABSENT_EXCUSED','ABSENT_UNEXCUSED')),
  check_in TEXT,
  check_out TEXT,
  notes TEXT,
  updated_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ,
  UNIQUE(shift_id, employee_id, attendance_date)
);
CREATE INDEX IF NOT EXISTS idx_attendance_records_shift_date ON attendance_records(shift_id, attendance_date);
CREATE INDEX IF NOT EXISTS idx_attendance_records_employee ON attendance_records(employee_id);
CREATE INDEX IF NOT EXISTS idx_shifts_status_date ON shifts(status, shift_date);

-- Remaining operational tables follow the same columns defined in ARCHITECTURE.md.
-- Migrations should add attendance, production_hourly, quality_checks, supplies,
-- downtime, maintenance_tickets, inventory_transactions, notifications, audit_logs,
-- shift_reports, and settings with foreign keys to shifts and users.
