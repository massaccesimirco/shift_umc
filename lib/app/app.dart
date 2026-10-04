import 'package:flutter/material.dart';

import '../presentation/screens/employee_screen.dart';
import '../presentation/screens/auth_gate.dart';

class ShiftUmcApp extends StatelessWidget {
  const ShiftUmcApp({super.key, this.demoMode = false, this.setupMessage});
  final bool demoMode;
  final String? setupMessage;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShiftUMC',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF156963)),
      ),
      home: demoMode
          ? const EmployeeScreen()
          : setupMessage != null
          ? Scaffold(
              appBar: AppBar(title: const Text('ShiftUMC')),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(setupMessage!, textAlign: TextAlign.center),
                ),
              ),
            )
          : const AuthGate(),
    );
  }
}
