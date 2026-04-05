import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app_launch_gate.dart';
import 'app_theme.dart';
import 'store/admin_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFF0a0c10),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final store = AdminStore();
  runApp(
    ChangeNotifierProvider<AdminStore>.value(
      value: store,
      child: MaterialApp(
        title: 'SupaAdmin',
        debugShowCheckedModeBanner: false,
        theme: adminTheme(),
        scrollBehavior: const MaterialScrollBehavior().copyWith(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        ),
        home: const AppLaunchGate(),
      ),
    ),
  );
}
