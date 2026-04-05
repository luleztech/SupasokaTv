import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:supaadmin/admin_shell.dart';
import 'package:supaadmin/app_theme.dart';
import 'package:supaadmin/store/admin_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Admin shell shows SupaAdmin', (WidgetTester tester) async {
    final store = AdminStore();
    await store.load();

    await tester.pumpWidget(
      ChangeNotifierProvider<AdminStore>.value(
        value: store,
        child: MaterialApp(
          theme: adminTheme(),
          home: const AdminShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SupaAdmin'), findsOneWidget);
  });
}
