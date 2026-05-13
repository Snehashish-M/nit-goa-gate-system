import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:nit_goa_gate_app/services/user_cache.dart';

import 'student_dashboard.dart';
import 'warden_dashboard.dart';
import 'vehicle_authority_dashboard.dart';
import 'profile_setup.dart';
import 'app_info_screen.dart';

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
        };

        if (existingRole.isEmpty) {
          userData["role"] = "student";
          userData["createdAt"] = Timestamp.now();
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
        } else if (role == "vehicle_authority") {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const VehicleAuthorityDashboard(),
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
            // Check if user has acknowledged the info screen
            bool infoAcknowledged = cachedData?["infoAcknowledged"] == true;

            if (!context.mounted) return;

            if (infoAcknowledged) {
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
                  builder: (context) => const AppInfoScreen(isFirstTime: true),
                ),
              );
            }
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
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: Column(
        children: [
          // ─── Top: Building image with rounded bottom ───
          Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(36),
                  bottomRight: Radius.circular(36),
                ),
                child: SizedBox(
                  height: screenHeight * 0.45,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        'assets/images/image.png',
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                      ),
                      // Subtle overlay just at edges
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.0, 0.15, 0.85, 1.0],
                            colors: [
                              const Color(0xFF0D1B2A).withOpacity(0.4),
                              Colors.transparent,
                              Colors.transparent,
                              const Color(0xFF0D1B2A).withOpacity(0.6),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Logo at the boundary
              Positioned(
                bottom: -45,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0D1B2A).withOpacity(0.5),
                          blurRadius: 20,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/images/logo.png',
                        width: 78,
                        height: 78,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // ─── Bottom: Navy blue section ───
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: Column(
                children: [
                  // Space for logo
                  const SizedBox(height: 55),

                  const Text(
                    "NIT Goa",
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Gate Management System",
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.white.withOpacity(0.55),
                      letterSpacing: 0.5,
                    ),
                  ),

                  const Spacer(),

                  // Welcome text
                  const Text(
                    "Welcome",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Sign in with your college email to continue",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withOpacity(0.45),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Google sign-in button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => signInWithGoogle(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0D1B2A),
                        elevation: 8,
                        shadowColor: Colors.black.withOpacity(0.3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset('assets/images/google_logo.png', height: 24, width: 24),
                          SizedBox(width: 10),
                          Text(
                            "Sign in with Google",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const Spacer(),

                  // Footer
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Text(
                      "National Institute of Technology, Goa",
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.3),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}