import 'package:flutter_test/flutter_test.dart';

import 'package:worker_shift_app/main.dart';

void main() {
  testWidgets('logs in and shows the worker shift dashboard', (WidgetTester tester) async {
    await tester.pumpWidget(WorkerShiftApp(
      loginHandler: (email, password) async => const UserSession(
        email: 'manager@wardia.app',
        role: UserRole.shiftManager,
      ),
    ));

    expect(find.text('تسجيل الدخول'), findsOneWidget);

    await tester.tap(find.text('دخول'));
    await tester.pumpAndSettle();

    expect(find.text('وردية'), findsWidgets);
    expect(find.text('الوردية الثانية'), findsOneWidget);
    expect(find.text('الوردية جارية'), findsOneWidget);
  });
}
