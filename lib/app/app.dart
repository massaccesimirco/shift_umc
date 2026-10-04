import 'package:flutter/material.dart';

import '../presentation/screens/employee_screen.dart';

class ShiftUmcApp extends StatelessWidget {
  const ShiftUmcApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShiftUMC',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF156963)),
      ),
      home: const EmployeeScreen(),
    );
  }
}
