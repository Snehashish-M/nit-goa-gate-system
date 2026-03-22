import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:nit_goa_gate_app/services/user_cache.dart';

import 'day_scholar.dart';
import 'hostel_exit.dart';
import 'leave_application.dart';
import 'leave_status.dart';
import 'profile_setup.dart';
import 'login_screen.dart';

class StudentDashboard extends StatefulWidget {
  const StudentDashboard({super.key});

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {

  Uint8List? photoBytes;

  @override
  void initState() {
    super.initState();
    _loadPhoto();
  }

  void _loadPhoto() {
    // Use cached profile data — no Firestore read needed
    var data = UserCache().profileData;
    if (data != null) {
      String? photo = data["photo"];
      if (photo != null && photo.isNotEmpty) {
        try {
          setState(() {
            photoBytes = base64Decode(photo);
          });
        } catch (e) {
          debugPrint("Error decoding photo: $e");
        }
      }
    }
  }

  void _handleMenuSelection(String value) async {
    if (value == "edit_profile") {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const ProfileSetup(),
        ),
      );
      // Reload photo from updated cache
      _loadPhoto();
    } else if (value == "logout") {
      UserCache().clear();
      await GoogleSignIn().signOut();
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {

    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(

      appBar: AppBar(
        title: const Text("Student Dashboard"),
        actions: [

          PopupMenuButton<String>(
            onSelected: _handleMenuSelection,
            offset: const Offset(0, 50),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: "edit_profile",
                child: Row(
                  children: [
                    Icon(Icons.edit, size: 20),
                    SizedBox(width: 10),
                    Text("Edit Profile"),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: "logout",
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 20),
                    SizedBox(width: 10),
                    Text("Log Out"),
                  ],
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: CircleAvatar(
                radius: 18,
                backgroundImage: photoBytes != null
                    ? MemoryImage(photoBytes!)
                    : null,
                child: photoBytes == null
                    ? const Icon(Icons.person, size: 20)
                    : null,
              ),
            ),
          ),

        ],
      ),

      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [

            Text(
              "Welcome ${user?.displayName ?? ""}",
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 40),

            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DayScholar(),
                  ),
                );
              },
              icon: const Icon(Icons.school),
              label: const Text("Day Scholar"),
            ),

            const SizedBox(height: 15),

            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const HostelExit(),
                  ),
                );
              },
              icon: const Icon(Icons.meeting_room),
              label: const Text("Hostel Entry / Exit"),
            ),

            const SizedBox(height: 15),

            ElevatedButton.icon(
              onPressed: () {
                var data = UserCache().profileData;
                if (data != null && data["hostel"] == "Day Scholar") {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Leave applications are only for hostel residents."),
                    ),
                  );
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const LeaveApplication(),
                  ),
                );
              },
              icon: const Icon(Icons.description),
              label: const Text("Leave Application"),
            ),

            const SizedBox(height: 15),

            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const LeaveStatus(),
                  ),
                );
              },
              icon: const Icon(Icons.fact_check),
              label: const Text("Leave Status"),
            ),

          ],
        ),
      ),
    );
  }
}