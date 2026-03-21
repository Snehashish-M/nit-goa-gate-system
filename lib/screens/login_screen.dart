import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:nit_goa_gate_app/services/user_cache.dart';

import 'student_dashboard.dart';
import 'warden_dashboard.dart';
import 'profile_setup.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  Future<void> signInWithGoogle(BuildContext context) async {
    try {
      User? user;

      if (kIsWeb) {
        // Web: Use signInWithPopup
        GoogleAuthProvider googleProvider = GoogleAuthProvider();
        googleProvider.setCustomParameters({
          "hd": "nitgoa.ac.in"
        });
        await FirebaseAuth.instance.signInWithPopup(googleProvider);
        user = FirebaseAuth.instance.currentUser;

        // Enforce domain check on web (hd param is only a hint)
        if (user != null && !(user.email ?? "").endsWith("@nitgoa.ac.in")) {
          await FirebaseAuth.instance.signOut();
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Please use your NIT Goa email (@nitgoa.ac.in)")),
          );
          return;
        }
      } else {
        // Mobile: Use GoogleSignIn
        final GoogleSignInAccount? googleUser = await GoogleSignIn(
          scopes: ['email', 'profile'],
        ).signIn();

        if (googleUser == null) {
          debugPrint("Google sign-in cancelled");
          return;
        }

        // Check if email is from NIT Goa domain
        if (!googleUser.email.endsWith("@nitgoa.ac.in")) {
          // Clear cached Google account so picker shows again next time
          await GoogleSignIn().signOut();
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Please use your NIT Goa email (@nitgoa.ac.in)")),
          );
          return;
        }

        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        await FirebaseAuth.instance.signInWithCredential(credential);
        user = FirebaseAuth.instance.currentUser;
      }

      if (user != null) {
        // Read existing user doc to check if role is already set
        var existingDoc = await FirebaseFirestore.instance
            .collection("users")
            .doc(user.uid)
            .get();

        String existingRole = "";
        if (existingDoc.exists && existingDoc.data() != null) {
          existingRole = existingDoc.data()!["role"] ?? "";
        }

        // Set user data; only set role to "student" if no role exists yet
        String email = user.email ?? "";
        String rollNumber = email.contains("@") ? email.split("@")[0] : "";

        String displayName = user.displayName ?? "";
        String name = displayName;
        if (displayName.contains("_")) {
          name = displayName.substring(displayName.indexOf("_") + 1).trim();
        }

        Map<String, dynamic> userData = {
          "name": name,
          "email": email,
          "rollNumber": rollNumber,
          "createdAt": Timestamp.now(),
        };

        if (existingRole.isEmpty) {
          userData["role"] = "student";
        }

        await FirebaseFirestore.instance
            .collection("users")
            .doc(user.uid)
            .set(userData, SetOptions(merge: true));

        // Cache the profile right after login (avoids re-reading in other screens)
        await UserCache().loadProfile(forceRefresh: true);

        // Determine role from Firestore (use existing role, or default "student")
        String role = existingRole.isNotEmpty ? existingRole : "student";

        if (!context.mounted) return;

        if (role == "warden") {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const WardenDashboard(),
            ),
          );
        } else {
          // Check if student profile is complete using cached data
          var cachedData = UserCache().profileData;
          bool isProfileComplete = false;

          if (cachedData != null) {
            bool hasRollNumber = cachedData["rollNumber"] != null &&
                (cachedData["rollNumber"] as String).isNotEmpty;
            bool hasDegree = cachedData["degree"] != null &&
                (cachedData["degree"] as String).isNotEmpty;
            bool hasHostel = cachedData["hostel"] != null &&
                (cachedData["hostel"] as String).isNotEmpty;
            bool isDayScholar = cachedData["hostel"] == "Day Scholar";
            bool hasRoomNumber = isDayScholar || (cachedData["roomNumber"] != null &&
                (cachedData["roomNumber"] as String).isNotEmpty);
            bool hasPhone = cachedData["phone"] != null &&
                (cachedData["phone"] as String).isNotEmpty;

            isProfileComplete = hasRollNumber && hasDegree && hasHostel &&
                hasRoomNumber && hasPhone;
          }

          if (!context.mounted) return;

          if (isProfileComplete) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const StudentDashboard(),
              ),
            );
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const ProfileSetup(isFirstTime: true),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint("Login error: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Login failed: ${e.toString()}")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [

            const Icon(Icons.security, size: 64, color: Colors.blueGrey),

            const SizedBox(height: 20),

            const Text(
              "NIT Goa Gate System",
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 40),

            ElevatedButton.icon(
              onPressed: () => signInWithGoogle(context),
              icon: const Icon(Icons.login),
              label: const Text("Sign in with Google"),
            ),
          ],
        ),
      ),
    );
  }
}