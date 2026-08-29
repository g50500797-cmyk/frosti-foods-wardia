# Wardia Production Architecture

## Current delivery

The Flutter web client is being structured around a single shift workspace with role-aware navigation, calculated KPIs, auditable mutations, and replaceable repositories. The current repository includes deterministic seed data so the operational flows can be tested without an external service.

## Production backend boundary

The recommended production deployment is:

- Flutter Web client.
- REST API with JWT access tokens and refresh-token rotation.
- PostgreSQL with foreign keys, check constraints, and indexes.
- Object storage for report exports and attachments.
- WebSocket or Server-Sent Events for live shift alerts.
- Server-side audit events and immutable approved records.

## Core relational schema

```text
users(id, department_id, role_id, name, email, password_hash, is_active, created_at)
roles(id, code, name)
permissions(id, code, name)
role_permissions(role_id, permission_id)
departments(id, code, name)
shifts(id, shift_no UNIQUE, shift_date, starts_at, ends_at, status, manager_id,
       production_supervisor_id, quality_engineer_id, security_user_id,
       opened_at, closed_at, approved_at)
employees(id, employee_no UNIQUE, name, department_id, job_title, is_active)
attendance(id, shift_id, department_id, required_count, present_count,
           absent_count, late_count, overtime_count, notes, approved_by, approved_at)
production_lines(id, code UNIQUE, name, is_active)
products(id, sku UNIQUE, name, unit, is_active)
machines(id, line_id, code UNIQUE, name, is_active)
production_hourly(id, shift_id, line_id, product_id, hour_started_at,
                  target_qty, actual_qty, waste_qty, rejected_qty,
                  downtime_minutes, downtime_reason, notes, approved_by, approved_at)
supplies(id, shift_id, supplier, material_name, product_id, quantity, unit,
         purchase_order_no, batch_no, status, received_at, approved_at, notes)
quality_checks(id, supply_id, shift_id, line_id, product_id, inspected_qty,
               accepted_qty, rejected_qty, rejection_reason, result, inspected_at,
               engineer_id, approved_at, notes)
waste(id, shift_id, line_id, product_id, hour_started_at, quantity, waste_type, reason, notes)
downtime(id, shift_id, line_id, machine_id, started_at, ended_at, reason_type,
         owner_id, action_taken, status, created_by)
maintenance_tickets(id, shift_id, machine_id, line_id, reported_at, severity,
                    description, assigned_to, arrived_at, repaired_at, closed_at,
                    cause, action_taken, spare_parts, status)
inventory_transactions(id, shift_id, material_name, transaction_type, quantity,
                       unit, reference_no, created_by, created_at, notes)
notifications(id, shift_id, severity, title, body, is_read, created_at)
audit_logs(id, user_id, department_id, entity_type, entity_id, action,
           old_data_json, new_data_json, reason, created_at)
shift_reports(id, shift_id UNIQUE, summary_json, generated_at, approved_by, pdf_url, xlsx_url)
settings(id, key UNIQUE, value_json)
```

## API contract

```text
POST   /api/auth/login
POST   /api/auth/refresh
GET    /api/me
GET    /api/shifts/current
POST   /api/shifts
PATCH  /api/shifts/:id/status
GET    /api/shifts/:id/dashboard
GET    /api/shifts/:id/attendance
POST   /api/shifts/:id/attendance
GET    /api/employees
GET    /api/shifts/:id/attendance/records
POST   /api/shifts/:id/attendance/records
PATCH  /api/shifts/:id/attendance/records/:recordId
GET    /api/shifts/:id/production/hourly
POST   /api/shifts/:id/production/hourly
GET    /api/shifts/:id/quality
POST   /api/shifts/:id/quality
GET    /api/shifts/:id/downtime
POST   /api/shifts/:id/downtime
PATCH  /api/maintenance/tickets/:id
GET    /api/shifts/:id/inventory
POST   /api/shifts/:id/inventory/transactions
GET    /api/shifts/:id/notifications
PATCH  /api/notifications/:id/read
GET    /api/shifts/:id/audit-log
POST   /api/shifts/:id/report
GET    /api/reports/production
GET    /api/reports/attendance
GET    /api/reports/quality
```

### Phase 1 attendance records

The existing shift-level `attendance` summary remains backward compatible. The detailed attendance module uses additive `employees` and `attendance_records` tables/collections. Attendance rates are calculated from `PRESENT` and `LATE` records, while absence rates are calculated from `ABSENT_EXCUSED` and `ABSENT_UNEXCUSED` records. Record edits write both old and new values to the audit log.

## Rules enforced server-side

1. Calculated fields are derived from source quantities and cannot be written by clients.
2. Approved attendance, quality, and production rows are locked.
3. Post-approval edits require a reason and create an immutable audit event.
4. Every endpoint checks role permission and shift ownership.
5. Long downtime and quality/attendance thresholds create notifications transactionally.
6. Report generation reads a consistent database snapshot.

## Client repository seam

The current `AppState` intentionally owns the same commands the API will expose. Replacing its seed repository with an authenticated HTTP repository will not require redesigning the screens: modules already call domain commands such as `addProduction`, `addDowntime`, `recordQuality`, and `addInventoryTransaction`.
