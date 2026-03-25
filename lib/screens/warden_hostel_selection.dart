import 'package:flutter/material.dart';
import 'warden_dashboard.dart';

class WardenHostelSelection extends StatelessWidget {
  const WardenHostelSelection({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Select Hostel"),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.apartment,
                size: 80,
                color: Colors.blueGrey,
              ),
              const SizedBox(height: 20),
              const Text(
                "Select Your Hostel",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "You will only see leave requests from the selected hostel.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 40),

              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const WardenDashboard(hostel: "Talpona Hostel"),
                      ),
                    );
                  },
                  icon: const Icon(Icons.home),
                  label: const Text(
                    "Talpona Hostel",
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const WardenDashboard(hostel: "Terekhol Hostel"),
                      ),
                    );
                  },
                  icon: const Icon(Icons.home_outlined),
                  label: const Text(
                    "Terekhol Hostel",
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
