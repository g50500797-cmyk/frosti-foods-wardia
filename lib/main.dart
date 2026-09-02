import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'download.dart';
import 'session_storage.dart';

void main() {
  runApp(const WorkerShiftApp());
}

class WorkerShiftApp extends StatelessWidget {
  const WorkerShiftApp({super.key, this.loginHandler});

  final Future<UserSession> Function(String email, String password)?
      loginHandler;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'وردية',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'EG'),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        );
      },
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
          primary: AppColors.primary,
          secondary: AppColors.amber,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.ink,
          elevation: 0,
          centerTitle: false,
        ),
      ),
      home: AuthGate(loginHandler: loginHandler),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, this.loginHandler});

  final Future<UserSession> Function(String email, String password)?
      loginHandler;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  UserSession? _session;
  bool _restoring = true;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    if (widget.loginHandler != null) {
      if (mounted) setState(() => _restoring = false);
      return;
    }
    final token = await SessionStorage.readToken();
    if (token != null && token.isNotEmpty) {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final session = await ApiClient.me(token);
          if (mounted) setState(() => _session = session);
          break;
        } catch (e, st) {
          // ignore: avoid_print
          print('[_restoreSession] attempt ${attempt + 1} failed: $e\n$st');
          if (e.toString().contains('SESSION_INVALID')) {
            await SessionStorage.clear();
            break;
          }
          if (attempt == 0) {
            await Future.delayed(const Duration(seconds: 2));
          }
          // transient failure (timeout / network / server error) even after
          // retry: keep the saved token instead of forcing the user to log
          // back in. _syncFromApi will keep retrying once the app is open.
        }
      }
    }
    if (mounted) setState(() => _restoring = false);
  }

  Future<void> _setSession(UserSession session) async {
    if (session.accessToken != null && session.accessToken!.isNotEmpty) {
      await SessionStorage.writeToken(session.accessToken!);
    }
    if (mounted) setState(() => _session = session);
  }

  @override
  Widget build(BuildContext context) {
    if (_restoring) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_session == null) {
      return LoginPage(
        loginHandler: widget.loginHandler,
        onLogin: _setSession,
      );
    }

    return ShiftWorkspace(
      session: _session!,
      onLogout: () {
        SessionStorage.clear();
        setState(() => _session = null);
      },
    );
  }
}

enum UserRole {
  systemAdmin,
  shiftManager,
  security,
  quality,
  qualityEngineer,
  production,
  productionEngineer,
  maintenance,
  warehouse,
}

extension UserRoleLabel on UserRole {
  String get label {
    switch (this) {
      case UserRole.systemAdmin:
        return 'مدير النظام';
      case UserRole.shiftManager:
        return 'مدير الوردية';
      case UserRole.security:
        return 'فرد الأمن';
      case UserRole.quality:
        return 'مهندس الجودة';
      case UserRole.qualityEngineer:
        return 'مهندس الجودة';
      case UserRole.production:
        return 'مشرف الإنتاج';
      case UserRole.productionEngineer:
        return 'مهندس الإنتاج';
      case UserRole.maintenance:
        return 'مسؤول الصيانة';
      case UserRole.warehouse:
        return 'مسؤول المخزن';
    }
  }

  IconData get icon {
    switch (this) {
      case UserRole.systemAdmin:
        return Icons.admin_panel_settings_outlined;
      case UserRole.shiftManager:
        return Icons.admin_panel_settings_outlined;
      case UserRole.security:
        return Icons.shield_outlined;
      case UserRole.quality:
        return Icons.verified_outlined;
      case UserRole.qualityEngineer:
        return Icons.verified_outlined;
      case UserRole.production:
        return Icons.precision_manufacturing_outlined;
      case UserRole.productionEngineer:
        return Icons.precision_manufacturing_outlined;
      case UserRole.maintenance:
        return Icons.build_outlined;
      case UserRole.warehouse:
        return Icons.inventory_2_outlined;
    }
  }

  bool canView(WorkspaceSection section) {
    if (this == UserRole.systemAdmin) return true;
    switch (this) {
      case UserRole.shiftManager:
        return section != WorkspaceSection.users &&
            section != WorkspaceSection.controlPanel;
      case UserRole.security:
        return {
          WorkspaceSection.dashboard,
          WorkspaceSection.shift,
          WorkspaceSection.attendance,
          WorkspaceSection.problems,
          WorkspaceSection.notifications
        }.contains(section);
      case UserRole.quality:
      case UserRole.qualityEngineer:
        return {
          WorkspaceSection.dashboard,
          WorkspaceSection.shift,
          WorkspaceSection.quality,
          WorkspaceSection.fridgeReadings,
          WorkspaceSection.productGuide,
          WorkspaceSection.reports,
          WorkspaceSection.auditLog,
          WorkspaceSection.notifications,
          WorkspaceSection.containerLoadings
        }.contains(section);
      case UserRole.production:
        return {
          WorkspaceSection.dashboard,
          WorkspaceSection.shift,
          WorkspaceSection.attendance,
          WorkspaceSection.production,
          WorkspaceSection.downtime,
          WorkspaceSection.problems,
          WorkspaceSection.notifications
        }.contains(section);
      case UserRole.productionEngineer:
        return {
          WorkspaceSection.dashboard,
          WorkspaceSection.shift,
          WorkspaceSection.attendance,
          WorkspaceSection.production,
          WorkspaceSection.productGuide,
          WorkspaceSection.downtime,
          WorkspaceSection.receipts,
          WorkspaceSection.reports,
          WorkspaceSection.auditLog,
          WorkspaceSection.problems,
          WorkspaceSection.notifications
        }.contains(section);
      case UserRole.maintenance:
        return {
          WorkspaceSection.dashboard,
          WorkspaceSection.shift,
          WorkspaceSection.downtime,
          WorkspaceSection.maintenance,
          WorkspaceSection.problems,
          WorkspaceSection.notifications
        }.contains(section);
      case UserRole.warehouse:
        return {
          WorkspaceSection.dashboard,
          WorkspaceSection.shift,
          WorkspaceSection.receipts,
          WorkspaceSection.supplies,
          WorkspaceSection.inventory,
          WorkspaceSection.problems,
          WorkspaceSection.notifications
        }.contains(section);
      case UserRole.systemAdmin:
        return true;
    }
  }
}

class UserSession {
  const UserSession(
      {required this.email,
      required this.role,
      this.name = '',
      this.department = '',
      this.accessToken});

  final String email;
  final UserRole role;
  final String name;
  final String department;
  final String? accessToken;

  bool canView(WorkspaceSection section) => role.canView(section);
}

class ApiClient {
  static const _configuredBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://wardia-api-production.up.railway.app',
  );

  static Uri _uri(String path) => Uri.parse('$_configuredBaseUrl$path');

  static Future<UserSession> login(String email, String password) async {
    final response = await http
        .post(
          _uri('/api/auth/login'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw Exception('بيانات الدخول غير صحيحة أو الخادم غير متاح');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final user = payload['user'] as Map<String, dynamic>;
    return UserSession(
      email: user['email'] as String,
      role: _roleFromApi(user['role'] as String?),
      name: user['name'] as String? ?? '',
      department: user['department'] as String? ?? '',
      accessToken: payload['token'] as String?,
    );
  }

  static Future<UserSession> me(String token) async {
    final response = await http.get(_uri('/api/me'), headers: {
      'Authorization': 'Bearer $token'
    }).timeout(const Duration(seconds: 25));
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw Exception('SESSION_INVALID');
    }
    if (response.statusCode != 200) {
      throw Exception('SESSION_CHECK_FAILED:${response.statusCode}');
    }
    final user = (jsonDecode(response.body) as Map<String, dynamic>)['user']
        as Map<String, dynamic>;
    return UserSession(
        email: user['email'] as String? ?? '',
        role: _roleFromApi(user['role'] as String?),
        name: user['name'] as String? ?? '',
        department: user['department'] as String? ?? '',
        accessToken: token);
  }

  static UserRole _roleFromApi(String? role) {
    switch (role) {
      case 'SECURITY':
        return UserRole.security;
      case 'QUALITY':
        return UserRole.quality;
      case 'QUALITY_ENGINEER':
        return UserRole.qualityEngineer;
      case 'PRODUCTION':
        return UserRole.production;
      case 'PRODUCTION_ENGINEER':
        return UserRole.productionEngineer;
      case 'MAINTENANCE':
        return UserRole.maintenance;
      case 'WAREHOUSE':
        return UserRole.warehouse;
      case 'SYSTEM_ADMIN':
        return UserRole.systemAdmin;
      default:
        return UserRole.shiftManager;
    }
  }

  static Future<ApiShiftSnapshot> loadCurrentShift(String token,
      {bool loadProduction = true}) async {
    final headers = {'Authorization': 'Bearer $token'};
    final currentResponse = await http
        .get(_uri('/api/shifts/current'), headers: headers)
        .timeout(const Duration(seconds: 25));
    if (currentResponse.statusCode != 200) throw Exception('SHIFT_LOAD_FAILED');
    final current = jsonDecode(currentResponse.body) as Map<String, dynamic>;
    final shift = current['shift'] as Map<String, dynamic>;
    final shiftId = shift['id'];
    final dashboardResponse = await http
        .get(_uri('/api/shifts/$shiftId/dashboard'), headers: headers)
        .timeout(const Duration(seconds: 25));
    final productionResponse = loadProduction
        ? await http
            .get(_uri('/api/shifts/$shiftId/production/hourly'),
                headers: headers)
            .timeout(const Duration(seconds: 25))
        : null;
    if (dashboardResponse.statusCode != 200 ||
        (productionResponse != null && productionResponse.statusCode != 200)) {
      throw Exception('DASHBOARD_LOAD_FAILED');
    }
    final dashboard =
        jsonDecode(dashboardResponse.body) as Map<String, dynamic>;
    final production = productionResponse == null
        ? const <String, dynamic>{'rows': <dynamic>[]}
        : jsonDecode(productionResponse.body) as Map<String, dynamic>;
    final attendance = dashboard['attendance'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final quality = dashboard['quality'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final productionTotals = dashboard['production'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final downtimeTotals =
        dashboard['downtime'] as Map<String, dynamic>? ?? const {};
    final maintenanceTotals =
        dashboard['maintenance'] as Map<String, dynamic>? ?? const {};
    final fridgeTotals =
        dashboard['fridges'] as Map<String, dynamic>? ?? const {};
    final problemTotals =
        dashboard['problems'] as Map<String, dynamic>? ?? const {};
    final containerTotals =
        dashboard['containers'] as Map<String, dynamic>? ?? const {};
    final rows = (production['rows'] as List<dynamic>)
        .map((item) => item as Map<String, dynamic>)
        .map((item) => HourlyProduction(
              hour: item['hour_started_at'] as String,
              target: (item['target_qty'] as num).toInt(),
              actual: (item['actual_qty'] as num).toInt(),
              line: item['line_code'] as String,
            ))
        .toList();
    return ApiShiftSnapshot(
      shiftId: (shiftId as num).toInt(),
      hourly: rows,
      present: (attendance['present'] as num?)?.toInt() ?? 0,
      absent: (attendance['absent'] as num?)?.toInt() ?? 0,
      late: (attendance['late'] as num?)?.toInt() ?? 0,
      qualityInspected: (quality['inspected'] as num?)?.toInt() ?? 0,
      qualityRejected: (quality['rejected'] as num?)?.toInt() ?? 0,
      downtime: (downtimeTotals['minutes'] as num?)?.toInt() ??
          (productionTotals['downtime'] as num?)?.toInt() ??
          0,
      requiredWorkers: (attendance['required'] as num?)?.toInt() ?? 0,
      target: (productionTotals['target'] as num?)?.toInt() ?? 0,
      actual: (productionTotals['actual'] as num?)?.toInt() ?? 0,
      waste: (productionTotals['waste'] as num?)?.toInt() ?? 0,
      rejected: (productionTotals['rejected'] as num?)?.toInt() ?? 0,
      openDowntime: (downtimeTotals['open_count'] as num?)?.toInt() ?? 0,
      maintenanceCount: (maintenanceTotals['count'] as num?)?.toInt() ?? 0,
      openMaintenance: (maintenanceTotals['open_count'] as num?)?.toInt() ?? 0,
      fridgeRequired: (fridgeTotals['required'] as num?)?.toInt() ?? 40,
      fridgeCompleted: (fridgeTotals['completed'] as num?)?.toInt() ?? 0,
      fridgeMissing: (fridgeTotals['missing'] as num?)?.toInt() ?? 40,
      fridgeDefrost: (fridgeTotals['defrost'] as num?)?.toInt() ?? 0,
      problemsCount: (problemTotals['count'] as num?)?.toInt() ?? 0,
      openProblems: (problemTotals['open_count'] as num?)?.toInt() ?? 0,
      containersCount: (containerTotals['count'] as num?)?.toInt() ?? 0,
      notifications: (dashboard['notifications'] as List<dynamic>? ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList(),
    );
  }

  static Future<void> addProduction(String token, HourlyProduction record,
      {int shiftId = 1}) async {
    final response = await http
        .post(
          _uri('/api/shifts/$shiftId/production/hourly'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json'
          },
          body: jsonEncode({
            'lineCode': record.line,
            'productName': 'خضروات مشكلة',
            'hourStartedAt': record.hour,
            'targetQty': record.target,
            'actualQty': record.actual,
          }),
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 201) throw Exception('PRODUCTION_SAVE_FAILED');
  }

  static Future<void> addAttendance(
      String token, int present, int absent, int late,
      {int shiftId = 1}) async {
    final response = await http
        .post(
          _uri('/api/shifts/$shiftId/attendance'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json'
          },
          body: jsonEncode({
            'department': 'الإنتاج',
            'requiredCount': present + absent,
            'presentCount': present,
            'absentCount': absent,
            'lateCount': late,
          }),
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 201) throw Exception('ATTENDANCE_SAVE_FAILED');
  }

  static Future<AttendanceSnapshot> loadAttendance(
    String token, {
    int shiftId = 1,
    String? date,
    String? department,
    String? jobTitle,
    String? status,
  }) async {
    final query = <String, String>{
      if (date != null && date.isNotEmpty) 'date': date,
      if (department != null && department.isNotEmpty) 'department': department,
      if (jobTitle != null && jobTitle.isNotEmpty) 'jobTitle': jobTitle,
      if (status != null && status.isNotEmpty) 'status': status,
    };
    final uri = _uri('/api/shifts/$shiftId/attendance/records')
        .replace(queryParameters: query);
    final response = await http.get(uri, headers: {
      'Authorization': 'Bearer $token'
    }).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) throw Exception('ATTENDANCE_LOAD_FAILED');
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final summary = (payload['summary'] as Map<String, dynamic>? ?? const {});
    return AttendanceSnapshot(
      records: (payload['rows'] as List<dynamic>? ?? const [])
          .map((row) => AttendanceRecord.fromJson(row as Map<String, dynamic>))
          .toList(),
      total: (summary['total'] as num?)?.toInt() ?? 0,
      present: (summary['present'] as num?)?.toInt() ?? 0,
      absent: (summary['absent'] as num?)?.toInt() ?? 0,
      late: (summary['late'] as num?)?.toInt() ?? 0,
      attendanceRate: (summary['attendanceRate'] as num?)?.toDouble() ?? 0,
      absenceRate: (summary['absenceRate'] as num?)?.toDouble() ?? 0,
    );
  }

  static Future<List<AttendanceEmployee>> employees(String token,
      {bool includeInactive = true}) async {
    final response = await http.get(
        _uri('/api/employees').replace(
            queryParameters: {if (includeInactive) 'includeInactive': 'true'}),
        headers: {
          'Authorization': 'Bearer $token'
        }).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) throw Exception('EMPLOYEES_LOAD_FAILED');
    return (jsonDecode(response.body)['rows'] as List<dynamic>)
        .map((row) => AttendanceEmployee.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  static Future<AttendanceEmployee> createEmployee(
    String token, {
    required String employeeNo,
    required String name,
    required String department,
    required String jobTitle,
    required String category,
    required String shiftName,
    String? startDate,
    String? notes,
    bool isActive = true,
  }) async {
    final response = await http
        .post(
          _uri('/api/employees'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json'
          },
          body: jsonEncode({
            'employeeNo': employeeNo,
            'name': name,
            'department': department,
            'jobTitle': jobTitle,
            'category': category,
            'shiftName': shiftName,
            'startDate': startDate,
            'notes': notes,
            'isActive': isActive,
          }),
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 201) {
      throw Exception(response.statusCode == 409
          ? 'EMPLOYEE_NO_EXISTS'
          : 'EMPLOYEE_CREATE_FAILED');
    }
    return AttendanceEmployee.fromJson((jsonDecode(response.body)
        as Map<String, dynamic>)['employee'] as Map<String, dynamic>);
  }

  static Future<AttendanceEmployee> updateEmployee(String token, int id,
      {String? name,
      String? department,
      String? jobTitle,
      String? category,
      String? shiftName,
      String? startDate,
      String? notes,
      bool? isActive}) async {
    final response = await http
        .patch(_uri('/api/employees/$id'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json'
            },
            body: jsonEncode({
              'name': name,
              'department': department,
              'jobTitle': jobTitle,
              'category': category,
              'shiftName': shiftName,
              'startDate': startDate,
              'notes': notes,
              'isActive': isActive
            }))
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) throw Exception('EMPLOYEE_UPDATE_FAILED');
    return AttendanceEmployee.fromJson((jsonDecode(response.body)
        as Map<String, dynamic>)['employee'] as Map<String, dynamic>);
  }

  static Future<AttendanceRecord> createAttendanceRecord(
    String token, {
    required int employeeId,
    required String attendanceDate,
    required String status,
    String shiftName = 'الثانية',
    String? checkIn,
    String? checkOut,
    String? notes,
    int shiftId = 1,
  }) async {
    final response = await http
        .post(
          _uri('/api/shifts/$shiftId/attendance/records'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json'
          },
          body: jsonEncode({
            'employeeId': employeeId,
            'attendanceDate': attendanceDate,
            'shiftName': shiftName,
            'status': status,
            'checkIn': checkIn,
            'checkOut': checkOut,
            'notes': notes
          }),
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 201)
      throw Exception(response.statusCode == 409
          ? 'ATTENDANCE_RECORD_EXISTS'
          : 'ATTENDANCE_CREATE_FAILED');
    return AttendanceRecord.fromJson((jsonDecode(response.body)
        as Map<String, dynamic>)['row'] as Map<String, dynamic>);
  }

  static Future<AttendanceRecord> updateAttendanceRecord(
    String token,
    int recordId, {
    required String status,
    String? checkIn,
    String? checkOut,
    String? notes,
    int shiftId = 1,
  }) async {
    final response = await http
        .patch(
          _uri('/api/shifts/$shiftId/attendance/records/$recordId'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json'
          },
          body: jsonEncode({
            'status': status,
            'checkIn': checkIn,
            'checkOut': checkOut,
            'notes': notes
          }),
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) throw Exception('ATTENDANCE_UPDATE_FAILED');
    return AttendanceRecord.fromJson((jsonDecode(response.body)
        as Map<String, dynamic>)['row'] as Map<String, dynamic>);
  }

  static Future<ProductionSnapshot> loadProduction(
      String token, String department,
      {int shiftId = 1}) async {
    final uri = _uri('/api/shifts/$shiftId/production/hourly')
        .replace(queryParameters: {'department': department});
    final response = await http.get(uri, headers: {
      'Authorization': 'Bearer $token'
    }).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) throw Exception('PRODUCTION_LOAD_FAILED');
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return ProductionSnapshot(
        rows: (payload['rows'] as List<dynamic>? ?? const [])
            .map((row) => ProductionEntry.fromJson(row as Map<String, dynamic>))
            .toList(),
        summary: ProductionTotals.fromJson(
            payload['summary'] as Map<String, dynamic>? ?? const {}));
  }

  static Future<void> createProduction(String token, ProductionEntry entry,
      {int shiftId = 1}) async {
    final response = await http
        .post(_uri('/api/shifts/$shiftId/production/hourly'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json'
            },
            body: jsonEncode(entry.toJson()))
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 201) throw Exception('PRODUCTION_CREATE_FAILED');
  }

  static Future<List<Map<String, dynamic>>> loadModule(
      String token, String module,
      {int shiftId = 1}) async {
    final response = await http.get(_uri('/api/shifts/$shiftId/$module'),
        headers: {
          'Authorization': 'Bearer $token'
        }).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) throw Exception('MODULE_LOAD_FAILED');
    return ((jsonDecode(response.body) as Map<String, dynamic>)['rows']
                as List<dynamic>? ??
            const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  static Future<int> loadInventoryOpeningBalance(String token) async {
    final response = await http.get(
        _uri('/api/settings/inventory-opening-balance'),
        headers: {
          'Authorization': 'Bearer $token'
        }).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) throw Exception('SETTING_LOAD_FAILED');
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return ((payload['openingBalance'] as num?) ?? 0).toInt();
  }

  static Future<void> updateInventoryOpeningBalance(
      String token, int value) async {
    final response = await http
        .patch(_uri('/api/settings/inventory-opening-balance'), headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json'
        }, body: jsonEncode({'openingBalance': value}))
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) throw Exception('SETTING_UPDATE_FAILED');
  }

  static Future<void> createSupply(String token, int quantity,
      {int shiftId = 1}) async {
    final response = await http
        .post(_uri('/api/shifts/$shiftId/supplies'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json'
            },
            body: jsonEncode({
              'supplier': 'غير محدد',
              'materialName': 'خامة تشغيل',
              'quantity': quantity,
              'unit': 'kg'
            }))
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 201) throw Exception('SUPPLY_CREATE_FAILED');
  }

  static Future<void> createDowntime(String token, DowntimeRecord record,
      {int shiftId = 1}) async {
    final response = await http
        .post(_uri('/api/shifts/$shiftId/downtime'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json'
            },
            body: jsonEncode({
              'lineCode': record.line,
              'machineName': record.machine,
              'minutes': record.minutes,
              'reasonType': record.reason,
              'status': 'OPEN'
            }))
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 201) throw Exception('DOWNTIME_CREATE_FAILED');
  }

  static Future<void> createMaintenance(String token, MaintenanceTicket ticket,
      {int shiftId = 1}) async {
    final response = await http
        .post(_uri('/api/shifts/$shiftId/maintenance'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json'
            },
            body: jsonEncode({
              'ticketNo': ticket.number,
              'lineCode': 'LINE-01',
              'machineName': ticket.machine,
              'severity': ticket.severity,
              'description': ticket.description,
              'status': 'OPEN'
            }))
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 201)
      throw Exception('MAINTENANCE_CREATE_FAILED');
  }

  static Future<void> createInventory(String token, InventoryMovement movement,
      {int shiftId = 1}) async {
    final type = movement.type == 'توريد'
        ? 'RECEIPT'
        : movement.type == 'مرتجع'
            ? 'RETURN'
            : 'ISSUE';
    final response = await http
        .post(_uri('/api/shifts/$shiftId/inventory'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json'
            },
            body: jsonEncode({
              'materialName': movement.material,
              'transactionType': type,
              'quantity': movement.quantity,
              'unit': 'kg'
            }))
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 201) throw Exception('INVENTORY_CREATE_FAILED');
  }

  static Future<List<ProductGuide>> loadProductGuides(String token,
      {String query = '', String? department}) async {
    final params = <String, String>{
      if (query.isNotEmpty) 'q': query,
      if (department != null && department.isNotEmpty) 'department': department
    };
    final response = await http.get(
        _uri('/api/products/guides').replace(queryParameters: params),
        headers: {
          'Authorization': 'Bearer $token'
        }).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200)
      throw Exception('PRODUCT_GUIDES_LOAD_FAILED');
    return (jsonDecode(response.body)['rows'] as List<dynamic>? ?? const [])
        .map((row) => ProductGuide.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  static Future<void> createProductGuide(
      String token, ProductGuide guide) async {
    final response = await http
        .post(_uri('/api/products/guides'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json'
            },
            body: jsonEncode(guide.toJson()))
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 201)
      throw Exception('PRODUCT_GUIDE_CREATE_FAILED');
  }

  static Future<void> updateProductGuide(
      String token, ProductGuide guide) async {
    final response = await http
        .patch(_uri('/api/products/guides/${guide.id}'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json'
            },
            body: jsonEncode(guide.toJson()))
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200)
      throw Exception('PRODUCT_GUIDE_UPDATE_FAILED');
  }

  static Future<FridgeSnapshot> loadFridgeReadings(String token,
      {int shiftId = 1, String? date}) async {
    final params = <String, String>{
      if (date != null && date.isNotEmpty) 'date': date
    };
    final response = await http.get(
        _uri('/api/shifts/$shiftId/quality/fridge-readings')
            .replace(queryParameters: params),
        headers: {
          'Authorization': 'Bearer $token'
        }).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200)
      throw Exception('FRIDGE_READINGS_LOAD_FAILED');
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return FridgeSnapshot(
        rows: (payload['rows'] as List<dynamic>? ?? const [])
            .map((row) => FridgeReading.fromJson(row as Map<String, dynamic>))
            .toList(),
        summary: FridgeTotals.fromJson(
            payload['summary'] as Map<String, dynamic>? ?? const {}));
  }

  static Future<List<Map<String, dynamic>>> loadShiftHistory(String token,
      {String? from,
      String? to,
      String? number,
      String? name,
      String? department}) async {
    final response = await http.get(
        _uri('/api/shifts/history').replace(queryParameters: {
          if (from != null && from.isNotEmpty) 'from': from,
          if (to != null && to.isNotEmpty) 'to': to,
          if (number != null && number.isNotEmpty) 'number': number,
          if (name != null && name.isNotEmpty) 'name': name,
          if (department != null && department.isNotEmpty)
            'department': department,
        }),
        headers: {
          'Authorization': 'Bearer $token'
        }).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200)
      throw Exception('SHIFT_HISTORY_LOAD_FAILED');
    return ((jsonDecode(response.body) as Map<String, dynamic>)['rows']
                as List<dynamic>? ??
            const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  static Future<List<Fridge>> loadFridges(String token) async {
    final response = await http.get(_uri('/api/quality/fridges'), headers: {
      'Authorization': 'Bearer $token'
    }).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) throw Exception('FRIDGES_LOAD_FAILED');
    return (jsonDecode(response.body)['rows'] as List<dynamic>? ?? const [])
        .map((row) => Fridge.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  static Future<Map<String, dynamic>> createFridgeReading(String token,
      {required int fridgeId,
      required String date,
      required String hour,
      required double temperature,
      required String status,
      String? notes,
      int shiftId = 1}) async {
    final response = await http
        .post(_uri('/api/shifts/$shiftId/quality/fridge-readings'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json'
            },
            body: jsonEncode({
              'fridgeId': fridgeId,
              'readingDate': date,
              'readingHour': hour,
              'temperature': temperature,
              'status': status,
              'notes': notes
            }))
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 201)
      throw Exception('FRIDGE_READING_CREATE_FAILED');
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<ReceiptSnapshot> loadReceipts(String token,
      {String? from, String? to, String? supplier, String? material}) async {
    final params = <String, String>{
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
      if (supplier != null && supplier.isNotEmpty) 'supplier': supplier,
      if (material != null && material.isNotEmpty) 'material': material
    };
    final response = await http
        .get(_uri('/api/receipts').replace(queryParameters: params), headers: {
      'Authorization': 'Bearer $token'
    }).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) throw Exception('RECEIPTS_LOAD_FAILED');
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return ReceiptSnapshot(
        rows: (payload['rows'] as List<dynamic>? ?? const [])
            .map((row) => RawReceipt.fromJson(row as Map<String, dynamic>))
            .toList(),
        summary: ReceiptTotals.fromJson(
            payload['summary'] as Map<String, dynamic>? ?? const {}));
  }

  static Future<void> createReceipt(String token, RawReceipt receipt) async {
    final response = await http
        .post(_uri('/api/receipts'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json'
            },
            body: jsonEncode(receipt.toJson()))
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 201) throw Exception('RECEIPT_CREATE_FAILED');
  }

  static Future<Map<String, dynamic>> loadPackagingReceipts(String token,
      {String? from, String? to, String? supplier, String? item}) async {
    final params = <String, String>{
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
      if (supplier != null && supplier.isNotEmpty) 'supplier': supplier,
      if (item != null && item.isNotEmpty) 'item': item,
    };
    final response = await http.get(
        _uri('/api/receipts/packaging').replace(queryParameters: params),
        headers: {
          'Authorization': 'Bearer $token'
        }).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200)
      throw Exception('PACKAGING_RECEIPTS_LOAD_FAILED');
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<List<ContainerLoading>> loadContainerLoadings(String token,
      {int shiftId = 1}) async {
    final response = await http.get(
        _uri('/api/shifts/$shiftId/container-loadings'),
        headers: {'Authorization': 'Bearer $token'}).timeout(
      const Duration(seconds: 25),
    );
    if (response.statusCode != 200) {
      throw Exception('CONTAINER_LOADINGS_LOAD_FAILED');
    }
    return ((jsonDecode(response.body) as Map<String, dynamic>)['rows']
                as List<dynamic>? ??
            const [])
        .map((row) => ContainerLoading.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  static Future<ContainerLoading> createContainerLoading(
      String token, ContainerLoading loading,
      {int shiftId = 1}) async {
    final response = await http
        .post(_uri('/api/shifts/$shiftId/container-loadings'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json'
            },
            body: jsonEncode(loading.toJson()))
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 201) {
      throw Exception('CONTAINER_LOADING_CREATE_FAILED');
    }
    return ContainerLoading.fromJson((jsonDecode(response.body)
        as Map<String, dynamic>)['row'] as Map<String, dynamic>);
  }

  static Future<void> createPackagingReceipt(
      String token, PackagingReceipt receipt) async {
    final response = await http
        .post(_uri('/api/receipts/packaging'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json'
            },
            body: jsonEncode(receipt.toJson()))
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 201)
      throw Exception('PACKAGING_RECEIPT_CREATE_FAILED');
  }

  static Future<Map<String, dynamic>> report(String token,
      {int shiftId = 1}) async {
    final response = await http.get(_uri('/api/shifts/$shiftId/report'),
        headers: {
          'Authorization': 'Bearer $token'
        }).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) throw Exception('REPORT_LOAD_FAILED');
    return jsonDecode(response.body)['report'] as Map<String, dynamic>;
  }

  static Future<void> exportReport(String token,
      {required bool csv, int shiftId = 1}) async {
    final suffix = csv ? 'csv' : 'html';
    final response = await http.get(_uri('/api/shifts/$shiftId/report.$suffix'),
        headers: {
          'Authorization': 'Bearer $token'
        }).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) throw Exception('REPORT_EXPORT_FAILED');
    await downloadText(
        csv ? 'shift-report.csv' : 'shift-report.html',
        response.body,
        csv ? 'text/csv;charset=utf-8' : 'text/html;charset=utf-8');
  }

  static Future<void> updateShiftStatus(String token, String status,
      {int shiftId = 1,
      bool closeDespiteIssues = false,
      String closeNotes = ''}) async {
    final response = await http
        .patch(_uri('/api/shifts/$shiftId/status'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json'
            },
            body: jsonEncode({
              'status': status,
              'closeDespiteIssues': closeDespiteIssues,
              'closeNotes': closeNotes
            }))
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) throw Exception('SHIFT_STATUS_FAILED');
  }

  static Future<ShiftRecord> loadCurrentShiftRecord(String token) async {
    final response = await http.get(_uri('/api/shifts/current'), headers: {
      'Authorization': 'Bearer $token'
    }).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) throw Exception('SHIFT_LOAD_FAILED');
    final row = (jsonDecode(response.body) as Map<String, dynamic>)['shift']
        as Map<String, dynamic>?;
    if (row == null) throw Exception('SHIFT_NOT_FOUND');
    return ShiftRecord(
        id: (row['id'] as num?)?.toInt() ?? 1,
        number: row['shift_no'] as String? ?? '',
        date: row['shift_date'] as String? ?? '',
        start: row['starts_at'] as String? ?? '',
        end: row['ends_at'] as String? ?? '',
        manager: '',
        status: row['status'] as String? ?? 'NOT_STARTED');
  }

  static Future<Map<String, dynamic>> loadCloseReview(String token,
      {int shiftId = 1}) async {
    final response = await http.get(_uri('/api/shifts/$shiftId/close-review'),
        headers: {
          'Authorization': 'Bearer $token'
        }).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) throw Exception('CLOSE_REVIEW_LOAD_FAILED');
    return (jsonDecode(response.body) as Map<String, dynamic>)['review']
        as Map<String, dynamic>;
  }

  static Future<List<Map<String, dynamic>>> loadProblems(String token,
      {int shiftId = 1}) async {
    final response = await http.get(_uri('/api/shifts/$shiftId/problems'),
        headers: {
          'Authorization': 'Bearer $token'
        }).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) throw Exception('PROBLEMS_LOAD_FAILED');
    return ((jsonDecode(response.body) as Map<String, dynamic>)['rows']
                as List<dynamic>? ??
            const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> loadAuditLog(String token,
      {int shiftId = 1}) async {
    final response = await http.get(_uri('/api/shifts/$shiftId/audit-log'),
        headers: {'Authorization': 'Bearer $token'}).timeout(
      const Duration(seconds: 25),
    );
    if (response.statusCode != 200) throw Exception('AUDIT_LOAD_FAILED');
    return ((jsonDecode(response.body) as Map<String, dynamic>)['rows']
                as List<dynamic>? ??
            const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  static Future<Map<String, dynamic>> createProblem(
      String token, Map<String, dynamic> problem,
      {int shiftId = 1}) async {
    final response = await http
        .post(_uri('/api/shifts/$shiftId/problems'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json'
            },
            body: jsonEncode(problem))
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 201) throw Exception('PROBLEM_CREATE_FAILED');
    return (jsonDecode(response.body) as Map<String, dynamic>)['row']
        as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> updateProblem(
      String token, int problemId, Map<String, dynamic> changes,
      {int shiftId = 1}) async {
    final response = await http
        .patch(_uri('/api/shifts/$shiftId/problems/$problemId'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json'
            },
            body: jsonEncode(changes))
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) throw Exception('PROBLEM_UPDATE_FAILED');
    return (jsonDecode(response.body) as Map<String, dynamic>)['row']
        as Map<String, dynamic>;
  }

  static Future<void> convertNotificationToProblem(
      String token, int notificationId,
      {int shiftId = 1}) async {
    final response = await http
        .post(
            _uri(
                '/api/shifts/$shiftId/problems/from-notification/$notificationId'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json'
            },
            body: jsonEncode({}))
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 201) {
      throw Exception('PROBLEM_CONVERT_FAILED');
    }
  }

  static Future<ShiftRecord> createShift(String token,
      {required String shiftNo,
      required String date,
      String startsAt = '16:00',
      String endsAt = '00:00'}) async {
    final response = await http
        .post(_uri('/api/shifts'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json'
            },
            body: jsonEncode({
              'shiftNo': shiftNo,
              'shiftDate': date,
              'startsAt': startsAt,
              'endsAt': endsAt
            }))
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 201) throw Exception('SHIFT_CREATE_FAILED');
    final row = (jsonDecode(response.body) as Map<String, dynamic>)['shift']
        as Map<String, dynamic>;
    return ShiftRecord.fromJson(row);
  }

  static Future<List<Map<String, dynamic>>> loadNotifications(
      String token) async {
    final response = await http.get(_uri('/api/shifts/1/notifications'),
        headers: {
          'Authorization': 'Bearer $token'
        }).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200)
      throw Exception('NOTIFICATIONS_LOAD_FAILED');
    return ((jsonDecode(response.body) as Map<String, dynamic>)['rows']
                as List<dynamic>? ??
            const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> roles(String token) async {
    final response = await http.get(_uri('/api/roles'), headers: {
      'Authorization': 'Bearer $token'
    }).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) throw Exception('ROLES_LOAD_FAILED');
    return (jsonDecode(response.body)['rows'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> users(String token) async {
    final response = await http.get(_uri('/api/users'), headers: {
      'Authorization': 'Bearer $token'
    }).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) throw Exception('USERS_LOAD_FAILED');
    return (jsonDecode(response.body)['rows'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  static Future<void> createUser(String token,
      {required String name,
      required String email,
      required String password,
      required String roleCode,
      String? department}) async {
    final response = await http
        .post(_uri('/api/users'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json'
            },
            body: jsonEncode({
              'name': name,
              'email': email,
              'password': password,
              'roleCode': roleCode,
              'department': department
            }))
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 201) throw Exception('USER_CREATE_FAILED');
  }

  static Future<void> updateUserStatus(
      String token, int id, bool active) async {
    final response = await http
        .patch(_uri('/api/users/$id/status'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json'
            },
            body: jsonEncode({'isActive': active}))
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) throw Exception('USER_STATUS_FAILED');
  }
}

class ApiShiftSnapshot {
  const ApiShiftSnapshot({
    required this.shiftId,
    required this.hourly,
    required this.present,
    required this.absent,
    required this.late,
    required this.qualityInspected,
    required this.qualityRejected,
    required this.downtime,
    required this.requiredWorkers,
    required this.target,
    required this.actual,
    required this.waste,
    required this.rejected,
    required this.openDowntime,
    required this.maintenanceCount,
    required this.openMaintenance,
    required this.fridgeRequired,
    required this.fridgeCompleted,
    required this.fridgeMissing,
    required this.fridgeDefrost,
    required this.problemsCount,
    required this.openProblems,
    required this.containersCount,
    required this.notifications,
  });

  final int shiftId;
  final List<HourlyProduction> hourly;
  final int present;
  final int absent;
  final int late;
  final int qualityInspected;
  final int qualityRejected;
  final int downtime;
  final int requiredWorkers;
  final int target;
  final int actual;
  final int waste;
  final int rejected;
  final int openDowntime;
  final int maintenanceCount;
  final int openMaintenance;
  final int fridgeRequired;
  final int fridgeCompleted;
  final int fridgeMissing;
  final int fridgeDefrost;
  final int problemsCount;
  final int openProblems;
  final int containersCount;
  final List<Map<String, dynamic>> notifications;
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onLogin, this.loginHandler});

  final ValueChanged<UserSession> onLogin;
  final Future<UserSession> Function(String email, String password)?
      loginHandler;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController(text: 'manager@wardia.app');
  final _passwordController = TextEditingController(text: '123456');
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _PhotoBackdrop(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppColors.ink,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          _BrandMark(),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'وردية',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'دخول مشرف الوردية',
                                  style: TextStyle(
                                      color: Color(0xFFC8D3CF), fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'تسجيل الدخول',
                              style: TextStyle(
                                color: AppColors.ink,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'استخدم الإيميل وكلمة المرور للدخول للوحة إدارة العمال.',
                              style: TextStyle(
                                  color: AppColors.muted, height: 1.5),
                            ),
                            const SizedBox(height: 18),
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: _inputDecoration(
                                label: 'الإيميل',
                                icon: Icons.email_outlined,
                              ),
                              validator: (value) {
                                final email = value?.trim() ?? '';
                                if (email.isEmpty) return 'اكتب الإيميل';
                                if (!email.contains('@') ||
                                    !email.contains('.')) {
                                  return 'الإيميل غير صحيح';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              decoration: _inputDecoration(
                                label: 'كلمة المرور',
                                icon: Icons.lock_outline,
                                suffix: IconButton(
                                  tooltip: _obscurePassword
                                      ? 'إظهار كلمة المرور'
                                      : 'إخفاء كلمة المرور',
                                  onPressed: () {
                                    setState(() =>
                                        _obscurePassword = !_obscurePassword);
                                  },
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                              validator: (value) {
                                if ((value ?? '').length < 6) {
                                  return 'كلمة المرور 6 أحرف على الأقل';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              height: 50,
                              child: FilledButton.icon(
                                onPressed: _isLoading ? null : _login,
                                icon: _isLoading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.login),
                                label: Text(_isLoading
                                    ? 'جار تسجيل الدخول...'
                                    : 'دخول'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'بيانات تجربة جاهزة: manager@wardia.app / 123456',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      suffixIcon: suffix,
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
    );
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final login = widget.loginHandler ?? ApiClient.login;
      final session = await login(
        _emailController.text.trim(),
        _passwordController.text,
      );
      if (!mounted) return;
      setState(() => _isLoading = false);
      widget.onLogin(session);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
              content:
                  Text('تعذر تسجيل الدخول. تأكد من تشغيل الخادم والبيانات.')),
        );
    }
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.width = 96, this.height = 68, this.padding = 3});

  final double width;
  final double height;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child:
            Image.asset('assets/images/frosty-logo.png', fit: BoxFit.contain),
      ),
    );
  }
}

class AppColors {
  static const background = Color(0xFFF5F7F2);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF1F2933);
  static const muted = Color(0xFF697586);
  static const border = Color(0xFFD9E0D6);
  static const primary = Color(0xFF0E7C66);
  static const primarySoft = Color(0xFFE1F3EE);
  static const amber = Color(0xFFE69F00);
  static const amberSoft = Color(0xFFFFF2D2);
  static const red = Color(0xFFC2413D);
  static const redSoft = Color(0xFFFCE5E2);
  static const violet = Color(0xFF6D5BD0);
  static const violetSoft = Color(0xFFEAE7FF);
}

class _PhotoBackdrop extends StatefulWidget {
  const _PhotoBackdrop({required this.child});

  final Widget child;

  @override
  State<_PhotoBackdrop> createState() => _PhotoBackdropState();
}

class _PhotoBackdropState extends State<_PhotoBackdrop> {
  static const _photos = [
    'assets/images/backgrounds/background-collage.jpg',
    'assets/images/backgrounds/background-ice.jpg',
    'assets/images/backgrounds/background-exhibition.jpg',
    'assets/images/backgrounds/background-frozen.jpg',
  ];

  int _photoIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (!mounted) return;
      setState(() => _photoIndex = (_photoIndex + 1) % _photos.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 900),
          child: Opacity(
            key: ValueKey(_photos[_photoIndex]),
            opacity: 0.52,
            child: Image.asset(_photos[_photoIndex], fit: BoxFit.cover),
          ),
        ),
        ColoredBox(color: Colors.white.withAlpha(135)),
        widget.child,
      ],
    );
  }
}

class ProductionEntry {
  const ProductionEntry(
      {required this.department,
      required this.hour,
      required this.line,
      required this.machine,
      required this.product,
      required this.workers,
      required this.target,
      required this.actual,
      required this.downtime,
      this.downtimeReason = '',
      this.notes = ''});
  factory ProductionEntry.fromJson(Map<String, dynamic> json) =>
      ProductionEntry(
          department: json['department'] as String? ?? 'PACKING',
          hour: json['hour_started_at'] as String? ?? '',
          line: json['line_code'] as String? ?? '',
          machine: json['machine_name'] as String? ?? '',
          product: json['product_name'] as String? ?? '',
          workers: (json['workers_count'] as num?)?.toInt() ?? 0,
          target: (json['target_qty'] as num?)?.toInt() ?? 0,
          actual: (json['actual_qty'] as num?)?.toInt() ?? 0,
          downtime: (json['downtime_minutes'] as num?)?.toInt() ?? 0,
          downtimeReason: json['downtime_reason'] as String? ?? '',
          notes: json['notes'] as String? ?? '');
  final String department, hour, line, machine, product, downtimeReason, notes;
  final int workers, target, actual, downtime;
  double get achievement => target == 0 ? 0 : actual / target * 100;
  int get difference => actual - target;
  Map<String, dynamic> toJson() => {
        'department': department,
        'hourStartedAt': hour,
        'lineCode': line,
        'machineName': machine,
        'productName': product,
        'workersCount': workers,
        'targetQty': target,
        'actualQty': actual,
        'downtimeMinutes': downtime,
        'downtimeReason': downtimeReason,
        'notes': notes
      };
}

class ProductionTotals {
  const ProductionTotals(
      {this.target = 0,
      this.actual = 0,
      this.achievement = 0,
      this.downtime = 0,
      this.hours = 0,
      this.products = 0});
  factory ProductionTotals.fromJson(Map<String, dynamic> json) =>
      ProductionTotals(
          target: (json['target'] as num?)?.toInt() ?? 0,
          actual: (json['actual'] as num?)?.toInt() ?? 0,
          achievement: (json['achievement'] as num?)?.toDouble() ?? 0,
          downtime: (json['downtime'] as num?)?.toInt() ?? 0,
          hours: (json['hours'] as num?)?.toInt() ?? 0,
          products: (json['products'] as num?)?.toInt() ?? 0);
  final int target, actual, downtime, hours, products;
  final double achievement;
}

class ProductionSnapshot {
  const ProductionSnapshot({required this.rows, required this.summary});
  final List<ProductionEntry> rows;
  final ProductionTotals summary;
}

class ProductGuide {
  const ProductGuide(
      {required this.id,
      required this.code,
      required this.name,
      required this.department,
      required this.rawMaterial,
      this.packWeight,
      this.packSize = '',
      this.size = '',
      this.temperature,
      this.lineSpeed,
      this.machineSettings = '',
      this.operatingTime = '',
      this.instructions = '',
      this.steps = const [],
      this.imageUrl});
  factory ProductGuide.fromJson(Map<String, dynamic> json) => ProductGuide(
      id: (json['id'] as num?)?.toInt() ?? 0,
      code: json['productCode'] as String? ?? '',
      name: json['name'] as String? ?? '',
      department: json['department'] as String? ?? 'PACKING',
      rawMaterial: json['rawMaterial'] as String? ?? '',
      packWeight: (json['packWeight'] as num?)?.toDouble(),
      packSize: json['packSize'] as String? ?? '',
      size: json['size'] as String? ?? '',
      temperature: json['temperature'] as String?,
      lineSpeed: json['lineSpeed'] as String?,
      machineSettings: json['machineSettings'] as String? ?? '',
      operatingTime: json['operatingTime'] as String? ?? '',
      instructions: json['instructions'] as String? ?? '',
      steps: (json['steps'] as List<dynamic>? ?? const [])
          .map((step) => step.toString())
          .toList(),
      imageUrl: json['imageUrl'] as String?);
  final int id;
  final String code,
      name,
      department,
      rawMaterial,
      packSize,
      size,
      machineSettings,
      operatingTime,
      instructions;
  final double? packWeight;
  final String? temperature, lineSpeed, imageUrl;
  final List<String> steps;
  Map<String, dynamic> toJson() => {
        'productCode': code,
        'name': name,
        'department': department,
        'rawMaterial': rawMaterial,
        'packWeight': packWeight,
        'packSize': packSize,
        'size': size,
        'temperature': temperature,
        'lineSpeed': lineSpeed,
        'machineSettings': machineSettings,
        'operatingTime': operatingTime,
        'instructions': instructions,
        'steps': steps,
        'imageUrl': imageUrl
      };
}

class Fridge {
  const Fridge(
      {required this.id,
      required this.no,
      required this.name,
      this.minTemp,
      this.maxTemp});
  factory Fridge.fromJson(Map<String, dynamic> json) => Fridge(
      id: (json['id'] as num).toInt(),
      no: json['fridgeNo'] as String? ?? '',
      name: json['name'] as String? ?? '',
      minTemp: (json['minTemp'] as num?)?.toDouble(),
      maxTemp: (json['maxTemp'] as num?)?.toDouble());
  final int id;
  final String no, name;
  final double? minTemp, maxTemp;
}

class FridgeReading {
  const FridgeReading(
      {required this.fridge,
      required this.date,
      required this.hour,
      required this.temperature,
      required this.status,
      this.notes});
  factory FridgeReading.fromJson(Map<String, dynamic> json) {
    final fridge = json['fridge'] as Map<String, dynamic>? ?? const {};
    return FridgeReading(
        fridge: fridge['name'] as String? ?? '',
        date: json['readingDate'] as String? ?? '',
        hour: json['readingHour'] as String? ?? '',
        temperature: (json['temperature'] as num?)?.toDouble() ?? 0,
        status: json['status'] as String? ?? 'NORMAL',
        notes: json['notes'] as String?);
  }
  final String fridge, date, hour, status;
  final double temperature;
  final String? notes;
}

class FridgeTotals {
  const FridgeTotals(
      {this.required = 0,
      this.completed = 0,
      this.missing = 0,
      this.compliance = 0,
      this.defrost = 0});
  factory FridgeTotals.fromJson(Map<String, dynamic> json) => FridgeTotals(
      required: (json['required'] as num?)?.toInt() ?? 40,
      completed: (json['completed'] as num?)?.toInt() ?? 0,
      missing: (json['missing'] as num?)?.toInt() ?? 0,
      compliance: (json['compliance'] as num?)?.toDouble() ?? 0,
      defrost: (json['defrost'] as num?)?.toInt() ?? 0);
  final int required, completed, missing, defrost;
  final double compliance;
}

class FridgeSnapshot {
  const FridgeSnapshot({required this.rows, required this.summary});
  final List<FridgeReading> rows;
  final FridgeTotals summary;
}

class RawReceipt {
  const RawReceipt(
      {required this.date,
      required this.time,
      required this.material,
      required this.supplier,
      required this.gross,
      required this.discountRate,
      this.supplierCode = '',
      this.defects = '',
      this.notes = '',
      this.discount = 0,
      this.net = 0});
  factory RawReceipt.fromJson(Map<String, dynamic> json) => RawReceipt(
      date: json['receiptDate'] as String? ?? '',
      time: json['receiptTime'] as String? ?? '',
      material: json['materialName'] as String? ?? '',
      supplier: json['supplier'] as String? ?? '',
      gross: (json['grossWeight'] as num?)?.toDouble() ?? 0,
      discountRate: (json['discountRate'] as num?)?.toDouble() ?? 0,
      supplierCode: json['supplierCode'] as String? ?? '',
      defects: json['defects'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      discount: (json['discountAmount'] as num?)?.toDouble() ?? 0,
      net: (json['netWeight'] as num?)?.toDouble() ?? 0);
  final String date, time, material, supplier, supplierCode, defects, notes;
  final double gross, discountRate, discount, net;
  Map<String, dynamic> toJson() => {
        'receiptDate': date,
        'receiptTime': time,
        'materialName': material,
        'supplier': supplier,
        'supplierCode': supplierCode,
        'grossWeight': gross,
        'discountRate': discountRate,
        'defects': defects,
        'notes': notes
      };
}

class ReceiptTotals {
  const ReceiptTotals(
      {this.count = 0,
      this.gross = 0,
      this.discount = 0,
      this.net = 0,
      this.averageDiscountRate = 0,
      this.suppliers = 0});
  factory ReceiptTotals.fromJson(Map<String, dynamic> json) => ReceiptTotals(
      count: (json['count'] as num?)?.toInt() ?? 0,
      gross: (json['gross'] as num?)?.toDouble() ?? 0,
      discount: (json['discount'] as num?)?.toDouble() ?? 0,
      net: (json['net'] as num?)?.toDouble() ?? 0,
      averageDiscountRate:
          (json['averageDiscountRate'] as num?)?.toDouble() ?? 0,
      suppliers: (json['suppliers'] as num?)?.toInt() ?? 0);
  final int count, suppliers;
  final double gross, discount, net, averageDiscountRate;
}

class PackagingReceipt {
  const PackagingReceipt(
      {required this.date,
      required this.time,
      required this.supplier,
      required this.item,
      required this.quantity,
      required this.unit,
      this.itemCode = '',
      this.receiptNo = '',
      this.notes = ''});
  final String date, time, supplier, item, unit, itemCode, receiptNo, notes;
  final double quantity;
  Map<String, dynamic> toJson() => {
        'receiptDate': date,
        'receiptTime': time,
        'supplier': supplier,
        'itemName': item,
        'itemCode': itemCode,
        'quantity': quantity,
        'unit': unit,
        'receiptNo': receiptNo,
        'notes': notes,
      };
}

class ContainerLoading {
  const ContainerLoading({
    this.id = 0,
    this.containerNo = '',
    this.productName = '',
    this.containerTempBefore = 0,
    this.productTemp = 0,
    this.containerTempAfter = 0,
    this.cartons = 0,
    this.quantity = 0,
    this.loadedAt = '',
    this.notes = '',
  });

  factory ContainerLoading.fromJson(Map<String, dynamic> json) =>
      ContainerLoading(
        id: (json['id'] as num?)?.toInt() ?? 0,
        containerNo: json['containerNo'] as String? ?? '',
        productName: json['productName'] as String? ?? '',
        containerTempBefore:
            (json['containerTempBefore'] as num?)?.toDouble() ?? 0,
        productTemp: (json['productTemp'] as num?)?.toDouble() ?? 0,
        containerTempAfter:
            (json['containerTempAfter'] as num?)?.toDouble() ?? 0,
        cartons: (json['cartons'] as num?)?.toDouble() ?? 0,
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        loadedAt: json['loadedAt'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
      );

  final int id;
  final String containerNo, productName, loadedAt, notes;
  final double containerTempBefore,
      productTemp,
      containerTempAfter,
      cartons,
      quantity;

  Map<String, dynamic> toJson() => {
        'containerNo': containerNo,
        'productName': productName,
        'containerTempBefore': containerTempBefore,
        'productTemp': productTemp,
        'containerTempAfter': containerTempAfter,
        'cartons': cartons,
        'quantity': quantity,
        'loadedAt': loadedAt,
        'notes': notes,
      };
}

class ReceiptSnapshot {
  const ReceiptSnapshot({required this.rows, required this.summary});
  final List<RawReceipt> rows;
  final ReceiptTotals summary;
}

class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.employeeId,
    required this.employeeNo,
    required this.employeeName,
    required this.department,
    required this.jobTitle,
    required this.category,
    required this.attendanceDate,
    required this.shiftName,
    required this.status,
    this.checkIn,
    this.checkOut,
    this.notes,
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    final employee = (json['employee'] as Map<String, dynamic>? ?? const {});
    return AttendanceRecord(
      id: (json['id'] as num?)?.toInt() ?? 0,
      employeeId: (json['employeeId'] as num?)?.toInt() ?? 0,
      employeeNo: employee['employeeNo'] as String? ?? '',
      employeeName: employee['name'] as String? ?? '',
      department: employee['department'] as String? ?? '',
      jobTitle: employee['jobTitle'] as String? ?? '',
      category: employee['category'] as String? ?? '',
      attendanceDate: json['attendanceDate'] as String? ?? '',
      shiftName: json['shiftName'] as String? ?? 'الثانية',
      status: json['status'] as String? ?? 'PRESENT',
      checkIn: json['checkIn'] as String?,
      checkOut: json['checkOut'] as String?,
      notes: json['notes'] as String?,
    );
  }

  final int id;
  final int employeeId;
  final String employeeNo;
  final String employeeName;
  final String department;
  final String jobTitle;
  final String category;
  final String attendanceDate;
  final String shiftName;
  final String status;
  final String? checkIn;
  final String? checkOut;
  final String? notes;

  AttendanceRecord copyWith(
          {String? status, String? checkIn, String? checkOut, String? notes}) =>
      AttendanceRecord(
        id: id,
        employeeId: employeeId,
        employeeNo: employeeNo,
        employeeName: employeeName,
        department: department,
        jobTitle: jobTitle,
        category: category,
        attendanceDate: attendanceDate,
        shiftName: shiftName,
        status: status ?? this.status,
        checkIn: checkIn ?? this.checkIn,
        checkOut: checkOut ?? this.checkOut,
        notes: notes ?? this.notes,
      );
}

class AttendanceEmployee {
  const AttendanceEmployee(
      {required this.id,
      required this.employeeNo,
      required this.name,
      required this.department,
      required this.jobTitle,
      required this.category,
      this.shiftName = 'الثانية',
      this.startDate,
      this.notes,
      this.isActive = true});

  factory AttendanceEmployee.fromJson(Map<String, dynamic> json) =>
      AttendanceEmployee(
        id: (json['id'] as num).toInt(),
        employeeNo: json['employeeNo'] as String? ?? '',
        name: json['name'] as String? ?? '',
        department: json['department'] as String? ?? '',
        jobTitle: json['jobTitle'] as String? ?? '',
        category: json['category'] as String? ?? '',
        shiftName: json['shiftName'] as String? ?? 'الثانية',
        startDate: json['startDate'] as String?,
        notes: json['notes'] as String?,
        isActive: json['isActive'] as bool? ?? true,
      );

  final int id;
  final String employeeNo;
  final String name;
  final String department;
  final String jobTitle;
  final String category;
  final String shiftName;
  final String? startDate;
  final String? notes;
  final bool isActive;
}

class AttendanceSnapshot {
  const AttendanceSnapshot(
      {required this.records,
      required this.total,
      required this.present,
      required this.absent,
      required this.late,
      required this.attendanceRate,
      required this.absenceRate});

  final List<AttendanceRecord> records;
  final int total;
  final int present;
  final int absent;
  final int late;
  final double attendanceRate;
  final double absenceRate;
}

String attendanceStatusLabel(String status) {
  const labels = {
    'PRESENT': 'حاضر',
    'LATE': 'متأخر',
    'MISSION': 'مأمورية',
    'LEAVE': 'إجازة',
    'ABSENT_EXCUSED': 'غياب بعذر',
    'ABSENT_UNEXCUSED': 'غياب بدون عذر',
  };
  return labels[status] ?? status;
}

Color attendanceStatusColor(String status) {
  if (status == 'PRESENT') return AppColors.primary;
  if (status == 'LATE') return AppColors.amber;
  if (status == 'ABSENT_EXCUSED' || status == 'ABSENT_UNEXCUSED')
    return AppColors.red;
  return AppColors.violet;
}

enum AttendanceStatus { present, late, absent, vacation }

extension AttendanceStatusLabel on AttendanceStatus {
  String get label {
    switch (this) {
      case AttendanceStatus.present:
        return 'حاضر';
      case AttendanceStatus.late:
        return 'متأخر';
      case AttendanceStatus.absent:
        return 'غائب';
      case AttendanceStatus.vacation:
        return 'إجازة';
    }
  }

  Color get color {
    switch (this) {
      case AttendanceStatus.present:
        return AppColors.primary;
      case AttendanceStatus.late:
        return AppColors.amber;
      case AttendanceStatus.absent:
        return AppColors.red;
      case AttendanceStatus.vacation:
        return AppColors.violet;
    }
  }

  Color get softColor {
    switch (this) {
      case AttendanceStatus.present:
        return AppColors.primarySoft;
      case AttendanceStatus.late:
        return AppColors.amberSoft;
      case AttendanceStatus.absent:
        return AppColors.redSoft;
      case AttendanceStatus.vacation:
        return AppColors.violetSoft;
    }
  }
}

class Worker {
  const Worker({
    required this.name,
    required this.role,
    required this.team,
    required this.dailyRate,
    required this.status,
    required this.overtime,
  });

  final String name;
  final String role;
  final String team;
  final double dailyRate;
  final AttendanceStatus status;
  final double overtime;
}

enum WorkspaceSection {
  dashboard,
  controlPanel,
  shift,
  attendance,
  production,
  productGuide,
  quality,
  fridgeReadings,
  supplies,
  receipts,
  downtime,
  maintenance,
  inventory,
  reports,
  auditLog,
  users,
  notifications,
  problems,
  containerLoadings,
}

extension WorkspaceSectionLabel on WorkspaceSection {
  String get label {
    switch (this) {
      case WorkspaceSection.dashboard:
        return 'لوحة الوردية';
      case WorkspaceSection.controlPanel:
        return 'لوحة التحكم';
      case WorkspaceSection.shift:
        return 'الوردية الحالية';
      case WorkspaceSection.attendance:
        return 'الحضور والغياب';
      case WorkspaceSection.production:
        return 'الإنتاج: التعبئة وIQF';
      case WorkspaceSection.productGuide:
        return 'دليل تشغيل المنتجات';
      case WorkspaceSection.quality:
        return 'الجودة والفحص';
      case WorkspaceSection.fridgeReadings:
        return 'قراءات الثلاجات';
      case WorkspaceSection.supplies:
        return 'التوريدات القديمة';
      case WorkspaceSection.receipts:
        return 'الاستلامات';
      case WorkspaceSection.downtime:
        return 'التوقفات';
      case WorkspaceSection.maintenance:
        return 'بلاغات الصيانة';
      case WorkspaceSection.inventory:
        return 'المخزن والخامات';
      case WorkspaceSection.reports:
        return 'التقارير';
      case WorkspaceSection.auditLog:
        return 'سجل الأحداث';
      case WorkspaceSection.users:
        return 'المستخدمون والأدوار';
      case WorkspaceSection.notifications:
        return 'مركز التنبيهات';
      case WorkspaceSection.problems:
        return 'سجل المشاكل';
      case WorkspaceSection.containerLoadings:
        return 'تحميل الحاويات';
    }
  }

  IconData get icon {
    switch (this) {
      case WorkspaceSection.dashboard:
        return Icons.dashboard_outlined;
      case WorkspaceSection.controlPanel:
        return Icons.admin_panel_settings_outlined;
      case WorkspaceSection.shift:
        return Icons.schedule_outlined;
      case WorkspaceSection.attendance:
        return Icons.groups_outlined;
      case WorkspaceSection.production:
        return Icons.show_chart;
      case WorkspaceSection.productGuide:
        return Icons.menu_book_outlined;
      case WorkspaceSection.quality:
        return Icons.fact_check_outlined;
      case WorkspaceSection.fridgeReadings:
        return Icons.thermostat_outlined;
      case WorkspaceSection.supplies:
        return Icons.local_shipping_outlined;
      case WorkspaceSection.receipts:
        return Icons.scale_outlined;
      case WorkspaceSection.downtime:
        return Icons.pause_circle_outline;
      case WorkspaceSection.maintenance:
        return Icons.build_circle_outlined;
      case WorkspaceSection.inventory:
        return Icons.inventory_2_outlined;
      case WorkspaceSection.reports:
        return Icons.assessment_outlined;
      case WorkspaceSection.auditLog:
        return Icons.history_outlined;
      case WorkspaceSection.users:
        return Icons.manage_accounts_outlined;
      case WorkspaceSection.notifications:
        return Icons.notifications_none_outlined;
      case WorkspaceSection.problems:
        return Icons.warning_amber_outlined;
      case WorkspaceSection.containerLoadings:
        return Icons.local_shipping_outlined;
    }
  }

  Color get accentColor {
    switch (this) {
      case WorkspaceSection.dashboard:
      case WorkspaceSection.shift:
      case WorkspaceSection.attendance:
      case WorkspaceSection.quality:
      case WorkspaceSection.fridgeReadings:
      case WorkspaceSection.reports:
      case WorkspaceSection.users:
        return AppColors.primary;
      case WorkspaceSection.controlPanel:
      case WorkspaceSection.productGuide:
      case WorkspaceSection.inventory:
      case WorkspaceSection.auditLog:
        return AppColors.violet;
      case WorkspaceSection.production:
      case WorkspaceSection.supplies:
      case WorkspaceSection.receipts:
      case WorkspaceSection.downtime:
      case WorkspaceSection.containerLoadings:
        return AppColors.amber;
      case WorkspaceSection.maintenance:
      case WorkspaceSection.notifications:
      case WorkspaceSection.problems:
        return AppColors.red;
    }
  }
}

class ShiftRecord {
  const ShiftRecord({
    this.id = 1,
    required this.number,
    required this.date,
    required this.start,
    required this.end,
    required this.manager,
    required this.status,
  });

  factory ShiftRecord.fromJson(Map<String, dynamic> json) => ShiftRecord(
        id: (json['id'] as num?)?.toInt() ?? 1,
        number: json['shift_no'] as String? ?? '',
        date: json['shift_date'] as String? ?? '',
        start: json['starts_at'] as String? ?? '',
        end: json['ends_at'] as String? ?? '',
        manager: json['manager_name'] as String? ?? '',
        status: json['status'] as String? ?? 'NOT_STARTED',
      );

  final String number;
  final int id;
  final String date;
  final String start;
  final String end;
  final String manager;
  final String status;
}

class HourlyProduction {
  const HourlyProduction({
    required this.hour,
    required this.target,
    required this.actual,
    required this.line,
  });

  final String hour;
  final int target;
  final int actual;
  final String line;

  int get difference => actual - target;
  double get achievement => target == 0 ? 0 : actual / target * 100;
}

class DowntimeRecord {
  const DowntimeRecord({
    required this.line,
    required this.machine,
    required this.reason,
    required this.minutes,
    required this.status,
  });

  final String line;
  final String machine;
  final String reason;
  final int minutes;
  final String status;
}

class MaintenanceTicket {
  const MaintenanceTicket({
    required this.number,
    required this.machine,
    required this.severity,
    required this.description,
    required this.status,
  });

  final String number;
  final String machine;
  final String severity;
  final String description;
  final String status;
}

class InventoryMovement {
  const InventoryMovement({
    required this.type,
    required this.material,
    required this.quantity,
  });

  final String type;
  final String material;
  final int quantity;
}

class AuditEvent {
  const AuditEvent({
    required this.user,
    required this.action,
    required this.department,
    required this.time,
  });

  final String user;
  final String action;
  final String department;
  final String time;
}

class ShiftWorkspace extends StatefulWidget {
  const ShiftWorkspace({
    super.key,
    required this.session,
    required this.onLogout,
  });

  final UserSession session;
  final VoidCallback onLogout;

  @override
  State<ShiftWorkspace> createState() => _ShiftWorkspaceState();
}

class _ShiftWorkspaceState extends State<ShiftWorkspace> {
  WorkspaceSection _section = WorkspaceSection.dashboard;
  int currentShiftId = 1;
  ShiftRecord? currentShift;
  Timer? _refreshTimer;

  static const shift = ShiftRecord(
    number: 'SHIFT-2026-08-21-02',
    date: '21 أغسطس 2026',
    start: '16:00',
    end: '00:00',
    manager: 'محمد حمدي',
    status: 'جارية',
  );

  static const seedWorkers = [
    Worker(
        name: 'أحمد سالم',
        role: 'مشغل ماكينة',
        team: 'إنتاج',
        dailyRate: 420,
        status: AttendanceStatus.present,
        overtime: 1),
    Worker(
        name: 'منى عادل',
        role: 'مراقبة جودة',
        team: 'جودة',
        dailyRate: 460,
        status: AttendanceStatus.present,
        overtime: 0),
    Worker(
        name: 'كريم فتحي',
        role: 'أمين مخزن',
        team: 'مخازن',
        dailyRate: 390,
        status: AttendanceStatus.late,
        overtime: 0),
    Worker(
        name: 'سارة يوسف',
        role: 'تعبئة وتغليف',
        team: 'تغليف',
        dailyRate: 360,
        status: AttendanceStatus.absent,
        overtime: 0),
    Worker(
        name: 'محمد حمدي',
        role: 'مشرف وردية',
        team: 'إنتاج',
        dailyRate: 620,
        status: AttendanceStatus.present,
        overtime: 1.5),
  ];

  static const seedHourly = [
    HourlyProduction(hour: '16:00', target: 850, actual: 820, line: 'خط 01'),
    HourlyProduction(hour: '17:00', target: 850, actual: 910, line: 'خط 01'),
    HourlyProduction(hour: '18:00', target: 850, actual: 790, line: 'خط 01'),
    HourlyProduction(hour: '19:00', target: 850, actual: 860, line: 'خط 01'),
    HourlyProduction(hour: '20:00', target: 850, actual: 730, line: 'خط 01'),
  ];

  final List<HourlyProduction> productionRecords = [...seedHourly];
  int presentCount = 4;
  int absentCount = 1;
  int lateCount = 1;
  int qualityInspected = 5700;
  int qualityRejected = 160;
  FridgeTotals fridgeTotals = const FridgeTotals();
  int requiredWorkers = 0;
  int dashboardTarget = 0;
  int dashboardActual = 0;
  int dashboardWaste = 0;
  int dashboardRejected = 0;
  int openDowntime = 0;
  int maintenanceCount = 0;
  int openMaintenance = 0;
  int fridgeRequired = 40;
  int fridgeCompleted = 0;
  int fridgeMissing = 40;
  int fridgeDefrost = 0;
  int problemsCount = 0;
  int openProblems = 0;
  int containersCount = 0;
  List<ContainerLoading> containerLoadings = [];
  List<Map<String, dynamic>> dashboardNotifications = [];
  int supplyRecords = 8;
  int supplyTotal = 3420;
  int approvedSupplies = 6;
  final List<DowntimeRecord> downtimeRecords = [
    const DowntimeRecord(
      line: 'خط 01',
      machine: 'ماكينة التعبئة',
      reason: 'عطل ماكينة',
      minutes: 18,
      status: 'مفتوح',
    ),
    const DowntimeRecord(
      line: 'خط 01',
      machine: 'نفق التجميد',
      reason: 'تنظيف',
      minutes: 9,
      status: 'مغلق',
    ),
  ];
  final List<MaintenanceTicket> maintenanceTickets = [
    const MaintenanceTicket(
      number: 'MT-204',
      machine: 'ماكينة التعبئة',
      severity: 'حرج',
      description: 'توقف حساس التغذية',
      status: 'In Progress',
    ),
    const MaintenanceTicket(
      number: 'MT-205',
      machine: 'نفق التجميد',
      severity: 'متوسط',
      description: 'ارتفاع حرارة مؤقت',
      status: 'Open',
    ),
  ];
  final List<InventoryMovement> inventoryMovements = [
    const InventoryMovement(
      type: 'صرف للإنتاج',
      material: 'فراولة مجمدة',
      quantity: 420,
    ),
    const InventoryMovement(
      type: 'توريد',
      material: 'خضروات مشكلة',
      quantity: 900,
    ),
  ];
  final List<AuditEvent> auditEvents = [
    const AuditEvent(
      user: 'محمد حمدي',
      action: 'اعتماد فتح الوردية الثانية',
      department: 'إدارة الوردية',
      time: '16:02',
    ),
    const AuditEvent(
      user: 'مشرف الإنتاج',
      action: 'تسجيل إنتاج الساعة 20:00 بقيمة 730',
      department: 'الإنتاج',
      time: '20:18',
    ),
  ];
  int inventoryOpening = 0;

  @override
  void initState() {
    super.initState();
    _syncFromApi();
    _refreshTimer = Timer.periodic(
        const Duration(seconds: 30), (_) => _syncFromApi(silent: true));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> refreshNow() => _syncFromApi();

  Future<void> _syncFromApi({bool silent = false}) async {
    final token = widget.session.accessToken;
    if (token == null) return;
    for (var attempt = 0; attempt < 2; attempt++) {
    try {
      final shiftRecord = await ApiClient.loadCurrentShiftRecord(token);
      final snapshot = await ApiClient.loadCurrentShift(token,
          loadProduction:
              widget.session.role.canView(WorkspaceSection.production));
      if (!mounted) return;
      setState(() {
        currentShiftId = snapshot.shiftId;
        currentShift = shiftRecord;
        productionRecords
          ..clear()
          ..addAll(snapshot.hourly);
        presentCount = snapshot.present;
        absentCount = snapshot.absent;
        lateCount = snapshot.late;
        qualityInspected = snapshot.qualityInspected;
        qualityRejected = snapshot.qualityRejected;
        requiredWorkers = snapshot.requiredWorkers;
        dashboardTarget = snapshot.target;
        dashboardActual = snapshot.actual;
        dashboardWaste = snapshot.waste;
        dashboardRejected = snapshot.rejected;
        openDowntime = snapshot.openDowntime;
        maintenanceCount = snapshot.maintenanceCount;
        openMaintenance = snapshot.openMaintenance;
        fridgeRequired = snapshot.fridgeRequired;
        fridgeCompleted = snapshot.fridgeCompleted;
        fridgeMissing = snapshot.fridgeMissing;
        fridgeDefrost = snapshot.fridgeDefrost;
        problemsCount = snapshot.problemsCount;
        openProblems = snapshot.openProblems;
        containersCount = snapshot.containersCount;
        dashboardNotifications = snapshot.notifications;
      });
      if ([UserRole.quality, UserRole.qualityEngineer]
          .contains(widget.session.role)) {
        final fridge = await ApiClient.loadFridgeReadings(token);
        if (mounted) setState(() => fridgeTotals = fridge.summary);
        try {
          final loadings = await ApiClient.loadContainerLoadings(token,
              shiftId: currentShiftId);
          if (mounted) {
            setState(() {
              containerLoadings = loadings;
              containersCount = loadings.length;
            });
          }
        } catch (_) {}
      }
      if (widget.session.role.canView(WorkspaceSection.downtime)) {
        try {
          final rows = await ApiClient.loadModule(token, 'downtime');
          if (mounted)
            setState(() {
              downtimeRecords
                ..clear()
                ..addAll(rows.map((row) => DowntimeRecord(
                    line: row['line_code'] as String? ?? '',
                    machine: row['machine_name'] as String? ?? '',
                    reason: row['reason_type'] as String? ?? '',
                    minutes: (row['minutes'] as num?)?.toInt() ?? 0,
                    status: row['status'] as String? ?? 'OPEN')));
            });
        } catch (_) {}
      }
      if (widget.session.role.canView(WorkspaceSection.maintenance)) {
        try {
          final rows = await ApiClient.loadModule(token, 'maintenance');
          if (mounted)
            setState(() {
              maintenanceTickets
                ..clear()
                ..addAll(rows.map((row) => MaintenanceTicket(
                    number: row['ticket_no'] as String? ?? '',
                    machine: row['machine_name'] as String? ?? '',
                    severity: row['severity'] as String? ?? '',
                    description: row['description'] as String? ?? '',
                    status: row['status'] as String? ?? 'OPEN')));
            });
        } catch (_) {}
      }
      if (widget.session.role.canView(WorkspaceSection.inventory)) {
        try {
          final rows = await ApiClient.loadModule(token, 'inventory');
          if (mounted)
            setState(() {
              inventoryMovements
                ..clear()
                ..addAll(rows.map((row) => InventoryMovement(
                    type: row['transaction_type'] == 'RECEIPT'
                        ? 'توريد'
                        : row['transaction_type'] == 'RETURN'
                            ? 'مرتجع'
                            : 'صرف للإنتاج',
                    material: row['material_name'] as String? ?? '',
                    quantity: (row['quantity'] as num?)?.toInt() ?? 0)));
            });
        } catch (_) {}
      }
        try {
          final opening = await ApiClient.loadInventoryOpeningBalance(token);
          if (mounted) setState(() => inventoryOpening = opening);
        } catch (_) {}
      if (widget.session.role.canView(WorkspaceSection.supplies)) {
        try {
          final rows = await ApiClient.loadModule(token, 'supplies');
          if (mounted)
            setState(() {
              supplyRecords = rows.length;
              supplyTotal = rows.fold<int>(
                  0,
                  (sum, row) =>
                      sum + ((row['quantity'] as num?)?.toInt() ?? 0));
              approvedSupplies =
                  rows.where((row) => row['status'] == 'APPROVED').length;
            });
        } catch (_) {}
      }
      return;
    } catch (e, st) {
      // ignore: avoid_print
      print('[_syncFromApi] attempt ${attempt + 1} failed: $e\n$st');
      if (attempt == 0) {
        await Future.delayed(const Duration(seconds: 2));
        continue;
      }
      if (mounted && !silent)
        _showSavedMessage(
            'تعذر تحديث البيانات من الخادم، تم عرض آخر بيانات متاحة');
    }
    }
  }

  List<Worker> get workers => seedWorkers;
  List<HourlyProduction> get hourly => productionRecords;
  int get present => presentCount;
  int get absent => absentCount;
  int get target => hourly.fold(0, (sum, item) => sum + item.target);
  int get actual => hourly.fold(0, (sum, item) => sum + item.actual);
  double get achievement => target == 0 ? 0 : actual / target * 100;
  int get liveTarget => dashboardTarget > 0 ? dashboardTarget : target;
  int get liveActual => dashboardActual > 0 ? dashboardActual : actual;
  double get liveAchievement =>
      liveTarget == 0 ? 0 : liveActual / liveTarget * 100;
  int get liveRequiredWorkers =>
      requiredWorkers > 0 ? requiredWorkers : workers.length;
  double get attendanceRate =>
      liveRequiredWorkers == 0 ? 0 : present / liveRequiredWorkers * 100;
  int get downtime =>
      downtimeRecords.fold(0, (sum, item) => sum + item.minutes);
  int get waste => dashboardWaste > 0 ? dashboardWaste : 64;
  int get qualityAccepted => qualityInspected - qualityRejected;
  double get rejection =>
      qualityInspected == 0 ? 0 : qualityRejected / qualityInspected * 100;
  int get openDowntimeCount => downtimeRecords
      .where((item) => item.status == 'مفتوح' || item.status == 'OPEN')
      .length;
  int get openTickets => maintenanceTickets
      .where((item) => !['Closed', 'CLOSED', 'RESOLVED'].contains(item.status))
      .length;
  int get inventoryReceived => inventoryMovements
      .where((item) => item.type == 'توريد')
      .fold(0, (sum, item) => sum + item.quantity);
  int get inventoryIssued => inventoryMovements
      .where((item) => item.type == 'صرف للإنتاج')
      .fold(0, (sum, item) => sum + item.quantity);
  int get inventoryReturned => inventoryMovements
      .where((item) => item.type == 'مرتجع')
      .fold(0, (sum, item) => sum + item.quantity);
  int get inventoryBalance =>
      inventoryOpening +
      inventoryReceived -
      inventoryIssued +
      inventoryReturned;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 70,
        leading: wide
            ? null
            : Builder(
                builder: (context) => IconButton(
                      tooltip: 'فتح القائمة',
                      onPressed: () => Scaffold.of(context).openDrawer(),
                      icon: const Icon(Icons.menu),
                    )),
        titleSpacing: wide ? 24 : 0,
        title: const Row(
          children: [
            _BrandMark(width: 58, height: 42, padding: 2),
            SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('وردية',
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                Text('مركز تشغيل المصنع',
                    style: TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
              tooltip: 'تحديث بيانات الوردية',
              onPressed: () => refreshNow(),
              icon: const Icon(Icons.refresh)),
          if (wide)
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                          widget.session.name.isEmpty
                              ? widget.session.role.label
                              : widget.session.name,
                          style: const TextStyle(
                              color: AppColors.ink,
                              fontSize: 12,
                              fontWeight: FontWeight.w800)),
                      Text(
                          '${widget.session.role.label}${widget.session.department.isEmpty ? '' : ' · ${widget.session.department}'}',
                          style: const TextStyle(
                              color: AppColors.muted, fontSize: 10)),
                    ])),
          IconButton(
              tooltip: 'تسجيل الخروج',
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout)),
          const SizedBox(width: 8),
        ],
      ),
      drawer: wide
          ? null
          : Drawer(
              child: _Sidebar(
                  onSelect: _select,
                  selected: _section,
                  session: widget.session,
                  onLogout: widget.onLogout)),
      bottomNavigationBar: wide
          ? null
          : Builder(
              builder: (context) => _MobileBottomNavigation(
                  selected: _section,
                  session: widget.session,
                  onSelect: _select,
                  onMore: () => Scaffold.of(context).openDrawer())),
      body: Row(
        children: [
          if (wide)
            _Sidebar(
                onSelect: _select,
                selected: _section,
                session: widget.session,
                onLogout: widget.onLogout),
          Expanded(
            child: _PhotoBackdrop(
              child: SafeArea(
                child: _sectionBody(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> openAddDialog(BuildContext context) async {
    switch (_section) {
      case WorkspaceSection.attendance:
        final result = await showDialog<List<int>>(
          context: context,
          builder: (_) => _AttendanceDialog(
            present: present,
            absent: absent,
            late: lateCount,
          ),
        );
        if (result != null && mounted) {
          if (widget.session.accessToken != null) {
            try {
              await ApiClient.addAttendance(
                  widget.session.accessToken!, result[0], result[1], result[2],
                  shiftId: currentShiftId);
            } catch (_) {
              _showSavedMessage('تعذر حفظ الحضور على الخادم');
              return;
            }
          }
          setState(() {
            presentCount = result[0];
            absentCount = result[1];
            lateCount = result[2];
          });
          _showSavedMessage('تم تحديث سجل الحضور وحساب النسب تلقائيًا');
        }
        return;
      case WorkspaceSection.production:
        final result = await showDialog<HourlyProduction>(
          context: context,
          builder: (_) => const _ProductionDialog(),
        );
        if (result != null && mounted) {
          if (widget.session.accessToken != null) {
            try {
              await ApiClient.addProduction(widget.session.accessToken!, result,
                  shiftId: currentShiftId);
            } catch (_) {
              _showSavedMessage('تعذر حفظ الإنتاج على الخادم');
              return;
            }
          }
          setState(() => productionRecords.add(result));
          _showSavedMessage(
            'تم حفظ الإنتاج: الفرق ${result.difference} ونسبة التحقيق ${result.achievement.toStringAsFixed(1)}%',
          );
        }
        return;
      case WorkspaceSection.quality:
        final result = await showDialog<List<int>>(
          context: context,
          builder: (_) => _QualityDialog(
            inspected: qualityInspected,
            rejected: qualityRejected,
          ),
        );
        if (result != null && mounted) {
          setState(() {
            qualityInspected = result[0];
            qualityRejected = result[1];
          });
          _showSavedMessage('تم حفظ الفحص وحساب نسبة الرفض تلقائيًا');
        }
        return;
      case WorkspaceSection.supplies:
        final quantity = await showDialog<int>(
          context: context,
          builder: (_) => const _SupplyDialog(),
        );
        if (quantity != null && mounted) {
          try {
            await ApiClient.createSupply(widget.session.accessToken!, quantity);
          } catch (_) {
            _showSavedMessage('تعذر حفظ التوريد على الخادم');
            return;
          }
          setState(() {
            supplyRecords++;
            supplyTotal += quantity;
            approvedSupplies++;
          });
          _showSavedMessage('تم تسجيل التوريد واعتماده للمراجعة');
        }
        return;
      case WorkspaceSection.downtime:
        final result = await showDialog<DowntimeRecord>(
          context: context,
          builder: (_) => const _DowntimeDialog(),
        );
        if (result != null && mounted) {
          try {
            await ApiClient.createDowntime(widget.session.accessToken!, result);
          } catch (_) {
            _showSavedMessage('تعذر حفظ التوقف على الخادم');
            return;
          }
          setState(() {
            downtimeRecords.add(result);
            auditEvents.insert(
                0,
                AuditEvent(
                    user: widget.session.role.label,
                    action:
                        'تسجيل توقف ${result.minutes} دقيقة على ${result.line}',
                    department: 'الإنتاج',
                    time: 'الآن'));
          });
          _showSavedMessage('تم حساب مدة التوقف وإضافة تنبيه إذا تجاوز الحد');
        }
        return;
      case WorkspaceSection.maintenance:
        final result = await showDialog<MaintenanceTicket>(
          context: context,
          builder: (_) => const _MaintenanceDialog(),
        );
        if (result != null && mounted) {
          try {
            await ApiClient.createMaintenance(
                widget.session.accessToken!, result);
          } catch (_) {
            _showSavedMessage('تعذر حفظ بلاغ الصيانة على الخادم');
            return;
          }
          setState(() {
            maintenanceTickets.add(result);
            auditEvents.insert(
                0,
                AuditEvent(
                    user: widget.session.role.label,
                    action: 'إنشاء بلاغ صيانة ${result.number}',
                    department: 'الصيانة',
                    time: 'الآن'));
          });
          _showSavedMessage('تم إنشاء بلاغ الصيانة وإرساله للفريق');
        }
        return;
      case WorkspaceSection.inventory:
        final result = await showDialog<InventoryMovement>(
          context: context,
          builder: (_) => const _InventoryDialog(),
        );
        if (result != null && mounted) {
          try {
            await ApiClient.createInventory(
                widget.session.accessToken!, result);
          } catch (_) {
            _showSavedMessage('تعذر حفظ حركة المخزن على الخادم');
            return;
          }
          setState(() {
            inventoryMovements.add(result);
            auditEvents.insert(
                0,
                AuditEvent(
                    user: widget.session.role.label,
                    action:
                        '${result.type}: ${result.quantity} كجم من ${result.material}',
                    department: 'المخزن',
                    time: 'الآن'));
          });
          _showSavedMessage('تم تحديث رصيد المخزن تلقائيًا');
        }
        return;
      case WorkspaceSection.auditLog:
        return;
      default:
        _showSavedMessage('نموذج هذه الوحدة سيضاف في المرحلة التالية');
    }
  }


  Future<void> editInventoryOpeningBalance(BuildContext context) async {
    final controller = TextEditingController(text: '$inventoryOpening');
    final result = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تعديل الرصيد الافتتاحي للمخزن'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'الرصيد الافتتاحي (كجم)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () {
                final value = int.tryParse(controller.text.trim());
                if (value == null || value < 0) return;
                Navigator.pop(context, value);
              },
              child: const Text('حفظ')),
        ],
      ),
    );
    if (result != null && mounted) {
      try {
        await ApiClient.updateInventoryOpeningBalance(
            widget.session.accessToken!, result);
      } catch (_) {
        _showSavedMessage('تعذر حفظ الرصيد الافتتاحي على الخادم');
        return;
      }
      setState(() => inventoryOpening = result);
      _showSavedMessage('تم تحديث الرصيد الافتتاحي بنجاح');
    }
  }

  void _showSavedMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _select(WorkspaceSection section) {
    if (!widget.session.role.canView(section)) {
      _showSavedMessage('ليس لديك صلاحية الوصول إلى هذه الوحدة');
      return;
    }
    setState(() => _section = section);
    if (MediaQuery.sizeOf(context).width < 900)
      Navigator.of(context).maybePop();
  }

  Widget _sectionBody() {
    switch (_section) {
      case WorkspaceSection.dashboard:
        return widget.session.role == UserRole.systemAdmin ||
                widget.session.role == UserRole.shiftManager
            ? _DashboardView(state: this)
            : _RoleDashboardView(state: this);
      case WorkspaceSection.controlPanel:
        return _ControlPanelView(state: this);
      case WorkspaceSection.shift:
        return _ShiftOverviewView(state: this);
      case WorkspaceSection.notifications:
        return _NotificationsView(state: this);
      case WorkspaceSection.problems:
        return _ProblemsView(state: this);
      case WorkspaceSection.reports:
        return _ReportsView(state: this);
      case WorkspaceSection.auditLog:
        return _AuditLogView(state: this);
      case WorkspaceSection.containerLoadings:
        return _ContainerLoadingView(state: this);
      case WorkspaceSection.attendance:
        return _AttendanceView(state: this);
      case WorkspaceSection.production:
        return _ProductionWorkspaceView(state: this);
      case WorkspaceSection.productGuide:
        return _ProductGuideView(state: this);
      case WorkspaceSection.quality:
      case WorkspaceSection.fridgeReadings:
        return _FridgeQualityView(state: this);
      case WorkspaceSection.receipts:
        return _ReceiptsView(state: this);
      case WorkspaceSection.users:
        return _UsersView(state: this);
      default:
        return _ModuleView(section: _section, state: this);
    }
  }
}

class _ShiftOverviewView extends StatefulWidget {
  const _ShiftOverviewView({required this.state});
  final _ShiftWorkspaceState state;
  @override
  State<_ShiftOverviewView> createState() => _ShiftOverviewViewState();
}

class _ShiftOverviewViewState extends State<_ShiftOverviewView> {
  ShiftRecord? current;
  bool loading = true;
  bool ending = false;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final token = widget.state.widget.session.accessToken;
    if (token == null) {
      setState(() => loading = false);
      return;
    }
    try {
      final value = await ApiClient.loadCurrentShiftRecord(token);
      if (mounted)
        setState(() {
          current = value;
          loading = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          current = _ShiftWorkspaceState.shift;
          loading = false;
        });
    }
  }

  Future<void> finishShift() async {
    final review = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => _CloseReviewDialog(
            token: widget.state.widget.session.accessToken!,
            shiftId: current?.id ?? 1));
    if (review == null) return;
    final token = widget.state.widget.session.accessToken;
    if (token == null) return;
    setState(() => ending = true);
    try {
      await ApiClient.updateShiftStatus(token, 'COMPLETED',
          shiftId: current?.id ?? 1,
          closeDespiteIssues: review['despite'] as bool? ?? false,
          closeNotes: review['notes'] as String? ?? '');
      await refresh();
      if (mounted)
        widget.state
            ._showSavedMessage('تم إنهاء الوردية وتسجيل التقرير النهائي');
    } catch (_) {
      if (mounted)
        widget.state._showSavedMessage('تعذر إنهاء الوردية من الخادم');
    } finally {
      if (mounted) setState(() => ending = false);
    }
  }

  Future<void> createNextShift() async {
    final values = await showDialog<Map<String, String>>(
        context: context, builder: (_) => const _NewShiftDialog());
    if (values == null) return;
    try {
      await ApiClient.createShift(widget.state.widget.session.accessToken!,
          shiftNo: values['shiftNo']!,
          date: values['date']!,
          startsAt: values['startsAt']!,
          endsAt: values['endsAt']!);
      await refresh();
      if (mounted) widget.state._showSavedMessage('تم فتح وردية جديدة مستقلة');
    } catch (_) {
      if (mounted) widget.state._showSavedMessage('تعذر فتح الوردية الجديدة');
    }
  }

  String statusLabel(String value) => switch (value) {
        'RUNNING' => 'مفتوحة',
        'PAUSED' => 'متوقفة',
        'COMPLETED' || 'CLOSED' => 'مغلقة',
        'APPROVED' => 'معتمدة',
        _ => 'لم تبدأ'
      };

  @override
  Widget build(BuildContext context) {
    final shift = current ?? _ShiftWorkspaceState.shift;
    final canFinish = [UserRole.shiftManager, UserRole.systemAdmin]
        .contains(widget.state.widget.session.role);
    return ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
        children: [
          Row(children: [
            const Icon(Icons.schedule_outlined,
                color: AppColors.primary, size: 30),
            const SizedBox(width: 10),
            const Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('الوردية الحالية',
                      style:
                          TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
                  SizedBox(height: 4),
                  Text('متابعة حالة الوردية وملخص التشغيل قبل الاعتماد',
                      style: TextStyle(color: AppColors.muted, fontSize: 12))
                ])),
            IconButton(
                tooltip: 'تحديث',
                onPressed: loading ? null : refresh,
                icon: const Icon(Icons.refresh))
          ]),
          const SizedBox(height: 16),
          _DataPanel(
              title: shift.number,
              child: Wrap(spacing: 28, runSpacing: 14, children: [
                _ShiftInfo(label: 'التاريخ', value: shift.date),
                _ShiftInfo(label: 'البداية', value: shift.start),
                _ShiftInfo(label: 'النهاية', value: shift.end),
                _ShiftInfo(
                    label: 'الحالة',
                    value: statusLabel(shift.status),
                    emphasized: true),
              ])),
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 10, children: [
            _ProductionMetric(
                label: 'الحضور', value: '${widget.state.present}'),
            _ProductionMetric(
                label: 'الإنتاج الفعلي', value: '${widget.state.actual}'),
            _ProductionMetric(
                label: 'تحقيق الهدف',
                value: '${widget.state.achievement.toStringAsFixed(1)}%'),
            _ProductionMetric(
                label: 'التوقفات', value: '${widget.state.downtime} دقيقة'),
            _ProductionMetric(
                label: 'نسبة الرفض',
                value: '${widget.state.rejection.toStringAsFixed(1)}%'),
          ]),
          if (canFinish) ...[
            const SizedBox(height: 18),
            OutlinedButton.icon(
                onPressed: () => showDialog(
                    context: context,
                    builder: (_) => _ShiftHistoryDialog(
                        token: widget.state.widget.session.accessToken!)),
                icon: const Icon(Icons.history),
                label: const Text('بحث في الورديات السابقة')),
          ],
          if (canFinish &&
              shift.status != 'COMPLETED' &&
              shift.status != 'CLOSED' &&
              shift.status != 'APPROVED') ...[
            const SizedBox(height: 18),
            FilledButton.icon(
                onPressed: ending ? null : finishShift,
                icon: const Icon(Icons.task_alt),
                label: Text(ending
                    ? 'جارٍ الإنهاء...'
                    : 'إنهاء الوردية وإصدار التقرير'))
          ],
          if (canFinish &&
              (shift.status == 'COMPLETED' || shift.status == 'CLOSED')) ...[
            const SizedBox(height: 18),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                  onPressed: () => showDialog(
                      context: context,
                      builder: (_) => _FinalReportDialog(
                          token: widget.state.widget.session.accessToken!,
                          shiftId: shift.id)),
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('عرض التقرير النهائي')),
              FilledButton.icon(
                  onPressed: createNextShift,
                  icon: const Icon(Icons.add_task),
                  label: const Text('فتح وردية جديدة')),
            ])
          ]
        ]);
  }
}

class _CloseReviewDialog extends StatefulWidget {
  const _CloseReviewDialog({required this.token, required this.shiftId});
  final String token;
  final int shiftId;
  @override
  State<_CloseReviewDialog> createState() => _CloseReviewDialogState();
}

class _CloseReviewDialogState extends State<_CloseReviewDialog> {
  Map<String, dynamic>? review;
  bool loading = true;
  bool despite = false;
  final notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final value = await ApiClient.loadCloseReview(widget.token,
          shiftId: widget.shiftId);
      if (mounted)
        setState(() {
          review = value;
          loading = false;
        });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  Color statusColor(String status) => switch (status) {
        'COMPLETE' => AppColors.primary,
        'WARNING' => AppColors.amber,
        _ => AppColors.red,
      };

  String statusText(String status) => switch (status) {
        'COMPLETE' => 'مكتمل',
        'WARNING' => 'يحتاج مراجعة',
        _ => 'ناقص / مشكلة',
      };

  @override
  Widget build(BuildContext context) {
    final items = (review?['items'] as List<dynamic>? ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    final hasProblems = review?['hasProblems'] == true;
    return AlertDialog(
        title: const Text('مراجعة الوردية قبل الإغلاق'),
        content: SizedBox(
            width: 650,
            child: SingleChildScrollView(
                child: loading
                    ? const LinearProgressIndicator()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            const Text(
                                'لا يتم الإغلاق تلقائيًا. راجع البنود ثم أكد العملية.',
                                style: TextStyle(color: AppColors.muted)),
                            const SizedBox(height: 12),
                            for (final item in items)
                              ListTile(
                                  dense: true,
                                  leading: Icon(
                                      item['status'] == 'COMPLETE'
                                          ? Icons.check_circle
                                          : Icons.warning_amber,
                                      color: statusColor(
                                          item['status'] as String? ??
                                              'PROBLEM')),
                                  title: Text(
                                      '${item['label']} · ${statusText(item['status'] as String? ?? 'PROBLEM')}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800)),
                                  subtitle:
                                      Text(item['detail'] as String? ?? '')),
                            if (hasProblems) ...[
                              const SizedBox(height: 8),
                              SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text(
                                      'إغلاق الوردية رغم وجود ملاحظات'),
                                  value: despite,
                                  onChanged: (value) =>
                                      setState(() => despite = value)),
                              if (despite)
                                TextField(
                                    controller: notes,
                                    maxLines: 3,
                                    onChanged: (_) => setState(() {}),
                                    decoration: const InputDecoration(
                                        labelText:
                                            'أسباب / ملاحظات الإغلاق الاستثنائي'))
                            ]
                          ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: loading ||
                      (hasProblems && (!despite || notes.text.trim().isEmpty))
                  ? null
                  : () async {
                      final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                                  title: const Text('تأكيد إنهاء الوردية'),
                                  content: const Text(
                                      'بعد الإنهاء ستصبح بيانات الوردية مقفلة للتعديل العادي.'),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('إلغاء')),
                                    FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child:
                                            const Text('تأكيد إنهاء الوردية'))
                                  ]));
                      if (confirmed == true && context.mounted)
                        Navigator.pop(context,
                            {'despite': despite, 'notes': notes.text.trim()});
                    },
              child: const Text('تأكيد إنهاء الوردية'))
        ]);
  }
}

class _NewShiftDialog extends StatefulWidget {
  const _NewShiftDialog();
  @override
  State<_NewShiftDialog> createState() => _NewShiftDialogState();
}

class _NewShiftDialogState extends State<_NewShiftDialog> {
  final number = TextEditingController();
  final date = TextEditingController(
      text: DateTime.now().toIso8601String().substring(0, 10));
  final startsAt = TextEditingController(text: '16:00');
  final endsAt = TextEditingController(text: '00:00');

  @override
  void dispose() {
    for (final controller in [number, date, startsAt, endsAt]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('فتح وردية جديدة'),
        content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: number,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                      labelText: 'رقم الوردية',
                      hintText: 'SHIFT-2026-08-26-02')),
              TextField(
                  controller: date,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'التاريخ')),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: startsAt,
                        decoration:
                            const InputDecoration(labelText: 'وقت البداية'))),
                const SizedBox(width: 10),
                Expanded(
                    child: TextField(
                        controller: endsAt,
                        decoration:
                            const InputDecoration(labelText: 'وقت النهاية'))),
              ])
            ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: number.text.trim().isEmpty || date.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, {
                        'shiftNo': number.text.trim(),
                        'date': date.text.trim(),
                        'startsAt': startsAt.text.trim(),
                        'endsAt': endsAt.text.trim()
                      }),
              child: const Text('فتح الوردية'))
        ],
      );
}

class _FinalReportDialog extends StatefulWidget {
  const _FinalReportDialog({required this.token, required this.shiftId});
  final String token;
  final int shiftId;
  @override
  State<_FinalReportDialog> createState() => _FinalReportDialogState();
}

class _FinalReportDialogState extends State<_FinalReportDialog> {
  Map<String, dynamic>? report;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    ApiClient.report(widget.token, shiftId: widget.shiftId).then((value) {
      if (mounted) {
        setState(() {
          report = value;
          loading = false;
        });
      }
    }).catchError((_) {
      if (mounted) setState(() => loading = false);
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('التقرير النهائي للوردية'),
        content: SizedBox(
            width: 720,
            child: loading
                ? const LinearProgressIndicator()
                : report == null
                    ? const Text('تعذر تحميل التقرير النهائي')
                    : SingleChildScrollView(
                        child:
                            _ShiftReportDialog(report: report!).build(context),
                      )),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'))
        ],
      );
}

class _ShiftHistoryDialog extends StatefulWidget {
  const _ShiftHistoryDialog({required this.token});
  final String token;

  @override
  State<_ShiftHistoryDialog> createState() => _ShiftHistoryDialogState();
}

class _ShiftHistoryDialogState extends State<_ShiftHistoryDialog> {
  final from = TextEditingController();
  final to = TextEditingController();
  final number = TextEditingController();
  final name = TextEditingController();
  final department = TextEditingController();
  List<Map<String, dynamic>> rows = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    for (final controller in [from, to, number, name, department]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> refresh() async {
    setState(() => loading = true);
    try {
      final value = await ApiClient.loadShiftHistory(widget.token,
          from: from.text.trim(),
          to: to.text.trim(),
          number: number.text.trim(),
          name: name.text.trim(),
          department: department.text.trim());
      if (mounted)
        setState(() {
          rows = value;
          loading = false;
        });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  String _value(Map<String, dynamic> row, String key) =>
      row[key]?.toString() ?? '-';

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('البحث في الورديات السابقة'),
        content: SizedBox(
          width: 760,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              _HistoryInput(controller: from, label: 'من تاريخ'),
              _HistoryInput(controller: to, label: 'إلى تاريخ'),
              _HistoryInput(controller: number, label: 'رقم الوردية'),
              _HistoryInput(controller: name, label: 'اسم الوردية'),
              _HistoryInput(controller: department, label: 'القسم PACKING/IQF'),
              FilledButton.icon(
                  onPressed: loading ? null : refresh,
                  icon: const Icon(Icons.search),
                  label: const Text('بحث'))
            ]),
            const SizedBox(height: 14),
            if (loading) const LinearProgressIndicator(),
            if (!loading && rows.isEmpty)
              const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('لا توجد ورديات مطابقة للبحث')),
            if (rows.isNotEmpty)
              SizedBox(
                  height: 360,
                  child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final report = rows[index];
                        final shift =
                            report['shift'] as Map<String, dynamic>? ?? {};
                        final production =
                            report['production'] as Map<String, dynamic>? ?? {};
                        return ListTile(
                            leading: const Icon(Icons.history,
                                color: AppColors.primary),
                            title: Text(_value(shift, 'shift_no'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800)),
                            subtitle: Text(
                                '${_value(shift, 'shift_date')} · ${_value(shift, 'status')} · إنتاج ${_value(production, 'actual')}'),
                            trailing: const Icon(Icons.chevron_left),
                            onTap: () => showDialog(
                                context: context,
                                builder: (_) =>
                                    _ShiftReportDialog(report: report)));
                      }))
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'))
        ],
      );
}

class _HistoryInput extends StatelessWidget {
  const _HistoryInput({required this.controller, required this.label});
  final TextEditingController controller;
  final String label;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: 145,
      child: TextField(
          controller: controller,
          decoration: InputDecoration(
              labelText: label,
              prefixIcon: const Icon(Icons.filter_alt_outlined))));
}

class _ShiftReportDialog extends StatelessWidget {
  const _ShiftReportDialog({required this.report});
  final Map<String, dynamic> report;

  String value(dynamic item) => item?.toString() ?? '-';
  String metric(String title, dynamic item) => '$title: ${value(item)}';

  @override
  Widget build(BuildContext context) {
    final shift = report['shift'] as Map<String, dynamic>? ?? {};
    final attendance = report['attendance'] as Map<String, dynamic>? ?? {};
    final production = report['production'] as Map<String, dynamic>? ?? {};
    final downtime = report['downtime'] as Map<String, dynamic>? ?? {};
    final maintenance = report['maintenance'] as Map<String, dynamic>? ?? {};
    final fridge = report['fridge'] as Map<String, dynamic>? ?? {};
    final byDepartment =
        report['production_by_department'] as Map<String, dynamic>? ?? {};
    final alerts = report['alerts'] as List<dynamic>? ?? const [];
    final productionRows =
        report['production_rows'] as List<dynamic>? ?? const [];
    final downtimeRows = report['downtime_rows'] as List<dynamic>? ?? const [];
    final maintenanceRows =
        report['maintenance_rows'] as List<dynamic>? ?? const [];
    final rawReceipts = report['raw_receipts'] as List<dynamic>? ?? const [];
    final packagingReceipts =
        report['packaging_receipts'] as List<dynamic>? ?? const [];
    final rawNetWeight = rawReceipts.fold<num>(
        0,
        (sum, row) =>
            sum +
            (row is Map
                ? ((row['netWeight'] ?? row['net_weight']) as num? ?? 0)
                : 0));
    return AlertDialog(
        title: Text('ملخص ${value(shift['shift_no'])}'),
        content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                      '${value(shift['shift_date'])} · ${value(shift['starts_at'])} - ${value(shift['ends_at'])}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 14),
                  _HistorySummary(title: 'العمالة', lines: [
                    metric('الإجمالي', attendance['required']),
                    metric('الحاضرون', attendance['present']),
                    metric('الغائبون', attendance['absent']),
                    metric('المتأخرون', attendance['late']),
                    metric('نسبة الحضور', report['attendance_rate'])
                  ]),
                  _HistorySummary(title: 'الإنتاج', lines: [
                    metric('الإجمالي الفعلي', production['actual']),
                    metric('المستهدف', production['target']),
                    metric('نسبة التحقيق', report['achievement']),
                    metric('التعبئة', byDepartment['PACKING']),
                    metric('IQF', byDepartment['IQF'])
                  ]),
                  _HistorySummary(title: 'التوقفات والصيانة', lines: [
                    metric('عدد التوقفات', downtime['count']),
                    metric('دقائق التوقف', downtime['minutes']),
                    metric('بلاغات الصيانة', maintenance['count']),
                    metric('بلاغات مفتوحة', maintenance['open_count'])
                  ]),
                  _HistorySummary(title: 'الثلاجات والجودة', lines: [
                    metric('القراءات المطلوبة', fridge['required']),
                    metric('المسجلة', fridge['completed']),
                    metric('الناقصة', fridge['missing']),
                    metric('Defrost', fridge['defrost'])
                  ]),
                  _HistorySummary(title: 'ملخص الحالة', lines: [
                    'حالة الوردية: ${value(shift['status'])}',
                    'التنبيهات المسجلة: ${alerts.length}',
                    'مدير الوردية: ${value(shift['manager_name'])}'
                  ]),
                  _HistorySummary(
                      title: 'الإنتاج بالساعة',
                      lines: productionRows
                          .map((row) => row is Map
                              ? '${value(row['hour_started_at'])} · ${value(row['department'])} · ${value(row['product_name'])} · ${value(row['actual_qty'])}/${value(row['target_qty'])}'
                              : value(row))
                          .toList()),
                  _HistorySummary(
                      title: 'التوقفات',
                      lines: downtimeRows
                          .map((row) => row is Map
                              ? '${value(row['line_code'])} · ${value(row['machine_name'])} · ${value(row['minutes'])} دقيقة · ${value(row['reason_type'])}'
                              : value(row))
                          .toList()),
                  _HistorySummary(
                      title: 'الصيانة',
                      lines: maintenanceRows
                          .map((row) => row is Map
                              ? '${value(row['ticket_no'])} · ${value(row['machine_name'])} · ${value(row['status'])}'
                              : value(row))
                          .toList()),
                  _HistorySummary(title: 'الاستلامات', lines: [
                    'خامات زراعية: ${rawReceipts.length} استلام · ${rawNetWeight.toStringAsFixed(1)} كجم',
                    'مواد تعبئة وتغليف: ${packagingReceipts.length} استلام'
                  ])
                ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'))
        ]);
  }
}

class _HistorySummary extends StatelessWidget {
  const _HistorySummary({required this.title, required this.lines});
  final String title;
  final List<String> lines;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _DataPanel(
          title: title,
          child: Wrap(
              spacing: 18,
              runSpacing: 8,
              children: lines.map((line) => Text(line)).toList())));
}

class _ShiftInfo extends StatelessWidget {
  const _ShiftInfo(
      {required this.label, required this.value, this.emphasized = false});
  final String label, value;
  final bool emphasized;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(color: AppColors.muted, fontSize: 11)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                color: emphasized ? AppColors.primary : AppColors.ink,
                fontWeight: FontWeight.w900,
                fontSize: 15))
      ]);
}

class _ProblemsView extends StatefulWidget {
  const _ProblemsView({required this.state});
  final _ShiftWorkspaceState state;
  @override
  State<_ProblemsView> createState() => _ProblemsViewState();
}

class _ProblemsViewState extends State<_ProblemsView> {
  List<Map<String, dynamic>> rows = [];
  bool loading = true;
  String get token => widget.state.widget.session.accessToken!;
  int get shiftId => widget.state.currentShiftId;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final value = await ApiClient.loadProblems(token, shiftId: shiftId);
      if (mounted)
        setState(() {
          rows = value;
          loading = false;
        });
    } catch (_) {
      if (mounted) {
        setState(() => loading = false);
        widget.state._showSavedMessage('تعذر تحميل سجل المشاكل');
      }
    }
  }

  Future<void> add() async {
    final value = await showDialog<Map<String, dynamic>>(
        context: context, builder: (_) => const _ProblemDialog());
    if (value == null) return;
    try {
      await ApiClient.createProblem(token, value, shiftId: shiftId);
      await refresh();
      if (mounted) widget.state._showSavedMessage('تم تسجيل المشكلة وتوثيقها');
    } catch (_) {
      if (mounted) widget.state._showSavedMessage('تعذر تسجيل المشكلة');
    }
  }

  Future<void> changeStatus(Map<String, dynamic> row, String status) async {
    var reason = '';
    if (widget.state.currentShift?.status == 'CLOSED') {
      reason = await _askReason() ?? '';
      if (reason.isEmpty) return;
    }
    try {
      await ApiClient.updateProblem(token, (row['id'] as num).toInt(),
          {'status': status, if (reason.isNotEmpty) 'exceptionReason': reason},
          shiftId: shiftId);
      await refresh();
    } catch (_) {
      if (mounted) widget.state._showSavedMessage('تعذر تحديث حالة المشكلة');
    }
  }

  Future<String?> _askReason() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
              title: const Text('سبب التعديل الاستثنائي'),
              content: TextField(
                  controller: controller,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'السبب')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('إلغاء')),
                FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, controller.text.trim()),
                    child: const Text('تسجيل'))
              ],
            ));
    controller.dispose();
    return result;
  }

  Color colorFor(String severity) => switch (severity) {
        'HIGH' => AppColors.red,
        'MEDIUM' => AppColors.amber,
        _ => AppColors.primary
      };

  String severityText(String value) =>
      switch (value) { 'HIGH' => 'عالية', 'MEDIUM' => 'متوسطة', _ => 'منخفضة' };

  String statusText(String value) => switch (value) {
        'IN_PROGRESS' => 'قيد التنفيذ',
        'RESOLVED' => 'تم الحل',
        'CLOSED' => 'مغلقة',
        _ => 'مفتوحة'
      };

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
        children: [
          Row(children: [
            const Icon(Icons.warning_amber_outlined,
                color: AppColors.red, size: 30),
            const SizedBox(width: 10),
            const Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('سجل المشاكل',
                      style:
                          TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
                  SizedBox(height: 4),
                  Text(
                      'متابعة المشكلة من البلاغ حتى الإغلاق مع توثيق الإجراءات',
                      style: TextStyle(color: AppColors.muted, fontSize: 12))
                ])),
            IconButton(
                onPressed: loading ? null : refresh,
                icon: const Icon(Icons.refresh),
                tooltip: 'تحديث'),
            FilledButton.icon(
                onPressed: add,
                icon: const Icon(Icons.add),
                label: const Text('مشكلة جديدة'))
          ]),
          const SizedBox(height: 16),
          if (loading) const LinearProgressIndicator(),
          if (!loading && rows.isEmpty)
            const _EmptyState(
                title: 'لا توجد مشاكل مسجلة لهذه الوردية',
                icon: Icons.check_circle_outline),
          for (final row in rows)
            Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: Colors.white.withAlpha(235),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: colorFor(row['severity'] as String? ?? 'LOW')
                            .withAlpha(90))),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.report_problem_outlined,
                            color:
                                colorFor(row['severity'] as String? ?? 'LOW')),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(row['title'] as String? ?? '-',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900))),
                        Text(severityText(row['severity'] as String? ?? 'LOW'),
                            style: TextStyle(
                                color: colorFor(
                                    row['severity'] as String? ?? 'LOW'),
                                fontWeight: FontWeight.w800))
                      ]),
                      const SizedBox(height: 8),
                      Text(
                          '${row['department'] ?? '-'} · ${row['line_code'] ?? 'بدون خط'} · ${row['machine_name'] ?? 'بدون ماكينة'}',
                          style: const TextStyle(color: AppColors.muted)),
                      if ((row['notes'] ?? '').toString().isNotEmpty)
                        Text(row['notes'].toString()),
                      const SizedBox(height: 8),
                      Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Chip(
                                label: Text(statusText(
                                    row['status'] as String? ?? 'OPEN'))),
                            if (row['status'] != 'IN_PROGRESS')
                              OutlinedButton(
                                  onPressed: () =>
                                      changeStatus(row, 'IN_PROGRESS'),
                                  child: const Text('بدء التنفيذ')),
                            if (row['status'] != 'RESOLVED' &&
                                row['status'] != 'CLOSED')
                              FilledButton(
                                  onPressed: () =>
                                      changeStatus(row, 'RESOLVED'),
                                  child: const Text('تسجيل الحل')),
                            if (row['status'] == 'RESOLVED')
                              OutlinedButton(
                                  onPressed: () => changeStatus(row, 'CLOSED'),
                                  child: const Text('إغلاق البلاغ')),
                          ])
                    ]))
        ],
      );
}

class _ProblemDialog extends StatefulWidget {
  const _ProblemDialog();
  @override
  State<_ProblemDialog> createState() => _ProblemDialogState();
}

class _ProblemDialogState extends State<_ProblemDialog> {
  final title = TextEditingController();
  final department = TextEditingController();
  final line = TextEditingController();
  final machine = TextEditingController();
  final owner = TextEditingController();
  final notes = TextEditingController();
  String severity = 'MEDIUM';

  @override
  void dispose() {
    for (final c in [title, department, line, machine, owner, notes])
      c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('تسجيل مشكلة جديدة'),
        content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: title,
                  onChanged: (_) => setState(() {}),
                  decoration:
                      const InputDecoration(labelText: 'عنوان المشكلة *')),
              TextField(
                  controller: department,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'القسم *')),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: line,
                        decoration:
                            const InputDecoration(labelText: 'خط الإنتاج'))),
                const SizedBox(width: 8),
                Expanded(
                    child: TextField(
                        controller: machine,
                        decoration:
                            const InputDecoration(labelText: 'الماكينة')))
              ]),
              DropdownButtonFormField<String>(
                  value: severity,
                  decoration: const InputDecoration(labelText: 'الخطورة'),
                  items: const [
                    DropdownMenuItem(value: 'HIGH', child: Text('عالية')),
                    DropdownMenuItem(value: 'MEDIUM', child: Text('متوسطة')),
                    DropdownMenuItem(value: 'LOW', child: Text('منخفضة'))
                  ],
                  onChanged: (value) =>
                      setState(() => severity = value ?? 'MEDIUM')),
              TextField(
                  controller: owner,
                  decoration: const InputDecoration(labelText: 'المسؤول')),
              TextField(
                  controller: notes,
                  maxLines: 3,
                  decoration:
                      const InputDecoration(labelText: 'وصف / ملاحظات')),
            ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed:
                  title.text.trim().isEmpty || department.text.trim().isEmpty
                      ? null
                      : () => Navigator.pop(context, {
                            'title': title.text.trim(),
                            'department': department.text.trim(),
                            'lineCode': line.text.trim(),
                            'machineName': machine.text.trim(),
                            'severity': severity,
                            'owner': owner.text.trim(),
                            'notes': notes.text.trim()
                          }),
              child: const Text('تسجيل المشكلة'))
        ],
      );
}

class _NotificationsView extends StatefulWidget {
  const _NotificationsView({required this.state});
  final _ShiftWorkspaceState state;
  @override
  State<_NotificationsView> createState() => _NotificationsViewState();
}

class _NotificationsViewState extends State<_NotificationsView> {
  List<Map<String, dynamic>> rows = [];
  bool loading = true;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final token = widget.state.widget.session.accessToken;
    if (token == null) return;
    try {
      final value = await ApiClient.loadNotifications(token);
      if (mounted)
        setState(() {
          rows = value;
          loading = false;
        });
    } catch (_) {
      if (mounted) {
        setState(() => loading = false);
        widget.state._showSavedMessage('تعذر تحميل التنبيهات');
      }
    }
  }

  Future<void> convertToProblem(Map<String, dynamic> row) async {
    final id = (row['id'] as num?)?.toInt();
    if (id == null) return;
    try {
      await ApiClient.convertNotificationToProblem(
          widget.state.widget.session.accessToken!, id,
          shiftId: widget.state.currentShiftId);
      if (mounted) widget.state._showSavedMessage('تم تحويل التنبيه إلى مشكلة');
    } catch (_) {
      if (mounted)
        widget.state._showSavedMessage('تعذر تحويل التنبيه إلى مشكلة');
    }
  }

  IconData iconFor(String title) {
    if (title.contains('Defrost') || title.contains('ثلاجة'))
      return Icons.thermostat_outlined;
    if (title.contains('توقف')) return Icons.pause_circle_outline;
    if (title.contains('إنتاج')) return Icons.trending_down;
    if (title.contains('عطل')) return Icons.build_outlined;
    return Icons.info_outline;
  }

  Color colorFor(String severity) =>
      severity == 'CRITICAL' ? AppColors.red : AppColors.amber;

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 28), children: [
        Row(children: [
          const Icon(Icons.notifications_none_outlined,
              color: AppColors.primary, size: 30),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('مركز التنبيهات',
                    style:
                        TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
                SizedBox(height: 4),
                Text('تنبيهات التشغيل والجودة مرتبة حسب الأولوية',
                    style: TextStyle(color: AppColors.muted, fontSize: 12))
              ])),
          IconButton(
              tooltip: 'تحديث',
              onPressed: loading ? null : refresh,
              icon: const Icon(Icons.refresh))
        ]),
        const SizedBox(height: 16),
        if (loading) const LinearProgressIndicator(),
        if (!loading && rows.isEmpty)
          const _EmptyState(
              title: 'لا توجد تنبيهات حالية',
              icon: Icons.notifications_none_outlined),
        for (final row in rows)
          _NotificationCard(
              row: row,
              icon: iconFor(row['title'] as String? ?? ''),
              color: colorFor(row['severity'] as String? ?? 'WARNING'),
              onConvert:
                  widget.state.widget.session.canView(WorkspaceSection.problems)
                      ? () => convertToProblem(row)
                      : null),
      ]);
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.icon});
  final String title;
  final IconData icon;
  @override
  Widget build(BuildContext context) => _DataPanel(
      title: 'الحالة الحالية',
      child: Column(children: [
        Icon(icon, size: 34, color: AppColors.muted),
        const SizedBox(height: 8),
        Text(title, style: const TextStyle(color: AppColors.muted))
      ]));
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard(
      {required this.row,
      required this.icon,
      required this.color,
      this.onConvert});
  final Map<String, dynamic> row;
  final IconData icon;
  final Color color;
  final VoidCallback? onConvert;
  @override
  Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white.withAlpha(235),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withAlpha(80))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: color.withAlpha(24),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color)),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(row['title'] as String? ?? 'تنبيه',
              style: const TextStyle(
                  fontWeight: FontWeight.w900, color: AppColors.ink)),
          const SizedBox(height: 4),
          Text(row['body'] as String? ?? '',
              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 5),
          Text(row['created_at'] as String? ?? '',
              style: const TextStyle(color: AppColors.muted, fontSize: 10))
        ])),
        if (onConvert != null)
          IconButton(
              tooltip: 'تحويل إلى مشكلة',
              onPressed: onConvert,
              icon: const Icon(Icons.add_alert_outlined))
      ]));
}

class _MobileBottomNavigation extends StatelessWidget {
  const _MobileBottomNavigation(
      {required this.selected,
      required this.session,
      required this.onSelect,
      required this.onMore});

  final WorkspaceSection selected;
  final UserSession session;
  final ValueChanged<WorkspaceSection> onSelect;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final sections = [
      WorkspaceSection.dashboard,
      WorkspaceSection.shift,
      WorkspaceSection.production,
      WorkspaceSection.quality
    ].where(session.canView).toList();
    final selectedIndex = sections.contains(selected)
        ? sections.indexOf(selected)
        : sections.length;
    return NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          if (index == sections.length) {
            onMore();
          } else {
            onSelect(sections[index]);
          }
        },
        destinations: [
          for (final section in sections)
            NavigationDestination(
                icon: Icon(section.icon),
                selectedIcon: Icon(section.icon),
                label: switch (section) {
                  WorkspaceSection.dashboard => 'الرئيسية',
                  WorkspaceSection.shift => 'الوردية',
                  WorkspaceSection.production => 'الإنتاج',
                  WorkspaceSection.quality => 'الجودة',
                  _ => section.label
                }),
          const NavigationDestination(
              icon: Icon(Icons.more_horiz), label: 'المزيد')
        ]);
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar(
      {required this.onSelect,
      required this.selected,
      required this.session,
      required this.onLogout});

  final ValueChanged<WorkspaceSection> onSelect;
  final WorkspaceSection selected;
  final UserSession session;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 248,
      color: AppColors.ink,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 20),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text('مساحة العمل',
                style: TextStyle(
                    color: Color(0xFF9DB5AE),
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ),
          for (final section in WorkspaceSection.values)
            if (section != WorkspaceSection.supplies &&
                session.role.canView(section))
              _SidebarItem(
                  section: section,
                  selected: selected == section,
                  onTap: () => onSelect(section)),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: const Color(0xFF2A3942),
                borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.primary,
                    child:
                        Icon(session.role.icon, color: Colors.white, size: 18)),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(
                          session.name.isEmpty
                              ? session.role.label
                              : session.name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 12)),
                      const SizedBox(height: 3),
                      Text(session.role.label,
                          style: const TextStyle(
                              color: Color(0xFFB8C5C1), fontSize: 10)),
                      if (session.department.isNotEmpty)
                        Text(session.department,
                            style: const TextStyle(
                                color: Color(0xFFB8C5C1), fontSize: 10)),
                      Text(session.email,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Color(0xFFB8C5C1), fontSize: 9)),
                    ])),
                IconButton(
                    tooltip: 'تسجيل الخروج',
                    onPressed: onLogout,
                    icon: const Icon(Icons.logout,
                        color: Color(0xFFB8C5C1), size: 18)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem(
      {required this.section, required this.selected, required this.onTap});

  final WorkspaceSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = section.accentColor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        selected: selected,
        selectedTileColor: AppColors.primary,
        onTap: onTap,
        leading: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
                color: selected ? Colors.white.withAlpha(46) : accent.withAlpha(38),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(section.icon,
                color: selected ? Colors.white : accent, size: 17)),
        title: Text(section.label,
            style: TextStyle(
                color: selected ? Colors.white : const Color(0xFFD9E2DE),
                fontSize: 13,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w600)),
      ),
    );
  }
}

class _RoleDashboardView extends StatelessWidget {
  const _RoleDashboardView({required this.state});
  final _ShiftWorkspaceState state;

  @override
  Widget build(BuildContext context) {
    final role = state.widget.session.role;
    final metrics = switch (role) {
      UserRole.security => [
          _KpiCard(
              icon: Icons.groups_outlined,
              label: 'الحضور',
              value: '${state.present}/${state.present + state.absent}',
              note: '${state.absent} غائب',
              color: AppColors.primary,
              soft: AppColors.primarySoft),
          _KpiCard(
              icon: Icons.schedule_outlined,
              label: 'المتأخرون',
              value: '${state.lateCount}',
              note: 'يحتاج متابعة',
              color: AppColors.amber,
              soft: AppColors.amberSoft)
        ],
      UserRole.quality || UserRole.qualityEngineer => [
          _KpiCard(
              icon: Icons.thermostat_outlined,
              label: 'قراءات الثلاجات',
              value:
                  '${state.fridgeTotals.completed}/${state.fridgeTotals.required}',
              note:
                  'نسبة الالتزام ${state.fridgeTotals.compliance.toStringAsFixed(1)}%',
              color: AppColors.primary,
              soft: AppColors.primarySoft),
          _KpiCard(
              icon: Icons.ac_unit_outlined,
              label: 'Defrost',
              value: '${state.fridgeTotals.defrost}',
              note: 'يتطلب مراجعة',
              color: AppColors.amber,
              soft: AppColors.amberSoft)
        ],
      UserRole.production || UserRole.productionEngineer => [
          _KpiCard(
              icon: Icons.factory_outlined,
              label: 'الإنتاج',
              value: '${state.actual}',
              note: '${state.achievement.toStringAsFixed(1)}% من المستهدف',
              color: AppColors.primary,
              soft: AppColors.primarySoft),
          _KpiCard(
              icon: Icons.pause_circle_outline,
              label: 'التوقفات',
              value: '${state.downtime} د',
              note: 'متابعة التشغيل',
              color: AppColors.amber,
              soft: AppColors.amberSoft)
        ],
      UserRole.warehouse => [
          _KpiCard(
              icon: Icons.scale_outlined,
              label: 'الاستلامات',
              value: '${state.supplyTotal}',
              note: 'كجم مسجل',
              color: AppColors.primary,
              soft: AppColors.primarySoft),
          _KpiCard(
              icon: Icons.inventory_2_outlined,
              label: 'رصيد المخزن',
              value: '${state.inventoryBalance}',
              note: 'كجم متاح',
              color: AppColors.ink,
              soft: AppColors.background)
        ],
      _ => [
          _KpiCard(
              icon: Icons.dashboard_outlined,
              label: 'لوحة التشغيل',
              value: 'جاهز',
              note: 'بيانات الوردية',
              color: AppColors.primary,
              soft: AppColors.primarySoft)
        ]
    };
    return ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
        children: [
          Text(
              'مرحبًا، ${state.widget.session.name.isEmpty ? role.label : state.widget.session.name}',
              style:
                  const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
          const SizedBox(height: 5),
          Text('${role.label} · الوردية الثانية',
              style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 18),
          Wrap(spacing: 10, runSpacing: 10, children: metrics),
          const SizedBox(height: 18),
          _DataPanel(
              title: 'التنبيهات الخاصة بالقسم',
              child: Text(
                  role == UserRole.security
                      ? 'تابع الحضور والانصراف والغياب من وحدة الحضور.'
                      : 'يمكنك فتح الوحدات المسموح بها من القائمة أو شريط التنقل.',
                  style: const TextStyle(color: AppColors.muted)))
        ]);
  }
}

class _DashboardView extends StatelessWidget {
  const _DashboardView({required this.state});

  final _ShiftWorkspaceState state;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('الوردية الثانية',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: AppColors.ink)),
                const SizedBox(height: 6),
                Text(
                    '${state.currentShift?.number ?? _ShiftWorkspaceState.shift.number}  ·  ${state.currentShift?.date ?? _ShiftWorkspaceState.shift.date}',
                    style:
                        const TextStyle(color: AppColors.muted, fontSize: 13))
              ])),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                const Icon(Icons.circle, color: AppColors.primary, size: 10),
                const SizedBox(width: 7),
                Text(
                    state.currentShift?.status == 'PAUSED'
                        ? 'الوردية متوقفة'
                        : state.currentShift?.status == 'CLOSED' ||
                                state.currentShift?.status == 'COMPLETED'
                            ? 'الوردية انتهت'
                            : 'الوردية جارية',
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w900,
                        fontSize: 12))
              ])),
        ]),
        const SizedBox(height: 16),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _KpiCard(
              icon: Icons.groups_outlined,
              label: 'الحضور',
              value: '${state.present} / ${state.liveRequiredWorkers}',
              note: 'نسبة الحضور ${state.attendanceRate.toStringAsFixed(1)}%',
              color: AppColors.primary,
              soft: AppColors.primarySoft),
          _KpiCard(
              icon: Icons.person_off_outlined,
              label: 'الغياب',
              value: '${state.absent}',
              note: 'يحتاج متابعة',
              color: AppColors.red,
              soft: AppColors.redSoft),
          _KpiCard(
              icon: Icons.factory_outlined,
              label: 'الإنتاج الحالي',
              value: '${state.liveActual}',
              note: 'من ${state.liveTarget} مستهدف',
              color: AppColors.ink,
              soft: const Color(0xFFE8ECE6)),
          _KpiCard(
              icon: Icons.track_changes_outlined,
              label: 'تحقيق المستهدف',
              value: '${state.liveAchievement.toStringAsFixed(1)}%',
              note: state.liveAchievement >= 100 ? 'ممتاز' : 'تحت المتابعة',
              color:
                  state.liveAchievement >= 90 ? AppColors.amber : AppColors.red,
              soft: state.liveAchievement >= 90
                  ? AppColors.amberSoft
                  : AppColors.redSoft),
          _KpiCard(
              icon: Icons.pause_circle_outline,
              label: 'إجمالي التوقف',
              value: '${state.downtime} د',
              note: '${state.openDowntime} توقف مفتوح',
              color: AppColors.amber,
              soft: AppColors.amberSoft),
          _KpiCard(
              icon: Icons.delete_outline,
              label: 'الهالك',
              value: '${state.waste} كجم',
              note: 'من الإنتاج الحالي',
              color: AppColors.violet,
              soft: AppColors.violetSoft),
          _KpiCard(
              icon: Icons.fact_check_outlined,
              label: 'نسبة الرفض',
              value: '${state.rejection.toStringAsFixed(1)}%',
              note: state.rejection > 5 ? 'تحتاج مراجعة' : 'حالة الجودة طبيعية',
              color: AppColors.primary,
              soft: AppColors.primarySoft),
          _KpiCard(
              icon: Icons.warning_amber_outlined,
              label: 'بلاغات الأعطال',
              value: '${state.maintenanceCount}',
              note: '${state.openMaintenance} بلاغ مفتوح',
              color: AppColors.red,
              soft: AppColors.redSoft),
          _KpiCard(
              icon: Icons.report_problem_outlined,
              label: 'مشاكل مفتوحة',
              value: '${state.openProblems}',
              note: '${state.problemsCount} مشكلة مسجلة',
              color:
                  state.openProblems == 0 ? AppColors.primary : AppColors.red,
              soft: state.openProblems == 0
                  ? AppColors.primarySoft
                  : AppColors.redSoft),
          _KpiCard(
              icon: Icons.thermostat_outlined,
              label: 'قراءات الثلاجات',
              value: '${state.fridgeCompleted}/${state.fridgeRequired}',
              note: state.fridgeDefrost == 0
                  ? '${state.fridgeMissing} قراءة متبقية'
                  : '${state.fridgeDefrost} Defrost',
              color:
                  state.fridgeDefrost > 0 ? AppColors.amber : AppColors.primary,
              soft: state.fridgeDefrost > 0
                  ? AppColors.amberSoft
                  : AppColors.primarySoft),
          _KpiCard(
              icon: Icons.local_shipping_outlined,
              label: 'تحميل الحاويات',
              value: '${state.containersCount}',
              note: 'عملية مرتبطة بالوردية',
              color: AppColors.ink,
              soft: const Color(0xFFE8ECE6)),
        ]),
        const SizedBox(height: 18),
        if (width >= 950)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _ProductionChart(state: state)),
            const SizedBox(width: 14),
            Expanded(child: _AlertsPanel(state: state))
          ])
        else
          Column(children: [
            _ProductionChart(state: state),
            const SizedBox(height: 14),
            _AlertsPanel(state: state)
          ]),
        const SizedBox(height: 18),
        _OperationsPanel(state: state),
        const SizedBox(height: 18),
        _DashboardEnhancements(state: state),
      ],
    );
  }
}

class _DashboardEnhancements extends StatefulWidget {
  const _DashboardEnhancements({required this.state});
  final _ShiftWorkspaceState state;
  @override
  State<_DashboardEnhancements> createState() => _DashboardEnhancementsState();
}

class _DashboardEnhancementsState extends State<_DashboardEnhancements> {
  bool loading = true;
  ProductionTotals iqf = const ProductionTotals();
  FridgeTotals fridge = const FridgeTotals();
  ReceiptTotals receipts = const ReceiptTotals();
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final values = await Future.wait([
        ApiClient.loadProduction(
            widget.state.widget.session.accessToken!, 'IQF'),
        ApiClient.loadFridgeReadings(widget.state.widget.session.accessToken!),
        ApiClient.loadReceipts(widget.state.widget.session.accessToken!)
      ]);
      if (mounted)
        setState(() {
          iqf = (values[0] as ProductionSnapshot).summary;
          fridge = (values[1] as FridgeSnapshot).summary;
          receipts = (values[2] as ReceiptSnapshot).summary;
          loading = false;
        });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => _DataPanel(
      title: 'مؤشرات التشغيل المحدثة',
      child: loading
          ? const LinearProgressIndicator()
          : Wrap(spacing: 10, runSpacing: 10, children: [
              _ProductionMetric(label: 'إنتاج IQF', value: '${iqf.actual} كجم'),
              _ProductionMetric(
                  label: 'تحقيق IQF',
                  value: '${iqf.achievement.toStringAsFixed(1)}%'),
              _ProductionMetric(
                  label: 'التزام الثلاجات',
                  value: '${fridge.compliance.toStringAsFixed(1)}%'),
              _ProductionMetric(
                  label: 'حالات Defrost', value: '${fridge.defrost}'),
              _ProductionMetric(
                  label: 'صافي الاستلامات',
                  value: '${receipts.net.toStringAsFixed(1)} كجم'),
              _ProductionMetric(
                  label: 'عدد الموردين', value: '${receipts.suppliers}')
            ]));
}

class _KpiCard extends StatelessWidget {
  const _KpiCard(
      {required this.icon,
      required this.label,
      required this.value,
      required this.note,
      required this.color,
      required this.soft});
  final IconData icon;
  final String label;
  final String value;
  final String note;
  final Color color;
  final Color soft;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: 205,
      child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
              color: Colors.white.withAlpha(235),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                      color: soft, borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, color: color, size: 19)),
              const Spacer(),
              Icon(Icons.more_horiz, color: AppColors.muted, size: 18)
            ]),
            const SizedBox(height: 12),
            Text(value,
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink)),
            const SizedBox(height: 3),
            Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink)),
            const SizedBox(height: 3),
            Text(note,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11, color: color, fontWeight: FontWeight.w700))
          ])));
}


class _ControlPanelView extends StatefulWidget {
  const _ControlPanelView({required this.state});
  final _ShiftWorkspaceState state;
  @override
  State<_ControlPanelView> createState() => _ControlPanelViewState();
}

class _ControlPanelViewState extends State<_ControlPanelView> {
  bool loading = true;
  List<Map<String, dynamic>> users = [];

  String get token => widget.state.widget.session.accessToken!;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final result = await ApiClient.users(token);
      if (mounted)
        setState(() {
          users = result;
          loading = false;
        });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final activeUsers =
        users.where((user) => (user['isActive'] as bool? ?? user['is_active'] as bool? ?? true) != false).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [AppColors.primary, Color(0xFF0B5C4D)],
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                  color: Colors.white.withAlpha(38),
                  borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.admin_panel_settings_outlined,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('لوحة تحكم المدير',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  const Text('أدوات إدارية حصرية لمدير النظام',
                      style: TextStyle(color: Color(0xFFDCEFE9), fontSize: 12)),
                ])),
          ]),
        ),
        const SizedBox(height: 16),
        if (loading) const LinearProgressIndicator(),
        const SizedBox(height: 4),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _KpiCard(
              icon: Icons.groups_outlined,
              label: 'المستخدمون',
              value: '${users.length}',
              note: '$activeUsers حساب مُفعّل',
              color: AppColors.primary,
              soft: AppColors.primarySoft),
          _KpiCard(
              icon: Icons.inventory_2_outlined,
              label: 'رصيد المخزون',
              value: '${state.inventoryOpening} كجم',
              note: 'الرصيد الافتتاحي الحالي',
              color: AppColors.violet,
              soft: AppColors.violetSoft),
          _KpiCard(
              icon: Icons.report_problem_outlined,
              label: 'مشاكل مفتوحة',
              value: '${state.openProblems}',
              note: '${state.problemsCount} مشكلة مسجلة',
              color:
                  state.openProblems == 0 ? AppColors.primary : AppColors.red,
              soft: state.openProblems == 0
                  ? AppColors.primarySoft
                  : AppColors.redSoft),
          _KpiCard(
              icon: Icons.build_circle_outlined,
              label: 'أعطال الصيانة',
              value: '${state.maintenanceCount}',
              note: '${state.openMaintenance} بلاغ مفتوح',
              color: AppColors.amber,
              soft: AppColors.amberSoft),
          _KpiCard(
              icon: Icons.track_changes_outlined,
              label: 'تحقيق المستهدف',
              value: '${state.liveAchievement.toStringAsFixed(1)}%',
              note: 'أداء الوردية الحالية',
              color: state.liveAchievement >= 90
                  ? AppColors.primary
                  : AppColors.red,
              soft: state.liveAchievement >= 90
                  ? AppColors.primarySoft
                  : AppColors.redSoft),
          _KpiCard(
              icon: Icons.pause_circle_outline,
              label: 'إجمالي التوقف',
              value: '${state.downtime} د',
              note: '${state.openDowntime} توقف مفتوح',
              color: AppColors.amber,
              soft: AppColors.amberSoft),
        ]),
        const SizedBox(height: 22),
        const Text('إجراءات سريعة',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.ink)),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _ControlPanelAction(
              icon: Icons.manage_accounts_outlined,
              label: 'إدارة المستخدمين',
              subtitle: 'إضافة وتفعيل/تعطيل الحسابات',
              color: AppColors.primary,
              soft: AppColors.primarySoft,
              onTap: () => state._select(WorkspaceSection.users)),
          _ControlPanelAction(
              icon: Icons.tune_outlined,
              label: 'الرصيد الافتتاحي للمخزون',
              subtitle: 'تعديل رصيد بداية الفترة',
              color: AppColors.violet,
              soft: AppColors.violetSoft,
              onTap: () => state.editInventoryOpeningBalance(context)),
          _ControlPanelAction(
              icon: Icons.history_outlined,
              label: 'سجل الأحداث',
              subtitle: 'مراجعة كل العمليات المسجلة',
              color: AppColors.violet,
              soft: AppColors.violetSoft,
              onTap: () => state._select(WorkspaceSection.auditLog)),
          _ControlPanelAction(
              icon: Icons.assessment_outlined,
              label: 'التقارير',
              subtitle: 'تقارير الورديات وتصديرها',
              color: AppColors.amber,
              soft: AppColors.amberSoft,
              onTap: () => state._select(WorkspaceSection.reports)),
        ]),
      ],
    );
  }
}

class _ControlPanelAction extends StatelessWidget {
  const _ControlPanelAction({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.soft,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final Color soft;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
      width: 250,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: Colors.white.withAlpha(235),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border)),
          child: Row(children: [
            Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: soft, borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 21)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style:
                          const TextStyle(fontSize: 11, color: AppColors.muted)),
                ])),
            const Icon(Icons.chevron_left, color: AppColors.muted, size: 18),
          ]),
        ),
      ));
}

class _ProductionChart extends StatelessWidget {
  const _ProductionChart({required this.state});
  final _ShiftWorkspaceState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(235),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('الإنتاج لكل ساعة',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.ink)),
          const SizedBox(height: 4),
          const Text('مقارنة المستهدف بالإنتاج الفعلي لخط 01',
              style: TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 18),
          SizedBox(
            height: 180,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (final item in state.hourly) _ChartBar(item: item)
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.square, color: AppColors.primary, size: 10),
              SizedBox(width: 4),
              Text('فعلي',
                  style: TextStyle(fontSize: 11, color: AppColors.muted)),
              SizedBox(width: 14),
              Icon(Icons.square, color: AppColors.border, size: 10),
              SizedBox(width: 4),
              Text('مستهدف',
                  style: TextStyle(fontSize: 11, color: AppColors.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChartBar extends StatelessWidget {
  const _ChartBar({required this.item});
  final HourlyProduction item;
  @override
  Widget build(BuildContext context) {
    final height = (item.actual / 1000 * 135).clamp(24, 135).toDouble();
    return Column(mainAxisAlignment: MainAxisAlignment.end, children: [
      Text('${item.actual}',
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Container(
          width: 28,
          height: height,
          decoration: BoxDecoration(
              color:
                  item.achievement >= 90 ? AppColors.primary : AppColors.amber,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(5))),
          child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                  width: 28, height: 4, color: AppColors.ink.withAlpha(100)))),
      const SizedBox(height: 6),
      Text(item.hour,
          style: const TextStyle(fontSize: 10, color: AppColors.muted))
    ]);
  }
}

class _AlertsPanel extends StatelessWidget {
  const _AlertsPanel({required this.state});
  final _ShiftWorkspaceState state;

  @override
  Widget build(BuildContext context) {
    final rows = state.dashboardNotifications;
    return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white.withAlpha(235),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.notifications_active_outlined,
                color: AppColors.ink),
            const SizedBox(width: 8),
            const Text('التنبيهات الحالية',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink)),
            const Spacer(),
            Text('${rows.length} جديدة',
                style: const TextStyle(
                    color: AppColors.red,
                    fontWeight: FontWeight.w900,
                    fontSize: 12))
          ]),
          const SizedBox(height: 14),
          if (rows.isEmpty)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text('لا توجد تنبيهات مفتوحة حاليًا',
                    style: TextStyle(color: AppColors.muted))),
          for (final row in rows.take(5))
            _AlertRow(
                icon: _alertIcon(row['title']?.toString() ?? ''),
                title: row['title']?.toString() ?? 'تنبيه',
                detail: row['body']?.toString() ?? '',
                color: row['severity'] == 'CRITICAL'
                    ? AppColors.red
                    : AppColors.amber)
        ]));
  }

  IconData _alertIcon(String title) {
    if (title.contains('إنتاج')) return Icons.trending_down;
    if (title.contains('توقف')) return Icons.pause_circle_outline;
    if (title.contains('عطل')) return Icons.build_outlined;
    if (title.contains('ثلاجة') || title.contains('Defrost')) {
      return Icons.thermostat_outlined;
    }
    return Icons.info_outline;
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow(
      {required this.icon,
      required this.title,
      required this.detail,
      required this.color});
  final IconData icon;
  final String title;
  final String detail;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: color.withAlpha(18), borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 9),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: AppColors.ink)),
          const SizedBox(height: 3),
          Text(detail,
              style: const TextStyle(color: AppColors.muted, fontSize: 11))
        ])),
        Icon(Icons.chevron_left, color: color, size: 18)
      ]));
}

class _OperationsPanel extends StatelessWidget {
  const _OperationsPanel({required this.state});
  final _ShiftWorkspaceState state;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white.withAlpha(235),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Text('حالة أقسام الوردية',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.ink)),
          Spacer(),
          Text('آخر تحديث الآن',
              style: TextStyle(color: AppColors.muted, fontSize: 11))
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _DepartmentStatus(
              name: 'الأمن',
              status: 'مكتمل',
              detail: '${state.present} حاضر',
              color: AppColors.primary,
              icon: Icons.shield_outlined),
          _DepartmentStatus(
              name: 'الإنتاج',
              status: 'يحتاج متابعة',
              detail: '${state.achievement.toStringAsFixed(1)}% تحقيق',
              color: AppColors.amber,
              icon: Icons.factory_outlined),
          _DepartmentStatus(
              name: 'الجودة',
              status: 'طبيعي',
              detail: '${state.rejection}% رفض',
              color: AppColors.primary,
              icon: Icons.verified_outlined),
          _DepartmentStatus(
              name: 'الصيانة',
              status: 'بلاغ مفتوح',
              detail: '2 بلاغ',
              color: AppColors.red,
              icon: Icons.build_outlined),
          _DepartmentStatus(
              name: 'المخزن',
              status: 'طبيعي',
              detail: 'رصيد كافٍ',
              color: AppColors.primary,
              icon: Icons.inventory_2_outlined)
        ])
      ]));
}

class _DepartmentStatus extends StatelessWidget {
  const _DepartmentStatus(
      {required this.name,
      required this.status,
      required this.detail,
      required this.color,
      required this.icon});
  final String name;
  final String status;
  final String detail;
  final Color color;
  final IconData icon;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: 190,
      child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          leading: Icon(icon, color: color),
          title: Text(name,
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          subtitle: Text('$status · $detail',
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.w700))));
}

class _AttendanceView extends StatefulWidget {
  const _AttendanceView({required this.state});

  final _ShiftWorkspaceState state;

  @override
  State<_AttendanceView> createState() => _AttendanceViewState();
}

class _AttendanceViewState extends State<_AttendanceView> {
  final date = TextEditingController(text: '2026-08-21');
  List<AttendanceRecord> records = [];
  List<AttendanceEmployee> employees = [];
  bool loading = true;
  String department = '';
  String jobTitle = '';
  String status = '';
  AttendanceSnapshot summary = const AttendanceSnapshot(
      records: [],
      total: 0,
      present: 0,
      absent: 0,
      late: 0,
      attendanceRate: 0,
      absenceRate: 0);

  String get token => widget.state.widget.session.accessToken!;
  bool get canEdit {
    final role = widget.state.widget.session.role;
    return role == UserRole.security ||
        role == UserRole.shiftManager ||
        role == UserRole.systemAdmin;
  }

  bool get canManageEmployees => [
        UserRole.systemAdmin,
        UserRole.shiftManager,
        UserRole.security
      ].contains(widget.state.widget.session.role);

  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    date.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    setState(() => loading = true);
    try {
      final results = await Future.wait([
        ApiClient.loadAttendance(token,
            date: date.text.trim(),
            department: department,
            jobTitle: jobTitle,
            status: status),
        ApiClient.employees(token),
      ]);
      if (!mounted) return;
      final loaded = results[0] as AttendanceSnapshot;
      setState(() {
        summary = loaded;
        records = loaded.records;
        employees = results[1] as List<AttendanceEmployee>;
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => loading = false);
      widget.state._showSavedMessage('تعذر تحميل سجلات الحضور من الخادم');
    }
  }

  Future<void> editRecord(AttendanceRecord? record) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _AttendanceRecordDialog(
          employees: employees, record: record, date: date.text.trim()),
    );
    if (result == null) return;
    try {
      if (record == null) {
        await ApiClient.createAttendanceRecord(token,
            employeeId: result['employeeId'] as int,
            attendanceDate: result['attendanceDate'] as String,
            status: result['status'] as String,
            checkIn: result['checkIn'] as String?,
            checkOut: result['checkOut'] as String?,
            notes: result['notes'] as String?,
            shiftId: widget.state.currentShiftId);
      } else {
        await ApiClient.updateAttendanceRecord(token, record.id,
            status: result['status'] as String,
            checkIn: result['checkIn'] as String?,
            checkOut: result['checkOut'] as String?,
            notes: result['notes'] as String?,
            shiftId: widget.state.currentShiftId);
      }
      await refresh();
      if (mounted)
        widget.state._showSavedMessage(record == null
            ? 'تم تسجيل الحضور وتحديث النسب تلقائيًا'
            : 'تم تعديل سجل الحضور وتسجيل التغيير في سجل الأحداث');
    } catch (error) {
      if (mounted)
        widget.state._showSavedMessage(error.toString().contains('EXISTS')
            ? 'يوجد سجل لهذا الموظف في نفس التاريخ'
            : 'تعذر حفظ سجل الحضور');
    }
  }

  Future<void> addEmployee() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _EmployeeDialog(),
    );
    if (result == null) return;
    try {
      await ApiClient.createEmployee(
        token,
        employeeNo: result['employeeNo']!,
        name: result['name']!,
        department: result['department']!,
        jobTitle: result['jobTitle']!,
        category: result['category']!,
        shiftName: result['shiftName']!,
        startDate: result['startDate']!.isEmpty ? null : result['startDate'],
        notes: result['notes']!.isEmpty ? null : result['notes'],
        isActive: result['isActive'] == 'true',
      );
      await refresh();
      if (mounted)
        widget.state
            ._showSavedMessage('تم إضافة الموظف وتسجيل العملية في سجل الأحداث');
    } catch (error) {
      if (mounted)
        widget.state._showSavedMessage(error.toString().contains('EXISTS')
            ? 'الرقم الوظيفي مستخدم بالفعل'
            : 'تعذر إضافة الموظف');
    }
  }

  Future<void> editEmployee(AttendanceEmployee employee) async {
    final result = await showDialog<Map<String, String>>(
        context: context, builder: (_) => _EmployeeDialog(initial: employee));
    if (result == null) return;
    try {
      await ApiClient.updateEmployee(token, employee.id,
          name: result['name'],
          department: result['department'],
          jobTitle: result['jobTitle'],
          category: result['category'],
          shiftName: result['shiftName'],
          startDate: result['startDate'],
          notes: result['notes'],
          isActive: result['isActive'] == 'true');
      await refresh();
      if (mounted)
        widget.state._showSavedMessage(
            'تم تعديل بيانات العامل وحفظ العملية في سجل الأحداث');
    } catch (_) {
      if (mounted) widget.state._showSavedMessage('تعذر تعديل بيانات العامل');
    }
  }

  @override
  Widget build(BuildContext context) {
    final departments =
        employees.map((item) => item.department).toSet().toList()..sort();
    final jobs = employees.map((item) => item.jobTitle).toSet().toList()
      ..sort();
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: [
        Row(children: [
          const Icon(Icons.groups_outlined, color: AppColors.primary, size: 30),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('الحضور والغياب',
                    style: TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w900,
                        color: AppColors.ink)),
                SizedBox(height: 4),
                Text(
                    'متابعة العاملين داخل الوردية مع حساب النسب من السجلات الأصلية',
                    style: TextStyle(color: AppColors.muted, fontSize: 12)),
              ])),
          if (canEdit)
            FilledButton.icon(
                onPressed: loading ? null : () => editRecord(null),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('تسجيل حضور')),
          if (canManageEmployees)
            OutlinedButton.icon(
                onPressed: loading ? null : addEmployee,
                icon: const Icon(Icons.badge_outlined),
                label: const Text('موظف جديد')),
          IconButton(
              tooltip: 'تحديث',
              onPressed: loading ? null : refresh,
              icon: const Icon(Icons.refresh)),
        ]),
        const SizedBox(height: 16),
        if (loading) const LinearProgressIndicator(),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _AttendanceMetric(
              label: 'إجمالي العاملين',
              value: '${summary.total}',
              icon: Icons.people_outline,
              color: AppColors.ink),
          _AttendanceMetric(
              label: 'الحاضرون',
              value: '${summary.present}',
              icon: Icons.check_circle_outline,
              color: AppColors.primary),
          _AttendanceMetric(
              label: 'الغائبون',
              value: '${summary.absent}',
              icon: Icons.person_off_outlined,
              color: AppColors.red),
          _AttendanceMetric(
              label: 'المتأخرون',
              value: '${summary.late}',
              icon: Icons.schedule_outlined,
              color: AppColors.amber),
          _AttendanceMetric(
              label: 'نسبة الحضور',
              value: '${summary.attendanceRate.toStringAsFixed(1)}%',
              icon: Icons.percent,
              color: AppColors.primary),
          _AttendanceMetric(
              label: 'نسبة الغياب',
              value: '${summary.absenceRate.toStringAsFixed(1)}%',
              icon: Icons.percent,
              color: AppColors.red),
        ]),
        const SizedBox(height: 14),
        if (canManageEmployees)
          _DataPanel(
              title: 'إدارة العمال',
              child: employees.isEmpty
                  ? const Text('لا يوجد عمال مسجلون',
                      style: TextStyle(color: AppColors.muted))
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: employees
                          .map((employee) => ActionChip(
                                avatar:
                                    const Icon(Icons.person_outline, size: 18),
                                label: Text(
                                    '${employee.name} · ${employee.employeeNo}${employee.isActive ? '' : ' · غير فعال'}'),
                                backgroundColor: employee.isActive
                                    ? null
                                    : AppColors.redSoft,
                                onPressed: () => editEmployee(employee),
                              ))
                          .toList())),
        if (canManageEmployees) const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: Colors.white.withAlpha(235),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border)),
          child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                    width: 150,
                    child: TextField(
                        controller: date,
                        decoration: const InputDecoration(
                            labelText: 'التاريخ',
                            prefixIcon: Icon(Icons.calendar_today_outlined)),
                        onSubmitted: (_) => refresh())),
                _AttendanceFilter(
                    label: 'القسم',
                    value: department,
                    values: departments,
                    onChanged: (value) {
                      setState(() => department = value);
                      refresh();
                    }),
                _AttendanceFilter(
                    label: 'الوظيفة',
                    value: jobTitle,
                    values: jobs,
                    onChanged: (value) {
                      setState(() => jobTitle = value);
                      refresh();
                    }),
                _AttendanceFilter(
                    label: 'الحالة',
                    value: status,
                    values: const [
                      'PRESENT',
                      'LATE',
                      'MISSION',
                      'LEAVE',
                      'ABSENT_EXCUSED',
                      'ABSENT_UNEXCUSED'
                    ],
                    labels: true,
                    onChanged: (value) {
                      setState(() => status = value);
                      refresh();
                    }),
                FilledButton.icon(
                    onPressed: loading ? null : refresh,
                    icon: const Icon(Icons.filter_alt_outlined),
                    label: const Text('تطبيق الفلتر')),
              ]),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: Colors.white.withAlpha(235),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('سجل العاملين',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink)),
            const SizedBox(height: 10),
            if (!loading && records.isEmpty)
              const Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('لا توجد سجلات مطابقة للفلاتر',
                      style: TextStyle(color: AppColors.muted))),
            if (records.isNotEmpty)
              SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor:
                        const WidgetStatePropertyAll(AppColors.background),
                    columns: const [
                      DataColumn(label: Text('الموظف')),
                      DataColumn(label: Text('القسم')),
                      DataColumn(label: Text('الوظيفة')),
                      DataColumn(label: Text('الحالة')),
                      DataColumn(label: Text('الحضور')),
                      DataColumn(label: Text('الانصراف')),
                      DataColumn(label: Text('ملاحظات')),
                      DataColumn(label: Text('إجراء'))
                    ],
                    rows: records
                        .map((item) => DataRow(cells: [
                              DataCell(Text(
                                  '${item.employeeName}\n${item.employeeNo}')),
                              DataCell(Text(item.department)),
                              DataCell(Text(item.jobTitle)),
                              DataCell(Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 5),
                                  decoration: BoxDecoration(
                                      color: attendanceStatusColor(item.status)
                                          .withAlpha(25),
                                      borderRadius: BorderRadius.circular(6)),
                                  child: Text(
                                      attendanceStatusLabel(item.status),
                                      style: TextStyle(
                                          color: attendanceStatusColor(
                                              item.status),
                                          fontWeight: FontWeight.w800)))),
                              DataCell(Text(item.checkIn ?? '-')),
                              DataCell(Text(item.checkOut ?? '-')),
                              DataCell(Text(item.notes?.isNotEmpty == true
                                  ? item.notes!
                                  : '-')),
                              DataCell(canEdit
                                  ? IconButton(
                                      tooltip: 'تعديل السجل',
                                      onPressed: () => editRecord(item),
                                      icon: const Icon(Icons.edit_outlined))
                                  : const Icon(Icons.lock_outline,
                                      size: 18, color: AppColors.muted)),
                            ]))
                        .toList(),
                  )),
          ]),
        ),
      ],
    );
  }
}

class _AttendanceMetric extends StatelessWidget {
  const _AttendanceMetric(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
      width: 158,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Colors.white.withAlpha(235),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border)),
        child: Row(children: [
          Icon(icon, color: color, size: 21),
          const SizedBox(width: 9),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(label,
                    style:
                        const TextStyle(color: AppColors.muted, fontSize: 11)),
                const SizedBox(height: 5),
                Text(value,
                    style: TextStyle(
                        color: color,
                        fontSize: 21,
                        fontWeight: FontWeight.w900))
              ]))
        ]),
      ));
}

class _AttendanceFilter extends StatelessWidget {
  const _AttendanceFilter(
      {required this.label,
      required this.value,
      required this.values,
      required this.onChanged,
      this.labels = false});
  final String label;
  final String value;
  final List<String> values;
  final ValueChanged<String> onChanged;
  final bool labels;

  @override
  Widget build(BuildContext context) => SizedBox(
      width: 165,
      child: DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(
            labelText: label,
            prefixIcon: const Icon(Icons.filter_alt_outlined)),
        items: [
          DropdownMenuItem(value: '', child: Text('كل $label')),
          ...values.map((item) => DropdownMenuItem(
              value: item,
              child: Text(labels ? attendanceStatusLabel(item) : item)))
        ],
        onChanged: (next) => onChanged(next ?? ''),
      ));
}

class _EmployeeDialog extends StatefulWidget {
  const _EmployeeDialog({this.initial});
  final AttendanceEmployee? initial;

  @override
  State<_EmployeeDialog> createState() => _EmployeeDialogState();
}

class _EmployeeDialogState extends State<_EmployeeDialog> {
  late final employeeNo =
      TextEditingController(text: widget.initial?.employeeNo ?? '');
  late final name = TextEditingController(text: widget.initial?.name ?? '');
  late final department =
      TextEditingController(text: widget.initial?.department ?? '');
  late final jobTitle =
      TextEditingController(text: widget.initial?.jobTitle ?? '');
  late final category =
      TextEditingController(text: widget.initial?.category ?? 'عمال');
  late final shiftName =
      TextEditingController(text: widget.initial?.shiftName ?? 'الثانية');
  late final startDate =
      TextEditingController(text: widget.initial?.startDate ?? '');
  late final notes = TextEditingController(text: widget.initial?.notes ?? '');
  late bool isActive = widget.initial?.isActive ?? true;

  @override
  void dispose() {
    employeeNo.dispose();
    name.dispose();
    department.dispose();
    jobTitle.dispose();
    category.dispose();
    shiftName.dispose();
    startDate.dispose();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title:
            Text(widget.initial == null ? 'إضافة موظف' : 'تعديل بيانات العامل'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 440,
            child: Column(children: [
              TextField(
                  controller: employeeNo,
                  decoration: const InputDecoration(
                      labelText: 'الرقم الوظيفي',
                      prefixIcon: Icon(Icons.badge_outlined))),
              const SizedBox(height: 10),
              TextField(
                  controller: name,
                  decoration: const InputDecoration(
                      labelText: 'الاسم',
                      prefixIcon: Icon(Icons.person_outline))),
              const SizedBox(height: 10),
              TextField(
                  controller: department,
                  decoration: const InputDecoration(
                      labelText: 'القسم',
                      prefixIcon: Icon(Icons.account_tree_outlined))),
              const SizedBox(height: 10),
              TextField(
                  controller: jobTitle,
                  decoration: const InputDecoration(
                      labelText: 'الوظيفة',
                      prefixIcon: Icon(Icons.work_outline))),
              const SizedBox(height: 10),
              TextField(
                  controller: category,
                  decoration: const InputDecoration(
                      labelText: 'الفئة',
                      prefixIcon: Icon(Icons.category_outlined))),
              const SizedBox(height: 10),
              TextField(
                  controller: shiftName,
                  decoration: const InputDecoration(
                      labelText: 'الوردية',
                      prefixIcon: Icon(Icons.schedule_outlined))),
              const SizedBox(height: 10),
              TextField(
                  controller: startDate,
                  decoration: const InputDecoration(
                      labelText: 'تاريخ بدء العمل',
                      prefixIcon: Icon(Icons.event_outlined))),
              const SizedBox(height: 10),
              TextField(
                  controller: notes,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'ملاحظات',
                      prefixIcon: Icon(Icons.notes_outlined))),
              if (widget.initial != null)
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('العامل فعال'),
                    value: isActive,
                    onChanged: (value) => setState(() => isActive = value)),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          FilledButton(
            onPressed: () {
              if ([name, department, jobTitle, category, shiftName]
                  .any((field) => field.text.trim().isEmpty)) return;
              Navigator.pop(context, {
                'employeeNo': employeeNo.text.trim(),
                'name': name.text.trim(),
                'department': department.text.trim(),
                'jobTitle': jobTitle.text.trim(),
                'category': category.text.trim(),
                'shiftName': shiftName.text.trim(),
                'startDate': startDate.text.trim(),
                'notes': notes.text.trim(),
                'isActive': isActive.toString(),
              });
            },
            child: const Text('حفظ'),
          ),
        ],
      );
}

class _AttendanceRecordDialog extends StatefulWidget {
  const _AttendanceRecordDialog(
      {required this.employees, required this.record, required this.date});
  final List<AttendanceEmployee> employees;
  final AttendanceRecord? record;
  final String date;

  @override
  State<_AttendanceRecordDialog> createState() =>
      _AttendanceRecordDialogState();
}

class _AttendanceRecordDialogState extends State<_AttendanceRecordDialog> {
  late final date =
      TextEditingController(text: widget.record?.attendanceDate ?? widget.date);
  late final checkIn =
      TextEditingController(text: widget.record?.checkIn ?? '');
  late final checkOut =
      TextEditingController(text: widget.record?.checkOut ?? '');
  late final notes = TextEditingController(text: widget.record?.notes ?? '');
  int? employeeId;
  late String status = widget.record?.status ?? 'PRESENT';

  @override
  void initState() {
    super.initState();
    employeeId = widget.record?.employeeId;
  }

  @override
  void dispose() {
    date.dispose();
    checkIn.dispose();
    checkOut.dispose();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(
            widget.record == null ? 'تسجيل حضور عامل' : 'تعديل سجل الحضور'),
        content: SingleChildScrollView(
            child: SizedBox(
                width: 460,
                child: Column(children: [
                  DropdownButtonFormField<int>(
                      value: employeeId,
                      decoration: const InputDecoration(
                          labelText: 'الموظف',
                          prefixIcon: Icon(Icons.person_outline)),
                      items: widget.employees
                          .map((employee) => DropdownMenuItem(
                              value: employee.id,
                              child: Text(
                                  '${employee.name} · ${employee.employeeNo}')))
                          .toList(),
                      onChanged: widget.record == null
                          ? (value) => setState(() => employeeId = value)
                          : null),
                  const SizedBox(height: 10),
                  TextField(
                      controller: date,
                      decoration: const InputDecoration(
                          labelText: 'التاريخ',
                          prefixIcon: Icon(Icons.calendar_today_outlined))),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                      value: status,
                      decoration: const InputDecoration(
                          labelText: 'الحالة',
                          prefixIcon: Icon(Icons.fact_check_outlined)),
                      items: const [
                        'PRESENT',
                        'LATE',
                        'MISSION',
                        'LEAVE',
                        'ABSENT_EXCUSED',
                        'ABSENT_UNEXCUSED'
                      ]
                          .map((item) => DropdownMenuItem(
                              value: item,
                              child: Text(item == 'PRESENT'
                                  ? 'حاضر'
                                  : item == 'LATE'
                                      ? 'متأخر'
                                      : item == 'MISSION'
                                          ? 'مأمورية'
                                          : item == 'LEAVE'
                                              ? 'إجازة'
                                              : item == 'ABSENT_EXCUSED'
                                                  ? 'غياب بعذر'
                                                  : 'غياب بدون عذر')))
                          .toList(),
                      onChanged: (value) =>
                          setState(() => status = value ?? status)),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                        child: TextField(
                            controller: checkIn,
                            decoration: const InputDecoration(
                                labelText: 'وقت الحضور',
                                prefixIcon: Icon(Icons.login_outlined)))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: TextField(
                            controller: checkOut,
                            decoration: const InputDecoration(
                                labelText: 'وقت الانصراف',
                                prefixIcon: Icon(Icons.logout_outlined))))
                  ]),
                  const SizedBox(height: 10),
                  TextField(
                      controller: notes,
                      maxLines: 2,
                      decoration: const InputDecoration(
                          labelText: 'ملاحظات',
                          prefixIcon: Icon(Icons.notes_outlined))),
                ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () {
                if ((widget.record == null && employeeId == null) ||
                    date.text.trim().isEmpty) return;
                Navigator.pop(context, {
                  'employeeId': employeeId,
                  'attendanceDate': date.text.trim(),
                  'status': status,
                  'checkIn':
                      checkIn.text.trim().isEmpty ? null : checkIn.text.trim(),
                  'checkOut': checkOut.text.trim().isEmpty
                      ? null
                      : checkOut.text.trim(),
                  'notes': notes.text.trim().isEmpty ? null : notes.text.trim()
                });
              },
              child: const Text('حفظ'))
        ],
      );
}

class _ProductionWorkspaceView extends StatefulWidget {
  const _ProductionWorkspaceView({required this.state});
  final _ShiftWorkspaceState state;
  @override
  State<_ProductionWorkspaceView> createState() =>
      _ProductionWorkspaceViewState();
}

class _ProductionWorkspaceViewState extends State<_ProductionWorkspaceView> {
  String department = 'PACKING';
  bool loading = true;
  ProductionSnapshot snapshot =
      const ProductionSnapshot(rows: [], summary: ProductionTotals());
  String get token => widget.state.widget.session.accessToken!;
  bool get canEdit => [
        UserRole.production,
        UserRole.productionEngineer,
        UserRole.shiftManager,
        UserRole.systemAdmin
      ].contains(widget.state.widget.session.role);
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    setState(() => loading = true);
    try {
      final value = await ApiClient.loadProduction(token, department);
      if (!mounted) return;
      setState(() {
        snapshot = value;
        loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => loading = false);
        widget.state._showSavedMessage('تعذر تحميل إنتاج القسم');
      }
    }
  }

  Future<void> add() async {
    final result = await showDialog<ProductionEntry>(
        context: context,
        builder: (_) => _ProductionEntryDialog(department: department));
    if (result == null) return;
    try {
      await ApiClient.createProduction(token, result);
      await refresh();
      if (mounted)
        widget.state._showSavedMessage(
            'تم تسجيل إنتاج الساعة وحساب الفرق ونسبة التحقيق');
    } catch (_) {
      if (mounted) widget.state._showSavedMessage('تعذر حفظ إنتاج الساعة');
    }
  }

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 28), children: [
        Row(children: [
          const Icon(Icons.factory_outlined,
              color: AppColors.primary, size: 30),
          const SizedBox(width: 10),
          const Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('الإنتاج بالساعة',
                    style: TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w900,
                        color: AppColors.ink)),
                SizedBox(height: 4),
                Text('اختر القسم بوضوح قبل تسجيل بيانات الإنتاج',
                    style: TextStyle(color: AppColors.muted, fontSize: 12))
              ])),
          if (canEdit)
            FilledButton.icon(
                onPressed: loading ? null : add,
                icon: const Icon(Icons.add_chart),
                label: const Text('إنتاج جديد')),
          IconButton(
              tooltip: 'تحديث',
              onPressed: loading ? null : refresh,
              icon: const Icon(Icons.refresh))
        ]),
        const SizedBox(height: 16),
        ToggleButtons(
            isSelected: [department == 'PACKING', department == 'IQF'],
            onPressed: (index) {
              setState(() => department = index == 0 ? 'PACKING' : 'IQF');
              refresh();
            },
            borderRadius: BorderRadius.circular(8),
            selectedColor: Colors.white,
            fillColor: AppColors.primary,
            children: const [
              Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Text('التعبئة – Packing',
                      style: TextStyle(fontWeight: FontWeight.w800))),
              Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Text('IQF – Individual Quick Freezing',
                      style: TextStyle(fontWeight: FontWeight.w800)))
            ]),
        const SizedBox(height: 14),
        if (loading) const LinearProgressIndicator(),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _ProductionMetric(
              label: 'إجمالي الإنتاج', value: '${snapshot.summary.actual} كجم'),
          _ProductionMetric(
              label: 'المستهدف', value: '${snapshot.summary.target} كجم'),
          _ProductionMetric(
              label: 'نسبة التحقيق',
              value: '${snapshot.summary.achievement.toStringAsFixed(1)}%'),
          _ProductionMetric(
              label: 'وقت التوقف', value: '${snapshot.summary.downtime} دقيقة'),
          _ProductionMetric(
              label: 'ساعات التشغيل', value: '${snapshot.summary.hours}'),
          _ProductionMetric(
              label: 'المنتجات المشغلة', value: '${snapshot.summary.products}')
        ]),
        const SizedBox(height: 14),
        _DataPanel(
            title: department == 'PACKING'
                ? 'سجل التعبئة – Packing'
                : 'سجل IQF – Individual Quick Freezing',
            child: snapshot.rows.isEmpty
                ? const Text('لا توجد بيانات إنتاج لهذا القسم',
                    style: TextStyle(color: AppColors.muted))
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                        columns: const [
                          DataColumn(label: Text('الساعة')),
                          DataColumn(label: Text('المنتج')),
                          DataColumn(label: Text('الخط')),
                          DataColumn(label: Text('الماكينة')),
                          DataColumn(label: Text('العمال')),
                          DataColumn(label: Text('المستهدف')),
                          DataColumn(label: Text('الفعلي')),
                          DataColumn(label: Text('الفرق')),
                          DataColumn(label: Text('التحقيق')),
                          DataColumn(label: Text('التوقف'))
                        ],
                        rows: snapshot.rows
                            .map((row) => DataRow(cells: [
                                  DataCell(Text(row.hour)),
                                  DataCell(Text(row.product)),
                                  DataCell(Text(row.line)),
                                  DataCell(Text(
                                      row.machine.isEmpty ? '-' : row.machine)),
                                  DataCell(Text('${row.workers}')),
                                  DataCell(Text('${row.target}')),
                                  DataCell(Text('${row.actual}')),
                                  DataCell(Text('${row.difference}')),
                                  DataCell(Text(
                                      '${row.achievement.toStringAsFixed(1)}%')),
                                  DataCell(Text('${row.downtime} د'))
                                ]))
                            .toList())))
      ]);
}

class _ProductionMetric extends StatelessWidget {
  const _ProductionMetric({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: 158,
      child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: Colors.white.withAlpha(235),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            const SizedBox(height: 6),
            Text(value,
                style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink))
          ])));
}

class _DataPanel extends StatelessWidget {
  const _DataPanel({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white.withAlpha(235),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        child
      ]));
}

class _ProductionEntryDialog extends StatefulWidget {
  const _ProductionEntryDialog({required this.department});
  final String department;
  @override
  State<_ProductionEntryDialog> createState() => _ProductionEntryDialogState();
}

class _ProductionEntryDialogState extends State<_ProductionEntryDialog> {
  final hour = TextEditingController(text: '21:00'),
      line = TextEditingController(text: 'LINE-01'),
      machine = TextEditingController(),
      product = TextEditingController(),
      workers = TextEditingController(text: '0'),
      target = TextEditingController(text: '0'),
      actual = TextEditingController(text: '0'),
      downtime = TextEditingController(text: '0'),
      downtimeReason = TextEditingController(),
      notes = TextEditingController();
  @override
  void dispose() {
    for (final controller in [
      hour,
      line,
      machine,
      product,
      workers,
      target,
      actual,
      downtime,
      downtimeReason,
      notes
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.department == 'PACKING'
              ? 'إنتاج التعبئة – Packing'
              : 'إنتاج IQF'),
          content: SingleChildScrollView(
              child: SizedBox(
                  width: 480,
                  child: Column(children: [
                    _DialogInput(controller: hour, label: 'الساعة'),
                    _DialogInput(controller: product, label: 'المنتج'),
                    _DialogInput(controller: line, label: 'خط الإنتاج'),
                    _DialogInput(controller: machine, label: 'الماكينة'),
                    Row(children: [
                      Expanded(
                          child: _DialogInput(
                              controller: workers,
                              label: 'عدد العمال',
                              numeric: true)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _DialogInput(
                              controller: target,
                              label: 'المستهدف',
                              numeric: true)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _DialogInput(
                              controller: actual,
                              label: 'الإنتاج الفعلي',
                              numeric: true))
                    ]),
                    Row(children: [
                      Expanded(
                          child: _DialogInput(
                              controller: downtime,
                              label: 'التوقف بالدقائق',
                              numeric: true)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _DialogInput(
                              controller: downtimeReason, label: 'سبب التوقف'))
                    ]),
                    _DialogInput(controller: notes, label: 'ملاحظات')
                  ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () {
                  final targetValue = int.tryParse(target.text) ?? 0,
                      actualValue = int.tryParse(actual.text) ?? 0;
                  if (product.text.trim().isEmpty ||
                      line.text.trim().isEmpty ||
                      targetValue <= 0 ||
                      actualValue < 0) return;
                  Navigator.pop(
                      context,
                      ProductionEntry(
                          department: widget.department,
                          hour: hour.text.trim(),
                          line: line.text.trim(),
                          machine: machine.text.trim(),
                          product: product.text.trim(),
                          workers: int.tryParse(workers.text) ?? 0,
                          target: targetValue,
                          actual: actualValue,
                          downtime: int.tryParse(downtime.text) ?? 0,
                          downtimeReason: downtimeReason.text.trim(),
                          notes: notes.text.trim()));
                },
                child: const Text('حفظ'))
          ]);
}

class _DialogInput extends StatelessWidget {
  const _DialogInput(
      {required this.controller, required this.label, this.numeric = false});
  final TextEditingController controller;
  final String label;
  final bool numeric;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: TextField(
          controller: controller,
          keyboardType: numeric ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(
              labelText: label,
              prefixIcon:
                  Icon(numeric ? Icons.numbers : Icons.edit_outlined))));
}

class _ProductGuideView extends StatefulWidget {
  const _ProductGuideView({required this.state});
  final _ShiftWorkspaceState state;
  @override
  State<_ProductGuideView> createState() => _ProductGuideViewState();
}

class _ProductGuideViewState extends State<_ProductGuideView> {
  final search = TextEditingController();
  String department = '';
  bool loading = true;
  List<ProductGuide> guides = [];
  String get token => widget.state.widget.session.accessToken!;
  bool get canEdit => [
        UserRole.production,
        UserRole.productionEngineer,
        UserRole.systemAdmin
      ].contains(widget.state.widget.session.role);
  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    setState(() => loading = true);
    try {
      final rows = await ApiClient.loadProductGuides(token,
          query: search.text.trim(), department: department);
      if (mounted)
        setState(() {
          guides = rows;
          loading = false;
        });
    } catch (_) {
      if (mounted) {
        setState(() => loading = false);
        widget.state._showSavedMessage('تعذر تحميل دليل المنتجات');
      }
    }
  }

  Future<void> add() async {
    final result = await showDialog<ProductGuide>(
        context: context, builder: (_) => const _ProductGuideDialog());
    if (result == null) return;
    try {
      await ApiClient.createProductGuide(token, result);
      await refresh();
      if (mounted) widget.state._showSavedMessage('تم حفظ دليل المنتج');
    } catch (_) {
      if (mounted) widget.state._showSavedMessage('تعذر حفظ دليل المنتج');
    }
  }

  Future<void> edit(ProductGuide guide) async {
    final result = await showDialog<ProductGuide>(
        context: context, builder: (_) => _ProductGuideDialog(initial: guide));
    if (result == null) return;
    try {
      await ApiClient.updateProductGuide(token, result);
      await refresh();
      if (mounted) widget.state._showSavedMessage('تم تحديث دليل المنتج');
    } catch (_) {
      if (mounted) widget.state._showSavedMessage('تعذر تحديث دليل المنتج');
    }
  }

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 28), children: [
        Row(children: [
          const Icon(Icons.menu_book_outlined,
              color: AppColors.primary, size: 30),
          const SizedBox(width: 10),
          const Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('دليل تشغيل المنتجات',
                    style:
                        TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
                SizedBox(height: 4),
                Text('مرجع المواصفات وخطوات التشغيل بدون افتراض قيم تشغيلية',
                    style: TextStyle(color: AppColors.muted, fontSize: 12))
              ])),
          if (canEdit)
            FilledButton.icon(
                onPressed: add,
                icon: const Icon(Icons.add),
                label: const Text('منتج جديد'))
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
              child: TextField(
                  controller: search,
                  onSubmitted: (_) => refresh(),
                  decoration: const InputDecoration(
                      labelText: 'البحث بالاسم أو الكود',
                      prefixIcon: Icon(Icons.search)))),
          const SizedBox(width: 10),
          DropdownButton<String>(
              value: department,
              items: const [
                DropdownMenuItem(value: '', child: Text('كل الأقسام')),
                DropdownMenuItem(
                    value: 'PACKING', child: Text('التعبئة – Packing')),
                DropdownMenuItem(value: 'IQF', child: Text('IQF'))
              ],
              onChanged: (value) {
                setState(() => department = value ?? '');
                refresh();
              }),
          IconButton(
              tooltip: 'بحث',
              onPressed: refresh,
              icon: const Icon(Icons.search))
        ]),
        const SizedBox(height: 14),
        if (loading) const LinearProgressIndicator(),
        ...guides.map((guide) => _ProductGuideCard(
            guide: guide, canEdit: canEdit, onEdit: () => edit(guide)))
      ]);
}

class _ProductGuideCard extends StatelessWidget {
  const _ProductGuideCard(
      {required this.guide, required this.canEdit, required this.onEdit});
  final ProductGuide guide;
  final bool canEdit;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) => Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
          leading: Icon(
              guide.department == 'IQF'
                  ? Icons.ac_unit_outlined
                  : Icons.inventory_2_outlined,
              color: AppColors.primary),
          title: Text(guide.name,
              style: const TextStyle(fontWeight: FontWeight.w900)),
          subtitle: Text(
              '${guide.code} · ${guide.department == 'IQF' ? 'IQF – Individual Quick Freezing' : 'التعبئة – Packing'}'),
          trailing: canEdit
              ? IconButton(
                  tooltip: 'تعديل دليل المنتج',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined))
              : null,
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
          children: [
            Wrap(spacing: 14, runSpacing: 8, children: [
              Text(
                  'الخامة: ${guide.rawMaterial.isEmpty ? 'غير محدد' : guide.rawMaterial}'),
              Text('وزن العبوة: ${guide.packWeight?.toString() ?? 'غير محدد'}'),
              Text('المقاس: ${guide.size.isEmpty ? 'غير محدد' : guide.size}'),
              Text('الحرارة: ${guide.temperature ?? 'غير محدد'}'),
              Text('سرعة الخط: ${guide.lineSpeed ?? 'غير محدد'}')
            ]),
            const SizedBox(height: 10),
            if (guide.machineSettings.isNotEmpty)
              Align(
                  alignment: Alignment.centerRight,
                  child: Text('إعدادات الماكينات: ${guide.machineSettings}')),
            if (guide.instructions.isNotEmpty)
              Align(
                  alignment: Alignment.centerRight,
                  child: Text('تعليمات: ${guide.instructions}')),
            const Align(
                alignment: Alignment.centerRight,
                child: Text('طريقة التشغيل',
                    style: TextStyle(fontWeight: FontWeight.w900))),
            ...guide.steps.asMap().entries.map((entry) => Align(
                alignment: Alignment.centerRight,
                child: Text('${entry.key + 1}. ${entry.value}')))
          ]));
}

class _ProductGuideDialog extends StatefulWidget {
  const _ProductGuideDialog({this.initial});
  final ProductGuide? initial;
  @override
  State<_ProductGuideDialog> createState() => _ProductGuideDialogState();
}

class _ProductGuideDialogState extends State<_ProductGuideDialog> {
  final code = TextEditingController(),
      name = TextEditingController(),
      raw = TextEditingController(),
      weight = TextEditingController(),
      size = TextEditingController(),
      temperature = TextEditingController(),
      speed = TextEditingController(),
      machine = TextEditingController(),
      time = TextEditingController(),
      instructions = TextEditingController(),
      steps = TextEditingController();
  String department = 'PACKING';

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial == null) return;
    code.text = initial.code;
    name.text = initial.name;
    department = initial.department;
    raw.text = initial.rawMaterial;
    weight.text = initial.packWeight?.toString() ?? '';
    size.text = initial.size;
    temperature.text = initial.temperature ?? '';
    speed.text = initial.lineSpeed ?? '';
    machine.text = initial.machineSettings;
    time.text = initial.operatingTime;
    instructions.text = initial.instructions;
    steps.text = initial.steps.join('\n');
  }

  @override
  void dispose() {
    for (final c in [
      code,
      name,
      raw,
      weight,
      size,
      temperature,
      speed,
      machine,
      time,
      instructions,
      steps
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.initial == null
              ? 'دليل تشغيل منتج جديد'
              : 'تعديل دليل تشغيل المنتج'),
          content: SingleChildScrollView(
              child: SizedBox(
                  width: 520,
                  child: Column(children: [
                    _DialogInput(controller: code, label: 'كود المنتج'),
                    _DialogInput(controller: name, label: 'اسم المنتج'),
                    DropdownButtonFormField<String>(
                        value: department,
                        items: const [
                          DropdownMenuItem(
                              value: 'PACKING',
                              child: Text('التعبئة – Packing')),
                          DropdownMenuItem(
                              value: 'IQF',
                              child: Text('IQF – Individual Quick Freezing'))
                        ],
                        onChanged: (value) =>
                            setState(() => department = value ?? department),
                        decoration: const InputDecoration(labelText: 'القسم')),
                    _DialogInput(controller: raw, label: 'المادة الخام'),
                    _DialogInput(controller: weight, label: 'وزن العبوة'),
                    _DialogInput(controller: size, label: 'المقاس'),
                    _DialogInput(
                        controller: temperature,
                        label: 'درجة الحرارة المطلوبة'),
                    _DialogInput(controller: speed, label: 'سرعة الخط'),
                    _DialogInput(
                        controller: machine, label: 'إعدادات الماكينات'),
                    _DialogInput(controller: time, label: 'الزمن'),
                    _DialogInput(
                        controller: instructions, label: 'التعليمات الخاصة'),
                    TextField(
                        controller: steps,
                        maxLines: 5,
                        decoration: const InputDecoration(
                            labelText: 'خطوات التشغيل، كل خطوة في سطر'))
                  ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () {
                  if (code.text.trim().isEmpty || name.text.trim().isEmpty)
                    return;
                  Navigator.pop(
                      context,
                      ProductGuide(
                          id: widget.initial?.id ?? 0,
                          code: code.text.trim(),
                          name: name.text.trim(),
                          department: department,
                          rawMaterial: raw.text.trim(),
                          packWeight: double.tryParse(weight.text),
                          size: size.text.trim(),
                          temperature: temperature.text.trim().isEmpty
                              ? null
                              : temperature.text.trim(),
                          lineSpeed: speed.text.trim().isEmpty
                              ? null
                              : speed.text.trim(),
                          machineSettings: machine.text.trim(),
                          operatingTime: time.text.trim(),
                          instructions: instructions.text.trim(),
                          steps: steps.text
                              .split('\n')
                              .map((item) => item.trim())
                              .where((item) => item.isNotEmpty)
                              .toList()));
                },
                child: const Text('حفظ'))
          ]);
}

class _FridgeQualityView extends StatefulWidget {
  const _FridgeQualityView({required this.state});
  final _ShiftWorkspaceState state;
  @override
  State<_FridgeQualityView> createState() => _FridgeQualityViewState();
}

class _FridgeQualityViewState extends State<_FridgeQualityView> {
  final date = TextEditingController(text: '2026-08-21');
  bool loading = true;
  List<Fridge> fridges = [];
  FridgeSnapshot snapshot =
      const FridgeSnapshot(rows: [], summary: FridgeTotals());
  String get token => widget.state.widget.session.accessToken!;
  bool get canEdit => [
        UserRole.quality,
        UserRole.qualityEngineer,
        UserRole.shiftManager,
        UserRole.systemAdmin
      ].contains(widget.state.widget.session.role);
  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    date.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    setState(() => loading = true);
    try {
      final result = await Future.wait([
        ApiClient.loadFridges(token),
        ApiClient.loadFridgeReadings(token, date: date.text.trim())
      ]);
      if (mounted)
        setState(() {
          fridges = result[0] as List<Fridge>;
          snapshot = result[1] as FridgeSnapshot;
          loading = false;
        });
    } catch (_) {
      if (mounted) {
        setState(() => loading = false);
        widget.state._showSavedMessage('تعذر تحميل قراءات الثلاجات');
      }
    }
  }

  Future<void> add() async {
    final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) =>
            _FridgeReadingDialog(fridges: fridges, date: date.text));
    if (result == null) return;
    try {
      final saved = await ApiClient.createFridgeReading(token,
          fridgeId: result['fridgeId'] as int,
          date: result['date'] as String,
          hour: result['hour'] as String,
          temperature: result['temperature'] as double,
          status: result['status'] as String,
          notes: result['notes'] as String?,
          shiftId: widget.state.currentShiftId);
      await refresh();
      if (mounted)
        widget.state._showSavedMessage(saved['defrostRequired'] == true
            ? 'تم حفظ القراءة. تنبيه: يجب تسجيل حالة Defrost'
            : 'تم حفظ قراءة الثلاجة');
    } catch (_) {
      if (mounted) widget.state._showSavedMessage('تعذر حفظ قراءة الثلاجة');
    }
  }

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 28), children: [
        Row(children: [
          const Icon(Icons.thermostat_outlined,
              color: AppColors.primary, size: 30),
          const SizedBox(width: 10),
          const Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('الجودة – قراءات الثلاجات الخمس',
                    style:
                        TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
                SizedBox(height: 4),
                Text(
                    '5 ثلاجات · المرجع التشغيلي -18°C · Defrost عند تجاوز -10°C',
                    style: TextStyle(color: AppColors.muted, fontSize: 12))
              ])),
          if (canEdit)
            FilledButton.icon(
                onPressed: add,
                icon: const Icon(Icons.add),
                label: const Text('قراءة جديدة'))
        ]),
        const SizedBox(height: 14),
        Row(children: [
          SizedBox(
              width: 160,
              child: TextField(
                  controller: date,
                  decoration: const InputDecoration(labelText: 'التاريخ'))),
          IconButton(
              tooltip: 'تحديث',
              onPressed: refresh,
              icon: const Icon(Icons.refresh))
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _ProductionMetric(
              label: 'المطلوب', value: '${snapshot.summary.required} قراءة'),
          _ProductionMetric(
              label: 'المنفذ', value: '${snapshot.summary.completed}'),
          _ProductionMetric(
              label: 'الناقص', value: '${snapshot.summary.missing}'),
          _ProductionMetric(
              label: 'نسبة الالتزام',
              value: '${snapshot.summary.compliance.toStringAsFixed(1)}%'),
          _ProductionMetric(
              label: 'Defrost', value: '${snapshot.summary.defrost}')
        ]),
        const SizedBox(height: 14),
        _DataPanel(
            title: 'حالة الثلاجات',
            child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: fridges.map((fridge) {
                  final readings = snapshot.rows
                      .where((row) => row.fridge == fridge.name)
                      .toList();
                  final latest = readings.isEmpty ? null : readings.last;
                  final isDefrost = latest?.status == 'DEFROST';
                  return SizedBox(
                      width: 205,
                      child: ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 8),
                          leading: Icon(Icons.thermostat_outlined,
                              color: latest == null
                                  ? AppColors.amber
                                  : isDefrost
                                      ? AppColors.red
                                      : AppColors.primary),
                          title: Text(fridge.no),
                          subtitle: Text(latest == null
                              ? 'قراءة ناقصة'
                              : '${latest.temperature}°C · ${isDefrost ? 'Defrost' : 'Normal'}')));
                }).toList())),
        const SizedBox(height: 14),
        _DataPanel(
            title: 'جدول الالتزام: 5 ثلاجات × 8 ساعات = 40 قراءة',
            child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                    columns: [
                      const DataColumn(label: Text('الثلاجة')),
                      ...const [
                        '16:00',
                        '17:00',
                        '18:00',
                        '19:00',
                        '20:00',
                        '21:00',
                        '22:00',
                        '23:00'
                      ].map((hour) => DataColumn(label: Text(hour)))
                    ],
                    rows: fridges.map((fridge) {
                      final values = [
                        '16:00',
                        '17:00',
                        '18:00',
                        '19:00',
                        '20:00',
                        '21:00',
                        '22:00',
                        '23:00'
                      ];
                      return DataRow(cells: [
                        DataCell(Text(fridge.no)),
                        ...values.map((hour) {
                          final row = snapshot.rows
                              .cast<FridgeReading?>()
                              .firstWhere(
                                  (item) =>
                                      item?.fridge == fridge.name &&
                                      (item?.hour ?? '').startsWith(hour),
                                  orElse: () => null);
                          return DataCell(Icon(
                              row == null
                                  ? Icons.remove_circle_outline
                                  : Icons.check_circle_outline,
                              size: 19,
                              color: row == null
                                  ? AppColors.amber
                                  : AppColors.primary));
                        })
                      ]);
                    }).toList()))),
        const SizedBox(height: 14),
        _DataPanel(
            title: 'سجل قراءات الثلاجات',
            child: snapshot.rows.isEmpty
                ? const Text('لا توجد قراءات لهذا التاريخ',
                    style: TextStyle(color: AppColors.muted))
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                        columns: const [
                          DataColumn(label: Text('الثلاجة')),
                          DataColumn(label: Text('التاريخ')),
                          DataColumn(label: Text('الساعة')),
                          DataColumn(label: Text('الحرارة')),
                          DataColumn(label: Text('الحالة')),
                          DataColumn(label: Text('ملاحظات'))
                        ],
                        rows: snapshot.rows
                            .map((row) => DataRow(cells: [
                                  DataCell(Text(row.fridge)),
                                  DataCell(Text(row.date)),
                                  DataCell(Text(row.hour)),
                                  DataCell(Text('${row.temperature}°C')),
                                  DataCell(Text(
                                      row.status == 'DEFROST'
                                          ? 'Defrost'
                                          : 'Normal',
                                      style: TextStyle(
                                          color: row.status == 'DEFROST'
                                              ? AppColors.amber
                                              : AppColors.primary,
                                          fontWeight: FontWeight.w800))),
                                  DataCell(Text(row.notes ?? '-'))
                                ]))
                            .toList())))
      ]);
}

class _FridgeReadingDialog extends StatefulWidget {
  const _FridgeReadingDialog({required this.fridges, required this.date});
  final List<Fridge> fridges;
  final String date;
  @override
  State<_FridgeReadingDialog> createState() => _FridgeReadingDialogState();
}

class _FridgeReadingDialogState extends State<_FridgeReadingDialog> {
  int? fridgeId;
  late final date = TextEditingController(text: widget.date);
  final hour = TextEditingController(text: '21:00'),
      temperature = TextEditingController(),
      notes = TextEditingController();
  @override
  void dispose() {
    date.dispose();
    hour.dispose();
    temperature.dispose();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('قراءة ثلاجة'),
          content: SingleChildScrollView(
              child: SizedBox(
                  width: 420,
                  child: Column(children: [
                    DropdownButtonFormField<int>(
                        value: fridgeId,
                        items: widget.fridges
                            .map((fridge) => DropdownMenuItem(
                                value: fridge.id,
                                child: Text('${fridge.no} · ${fridge.name}')))
                            .toList(),
                        onChanged: (value) => setState(() => fridgeId = value),
                        decoration:
                            const InputDecoration(labelText: 'الثلاجة')),
                    _DialogInput(controller: date, label: 'التاريخ'),
                    _DialogInput(controller: hour, label: 'الساعة'),
                    _DialogInput(
                        controller: temperature, label: 'درجة الحرارة'),
                    const Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                            'الحالة تحسب تلقائيًا من درجة الحرارة: أكبر من -10°C = Defrost')),
                    _DialogInput(controller: notes, label: 'ملاحظات')
                  ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () {
                  final value = double.tryParse(temperature.text);
                  if (fridgeId == null ||
                      value == null ||
                      date.text.trim().isEmpty ||
                      hour.text.trim().isEmpty) return;
                  Navigator.pop(context, {
                    'fridgeId': fridgeId,
                    'date': date.text.trim(),
                    'hour': hour.text.trim(),
                    'temperature': value,
                    'status': value > -10 ? 'DEFROST' : 'NORMAL',
                    'notes':
                        notes.text.trim().isEmpty ? null : notes.text.trim()
                  });
                },
                child: const Text('حفظ'))
          ]);
}

class _ReceiptsView extends StatefulWidget {
  const _ReceiptsView({required this.state});
  final _ShiftWorkspaceState state;
  @override
  State<_ReceiptsView> createState() => _ReceiptsViewState();
}

class _ReceiptsViewState extends State<_ReceiptsView> {
  final from = TextEditingController(),
      to = TextEditingController(),
      supplier = TextEditingController(),
      material = TextEditingController();
  bool loading = true;
  bool packagingMode = false;
  List<Map<String, dynamic>> packagingRows = [];
  Map<String, dynamic> packagingSummary = const {};
  ReceiptSnapshot snapshot =
      const ReceiptSnapshot(rows: [], summary: ReceiptTotals());
  String get token => widget.state.widget.session.accessToken!;
  bool get canEdit => [
        UserRole.warehouse,
        UserRole.shiftManager,
        UserRole.systemAdmin
      ].contains(widget.state.widget.session.role);
  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    for (final c in [from, to, supplier, material]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> refresh() async {
    setState(() => loading = true);
    try {
      if (packagingMode) {
        final value = await ApiClient.loadPackagingReceipts(token,
            from: from.text.trim(),
            to: to.text.trim(),
            supplier: supplier.text.trim(),
            item: material.text.trim());
        if (mounted)
          setState(() {
            packagingRows = (value['rows'] as List<dynamic>? ?? const [])
                .map((row) => Map<String, dynamic>.from(row as Map))
                .toList();
            packagingSummary =
                Map<String, dynamic>.from(value['summary'] as Map? ?? const {});
            loading = false;
          });
        return;
      }
      final value = await ApiClient.loadReceipts(token,
          from: from.text.trim(),
          to: to.text.trim(),
          supplier: supplier.text.trim(),
          material: material.text.trim());
      if (mounted)
        setState(() {
          snapshot = value;
          loading = false;
        });
    } catch (_) {
      if (mounted) {
        setState(() => loading = false);
        widget.state._showSavedMessage('تعذر تحميل استلامات الخامات');
      }
    }
  }

  Future<void> add() async {
    if (packagingMode) {
      final result = await showDialog<PackagingReceipt>(
          context: context, builder: (_) => const _PackagingReceiptDialog());
      if (result == null) return;
      try {
        await ApiClient.createPackagingReceipt(token, result);
        await refresh();
        if (mounted)
          widget.state
              ._showSavedMessage('تم تسجيل استلام مواد التعبئة أو المعدات');
      } catch (_) {
        if (mounted)
          widget.state._showSavedMessage('تعذر تسجيل استلام مواد التعبئة');
      }
      return;
    }
    final result = await showDialog<RawReceipt>(
        context: context, builder: (_) => const _ReceiptDialog());
    if (result == null) return;
    try {
      await ApiClient.createReceipt(token, result);
      await refresh();
      if (mounted)
        widget.state
            ._showSavedMessage('تم تسجيل الاستلام وحساب الخصم والوزن الصافي');
    } catch (_) {
      if (mounted) widget.state._showSavedMessage('تعذر تسجيل استلام الخامة');
    }
  }

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 28), children: [
        Row(children: [
          const Icon(Icons.scale_outlined, color: AppColors.primary, size: 30),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                    packagingMode
                        ? 'استلامات مواد التعبئة والتغليف والمعدات'
                        : 'استلامات الخامات الزراعية',
                    style:
                        TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
                SizedBox(height: 4),
                Text(
                    packagingMode
                        ? 'سجل مستقل للكرتون والأكياس والمواد والمعدات'
                        : 'إجمالي الموردات والخصومات والوزن الصافي حسب الفترة والمورد والخامة',
                    style: TextStyle(color: AppColors.muted, fontSize: 12))
              ])),
          if (canEdit)
            FilledButton.icon(
                onPressed: add,
                icon: const Icon(Icons.add),
                label: const Text('استلام جديد'))
        ]),
        const SizedBox(height: 14),
        SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                  value: false,
                  label: Text('الخامات الزراعية'),
                  icon: Icon(Icons.agriculture_outlined)),
              ButtonSegment(
                  value: true,
                  label: Text('مواد التعبئة والمعدات'),
                  icon: Icon(Icons.inventory_2_outlined)),
            ],
            selected: {
              packagingMode
            },
            onSelectionChanged: (value) {
              setState(() => packagingMode = value.first);
              refresh();
            }),
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _ReceiptFilter(controller: from, label: 'من تاريخ'),
          _ReceiptFilter(controller: to, label: 'إلى تاريخ'),
          _ReceiptFilter(controller: supplier, label: 'المورد'),
          _ReceiptFilter(
              controller: material, label: packagingMode ? 'الصنف' : 'الخامة'),
          FilledButton.icon(
              onPressed: refresh,
              icon: const Icon(Icons.filter_alt_outlined),
              label: const Text('تطبيق'))
        ]),
        const SizedBox(height: 14),
        if (packagingMode) ...[
          Wrap(spacing: 10, runSpacing: 10, children: [
            _ProductionMetric(
                label: 'عدد الاستلامات',
                value: '${packagingSummary['count'] ?? 0}'),
            _ProductionMetric(
                label: 'إجمالي الكمية',
                value: '${packagingSummary['quantity'] ?? 0}'),
            _ProductionMetric(
                label: 'عدد الموردين',
                value: '${packagingSummary['suppliers'] ?? 0}')
          ]),
          const SizedBox(height: 14),
          _DataPanel(
              title: 'تفاصيل مواد التعبئة والمعدات',
              child: packagingRows.isEmpty
                  ? const Text('لا توجد استلامات مطابقة',
                      style: TextStyle(color: AppColors.muted))
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                          columns: const [
                            DataColumn(label: Text('التاريخ')),
                            DataColumn(label: Text('الصنف')),
                            DataColumn(label: Text('المورد')),
                            DataColumn(label: Text('الكمية')),
                            DataColumn(label: Text('الوحدة')),
                            DataColumn(label: Text('إذن الاستلام'))
                          ],
                          rows: packagingRows
                              .map((row) => DataRow(cells: [
                                    DataCell(Text(
                                        row['receiptDate'] as String? ?? '')),
                                    DataCell(
                                        Text(row['itemName'] as String? ?? '')),
                                    DataCell(
                                        Text(row['supplier'] as String? ?? '')),
                                    DataCell(Text('${row['quantity'] ?? 0}')),
                                    DataCell(
                                        Text(row['unit'] as String? ?? '')),
                                    DataCell(
                                        Text(row['receiptNo'] as String? ?? ''))
                                  ]))
                              .toList())))
        ] else ...[
          Wrap(spacing: 10, runSpacing: 10, children: [
            _ProductionMetric(
                label: 'عدد الاستلامات', value: '${snapshot.summary.count}'),
            _ProductionMetric(
                label: 'الوزن المستلم',
                value: '${snapshot.summary.gross.toStringAsFixed(1)} كجم'),
            _ProductionMetric(
                label: 'إجمالي الخصم',
                value: '${snapshot.summary.discount.toStringAsFixed(1)} كجم'),
            _ProductionMetric(
                label: 'الوزن الصافي',
                value: '${snapshot.summary.net.toStringAsFixed(1)} كجم'),
            _ProductionMetric(
                label: 'عدد الموردين', value: '${snapshot.summary.suppliers}')
          ]),
          const SizedBox(height: 14),
          _DataPanel(
              title: 'تفاصيل الاستلامات',
              child: snapshot.rows.isEmpty
                  ? const Text('لا توجد استلامات مطابقة',
                      style: TextStyle(color: AppColors.muted))
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                          columns: const [
                            DataColumn(label: Text('التاريخ')),
                            DataColumn(label: Text('الخامة')),
                            DataColumn(label: Text('المورد')),
                            DataColumn(label: Text('المستلم')),
                            DataColumn(label: Text('الخصم')),
                            DataColumn(label: Text('الصافي'))
                          ],
                          rows: snapshot.rows
                              .map((row) => DataRow(cells: [
                                    DataCell(Text(row.date)),
                                    DataCell(Text(row.material)),
                                    DataCell(Text(row.supplier)),
                                    DataCell(Text('${row.gross} كجم')),
                                    DataCell(Text('${row.discount} كجم')),
                                    DataCell(Text('${row.net} كجم'))
                                  ]))
                              .toList())))
        ]
      ]);
}

class _ReceiptFilter extends StatelessWidget {
  const _ReceiptFilter({required this.controller, required this.label});
  final TextEditingController controller;
  final String label;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: 155,
      child: TextField(
          controller: controller,
          decoration: InputDecoration(
              labelText: label, prefixIcon: const Icon(Icons.search))));
}

class _ReceiptDialog extends StatefulWidget {
  const _ReceiptDialog();
  @override
  State<_ReceiptDialog> createState() => _ReceiptDialogState();
}

class _ReceiptDialogState extends State<_ReceiptDialog> {
  final date = TextEditingController(text: '2026-08-25'),
      time = TextEditingController(text: '16:00'),
      material = TextEditingController(),
      supplier = TextEditingController(),
      supplierCode = TextEditingController(),
      gross = TextEditingController(),
      discountRate = TextEditingController(text: '0'),
      defects = TextEditingController(),
      notes = TextEditingController();
  @override
  void dispose() {
    for (final c in [
      date,
      time,
      material,
      supplier,
      supplierCode,
      gross,
      discountRate,
      defects,
      notes
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('استلام خامة'),
          content: SingleChildScrollView(
              child: SizedBox(
                  width: 460,
                  child: Column(children: [
                    _DialogInput(controller: date, label: 'التاريخ'),
                    _DialogInput(controller: time, label: 'وقت الاستلام'),
                    _DialogInput(controller: material, label: 'اسم الخام'),
                    _DialogInput(controller: supplier, label: 'اسم المورد'),
                    _DialogInput(controller: supplierCode, label: 'كود المورد'),
                    _DialogInput(controller: gross, label: 'الوزن المستلم'),
                    _DialogInput(controller: discountRate, label: 'نسبة الخصم'),
                    _DialogInput(controller: defects, label: 'العيوب'),
                    _DialogInput(controller: notes, label: 'ملاحظات')
                  ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () {
                  final grossValue = double.tryParse(gross.text),
                      rateValue = double.tryParse(discountRate.text) ?? 0;
                  if (grossValue == null ||
                      grossValue <= 0 ||
                      material.text.trim().isEmpty ||
                      supplier.text.trim().isEmpty) return;
                  Navigator.pop(
                      context,
                      RawReceipt(
                          date: date.text.trim(),
                          time: time.text.trim(),
                          material: material.text.trim(),
                          supplier: supplier.text.trim(),
                          supplierCode: supplierCode.text.trim(),
                          gross: grossValue,
                          discountRate: rateValue,
                          defects: defects.text.trim(),
                          notes: notes.text.trim()));
                },
                child: const Text('حفظ'))
          ]);
}

class _PackagingReceiptDialog extends StatefulWidget {
  const _PackagingReceiptDialog();
  @override
  State<_PackagingReceiptDialog> createState() =>
      _PackagingReceiptDialogState();
}

class _PackagingReceiptDialogState extends State<_PackagingReceiptDialog> {
  final date = TextEditingController(text: '2026-08-25');
  final time = TextEditingController(text: '16:00');
  final supplier = TextEditingController();
  final item = TextEditingController();
  final code = TextEditingController();
  final quantity = TextEditingController();
  final unit = TextEditingController(text: 'قطعة');
  final receiptNo = TextEditingController();
  final notes = TextEditingController();

  @override
  void dispose() {
    for (final controller in [
      date,
      time,
      supplier,
      item,
      code,
      quantity,
      unit,
      receiptNo,
      notes
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('استلام مواد تعبئة أو معدات'),
        content: SingleChildScrollView(
            child: SizedBox(
                width: 460,
                child: Column(children: [
                  _DialogInput(controller: date, label: 'التاريخ'),
                  _DialogInput(controller: time, label: 'وقت الاستلام'),
                  _DialogInput(controller: supplier, label: 'المورد'),
                  _DialogInput(controller: item, label: 'الصنف'),
                  _DialogInput(controller: code, label: 'كود الصنف'),
                  _DialogInput(controller: quantity, label: 'الكمية'),
                  _DialogInput(controller: unit, label: 'الوحدة'),
                  _DialogInput(
                      controller: receiptNo, label: 'رقم إذن الاستلام'),
                  _DialogInput(controller: notes, label: 'ملاحظات'),
                ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () {
                final value = double.tryParse(quantity.text);
                if (value == null ||
                    value <= 0 ||
                    supplier.text.trim().isEmpty ||
                    item.text.trim().isEmpty ||
                    unit.text.trim().isEmpty) return;
                Navigator.pop(
                    context,
                    PackagingReceipt(
                        date: date.text.trim(),
                        time: time.text.trim(),
                        supplier: supplier.text.trim(),
                        item: item.text.trim(),
                        quantity: value,
                        unit: unit.text.trim(),
                        itemCode: code.text.trim(),
                        receiptNo: receiptNo.text.trim(),
                        notes: notes.text.trim()));
              },
              child: const Text('حفظ'))
        ],
      );
}

class _AuditLogView extends StatefulWidget {
  const _AuditLogView({required this.state});

  final _ShiftWorkspaceState state;

  @override
  State<_AuditLogView> createState() => _AuditLogViewState();
}

class _AuditLogViewState extends State<_AuditLogView> {
  List<Map<String, dynamic>> rows = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final token = widget.state.widget.session.accessToken;
    if (token == null) return;
    try {
      final value = await ApiClient.loadAuditLog(token,
          shiftId: widget.state.currentShiftId);
      if (mounted) setState(() => rows = value);
    } catch (_) {
      if (mounted) widget.state._showSavedMessage('تعذر تحميل سجل الأحداث');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: [
        Row(children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('سجل الأحداث',
                    style: TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w900,
                        color: AppColors.ink)),
                SizedBox(height: 4),
                Text('كل العمليات المهمة المسجلة على الوردية',
                    style: TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
              tooltip: 'تحديث السجل',
              onPressed: loading ? null : refresh,
              icon: const Icon(Icons.refresh)),
        ]),
        const SizedBox(height: 16),
        if (loading) const LinearProgressIndicator(),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: Colors.white.withAlpha(235),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border)),
          child: rows.isEmpty && !loading
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('لا توجد أحداث مسجلة لهذه الوردية',
                      style: TextStyle(color: AppColors.muted)),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor:
                        const WidgetStatePropertyAll(AppColors.background),
                    columns: const [
                      DataColumn(label: Text('الوقت')),
                      DataColumn(label: Text('المستخدم')),
                      DataColumn(label: Text('القسم/الكيان')),
                      DataColumn(label: Text('العملية')),
                    ],
                    rows: [
                      for (final row in rows)
                        DataRow(cells: [
                          DataCell(Text(_auditTime(row['created_at']))),
                          DataCell(Text('${row['user_id'] ?? '-'}')),
                          DataCell(Text('${row['entity_type'] ?? '-'}')),
                          DataCell(Text('${row['action'] ?? '-'}')),
                        ])
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  String _auditTime(dynamic value) {
    final parsed = DateTime.tryParse('$value');
    if (parsed == null) return '$value';
    return '${parsed.toLocal().hour.toString().padLeft(2, '0')}:${parsed.toLocal().minute.toString().padLeft(2, '0')}';
  }
}

class _ContainerLoadingView extends StatefulWidget {
  const _ContainerLoadingView({required this.state});

  final _ShiftWorkspaceState state;

  @override
  State<_ContainerLoadingView> createState() => _ContainerLoadingViewState();
}

class _ContainerLoadingViewState extends State<_ContainerLoadingView> {
  List<ContainerLoading> rows = [];
  bool loading = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final token = widget.state.widget.session.accessToken;
    if (token == null) return;
    try {
      final value = await ApiClient.loadContainerLoadings(token,
          shiftId: widget.state.currentShiftId);
      if (mounted) setState(() => rows = value);
    } catch (_) {
      if (mounted) widget.state._showSavedMessage('تعذر تحميل عمليات الحاويات');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> addLoading() async {
    final value = await showDialog<ContainerLoading>(
      context: context,
      builder: (_) => const _ContainerLoadingDialog(),
    );
    if (value == null) return;
    final token = widget.state.widget.session.accessToken;
    if (token == null) return;
    setState(() => saving = true);
    try {
      final saved = await ApiClient.createContainerLoading(token, value,
          shiftId: widget.state.currentShiftId);
      if (mounted) {
        setState(() {
          rows = [saved, ...rows];
          widget.state.containerLoadings = rows;
          widget.state.containersCount = rows.length;
        });
        widget.state._showSavedMessage('تم حفظ تحميل الحاوية وتسجيل الحدث');
      }
    } catch (_) {
      if (mounted) widget.state._showSavedMessage('تعذر حفظ تحميل الحاوية');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: [
        Row(children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('تحميل الحاويات',
                    style: TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w900,
                        color: AppColors.ink)),
                SizedBox(height: 4),
                Text('تسجيل عمليات تحميل الحاويات وربطها بالوردية الحالية',
                    style: TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
          ),
          FilledButton.icon(
              onPressed: saving ? null : addLoading,
              icon: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.add),
              label: const Text('تحميل جديد')),
        ]),
        const SizedBox(height: 16),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _MiniMetric(
              label: 'الحاويات المحملة',
              value: '${rows.length}',
              color: AppColors.primary),
          _MiniMetric(
              label: 'الوردية',
              value:
                  '${widget.state.currentShift?.number ?? _ShiftWorkspaceState.shift.number}',
              color: AppColors.ink),
        ]),
        const SizedBox(height: 14),
        if (loading) const LinearProgressIndicator(),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: Colors.white.withAlpha(235),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border)),
          child: rows.isEmpty && !loading
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('لم يتم تسجيل تحميل حاويات بعد',
                      style: TextStyle(color: AppColors.muted)),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor:
                        const WidgetStatePropertyAll(AppColors.background),
                    columns: const [
                      DataColumn(label: Text('الحاوية')),
                      DataColumn(label: Text('المنتج')),
                      DataColumn(label: Text('الكراتين')),
                      DataColumn(label: Text('الكمية')),
                      DataColumn(label: Text('حرارة المنتج')),
                      DataColumn(label: Text('وقت التحميل')),
                    ],
                    rows: [
                      for (final row in rows)
                        DataRow(cells: [
                          DataCell(Text(row.containerNo)),
                          DataCell(Text(row.productName)),
                          DataCell(Text(row.cartons.toStringAsFixed(0))),
                          DataCell(Text(row.quantity.toStringAsFixed(1))),
                          DataCell(
                              Text('${row.productTemp.toStringAsFixed(1)}°C')),
                          DataCell(Text(_containerTime(row.loadedAt))),
                        ])
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  String _containerTime(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    final local = parsed.toLocal();
    return '${local.day}/${local.month} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _ContainerLoadingDialog extends StatefulWidget {
  const _ContainerLoadingDialog();

  @override
  State<_ContainerLoadingDialog> createState() =>
      _ContainerLoadingDialogState();
}

class _ContainerLoadingDialogState extends State<_ContainerLoadingDialog> {
  final containerNo = TextEditingController();
  final productName = TextEditingController();
  final before = TextEditingController();
  final productTemp = TextEditingController();
  final after = TextEditingController();
  final cartons = TextEditingController();
  final quantity = TextEditingController();
  final notes = TextEditingController();

  @override
  void dispose() {
    for (final controller in [
      containerNo,
      productName,
      before,
      productTemp,
      after,
      cartons,
      quantity,
      notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController controller, String label,
            {TextInputType? type}) =>
        TextField(
          controller: controller,
          keyboardType: type,
          decoration: InputDecoration(labelText: label),
        );
    return AlertDialog(
      title: const Text('تسجيل تحميل حاوية'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 440,
          child: Column(children: [
            field(containerNo, 'رقم الحاوية'),
            field(productName, 'اسم المنتج'),
            field(before, 'درجة حرارة الحاوية قبل التحميل',
                type: const TextInputType.numberWithOptions(decimal: true)),
            field(productTemp, 'درجة حرارة المنتج',
                type: const TextInputType.numberWithOptions(decimal: true)),
            field(after, 'درجة حرارة الحاوية بعد التحميل',
                type: const TextInputType.numberWithOptions(decimal: true)),
            field(cartons, 'عدد الكراتين',
                type: const TextInputType.numberWithOptions(decimal: true)),
            field(quantity, 'الكمية',
                type: const TextInputType.numberWithOptions(decimal: true)),
            field(notes, 'ملاحظات'),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء')),
        FilledButton(
            onPressed: () {
              final values = [
                double.tryParse(before.text),
                double.tryParse(productTemp.text),
                double.tryParse(after.text),
                double.tryParse(cartons.text),
                double.tryParse(quantity.text),
              ];
              if (containerNo.text.trim().isEmpty ||
                  productName.text.trim().isEmpty ||
                  values.any((value) => value == null)) return;
              Navigator.pop(
                context,
                ContainerLoading(
                  containerNo: containerNo.text.trim(),
                  productName: productName.text.trim(),
                  containerTempBefore: values[0]!,
                  productTemp: values[1]!,
                  containerTempAfter: values[2]!,
                  cartons: values[3]!,
                  quantity: values[4]!,
                  loadedAt: DateTime.now().toIso8601String(),
                  notes: notes.text.trim(),
                ),
              );
            },
            child: const Text('حفظ')),
      ],
    );
  }
}

class _ModuleView extends StatelessWidget {
  const _ModuleView({required this.section, required this.state});
  final WorkspaceSection section;
  final _ShiftWorkspaceState state;
  @override
  Widget build(BuildContext context) {
    final titles = {
      WorkspaceSection.attendance: 'الحضور والغياب',
      WorkspaceSection.production: 'الإنتاج لكل ساعة',
      WorkspaceSection.quality: 'الجودة والفحص',
      WorkspaceSection.supplies: 'التوريدات',
      WorkspaceSection.downtime: 'التوقفات',
      WorkspaceSection.maintenance: 'بلاغات الصيانة',
      WorkspaceSection.inventory: 'المخزن والخامات',
      WorkspaceSection.reports: 'التقارير',
      WorkspaceSection.auditLog: 'سجل الأحداث'
    };
    final icons = {
      WorkspaceSection.attendance: Icons.groups_outlined,
      WorkspaceSection.production: Icons.show_chart,
      WorkspaceSection.quality: Icons.fact_check_outlined,
      WorkspaceSection.supplies: Icons.local_shipping_outlined,
      WorkspaceSection.downtime: Icons.pause_circle_outline,
      WorkspaceSection.maintenance: Icons.build_circle_outlined,
      WorkspaceSection.inventory: Icons.inventory_2_outlined,
      WorkspaceSection.reports: Icons.assessment_outlined,
      WorkspaceSection.auditLog: Icons.history_outlined
    };
    return ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
        children: [
          Row(children: [
            Icon(icons[section], color: AppColors.primary, size: 30),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(titles[section]!,
                      style: const TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w900,
                          color: AppColors.ink)),
                  const SizedBox(height: 4),
                  Text(
                      'الوردية ${_ShiftWorkspaceState.shift.number} · البيانات التشغيلية لحظيًا',
                      style:
                          const TextStyle(color: AppColors.muted, fontSize: 12))
                ])),
            FilledButton.icon(
                onPressed: () => state.openAddDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('إضافة سجل')),
            if (section == WorkspaceSection.inventory &&
                state.widget.session.role == UserRole.systemAdmin) ...[
              const SizedBox(width: 10),
              OutlinedButton.icon(
                  onPressed: () =>
                      state.editInventoryOpeningBalance(context),
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('الرصيد الافتتاحي')),
            ]
          ]),
          const SizedBox(height: 16),
          _ModuleSummary(section: section, state: state),
          const SizedBox(height: 14),
          _ModuleTable(section: section, state: state)
        ]);
  }
}

class _ReportsView extends StatefulWidget {
  const _ReportsView({required this.state});

  final _ShiftWorkspaceState state;

  @override
  State<_ReportsView> createState() => _ReportsViewState();
}

class _ReportsViewState extends State<_ReportsView> {
  Map<String, dynamic>? report;
  bool loading = false;
  int shiftId = 1;

  Future<void> loadReport() async {
    final token = widget.state.widget.session.accessToken;
    if (token == null) return;
    setState(() => loading = true);
    try {
      final shift = await ApiClient.loadCurrentShiftRecord(token);
      shiftId = shift.id;
      final result = await ApiClient.report(token, shiftId: shiftId);
      if (mounted) setState(() => report = result);
    } catch (_) {
      if (mounted)
        widget.state._showSavedMessage('تعذر تحميل التقرير من الخادم');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    loadReport();
  }

  @override
  Widget build(BuildContext context) {
    final current = report;
    final production = current?['production'] as Map<String, dynamic>?;
    final attendance = current?['attendance'] as Map<String, dynamic>?;
    final quality = current?['quality'] as Map<String, dynamic>?;
    final achievement = (current?['achievement'] as num?)?.toDouble() ??
        widget.state.achievement;
    final attendanceRate =
        (current?['attendance_rate'] as num?)?.toDouble() ?? 0;
    final rejectionRate = (current?['rejection_rate'] as num?)?.toDouble() ??
        widget.state.rejection;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: [
        Row(children: [
          const Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('التقارير والتحليلات',
                  style: TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w900,
                      color: AppColors.ink)),
              SizedBox(height: 4),
              Text('ملخص مبني على بيانات الوردية المحفوظة في الخادم',
                  style: TextStyle(color: AppColors.muted, fontSize: 12)),
            ]),
          ),
          IconButton(
              tooltip: 'تحديث التقرير',
              onPressed: loading ? null : loadReport,
              icon: const Icon(Icons.refresh)),
        ]),
        const SizedBox(height: 16),
        if (loading) const LinearProgressIndicator(),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _MiniMetric(
              label: 'الإنتاج الفعلي',
              value: '${production?['actual'] ?? widget.state.actual}',
              color: AppColors.ink),
          _MiniMetric(
              label: 'المستهدف',
              value: '${production?['target'] ?? widget.state.target}',
              color: AppColors.ink),
          _MiniMetric(
              label: 'تحقيق المستهدف',
              value: '${achievement.toStringAsFixed(1)}%',
              color: achievement >= 90 ? AppColors.primary : AppColors.red),
          _MiniMetric(
              label: 'نسبة الحضور',
              value: '${attendanceRate.toStringAsFixed(1)}%',
              color: AppColors.primary),
          _MiniMetric(
              label: 'نسبة الرفض',
              value: '${rejectionRate.toStringAsFixed(1)}%',
              color: rejectionRate <= 5 ? AppColors.primary : AppColors.red),
          _MiniMetric(
              label: 'التوقف',
              value:
                  '${current?['downtime']?['minutes'] ?? widget.state.downtime} دقيقة',
              color: AppColors.amber),
        ]),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: Colors.white.withAlpha(235),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('إجراءات التقرير',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                  onPressed: () async {
                    await ApiClient.exportReport(
                        widget.state.widget.session.accessToken!,
                        csv: true,
                        shiftId: shiftId);
                    if (mounted)
                      widget.state
                          ._showSavedMessage('تم تجهيز ملف CSV لفتحه في Excel');
                  },
                  icon: const Icon(Icons.table_view_outlined),
                  label: const Text('تصدير Excel')),
              OutlinedButton.icon(
                  onPressed: () async {
                    await ApiClient.exportReport(
                        widget.state.widget.session.accessToken!,
                        csv: false,
                        shiftId: shiftId);
                    if (mounted)
                      widget.state._showSavedMessage(
                          'تم تجهيز التقرير للطباعة أو الحفظ PDF');
                  },
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('تقرير PDF')),
              OutlinedButton.icon(
                  onPressed: () async {
                    await ApiClient.updateShiftStatus(
                        widget.state.widget.session.accessToken!, 'COMPLETED',
                        shiftId: shiftId);
                    if (mounted)
                      widget.state._showSavedMessage(
                          'تم إنهاء الوردية وتسجيل وقت الإغلاق');
                  },
                  icon: const Icon(Icons.task_alt),
                  label: const Text('إنهاء الوردية')),
            ]),
          ]),
        ),
        const SizedBox(height: 16),
        if (attendance != null || quality != null)
          _ModuleTable(
              section: WorkspaceSection.production, state: widget.state),
      ],
    );
  }
}

class _UsersView extends StatefulWidget {
  const _UsersView({required this.state});

  final _ShiftWorkspaceState state;

  @override
  State<_UsersView> createState() => _UsersViewState();
}

class _UsersViewState extends State<_UsersView> {
  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> roles = [];
  bool loading = true;

  String get token => widget.state.widget.session.accessToken!;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final results = await Future.wait([
        ApiClient.users(token),
        ApiClient.roles(token),
      ]);
      if (!mounted) return;
      setState(() {
        users = results[0];
        roles = results[1];
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => loading = false);
      widget.state._showSavedMessage(
          'تعذر تحميل المستخدمين. تأكد من صلاحية مدير النظام.');
    }
  }

  Future<void> addUser() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _CreateUserDialog(roles: roles),
    );
    if (result == null) return;
    try {
      await ApiClient.createUser(
        token,
        name: result['name']!,
        email: result['email']!,
        password: result['password']!,
        roleCode: result['roleCode']!,
        department: result['department'],
      );
      await refresh();
      if (mounted)
        widget.state._showSavedMessage(
            'تم إنشاء المستخدم وتسجيل العملية في سجل الأحداث');
    } catch (_) {
      if (mounted)
        widget.state
            ._showSavedMessage('تعذر إنشاء المستخدم أو البريد مستخدم بالفعل');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: [
        Row(children: [
          const Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('المستخدمون والأدوار',
                  style: TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w900,
                      color: AppColors.ink)),
              SizedBox(height: 4),
              Text('إدارة الحسابات وصلاحيات الوصول للنظام',
                  style: TextStyle(color: AppColors.muted, fontSize: 12)),
            ]),
          ),
          IconButton(
              tooltip: 'تحديث',
              onPressed: loading ? null : refresh,
              icon: const Icon(Icons.refresh)),
          FilledButton.icon(
              onPressed: addUser,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('مستخدم جديد')),
        ]),
        const SizedBox(height: 16),
        if (loading) const LinearProgressIndicator(),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: Colors.white.withAlpha(235),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${users.length} مستخدم مسجل',
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink)),
            const SizedBox(height: 10),
            if (!loading && users.isEmpty)
              const Text('لا يوجد مستخدمون بعد',
                  style: TextStyle(color: AppColors.muted)),
            for (final user in users)
              _UserRow(
                  user: user,
                  onChanged: (active) async {
                    await ApiClient.updateUserStatus(
                        token, (user['id'] as num).toInt(), active);
                    await refresh();
                  }),
          ]),
        ),
      ],
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({required this.user, required this.onChanged});

  final Map<String, dynamic> user;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final active =
        user['isActive'] as bool? ?? user['is_active'] as bool? ?? false;
    final role = user['role'] as String? ?? user['role_code'] as String? ?? '';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: CircleAvatar(
          backgroundColor: active ? AppColors.primarySoft : AppColors.redSoft,
          child: Icon(Icons.person_outline,
              color: active ? AppColors.primary : AppColors.red)),
      title: Text(user['name'] as String? ?? '',
          style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(
          '${user['email']} · $role · ${user['department'] ?? 'بدون قسم'}',
          style: const TextStyle(color: AppColors.muted, fontSize: 11)),
      trailing: Switch(value: active, onChanged: onChanged),
    );
  }
}

class _CreateUserDialog extends StatefulWidget {
  const _CreateUserDialog({required this.roles});

  final List<Map<String, dynamic>> roles;

  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController(text: 'User@123456');
  final department = TextEditingController();
  String? roleCode;

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    department.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final availableRoles = widget.roles.isEmpty
        ? const [
            {'code': 'SHIFT_MANAGER', 'name': 'Shift Manager'},
            {'code': 'SECURITY', 'name': 'Security'},
          ]
        : widget.roles;
    roleCode ??= availableRoles.first['code'] as String;
    return AlertDialog(
      title: const Text('إنشاء مستخدم'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 420,
          child: Column(children: [
            TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'الاسم')),
            TextField(
                controller: email,
                decoration:
                    const InputDecoration(labelText: 'البريد الإلكتروني')),
            TextField(
                controller: password,
                decoration: const InputDecoration(labelText: 'كلمة المرور')),
            TextField(
                controller: department,
                decoration: const InputDecoration(labelText: 'القسم')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
                value: roleCode,
                decoration: const InputDecoration(labelText: 'الدور'),
                items: [
                  for (final role in availableRoles)
                    DropdownMenuItem(
                        value: role['code'] as String,
                        child: Text(role['name'] as String))
                ],
                onChanged: (value) => setState(() => roleCode = value)),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء')),
        FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty ||
                  email.text.trim().isEmpty ||
                  roleCode == null) return;
              Navigator.pop(context, {
                'name': name.text.trim(),
                'email': email.text.trim(),
                'password': password.text,
                'department': department.text.trim(),
                'roleCode': roleCode!
              });
            },
            child: const Text('إنشاء')),
      ],
    );
  }
}

class _ModuleSummary extends StatelessWidget {
  const _ModuleSummary({required this.section, required this.state});
  final WorkspaceSection section;
  final _ShiftWorkspaceState state;
  @override
  Widget build(BuildContext context) {
    final items = <WorkspaceSection, List<String>>{
      WorkspaceSection.attendance: [
        '5',
        '${state.present}',
        '${state.absent}',
        '${(state.present / state.workers.length * 100).toStringAsFixed(0)}%'
      ],
      WorkspaceSection.production: [
        '5',
        '${state.actual}',
        '${state.target}',
        '${state.achievement.toStringAsFixed(1)}%'
      ],
      WorkspaceSection.quality: [
        '${state.qualityInspected}',
        '${state.qualityAccepted}',
        '${state.qualityRejected}',
        '${state.rejection.toStringAsFixed(1)}% رفض'
      ],
      WorkspaceSection.supplies: [
        '${state.supplyRecords}',
        '${state.supplyTotal} كجم',
        '7',
        '${state.approvedSupplies} معتمدة'
      ],
      WorkspaceSection.downtime: [
        '${state.downtimeRecords.length}',
        '${state.downtime} دقيقة',
        '${state.openDowntimeCount}',
        'بلاغ مفتوح'
      ],
      WorkspaceSection.maintenance: [
        '${state.maintenanceTickets.length}',
        '${state.openTickets} مفتوح',
        '18 دقيقة',
        'متابعة'
      ],
      WorkspaceSection.inventory: [
        '${state.inventoryMovements.length}',
        '${state.inventoryBalance} كجم',
        '${state.inventoryIssued} كجم',
        'محسوب'
      ],
      WorkspaceSection.reports: ['6', '4 مكتملة', '2 تنبيه', 'جاهزة'],
      WorkspaceSection.auditLog: [
        '${state.auditEvents.length}',
        '2 أقسام',
        '0 حذف',
        'مسجل'
      ],
      WorkspaceSection.containerLoadings: [
        '${state.containersCount}',
        'حالية',
        '0 معلقة',
        'مسجلة'
      ],
    }[section]!;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var i = 0; i < items.length; i++)
          _MiniMetric(
            label: ['السجلات', 'القيمة الحالية', 'الإجمالي', 'الحالة'][i],
            value: items[i],
            color: i == 3 ? AppColors.primary : AppColors.ink,
          ),
      ],
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric(
      {required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(235),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w900, fontSize: 21)),
          ],
        ),
      ),
    );
  }
}

class _ModuleTable extends StatelessWidget {
  const _ModuleTable({required this.section, required this.state});
  final WorkspaceSection section;
  final _ShiftWorkspaceState state;
  @override
  Widget build(BuildContext context) {
    late final List<List<String>> rows;
    late final List<String> headers;
    if (section == WorkspaceSection.production) {
      headers = ['الساعة', 'الخط', 'المستهدف', 'الفعلي', 'الفرق', 'التحقيق'];
      rows = state.hourly
          .map((item) => [
                item.hour,
                item.line,
                '${item.target}',
                '${item.actual}',
                '${item.difference}',
                '${item.achievement.toStringAsFixed(1)}%'
              ])
          .toList();
    } else if (section == WorkspaceSection.downtime) {
      headers = ['الخط', 'الماكينة', 'السبب', 'المدة', 'الحالة'];
      rows = state.downtimeRecords
          .map((item) => [
                item.line,
                item.machine,
                item.reason,
                '${item.minutes} د',
                item.status
              ])
          .toList();
    } else if (section == WorkspaceSection.maintenance) {
      headers = ['رقم البلاغ', 'الماكينة', 'الخطورة', 'الوصف', 'الحالة'];
      rows = state.maintenanceTickets
          .map((item) => [
                item.number,
                item.machine,
                item.severity,
                item.description,
                item.status
              ])
          .toList();
    } else if (section == WorkspaceSection.inventory) {
      headers = ['نوع الحركة', 'الخامة', 'الكمية', 'الرصيد الحالي'];
      rows = state.inventoryMovements
          .map((item) => [
                item.type,
                item.material,
                '${item.quantity} كجم',
                '${state.inventoryBalance} كجم'
              ])
          .toList();
    } else if (section == WorkspaceSection.auditLog) {
      headers = ['الوقت', 'المستخدم', 'القسم', 'العملية'];
      rows = state.auditEvents
          .map((item) => [item.time, item.user, item.department, item.action])
          .toList();
    } else {
      headers = ['التاريخ', 'السياق', 'المسؤول', 'آخر إجراء', 'الحالة'];
      rows = [
        ['21 أغسطس 2026', 'وردية ثانية', 'محمد حمدي', 'مسجل', 'مفتوح'],
        ['21 أغسطس 2026', 'خط 01', 'النظام', 'محدث الآن', 'طبيعي']
      ];
    }
    return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Colors.white.withAlpha(235),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('السجلات الأخيرة',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                  headingRowColor: WidgetStatePropertyAll(AppColors.background),
                  columns: [
                    for (final header in headers)
                      DataColumn(
                          label: Text(header,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 11)))
                  ],
                  rows: [
                    for (final row in rows)
                      DataRow(cells: [
                        for (final cell in row)
                          DataCell(
                              Text(cell, style: const TextStyle(fontSize: 12)))
                      ])
                  ]))
        ]));
  }
}

class _ProductionDialog extends StatefulWidget {
  const _ProductionDialog();

  @override
  State<_ProductionDialog> createState() => _ProductionDialogState();
}

class _ProductionDialogState extends State<_ProductionDialog> {
  final hour = TextEditingController(text: '21:00');
  final line = TextEditingController(text: 'خط 01');
  final target = TextEditingController(text: '850');
  final actual = TextEditingController(text: '800');

  @override
  void dispose() {
    hour.dispose();
    line.dispose();
    target.dispose();
    actual.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _DataDialog(
      title: 'إضافة إنتاج الساعة',
      subtitle: 'الوردية الثانية · يتم حساب الفرق ونسبة التحقيق تلقائيًا',
      icon: Icons.show_chart,
      fields: [
        _DialogField(
            controller: hour, label: 'الساعة', icon: Icons.schedule_outlined),
        _DialogField(
            controller: line,
            label: 'خط الإنتاج',
            icon: Icons.factory_outlined),
        _DialogField(
            controller: target,
            label: 'المستهدف',
            icon: Icons.track_changes_outlined,
            numeric: true),
        _DialogField(
            controller: actual,
            label: 'الإنتاج الفعلي',
            icon: Icons.production_quantity_limits,
            numeric: true),
      ],
      onSave: () {
        final targetValue = int.tryParse(target.text.trim());
        final actualValue = int.tryParse(actual.text.trim());
        if (targetValue == null ||
            actualValue == null ||
            targetValue <= 0 ||
            actualValue < 0) return;
        Navigator.pop(
            context,
            HourlyProduction(
                hour: hour.text.trim(),
                line: line.text.trim(),
                target: targetValue,
                actual: actualValue));
      },
    );
  }
}

class _AttendanceDialog extends StatefulWidget {
  const _AttendanceDialog(
      {required this.present, required this.absent, required this.late});

  final int present;
  final int absent;
  final int late;

  @override
  State<_AttendanceDialog> createState() => _AttendanceDialogState();
}

class _AttendanceDialogState extends State<_AttendanceDialog> {
  late final present = TextEditingController(text: '${widget.present}');
  late final absent = TextEditingController(text: '${widget.absent}');
  late final late = TextEditingController(text: '${widget.late}');

  @override
  void dispose() {
    present.dispose();
    absent.dispose();
    late.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _DataDialog(
      title: 'تسجيل حضور الوردية',
      subtitle: 'إجمالي العمال المطلوبين: 5 · النسب محسوبة من الأعداد',
      icon: Icons.groups_outlined,
      fields: [
        _DialogField(
            controller: present,
            label: 'الحاضرون',
            icon: Icons.check_circle_outline,
            numeric: true),
        _DialogField(
            controller: absent,
            label: 'الغائبون',
            icon: Icons.person_off_outlined,
            numeric: true),
        _DialogField(
            controller: late,
            label: 'المتأخرون',
            icon: Icons.schedule_outlined,
            numeric: true),
      ],
      onSave: () {
        final presentValue = int.tryParse(present.text.trim());
        final absentValue = int.tryParse(absent.text.trim());
        final lateValue = int.tryParse(late.text.trim());
        if (presentValue == null ||
            absentValue == null ||
            lateValue == null ||
            presentValue < 0 ||
            absentValue < 0 ||
            lateValue < 0) return;
        Navigator.pop(context, [presentValue, absentValue, lateValue]);
      },
    );
  }
}

class _QualityDialog extends StatefulWidget {
  const _QualityDialog({required this.inspected, required this.rejected});

  final int inspected;
  final int rejected;

  @override
  State<_QualityDialog> createState() => _QualityDialogState();
}

class _QualityDialogState extends State<_QualityDialog> {
  late final inspected = TextEditingController(text: '${widget.inspected}');
  late final rejected = TextEditingController(text: '${widget.rejected}');

  @override
  void dispose() {
    inspected.dispose();
    rejected.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _DataDialog(
      title: 'إضافة فحص جودة',
      subtitle: 'أدخل الكمية المفحوصة والمرفوضة فقط، والنسبة تحسب تلقائيًا',
      icon: Icons.fact_check_outlined,
      fields: [
        _DialogField(
            controller: inspected,
            label: 'الكمية المفحوصة',
            icon: Icons.inventory_outlined,
            numeric: true),
        _DialogField(
            controller: rejected,
            label: 'الكمية المرفوضة',
            icon: Icons.cancel_outlined,
            numeric: true),
      ],
      onSave: () {
        final inspectedValue = int.tryParse(inspected.text.trim());
        final rejectedValue = int.tryParse(rejected.text.trim());
        if (inspectedValue == null ||
            rejectedValue == null ||
            inspectedValue <= 0 ||
            rejectedValue < 0 ||
            rejectedValue > inspectedValue) return;
        Navigator.pop(context, [inspectedValue, rejectedValue]);
      },
    );
  }
}

class _SupplyDialog extends StatefulWidget {
  const _SupplyDialog();

  @override
  State<_SupplyDialog> createState() => _SupplyDialogState();
}

class _SupplyDialogState extends State<_SupplyDialog> {
  final quantity = TextEditingController(text: '500');

  @override
  void dispose() {
    quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _DataDialog(
      title: 'تسجيل توريد جديد',
      subtitle: 'سيتم إضافة الكمية إلى إجمالي التوريدات للمراجعة',
      icon: Icons.local_shipping_outlined,
      fields: [
        _DialogField(
            controller: quantity,
            label: 'الكمية بالكيلوجرام',
            icon: Icons.scale_outlined,
            numeric: true),
      ],
      onSave: () {
        final value = int.tryParse(quantity.text.trim());
        if (value == null || value <= 0) return;
        Navigator.pop(context, value);
      },
    );
  }
}

class _DowntimeDialog extends StatefulWidget {
  const _DowntimeDialog();

  @override
  State<_DowntimeDialog> createState() => _DowntimeDialogState();
}

class _DowntimeDialogState extends State<_DowntimeDialog> {
  final line = TextEditingController(text: 'خط 01');
  final machine = TextEditingController(text: 'ماكينة التعبئة');
  final reason = TextEditingController(text: 'عطل ماكينة');
  final minutes = TextEditingController(text: '15');

  @override
  void dispose() {
    line.dispose();
    machine.dispose();
    reason.dispose();
    minutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _DataDialog(
      title: 'تسجيل توقف',
      subtitle: 'سيتم احتساب مدة التوقف ضمن مؤشرات الوردية والتنبيهات',
      icon: Icons.pause_circle_outline,
      fields: [
        _DialogField(
            controller: line,
            label: 'خط الإنتاج',
            icon: Icons.factory_outlined),
        _DialogField(
            controller: machine,
            label: 'الماكينة',
            icon: Icons.precision_manufacturing_outlined),
        _DialogField(
            controller: reason, label: 'سبب التوقف', icon: Icons.info_outline),
        _DialogField(
            controller: minutes,
            label: 'المدة بالدقائق',
            icon: Icons.timer_outlined,
            numeric: true),
      ],
      onSave: () {
        final value = int.tryParse(minutes.text.trim());
        if (value == null || value <= 0) return;
        Navigator.pop(
            context,
            DowntimeRecord(
                line: line.text.trim(),
                machine: machine.text.trim(),
                reason: reason.text.trim(),
                minutes: value,
                status: 'مفتوح'));
      },
    );
  }
}

class _MaintenanceDialog extends StatefulWidget {
  const _MaintenanceDialog();

  @override
  State<_MaintenanceDialog> createState() => _MaintenanceDialogState();
}

class _MaintenanceDialogState extends State<_MaintenanceDialog> {
  final machine = TextEditingController(text: 'ماكينة التعبئة');
  final description = TextEditingController(text: 'وصف المشكلة');

  @override
  void dispose() {
    machine.dispose();
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _DataDialog(
      title: 'فتح بلاغ صيانة',
      subtitle: 'البلاغ سيظهر لفريق الصيانة بحالة Open',
      icon: Icons.build_circle_outlined,
      fields: [
        _DialogField(
            controller: machine,
            label: 'الماكينة',
            icon: Icons.precision_manufacturing_outlined),
        _DialogField(
            controller: description,
            label: 'وصف المشكلة',
            icon: Icons.description_outlined),
      ],
      onSave: () {
        Navigator.pop(
            context,
            MaintenanceTicket(
                number: 'MT-${206 + DateTime.now().second}',
                machine: machine.text.trim(),
                severity: 'متوسط',
                description: description.text.trim(),
                status: 'Open'));
      },
    );
  }
}

class _InventoryDialog extends StatefulWidget {
  const _InventoryDialog();

  @override
  State<_InventoryDialog> createState() => _InventoryDialogState();
}

class _InventoryDialogState extends State<_InventoryDialog> {
  final material = TextEditingController(text: 'فراولة مجمدة');
  final quantity = TextEditingController(text: '250');
  String type = 'توريد';

  @override
  void dispose() {
    material.dispose();
    quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _DataDialog(
      title: 'إضافة حركة مخزن',
      subtitle: 'الرصيد النهائي = البداية + التوريدات - الصرف + المرتجع',
      icon: Icons.inventory_2_outlined,
      fields: [
        _DialogField(
            controller: material,
            label: 'الخامة',
            icon: Icons.category_outlined),
        DropdownButtonFormField<String>(
          value: type,
          decoration: InputDecoration(
              labelText: 'نوع الحركة',
              prefixIcon: const Icon(Icons.swap_vert),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          items: const [
            DropdownMenuItem(value: 'توريد', child: Text('توريد')),
            DropdownMenuItem(value: 'صرف للإنتاج', child: Text('صرف للإنتاج')),
            DropdownMenuItem(value: 'مرتجع', child: Text('مرتجع'))
          ],
          onChanged: (value) => setState(() => type = value ?? type),
        ),
        const SizedBox(height: 12),
        _DialogField(
            controller: quantity,
            label: 'الكمية بالكيلوجرام',
            icon: Icons.scale_outlined,
            numeric: true),
      ],
      onSave: () {
        final value = int.tryParse(quantity.text.trim());
        if (value == null || value <= 0) return;
        Navigator.pop(
            context,
            InventoryMovement(
                type: type, material: material.text.trim(), quantity: value));
      },
    );
  }
}

class _DataDialog extends StatelessWidget {
  const _DataDialog(
      {required this.title,
      required this.subtitle,
      required this.icon,
      required this.fields,
      required this.onSave});

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> fields;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        Icon(icon, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(
            child: Text(title,
                style: const TextStyle(fontWeight: FontWeight.w900)))
      ]),
      content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                Text(subtitle,
                    style:
                        const TextStyle(color: AppColors.muted, fontSize: 12)),
                const SizedBox(height: 16),
                ...fields
              ]))),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء')),
        FilledButton.icon(
            onPressed: onSave,
            icon: const Icon(Icons.save_outlined),
            label: const Text('حفظ السجل'))
      ],
    );
  }
}

class _DialogField extends StatelessWidget {
  const _DialogField(
      {required this.controller,
      required this.label,
      required this.icon,
      this.numeric = false});

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool numeric;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.factory_outlined,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'وردية تشغيل المصنع',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 5),
                Text(
                  '${now.day}/${now.month}/${now.year} · 08:00 ص - 04:00 م',
                  style:
                      const TextStyle(color: Color(0xFFC8D3CF), fontSize: 13),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.playlist_add_check),
            label: const Text('اعتماد'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.softColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color softColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: softColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkerTile extends StatelessWidget {
  const _WorkerTile({required this.worker});

  final Worker worker;

  @override
  Widget build(BuildContext context) {
    final payable = worker.status == AttendanceStatus.absent
        ? 0
        : worker.dailyRate + (worker.overtime * (worker.dailyRate / 8) * 1.25);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _Avatar(name: worker.name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  worker.name,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  '${worker.role} · ${worker.team}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    const _InfoChip(
                        icon: Icons.schedule_outlined, label: '08:00 - 16:00'),
                    _InfoChip(
                        icon: Icons.more_time,
                        label: '${worker.overtime} س إضافي'),
                    _InfoChip(
                        icon: Icons.payments_outlined,
                        label: '${payable.toStringAsFixed(0)} ج'),
                  ],
                ),
              ],
            ),
          ),
          _StatusPill(status: worker.status),
        ],
      ),
    );
  }
}

class _PayrollPanel extends StatelessWidget {
  const _PayrollPanel({required this.total});

  final double total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_balance_wallet_outlined,
              color: Colors.white, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'إجمالي مستحقات الوردية',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  '${total.toStringAsFixed(0)} جنيه',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () {},
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white70),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('تقرير'),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final AttendanceStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: status.softColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.label,
        style: TextStyle(
            color: status.color, fontWeight: FontWeight.w900, fontSize: 12),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final initials = parts.take(2).map((part) => part.characters.first).join();

    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        initials,
        style: const TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w900,
            fontSize: 16),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.muted),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(color: AppColors.ink, fontSize: 12)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.note});

  final String title;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
                color: AppColors.ink,
                fontSize: 19,
                fontWeight: FontWeight.w900),
          ),
        ),
        Text(
          note,
          style: const TextStyle(
              color: AppColors.muted,
              fontSize: 13,
              fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
