import 'package:flutter/material.dart';
import 'vehicle_application.dart';
import 'vehicle_status.dart';

class VehiclePortal extends StatelessWidget {
  const VehiclePortal({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Vehicle Entry"),
          bottom: const TabBar(
            tabs: [
              Tab(text: "Apply"),
              Tab(text: "Status"),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            VehicleApplication(embedded: true),
            VehicleStatus(embedded: true),
          ],
        ),
      ),
    );
  }
}
