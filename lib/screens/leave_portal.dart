import 'package:flutter/material.dart';
import 'leave_application.dart';
import 'leave_status.dart';

class LeavePortal extends StatelessWidget {
  const LeavePortal({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Leave Application"),
          bottom: const TabBar(
            tabs: [
              Tab(text: "Apply"),
              Tab(text: "Status"),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            LeaveApplication(embedded: true),
            LeaveStatus(embedded: true),
          ],
        ),
      ),
    );
  }
}
